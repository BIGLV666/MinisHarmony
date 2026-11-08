import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { StoredSession } from '../core/Types';
import { exportFileName, exportMarkdown } from '../core/MarkdownExport';
import {
  parseSessionsExport,
  sessionBundleFileName,
  sessionBundleJson,
  sessionExportJson,
  sessionJsonFileName
} from '../core/SessionExport';

const MAX_IMPORT_BYTES: number = 8 * 1024 * 1024;
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

export interface ExportOutcome {
  ok: boolean;
  message: string;
}

/**
 * Ask for a destination through the system document picker, then write the
 * text to the returned URI. No broad storage permission is needed.
 */
async function saveText(
  context: common.UIAbilityContext,
  fileName: string,
  suffixChoice: string,
  text: string,
  successMessage: string
): Promise<ExportOutcome> {
  try {
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = [suffixChoice];
    const documentPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.save(options);
    if (uris.length === 0) {
      return { ok: false, message: '已取消导出' };
    }
    const file = fs.openSync(
      uris[0],
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
    return { ok: true, message: successMessage };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: '导出失败：' + error.message };
  }
}

export async function saveSessionMarkdown(
  context: common.UIAbilityContext,
  session: StoredSession
): Promise<ExportOutcome> {
  const now: Date = new Date();
  return saveText(
    context,
    exportFileName(session.meta.title, now),
    'Markdown|.md',
    exportMarkdown(session, now),
    '已导出 Markdown'
  );
}

export interface BundleImportOutcome {
  ok: boolean;
  message: string;
  sessions: StoredSession[];
}

/** Multi-session export: one JSON file with a `sessions` array. */
export async function saveSessionBundle(
  context: common.UIAbilityContext,
  sessions: StoredSession[]
): Promise<ExportOutcome> {
  if (sessions.length === 0) {
    return { ok: false, message: '没有选中会话' };
  }
  const now: Date = new Date();
  return saveText(
    context,
    sessionBundleFileName(now),
    'JSON|.json',
    sessionBundleJson(sessions, now),
    '已导出 ' + sessions.length.toString() + ' 个会话'
  );
}

/**
 * Read a JSON file chosen by the user and parse it into fresh sessions.
 * Accepts both a single-session export and a multi-session bundle. Parsing is
 * pure and defensive; this function only does file I/O.
 */
export async function importSessionsJson(
  context: common.UIAbilityContext,
  newId: () => string
): Promise<BundleImportOutcome> {
  try {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['JSON|.json'];
    const documentPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      return { ok: false, message: '已取消导入', sessions: [] };
    }
    const stat = fs.statSync(uris[0]);
    if (stat.size <= 0) {
      return { ok: false, message: '文件是空的', sessions: [] };
    }
    if (stat.size > MAX_IMPORT_BYTES) {
      return { ok: false, message: '文件超过 8 MB，拒绝导入', sessions: [] };
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    const text: string = decoder.decodeToString(new Uint8Array(buffer));
    const parsed = parseSessionsExport(text, newId, new Date());
    if (!parsed.ok || parsed.sessions.length === 0) {
      return { ok: false, message: parsed.error, sessions: [] };
    }
    return {
      ok: true,
      message: parsed.sessions.length === 1
        ? '已导入会话'
        : '已导入 ' + parsed.sessions.length.toString() + ' 个会话',
      sessions: parsed.sessions
    };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: '导入失败：' + error.message, sessions: [] };
  }
}

export async function saveSessionJson(
  context: common.UIAbilityContext,
  session: StoredSession
): Promise<ExportOutcome> {
  const now: Date = new Date();
  return saveText(
    context,
    sessionJsonFileName(session.meta.title, now),
    'JSON|.json',
    sessionExportJson(session, now),
    '已导出 JSON'
  );
}
