import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatMessage,
  MessagePart,
  PART_TOOL_CALL,
  StoredSession,
  TOOL_DONE,
  TOOL_ERROR,
  TOOL_PENDING,
  TOOL_RUNNING,
  appendReasoning,
  appendText,
  newChatMessage,
  textOf,
  toolCallPart
} from '../core/Types';
import { TokenUsage, ToolCallDelta } from '../core/SseParser';
import { ToolResult, ToolRuntime } from '../core/ToolTypes';
import { BudgetResult, fitHistoryToBudget } from '../core/ContextBudget';
import { repairToolArguments } from '../core/ToolArgs';
import {
  TOOL_LOOP_THRESHOLD,
  ToolLoopGuard,
  toolLoopWarning
} from '../core/ToolLoop';
import { truncateText } from '../core/Workspace';
import { AttachmentStore } from './AttachmentStore';
import {
  EVENT_AGENT_FINISH,
  EVENT_AGENT_START,
  EVENT_CANCELLED,
  EVENT_MODEL_DONE,
  EVENT_MODEL_ERROR,
  EVENT_MODEL_START,
  EVENT_TOOL_DONE,
  EVENT_TOOL_START,
  EVENT_TURN_CAP,
  LOG_ERROR,
  LOG_INFO,
  LOG_WARN,
  LogEvent,
  newLogEvent,
  sessionTag
} from '../core/EventLog';
import { clampMaxTurns } from '../core/Types';
import { AppLogger } from './AppLogger';
import { MemoryStore } from './MemoryStore';
import { ChatStreamHandle, startChatStream } from './ChatApi';

const MAX_TOOL_RESULT: number = 20000;
const FLUSH_MS: number = 50;

export interface AgentCallbacks {
  /** New snapshot after any visible change. `running` drives the stop button. */
  onUpdate: (messages: ChatMessage[], running: boolean) => void;
  onError: (message: string) => void;
}

/**
 * Asked immediately before a write tool runs when the user enabled
 * confirmation. Resolve `false` to skip the call; the part becomes an error
 * the model can see and react to.
 */
export type ToolConfirmHandler = (name: string, argumentsText: string) => Promise<boolean>;

interface ToolAccumulator {
  id: string;
  name: string;
  argumentsText: string;
}

/**
 * One user turn, including every model/tool round trip it triggers.
 *
 * The runtime owns only the transcript mutation and the loop. Network I/O is
 * in ChatApi, tool execution is behind ToolRuntime, and the UI receives
 * immutable snapshots through AgentCallbacks.
 */
export class AgentRuntime {
  private settings: AppSettings;
  private tools: ToolRuntime;
  private session: StoredSession;
  private callbacks: AgentCallbacks;
  private confirmTool: ToolConfirmHandler | null;

  private handle: ChatStreamHandle | null = null;
  private lastAssistant: ChatMessage | null = null;
  private accumulators: Map<number, ToolAccumulator> = new Map<number, ToolAccumulator>();
  private flushTimer: number = -1;
  private step: number = 0;
  private maxTurns: number = 200;
  private running: boolean = false;
  private finished: boolean = false;
  private cancelled: boolean = false;
  private agentStartedAt: number = 0;
  private requestStartedAt: number = 0;
  private toolCount: number = 0;
  private requestId: string = '';
  private loopGuard: ToolLoopGuard = new ToolLoopGuard();
  /** Steer / background input, read at the next model request boundary. */
  private pendingInputs: string[] = [];
  private currentTool: string = '';

  constructor(
    settings: AppSettings,
    tools: ToolRuntime,
    session: StoredSession,
    callbacks: AgentCallbacks,
    confirmTool: ToolConfirmHandler | null = null
  ) {
    this.settings = settings;
    this.tools = tools;
    this.session = session;
    this.callbacks = callbacks;
    this.confirmTool = confirmTool;
    this.maxTurns = clampMaxTurns(settings.maxAgentTurns);
  }

  isRunning(): boolean {
    return this.running;
  }

  /** Tool currently executing in this run, for subagent status reports. */
  currentToolName(): string {
    return this.currentTool;
  }

  /**
   * Steer a run without interrupting it: the text is queued and appended as a
   * user message immediately before the next model request, so a running tool
   * call is never cut off. If the turn was about to end, `finish` keeps the
   * loop alive to read it instead of settling.
   */
  injectInput(text: string): void {
    const trimmed: string = text.trim();
    if (trimmed.length === 0 || this.finished) {
      return;
    }
    this.pendingInputs.push(trimmed);
  }

  /** Pending steer / background texts not yet handed to the model. */
  pendingInputCount(): number {
    return this.pendingInputs.length;
  }

  start(userText: string, attachments: MessagePart[] = []): void {
    if (this.running) {
      return;
    }
    const message: ChatMessage = newChatMessage(
      util.generateRandomUUID(true), 'user', userText);
    for (let i = 0; i < attachments.length; i++) {
      message.parts.push(attachments[i]);
    }
    this.session.messages.push(message);
    this.beginRun('new');
  }

  /**
   * Re-run the current turn without appending a user message. The caller has
   * already trimmed the transcript back to the user turn, which is how
   * "regenerate" and "edit and resend" share the same loop.
   */
  regenerate(): void {
    if (this.running) {
      return;
    }
    this.beginRun('resume');
  }

  private beginRun(kind: string): void {
    this.running = true;
    this.agentStartedAt = Date.now();
    this.beginAssistant();
    this.log(
      EVENT_AGENT_START, LOG_INFO, 0, '', true, 0,
      'kind=' + kind +
        ' maxTurns=' + this.maxTurns.toString() +
        ' tools=' + (this.settings.toolsEnabled ? 'on' : 'off')
    );
    this.emit();
    this.runStep();
  }

  cancel(): void {
    if (!this.running || this.finished) {
      return;
    }
    this.cancelled = true;
    this.log(EVENT_CANCELLED, LOG_WARN, this.step, '', false, 0, '用户停止生成');
    if (this.handle !== null) {
      this.handle.cancel();
      this.handle = null;
    }
    if (this.lastAssistant !== null) {
      this.interruptToolCalls(this.lastAssistant);
      if (this.lastAssistant.parts.length === 0) {
        appendText(this.lastAssistant, '（已停止生成）');
      }
    }
    this.finish();
  }

  /** A stopped turn must not leave cards spinning forever or a request waiting for a result. */
  private interruptToolCalls(message: ChatMessage): void {
    for (let i = 0; i < message.parts.length; i++) {
      const part: MessagePart = message.parts[i];
      if (part.kind === PART_TOOL_CALL &&
        (part.status === TOOL_PENDING || part.status === TOOL_RUNNING)) {
        part.status = TOOL_ERROR;
        part.isError = true;
        if (part.resultText.length === 0) {
          part.resultText = '生成已停止，工具未执行。';
        }
      }
    }
  }

  private beginAssistant(): ChatMessage {
    const message: ChatMessage = newChatMessage(
      util.generateRandomUUID(true), 'assistant', ''
    );
    message.streaming = true;
    this.session.messages.push(message);
    this.lastAssistant = message;
    return message;
  }

  /**
   * Turn queued input into user messages just before the pending assistant
   * placeholder. Tool results travel with their assistant message, so a user
   * message at this point is valid for every supported protocol.
   */
  private drainPendingInputs(): void {
    if (this.pendingInputs.length === 0) {
      return;
    }
    const at: number = Math.max(0, this.session.messages.length - 1);
    for (let i = 0; i < this.pendingInputs.length; i++) {
      const message: ChatMessage = newChatMessage(
        util.generateRandomUUID(true), 'user', this.pendingInputs[i]);
      this.session.messages.splice(at + i, 0, message);
    }
    this.pendingInputs = [];
    this.emit();
  }

  private runStep(): void {
    if (this.cancelled || !this.running) {
      this.finish();
      return;
    }
    this.requestId = '';
    if (this.step >= this.maxTurns) {
      if (this.lastAssistant !== null) {
        appendText(
          this.lastAssistant,
          '\n\n> 已达到 ' + this.maxTurns.toString() +
            ' 轮工具调用上限。已完成的上下文与工具结果都保留在本对话中，继续发送消息即可接着执行。'
        );
      }
      this.log(
        EVENT_TURN_CAP, LOG_WARN, this.step, '', false, 0,
        'limit=' + this.maxTurns.toString()
      );
      this.finish();
      return;
    }
    this.step++;

    const assistant: ChatMessage | null = this.lastAssistant;
    if (assistant === null) {
      this.callbacks.onError('内部错误：缺少 assistant 占位消息');
      this.finish();
      return;
    }

    // Steer / background input is inserted before this step's assistant
    // placeholder, so it lands after the previous tool results and is part of
    // the request that is about to be built.
    this.drainPendingInputs();
    this.currentTool = '';

    const history: ChatMessage[] = this.session.messages.slice(
      0, this.session.messages.length - 1
    );
    // Shrink old tool results for this request only. The stored transcript and
    // the UI keep the full output; the model sees a budgeted view.
    const budgeted: BudgetResult = fitHistoryToBudget(
      history, this.settings.contextBudgetChars
    );
    this.accumulators.clear();
    const definitions = this.settings.toolsEnabled ? this.tools.definitions() : [];
    const memoryContext: string = this.settings.memoryEnabled
      ? MemoryStore.context()
      : '';
    this.requestStartedAt = Date.now();
    // Correlates the start/done/error lines of this one HTTP call; never
    // derived from content and safe to show in the log viewer.
    this.requestId = util.generateRandomUUID(true).substring(0, 8);
    this.log(
      EVENT_MODEL_START, LOG_INFO, this.step, '', true, 0,
      'messages=' + history.length.toString() +
        ' tools=' + definitions.length.toString() +
        ' trimmed=' + budgeted.trimmedParts.toString()
    );

    const handle: ChatStreamHandle = startChatStream(
      this.settings,
      this.session.meta.id,
      budgeted.messages,
      definitions,
      memoryContext,
      {
        onDelta: (content: string, reasoning: string, toolCalls: ToolCallDelta[]) => {
          this.onDelta(assistant, content, reasoning, toolCalls);
        },
        onUsage: (usage: TokenUsage) => {
          if (!this.running || this.cancelled) {
            return;
          }
          assistant.promptTokens = usage.promptTokens;
          assistant.completionTokens = usage.completionTokens;
          assistant.totalTokens = usage.totalTokens;
          this.emit();
        },
        onDone: (finishReason: string) => {
          this.onDone(assistant, finishReason);
        },
        onError: (message: string) => {
          this.onModelError(assistant, message);
        }
      },
      (uri: string, mimeType: string) => AttachmentStore.isAttachmentUri(uri)
        ? AttachmentStore.dataUrl(uri, mimeType)
        : this.tools.imageDataUrl(uri, mimeType)
    );
    this.handle = handle;
    if (!this.running || this.cancelled) {
      handle.cancel();
      this.handle = null;
    }
  }

  private onDelta(
    assistant: ChatMessage,
    content: string,
    reasoning: string,
    toolCalls: ToolCallDelta[]
  ): void {
    if (!this.running || this.cancelled) {
      return;
    }
    appendText(assistant, content);
    appendReasoning(assistant, reasoning);
    this.accumulate(toolCalls);
    this.scheduleFlush();
  }

  private onDone(assistant: ChatMessage, finishReason: string): void {
    if (!this.running || this.cancelled) {
      return;
    }
    this.handle = null;
    this.clearFlush();
    assistant.streaming = false;
    this.log(
      EVENT_MODEL_DONE, LOG_INFO, this.step, '', true,
      Date.now() - this.requestStartedAt,
      'finish=' + finishReason +
        ' chars=' + textOf(assistant).length.toString() +
        ' calls=' + this.accumulators.size.toString()
    );

    if (finishReason === 'length') {
      const prefix: string = textOf(assistant).length > 0 ? '\n\n' : '';
      appendText(assistant, prefix + '> 已达到最大输出长度，内容可能被截断。');
    }

    const calls: MessagePart[] = this.settings.toolsEnabled
      ? this.collectToolCalls()
      : [];
    if (calls.length === 0) {
      if (this.settings.toolsEnabled) {
        if (textOf(assistant).length === 0) {
          appendText(assistant, '（模型没有返回内容）');
        }
      } else if (this.accumulators.size > 0) {
        appendText(assistant, '（模型请求了工具，但工具调用已在设置中关闭）');
      } else if (textOf(assistant).length === 0) {
        appendText(assistant, '（模型没有返回内容）');
      }
      // A steer that arrived while this turn was streaming keeps the loop
      // alive instead of being reported as missed.
      this.finish(true);
      return;
    }

    for (let i = 0; i < calls.length; i++) {
      assistant.parts.push(calls[i]);
    }
    this.emit();
    this.executeTool(calls);
  }

  private onModelError(assistant: ChatMessage, message: string): void {
    if (!this.running || this.cancelled) {
      return;
    }
    this.handle = null;
    this.clearFlush();
    assistant.streaming = false;
    this.log(
      EVENT_MODEL_ERROR, LOG_ERROR, this.step, '', false,
      Date.now() - this.requestStartedAt,
      message
    );
    if (textOf(assistant).length > 0) {
      appendText(assistant, '\n\n');
    }
    appendText(assistant, '> ⚠️ ' + message);
    assistant.error = true;
    this.callbacks.onError(message);
    this.finish();
  }

  /**
   * Run every tool call of this round concurrently. OpenMinis issues parallel
   * tool calls too; results stay attached to their own part so order in the
   * transcript is unchanged, and the next model turn waits for all of them.
   */
  private executeTool(calls: MessagePart[]): void {
    if (!this.running || this.cancelled) {
      this.finish();
      return;
    }
    if (calls.length === 0) {
      this.beginAssistant();
      this.emit();
      this.runStep();
      return;
    }

    const jobs: Promise<void>[] = [];
    for (let i = 0; i < calls.length; i++) {
      const call: MessagePart = calls[i];
      call.status = TOOL_RUNNING;
      this.currentTool = call.toolName;
      const toolStartedAt: number = Date.now();
      this.log(EVENT_TOOL_START, LOG_INFO, this.step, call.toolName, true, 0, '');
      const repaired = repairToolArguments(call.argumentsText);
      const args: string = repaired.text.length > 0 ? repaired.text : '{}';
      if (repaired.changed) {
        // Persist the repaired form so retry/regenerate sends valid JSON too.
        call.argumentsText = args;
      }
      const repeat: number = this.loopGuard.observe(call.toolName, args);
      const job: Promise<void> = this.runTool(call, args, repeat, toolStartedAt);
      jobs.push(job);
    }
    this.emit();

    Promise.all(jobs).then(() => {
      if (!this.running || this.cancelled) {
        this.finish();
        return;
      }
      this.beginAssistant();
      this.emit();
      this.runStep();
    }).catch((error: Error) => {
      if (!this.running || this.cancelled) {
        this.finish();
        return;
      }
      this.callbacks.onError('工具调度失败：' + error.message);
      this.finish();
    });
  }

  /**
   * One tool call, including the optional user confirmation. Confirmation is
   * requested only for writes and only when the caller supplied a handler, so
   * subagents (which run without UI) are never blocked.
   */
  private async runTool(
    call: MessagePart,
    args: string,
    repeat: number,
    toolStartedAt: number
  ): Promise<void> {
    const needsConfirm: boolean = this.confirmTool !== null &&
      (call.toolName === 'write_file' || call.toolName === 'file_edit');
    if (needsConfirm) {
      const handler: ToolConfirmHandler | null = this.confirmTool;
      let allowed: boolean = false;
      if (handler !== null) {
        allowed = await handler(call.toolName, args);
      }
      if (!this.running || this.cancelled) {
        return;
      }
      if (!allowed) {
        call.resultText = '用户拒绝了这次工具调用：' + call.toolName;
        call.status = TOOL_ERROR;
        call.isError = true;
        this.toolCount++;
        this.log(
          EVENT_TOOL_DONE, LOG_WARN, this.step, call.toolName, false,
          Date.now() - toolStartedAt, 'denied by user'
        );
        this.emit();
        return;
      }
    }
    try {
      const result: ToolResult = await this.tools.execute(call.toolName, args);
      if (!this.running || this.cancelled) {
        return;
      }
      let content: string = result.content;
      if (repeat >= TOOL_LOOP_THRESHOLD) {
        content = toolLoopWarning(call.toolName, repeat) + '\n\n' + content;
      }
      call.resultText = truncateText(content, MAX_TOOL_RESULT);
      call.status = result.ok ? TOOL_DONE : TOOL_ERROR;
      call.isError = !result.ok;
      if (result.imageUri !== undefined && result.imageUri.length > 0) {
        call.uri = result.imageUri;
        call.mimeType = result.imageMimeType !== undefined
          ? result.imageMimeType
          : '';
      }
      this.toolCount++;
      this.log(
        EVENT_TOOL_DONE, result.ok ? LOG_INFO : LOG_WARN, this.step,
        call.toolName, result.ok, Date.now() - toolStartedAt,
        'resultChars=' + call.resultText.length.toString() +
          (repeat >= TOOL_LOOP_THRESHOLD ? ' loop=' + repeat.toString() : '')
      );
      this.emit();
    } catch (e) {
      if (!this.running || this.cancelled) {
        return;
      }
      const error: Error = e as Error;
      call.resultText = '工具执行异常：' + error.message;
      call.status = TOOL_ERROR;
      call.isError = true;
      this.toolCount++;
      this.log(
        EVENT_TOOL_DONE, LOG_ERROR, this.step, call.toolName, false,
        Date.now() - toolStartedAt, error.message
      );
      this.emit();
    }
  }

  private accumulate(deltas: ToolCallDelta[]): void {
    for (let i = 0; i < deltas.length; i++) {
      const delta: ToolCallDelta = deltas[i];
      let acc: ToolAccumulator | undefined = this.accumulators.get(delta.index);
      if (acc === undefined) {
        acc = { id: '', name: '', argumentsText: '' };
        this.accumulators.set(delta.index, acc);
      }
      if (delta.id.length > 0) {
        acc.id = delta.id;
      }
      if (delta.name.length > 0) {
        acc.name += delta.name;
      }
      if (delta.arguments.length > 0) {
        acc.argumentsText += delta.arguments;
      }
    }
  }

  private collectToolCalls(): MessagePart[] {
    const indexes: number[] = [];
    this.accumulators.forEach((value: ToolAccumulator, key: number) => {
      indexes.push(key);
    });
    indexes.sort((a: number, b: number): number => a - b);

    const parts: MessagePart[] = [];
    for (let i = 0; i < indexes.length; i++) {
      const acc: ToolAccumulator | undefined = this.accumulators.get(indexes[i]);
      if (acc === undefined || acc.name.length === 0) {
        continue;
      }
      const id: string = acc.id.length > 0
        ? acc.id
        : 'call_' + indexes[i].toString() + '_' + Date.now().toString();
      parts.push(toolCallPart(id, acc.name, acc.argumentsText));
    }
    return parts;
  }

  private scheduleFlush(): void {
    if (this.flushTimer !== -1) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1;
      if (this.running) {
        this.emit();
      }
    }, FLUSH_MS);
  }

  private clearFlush(): void {
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
  }

  private log(
    event: string,
    level: string,
    step: number,
    tool: string,
    ok: boolean,
    durationMs: number,
    detail: string
  ): void {
    if (!this.settings.loggingEnabled) {
      return;
    }
    const record: LogEvent = newLogEvent(event, level);
    record.session = sessionTag(this.session.meta.id);
    record.model = this.settings.modelId;
    record.step = step;
    record.tool = tool;
    record.ok = ok;
    record.durationMs = durationMs;
    record.detail = detail;
    record.req = this.requestId;
    AppLogger.log(record);
  }

  private emit(): void {
    this.session.meta.updatedAt = Date.now();
    this.session.meta.messageCount = this.session.messages.length;
    this.callbacks.onUpdate(this.session.messages.slice(), this.running);
  }

  /**
   * `continueForSteer` is set only when a model turn ended normally. A steer
   * that arrived too late to be part of that turn restarts the loop instead of
   * being dropped; cancellation, errors and the turn cap always settle.
   */
  private finish(continueForSteer: boolean = false): void {
    if (this.finished) {
      return;
    }
    if (continueForSteer && !this.cancelled && this.pendingInputs.length > 0 &&
      this.step < this.maxTurns) {
      this.beginAssistant();
      this.emit();
      this.runStep();
      return;
    }
    this.finished = true;
    this.running = false;
    this.currentTool = '';
    this.clearFlush();
    if (this.lastAssistant !== null) {
      this.lastAssistant.streaming = false;
    }
    this.handle = null;
    this.log(
      EVENT_AGENT_FINISH, this.cancelled ? LOG_WARN : LOG_INFO, this.step,
      '', !this.cancelled, Date.now() - this.agentStartedAt,
      'steps=' + this.step.toString() + ' tools=' + this.toolCount.toString()
    );
    this.session.meta.updatedAt = Date.now();
    this.session.meta.messageCount = this.session.messages.length;
    this.callbacks.onUpdate(this.session.messages.slice(), false);
  }
}
