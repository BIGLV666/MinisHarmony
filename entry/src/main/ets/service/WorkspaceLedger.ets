import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkspaceWriteHandler } from '../core/ToolTypes';
import {
  STORAGE_ENTRY_LIMIT,
  SessionAttachmentUsage,
  SessionStorageTotal,
  StorageEntry,
  mergeStorageEntry,
  parseStorageEntries,
  storagePaths,
  storageTotals
} from '../core/SessionStorage';

export interface LedgerClearResult {
  files: number;
  bytes: number;
}

/**
 * Persists which session wrote which workspace file. Paths stay relative to
 * the shared workspace root; cleanup only removes files recorded for the
 * requested session, so unrelated artifacts are never touched by accident.
 */
export class WorkspaceLedger {
  private static ledgerPath: string = '';
  private static root: string = '';
  private static entries: StorageEntry[] = [];

  static init(ledgerPath: string, workspaceRoot: string): void {
    WorkspaceLedger.ledgerPath = ledgerPath;
    WorkspaceLedger.root = workspaceRoot;
    WorkspaceLedger.entries = parseStorageEntries(WorkspaceLedger.read());
  }

  private static read(): string {
    if (WorkspaceLedger.ledgerPath.length === 0) {
      return '';
    }
    try {
      if (!fs.accessSync(WorkspaceLedger.ledgerPath)) {
        return '';
      }
      return fs.readTextSync(WorkspaceLedger.ledgerPath);
    } catch (e) {
      return '';
    }
  }

  private static persist(): void {
    if (WorkspaceLedger.ledgerPath.length === 0) {
      return;
    }
    try {
      const file = fs.openSync(
        WorkspaceLedger.ledgerPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(file.fd, JSON.stringify(WorkspaceLedger.entries));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      // Accounting is best-effort; a failed write must not break tool use.
    }
  }

  static record(sessionId: string, path: string, bytes: number): void {
    const id: string = sessionId.trim();
    const relative: string = path.trim();
    if (id.length === 0 || relative.length === 0) {
      return;
    }
    WorkspaceLedger.entries = mergeStorageEntry(WorkspaceLedger.entries, {
      sessionId: id,
      path: relative,
      bytes: bytes > 0 ? Math.floor(bytes) : 0,
      at: Date.now()
    }, STORAGE_ENTRY_LIMIT);
    WorkspaceLedger.persist();
  }

  static all(): StorageEntry[] {
    return WorkspaceLedger.entries.slice();
  }

  static totals(attachments: SessionAttachmentUsage[]): SessionStorageTotal[] {
    return storageTotals(WorkspaceLedger.entries, attachments);
  }

  /** Delete only files this session wrote; missing files are still dropped. */
  static clearSession(sessionId: string): LedgerClearResult {
    const paths: string[] = storagePaths(WorkspaceLedger.entries, sessionId);
    let files: number = 0;
    let bytes: number = 0;
    for (let i = 0; i < paths.length; i++) {
      const absolute: string = WorkspaceLedger.root + '/' + paths[i];
      try {
        const stat = fs.lstatSync(absolute);
        if (stat.isSymbolicLink() || stat.isDirectory()) {
          continue;
        }
        bytes += stat.size;
        fs.unlinkSync(absolute);
        files++;
      } catch (e) {
        // Already gone or unreadable; still remove the ledger row below.
      }
    }
    const kept: StorageEntry[] = [];
    for (let i = 0; i < WorkspaceLedger.entries.length; i++) {
      if (WorkspaceLedger.entries[i].sessionId !== sessionId) {
        kept.push(WorkspaceLedger.entries[i]);
      }
    }
    WorkspaceLedger.entries = kept;
    WorkspaceLedger.persist();
    return { files: files, bytes: bytes };
  }
}

/** Binds one session id to the runtime's write callback. */
export class SessionWriteRecorder implements WorkspaceWriteHandler {
  private sessionId: string;

  constructor(sessionId: string) {
    this.sessionId = sessionId;
  }

  record(relative: string, bytes: number): void {
    WorkspaceLedger.record(this.sessionId, relative, bytes);
  }
}
