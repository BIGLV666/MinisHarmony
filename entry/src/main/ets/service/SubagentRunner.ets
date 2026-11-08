import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatMessage,
  SessionMeta,
  StoredSession,
  cloneSettings,
  textOf
} from '../core/Types';
import { ShellHandler, SubagentHandler, SubagentRequest, ToolResult } from '../core/ToolTypes';
import {
  BACKGROUND_PREFIX,
  SubagentJobRecord,
  SubagentState,
  backgroundMessage,
  endJob,
  isActiveState,
  isTerminalState,
  matchJobs,
  newJobRecord,
  parseProgressLevel,
  progressInterval,
  progressMessage,
  progressSignature,
  pruneJobs,
  stateLabel,
  statusReport
} from '../core/SubagentJob';
import {
  BUILTIN_AGENT_NAME,
  SubAgentDefinition,
  agentNameList,
  childBrief,
  childSessionTitle,
  resolveAgent
} from '../core/SubAgentRoster';
import { AgentRuntime } from './AgentRuntime';
import { LocalToolRuntime } from './LocalToolRuntime';
import { SettingsImageGen } from './ImageGen';
import { LocalStore } from './LocalStore';

/** OpenMinis runs at most three subagents at once; the rest wait in a queue. */
export const MAX_PARALLEL_SUBAGENTS: number = 3;
/** Prevent a subagent from spawning subagents forever. */
export const MAX_SUBAGENT_DEPTH: number = 2;
export const SUBAGENT_DEFAULT_MINUTES: number = 10;
export const SUBAGENT_MAX_MINUTES: number = 60;
/** Finished jobs kept for `action=status` in this process. */
const KEEP_FINISHED_JOBS: number = 20;

/** One live (or restored) job. Scheduling state lives in `record`. */
interface LiveJob {
  record: SubagentJobRecord;
  runtime: AgentRuntime | null;
  session: StoredSession | null;
  timer: number;
  /** Caller blocked in `wait=true`; resolved when the job settles. */
  resolve: ((result: ToolResult) => void) | null;
  /** Background jobs post their outcome; blocking ones return it inline. */
  wait: boolean;
  /** Whether this job ever took a running slot. */
  started: boolean;
  /** Wall-clock budget requested at delegation time. */
  minutes: number;
  cancelRequested: boolean;
  timedOut: boolean;
  errorText: string;
  /** Context used to restart an interrupted job; null after a relaunch. */
  settings: AppSettings | null;
  root: string;
  allowWrite: boolean;
  depth: number;
  onChild: ((session: StoredSession) => void) | null;
  deliver: ((parentSessionId: string, text: string) => void) | null;
  /** Shared shell handler; null in remote mode or after a restored job. */
  shell: ShellHandler | null;
  /** Mid-run reporter; -1 when `progress_report` is none. */
  progressTimer: number;
  progressLevel: string;
  progressLastSignature: string;
}

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

function shortId(): string {
  return util.generateRandomUUID(true).replace(/-/g, '').substring(0, 8);
}

function clampMinutes(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return SUBAGENT_DEFAULT_MINUTES;
  }
  if (value > SUBAGENT_MAX_MINUTES) {
    return SUBAGENT_MAX_MINUTES;
  }
  return Math.floor(value);
}

/**
 * The single `subagent_task` tool.
 *
 * `delegate` starts a child with its own transcript and tool loop. By default
 * it returns a job id at once and the outcome arrives later as a user message
 * prefixed `[后台任务结束`; `wait=true` (and every nested delegation) blocks
 * until the child settles. `status`, `steer`, `cancel` and `resume` operate on
 * the jobs of the calling conversation.
 */
export class SubagentRunner implements SubagentHandler {
  private settings: AppSettings;
  private root: string;
  private allowWrite: boolean;
  private parentSessionId: string;
  private depth: number;
  private onChild: ((session: StoredSession) => void) | null;
  private deliver: ((parentSessionId: string, text: string) => void) | null;
  private shell: ShellHandler | null;

  private static jobs: Map<string, LiveJob> = new Map<string, LiveJob>();
  private static active: number = 0;
  /**
   * Handler installed by the UI for jobs restored from disk, which cannot
   * remember the one captured at delegation time.
   */
  private static defaultShell: ShellHandler | null = null;
  /** Serializes preference writes so a slower earlier save cannot win. */
  private static saveChain: Promise<void> = Promise.resolve();

  constructor(
    settings: AppSettings,
    workspaceRoot: string,
    allowWrite: boolean,
    parentSessionId: string,
    depth: number = 0,
    onChild: ((session: StoredSession) => void) | null = null,
    deliver: ((parentSessionId: string, text: string) => void) | null = null,
    shell: ShellHandler | null = null
  ) {
    this.settings = settings;
    this.root = workspaceRoot;
    this.allowWrite = allowWrite;
    this.parentSessionId = parentSessionId;
    this.depth = depth;
    this.onChild = onChild;
    this.deliver = deliver;
    this.shell = shell;
  }

  static setShell(shell: ShellHandler | null): void {
    SubagentRunner.defaultShell = shell;
  }

  /**
   * Rebuild jobs left running when the process died. They have no transcript
   * to continue from, so they are reported as `interrupted` and `resume`
   * restarts them from the original brief.
   */
  static async restore(): Promise<void> {
    const records: SubagentJobRecord[] = await LocalStore.loadSubagentJobs();
    for (let i = 0; i < records.length; i++) {
      const record: SubagentJobRecord = records[i];
      if (SubagentRunner.jobs.has(record.id)) {
        continue;
      }
      record.state = 'interrupted';
      record.currentTool = '';
      record.steers = [];
      const job: LiveJob = {
        record: record,
        runtime: null,
        session: null,
        timer: -1,
        resolve: null,
        wait: false,
        started: false,
        minutes: SUBAGENT_DEFAULT_MINUTES,
        cancelRequested: false,
        timedOut: false,
        errorText: '',
        settings: null,
        root: '',
        allowWrite: false,
        depth: 0,
        onChild: null,
        deliver: null,
        shell: null,
        progressTimer: -1,
        progressLevel: 'none',
        progressLastSignature: ''
      };
      SubagentRunner.jobs.set(record.id, job);
    }
  }

  /** Cancel children the caller is synchronously waiting on. */
  static cancelBlocking(parentSessionId: string): void {
    const ids: string[] = [];
    SubagentRunner.jobs.forEach((job: LiveJob, id: string) => {
      if (job.record.parentSessionId === parentSessionId && job.wait &&
        isActiveState(job.record.state) && job.runtime !== null) {
        ids.push(id);
      }
    });
    for (let i = 0; i < ids.length; i++) {
      const job: LiveJob | undefined = SubagentRunner.jobs.get(ids[i]);
      if (job === undefined) {
        continue;
      }
      job.cancelRequested = true;
      if (job.runtime !== null) {
        job.runtime.cancel();
      }
      SubagentRunner.cancelBlocking(job.record.childSessionId);
    }
  }

  async execute(request: SubagentRequest): Promise<ToolResult> {
    const action: string = request.action.trim().length > 0
      ? request.action.trim().toLowerCase()
      : 'delegate';
    if (action === 'delegate') {
      return this.delegate(request);
    }
    if (action === 'status') {
      return this.status(request.jobId);
    }
    if (action === 'steer') {
      return this.steer(request.jobId, request.message);
    }
    if (action === 'cancel') {
      return this.cancel(request.jobId);
    }
    if (action === 'resume') {
      return this.resume(request.jobId);
    }
    return {
      ok: false,
      content: '未知 action：' + action + '。可用 delegate / status / steer / cancel / resume。'
    };
  }

  private async delegate(request: SubagentRequest): Promise<ToolResult> {
    const prompt: string = request.prompt.trim();
    if (prompt.length === 0) {
      return { ok: false, content: 'action=delegate 需要非空的 prompt。' };
    }
    if (this.depth >= MAX_SUBAGENT_DEPTH) {
      return { ok: false, content: '子代理嵌套层级已达上限，请把任务拆给主对话。' };
    }
    const agent: SubAgentDefinition | null =
      resolveAgent(this.settings.subAgents, request.agent);
    if (agent === null) {
      return {
        ok: false,
        content: '未知子代理「' + request.agent.trim() + '」。可选：' +
          agentNameList(this.settings.subAgents)
      };
    }

    const childSettings: AppSettings = cloneSettings(this.settings);
    childSettings.memoryEnabled = false;
    const basePrompt: string = childSettings.systemPrompt.trim();
    childSettings.systemPrompt = (basePrompt.length > 0 ? basePrompt + '\n\n' : '') +
      childBrief(agent);

    const label: string = request.label.trim();
    const displayLabel: string = agent.name === BUILTIN_AGENT_NAME
      ? label
      : (label.length > 0 ? agent.name + ' · ' + label : agent.name);
    const id: string = shortId();
    const childSessionId: string = util.generateRandomUUID(true);
    const title: string = childSessionTitle(label, agent.name);
    const meta: SessionMeta = {
      id: childSessionId,
      title: title,
      updatedAt: Date.now(),
      modelId: childSettings.modelId,
      messageCount: 0,
      pinned: false,
      archived: false
    };
    const session: StoredSession = { meta: meta, messages: [] };
    const record: SubagentJobRecord = newJobRecord(
      id, this.parentSessionId, childSessionId, displayLabel, prompt,
      childSettings.modelId, Date.now());
    record.agent = agent.name;
    const wait: boolean = request.wait || this.depth > 0;
    const minutes: number = clampMinutes(request.maxMinutes);
    // Blocking callers get the result inline, so reports would only be noise.
    const progressLevel: string = wait ? 'none' : parseProgressLevel(request.progressReport);
    const shell: ShellHandler | null = this.shell !== null
      ? this.shell
      : SubagentRunner.defaultShell;
    const job: LiveJob = {
      record: record,
      runtime: null,
      session: session,
      timer: -1,
      resolve: null,
      wait: wait,
      started: false,
      minutes: minutes,
      cancelRequested: false,
      timedOut: false,
      errorText: '',
      settings: childSettings,
      root: this.root,
      allowWrite: this.allowWrite,
      depth: this.depth + 1,
      onChild: this.onChild,
      deliver: this.deliver,
      shell: shell,
      progressTimer: -1,
      progressLevel: progressLevel,
      progressLastSignature: ''
    };
    SubagentRunner.jobs.set(id, job);
    SubagentRunner.saveActive();

    if (wait) {
      return new Promise<ToolResult>((resolve: (result: ToolResult) => void) => {
        // The resolver exists before the first request goes out, so even an
        // immediate failure settles the blocked tool call.
        job.resolve = resolve;
        if (SubagentRunner.active < MAX_PARALLEL_SUBAGENTS) {
          SubagentRunner.startJob(job);
        }
      });
    }
    if (SubagentRunner.active < MAX_PARALLEL_SUBAGENTS) {
      SubagentRunner.startJob(job);
    }
    const state: string = job.record.state === 'running' ? 'running' : 'queued';
    return {
      ok: true,
      content: '已启动子代理「' + title + '」\njob_id=' + id +
        '\nstatus=' + state +
        '\n结果稍后以「' + BACKGROUND_PREFIX + ' …」消息送达；无需轮询，也不要重复委派同一任务。'
    };
  }

  /** The child's latest non-empty assistant text, for progress reports. */
  private static lastAssistantText(job: LiveJob): string {
    const session: StoredSession | null = job.session;
    if (session === null) {
      return '';
    }
    for (let i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].role !== 'assistant') {
        continue;
      }
      const text: string = textOf(session.messages[i]).trim();
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  /** Completed assistant turns, the same count OpenMinis reports. */
  private static assistantTurns(job: LiveJob): number {
    const session: StoredSession | null = job.session;
    if (session === null) {
      return 0;
    }
    let turns: number = 0;
    for (let i = 0; i < session.messages.length; i++) {
      if (session.messages[i].role === 'assistant') {
        turns++;
      }
    }
    return turns;
  }

  /**
   * `progress_report`: post a `[后台任务进度 …]` user message into the parent
   * conversation while the child runs. "frequent" only reports when the tool,
   * turn count or latest text changed; "moderate" reports every minute.
   */
  private static startProgress(job: LiveJob): void {
    const interval: number = progressInterval(job.progressLevel);
    const deliver: ((parentSessionId: string, text: string) => void) | null =
      job.deliver;
    if (interval <= 0 || deliver === null || job.record.state !== 'running') {
      return;
    }
    job.progressTimer = setInterval(() => {
      if (job.record.state !== 'running' || job.runtime === null) {
        return;
      }
      const tool: string = job.runtime.currentToolName();
      const turns: number = SubagentRunner.assistantTurns(job);
      const lastMessage: string = SubagentRunner.lastAssistantText(job);
      const signature: string = progressSignature(tool, turns, lastMessage);
      if (job.progressLevel === 'frequent' &&
        signature === job.progressLastSignature) {
        return;
      }
      job.progressLastSignature = signature;
      const text: string = progressMessage(job.record, tool,
        Date.now() - job.record.startedAt, turns, lastMessage);
      try {
        deliver(job.record.parentSessionId, text);
      } catch (e) {
        // A closed UI must not break the job.
      }
    }, interval);
  }

  private static clearProgress(job: LiveJob): void {
    if (job.progressTimer !== -1) {
      clearInterval(job.progressTimer);
      job.progressTimer = -1;
    }
  }

  private static startJob(job: LiveJob): void {
    const settings: AppSettings | null = job.settings;
    const session: StoredSession | null = job.session;
    if (settings === null || session === null) {
      return;
    }
    job.record.state = 'running';
    job.record.startedAt = Date.now();
    job.record.currentTool = '';
    job.started = true;
    SubagentRunner.active++;

    const record: SubagentJobRecord = job.record;
    const childId: string = record.childSessionId;
    const nextDepth: number = job.depth;
    const nextRunner: SubagentRunner | null = nextDepth < MAX_SUBAGENT_DEPTH
      ? new SubagentRunner(
        settings, job.root, job.allowWrite, childId, nextDepth,
        job.onChild, job.deliver, job.shell)
      : null;
    const tools: LocalToolRuntime = new LocalToolRuntime(
      job.root,
      job.allowWrite,
      false,
      settings.imageToolsEnabled,
      nextRunner,
      settings.disabledTools,
      settings.clipboardToolsEnabled,
      null,
      settings.imageGenEnabled ? new SettingsImageGen(settings) : null,
      null,
      job.shell !== null ? job.shell : SubagentRunner.defaultShell
    );

    const runtime: AgentRuntime = new AgentRuntime(
      settings,
      tools,
      session,
      {
        onUpdate: (messages: ChatMessage[], running: boolean) => {
          if (running) {
            return;
          }
          if (job.cancelRequested) {
            SubagentRunner.settleJob(job, 'cancelled', finalAnswer(messages));
          } else if (job.timedOut) {
            SubagentRunner.settleJob(job, 'timeout', finalAnswer(messages));
          } else if (job.errorText.length > 0) {
            SubagentRunner.settleJob(job, 'failed', job.errorText);
          } else {
            SubagentRunner.settleJob(job, 'done', finalAnswer(messages));
          }
        },
        onError: (message: string) => {
          job.errorText = message;
        }
      }
    );
    job.runtime = runtime;

    // Steers accepted while the job was queued are read before its first
    // request, which is exactly "at its next turn".
    const queuedSteers: string[] = record.steers;
    record.steers = [];
    for (let i = 0; i < queuedSteers.length; i++) {
      runtime.injectInput(queuedSteers[i]);
    }

    job.timer = setTimeout(() => {
      job.timedOut = true;
      runtime.cancel();
    }, job.minutes * 60 * 1000);

    runtime.start(record.prompt);
    SubagentRunner.startProgress(job);
  }

  private static clearTimer(job: LiveJob): void {
    if (job.timer !== -1) {
      clearTimeout(job.timer);
      job.timer = -1;
    }
  }

  private static settleJob(job: LiveJob, state: SubagentState, text: string): void {
    if (isTerminalState(job.record.state)) {
      return;
    }
    SubagentRunner.clearTimer(job);
    SubagentRunner.clearProgress(job);
    const record: SubagentJobRecord = job.record;
    const body: string = text.trim();
    endJob(record, state, body, Date.now());
    if (job.session !== null && job.onChild !== null && job.session.messages.length > 0) {
      job.session.meta.messageCount = job.session.messages.length;
      job.session.meta.updatedAt = Date.now();
      try {
        job.onChild(job.session);
      } catch (e) {
        // Storage failure must not swallow the result.
      }
    }
    if (job.wait && job.resolve !== null) {
      const resolve: (result: ToolResult) => void = job.resolve;
      job.resolve = null;
      resolve(SubagentRunner.toolResultFor(job));
    } else if (!job.wait && job.deliver !== null && job.started) {
      const message: string = backgroundMessage(record);
      try {
        job.deliver(record.parentSessionId, message);
      } catch (e) {
        // A closed UI must not break job bookkeeping.
      }
    }
    job.runtime = null;
    SubagentRunner.saveActive();
    SubagentRunner.prune();
    if (job.started) {
      job.started = false;
      SubagentRunner.active--;
      if (SubagentRunner.active < 0) {
        SubagentRunner.active = 0;
      }
    }
    SubagentRunner.pump();
  }

  private static toolResultFor(job: LiveJob): ToolResult {
    const record: SubagentJobRecord = job.record;
    const body: string = record.resultText.trim();
    if (record.state === 'done') {
      return body.length > 0
        ? { ok: true, content: body }
        : { ok: false, content: '子代理没有返回最终文本。' };
    }
    if (record.state === 'cancelled') {
      return {
        ok: false,
        content: '子代理已取消。' + (body.length > 0 ? '\n\n部分结果：\n' + body : '')
      };
    }
    if (record.state === 'timeout') {
      return {
        ok: false,
        content: '子代理超时。' + (body.length > 0 ? '\n\n部分结果：\n' + body : '')
      };
    }
    return { ok: false, content: '子代理失败：' + body };
  }

  /** Start the oldest queued job whenever a slot frees up. */
  private static pump(): void {
    const candidates: LiveJob[] = [];
    SubagentRunner.jobs.forEach((job: LiveJob) => {
      if (job.record.state === 'queued' && job.settings !== null) {
        candidates.push(job);
      }
    });
    candidates.sort((a: LiveJob, b: LiveJob): number =>
      a.record.startedAt - b.record.startedAt);
    for (let i = 0; i < candidates.length; i++) {
      if (SubagentRunner.active >= MAX_PARALLEL_SUBAGENTS) {
        break;
      }
      if (candidates[i].runtime !== null || candidates[i].started) {
        continue;
      }
      SubagentRunner.startJob(candidates[i]);
    }
  }

  private static saveActive(): void {
    const active: SubagentJobRecord[] = [];
    SubagentRunner.jobs.forEach((job: LiveJob) => {
      if (isActiveState(job.record.state)) {
        active.push(job.record);
      }
    });
    SubagentRunner.saveChain = SubagentRunner.saveChain
      .then((): Promise<void> => LocalStore.saveSubagentJobs(active))
      .catch((error: Error): void => {});
  }

  private static prune(): void {
    const parents: string[] = [];
    SubagentRunner.jobs.forEach((job: LiveJob) => {
      if (parents.indexOf(job.record.parentSessionId) < 0) {
        parents.push(job.record.parentSessionId);
      }
    });
    for (let i = 0; i < parents.length; i++) {
      const records: SubagentJobRecord[] = [];
      SubagentRunner.jobs.forEach((job: LiveJob) => {
        if (job.record.parentSessionId === parents[i]) {
          records.push(job.record);
        }
      });
      if (records.length <= KEEP_FINISHED_JOBS) {
        continue;
      }
      const kept: SubagentJobRecord[] = pruneJobs(records, KEEP_FINISHED_JOBS);
      for (let j = 0; j < records.length; j++) {
        if (kept.indexOf(records[j]) < 0) {
          SubagentRunner.jobs.delete(records[j].id);
        }
      }
    }
  }

  private jobsOfThisParent(): SubagentJobRecord[] {
    const records: SubagentJobRecord[] = [];
    SubagentRunner.jobs.forEach((job: LiveJob) => {
      if (job.runtime !== null) {
        job.record.currentTool = job.runtime.currentToolName();
      }
      if (job.record.parentSessionId === this.parentSessionId) {
        records.push(job.record);
      }
    });
    records.sort((a: SubagentJobRecord, b: SubagentJobRecord): number =>
      a.startedAt - b.startedAt);
    return records;
  }

  private status(query: string): ToolResult {
    const report: string = statusReport(this.jobsOfThisParent(), query, Date.now());
    return { ok: true, content: report };
  }

  private steer(jobId: string, message: string): ToolResult {
    const text: string = message.trim();
    if (text.length === 0) {
      return { ok: false, content: 'action=steer 需要非空的 message。' };
    }
    const ambiguous: string = this.ambiguity(jobId);
    if (ambiguous.length > 0) {
      return { ok: false, content: ambiguous };
    }
    const job: LiveJob | null = this.findJob(jobId);
    if (job === null) {
      return {
        ok: false,
        content: jobId.trim().length === 0
          ? 'action=steer 需要 job_id。'
          : '没有找到 job_id=' + jobId + ' 的子代理。'
      };
    }
    if (job.record.state === 'queued') {
      job.record.steers.push(text);
      return {
        ok: true,
        content: '子代理还在排队，纠正已记录，将在启动后的第一次请求前读取。'
      };
    }
    if (job.record.state !== 'running' || job.runtime === null) {
      return {
        ok: false,
        content: '子代理「' + job.record.id + '」已' + stateLabel(job.record.state) +
          '，steer 未送达。下次委派时请把这条纠正直接写进 prompt。'
      };
    }
    job.runtime.injectInput(text);
    return {
      ok: true,
      content: '已把纠正交给运行中的子代理，它会在下一次请求模型前读取；' +
        '正在进行的工具调用不会被打断。'
    };
  }

  private cancel(jobId: string): ToolResult {
    const ambiguous: string = this.ambiguity(jobId);
    if (ambiguous.length > 0) {
      return { ok: false, content: ambiguous };
    }
    const job: LiveJob | null = this.findJob(jobId);
    if (job === null) {
      return {
        ok: false,
        content: jobId.trim().length === 0
          ? 'action=cancel 需要 job_id。'
          : '没有找到 job_id=' + jobId + ' 的子代理。'
      };
    }
    if (job.record.state === 'queued') {
      job.cancelRequested = true;
      SubagentRunner.settleJob(job, 'cancelled', '');
      return { ok: true, content: '已取消排队中的子代理 ' + job.record.id + '。' };
    }
    if (job.record.state === 'running' && job.runtime !== null) {
      job.cancelRequested = true;
      job.runtime.cancel();
      SubagentRunner.cancelBlocking(job.record.childSessionId);
      return {
        ok: true,
        content: '已停止子代理 ' + job.record.id + '，已完成的部分结果会随结果返回。'
      };
    }
    return {
      ok: false,
      content: '子代理 ' + job.record.id + ' 已' + stateLabel(job.record.state) + '，无需取消。'
    };
  }

  private async resume(jobId: string): Promise<ToolResult> {
    if (this.depth > 0) {
      return { ok: false, content: '子代理内部不能重启任务，请让主对话执行 resume。' };
    }
    const records: SubagentJobRecord[] = this.jobsOfThisParent();
    const interrupted: SubagentJobRecord[] = [];
    for (let i = 0; i < records.length; i++) {
      if (records[i].state === 'interrupted') {
        interrupted.push(records[i]);
      }
    }
    if (interrupted.length === 0) {
      return { ok: true, content: '这个对话没有需要重启的中断子代理。' };
    }
    let targets: SubagentJobRecord[] = [];
    if (jobId.trim().length === 0) {
      targets = interrupted;
    } else {
      const matches: SubagentJobRecord[] = matchJobs(interrupted, jobId);
      if (matches.length === 0) {
        return { ok: false, content: '没有匹配「' + jobId + '」的中断子代理。' };
      }
      if (matches.length > 1) {
        return {
          ok: false,
          content: 'job_id 前缀「' + jobId + '」匹配了多个子代理，请提供更长的前缀。'
        };
      }
      targets = matches;
    }

    const lines: string[] = [];
    for (let i = 0; i < targets.length; i++) {
      const target: SubagentJobRecord = targets[i];
      const restarted: LiveJob | null = await this.restart(target);
      if (restarted === null) {
        lines.push(target.id + '：重启失败（缺少原始任务说明）');
        continue;
      }
      lines.push(target.id + '：已重新排队（新 job_id=' + restarted.record.id + '）');
    }
    SubagentRunner.pump();
    return { ok: true, content: '已重启中断的子代理：\n' + lines.join('\n') };
  }

  /**
   * A relaunch loses the child transcript, so resume starts a fresh child with
   * the original brief under a new job id; the interrupted record is retired.
   */
  private async restart(target: SubagentJobRecord): Promise<LiveJob | null> {
    if (target.prompt.trim().length === 0) {
      return null;
    }
    const agentName: string = target.agent !== undefined ? target.agent : '';
    let label: string = target.label;
    const prefix: string = agentName + ' · ';
    if (agentName.length > 0 && agentName !== BUILTIN_AGENT_NAME &&
      label.startsWith(prefix)) {
      label = label.substring(prefix.length);
    }
    const request: SubagentRequest = {
      action: 'delegate',
      prompt: target.prompt,
      label: label,
      jobId: '',
      message: '',
      wait: false,
      maxMinutes: SUBAGENT_DEFAULT_MINUTES,
      progressReport: 'none',
      agent: agentName
    };
    const result: ToolResult = await this.delegate(request);
    if (!result.ok) {
      return null;
    }
    const lines: string[] = result.content.split('\n');
    let newId: string = '';
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('job_id=')) {
        newId = lines[i].substring(7).trim();
      }
    }
    const created: LiveJob | undefined = SubagentRunner.jobs.get(newId);
    if (created === undefined) {
      return null;
    }
    SubagentRunner.jobs.delete(target.id);
    SubagentRunner.saveActive();
    return created;
  }

  private findMatches(jobId: string): SubagentJobRecord[] {
    const query: string = jobId.trim();
    if (query.length === 0) {
      return [];
    }
    return matchJobs(this.jobsOfThisParent(), query);
  }

  /** Non-empty when a shortened id matches more than one job. */
  private ambiguity(jobId: string): string {
    const matches: SubagentJobRecord[] = this.findMatches(jobId);
    if (matches.length <= 1) {
      return '';
    }
    const ids: string[] = [];
    for (let i = 0; i < matches.length; i++) {
      ids.push(matches[i].id);
    }
    return 'job_id 前缀「' + jobId.trim() + '」匹配了多个子代理：' +
      ids.join('、') + '。请提供更长的前缀。';
  }

  private findJob(jobId: string): LiveJob | null {
    const matches: SubagentJobRecord[] = this.findMatches(jobId);
    if (matches.length !== 1) {
      return null;
    }
    const job: LiveJob | undefined = SubagentRunner.jobs.get(matches[0].id);
    return job !== undefined ? job : null;
  }
}
