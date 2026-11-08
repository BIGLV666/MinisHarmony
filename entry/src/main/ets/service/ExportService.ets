import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { StoredSession } from '../core/Types';
import { exportFileName, exportMarkdown } from '../core/MarkdownExport';
import { sessionExportJson, sessionJsonFileName } from '../core/SessionExport';

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
