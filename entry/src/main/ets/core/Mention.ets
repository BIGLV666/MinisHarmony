import { FileEntry } from './FileListing';

/**
 * `@` file mentions in the composer. The token is resolved against the caret
 * position reported by TextArea.onTextSelectionChange, so an `@` typed in the
 * middle of the draft opens the menu just like one typed at the end. A mention
 * is an `@` at the start of the draft or after whitespace, followed by a run of
 * non-whitespace text up to the caret; that leaves e-mail addresses and
 * already-inserted `@path` mentions alone.
 */

export interface MentionQuery {
  /** Index of the `@` character in the draft. */
  start: number;
  /** Text typed after `@` up to the caret (may be empty right after `@`). */
  query: string;
}

const MAX_QUERY: number = 120;

function isSpace(ch: string): boolean {
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r';
}

function clampCaret(text: string, caret: number): number {
  if (!Number.isFinite(caret)) {
    return text.length;
  }
  const rounded: number = Math.floor(caret);
  if (rounded < 0) {
    return 0;
  }
  return rounded > text.length ? text.length : rounded;
}

/** The `@query` token ending at the caret, or null when there is none. */
export function activeMentionAt(text: string, caret: number): MentionQuery | null {
  const end: number = clampCaret(text, caret);
  const before: string = text.substring(0, end);
  const at: number = before.lastIndexOf('@');
  if (at < 0) {
    return null;
  }
  if (at > 0 && !isSpace(text.substring(at - 1, at))) {
    return null;
  }
  const query: string = before.substring(at + 1);
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

/** The trailing `@query` token; used when no caret has been reported yet. */
export function activeMention(text: string): MentionQuery | null {
  return activeMentionAt(text, text.length);
}

/**
 * Replace [start, end) with `@path ` and keep the text after `end`, so a
 * mention inserted mid-draft does not swallow the rest of the sentence.
 */
export function replaceMentionRange(
  text: string,
  start: number,
  end: number,
  path: string
): string {
  const from: number = start >= 0 && start <= text.length ? start : text.length;
  const to: number = end >= from && end <= text.length ? end : text.length;
  const rest: string = text.substring(to);
  // The replacement already ends with a space; drop one existing space so a
  // mid-draft mention does not leave a double gap.
  const tail: string = rest.startsWith(' ') ? rest.substring(1) : rest;
  return text.substring(0, from) + '@' + path + ' ' + tail;
}

/** Replace the active token with `@path ` so the next word starts cleanly. */
export function replaceMention(text: string, start: number, path: string): string {
  return replaceMentionRange(text, start, text.length, path);
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
