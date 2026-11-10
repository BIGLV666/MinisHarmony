import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FileEntry, joinRelative, sortFileEntries } from '../core/FileListing';
import { normalizeRelativePath, resolveWorkspacePath } from '../core/Workspace';
import { t } from '../core/I18n';

const MAX_PREVIEW_BYTES: number = 256 * 1024;
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

const TEXT_EXT: string[] = [
  'txt', 'md', 'json', 'json5', 'js', 'mjs', 'ts', 'ets', 'tsx', 'jsx',
  'css', 'html', 'htm', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf', 'cfg',
  'log', 'csv', 'sh', 'py', 'go', 'rs', 'java', 'kt', 'c', 'h', 'cpp', 'hpp',
  'sql', 'gradle', 'properties', 'gitignore', 'env', 'lock'
];

export interface WorkspaceListing {
  ok: boolean;
  error: string;
  entries: FileEntry[];
}

export interface WorkspacePreview {
  ok: boolean;
  error: string;
  text: string;
  truncated: boolean;
}

function absoluteFor(root: string, relative: string): string | null {
  const normalized: string | null = normalizeRelativePath(relative);
  if (normalized === null) {
    return null;
  }
  return resolveWorkspacePath(root, normalized);
}

/** Read a directory without following symlinks out of the workspace. */
export function listWorkspace(root: string, relative: string): WorkspaceListing {
  const absolute: string | null = absoluteFor(root, relative);
  if (absolute === null) {
    return { ok: false, error: t('不支持的路径'), entries: [] };
  }
  try {
    const names: string[] = fs.listFileSync(absolute);
    const entries: FileEntry[] = [];
    const parent: string = relative.length > 0
      ? normalizeRelativePath(relative) as string
      : '';
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      const child: string = absolute + '/' + name;
      try {
        const lstat = fs.lstatSync(child);
        if (lstat.isSymbolicLink()) {
          continue;
        }
        entries.push({
          name: name,
          path: joinRelative(parent, name),
          isDir: lstat.isDirectory(),
          size: lstat.isDirectory() ? 0 : lstat.size
        });
      } catch (e) {
        // An entry can vanish between listing and stat; skip it.
      }
    }
    return { ok: true, error: '', entries: sortFileEntries(entries) };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, error: t('无法打开目录：') + error.message, entries: [] };
  }
}

const MENTION_SKIP_DIRS: string[] = [
  'node_modules', 'oh_modules', '.hvigor', 'build', '.minis-browser'
];
const MENTION_MAX_DEPTH: number = 4;

function collectWorkspaceFiles(
  root: string,
  relative: string,
  depth: number,
  limit: number,
  out: FileEntry[]
): void {
  if (out.length >= limit || depth > MENTION_MAX_DEPTH) {
    return;
  }
  const listing: WorkspaceListing = listWorkspace(root, relative);
  if (!listing.ok) {
    return;
  }
  for (let i = 0; i < listing.entries.length && out.length < limit; i++) {
    const entry: FileEntry = listing.entries[i];
    if (!entry.isDir) {
      out.push(entry);
      continue;
    }
    if (entry.name.startsWith('.') ||
      MENTION_SKIP_DIRS.indexOf(entry.name) >= 0) {
      continue;
    }
    collectWorkspaceFiles(root, entry.path, depth + 1, limit, out);
  }
}

/**
 * Flat file list for the composer's `@` menu. Walks subdirectories up to four
 * levels, skipping hidden folders and dependency/build trees, and stops at
 * `limit`. Directories are not returned: a mention points at a file.
 */
export function listWorkspaceFiles(root: string, limit: number): FileEntry[] {
  const out: FileEntry[] = [];
  if (root.length > 0) {
    collectWorkspaceFiles(root, '', 0, limit, out);
  }
  return out;
}

export function looksLikeText(name: string): boolean {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0) {
    return true;
  }
  const ext: string = name.substring(dot + 1).toLowerCase();
  return TEXT_EXT.indexOf(ext) >= 0;
}

/** Preview a text file; binary and oversize files are rejected with a reason. */
export function previewWorkspaceFile(root: string, relative: string): WorkspacePreview {
  const absolute: string | null = absoluteFor(root, relative);
  if (absolute === null) {
    return { ok: false, error: t('不支持的路径'), text: '', truncated: false };
  }
  const name: string = relative.substring(relative.lastIndexOf('/') + 1);
  if (!looksLikeText(name)) {
    return { ok: false, error: t('这是二进制文件，无法预览'), text: '', truncated: false };
  }
  try {
    const stat = fs.statSync(absolute);
    if (stat.isDirectory()) {
      return { ok: false, error: t('这是目录'), text: '', truncated: false };
    }
    const size: number = Math.min(stat.size, MAX_PREVIEW_BYTES);
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    const file = fs.openSync(absolute, fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    const text: string = decoder.decodeToString(new Uint8Array(buffer));
    return {
      ok: true,
      error: '',
      text: text,
      truncated: stat.size > MAX_PREVIEW_BYTES
    };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, error: t('读取失败：') + error.message, text: '', truncated: false };
  }
}
