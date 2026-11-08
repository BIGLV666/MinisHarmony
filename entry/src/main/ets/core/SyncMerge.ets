/**
 * Two-way merge for the WebDAV backup.
 *
 * Sessions are immutable once a turn finishes, so a session is treated as one
 * unit: the transcript with the newer `updatedAt` wins. A local session that
 * is absent remotely is always kept (the remote copy may be older or the
 * upload may have failed). Deletions therefore never propagate automatically;
 * a user who deleted on one device must delete again after a sync.
 */

import { StoredSession, sortSessionMetas } from './Types';

export interface SyncMergeResult {
  sessions: StoredSession[];
  /** Sessions that only the remote had. */
  addedFromRemote: number;
  /** Sessions whose local transcript was replaced by a newer remote one. */
  updatedFromRemote: number;
  /** Sessions kept because the local copy was newer or equal. */
  keptLocal: number;
}

function indexById(sessions: StoredSession[]): Map<string, StoredSession> {
  const map: Map<string, StoredSession> = new Map();
  for (let i = 0; i < sessions.length; i++) {
    const session: StoredSession = sessions[i];
    if (session !== null && session !== undefined && session.meta !== undefined &&
      session.meta.id.length > 0) {
      map.set(session.meta.id, session);
    }
  }
  return map;
}

function newer(local: StoredSession, remote: StoredSession): boolean {
  const localAt: number = local.meta.updatedAt !== undefined ? local.meta.updatedAt : 0;
  const remoteAt: number = remote.meta.updatedAt !== undefined ? remote.meta.updatedAt : 0;
  if (remoteAt > localAt) {
    return true;
  }
  // Same clock value: prefer the side that actually has messages.
  return remoteAt === localAt && local.messages.length === 0 &&
    remote.messages.length > 0;
}

export function mergeSessionSets(
  local: StoredSession[],
  remote: StoredSession[]
): SyncMergeResult {
  const byId: Map<string, StoredSession> = indexById(local);
  let addedFromRemote: number = 0;
  let updatedFromRemote: number = 0;
  let keptLocal: number = 0;

  for (let i = 0; i < remote.length; i++) {
    const incoming: StoredSession = remote[i];
    if (incoming === null || incoming === undefined || incoming.meta === undefined ||
      incoming.meta.id.length === 0) {
      continue;
    }
    const existing: StoredSession | undefined = byId.get(incoming.meta.id);
    if (existing === undefined) {
      byId.set(incoming.meta.id, incoming);
      addedFromRemote++;
    } else if (newer(existing, incoming)) {
      byId.set(incoming.meta.id, incoming);
      updatedFromRemote++;
    } else {
      keptLocal++;
    }
  }

  const merged: StoredSession[] = [];
  byId.forEach((session: StoredSession) => {
    merged.push(session);
  });
  const ordered = sortSessionMetas(merged.map((session: StoredSession) => session.meta));
  const result: StoredSession[] = [];
  for (let i = 0; i < ordered.length; i++) {
    const session: StoredSession | undefined = byId.get(ordered[i].id);
    if (session !== undefined) {
      result.push(session);
    }
  }
  return {
    sessions: result,
    addedFromRemote: addedFromRemote,
    updatedFromRemote: updatedFromRemote,
    keptLocal: keptLocal
  };
}

/** How many remote sessions differ from the local copy, for UI feedback. */
export function remoteChangeCount(local: StoredSession[], remote: StoredSession[]): number {
  const byId: Map<string, StoredSession> = indexById(local);
  let changed: number = 0;
  for (let i = 0; i < remote.length; i++) {
    const incoming: StoredSession = remote[i];
    if (incoming === null || incoming === undefined || incoming.meta === undefined ||
      incoming.meta.id.length === 0) {
      continue;
    }
    const existing: StoredSession | undefined = byId.get(incoming.meta.id);
    if (existing === undefined || newer(existing, incoming)) {
      changed++;
    }
  }
  return changed;
}
