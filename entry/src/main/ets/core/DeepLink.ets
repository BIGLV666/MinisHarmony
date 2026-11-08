/**
 * `minis://` deep links.
 *
 * Supported shapes:
 *   minis://session/<id>   open an existing conversation
 *   minis://chat/<id>      alias for session
 *   minis://new            start a new conversation
 *
 * Anything else is rejected rather than guessed. Query strings and fragments
 * are ignored; the id is kept verbatim (ids are UUIDs).
 */

export const DEEP_LINK_SCHEME: string = 'minis://';

export interface DeepLink {
  kind: string;
  value: string;
}

export function parseDeepLink(uri: string): DeepLink | null {
  if (uri === null || uri === undefined) {
    return null;
  }
  const trimmed: string = uri.trim();
  const lower: string = trimmed.toLowerCase();
  if (lower.indexOf(DEEP_LINK_SCHEME) !== 0) {
    return null;
  }
  let rest: string = trimmed.substring(DEEP_LINK_SCHEME.length);
  const query: number = rest.indexOf('?');
  if (query >= 0) {
    rest = rest.substring(0, query);
  }
  const hash: number = rest.indexOf('#');
  if (hash >= 0) {
    rest = rest.substring(0, hash);
  }
  if (rest.length === 0) {
    return null;
  }
  const slash: number = rest.indexOf('/');
  const host: string = (slash < 0 ? rest : rest.substring(0, slash)).toLowerCase();
  const value: string = slash < 0 ? '' : rest.substring(slash + 1);
  if (host === 'new') {
    return { kind: 'new', value: '' };
  }
  if (host === 'session' || host === 'chat' || host === 's') {
    if (value.length === 0) {
      return null;
    }
    return { kind: 'session', value: value };
  }
  return null;
}
