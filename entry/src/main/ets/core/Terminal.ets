/**
 * Terminal output cleanup for `shell_execute`, mirroring OpenMinis'
 * TerminalSanitizer: shell tools, package managers and build systems emit
 * ANSI colours and `\r` progress rewrites that are noise to the model, and
 * their most useful lines (the error) are usually at the end, so plain
 * head truncation throws away exactly what the model needs.
 *
 * Pure functions with no ArkUI/ohos imports so scripts/test-core.mjs can run
 * them under Node.
 */

/**
 * Ceiling applied before the multi-pass rewrite. Sanitising only ever shrinks
 * text, so a larger input keeps far more than the final shell cap while the
 * intermediate allocations stay bounded.
 */
const PRE_SANITIZE_MAX_CHARS: number = 400000;

const ESC_CODE: number = 27;

/**
 * CSI sequences (colours, cursor movement), OSC sequences (titles, hyperlinks),
 * charset designators and two-char escapes. Anything left over is removed by
 * the control-character pass.
 */
const ANSI_SEQUENCE: RegExp =
  /\x1B\[[0-9;?]*[ -\/]*[@-~]|\x1B\][^\x07]*(?:\x07|\x1B\\)|\x1B[()][0-2AB]|\x1B[A-Za-z]/g;

/**
 * Truncate to `max` chars keeping both ends.
 *
 * Unlike a head-only cut this preserves the tail of a build log, where the
 * compiler prints the failing file and error.
 */
export function truncateMiddle(text: string, max: number): string {
  if (max <= 0 || text.length <= max) {
    return text;
  }
  const keepEach: number = Math.floor(max / 2);
  const head: string = text.substring(0, keepEach);
  const tail: string = text.substring(text.length - keepEach);
  const omitted: number = text.length - keepEach * 2;
  return head + '\n\n[... ' + omitted.toString() + ' characters omitted ...]\n\n' + tail;
}

/** Length of the escape sequence starting at `index`, or 0 if none. */
function escapeLength(text: string, index: number): number {
  if (text.charCodeAt(index) !== ESC_CODE) {
    return 0;
  }
  const next: number = text.charCodeAt(index + 1);
  if (next === 91) { // '['
    let j: number = index + 2;
    while (j < text.length) {
      const code: number = text.charCodeAt(j);
      // Final byte of a CSI sequence is 0x40..0x7E.
      if (code >= 64 && code <= 126) {
        return j - index + 1;
      }
      j++;
    }
    return text.length - index;
  }
  if (next === 93 || next === 80 || next === 94 || next === 95) { // ']' 'P' '^' '_'
    let j: number = index + 2;
    while (j < text.length) {
      const code: number = text.charCodeAt(j);
      if (code === 7) { // BEL
        return j - index + 1;
      }
      if (code === ESC_CODE && text.charCodeAt(j + 1) === 92) { // ESC '\'
        return j - index + 2;
      }
      j++;
    }
    return text.length - index;
  }
  if (next === 40 || next === 41) { // '(' ')'
    return 3;
  }
  return 2;
}

/** `ESC[<param>K`: 0/empty = cursor to end, 1 = start to cursor, 2 = whole line. */
function eraseInLine(line: string[], cursor: number, param: string): void {
  if (param === '' || param === '0') {
    if (cursor < line.length) {
      line.length = cursor;
    }
    return;
  }
  if (param === '1') {
    const last: number = Math.min(cursor, line.length - 1);
    for (let i = 0; i <= last; i++) {
      line[i] = ' ';
    }
    return;
  }
  if (param === '2') {
    const keep: number = Math.min(cursor, line.length);
    line.length = keep;
    for (let i = 0; i < keep; i++) {
      line[i] = ' ';
    }
  }
}

/**
 * Simulate a terminal line that contains `\r`: the cursor returns to column 0
 * and later text overwrites earlier text character by character, so
 * `"AAAA\rBB"` renders as `"BBAA"`. Escapes take no columns and `ESC[K`
 * erases to the end of the line, matching what a real terminal shows.
 */
function foldCarriageReturns(text: string): string {
  if (text.indexOf('\r') < 0) {
    return text;
  }
  const lines: string[] = text.split('\n');
  for (let index = 0; index < lines.length; index++) {
    const line: string = lines[index];
    if (line.indexOf('\r') < 0) {
      continue;
    }
    const out: string[] = [];
    let cursor: number = 0;
    let i: number = 0;
    while (i < line.length) {
      const code: number = line.charCodeAt(i);
      if (code === 13) { // '\r'
        cursor = 0;
        i++;
        continue;
      }
      if (code === ESC_CODE) {
        const length: number = escapeLength(line, i);
        if (length >= 3 && line.charCodeAt(i + 1) === 91 &&
          line.charCodeAt(i + length - 1) === 75) { // ESC[...K
          eraseInLine(out, cursor, line.substring(i + 2, i + length - 1));
        }
        i += length > 0 ? length : 1;
        continue;
      }
      const char: string = line.charAt(i);
      if (code < 32 && char !== '\t') {
        i++;
        continue;
      }
      if (cursor < out.length) {
        out[cursor] = char;
      } else {
        out.push(char);
      }
      cursor++;
      i++;
    }
    lines[index] = out.join('');
  }
  return lines.join('\n');
}

/** Drop remaining control bytes, keeping newline and tab. */
function dropControlChars(text: string): string {
  const kept: string[] = [];
  for (let i = 0; i < text.length; i++) {
    const char: string = text.charAt(i);
    const code: number = text.charCodeAt(i);
    if (char === '\n' || char === '\t' || code >= 32) {
      kept.push(char);
    }
  }
  return kept.join('');
}

/**
 * Clean shell output: fold `\r` overwrites, strip ANSI/OSC escapes and
 * control bytes, then collapse runs of blank lines. Leading and trailing
 * whitespace is trimmed.
 */
export function sanitizeTerminal(raw: string): string {
  if (raw.length === 0) {
    return raw;
  }
  const pre: string = truncateMiddle(raw, PRE_SANITIZE_MAX_CHARS);
  const folded: string = foldCarriageReturns(pre);
  const stripped: string = folded.replace(ANSI_SEQUENCE, '');
  const cleaned: string = dropControlChars(stripped);
  return cleaned.replace(/\n{3,}/g, '\n\n').trim();
}
