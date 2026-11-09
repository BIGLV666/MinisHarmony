import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ToolResult } from '../core/ToolTypes';
import { sanitizeTerminal, truncateMiddle } from '../core/Terminal';
import { SandboxIsh, SandboxOptions } from './SandboxIsh';
import { t } from '../core/I18n';

/** The model sees the same budget as shell_execute. */
const MAX_RESULT_CHARS: number = 20000;
/** The running card shows the tail of this much output. */
const MAX_PREVIEW_CHARS: number = 4000;
/** OpenMinis defaults to 15 minutes for shell; Python calls are shorter. */
const DEFAULT_TIMEOUT_SECONDS: number = 120;
const MAX_TIMEOUT_SECONDS: number = 900;
const MIN_TIMEOUT_SECONDS: number = 5;
/** A cold daemon boot plus the interpreter start fits comfortably here. */
const START_TIMEOUT_MS: number = 45000;
const KILL_TIMEOUT_MS: number = 15000;
const POLL_MS: number = 25;

interface PythonArgs {
  code?: string;
  timeout?: number;
}

/**
 * `python_execute` for the local sandbox.
 *
 * Every call used to pay `python3 -c` startup (0.3–0.6 s, plus 0.7–4.5 s for
 * the first import of common modules). This class keeps one `python3 -u -S -E`
 * interpreter alive inside the guest shell and talks to it through files in
 * the mounted workspace: the app writes `req.txt` (atomic rename) and polls
 * `out.txt` for a per-request marker. Measured on the tablet: 14–28 ms per
 * warm request instead of 300+ ms, with variables and imports preserved.
 *
 * The interpreter lives in the sandbox daemon, so stopping the daemon (user
 * cancels, a shell command times out) kills it too; the generation check
 * aborts the poll immediately and the next call starts a fresh one.
 */
export class PythonService {
  private static readonly START_COMMAND: string =
    'd=/var/minis/workspace/.minis-py; ' +
    'p=$(cat $d/ready.txt 2>/dev/null); ' +
    'if [ -n "$p" ] && grep -q srv.py /proc/$p/cmdline 2>/dev/null; then ' +
    'kill -9 $p 2>/dev/null; fi; ' +
    'rm -f $d/ready.txt $d/out.txt $d/req.txt; ' +
    'mkdir -p /dev/shm; ' +
    'cd /var/minis/workspace; ' +
    'nohup python3 -u -S -E $d/srv.py </dev/null >$d/srv.log 2>&1 & ' +
    'echo minis-py-started';

  private static ready: boolean = false;
  /** Daemon generation the running interpreter belongs to. */
  private static generation: number = -1;
  private static seq: number = 0;
  private static starting: Promise<string> | null = null;
  /** One interpreter, therefore one request at a time. */
  private static queue: Promise<void> = Promise.resolve();

  static async executePython(context: common.UIAbilityContext, argumentsJson: string,
    onProgress?: (text: string) => void): Promise<ToolResult> {
    let args: PythonArgs;
    try {
      args = JSON.parse(argumentsJson) as PythonArgs;
    } catch (e) {
      return { ok: false, content: t('参数不是合法 JSON。') };
    }
    const code: string = args.code !== undefined ? args.code : '';
    if (code.trim().length === 0) {
      return { ok: false, content: t('code 不能为空。') };
    }
    const requested: number = args.timeout === undefined || Number.isNaN(args.timeout)
      ? DEFAULT_TIMEOUT_SECONDS
      : Math.floor(args.timeout);
    const seconds: number = Math.max(MIN_TIMEOUT_SECONDS,
      Math.min(MAX_TIMEOUT_SECONDS, requested));

    const previous: Promise<void> = PythonService.queue;
    let release: () => void = () => {
    };
    PythonService.queue = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    try {
      return await PythonService.runOnce(context, code, seconds, onProgress);
    } finally {
      release();
    }
  }

  private static async runOnce(context: common.UIAbilityContext, code: string,
    seconds: number, onProgress?: (text: string) => void): Promise<ToolResult> {
    const hostDir: string = context.filesDir + '/workspace/.minis-py';
    const startError: string = await PythonService.ensureStarted(context);
    if (startError.length > 0) {
      return { ok: false, content: startError };
    }

    if (PythonService.seq === 0) {
      const saved: number = Number(PythonService.read(hostDir + '/seq.txt').trim());
      if (!Number.isNaN(saved) && Number.isFinite(saved) && saved > 0) {
        PythonService.seq = Math.floor(saved);
      }
    }
    PythonService.seq++;
    const id: number = PythonService.seq;
    PythonService.write(hostDir + '/seq.txt', id.toString());

    const temporary: string = hostDir + '/req.txt.tmp';
    if (!PythonService.write(temporary, 'id=' + id.toString() + '\n' + code)) {
      return { ok: false, content: t('无法写入 Python 请求文件。') };
    }
    try {
      fs.renameSync(temporary, hostDir + '/req.txt');
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('无法提交 Python 请求：') + error.message };
    }

    const generation: number = PythonService.generation;
    const outPath: string = hostDir + '/out.txt';
    const marker: string = '__MINIS_DONE__ ' + id.toString() + ' ';
    const deadline: number = Date.now() + seconds * 1000;
    let lastSize: number = -1;
    let text: string = '';

    while (Date.now() < deadline) {
      if (SandboxIsh.daemonGeneration() !== generation) {
        PythonService.ready = false;
        return {
          ok: false,
          content: t('命令已取消：沙箱已重启。')
        };
      }
      let size: number = 0;
      try {
        size = fs.statSync(outPath).size;
      } catch (e) {
        size = 0;
      }
      if (size !== lastSize) {
        lastSize = size;
        text = PythonService.read(outPath);
        if (onProgress !== undefined) {
          const clean: string = sanitizeTerminal(text);
          onProgress(clean.length > MAX_PREVIEW_CHARS
            ? clean.substring(clean.length - MAX_PREVIEW_CHARS)
            : clean);
        }
      }
      const at: number = text.indexOf(marker);
      if (at >= 0) {
        return PythonService.finish(text, at, marker);
      }
      await PythonService.sleep(POLL_MS);
    }

    // Timed out: hand back what the script printed, then stop the interpreter
    // so a stuck loop cannot burn CPU forever. kill -9 does not affect the
    // shell (verified on the tablet), and the next call starts a new server.
    const partial: string = sanitizeTerminal(PythonService.read(outPath));
    const body: string = truncateMiddle(partial, MAX_RESULT_CHARS);
    if (SandboxIsh.daemonGeneration() === generation) {
      await PythonService.kill(context);
    }
    PythonService.ready = false;
    return {
      ok: false,
      content: (body.length > 0 ? body + '\n' : '') +
        t('[超时：已终止 Python 服务，下一条请求会重新启动]')
    };
  }

  private static finish(text: string, at: number, marker: string): ToolResult {
    const rest: string = text.substring(at + marker.length).trim();
    const parts: string[] = rest.split(' ');
    let status: number = 0;
    if (parts.length >= 2) {
      const parsed: number = Number(parts[1]);
      if (!Number.isNaN(parsed)) {
        status = parsed;
      }
    }
    let body: string = text.substring(0, at);
    if (body.endsWith('\n')) {
      body = body.substring(0, body.length - 1);
    }
    const clean: string = truncateMiddle(sanitizeTerminal(body), MAX_RESULT_CHARS);
    const exit: string = '[exit=' + status.toString() + ']';
    return {
      ok: status === 0,
      content: clean.length > 0 ? clean + '\n' + exit : exit
    };
  }

  private static async ensureStarted(context: common.UIAbilityContext): Promise<string> {
    if (PythonService.ready &&
      PythonService.generation === SandboxIsh.daemonGeneration()) {
      return '';
    }
    PythonService.ready = false;
    if (PythonService.starting !== null) {
      return await PythonService.starting;
    }
    const starting: Promise<string> = PythonService.start(context);
    PythonService.starting = starting;
    try {
      return await starting;
    } finally {
      PythonService.starting = null;
    }
  }

  private static async start(context: common.UIAbilityContext): Promise<string> {
    const hostDir: string = context.filesDir + '/workspace/.minis-py';
    try {
      if (!fs.accessSync(hostDir)) {
        fs.mkdirSync(hostDir, true);
      }
    } catch (e) {
      return t('无法创建 Python 工作目录。');
    }
    // The interpreter is shipped as a rawfile so the Python source does not
    // have to survive ArkTS string escaping.
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent('minis_py_srv.py');
      const source: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      if (PythonService.read(hostDir + '/srv.py') !== source) {
        PythonService.write(hostDir + '/srv.py', source);
      }
    } catch (e) {
      const error: Error = e as Error;
      return t('无法写入 Python 服务脚本：') + error.message;
    }

    const options: SandboxOptions = {
      workspace: context.filesDir + '/workspace',
      memory: context.filesDir + '/memory',
      attachments: context.filesDir + '/attachments',
      skills: context.filesDir + '/skills'
    };
    const boot = await SandboxIsh.run(context, PythonService.START_COMMAND,
      60000, options);
    if (boot.error.length > 0) {
      return t('无法启动 Python 服务：') + boot.error;
    }
    const generation: number = SandboxIsh.daemonGeneration();
    const deadline: number = Date.now() + START_TIMEOUT_MS;
    while (Date.now() < deadline) {
      if (SandboxIsh.daemonGeneration() !== generation) {
        return t('Python 服务启动时沙箱被停止。');
      }
      const pid: number = Number(PythonService.read(hostDir + '/ready.txt').trim());
      if (!Number.isNaN(pid) && Number.isFinite(pid) && pid > 0) {
        PythonService.generation = generation;
        PythonService.ready = true;
        return '';
      }
      await PythonService.sleep(30);
    }
    const log: string = PythonService.read(hostDir + '/srv.log').trim();
    return t('Python 服务启动超时。') +
      (log.length > 0 ? '\n' + truncateMiddle(log, 4000) : '');
  }

  private static async kill(context: common.UIAbilityContext): Promise<void> {
    const options: SandboxOptions = {
      workspace: context.filesDir + '/workspace',
      memory: context.filesDir + '/memory',
      attachments: context.filesDir + '/attachments',
      skills: context.filesDir + '/skills'
    };
    const command: string = 'd=/var/minis/workspace/.minis-py; ' +
      'p=$(cat $d/ready.txt 2>/dev/null); ' +
      'if [ -n "$p" ]; then kill -9 $p 2>/dev/null; fi; ' +
      'rm -f $d/ready.txt; echo killed';
    try {
      await SandboxIsh.run(context, command, KILL_TIMEOUT_MS, options);
    } catch (e) {
      // The daemon may already be gone; the next call starts a fresh server.
    }
  }

  private static read(path: string): string {
    try {
      return fs.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  private static write(path: string, text: string): boolean {
    try {
      const file = fs.openSync(path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
