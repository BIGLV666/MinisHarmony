/**
 * `minis://workspace/<path>` and `minis://attachments/<path>` links that the
 * agent writes into Markdown. They address files inside the same directories
 * the sandbox mounts, so the app can preview them without a network hop.
 *
 * Kept dependency-free apart from the shared path rules, so the Node test
 * harness can exercise it.
 */

import { normalizeRelativePath } from './Workspace';

export const MINIS_SCHEME: string = 'minis://';
export const MINIS_WORKSPACE: string = 'workspace';
export const MINIS_ATTACHMENTS: string = 'attachments';
/** Browser artifacts live in `<workspace>/.minis-browser`. */
export const MINIS_BROWSER: string = 'browser';
export const BROWSER_ARTIFACT_DIR: string = '.minis-browser';

export interface MinisResource {
  /** `workspace`, `attachments` or `browser`. */
  scope: string;
  /** Normalised relative path; empty means the directory root. */
  path: string;
}

/**
 * Parse a resource link. Returns null for any other scheme, an unknown host,
 * an absolute path or a path containing `..`. Percent escapes are decoded
 * once, so a file named `a b.md` can be written as `a%20b.md`.
 */
export function parseMinisResource(uri: string): MinisResource | null {
  const raw: string = uri.trim();
  if (raw.length < MINIS_SCHEME.length ||
    raw.substring(0, MINIS_SCHEME.length).toLowerCase() !== MINIS_SCHEME) {
    return null;
  }
  let rest: string = raw.substring(MINIS_SCHEME.length);
  // Tolerate `minis:/workspace/...` only through the exact `//` form above;
  // a single slash is not a resource link.
  const slash: number = rest.indexOf('/');
  const scope: string = (slash < 0 ? rest : rest.substring(0, slash)).toLowerCase();
  if (scope !== MINIS_WORKSPACE && scope !== MINIS_ATTACHMENTS &&
    scope !== MINIS_BROWSER) {
    return null;
  }
  let encoded: string = slash < 0 ? '' : rest.substring(slash + 1);
  let decoded: string = encoded;
  try {
    decoded = decodeURIComponent(encoded);
  } catch (e) {
    return null;
  }
  if (decoded.indexOf('\u0000') >= 0 || decoded.indexOf('\n') >= 0 ||
    decoded.indexOf('\r') >= 0) {
    return null;
  }
  const path: string | null = normalizeRelativePath(decoded);
  if (path === null) {
    return null;
  }
  return { scope: scope, path: path };
}

/** Build a `minis://` URL with each path segment percent-encoded. */
export function resourceUrl(scope: string, path: string): string {
  const encoded: string = path.split('/').map((segment: string): string =>
    encodeURIComponent(segment)).join('/');
  return MINIS_SCHEME + scope + '/' + encoded;
}

/** Directory and leaf name for opening a preview at a specific file. */
export function splitResourcePath(path: string): string[] {
  const cut: number = path.lastIndexOf('/');
  if (cut < 0) {
    return ['', path];
  }
  return [path.substring(0, cut), path.substring(cut + 1)];
}
