/**
 * Pure helpers for the workspace browser. Directory I/O stays in
 * `service/WorkspaceFiles.ets`; ordering and display formatting live here so
 * they can be tested under Node.
 */

export interface FileEntry {
  /** File or directory name, no path. */
  name: string;
  /** Relative path from the workspace root. */
  path: string;
  isDir: boolean;
  size: number;
}

/** Directories first, then case-insensitive name order. */
export function sortFileEntries(entries: FileEntry[]): FileEntry[] {
  const sorted: FileEntry[] = entries.slice();
  sorted.sort((a: FileEntry, b: FileEntry): number => {
    if (a.isDir !== b.isDir) {
      return a.isDir ? -1 : 1;
    }
    const left: string = a.name.toLowerCase();
    const right: string = b.name.toLowerCase();
    if (left < right) {
      return -1;
    }
    return left > right ? 1 : 0;
  });
  return sorted;
}

export function joinRelative(parent: string, name: string): string {
  return parent.length === 0 ? name : parent + '/' + name;
}

/** One level up; the root stays the root. */
export function parentRelative(path: string): string {
  const cut: number = path.lastIndexOf('/');
  return cut < 0 ? '' : path.substring(0, cut);
}

export function formatFileSize(bytes: number): string {
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}
