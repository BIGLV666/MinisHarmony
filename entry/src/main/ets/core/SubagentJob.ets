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
export const BACKGROUND_PREFIX: string = '[后台任务结束';

export interface SubagentJobRecord {
  id: string;
  parentSessionId: string;
  childSessionId: string;
  label: string;
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
    return '排队中';
  }
  if (state === 'running') {
    return '运行中';
  }
  if (state === 'done') {
    return '已完成';
  }
  if (state === 'cancelled') {
    return '已取消';
  }
  if (state === 'failed') {
    return '失败';
  }
  if (state === 'timeout') {
    return '超时';
  }
  return '已中断';
}

export function elapsedText(ms: number): string {
  const seconds: number = Math.max(0, Math.floor(ms / 1000));
  if (seconds < 60) {
    return seconds.toString() + ' 秒';
  }
  const minutes: number = Math.floor(seconds / 60);
  if (minutes < 60) {
    return minutes.toString() + ' 分 ' + (seconds % 60).toString() + ' 秒';
  }
  const hours: number = Math.floor(minutes / 60);
  return hours.toString() + ' 小时 ' + (minutes % 60).toString() + ' 分';
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
  return trimmed.substring(0, limit) + '…';
}

function jobLines(job: SubagentJobRecord, now: number): string[] {
  const lines: string[] = [];
  const title: string = job.label.length > 0 ? job.label : '子代理';
  lines.push('job_id=' + job.id + ' · ' + title + ' · ' + stateLabel(job.state));
  const end: number = job.finishedAt > 0 ? job.finishedAt : now;
  lines.push('  已运行 ' + elapsedText(Math.max(0, end - job.startedAt)) +
    (job.finishedAt > 0 ? '（已结束）' : ''));
  if (job.state === 'running' && job.currentTool.length > 0) {
    lines.push('  当前工具：' + job.currentTool);
  }
  if (job.modelId.length > 0) {
    lines.push('  模型：' + job.modelId);
  }
  if (job.steers.length > 0) {
    lines.push('  待读取的纠正：' + job.steers.length.toString() + ' 条');
  }
  if (job.resultText.length > 0) {
    lines.push('  结果：' + resultExcerpt(job.resultText, 400));
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
      return '这个对话还没有启动过子代理。';
    }
    return '没有匹配「' + query.trim() + '」的子代理。可用 job_id：' +
      jobs[jobs.length - 1].id;
  }
  if (matches.length > 1 && query.trim().length > 0) {
    const ids: string[] = [];
    for (let i = 0; i < matches.length; i++) {
      ids.push(matches[i].id);
    }
    return 'job_id 前缀「' + query.trim() + '」匹配了多个子代理：' +
      ids.join('、') + '。请提供更长的前缀。';
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
    lines.push('子代理状态：');
  } else {
    lines.push('共 ' + matches.length.toString() + ' 个子代理：' +
      running.toString() + ' 运行中，' + queued.toString() + ' 排队中，' +
      (matches.length - running - queued).toString() + ' 已结束');
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
  const title: string = job.label.length > 0 ? job.label : '子代理';
  const minutes: number = Math.floor(
    Math.max(0, job.finishedAt - job.startedAt) / 60000);
  let line: string = BACKGROUND_PREFIX + ' · ' + title + ' · job_id=' + job.id +
    ']\n状态：' + stateLabel(job.state) + ' · 用时 ' +
    elapsedText(Math.max(0, job.finishedAt - job.startedAt));
  if (minutes >= 1) {
    line += '（约 ' + minutes.toString() + ' 分钟）';
  }
  const body: string = job.resultText.trim();
  return line + '\n\n' + (body.length > 0 ? body : '（子代理没有返回文本）');
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
