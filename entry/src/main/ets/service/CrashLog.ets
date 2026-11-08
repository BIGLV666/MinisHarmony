import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { crashLine } from '../core/Diagnostics';

const MAX_RECORDS: number = 40;

/**
 * Collects app crash / freeze events reported by hiAppEvent and keeps the last
 * 40 as redacted one-line records under `filesDir/diagnostics`. Records are
 * metadata only: event name, receive time and the OS parameter text with
 * credential-shaped strings removed.
 *
 * A watcher only sees events delivered while it is registered; a crash that
 * kills the process before the callback may not be captured. The bundle also
 * carries the regular event log, so the two together are the best offline
 * signal the platform offers.
 */
export class CrashLog {
  private static dir: string = '';
  private static file: string = '';
  private static watcher: hiAppEvent.Watcher | null = null;

  static init(context: common.UIAbilityContext): void {
    CrashLog.dir = context.filesDir + '/diagnostics';
    CrashLog.file = CrashLog.dir + '/crashes.jsonl';
    try {
      if (!fs.accessSync(CrashLog.dir)) {
        fs.mkdirSync(CrashLog.dir, true);
      }
    } catch (e) {
      // Recording is best effort; export still works without it.
    }
    CrashLog.prune();
    if (CrashLog.watcher !== null) {
      return;
    }
    try {
      const watcher: hiAppEvent.Watcher = {
        name: 'minis_fault',
        appEventFilters: [
          {
            domain: hiAppEvent.domain.OS,
            names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE]
          }
        ],
        onReceive: (domain: string, appEventGroups: hiAppEvent.AppEventGroup[]) => {
          CrashLog.receive(domain, appEventGroups);
        }
      };
      hiAppEvent.addWatcher(watcher);
      CrashLog.watcher = watcher;
    } catch (e) {
      CrashLog.watcher = null;
    }
  }

  private static receive(
    domain: string,
    groups: hiAppEvent.AppEventGroup[]
  ): void {
    for (let i = 0; i < groups.length; i++) {
      const infos: hiAppEvent.AppEventInfo[] = groups[i].appEventInfos;
      for (let j = 0; j < infos.length; j++) {
        let params: string = '';
        try {
          params = JSON.stringify(infos[j].params);
        } catch (e) {
          params = '';
        }
        CrashLog.append(infos[j].name, params);
      }
    }
  }

  static append(event: string, paramsJson: string): void {
    if (CrashLog.file.length === 0) {
      return;
    }
    try {
      const file = fs.openSync(
        CrashLog.file,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND
      );
      try {
        fs.writeSync(file.fd, crashLine(Date.now(), event, paramsJson) + '\n');
      } finally {
        fs.closeSync(file);
      }
      CrashLog.prune();
    } catch (e) {
      // Never let diagnostics break the app.
    }
  }

  /** Newest-first records for the diagnostics bundle. */
  static recent(limit: number): string[] {
    if (CrashLog.file.length === 0 || limit <= 0) {
      return [];
    }
    try {
      const lines: string[] = fs.readTextSync(CrashLog.file).split('\n');
      const out: string[] = [];
      for (let i = lines.length - 1; i >= 0 && out.length < limit; i--) {
        const line: string = lines[i].trim();
        if (line.length > 0) {
          out.push(line);
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  private static prune(): void {
    if (CrashLog.file.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(CrashLog.file)) {
        return;
      }
      const parts: string[] = fs.readTextSync(CrashLog.file).split('\n');
      const lines: string[] = [];
      for (let i = 0; i < parts.length; i++) {
        const line: string = parts[i].trim();
        if (line.length > 0) {
          lines.push(line);
        }
      }
      if (lines.length <= MAX_RECORDS) {
        return;
      }
      const kept: string[] = lines.slice(lines.length - MAX_RECORDS);
      let body: string = '';
      for (let i = 0; i < kept.length; i++) {
        body += kept[i] + '\n';
      }
      const file = fs.openSync(
        CrashLog.file,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(file.fd, body);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      // Ignore; the next append retries.
    }
  }
}
