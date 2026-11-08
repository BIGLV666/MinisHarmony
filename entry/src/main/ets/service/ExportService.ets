import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { AppSettings, StoredSession } from '../core/Types';
import { exportFileName, exportMarkdown } from '../core/MarkdownExport';
import {
  parseSessionsExport,
  sessionBundleFileName,
  sessionBundleJson,
  sessionExportJson,
  sessionJsonFileName
} from '../core/SessionExport';
import {
  backupFileName,
  backupJson,
  parseBackupSettings
} from '../core/Backup';
import { encryptedBackupFileName } from '../core/BackupCrypto';
import { encryptBackupText } from './BackupCrypto';

const MAX_IMPORT_BYTES: number = 16 * 1024 * 1024;
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

export interface ExportOutcome {
  ok: boolean;
  message: string;
}

/**
 * Ask for a destination through the system document picker, then write the
 * text to the returned URI. No broad storage permission is needed.
 */
export async function saveText(
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
  /** Non-null when the file was a whole-library backup. */
  settings: AppSettings | null;
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

export interface PickedImport {
  ok: boolean;
  message: string;
  text: string;
}

/**
 * Ask for a JSON file and read its text. Parsing is separate so the caller can
 * decrypt an encrypted backup (which needs a password prompt) before import.
 */
export async function pickImportText(
  context: common.UIAbilityContext
): Promise<PickedImport> {
  try {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['JSON|.json'];
    const documentPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      return { ok: false, message: '已取消导入', text: '' };
    }
    const stat = fs.statSync(uris[0]);
    if (stat.size <= 0) {
      return { ok: false, message: '文件是空的', text: '' };
    }
    if (stat.size > MAX_IMPORT_BYTES) {
      return { ok: false, message: '文件超过 16 MB，拒绝导入', text: '' };
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return {
      ok: true,
      message: '',
      text: decoder.decodeToString(new Uint8Array(buffer))
    };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: '导入失败：' + error.message, text: '' };
  }
}

/**
 * Parse already-read text into fresh sessions. Accepts a single-session
 * export, a multi-session bundle and a decrypted whole-library backup.
 */
export function importSessionsText(
  text: string,
  newId: () => string
): BundleImportOutcome {
  const parsed = parseSessionsExport(text, newId, new Date());
  if (!parsed.ok || parsed.sessions.length === 0) {
    return { ok: false, message: parsed.error, sessions: [], settings: null };
  }
  const settings: AppSettings | null = parseBackupSettings(text);
  const count: number = parsed.sessions.length;
  return {
    ok: true,
    message: settings !== null
      ? '已恢复备份：' + count.toString() + ' 个会话与设置'
      : (count === 1 ? '已导入会话' : '已导入 ' + count.toString() + ' 个会话'),
    sessions: parsed.sessions,
    settings: settings
  };
}

/** Pick, read and parse a plain (unencrypted) export in one step. */
export async function importSessionsJson(
  context: common.UIAbilityContext,
  newId: () => string
): Promise<BundleImportOutcome> {
  const picked: PickedImport = await pickImportText(context);
  if (!picked.ok) {
    return { ok: false, message: picked.message, sessions: [], settings: null };
  }
  return importSessionsText(picked.text, newId);
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

/** Whole-library backup: all sessions plus settings with secrets removed. */
export async function saveBackup(
  context: common.UIAbilityContext,
  settings: AppSettings,
  sessions: StoredSession[]
): Promise<ExportOutcome> {
  const now: Date = new Date();
  return saveText(
    context,
    backupFileName(now),
    'JSON|.json',
    backupJson(settings, sessions, now),
    '已导出 ' + sessions.length.toString() + ' 个会话与设置（不含密钥）'
  );
}

/**
 * Whole-library backup sealed with a user password (AES-256-GCM, key derived
 * with PBKDF2). The password never leaves the device.
 */
export async function saveEncryptedBackup(
  context: common.UIAbilityContext,
  settings: AppSettings,
  sessions: StoredSession[],
  password: string
): Promise<ExportOutcome> {
  const now: Date = new Date();
  try {
    const plain: string = backupJson(settings, sessions, now);
    const sealed: string = await encryptBackupText(plain, password, now);
    return await saveText(
      context,
      encryptedBackupFileName(now),
      'JSON|.json',
      sealed,
      '已导出加密备份：' + sessions.length.toString() + ' 个会话与设置'
    );
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: '加密失败：' + error.message };
  }
}
