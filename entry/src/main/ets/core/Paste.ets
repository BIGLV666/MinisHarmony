import { MINIS_WORKSPACE, parseMinisResource } from './MinisResource';

/**
 * A paste above this many characters stops being draft text. It is written to
 * `<workspace>/pasted/` and attached as a file, so the composer stays light and
 * the content travels the same path as any other workspace document. The model
 * sees a short marker with the relative path and can read the file on demand.
 */
export const PASTE_FILE_THRESHOLD: number = 15000;
export const PASTED_DIR: string = 'pasted';

/**
 * The chunk a single edit inserted, when that chunk is over the threshold.
 *
 * TextArea only reports the whole value, so the edited span is recovered by
 * trimming the common prefix and suffix. A paste at the caret leaves the
 * surrounding draft text in place, so this works for start, middle and end
 * insertions alike; a replacement paste yields the replacement text.
 */
export function hugePasteInsertion(before: string, after: string): string {
  if (after.length - before.length <= PASTE_FILE_THRESHOLD) {
    return '';
  }
  const maxPrefix: number = Math.min(before.length, after.length);
  let prefix: number = 0;
  while (prefix < maxPrefix &&
    before.charCodeAt(prefix) === after.charCodeAt(prefix)) {
    prefix++;
  }
  const maxSuffix: number = Math.min(before.length, after.length) - prefix;
  let suffix: number = 0;
  while (suffix < maxSuffix &&
    before.charCodeAt(before.length - 1 - suffix) ===
      after.charCodeAt(after.length - 1 - suffix)) {
    suffix++;
  }
  return after.substring(prefix, after.length - suffix);
}

function pad(value: number, width: number): string {
  let text: string = value.toString();
  while (text.length < width) {
    text = '0' + text;
  }
  return text;
}

/** Local-time file name; milliseconds keep two quick pastes apart. */
export function pasteFileName(at: Date): string {
  return 'Pasted_' + at.getFullYear().toString() + '-' +
    pad(at.getMonth() + 1, 2) + '-' + pad(at.getDate(), 2) + '_' +
    pad(at.getHours(), 2) + pad(at.getMinutes(), 2) + pad(at.getSeconds(), 2) +
    pad(at.getMilliseconds(), 3) + '.txt';
}

export function pastedRelativePath(name: string): string {
  return PASTED_DIR + '/' + name;
}

/** Text part the model and the bubble see instead of the pasted body. */
export function pastePlaceholder(relativePath: string): string {
  return '[粘贴文本] ' + relativePath +
    '（长文本已保存为工作区文件，可用 read_file 读取完整内容）';
}

/** Relative workspace path of a pasted attachment, or '' for anything else. */
export function pasteRelativePath(uri: string): string {
  const resource = parseMinisResource(uri);
  if (resource === null || resource.scope !== MINIS_WORKSPACE ||
    resource.path.indexOf(PASTED_DIR + '/') !== 0) {
    return '';
  }
  return resource.path;
}

/** True when this attachment is a long paste stored in the workspace. */
export function isPastedAttachment(uri: string, mimeType: string): boolean {
  return mimeType === 'text/plain' && pasteRelativePath(uri).length > 0;
}
