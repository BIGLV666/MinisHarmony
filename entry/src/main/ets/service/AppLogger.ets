import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import {
  LogEvent,
  logFileName,
  serializeEvent
} from '../core/EventLog';

const RETENTION_DAYS: number = 14;
const MAX_FILE_BYTES: number = 8 * 1024 * 1024;

/**
 * Append-only JSONL event log in the app sandbox (`filesDir/logs`).
 *
 * Design constraints:
 * - off by default; the user opts in from Settings;
 * - metadata only — no prompts, message bodies, API keys or tokens;
 * - one file per local day, 14-day retention, 8 MB daily cap;
 * - logging must never break a conversation, so every I/O error is swallowed
 *   after the first failure and the logger disables itself.
 */
export class AppLogger {
  private static dir: string = '';
  private static enabled: boolean = false;
  private static fd: number = -1;
  private static currentName: string = '';
  private static broken: boolean = false;

  static init(context: common.UIAbilityContext, enabled: boolean): void {
    AppLogger.dir = context.filesDir + '/logs';
    AppLogger.enabled = enabled;
    try {
      if (!fileIo.accessSync(AppLogger.dir)) {
        fileIo.mkdirSync(AppLogger.dir, true);
      }
      AppLogger.prune();
    } catch (e) {
      AppLogger.broken = true;
    }
  }

  static setEnabled(enabled: boolean): void {
    AppLogger.enabled = enabled;
    if (!enabled) {
      AppLogger.close();
    }
  }

  static isEnabled(): boolean {
    return AppLogger.enabled && !AppLogger.broken;
  }

  static log(event: LogEvent): void {
    if (!AppLogger.isEnabled()) {
      return;
    }
    try {
      AppLogger.ensureFile();
      if (AppLogger.fd === -1) {
        return;
      }
      if (fileIo.statSync(AppLogger.fd).size >= MAX_FILE_BYTES) {
        AppLogger.close();
        return;
      }
      fileIo.writeSync(AppLogger.fd, serializeEvent(event));
    } catch (e) {
      AppLogger.broken = true;
      AppLogger.close();
    }
  }

  /** Delete every event log. Returns how many files were removed. */
  static clear(): number {
    AppLogger.close();
    if (AppLogger.dir.length === 0) {
      return 0;
    }
    let removed: number = 0;
    try {
      const names: string[] = fileIo.listFileSync(AppLogger.dir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].startsWith('events-') && names[i].endsWith('.jsonl')) {
          fileIo.unlinkSync(AppLogger.dir + '/' + names[i]);
          removed++;
        }
      }
    } catch (e) {
      // Clearing is best effort.
    }
    return removed;
  }

  private static ensureFile(): void {
    const name: string = logFileName(new Date());
    if (AppLogger.fd !== -1 && name === AppLogger.currentName) {
      return;
    }
    AppLogger.close();
    if (AppLogger.dir.length === 0) {
      return;
    }
    const file: fileIo.File = fileIo.openSync(
      AppLogger.dir + '/' + name,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND
    );
    AppLogger.fd = file.fd;
    AppLogger.currentName = name;
  }

  private static close(): void {
    if (AppLogger.fd !== -1) {
      try {
        fileIo.closeSync(AppLogger.fd);
      } catch (e) {
        // Ignore.
      }
      AppLogger.fd = -1;
    }
    AppLogger.currentName = '';
  }

  /** Drop daily files older than the retention window. */
  private static prune(): void {
    if (AppLogger.dir.length === 0) {
      return;
    }
    const cutoff: number = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
    const names: string[] = fileIo.listFileSync(AppLogger.dir);
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      if (!name.startsWith('events-') || !name.endsWith('.jsonl')) {
        continue;
      }
      const stamp: string = name.substring('events-'.length, name.length - '.jsonl'.length);
      const parsed: number = parseDayStamp(stamp);
      if (parsed > 0 && parsed < cutoff) {
        try {
          fileIo.unlinkSync(AppLogger.dir + '/' + name);
        } catch (e) {
          // Ignore individual failures.
        }
      }
    }
  }
}

/** `2026-11-07` -> local midnight epoch, or 0 when the name is malformed. */
function parseDayStamp(stamp: string): number {
  const parts: string[] = stamp.split('-');
  if (parts.length !== 3) {
    return 0;
  }
  const year: number = Number(parts[0]);
  const month: number = Number(parts[1]);
  const day: number = Number(parts[2]);
  if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)) {
    return 0;
  }
  return new Date(year, month - 1, day).getTime();
}
