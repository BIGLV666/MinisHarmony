/**
 * Scheduled task model and pure formatting/validation helpers.
 *
 * A task is a reminder that carries a prompt. When the system notification
 * fires, tapping it opens the app through `minis://task/<id>`; the prompt is
 * placed in the composer so the user confirms before any model request is
 * made. Runs (prompt actually sent and finished) are kept separately as a
 * small history list.
 */

export const MAX_TASK_PROMPT: number = 4000;
export const MAX_TASK_RUNS: number = 50;
export const MIN_TASK_LEAD_MS: number = 60 * 1000;
export const MAX_TASK_LEAD_MS: number = 365 * 24 * 60 * 60 * 1000;

export interface ScheduledTask {
  id: string;
  prompt: string;
  /** Epoch milliseconds of the reminder. */
  at: number;
  /** Reminder id returned by reminderAgentManager; 0 when not published. */
  reminderId: number;
  createdAt: number;
  /** Last time the notification reopened the app; 0 when never. */
  triggeredAt: number;
}

export interface TaskRun {
  id: string;
  taskId: string;
  /** Prompt-derived title, so history survives task deletion. */
  title: string;
  startedAt: number;
  finishedAt: number;
  ok: boolean;
  /** First part of the answer, or the error text. Never redacted secrets. */
  summary: string;
}

export function normalizeTaskPrompt(text: string): string {
  const trimmed: string = text.trim();
  return trimmed.length > MAX_TASK_PROMPT
    ? trimmed.substring(0, MAX_TASK_PROMPT)
    : trimmed;
}

function singleLine(text: string): string {
  return text.replace(/[\r\n\t]+/g, ' ').trim();
}

export function taskTitle(prompt: string): string {
  let line: string = '';
  const lines: string[] = prompt.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const candidate: string = lines[i].trim();
    if (candidate.length > 0) {
      line = candidate;
      break;
    }
  }
  line = singleLine(line).replace(/^[#>*\-+\s]+/, '');
  if (line.length === 0) {
    return '定时任务';
  }
  return line.length > 20 ? line.substring(0, 20) + '…' : line;
}

export function taskNotificationContent(prompt: string): string {
  const line: string = singleLine(prompt);
  if (line.length === 0) {
    return '点击填入提示词';
  }
  return line.length > 80 ? line.substring(0, 80) + '…' : line;
}

/** '' when the time is usable, otherwise a user-facing reason. */
export function validateTaskAt(at: number, now: number): string {
  if (!Number.isFinite(at) || at <= 0) {
    return '请选择提醒时间';
  }
  if (at < now + MIN_TASK_LEAD_MS) {
    return '提醒时间至少要在 1 分钟之后';
  }
  if (at > now + MAX_TASK_LEAD_MS) {
    return '提醒时间不能超过一年';
  }
  return '';
}

export function makeTask(
  id: string,
  prompt: string,
  at: number,
  now: number
): ScheduledTask {
  return {
    id: id,
    prompt: normalizeTaskPrompt(prompt),
    at: at,
    reminderId: 0,
    createdAt: now,
    triggeredAt: 0
  };
}

/** Earliest reminder first; ties keep insertion order. */
export function sortTasks(tasks: ScheduledTask[]): ScheduledTask[] {
  const copy: ScheduledTask[] = tasks.slice(0);
  copy.sort((a: ScheduledTask, b: ScheduledTask) => a.at - b.at);
  return copy;
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

function dayStart(timestamp: number): number {
  const date: Date = new Date(timestamp);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

export function formatTaskTime(at: number, now: number): string {
  const date: Date = new Date(at);
  const time: string = pad2(date.getHours()) + ':' + pad2(date.getMinutes());
  const today: number = dayStart(now);
  const target: number = dayStart(at);
  if (target === today) {
    return '今天 ' + time;
  }
  if (target === today + 24 * 60 * 60 * 1000) {
    return '明天 ' + time;
  }
  const monthDay: string = pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  if (date.getFullYear() === new Date(now).getFullYear()) {
    return monthDay + ' ' + time;
  }
  return date.getFullYear().toString() + '-' + monthDay + ' ' + time;
}

interface RawTask {
  id?: string;
  prompt?: string;
  at?: number;
  reminderId?: number;
  createdAt?: number;
  triggeredAt?: number;
}

export function parseTasks(text: string): ScheduledTask[] {
  if (text.trim().length === 0) {
    return [];
  }
  let raw: RawTask[];
  try {
    raw = JSON.parse(text) as RawTask[];
  } catch (e) {
    return [];
  }
  if (!Array.isArray(raw)) {
    return [];
  }
  const out: ScheduledTask[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item: RawTask = raw[i];
    if (item === null || item === undefined) {
      continue;
    }
    const id: string = typeof item.id === 'string' ? item.id : '';
    const prompt: string = typeof item.prompt === 'string' ? item.prompt : '';
    if (id.length === 0 || prompt.trim().length === 0) {
      continue;
    }
    out.push({
      id: id,
      prompt: normalizeTaskPrompt(prompt),
      at: typeof item.at === 'number' && item.at > 0 ? item.at : 0,
      reminderId: typeof item.reminderId === 'number' ? item.reminderId : 0,
      createdAt: typeof item.createdAt === 'number' ? item.createdAt : 0,
      triggeredAt: typeof item.triggeredAt === 'number' ? item.triggeredAt : 0
    });
  }
  return sortTasks(out);
}

export function tasksJson(tasks: ScheduledTask[]): string {
  return JSON.stringify(sortTasks(tasks));
}

interface RawRun {
  id?: string;
  taskId?: string;
  title?: string;
  startedAt?: number;
  finishedAt?: number;
  ok?: boolean;
  summary?: string;
}

function summarize(text: string): string {
  const line: string = singleLine(text);
  return line.length > 120 ? line.substring(0, 120) + '…' : line;
}

export function makeRun(
  id: string,
  task: ScheduledTask,
  startedAt: number,
  replyText: string,
  errorText: string,
  finishedAt: number
): TaskRun {
  const ok: boolean = errorText.length === 0 && replyText.trim().length > 0;
  const source: string = ok ? replyText : (errorText.length > 0 ? errorText : '没有返回内容');
  return {
    id: id,
    taskId: task.id,
    title: taskTitle(task.prompt),
    startedAt: startedAt,
    finishedAt: finishedAt,
    ok: ok,
    summary: summarize(source)
  };
}

/** Newest first, capped. */
export function trimRuns(runs: TaskRun[]): TaskRun[] {
  const copy: TaskRun[] = runs.slice(0);
  copy.sort((a: TaskRun, b: TaskRun) => b.finishedAt - a.finishedAt);
  return copy.length > MAX_TASK_RUNS ? copy.slice(0, MAX_TASK_RUNS) : copy;
}

export function parseRuns(text: string): TaskRun[] {
  if (text.trim().length === 0) {
    return [];
  }
  let raw: RawRun[];
  try {
    raw = JSON.parse(text) as RawRun[];
  } catch (e) {
    return [];
  }
  if (!Array.isArray(raw)) {
    return [];
  }
  const out: TaskRun[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item: RawRun = raw[i];
    if (item === null || item === undefined) {
      continue;
    }
    const id: string = typeof item.id === 'string' ? item.id : '';
    if (id.length === 0) {
      continue;
    }
    out.push({
      id: id,
      taskId: typeof item.taskId === 'string' ? item.taskId : '',
      title: typeof item.title === 'string' ? item.title : '定时任务',
      startedAt: typeof item.startedAt === 'number' ? item.startedAt : 0,
      finishedAt: typeof item.finishedAt === 'number' ? item.finishedAt : 0,
      ok: item.ok === true,
      summary: typeof item.summary === 'string' ? item.summary : ''
    });
  }
  return trimRuns(out);
}

export function runsJson(runs: TaskRun[]): string {
  return JSON.stringify(trimRuns(runs));
}
