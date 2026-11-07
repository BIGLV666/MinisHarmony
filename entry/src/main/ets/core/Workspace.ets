/**
 * Workspace path rules. The model may only name paths relative to the app's
 * workspace directory; absolute paths, `..` traversal and symlinks are
 * rejected before any file API sees them.
 *
 * Kept dependency-free so the Node test harness can exercise it.
 */

/**
 * Normalise a model-supplied relative path. Returns null for absolute paths
 * and any path containing a `..` segment. An empty string means "workspace
 * root" and is allowed for directory tools.
 */
export function normalizeRelativePath(raw: string): string | null {
  let value: string = raw.trim();
  if (value.length === 0) {
    return '';
  }
  // Accept Windows-style separators from the model, but never absolute paths.
  value = value.split('\\').join('/');
  if (value.startsWith('/')) {
    return null;
  }
  const segments: string[] = value.split('/');
  const out: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    const segment: string = segments[i];
    if (segment.length === 0 || segment === '.') {
      continue;
    }
    if (segment === '..') {
      return null;
    }
    out.push(segment);
  }
  return out.join('/');
}

export function resolveWorkspacePath(root: string, relative: string): string {
  let base: string = root;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (relative.length === 0) {
    return base;
  }
  return base + '/' + relative;
}

/** Trim a tool result before it is stored in the transcript. */
export function truncateText(text: string, max: number): string {
  if (text.length <= max) {
    return text;
  }
  return text.substring(0, max) + '\n…（已截断，共 ' + text.length + ' 字符）';
}
