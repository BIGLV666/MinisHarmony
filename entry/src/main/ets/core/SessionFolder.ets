import { MAX_SESSION_FOLDERS, SessionFolder, SessionMeta } from './Types';

/**
 * User-created sidebar folders. OpenMinis lets each folder be renamed, deleted
 * (its sessions fall back to "ungrouped"), collapsed, and filled with sessions;
 * the folder list itself lives in settings so it travels with a backup while
 * each session only stores its `folderId`. The `SessionFolder` shape lives in
 * `Types` so `AppSettings` can reference it without a circular import.
 */

/** One rendered bucket in the sidebar; `id` is empty for the ungrouped list. */
export interface FolderGroup {
  id: string;
  /** Empty for the ungrouped bucket; the UI substitutes its own label. */
  label: string;
  collapsed: boolean;
  sessions: SessionMeta[];
}

/** Next free id; folder ids never collide with session ids (prefix `folder-`). */
export function newFolderId(folders: SessionFolder[], now: number): string {
  let base: string = 'folder-' + Math.floor(now).toString(36);
  let candidate: string = base;
  let suffix: number = 2;
  while (folderNamed(folders, candidate)) {
    candidate = base + '-' + suffix.toString();
    suffix++;
  }
  return candidate;
}

function folderNamed(folders: SessionFolder[], id: string): boolean {
  for (let i = 0; i < folders.length; i++) {
    if (folders[i].id === id) {
      return true;
    }
  }
  return false;
}

/** Append a folder; empty names and the cap are rejected (returns the input). */
export function addFolder(folders: SessionFolder[], name: string, id: string): SessionFolder[] {
  const trimmed: string = name.trim();
  if (trimmed.length === 0 || folders.length >= MAX_SESSION_FOLDERS ||
    id.length === 0 || folderNamed(folders, id)) {
    return folders;
  }
  const next: SessionFolder[] = folders.slice();
  next.push({ id: id, name: trimmed, collapsed: false });
  return next;
}

export function renameFolder(folders: SessionFolder[], id: string, name: string): SessionFolder[] {
  const trimmed: string = name.trim();
  if (trimmed.length === 0) {
    return folders;
  }
  const next: SessionFolder[] = [];
  for (let i = 0; i < folders.length; i++) {
    const item: SessionFolder = folders[i];
    next.push(item.id === id
      ? { id: item.id, name: trimmed, collapsed: item.collapsed }
      : item);
  }
  return next;
}

/** Removing a folder leaves its sessions in place under "ungrouped". */
export function removeFolder(folders: SessionFolder[], id: string): SessionFolder[] {
  const next: SessionFolder[] = [];
  for (let i = 0; i < folders.length; i++) {
    if (folders[i].id !== id) {
      next.push(folders[i]);
    }
  }
  return next;
}

export function setFolderCollapsed(folders: SessionFolder[], id: string,
  collapsed: boolean): SessionFolder[] {
  const next: SessionFolder[] = [];
  for (let i = 0; i < folders.length; i++) {
    const item: SessionFolder = folders[i];
    next.push(item.id === id
      ? { id: item.id, name: item.name, collapsed: collapsed }
      : item);
  }
  return next;
}

export function findFolder(folders: SessionFolder[], id: string): SessionFolder | null {
  for (let i = 0; i < folders.length; i++) {
    if (folders[i].id === id) {
      return folders[i];
    }
  }
  return null;
}

export function countFolderSessions(metas: SessionMeta[], folderId: string): number {
  let count: number = 0;
  for (let i = 0; i < metas.length; i++) {
    const assigned: string = metas[i].folderId ?? '';
    if (folderId.length > 0 ? assigned === folderId : assigned.length === 0) {
      count++;
    }
  }
  return count;
}

/**
 * Bucket already-sorted metas by folder. Every folder is emitted even when
 * empty so a freshly created folder is visible. Sessions whose `folderId` no
 * longer exists (deleted folder, imported session) fall into the ungrouped
 * bucket, which is emitted last and only when non-empty.
 */
export function groupByFolder(metas: SessionMeta[], folders: SessionFolder[]): FolderGroup[] {
  const groups: FolderGroup[] = [];
  const grouped: boolean[] = [];
  for (let i = 0; i < metas.length; i++) {
    grouped.push(false);
  }
  for (let i = 0; i < folders.length; i++) {
    const folder: SessionFolder = folders[i];
    const sessions: SessionMeta[] = [];
    for (let m = 0; m < metas.length; m++) {
      if (metas[m].folderId === folder.id) {
        sessions.push(metas[m]);
        grouped[m] = true;
      }
    }
    groups.push({ id: folder.id, label: folder.name, collapsed: folder.collapsed, sessions: sessions });
  }
  const rest: SessionMeta[] = [];
  for (let m = 0; m < metas.length; m++) {
    if (!grouped[m]) {
      rest.push(metas[m]);
    }
  }
  if (rest.length > 0) {
    groups.push({ id: '', label: '', collapsed: false, sessions: rest });
  }
  return groups;
}
