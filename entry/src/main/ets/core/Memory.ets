import { t } from './I18n';
/**
 * Persistent memory, modelled on OpenMinis: a user-maintained GLOBAL.md plus
 * one daily note per day. Pure formatting and search live here so the Node
 * harness can test them; MemoryStore owns the file I/O.
 */

export interface MemoryFile {
  /** File name shown in search hits, e.g. `2026-11-08.md`. */
  name: string;
  text: string;
}

export interface MemoryHit {
  line: string;
  name: string;
  score: number;
  order: number;
}

export interface MemoryLogEntry {
  at: number;
  text: string;
}

/** One non-empty line of a memory file, with its position in the file. */
export interface MemoryLine {
  index: number;
  text: string;
}

export const MEMORY_ENTRY_CHARS: number = 500;
export const MEMORY_CONTEXT_CHARS: number = 4000;
/** Read/write history rows kept for the in-chat memory panel. */
export const MEMORY_LOG_LIMIT: number = 50;

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** `YYYY-MM-DD`, using local time so "today" matches the user's clock. */
/**
 * Only the long-lived profile and one-file-per-day notes may be edited from
 * the UI. This rejects path separators and any other file name unchanged.
 */
export function isEditableMemoryFile(name: string): boolean {
  if (name === 'GLOBAL.md') {
    return true;
  }
  return new RegExp('^\\d{4}-\\d{2}-\\d{2}\\.md$').test(name);
}

export function dayKey(date: Date): string {
  return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) +
    '-' + pad2(date.getDate());
}

/** `HH:MM`, local time. */
export function clockKey(date: Date): string {
  return pad2(date.getHours()) + ':' + pad2(date.getMinutes());
}

/** Collapse a multi-line memory note into one bullet-sized line. */
export function oneLine(text: string): string {
  const flat: string = text.split('\n').join(' ').split('\r').join(' ')
    .split('\t').join(' ').trim();
  if (flat.length <= MEMORY_ENTRY_CHARS) {
    return flat;
  }
  return flat.substring(0, MEMORY_ENTRY_CHARS) + t('…');
}

export function memoryEntry(date: Date, content: string): string {
  return '- ' + clockKey(date) + ' ' + oneLine(content);
}

/**
 * Non-empty lines for per-entry editing. `index` counts every line in the
 * file, blank ones included, so callers can rewrite the file in place.
 */
export function memoryLines(text: string): MemoryLine[] {
  const parts: string[] = text.split('\n');
  const out: MemoryLine[] = [];
  for (let i = 0; i < parts.length; i++) {
    const clean: string = parts[i].split('\r').join('').trim();
    if (clean.length > 0) {
      out.push({ index: i, text: clean });
    }
  }
  return out;
}

/** Read one line without collapsing it; returns '' for an invalid index. */
export function memoryLineAt(text: string, index: number): string {
  const parts: string[] = text.split('\n');
  if (index < 0 || index >= parts.length) {
    return '';
  }
  return parts[index].split('\r').join('').trim();
}

/** Rewrite one line, flattening any newlines the user pasted. */
export function replaceMemoryLine(
  text: string,
  index: number,
  next: string
): string {
  const parts: string[] = text.split('\n');
  if (index < 0 || index >= parts.length) {
    return text;
  }
  parts[index] = oneLine(next);
  return parts.join('\n');
}

/** Drop one line while keeping every other line (and blank lines) intact. */
export function removeMemoryLine(text: string, index: number): string {
  const parts: string[] = text.split('\n');
  if (index < 0 || index >= parts.length) {
    return text;
  }
  parts.splice(index, 1);
  return parts.join('\n');
}

/** Newest-first log list, capped; malformed rows are dropped on read. */
export function parseMemoryLogs(raw: string): MemoryLogEntry[] {
  if (raw.trim().length === 0) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const list: Object[] = parsed as Object[];
  const out: MemoryLogEntry[] = [];
  for (let i = 0; i < list.length && out.length < MEMORY_LOG_LIMIT; i++) {
    const item: Record<string, Object> = list[i] as Record<string, Object>;
    const at: number = typeof item.at === 'number' ? item.at as number : 0;
    const text: string = typeof item.text === 'string' ? item.text as string : '';
    if (at > 0 && text.trim().length > 0) {
      out.push({ at: at, text: text });
    }
  }
  return out;
}

/** Prepend one row and trim to the limit; returns a fresh array. */
export function mergeMemoryLog(
  logs: MemoryLogEntry[],
  entry: MemoryLogEntry,
  limit: number
): MemoryLogEntry[] {
  const cap: number = limit > 0 ? limit : MEMORY_LOG_LIMIT;
  const next: MemoryLogEntry[] = [entry].concat(logs);
  return next.length > cap ? next.slice(0, cap) : next;
}

export function memoryLogsJson(logs: MemoryLogEntry[]): string {
  return JSON.stringify(logs);
}

/** Split a query into lowercase terms; empty input means "list recent". */
export function queryTerms(query: string): string[] {
  const trimmed: string = query.trim().toLowerCase();
  if (trimmed.length === 0) {
    return [];
  }
  const raw: string[] = trimmed.split(' ');
  const terms: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    if (raw[i].length > 0 && terms.indexOf(raw[i]) < 0) {
      terms.push(raw[i]);
    }
  }
  return terms;
}

/**
 * Keyword search across memory files. Every term is matched independently;
 * lines matching more terms rank first. With no terms, the newest lines are
 * returned so the model can ask "what do you remember".
 */
export function searchMemoryFiles(
  files: MemoryFile[],
  query: string,
  limit: number
): string {
  const terms: string[] = queryTerms(query);
  const hits: MemoryHit[] = [];
  let order: number = 0;
  for (let i = 0; i < files.length; i++) {
    const lines: string[] = files[i].text.split('\n');
    for (let j = 0; j < lines.length; j++) {
      const line: string = lines[j].trim();
      if (line.length === 0) {
        continue;
      }
      let score: number = 0;
      const lower: string = line.toLowerCase();
      for (let k = 0; k < terms.length; k++) {
        if (lower.indexOf(terms[k]) >= 0) {
          score++;
        }
      }
      if (terms.length === 0 || score > 0) {
        hits.push({ line: line, name: files[i].name, score: score, order: order });
        order++;
      }
    }
  }
  if (hits.length === 0) {
    return query.trim().length > 0
      ? t('记忆中没有找到与“') + query.trim() + t('”相关的内容。')
      : t('还没有记忆内容。');
  }
  hits.sort((a: MemoryHit, b: MemoryHit): number => {
    if (b.score !== a.score) {
      return b.score - a.score;
    }
    return a.order - b.order;
  });
  const out: string[] = [];
  const count: number = limit > 0 ? Math.min(limit, hits.length) : hits.length;
  for (let i = 0; i < count; i++) {
    out.push('[' + hits[i].name + '] ' + hits[i].line);
  }
  return out.join('\n');
}

/**
 * Context injected into the system prompt. Files are expected newest-first,
 * with GLOBAL.md last so the user-maintained profile survives truncation.
 */
export function buildMemoryContext(files: MemoryFile[], maxChars: number): string {
  if (files.length === 0) {
    return '';
  }
  let body: string = '';
  for (let i = 0; i < files.length; i++) {
    const block: string = '### ' + files[i].name + '\n' + files[i].text.trim() + '\n\n';
    if (body.length + block.length > maxChars) {
      const room: number = maxChars - body.length;
      if (room > 40) {
        body += block.substring(0, room);
      }
      break;
    }
    body += block;
  }
  if (body.trim().length === 0) {
    return '';
  }
  return t('## 长期记忆\n') +
    t('以下内容来自本机记忆文件，仅在与当前任务相关时参考，不要逐条复述。\n\n') +
    body.trim();
}
