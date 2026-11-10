import { fileIo as fs } from '@kit.CoreFileKit';

/** Files and bytes below a directory; zero when it does not exist. */
export interface DirUsage {
  files: number;
  bytes: number;
}

const MAX_DEPTH: number = 8;

function walk(path: string, usage: DirUsage, depth: number): void {
  if (depth > MAX_DEPTH) {
    return;
  }
  let names: string[] = [];
  try {
    names = fs.listFileSync(path);
  } catch (e) {
    return;
  }
  for (let i = 0; i < names.length; i++) {
    const child: string = path + '/' + names[i];
    try {
      const stat = fs.lstatSync(child);
      if (stat.isDirectory()) {
        walk(child, usage, depth + 1);
      } else if (stat.isFile()) {
        usage.files++;
        usage.bytes += stat.size;
      }
    } catch (e) {
      // Entry vanished between listing and stat.
    }
  }
}

export function directoryUsage(path: string): DirUsage {
  const usage: DirUsage = { files: 0, bytes: 0 };
  if (path.length > 0) {
    walk(path, usage, 0);
  }
  return usage;
}

/** Remove every child of `path`, keeping the directory itself. */
export function clearDirectory(path: string): number {
  let names: string[] = [];
  try {
    names = fs.listFileSync(path);
  } catch (e) {
    return 0;
  }
  let removed: number = 0;
  for (let i = 0; i < names.length; i++) {
    const child: string = path + '/' + names[i];
    try {
      const stat = fs.lstatSync(child);
      if (stat.isDirectory()) {
        removed += clearDirectory(child);
        fs.rmdirSync(child);
      } else {
        fs.unlinkSync(child);
        removed++;
      }
    } catch (e) {
      // Keep going: one locked file must not abort the whole cleanup.
    }
  }
  return removed;
}
