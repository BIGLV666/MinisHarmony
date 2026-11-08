import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatMessage,
  SessionMeta,
  StoredSession,
  cloneSettings,
  textOf
} from '../core/Types';
import { SubagentHandler, ToolResult } from '../core/ToolTypes';
import { AgentRuntime } from './AgentRuntime';
import { LocalToolRuntime } from './LocalToolRuntime';

/** OpenMinis runs at most three subagents at once. */
export const MAX_PARALLEL_SUBAGENTS: number = 3;
/** Prevent a subagent from spawning subagents forever. */
export const MAX_SUBAGENT_DEPTH: number = 2;
export const SUBAGENT_TIMEOUT_MS: number = 10 * 60 * 1000;

function finalAnswer(messages: ChatMessage[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'assistant') {
      const text: string = textOf(messages[i]).trim();
      if (text.length > 0) {
        return text;
      }
    }
  }
  return '';
}

/**
 * Runs a focused task in an isolated, in-memory conversation.
 *
 * The child gets the same provider settings and tools as the parent, but its
 * own transcript, so it cannot see or disturb the main chat. Only the final
 * assistant text is returned to the calling tool. Memory is disabled for
 * children: the main agent already injects it, and a child writing to the
 * daily memory would create surprising cross-task entries.
 */
export class SubagentRunner implements SubagentHandler {
  private settings: AppSettings;
  private workspaceRoot: string;
  private allowWrite: boolean;
  private depth: number;

  private static active: number = 0;

  constructor(
    settings: AppSettings,
    workspaceRoot: string,
    allowWrite: boolean,
    depth: number = 0
  ) {
    this.settings = settings;
    this.workspaceRoot = workspaceRoot;
    this.allowWrite = allowWrite;
    this.depth = depth;
  }

  async run(prompt: string, label: string): Promise<ToolResult> {
    if (prompt.trim().length === 0) {
      return { ok: false, content: '子代理任务说明不能为空。' };
    }
    if (this.depth >= MAX_SUBAGENT_DEPTH) {
      return { ok: false, content: '子代理嵌套层级已达上限，请把任务拆给主对话。' };
    }
    if (SubagentRunner.active >= MAX_PARALLEL_SUBAGENTS) {
      return {
        ok: false,
        content: '已有 ' + MAX_PARALLEL_SUBAGENTS.toString() +
          ' 个子代理在运行，请等它们完成后再试。'
      };
    }
    SubagentRunner.active++;
    try {
      return await this.execute(prompt, label);
    } finally {
      SubagentRunner.active--;
    }
  }

  private execute(prompt: string, label: string): Promise<ToolResult> {
    const childSettings: AppSettings = cloneSettings(this.settings);
    childSettings.memoryEnabled = false;
    const basePrompt: string = childSettings.systemPrompt.trim();
    childSettings.systemPrompt = (basePrompt.length > 0 ? basePrompt + '\n\n' : '') +
      '你是一个独立的子代理。专注完成用户交代的任务，' +
      '完成后用简洁的最终结论回答；不要询问用户，也不要等待确认。';

    const nextDepth: number = this.depth + 1;
    const nextRunner: SubagentRunner | null = nextDepth < MAX_SUBAGENT_DEPTH
      ? new SubagentRunner(childSettings, this.workspaceRoot, this.allowWrite, nextDepth)
      : null;
    const tools: LocalToolRuntime = new LocalToolRuntime(
      this.workspaceRoot,
      this.allowWrite,
      false,
      childSettings.imageToolsEnabled,
      nextRunner
    );

    const title: string = label.length > 0 ? label : '子代理';
    const meta: SessionMeta = {
      id: util.generateRandomUUID(true),
      title: title,
      updatedAt: Date.now(),
      modelId: childSettings.modelId,
      messageCount: 0,
      pinned: false,
      archived: false
    };
    const session: StoredSession = { meta: meta, messages: [] };

    return new Promise<ToolResult>((resolve: (result: ToolResult) => void) => {
      let settled: boolean = false;
      let timer: number = -1;

      const finish = (result: ToolResult): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timer !== -1) {
          clearTimeout(timer);
          timer = -1;
        }
        resolve(result);
      };

      const agent: AgentRuntime = new AgentRuntime(
        childSettings,
        tools,
        session,
        {
          onUpdate: (messages: ChatMessage[], running: boolean) => {
            if (running) {
              return;
            }
            const text: string = finalAnswer(messages);
            finish(text.length > 0
              ? { ok: true, content: text }
              : { ok: false, content: '子代理没有返回最终文本。' });
          },
          onError: (message: string) => {
            finish({ ok: false, content: '子代理失败：' + message });
          }
        }
      );

      timer = setTimeout(() => {
        agent.cancel();
        finish({
          ok: false,
          content: '子代理超时（' + (SUBAGENT_TIMEOUT_MS / 60000).toString() + ' 分钟）。'
        });
      }, SUBAGENT_TIMEOUT_MS);

      agent.start(prompt);
    });
  }
}
