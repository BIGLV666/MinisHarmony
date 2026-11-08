import { common } from '@kit.AbilityKit';
import { ShellHandler, ToolResult } from '../core/ToolTypes';
import { sanitizeTerminal, truncateMiddle } from '../core/Terminal';
import { SandboxIsh, SandboxOptions, SandboxRunResult } from './SandboxIsh';

/** Matches OpenMinis: one shell call may return at most this much text. */
const MAX_SHELL_CHARS: number = 20000;
/** The running card shows the tail of this much output, not the whole log. */
const MAX_PREVIEW_CHARS: number = 4000;
/** OpenMinis defaults to 15 minutes and refuses anything above an hour. */
const DEFAULT_TIMEOUT_SECONDS: number = 900;
const MAX_TIMEOUT_SECONDS: number = 3600;
const MIN_TIMEOUT_SECONDS: number = 5;

interface ShellArgs {
  command?: string;
  timeout?: number;
}

/**
 * `shell_execute` for the local runtime. The sandbox itself lives in
 * SandboxIsh; this class only validates arguments, bounds the timeout and
 * formats the result the model reads back.
 *
 * Commands share one guest shell, so shell state (cwd, exported variables,
 * background jobs) carries over between calls. That matches OpenMinis, where
 * `shell_execute` is the general escape hatch whenever a file tool is not
 * enough: building, running scripts, inspecting binaries.
 */
export class ShellTool implements ShellHandler {
  private context: common.UIAbilityContext;
  private options: SandboxOptions;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.options = {
      workspace: context.filesDir + '/workspace',
      memory: context.filesDir + '/memory',
      // Attachments are where read_image and the chat picker store media, so
      // the shell can process the same files (Python, file, identify, ...).
      attachments: context.filesDir + '/attachments'
    };
  }

  async execute(argumentsJson: string,
    onProgress?: (text: string) => void): Promise<ToolResult> {
    let args: ShellArgs;
    try {
      args = JSON.parse(argumentsJson) as ShellArgs;
    } catch (e) {
      return { ok: false, content: '参数不是合法 JSON。' };
    }
    const command: string = args.command !== undefined ? args.command : '';
    if (command.trim().length === 0) {
      return { ok: false, content: 'command 不能为空。' };
    }
    const requested: number = args.timeout === undefined || Number.isNaN(args.timeout)
      ? DEFAULT_TIMEOUT_SECONDS
      : Math.floor(args.timeout);
    const seconds: number = Math.max(MIN_TIMEOUT_SECONDS,
      Math.min(MAX_TIMEOUT_SECONDS, requested));

    // The preview is cleaned the same way as the final result, but only its
    // tail matters while a build or install streams lines.
    const report: ((text: string) => void) | undefined =
      onProgress === undefined ? undefined : (text: string) => {
        const clean: string = sanitizeTerminal(text);
        if (clean.length === 0) {
          return;
        }
        onProgress(clean.length > MAX_PREVIEW_CHARS
          ? clean.substring(clean.length - MAX_PREVIEW_CHARS)
          : clean);
      };
    const result: SandboxRunResult = await SandboxIsh.run(
      this.context, command, seconds * 1000, this.options, report);

    // ANSI colours and `\r` progress rewrites are noise for the model; the
    // error at the end of a build log matters more than its head.
    const output: string = sanitizeTerminal(result.output);
    const parts: string[] = [];
    if (result.error.length > 0) {
      parts.push(result.error);
    }
    if (output.length > 0) {
      parts.push(output);
    }
    const body: string = truncateMiddle(parts.join('\n'), MAX_SHELL_CHARS);
    const exit: string = '[exit=' + result.exitCode.toString() + ']';
    return {
      ok: result.error.length === 0 && !result.timedOut,
      content: body.length > 0 ? body + '\n' + exit : exit
    };
  }
}
