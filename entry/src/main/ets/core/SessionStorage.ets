/**
 * Per-session workspace ownership. The workspace itself stays a single shared
 * directory (tools and existing files keep their paths); this ledger only
 * remembers which session wrote which relative path, so the settings page can
 * show a per-session breakdown and delete one session's generated files.
 */

export interface StorageEntry {
  sessionId: string;
  /** Workspace-relative path, already normalised by the writer. */
  path: string;
  bytes: number;
  at: number;
}

/** One attachment reference found in a session's messages. */
export interface SessionAttachmentUsage {
  sessionId: string;
  uri: string;
  bytes: number;
}

export interface SessionStorageTotal {
  sessionId: string;
  workspaceFiles: number;
  workspaceBytes: number;
  attachmentFiles: number;
  attachmentBytes: number;
}

export const STORAGE_ENTRY_LIMIT: number = 4000;

function safeRelative(path: string): boolean {
  if (path.length === 0 || path.startsWith('/') || path.indexOf('\\') >= 0) {
    return false;
  }
  const parts: string[] = path.split('/');
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0 || parts[i] === '.' || parts[i] === '..') {
      return false;
    }
  }
  return true;
}

/** Load the ledger, dropping malformed rows and unsafe paths. */
export function parseStorageEntries(raw: string): StorageEntry[] {
  if (raw.trim().length === 0) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const list: Object[] = parsed as Object[];
  const out: StorageEntry[] = [];
  const seen: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < list.length; i++) {
    const item: Record<string, Object> = list[i] as Record<string, Object>;
    const sessionId: string =
      typeof item.sessionId === 'string' ? item.sessionId as string : '';
    const path: string = typeof item.path === 'string' ? item.path as string : '';
    const bytes: number = typeof item.bytes === 'number' ? item.bytes as number : -1;
    const at: number = typeof item.at === 'number' ? item.at as number : 0;
    if (sessionId.trim().length === 0 || !safeRelative(path) || bytes < 0 || at <= 0) {
      continue;
    }
    const entry: StorageEntry = {
      sessionId: sessionId,
      path: path,
      bytes: Math.floor(bytes),
      at: at
    };
    const key: string = sessionId + '\n' + path;
    const existing: number | undefined = seen.get(key);
    if (existing !== undefined) {
      out[existing] = entry;
    } else {
      seen.set(key, out.length);
      out.push(entry);
    }
  }
  return out;
}

/** Replace the same session+path and keep the newest `limit` rows. */
export function mergeStorageEntry(
  entries: StorageEntry[],
  entry: StorageEntry,
  limit: number
): StorageEntry[] {
  const cap: number = limit > 0 ? limit : STORAGE_ENTRY_LIMIT;
  const out: StorageEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    if (!(entries[i].sessionId === entry.sessionId &&
      entries[i].path === entry.path)) {
      out.push(entries[i]);
    }
  }
  out.push(entry);
  return out.length > cap ? out.slice(out.length - cap) : out;
}

export function storagePaths(entries: StorageEntry[], sessionId: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].sessionId === sessionId) {
      out.push(entries[i].path);
    }
  }
  return out;
}

/**
 * Combine ledger rows and attachment references. Attachments are deduplicated
 * per session+uri because a message can repeat the same file part.
 */
export function storageTotals(
  entries: StorageEntry[],
  attachments: SessionAttachmentUsage[]
): SessionStorageTotal[] {
  const bySession: Map<string, SessionStorageTotal> = new Map<string, SessionStorageTotal>();
  for (let i = 0; i < entries.length; i++) {
    const entry: StorageEntry = entries[i];
    let row: SessionStorageTotal | undefined = bySession.get(entry.sessionId);
    if (row === undefined) {
      row = {
        sessionId: entry.sessionId,
        workspaceFiles: 0,
        workspaceBytes: 0,
        attachmentFiles: 0,
        attachmentBytes: 0
      };
      bySession.set(entry.sessionId, row);
    }
    row.workspaceFiles++;
    row.workspaceBytes += entry.bytes;
  }
  const seen: Map<string, boolean> = new Map<string, boolean>();
  for (let i = 0; i < attachments.length; i++) {
    const item: SessionAttachmentUsage = attachments[i];
    const key: string = item.sessionId + '\n' + item.uri;
    if (seen.get(key) === true) {
      continue;
    }
    seen.set(key, true);
    let row: SessionStorageTotal | undefined = bySession.get(item.sessionId);
    if (row === undefined) {
      row = {
        sessionId: item.sessionId,
        workspaceFiles: 0,
        workspaceBytes: 0,
        attachmentFiles: 0,
        attachmentBytes: 0
      };
      bySession.set(item.sessionId, row);
    }
    row.attachmentFiles++;
    row.attachmentBytes += item.bytes;
  }
  const out: SessionStorageTotal[] = [];
  bySession.forEach((row: SessionStorageTotal) => {
    out.push(row);
  });
  out.sort((a: SessionStorageTotal, b: SessionStorageTotal): number =>
    (b.workspaceBytes + b.attachmentBytes) - (a.workspaceBytes + a.attachmentBytes));
  return out;
}
