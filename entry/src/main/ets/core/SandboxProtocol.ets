/**
 * Wire format shared by the ArkTS sandbox client and the native harness
 * (entry/src/main/cpp/ish/sandbox_ish.cpp).
 *
 * The daemon boots an iSH kernel once and keeps `/bin/sh` alive as PID 1.
 * Commands and their results travel through files, so both sides must agree
 * exactly on the framing; keeping it here makes the parser testable on the
 * host without booting a kernel or a tablet.
 *
 * Pure: no ArkUI/ohos imports.
 */

/** Prefix the guest shell prints after each command. */
export const SANDBOX_MARKER_PREFIX: string = '[sandbox exit=';

/**
 * The harness reads at most 16 KB per command file. A longer command would be
 * truncated or ignored and the caller would wait until its timeout, so the
 * client rejects it up front instead.
 */
export const MAX_COMMAND_BYTES: number = 16000;

/** A parsed `[sandbox exit=<code> id=<id>]` marker. */
export interface SandboxMarker {
  /** Index of the opening bracket. */
  index: number;
  /** Index just past the closing bracket. */
  end: number;
  /** Exit status the shell reported. */
  code: number;
}

/**
 * Find the completion marker for `id` at or after `from`.
 *
 * Markers for other ids are skipped: a late marker from a command whose
 * caller gave up (timeout or cancel) must not be mistaken for the current
 * one. An unterminated marker means the line is still arriving; the caller
 * polls again rather than settling early.
 */
export function findSandboxMarker(text: string, from: number, id: number): SandboxMarker | null {
  const tag: string = 'id=' + id.toString() + ']';
  let search: number = from < 0 ? 0 : from;
  while (search < text.length) {
    const index: number = text.indexOf(SANDBOX_MARKER_PREFIX, search);
    if (index < 0) {
      return null;
    }
    const end: number = text.indexOf(']', index);
    if (end < 0) {
      return null;
    }
    const content: string = text.substring(index, end + 1);
    if (content.indexOf(tag) >= 0) {
      const equals: number = content.indexOf('=');
      const space: number = content.indexOf(' ', equals);
      const digits: string = content.substring(equals + 1,
        space > 0 ? space : content.length);
      const code: number = parseInt(digits, 10);
      return { index: index, end: end + 1, code: isNaN(code) ? -1 : code };
    }
    search = index + 1;
  }
  return null;
}

/**
 * UTF-8 byte length without encoding. The harness buffer is measured in
 * bytes while JavaScript strings count UTF-16 units, so a command of Chinese
 * text is three times longer than `length` suggests.
 */
export function utf8ByteLength(text: string): number {
  let bytes: number = 0;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF) {
      // Surrogate pair: four bytes for both units.
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/** Command file body: `id=<n>\n<command>`, written atomically by the app. */
export function commandPayload(id: number, command: string): string {
  return 'id=' + id.toString() + '\n' + command;
}

/** True when the harness would refuse (or truncate) this command file. */
export function commandTooLong(payload: string): boolean {
  return utf8ByteLength(payload) > MAX_COMMAND_BYTES;
}

/** One-time daemon request, one `key=value` per line. */
export function sandboxRequestPayload(rootfs: string, output: string, commands: string,
  workspace: string, memory: string, attachments: string, skills: string): string {
  return 'rootfs=' + rootfs + '\n' +
    'output=' + output + '\n' +
    'commands=' + commands + '\n' +
    'workspace=' + workspace + '\n' +
    'memory=' + memory + '\n' +
    'attachments=' + attachments + '\n' +
    'skills=' + skills + '\n';
}
