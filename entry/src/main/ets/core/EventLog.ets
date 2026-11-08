/**
 * Structured event log ("埋点") records.
 *
 * Everything here is pure so the format and redaction rules can be tested
 * under Node. The app writes one JSON object per line; it never records
 * message bodies, prompts, API keys or sandbox tokens.
 */

export const LOG_INFO: string = 'info';
export const LOG_WARN: string = 'warn';
export const LOG_ERROR: string = 'error';

export const EVENT_AGENT_START: string = 'agent_start';
export const EVENT_AGENT_FINISH: string = 'agent_finish';
export const EVENT_MODEL_START: string = 'model_start';
export const EVENT_MODEL_DONE: string = 'model_done';
export const EVENT_MODEL_ERROR: string = 'model_error';
export const EVENT_TOOL_START: string = 'tool_start';
export const EVENT_TOOL_DONE: string = 'tool_done';
export const EVENT_TURN_CAP: string = 'turn_cap';
export const EVENT_CANCELLED: string = 'cancelled';
export const EVENT_SETTINGS: string = 'settings_saved';
export const EVENT_LOG_CLEARED: string = 'log_cleared';

export interface LogEvent {
  /** Epoch milliseconds. */
  ts: number;
  /** Stable event name, e.g. model_done. */
  event: string;
  level: string;
  /** First 8 characters of the conversation id: enough to correlate, not to reuse. */
  session: string;
  model: string;
  /** Model/tool round trip number inside the user turn, 1-based. */
  step: number;
  /** Tool name for tool_* events, otherwise empty. */
  tool: string;
  ok: boolean;
  durationMs: number;
  /** Short, redacted, non-content detail (error text, status, counts). */
  detail: string;
  /** First 8 characters of the request id, so one HTTP call can be traced. */
  req: string;
}

/** Session ids are routing hints, not secrets, but logs do not need the full id. */
export function sessionTag(sessionId: string): string {
  if (sessionId.length <= 8) {
    return sessionId;
  }
  return sessionId.substring(0, 8);
}

/**
 * Remove credential-shaped strings that may appear in upstream error bodies.
 * Redaction is deliberately conservative: it is better to over-mask than to
 * persist a key.
 */
export function redactSecrets(text: string): string {
  let value: string = text;
  value = value.replace(/sk-[A-Za-z0-9_-]{6,}/g, 'sk-***');
  value = value.replace(/Bearer\s+[A-Za-z0-9._~+\/=-]+/gi, 'Bearer ***');
  value = value.replace(
    /(\b(?:api[_-]?key|access_token|token|authorization)\s*[=:]\s*)("[^"]*"|[^\s&,]+)/gi,
    '$1***'
  );
  value = value.replace(/"(api[_-]?key|token|authorization)"\s*:\s*"[^"]*"/gi, '"$1":"***"');
  return value;
}

/** Flatten newlines and cap the detail so one event stays one short line. */
export function sanitizeDetail(text: string): string {
  let value: string = redactSecrets(text);
  value = value.replace(/[\r\n\t]+/g, ' ');
  if (value.length > 300) {
    value = value.substring(0, 300) + '…';
  }
  return value;
}

interface RawEventLine {
  ts?: number;
  event?: string;
  level?: string;
  tool?: string;
  ok?: boolean;
  durationMs?: number;
  detail?: string;
  req?: string;
}

/** Structured form used by the in-app log viewer for filtering. */
export interface ParsedEventLine {
  ts: number;
  event: string;
  level: string;
  tool: string;
  ok: boolean;
  durationMs: number;
  detail: string;
  req: string;
  /** The original JSONL text, so copy/export never loses any field. */
  raw: string;
}

/**
 * Parse one stored line for filtering. Corrupt or legacy lines degrade to an
 * `info` entry with the raw text as the detail, never dropping the line.
 */
export function parseEventLine(line: string): ParsedEventLine {
  const trimmed: string = line.trim();
  try {
    const raw: RawEventLine = JSON.parse(trimmed) as RawEventLine;
    // Stored JSON can contain `null` for any field; type checks keep a
    // corrupt line from crashing the viewer.
    return {
      ts: typeof raw.ts === 'number' ? raw.ts : 0,
      event: typeof raw.event === 'string' ? raw.event : '?',
      level: typeof raw.level === 'string' ? raw.level : LOG_INFO,
      tool: typeof raw.tool === 'string' ? raw.tool : '',
      ok: raw.ok !== false,
      durationMs: typeof raw.durationMs === 'number' ? raw.durationMs : 0,
      detail: typeof raw.detail === 'string' ? raw.detail : '',
      req: typeof raw.req === 'string' ? raw.req : '',
      raw: trimmed
    };
  } catch (e) {
    return {
      ts: 0,
      event: '?',
      level: LOG_INFO,
      tool: '',
      ok: true,
      durationMs: 0,
      detail: trimmed,
      req: '',
      raw: trimmed
    };
  }
}

function two(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/**
 * Turn one stored JSONL line into a compact viewer line. Unknown/corrupt
 * lines are returned as-is so debugging is never blocked by a parser.
 */
export function formatEventLine(line: string): string {
  const trimmed: string = line.trim();
  if (trimmed.length === 0) {
    return '';
  }
  try {
    const raw: RawEventLine = JSON.parse(trimmed) as RawEventLine;
    // `null` passes an `!== undefined` check, so type-check every field.
    const ts: number = typeof raw.ts === 'number' ? raw.ts : 0;
    const date: Date = new Date(ts);
    let text: string = two(date.getMonth() + 1) + '-' + two(date.getDate()) + ' ' +
      two(date.getHours()) + ':' + two(date.getMinutes()) + ':' +
      two(date.getSeconds()) + ' ' +
      (typeof raw.event === 'string' ? raw.event : '?');
    const tool: string = typeof raw.tool === 'string' ? raw.tool : '';
    if (tool.length > 0) {
      text += ' · ' + tool;
    }
    text += raw.ok === false ? ' ✗' : ' ✓';
    const duration: number = typeof raw.durationMs === 'number' ? raw.durationMs : 0;
    if (duration > 0) {
      text += ' ' + duration.toString() + 'ms';
    }
    const req: string = typeof raw.req === 'string' ? raw.req : '';
    if (req.length > 0) {
      text += ' · req=' + req;
    }
    const detail: string = typeof raw.detail === 'string' ? raw.detail : '';
    if (detail.length > 0) {
      text += ' · ' + detail;
    }
    return text;
  } catch (e) {
    return trimmed;
  }
}

export function newLogEvent(event: string, level: string): LogEvent {
  return {
    ts: Date.now(),
    event: event,
    level: level,
    session: '',
    model: '',
    step: 0,
    tool: '',
    ok: true,
    durationMs: 0,
    detail: '',
    req: ''
  };
}

/** One JSONL record. The trailing newline is required for append-only files. */
export function serializeEvent(event: LogEvent): string {
  const safe: LogEvent = {
    ts: event.ts,
    event: event.event,
    level: event.level,
    session: event.session,
    model: event.model,
    step: event.step,
    tool: event.tool,
    ok: event.ok,
    durationMs: event.durationMs,
    detail: sanitizeDetail(event.detail),
    req: event.req
  };
  return JSON.stringify(safe) + '\n';
}

/** `events-2026-11-07.jsonl`, local date, one file per day. */
export function logFileName(date: Date): string {
  const year: string = date.getFullYear().toString();
  const month: string = pad2(date.getMonth() + 1);
  const day: string = pad2(date.getDate());
  return 'events-' + year + '-' + month + '-' + day + '.jsonl';
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}
