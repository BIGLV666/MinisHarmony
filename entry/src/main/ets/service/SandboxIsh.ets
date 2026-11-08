import { childProcessManager, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, zlib } from '@kit.BasicServicesKit';

/**
 * Drives the iSH-based on-device Linux sandbox.
 *
 * The native child (entry/src/main/cpp/ish/sandbox_ish.cpp) boots the iSH
 * ARM64 kernel against a fakefs rootfs, runs `/bin/sh -c <command>`, and
 * writes stdout/stderr plus a final `[sandbox exit=...]` line to a file we
 * poll.
 *
 * The rootfs ships inside the HAP as rawfile/ish-rootfs.zip and is extracted
 * into the app's files directory on first use. Keeping it in app storage
 * avoids SELinux denials on /data/local/tmp, and the app owns every file the
 * guest needs to write.
 */
export class SandboxIsh {
  private static readonly ARCHIVE: string = 'ish-rootfs.zip';
  private static readonly ROOTFS_DIR: string = 'ish-rootfs';
  private static readonly LEGACY_ROOTFS: string = '/data/local/tmp/minis-ish-rootfs';
  private static readonly MARKER: string = '[sandbox exit=';
  private static readonly TIMEOUT_MARKER: string = '[sandbox timeout';
  /** Guest-side limit, written into the request. */
  private static readonly GUEST_TIMEOUT_MS: number = 60000;
  /** App-side ceiling: guest timeout plus kernel boot and scheduling slack. */
  private static readonly POLL_TIMEOUT_MS: number = 150000;

  /** Returns the app-private rootfs, extracting the bundled archive once. */
  private static async ensureRootfs(context: common.UIAbilityContext): Promise<string> {
    const local: string = context.filesDir + '/' + SandboxIsh.ROOTFS_DIR;
    if (SandboxIsh.hasMetaDb(local)) {
      return local;
    }
    const archivePath: string = context.filesDir + '/ish-rootfs.zip';
    const staging: string = context.filesDir + '/' + SandboxIsh.ROOTFS_DIR + '-staging';
    const archive: Uint8Array = await context.resourceManager.getRawFileContent(SandboxIsh.ARCHIVE);
    const copy: ArrayBuffer = archive.buffer.slice(archive.byteOffset,
      archive.byteOffset + archive.byteLength);
    if (!SandboxIsh.writeBuffer(archivePath, copy)) {
      throw new Error('无法写入 rootfs 压缩包');
    }
    // Extract to a fresh staging directory so a failed or interrupted unzip
    // never leaves a half-valid rootfs behind. decompressFile requires the
    // destination directory to exist already (otherwise 900002).
    SandboxIsh.removeTree(staging);
    fileIo.mkdirSync(staging, true);
    await zlib.decompressFile(archivePath, staging);
    SandboxIsh.remove(archivePath);
    if (!SandboxIsh.hasMetaDb(staging)) {
      SandboxIsh.removeTree(staging);
      throw new Error('解压后缺少 meta.db');
    }
    SandboxIsh.removeTree(local);
    fileIo.renameSync(staging, local);
    return local;
  }

  static async run(context: common.UIAbilityContext, command: string): Promise<string> {
    let rootfs: string = '';
    try {
      rootfs = await SandboxIsh.ensureRootfs(context);
    } catch (e) {
      const error: Error = e as Error;
      if (SandboxIsh.hasMetaDb(SandboxIsh.LEGACY_ROOTFS)) {
        // Diagnostic fallback for a rootfs pushed with hdc while developing.
        rootfs = SandboxIsh.LEGACY_ROOTFS;
      } else {
        return '沙箱根文件系统准备失败：' + error.message;
      }
    }

    const requestPath: string = context.filesDir + '/ish-request.txt';
    const outputPath: string = context.filesDir + '/ish-output.txt';
    SandboxIsh.remove(outputPath);

    // The native parser reads one key=value per line, so flatten newlines in
    // the command into shell separators for now.
    const flat: string = command.replace(/\r?\n/g, '; ');
    // Have the shell itself report completion. When the guest's PID 1 exits,
    // iSH tears the whole native process down, so the harness never gets to
    // append its own `[sandbox exit=...]` line (observed on device: full
    // output, no marker). Printing it from the command guarantees the UI sees
    // a completion line for anything that returns to the shell.
    const wrapped: string = flat +
      '; __minis_status=$?; printf "\\n[sandbox exit=%d]\\n" "$__minis_status"';
    // The guest timeout must stay well inside the app-side poll window: booting
    // the fakefs kernel on a tablet is not instant, and if the app gives up
    // first the user sees a false "did not finish" even though the command ran.
    const request: string = 'rootfs=' + rootfs + '\n' +
      'output=' + outputPath + '\n' +
      'timeout_ms=' + SandboxIsh.GUEST_TIMEOUT_MS.toString() + '\n' +
      'command=' + wrapped + '\n';
    if (!SandboxIsh.writeText(requestPath, request)) {
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

    const deadline: number = Date.now() + SandboxIsh.POLL_TIMEOUT_MS;
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
      const seconds: number = Math.round(SandboxIsh.POLL_TIMEOUT_MS / 1000);
      return '沙箱在 ' + seconds.toString() + ' 秒内没有报告结束（命令可能仍在运行），' +
        '已收到的输出：\n' + partial;
    }
    return '沙箱没有产生输出，可能是原生子进程被系统拒绝或内核启动失败。';
  }

  private static hasMetaDb(dir: string): boolean {
    try {
      return fileIo.accessSync(dir + '/meta.db');
    } catch (e) {
      return false;
    }
  }

  private static writeText(path: string, text: string): boolean {
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

  private static writeBuffer(path: string, data: ArrayBuffer): boolean {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE |
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, data);
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

  private static removeTree(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        return;
      }
      if (!fileIo.statSync(path).isDirectory()) {
        fileIo.unlinkSync(path);
        return;
      }
      const names: string[] = fileIo.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        SandboxIsh.removeTree(path + '/' + names[i]);
      }
      fileIo.rmdirSync(path);
    } catch (e) {
      // Best effort: extraction overwrites or renames over stale content.
    }
  }

  private static sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }
}
