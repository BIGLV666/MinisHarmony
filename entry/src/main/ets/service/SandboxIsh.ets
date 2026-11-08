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
    // never leaves a half-valid rootfs behind.
    SandboxIsh.removeTree(staging);
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
    const request: string = 'rootfs=' + rootfs + '\n' +
      'output=' + outputPath + '\n' +
      'timeout_ms=30000\n' +
      'command=' + flat + '\n';
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
