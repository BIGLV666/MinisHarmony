import { childProcessManager, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Drives the iSH-based on-device Linux sandbox.
 *
 * The native child (entry/src/main/cpp/ish/sandbox_ish.cpp) boots the iSH
 * ARM64 kernel against a fakefs rootfs, runs `/bin/sh -c <command>`, and
 * writes stdout/stderr plus a final `[sandbox exit=...]` line to a file we
 * poll. The rootfs currently lives in /data/local/tmp so it can be updated
 * with hdc while the sandbox is being brought up; once the boot path is
 * stable it moves into the app's files directory.
 */
export class SandboxIsh {
  private static readonly ROOTFS: string = '/data/local/tmp/minis-ish-rootfs';
  private static readonly MARKER: string = '[sandbox exit=';
  private static readonly TIMEOUT_MARKER: string = '[sandbox timeout';

  static rootfsReady(): boolean {
    try {
      return fileIo.accessSync(SandboxIsh.ROOTFS + '/meta.db');
    } catch (e) {
      return false;
    }
  }

  static async run(context: common.UIAbilityContext, command: string): Promise<string> {
    if (!SandboxIsh.rootfsReady()) {
      return '沙箱根文件系统不存在：' + SandboxIsh.ROOTFS + '\n' +
        '请先用 hdc 推送 Alpine rootfs。';
    }
    const requestPath: string = context.filesDir + '/ish-request.txt';
    const outputPath: string = context.filesDir + '/ish-output.txt';
    SandboxIsh.remove(outputPath);

    // The native parser reads one key=value per line, so flatten newlines in
    // the command into shell separators for now.
    const flat: string = command.replace(/\r?\n/g, '; ');
    const request: string = 'rootfs=' + SandboxIsh.ROOTFS + '\n' +
      'output=' + outputPath + '\n' +
      'timeout_ms=30000\n' +
      'command=' + flat + '\n';
    if (!SandboxIsh.write(requestPath, request)) {
      return '无法写入沙箱请求文件：' + requestPath;
    }

    try {
      await childProcessManager.startNativeChildProcess(
        'libishsandbox.so:Main',
        { entryParams: requestPath }
      );
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return '沙箱子进程启动失败：' + error.code.toString() + ' ' + error.message;
    }

    const deadline: number = Date.now() + 45000;
    while (Date.now() < deadline) {
      const text: string = SandboxIsh.read(outputPath);
      if (text.indexOf(SandboxIsh.MARKER) >= 0 ||
          text.indexOf(SandboxIsh.TIMEOUT_MARKER) >= 0) {
        return text;
      }
      await SandboxIsh.sleep(150);
    }
    const partial: string = SandboxIsh.read(outputPath);
    if (partial.length > 0) {
      return '沙箱未在 45 秒内结束，已收到的输出：\n' + partial;
    }
    return '沙箱没有产生输出，可能是原生子进程被系统拒绝或内核启动失败。';
  }

  private static write(path: string, text: string): boolean {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE |
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, text);
      fileIo.closeSync(file);
      return true;
    } catch (e) {
      return false;
    }
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
      // A stale output file is harmless; the native side truncates it.
    }
  }

  private static sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }
}
