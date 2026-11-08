import { childProcessManager, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, zlib } from '@kit.BasicServicesKit';

/**
 * Drives the iSH-based on-device Linux sandbox as a persistent daemon.
 *
 * The native child (entry/src/main/cpp/ish/sandbox_ish.cpp) boots the iSH
 * ARM64 kernel once against a fakefs rootfs and keeps one `/bin/sh` alive as
 * PID 1. Commands arrive through a file the app rewrites atomically; the
 * harness feeds each one into the shell's stdin, and the shell appends
 * `[sandbox exit=<code> id=<n>]` when it is done. Because the kernel is booted
 * once, the second command is roughly as fast as the first — booting per call
 * cost around 20 seconds on the tablet.
 *
 * The rootfs ships inside the HAP as rawfile/ish-rootfs.zip and is extracted
 * into the app's files directory on first use. Keeping it in app storage
 * avoids SELinux denials on /data/local/tmp, and the app owns every file the
 * guest needs to write. The workspace and memory directories are mounted into
 * the guest with iSH's realfs, so the shell sees exactly the files the
 * read_file / write_file tools use.
 */
export interface SandboxOptions {
  /** Host directory mounted at /var/minis/workspace. */
  workspace: string;
  /** Host directory mounted at /var/minis/memory. */
  memory: string;
}

export interface SandboxRunResult {
  output: string;
  exitCode: number;
  timedOut: boolean;
  /** Non-empty when the sandbox could not run the command at all. */
  error: string;
}

interface Marker {
  index: number;
  end: number;
  code: number;
}

export class SandboxIsh {
  private static readonly ARCHIVE: string = 'ish-rootfs.zip';
  private static readonly ROOTFS_DIR: string = 'ish-rootfs';
  private static readonly LEGACY_ROOTFS: string = '/data/local/tmp/minis-ish-rootfs';
  private static readonly MARKER: string = '[sandbox exit=';
  private static readonly READY: string = '[sandbox ready]';

  private static started: boolean = false;
  private static startError: string = '';
  private static startFailure: string = '';
  private static consumed: number = 0;
  private static sequence: number = 0;
  private static outputPath: string = '';
  private static commandPath: string = '';
  private static requestPath: string = '';
  private static options: SandboxOptions = { workspace: '', memory: '' };
  /** Commands share one shell, so they also share one queue. */
  private static queue: Promise<void> = Promise.resolve();

  /**
   * Run one command. Calls are serialized: the guest has a single shell and a
   * single stdin stream, and interleaving would mix two commands' output.
   */
  static async run(context: common.UIAbilityContext, command: string,
    timeoutMs: number = 300000,
    options: SandboxOptions = { workspace: '', memory: '' }): Promise<SandboxRunResult> {
    const previous: Promise<void> = SandboxIsh.queue;
    let release: () => void = () => {
    };
    SandboxIsh.queue = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    try {
      return await SandboxIsh.execute(context, command, timeoutMs, options);
    } finally {
      release();
    }
  }

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

  private static async execute(context: common.UIAbilityContext, command: string,
    timeoutMs: number, options: SandboxOptions): Promise<SandboxRunResult> {
    if (SandboxIsh.options.workspace.length === 0) {
      SandboxIsh.options = options;
    }
    let rootfs: string = '';
    try {
      rootfs = await SandboxIsh.ensureRootfs(context);
    } catch (e) {
      const error: Error = e as Error;
      if (SandboxIsh.hasMetaDb(SandboxIsh.LEGACY_ROOTFS)) {
        // Diagnostic fallback for a rootfs pushed with hdc while developing.
        rootfs = SandboxIsh.LEGACY_ROOTFS;
      } else {
        return SandboxIsh.failed('沙箱根文件系统准备失败：' + error.message);
      }
    }

    const readyError: string = await SandboxIsh.ensureDaemon(context, rootfs);
    if (readyError.length > 0) {
      return SandboxIsh.failed(readyError);
    }

    const id: number = ++SandboxIsh.sequence;
    // The app owns the read cursor. It counts characters, not bytes, because
    // readTextSync decodes UTF-8 and the two offsets diverge on Chinese text.
    const start: number = SandboxIsh.consumed;
    const writeError: string = SandboxIsh.writeCommand(id, command);
    if (writeError.length > 0) {
      return SandboxIsh.failed(writeError);
    }

    const deadline: number = Date.now() + Math.max(1000, timeoutMs);
    let text: string = '';
    while (Date.now() < deadline) {
      text = SandboxIsh.read(SandboxIsh.outputPath);
      const marker: Marker | null = SandboxIsh.findMarker(text, start, id);
      if (marker !== null) {
        let output: string = text.substring(start, marker.index);
        if (output.endsWith('\n')) {
          output = output.substring(0, output.length - 1);
        }
        SandboxIsh.consumed = marker.end;
        return { output: output, exitCode: marker.code, timedOut: false, error: '' };
      }
      await SandboxIsh.sleep(120);
    }

    // A stuck command cannot be interrupted inside the guest from here. Stop
    // the whole daemon instead; the next call boots a fresh one.
    text = SandboxIsh.read(SandboxIsh.outputPath);
    let partial: string = text.length > start ? text.substring(start) : '';
    SandboxIsh.stopDaemon();
    return {
      output: partial,
      exitCode: -1,
      timedOut: true,
      error: '命令超过 ' + Math.round(timeoutMs / 1000).toString() + ' 秒未结束，沙箱已重启'
    };
  }

  private static failed(message: string): SandboxRunResult {
    return { output: '', exitCode: -1, timedOut: false, error: message };
  }

  /** Boot the daemon once and wait for its readiness line. */
  private static async ensureDaemon(context: common.UIAbilityContext,
    rootfs: string): Promise<string> {
    if (SandboxIsh.started) {
      return '';
    }
    const dir: string = context.filesDir;
    SandboxIsh.outputPath = dir + '/ish-daemon-output.txt';
    SandboxIsh.commandPath = dir + '/ish-daemon-command.txt';
    SandboxIsh.requestPath = dir + '/ish-daemon-request.txt';
    SandboxIsh.remove(SandboxIsh.outputPath);
    SandboxIsh.remove(SandboxIsh.commandPath);
    SandboxIsh.startError = '';
    SandboxIsh.startFailure = '';
    SandboxIsh.consumed = 0;

    const request: string = 'rootfs=' + rootfs + '\n' +
      'output=' + SandboxIsh.outputPath + '\n' +
      'commands=' + SandboxIsh.commandPath + '\n' +
      'workspace=' + SandboxIsh.options.workspace + '\n' +
      'memory=' + SandboxIsh.options.memory + '\n';
    if (!SandboxIsh.writeText(SandboxIsh.requestPath, request)) {
      return '无法写入沙箱请求文件：' + SandboxIsh.requestPath;
    }

    try {
      // Do not await completion: this promise belongs to the child's start,
      // and the daemon itself lives until the app does.
      childProcessManager.startNativeChildProcess(
        'libishsandbox.so:Main',
        { entryParams: SandboxIsh.requestPath }
      ).catch((error: BusinessError) => {
        SandboxIsh.startError = '沙箱子进程启动失败：' + error.code.toString() +
          ' ' + error.message;
      });
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return '沙箱子进程启动失败：' + error.message;
    }

    const deadline: number = Date.now() + 90000;
    while (Date.now() < deadline) {
      const text: string = SandboxIsh.read(SandboxIsh.outputPath);
      const ready: number = text.indexOf(SandboxIsh.READY);
      if (ready >= 0) {
        SandboxIsh.consumed = ready + SandboxIsh.READY.length;
        SandboxIsh.started = true;
        return '';
      }
      // Any other [sandbox] line is a boot failure; surface it verbatim.
      const failure: number = text.indexOf('[sandbox]');
      if (failure >= 0) {
        SandboxIsh.startFailure = text.substring(failure);
        return SandboxIsh.startFailure;
      }
      if (SandboxIsh.startError.length > 0) {
        return SandboxIsh.startError;
      }
      await SandboxIsh.sleep(200);
    }
    return '沙箱在 90 秒内没有启动完成';
  }

  /** Write `id=<n>\n<command>` atomically so the harness never reads half. */
  private static writeCommand(id: number, command: string): string {
    const temporary: string = SandboxIsh.commandPath + '.tmp';
    const body: string = 'id=' + id.toString() + '\n' + command;
    if (!SandboxIsh.writeText(temporary, body)) {
      return '无法写入沙箱命令文件';
    }
    try {
      fileIo.renameSync(temporary, SandboxIsh.commandPath);
      return '';
    } catch (e) {
      const error: Error = e as Error;
      return '无法提交沙箱命令：' + error.message;
    }
  }

  private static stopDaemon(): void {
    SandboxIsh.started = false;
    SandboxIsh.consumed = 0;
    if (SandboxIsh.commandPath.length > 0) {
      SandboxIsh.writeText(SandboxIsh.commandPath, 'id=-1\nstop');
    }
  }

  /**
   * Find `[sandbox exit=<code> id=<id>]` at or after `from`. Output can arrive
   * in chunks, so a marker without the trailing bracket is simply not there
   * yet and the caller polls again.
   */
  private static findMarker(text: string, from: number, id: number): Marker | null {
    const tag: string = 'id=' + id.toString() + ']';
    let search: number = from;
    while (true) {
      const index: number = text.indexOf(SandboxIsh.MARKER, search);
      if (index < 0) {
        return null;
      }
      const end: number = text.indexOf(']', index);
      if (end < 0) {
        return null;
      }
      const content: string = text.substring(index, end + 1);
      if (content.indexOf(tag) >= 0) {
        const equals: number = content.indexOf('=');
        const space: number = content.indexOf(' ', equals);
        const digits: string = content.substring(equals + 1, space > 0 ? space : content.length);
        const code: number = parseInt(digits, 10);
        return { index: index, end: end + 1, code: isNaN(code) ? -1 : code };
      }
      search = index + 1;
    }
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
