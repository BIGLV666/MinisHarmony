import { childProcessManager, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { t } from '../core/I18n';

/**
 * Runs the native child process probe and returns its plain-text report.
 *
 * The child (entry/src/main/cpp/sandbox_probe.cpp) receives the report path
 * through entryParams, writes the file, then exits. We poll the file because
 * the API only reports the pid, not process exit.
 */
export class SandboxProbe {
  static async run(context: common.UIAbilityContext): Promise<string> {
    const reportPath: string = context.filesDir + '/sandbox-probe.txt';
    SandboxProbe.remove(reportPath);
    try {
      await childProcessManager.startNativeChildProcess(
        'libsandboxprobe.so:Main',
        { entryParams: reportPath }
      );
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return t('原生子进程启动失败：') + error.code.toString() + ' ' + error.message;
    }
    const deadline: number = Date.now() + 15000;
    while (Date.now() < deadline) {
      const text: string = SandboxProbe.read(reportPath);
      if (text.indexOf('probe=done') >= 0) {
        return text;
      }
      await SandboxProbe.sleep(150);
    }
    const partial: string = SandboxProbe.read(reportPath);
    if (partial.length > 0) {
      return t('探针未在 15 秒内结束，已收到的部分结果：\n') + partial;
    }
    return t('探针没有生成报告，可能是原生子进程被系统拒绝或立即退出。');
  }

  private static read(path: string): string {
    try {
      if (!fileIo.accessSync(path)) {
        return '';
      }
      return fileIo.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  private static remove(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      // A stale report is harmless; read() will overwrite it below.
    }
  }

  private static sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }
}
