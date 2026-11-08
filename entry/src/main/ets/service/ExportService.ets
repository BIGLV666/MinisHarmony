import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { StoredSession } from '../core/Types';
import { exportFileName, exportMarkdown } from '../core/MarkdownExport';

export interface ExportOutcome {
  ok: boolean;
  message: string;
}

/**
 * Render the session to Markdown, then let the user pick a destination through
 * the system document picker. The file is written to the returned URI, so no
 * broad storage permission is needed.
 */
export async function saveSessionMarkdown(
  context: common.UIAbilityContext,
  session: StoredSession
): Promise<ExportOutcome> {
  try {
    const now: Date = new Date();
    const markdown: string = exportMarkdown(session, now);
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [exportFileName(session.meta.title, now)];
    options.fileSuffixChoices = ['Markdown|.md'];
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
      fs.writeSync(file.fd, markdown);
    } finally {
      fs.closeSync(file);
    }
    return { ok: true, message: '已导出 Markdown' };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: '导出失败：' + error.message };
  }
}
