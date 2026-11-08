import { childProcessManager, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { MAX_COMMAND_BYTES, SandboxMarker, commandPayload, commandTooLong, findSandboxMarker,
  sandboxRequestPayload } from '../core/SandboxProtocol';
import { t } from '../core/I18n';

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
  /** Host directory mounted at /var/minis/attachments. */
  attachments: string;
  /** Host directory mounted at /var/minis/skills. */
  skills: string;
}

export interface SandboxRunResult {
  output: string;
  exitCode: number;
  timedOut: boolean;
  /** Non-empty when the sandbox could not run the command at all. */
  error: string;
}

/** What the settings page can show without booting anything. */
export interface SandboxStatus {
  /** The rootfs has been extracted and carries the current version. */
  ready: boolean;
  version: string;
  /** Bytes occupied by the extracted rootfs. */
  bytes: number;
  /** A daemon is alive, or a command is in flight. */
  running: boolean;
}

export class SandboxIsh {
  private static readonly ARCHIVE: string = 'ish-rootfs.zip';
  private static readonly ROOTFS_DIR: string = 'ish-rootfs';
  /**
   * Bump whenever rawfile/ish-rootfs.zip changes. An installed app keeps the
   * previously extracted tree, so without this an upgrade would keep running
   * the old rootfs (for example one without Python).
   */
  private static readonly ROOTFS_VERSION: string = '2';
  private static readonly LEGACY_ROOTFS: string = '/data/local/tmp/minis-ish-rootfs';
  private static readonly READY: string = '[sandbox ready]';
  /**
   * Completion detection scans only this much of the output tail; the marker
   * is always the last thing the shell prints. Reading the whole file per
   * 120 ms poll would make a large log quadratic.
   */
  private static readonly TAIL_BYTES: number = 256 * 1024;
  /** What a timed-out command hands back; its last lines hold the error. */
  private static readonly TIMEOUT_TAIL_BYTES: number = 512 * 1024;
  /**
   * The output file is appended to for the daemon's whole life. Rotating at
   * this size costs one kernel restart in a long session instead of hitting
   * the hard stop below and failing a command.
   */
  private static readonly MAX_SESSION_OUTPUT_BYTES: number = 24 * 1024 * 1024;
  /**
   * Hard stop: past this size the daemon is stopped and only the head is
   * returned. cat on a binary must not take the whole app down.
   */
  private static readonly MAX_OUTPUT_BYTES: number = 64 * 1024 * 1024;
  private static readonly HEAD_BYTES: number = 64 * 1024;

  private static started: boolean = false;
  private static startError: string = '';
  private static startFailure: string = '';
  private static consumed: number = 0;
  private static sequence: number = 0;
  private static outputPath: string = '';
  private static commandPath: string = '';
  private static requestPath: string = '';
  private static options: SandboxOptions = { workspace: '', memory: '', attachments: '', skills: '' };
  /** Commands share one shell, so they also share one queue. */
  private static queue: Promise<void> = Promise.resolve();
  private static busy: number = 0;
  /** Bumped by cancel(): an in-flight execute compares it and returns early. */
  private static cancelToken: number = 0;

  /**
   * Run one command. Calls are serialized: the guest has a single shell and a
   * single stdin stream, and interleaving would mix two commands' output.
   */
  static async run(context: common.UIAbilityContext, command: string,
    timeoutMs: number = 300000,
    options: SandboxOptions = { workspace: '', memory: '', attachments: '', skills: '' },
    onProgress?: (text: string) => void): Promise<SandboxRunResult> {
    const previous: Promise<void> = SandboxIsh.queue;
    let release: () => void = () => {
    };
    SandboxIsh.queue = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    SandboxIsh.busy++;
    try {
      return await SandboxIsh.execute(context, command, timeoutMs, options, onProgress);
    } finally {
      SandboxIsh.busy--;
      release();
    }
  }

  /**
   * Abort the command currently running, when the user stops the turn.
   *
   * The guest cannot be interrupted from the host, so the daemon is stopped
   * and the in-flight run returns immediately. Commands still queued are
   * unaffected: they were never fed to this shell and boot a fresh one.
   * The running command is the one the user stopped — the queue is serial,
   * so no background job can be using the shell at the same time.
   */
  static cancel(): void {
    SandboxIsh.cancelToken++;
    if (SandboxIsh.busy > 0) {
      SandboxIsh.stopDaemon();
    }
  }

  /**
   * Report what the settings page needs: whether the rootfs is ready, how
   * large the extracted tree is, and whether the daemon or a command is live.
   */
  static status(context: common.UIAbilityContext): SandboxStatus {
    const dir: string = context.filesDir + '/' + SandboxIsh.ROOTFS_DIR;
    const version: string = SandboxIsh.read(dir + '/.minis-version');
    return {
      ready: SandboxIsh.hasMetaDb(dir) && version === SandboxIsh.ROOTFS_VERSION,
      version: version,
      bytes: SandboxIsh.directorySize(dir),
      running: SandboxIsh.started || SandboxIsh.busy > 0
    };
  }

  /**
   * Delete the extracted rootfs so the next command unpacks it again. Used
   * after a broken extraction or when the user wants a clean system. Refuses
   * while a command runs: removing files under a live guest would only
   * produce I/O errors.
   */
  static async reset(context: common.UIAbilityContext): Promise<boolean> {
    if (SandboxIsh.busy > 0) {
      return false;
    }
    SandboxIsh.stopDaemon();
    // Give the native poll loop a moment to notice id=-1 and exit.
    await SandboxIsh.sleep(400);
    SandboxIsh.removeTree(context.filesDir + '/' + SandboxIsh.ROOTFS_DIR);
    SandboxIsh.sequence = 0;
    return true;
  }

  /** Returns the app-private rootfs, extracting the bundled archive once. */
  private static async ensureRootfs(context: common.UIAbilityContext): Promise<string> {
    const local: string = context.filesDir + '/' + SandboxIsh.ROOTFS_DIR;
    if (SandboxIsh.hasMetaDb(local) &&
      SandboxIsh.read(local + '/.minis-version') === SandboxIsh.ROOTFS_VERSION) {
      return local;
    }
    const archivePath: string = context.filesDir + '/ish-rootfs.zip';
    const staging: string = context.filesDir + '/' + SandboxIsh.ROOTFS_DIR + '-staging';
    const archive: Uint8Array = await context.resourceManager.getRawFileContent(SandboxIsh.ARCHIVE);
    const copy: ArrayBuffer = archive.buffer.slice(archive.byteOffset,
      archive.byteOffset + archive.byteLength);
    if (!SandboxIsh.writeBuffer(archivePath, copy)) {
      throw new Error(t('无法写入 rootfs 压缩包'));
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
      throw new Error(t('解压后缺少 meta.db'));
    }
    // The marker lives beside data/ and meta.db; fakefs never sees it.
    SandboxIsh.writeText(staging + '/.minis-version', SandboxIsh.ROOTFS_VERSION);
    SandboxIsh.removeTree(local);
    fileIo.renameSync(staging, local);
    return local;
  }

  private static async execute(context: common.UIAbilityContext, command: string,
    timeoutMs: number, options: SandboxOptions,
    onProgress?: (text: string) => void): Promise<SandboxRunResult> {
    const token: number = SandboxIsh.cancelToken;
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
        return SandboxIsh.failed(t('沙箱根文件系统准备失败：') + error.message);
      }
    }

    const readyError: string = await SandboxIsh.ensureDaemon(context, rootfs, token);
    if (readyError.length > 0) {
      return SandboxIsh.failed(readyError);
    }
    // The user may have stopped while the kernel was booting.
    if (SandboxIsh.cancelToken !== token) {
      SandboxIsh.stopDaemon();
      return { output: '', exitCode: -1, timedOut: false, error: t('命令已取消') };
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
    let lastSize: number = -1;
    let lastProgress: number = 0;
    while (Date.now() < deadline) {
      if (SandboxIsh.cancelToken !== token) {
        return { output: '', exitCode: -1, timedOut: false, error: t('命令已取消') };
      }
      const size: number = SandboxIsh.fileSize(SandboxIsh.outputPath);
      if (size > SandboxIsh.MAX_OUTPUT_BYTES) {
        const head: string = SandboxIsh.readHead(SandboxIsh.outputPath);
        SandboxIsh.stopDaemon();
        return {
          output: head,
          exitCode: -1,
          timedOut: false,
          error: t('命令输出超过 64 MB，沙箱已停止；上面是开头部分')
        };
      }
      if (size !== lastSize) {
        lastSize = size;
        // The marker is the last line the shell prints, so scanning the tail
        // decides completion without loading a multi-megabyte log on every
        // poll. Only when the marker is there is the full text read once.
        const whole: boolean = size <= SandboxIsh.TAIL_BYTES;
        const sample: string = whole
          ? SandboxIsh.read(SandboxIsh.outputPath)
          : SandboxIsh.readTail(SandboxIsh.outputPath, size, SandboxIsh.TAIL_BYTES);
        if (findSandboxMarker(sample, whole ? start : 0, id) !== null) {
          const text: string = whole ? sample : SandboxIsh.read(SandboxIsh.outputPath);
          const marker: SandboxMarker | null = findSandboxMarker(text, start, id);
          if (marker !== null) {
            let output: string = text.substring(start, marker.index);
            if (output.endsWith('\n')) {
              output = output.substring(0, output.length - 1);
            }
            SandboxIsh.consumed = marker.end;
            // The daemon appends to one file for its whole life. Rotate it
            // before it reaches the 64 MB hard stop, so a long session pays
            // one kernel restart instead of failing a command later.
            if (size > SandboxIsh.MAX_SESSION_OUTPUT_BYTES) {
              SandboxIsh.stopDaemon();
            }
            return { output: output, exitCode: marker.code, timedOut: false, error: '' };
          }
        }
        // Live preview for the tool card; throttled so a chatty command does
        // not re-render the message list on every poll.
        if (onProgress !== undefined && Date.now() - lastProgress >= 700) {
          lastProgress = Date.now();
          onProgress(whole ? sample.substring(start) : sample);
        }
      }
      // Large outputs grow in expensive steps; poll them less often.
      await SandboxIsh.sleep(size > 4 * 1024 * 1024 ? 500 : 120);
    }

    // A stuck command cannot be interrupted inside the guest from here. Stop
    // the whole daemon instead; the next call boots a fresh one. Keep what it
    // printed: the last lines before the hang are what the model needs.
    const timeoutSize: number = SandboxIsh.fileSize(SandboxIsh.outputPath);
    let partial: string = '';
    if (timeoutSize > SandboxIsh.TIMEOUT_TAIL_BYTES) {
      partial = t('（输出过长，仅保留末尾部分）\n') +
        SandboxIsh.readTail(SandboxIsh.outputPath, timeoutSize, SandboxIsh.TIMEOUT_TAIL_BYTES);
    } else {
      const text: string = SandboxIsh.read(SandboxIsh.outputPath);
      partial = text.length > start ? text.substring(start) : '';
    }
    SandboxIsh.stopDaemon();
    return {
      output: partial,
      exitCode: -1,
      timedOut: true,
      error: t('命令超过 ') + Math.round(timeoutMs / 1000).toString() + t(' 秒未结束，沙箱已重启')
    };
  }

  private static failed(message: string): SandboxRunResult {
    return { output: '', exitCode: -1, timedOut: false, error: message };
  }

  /** Boot the daemon once and wait for its readiness line. */
  private static async ensureDaemon(context: common.UIAbilityContext,
    rootfs: string, token: number): Promise<string> {
    if (SandboxIsh.started) {
      return '';
    }
    const dir: string = context.filesDir;
    SandboxIsh.outputPath = dir + '/ish-daemon-output.txt';
    SandboxIsh.commandPath = dir + '/ish-daemon-command.txt';
    SandboxIsh.requestPath = dir + '/ish-daemon-request.txt';
    // realfs mounts fail on a missing host directory; create both up front so
    // a fresh install (no memory yet) still gets its mounts.
    SandboxIsh.ensureDirectory(SandboxIsh.options.workspace);
    SandboxIsh.ensureDirectory(SandboxIsh.options.memory);
    SandboxIsh.ensureDirectory(SandboxIsh.options.attachments);
    SandboxIsh.ensureDirectory(SandboxIsh.options.skills);
    // A previous daemon may still be alive (a timeout or reset happened while
    // this call was queued). Tell it to stop and give its 80 ms poll loop time
    // to see the request; deleting the command file first would strand it.
    SandboxIsh.stopDaemon();
    await SandboxIsh.sleep(300);
    SandboxIsh.remove(SandboxIsh.outputPath);
    SandboxIsh.remove(SandboxIsh.commandPath);
    SandboxIsh.startError = '';
    SandboxIsh.startFailure = '';
    SandboxIsh.consumed = 0;

    const request: string = sandboxRequestPayload(rootfs, SandboxIsh.outputPath,
      SandboxIsh.commandPath, SandboxIsh.options.workspace, SandboxIsh.options.memory,
      SandboxIsh.options.attachments, SandboxIsh.options.skills);
    if (!SandboxIsh.writeText(SandboxIsh.requestPath, request)) {
      return t('无法写入沙箱请求文件：') + SandboxIsh.requestPath;
    }

    try {
      // Do not await completion: this promise belongs to the child's start,
      // and the daemon itself lives until the app does.
      childProcessManager.startNativeChildProcess(
        'libishsandbox.so:Main',
        { entryParams: SandboxIsh.requestPath }
      ).catch((error: BusinessError) => {
        SandboxIsh.startError = t('沙箱子进程启动失败：') + error.code.toString() +
          ' ' + error.message;
      });
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return t('沙箱子进程启动失败：') + error.message;
    }

    const deadline: number = Date.now() + 90000;
    while (Date.now() < deadline) {
      if (SandboxIsh.cancelToken !== token) {
        // The user stopped while the kernel was booting; make sure the child
        // that may have started anyway is told to exit.
        SandboxIsh.stopDaemon();
        return t('命令已取消');
      }
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
    return t('沙箱在 90 秒内没有启动完成');
  }

  /** Write `id=<n>\n<command>` atomically so the harness never reads half. */
  private static writeCommand(id: number, command: string): string {
    const temporary: string = SandboxIsh.commandPath + '.tmp';
    const body: string = commandPayload(id, command);
    // The harness reads at most MAX_COMMAND_BYTES; a longer command would be
    // silently ignored and the caller would wait until the timeout.
    if (commandTooLong(body)) {
      return t('命令过长（上限 ') + MAX_COMMAND_BYTES.toString() + t(' 字节）');
    }
    if (!SandboxIsh.writeText(temporary, body)) {
      return t('无法写入沙箱命令文件');
    }
    try {
      fileIo.renameSync(temporary, SandboxIsh.commandPath);
      return '';
    } catch (e) {
      const error: Error = e as Error;
      return t('无法提交沙箱命令：') + error.message;
    }
  }

  private static stopDaemon(): void {
    SandboxIsh.started = false;
    SandboxIsh.consumed = 0;
    if (SandboxIsh.commandPath.length > 0) {
      SandboxIsh.writeText(SandboxIsh.commandPath, 'id=-1\nstop');
    }
  }

  static formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return bytes.toString() + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(1) + ' KB';
    }
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  private static directorySize(path: string): number {
    let total: number = 0;
    try {
      if (!fileIo.accessSync(path)) {
        return 0;
      }
      const stat = fileIo.statSync(path);
      if (!stat.isDirectory()) {
        return stat.size;
      }
      const names: string[] = fileIo.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        total += SandboxIsh.directorySize(path + '/' + names[i]);
      }
    } catch (e) {
      // A partially removed tree still yields the bytes counted so far.
    }
    return total;
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

  private static ensureDirectory(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (e) {
      // The mount will report the failure through [sandbox warn].
    }
  }

  private static fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  /** Last `maxBytes` of the output, decoded; a marker split at the boundary is fine. */
  private static readTail(path: string, size: number, maxBytes: number): string {
    const length: number = Math.min(size, maxBytes);
    if (length <= 0) {
      return '';
    }
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(length);
        const read: number = fileIo.readSync(file.fd, buffer, {
          offset: size - length,
          length: length
        });
        const bytes: Uint8Array = new Uint8Array(buffer, 0, read);
        return util.TextDecoder.create('utf-8').decodeToString(bytes);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      return '';
    }
  }

  /** First HEAD_BYTES of the output, decoded; used for the oversize guard. */
  private static readHead(path: string): string {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(SandboxIsh.HEAD_BYTES);
        const read: number = fileIo.readSync(file.fd, buffer);
        const bytes: Uint8Array = new Uint8Array(buffer, 0, read);
        return util.TextDecoder.create('utf-8').decodeToString(bytes);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      return '';
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
