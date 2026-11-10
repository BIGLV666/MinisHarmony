import { FileEntry } from './FileListing';

/**
 * `@` file mentions in the composer. The caret position is not exposed by
 * ArkUI's TextArea, so the mention is the trailing token: an `@` at the start
 * of the draft or after whitespace, followed by a run of non-whitespace text.
 * That covers the usual "type @, keep typing the name" flow while leaving
 * e-mail addresses and already-inserted `@path` mentions alone.
 */

export interface MentionQuery {
  /** Index of the `@` character in the draft. */
  start: number;
  /** Text typed after `@` (may be empty right after the trigger). */
  query: string;
}

const MAX_QUERY: number = 120;

function isSpace(ch: string): boolean {
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r';
}

/** The trailing `@query` token, or null when the draft has none. */
export function activeMention(text: string): MentionQuery | null {
  const at: number = text.lastIndexOf('@');
  if (at < 0) {
    return null;
  }
  if (at > 0 && !isSpace(text.substring(at - 1, at))) {
    return null;
  }
  const query: string = text.substring(at + 1);
  if (query.length > MAX_QUERY) {
    return null;
  }
  for (let i = 0; i < query.length; i++) {
    if (isSpace(query.substring(i, i + 1))) {
      return null;
    }
  }
  return { start: at, query: query };
}

/** Replace the active token with `@path ` so the next word starts cleanly. */
export function replaceMention(text: string, start: number, path: string): string {
  const from: number = start >= 0 && start <= text.length ? start : text.length;
  return text.substring(0, from) + '@' + path + ' ';
}

/** Files whose relative path contains the query, case-insensitively. */
export function filterMentionFiles(
  entries: FileEntry[],
  query: string,
  limit: number
): FileEntry[] {
  const needle: string = query.trim().toLowerCase();
  const matched: FileEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    const entry: FileEntry = entries[i];
    if (entry.isDir) {
      continue;
    }
    const path: string = entry.path.toLowerCase();
    if (needle.length === 0 || path.indexOf(needle) >= 0) {
      matched.push(entry);
      if (matched.length >= limit) {
        break;
      }
    }
  }
  return matched;
}
