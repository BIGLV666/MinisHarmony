import { t } from './I18n';
/**
 * Pure state for delegated subagent jobs.
 *
 * OpenMinis exposes one `subagent_task` tool with an `action`: delegate,
 * status, steer, cancel or resume. A background job returns at once with a
 * job id and posts its outcome later as a new message in the parent
 * conversation. This module holds the parts that do not touch Android or
 * ArkUI: the state machine, id prefix matching, human-readable status and the
 * completion message, so all of it can be unit tested in Node.
 */

export type SubagentState =
  'queued' | 'running' | 'done' | 'cancelled' | 'failed' | 'timeout' | 'interrupted';

/** User-role messages with this prefix resume the parent's turn on open. */
// Internal markers stay language-independent: they are matched against
// messages restored from disk after a language switch.
export const BACKGROUND_PREFIX: string = '[后台任务结束';

export interface SubagentJobRecord {
  id: string;
  parentSessionId: string;
  childSessionId: string;
  label: string;
  /** Roster name the job was delegated to; `helper` when unspecified. */
  agent: string;
  prompt: string;
  modelId: string;
  state: SubagentState;
  startedAt: number;
  finishedAt: number;
  /** Tool the child is executing right now, empty between turns. */
  currentTool: string;
  /** Corrections waiting to be read at the child's next turn. */
  steers: string[];
  resultText: string;
}

export function newJobRecord(
  id: string,
  parentSessionId: string,
  childSessionId: string,
  label: string,
  prompt: string,
  modelId: string,
  now: number
): SubagentJobRecord {
  return {
    id: id,
    parentSessionId: parentSessionId,
    childSessionId: childSessionId,
    label: label,
    agent: '',
    prompt: prompt,
    modelId: modelId,
    state: 'queued',
    startedAt: now,
    finishedAt: 0,
    currentTool: '',
    steers: [],
    resultText: ''
  };
}

export function isActiveState(state: SubagentState): boolean {
  return state === 'queued' || state === 'running';
}

export function isTerminalState(state: SubagentState): boolean {
  return !isActiveState(state);
}

export function stateLabel(state: SubagentState): string {
  if (state === 'queued') {
    return t('排队中');
  }
  if (state === 'running') {
    return t('运行中');
  }
  if (state === 'done') {
    return t('已完成');
  }
  if (state === 'cancelled') {
    return t('已取消');
  }
  if (state === 'failed') {
    return t('失败');
  }
  if (state === 'timeout') {
    return t('超时');
  }
  return t('已中断');
}

export function elapsedText(ms: number): string {
  const seconds: number = Math.max(0, Math.floor(ms / 1000));
  if (seconds < 60) {
    return seconds.toString() + t(' 秒');
  }
  const minutes: number = Math.floor(seconds / 60);
  if (minutes < 60) {
    return minutes.toString() + t(' 分 ') + (seconds % 60).toString() + t(' 秒');
  }
  const hours: number = Math.floor(minutes / 60);
  return hours.toString() + t(' 小时 ') + (minutes % 60).toString() + t(' 分');
}

/**
 * Jobs matching a full id or a unique prefix. An exact id wins over prefixes;
 * when several prefixes match the caller must ask for a longer id.
 */
export function matchJobs(
  jobs: SubagentJobRecord[],
  query: string
): SubagentJobRecord[] {
  const needle: string = query.trim().toLowerCase();
  if (needle.length === 0) {
    return jobs.slice();
  }
  const exact: SubagentJobRecord[] = [];
  const prefix: SubagentJobRecord[] = [];
  for (let i = 0; i < jobs.length; i++) {
    const id: string = jobs[i].id.toLowerCase();
    if (id === needle) {
      exact.push(jobs[i]);
    } else if (id.startsWith(needle)) {
      prefix.push(jobs[i]);
    }
  }
  return exact.length > 0 ? exact : prefix;
}

export function endJob(
  job: SubagentJobRecord,
  state: SubagentState,
  resultText: string,
  now: number
): void {
  job.state = state;
  job.finishedAt = now;
  job.resultText = resultText;
  job.currentTool = '';
}

export function takeSteers(job: SubagentJobRecord): string[] {
  const pending: string[] = job.steers;
  job.steers = [];
  return pending;
}

function resultExcerpt(text: string, limit: number): string {
  const trimmed: string = text.trim();
  if (trimmed.length <= limit) {
    return trimmed;
  }
  return trimmed.substring(0, limit) + t('…');
}

function jobLines(job: SubagentJobRecord, now: number): string[] {
  const lines: string[] = [];
  const title: string = job.label.length > 0 ? job.label : t('子代理');
  lines.push('job_id=' + job.id + t(' · ') + title + t(' · ') + stateLabel(job.state));
  const end: number = job.finishedAt > 0 ? job.finishedAt : now;
  lines.push(t('  已运行 ') + elapsedText(Math.max(0, end - job.startedAt)) +
    (job.finishedAt > 0 ? t('（已结束）') : ''));
  if (job.state === 'running' && job.currentTool.length > 0) {
    lines.push(t('  当前工具：') + job.currentTool);
  }
  if (job.modelId.length > 0) {
    lines.push(t('  模型：') + job.modelId);
  }
  if (job.steers.length > 0) {
    lines.push(t('  待读取的纠正：') + job.steers.length.toString() + t(' 条'));
  }
  if (job.resultText.length > 0) {
    lines.push(t('  结果：') + resultExcerpt(job.resultText, 400));
  }
  return lines;
}

/**
 * `action=status` reply. With no query every job of this conversation is
 * listed; an id or a unique prefix narrows it to one.
 */
export function statusReport(
  jobs: SubagentJobRecord[],
  query: string,
  now: number
): string {
  const matches: SubagentJobRecord[] = matchJobs(jobs, query);
  if (matches.length === 0) {
    if (jobs.length === 0) {
      return t('这个对话还没有启动过子代理。');
    }
    return t('没有匹配「') + query.trim() + t('」的子代理。可用 job_id：') +
      jobs[jobs.length - 1].id;
  }
  if (matches.length > 1 && query.trim().length > 0) {
    const ids: string[] = [];
    for (let i = 0; i < matches.length; i++) {
      ids.push(matches[i].id);
    }
    return t('job_id 前缀「') + query.trim() + t('」匹配了多个子代理：') +
      ids.join(t('、')) + t('。请提供更长的前缀。');
  }

  let running: number = 0;
  let queued: number = 0;
  for (let i = 0; i < matches.length; i++) {
    if (matches[i].state === 'running') {
      running++;
    } else if (matches[i].state === 'queued') {
      queued++;
    }
  }
  const lines: string[] = [];
  if (matches.length === 1) {
    lines.push(t('子代理状态：'));
  } else {
    lines.push(t('共 ') + matches.length.toString() + t(' 个子代理：') +
      running.toString() + t(' 运行中，') + queued.toString() + t(' 排队中，') +
      (matches.length - running - queued).toString() + t(' 已结束'));
  }
  for (let i = 0; i < matches.length; i++) {
    if (i > 0) {
      lines.push('');
    }
    const part: string[] = jobLines(matches[i], now);
    for (let j = 0; j < part.length; j++) {
      lines.push(part[j]);
    }
  }
  return lines.join('\n');
}

/** Message posted into the parent conversation when a background job ends. */
export function backgroundMessage(job: SubagentJobRecord): string {
  const title: string = job.label.length > 0 ? job.label : t('子代理');
  const minutes: number = Math.floor(
    Math.max(0, job.finishedAt - job.startedAt) / 60000);
  let line: string = BACKGROUND_PREFIX + t(' · ') + title + t(' · job_id=') + job.id +
    t(']\n状态：') + stateLabel(job.state) + t(' · 用时 ') +
    elapsedText(Math.max(0, job.finishedAt - job.startedAt));
  if (minutes >= 1) {
    line += t('（约 ') + minutes.toString() + t(' 分钟）');
  }
  const body: string = job.resultText.trim();
  return line + '\n\n' + (body.length > 0 ? body : t('（子代理没有返回文本）'));
}

/** User-role messages with this prefix are mid-run progress reports. */
export const PROGRESS_PREFIX: string = '[后台任务进度';
/** OpenMinis: "frequent" reports every 15 s, "moderate" once a minute. */
export const PROGRESS_FREQUENT_MS: number = 15000;
export const PROGRESS_MODERATE_MS: number = 60000;
/** Only the tail of the child's latest text is worth a parent turn. */
export const PROGRESS_MESSAGE_MAX_CHARS: number = 800;

/** Normalize `progress_report`; unknown values mean "none". */
export function parseProgressLevel(raw: string): string {
  const value: string = raw.trim().toLowerCase();
  if (value === 'frequent' || value === 'moderate') {
    return value;
  }
  return 'none';
}

/** Milliseconds between reports, or 0 when the level reports nothing. */
export function progressInterval(level: string): number {
  if (level === 'frequent') {
    return PROGRESS_FREQUENT_MS;
  }
  if (level === 'moderate') {
    return PROGRESS_MODERATE_MS;
  }
  return 0;
}

/**
 * What counts as "something changed" for the frequent level: the current
 * tool, the number of completed turns, and the beginning of the latest text.
 */
export function progressSignature(
  currentTool: string,
  turns: number,
  lastMessage: string
): string {
  return currentTool + '|' + turns.toString() + '|' +
    lastMessage.substring(0, 200);
}

/** Mid-run message posted into the parent conversation. */
export function progressMessage(
  job: SubagentJobRecord,
  currentTool: string,
  elapsedMs: number,
  turns: number,
  lastMessage: string
): string {
  const title: string = job.label.length > 0 ? job.label : t('子代理');
  let text = PROGRESS_PREFIX + t(' · ') + title + t(' · job_id=') + job.id + ']\n' +
    t('状态：') + stateLabel(job.state) + t(' · 已用时 ') +
    elapsedText(Math.max(0, elapsedMs)) + t(' · 已进行 ') + turns.toString() + t(' 轮');
  if (currentTool.length > 0) {
    text += t('\n当前工具：') + currentTool;
  }
  const body: string = lastMessage.trim();
  text += '\n\n' + (body.length > 0
    ? body.length > PROGRESS_MESSAGE_MAX_CHARS
      ? body.substring(body.length - PROGRESS_MESSAGE_MAX_CHARS)
      : body
    : t('（子代理还没有输出文本）'));
  return text;
}

/** Keep the most recent terminal jobs so status stays readable. */
export function pruneJobs(
  jobs: SubagentJobRecord[],
  keepTerminal: number
): SubagentJobRecord[] {
  const terminal: SubagentJobRecord[] = [];
  const active: SubagentJobRecord[] = [];
  for (let i = 0; i < jobs.length; i++) {
    if (isTerminalState(jobs[i].state)) {
      terminal.push(jobs[i]);
    } else {
      active.push(jobs[i]);
    }
  }
  terminal.sort((a: SubagentJobRecord, b: SubagentJobRecord): number =>
    b.finishedAt - a.finishedAt);
  const kept: SubagentJobRecord[] = active.concat(
    terminal.slice(0, keepTerminal));
  kept.sort((a: SubagentJobRecord, b: SubagentJobRecord): number =>
    a.startedAt - b.startedAt);
  return kept;
}
