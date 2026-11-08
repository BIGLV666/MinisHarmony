import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { sharedFromWant, isTextualShare } from '../core/SharePayload';

export const PENDING_SHARE_KEY: string = 'pendingShareText';

const MAX_SHARED_FILE: number = 512 * 1024;
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

function readTextFile(uri: string): string {
  try {
    const stat = fs.statSync(uri);
    if (stat.size <= 0 || stat.size > MAX_SHARED_FILE) {
      return '';
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return decoder.decodeToString(new Uint8Array(buffer));
  } catch (e) {
    return '';
  }
}

function looksTextual(uri: string, type: string): boolean {
  if (isTextualShare(type)) {
    return true;
  }
  const lower: string = uri.toLowerCase();
  const suffixes: string[] = ['.txt', '.md', '.json', '.log', '.csv', '.xml', '.yaml', '.yml'];
  for (let i = 0; i < suffixes.length; i++) {
    if (lower.endsWith(suffixes[i])) {
      return true;
    }
  }
  return false;
}

/**
 * Turn a share Want into text. Pure text payloads win; otherwise the first
 * textual file is read (up to 512 KB). Image-only shares return an empty
 * string and are ignored for now.
 */
export async function textFromShare(want: Want): Promise<string> {
  const type: string = want.type !== undefined ? want.type : '';
  const uri: string = want.uri !== undefined ? want.uri : '';
  const content = sharedFromWant(want.parameters, uri, type);
  if (content.text.length > 0) {
    return content.text;
  }
  for (let i = 0; i < content.uris.length; i++) {
    if (!looksTextual(content.uris[i], type)) {
      continue;
    }
    const text: string = readTextFile(content.uris[i]);
    if (text.trim().length > 0) {
      return text;
    }
  }
  return '';
}

/** Called by EntryAbility; the UI picks the value up through AppStorage. */
export async function handleShareWant(want: Want): Promise<void> {
  if (want.action !== undefined && want.action.length > 0 &&
    want.action !== 'ohos.want.action.sendData' &&
    want.action !== 'ohos.want.action.viewData') {
    return;
  }
  const text: string = await textFromShare(want);
  if (text.length > 0) {
    AppStorage.setOrCreate<string>(PENDING_SHARE_KEY, text);
  }
}
