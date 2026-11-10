/**
 * `minis://` deep links.
 *
 * Supported shapes (mirroring OpenMinis where the app has an equivalent UI):
 *   minis://session/<id>           open an existing conversation
 *   minis://sessions/<id>          canonical alias
 *   minis://chat/<id>              alias
 *   minis://s/<id>                 short alias
 *   minis://session/<id>/<path>    open a conversation and a local resource
 *   minis://open?session=<id>&path=<path>  launcher round-trip
 *   minis://new                    start a new conversation
 *   minis://action/new_chat        quick action
 *   minis://action/camera_chat     new chat, then open the camera picker
 *   minis://task/<id>              scheduled reminder: restore its prompt
 *   minis://settings[/<path>]      open settings (sub-paths are informational)
 *   minis://views/alarm            open the scheduled-task list
 *
 * Anything else is rejected rather than guessed.
 */

export const DEEP_LINK_SCHEME: string = 'minis://';

export interface DeepLink {
  kind: string;
  value: string;
  /** Optional resource path for session/open routes. */
  path?: string;
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (e) {
    return value;
  }
}

/** Read one query parameter without pulling in a URL parser. */
function queryValue(query: string, key: string): string {
  const parts: string[] = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    const eq: number = part.indexOf('=');
    if (eq < 0) {
      continue;
    }
    if (safeDecode(part.substring(0, eq)) === key) {
      return safeDecode(part.substring(eq + 1));
    }
  }
  return '';
}

function sessionLink(id: string, resourcePath: string): DeepLink {
  if (id.length === 0) {
    return { kind: 'invalid', value: '' };
  }
  if (resourcePath.length > 0) {
    return { kind: 'session', value: id, path: resourcePath };
  }
  return { kind: 'session', value: id };
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
  let query: string = '';
  const queryAt: number = rest.indexOf('?');
  if (queryAt >= 0) {
    query = rest.substring(queryAt + 1);
    rest = rest.substring(0, queryAt);
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
  const rawValue: string = slash < 0 ? '' : rest.substring(slash + 1);

  if (host === 'new') {
    return { kind: 'new', value: '' };
  }
  if (host === 'action') {
    const action: string = rawValue.toLowerCase();
    if (action === 'new_chat') {
      return { kind: 'new', value: '' };
    }
    if (action === 'camera_chat') {
      return { kind: 'camera', value: '' };
    }
    // `voice_chat` needs CoreSpeechKit, which the public SDK lacks.
    return null;
  }
  if (host === 'open') {
    const id: string = queryValue(query, 'session');
    const path: string = queryValue(query, 'path');
    if (id.length > 0) {
      const link: DeepLink = sessionLink(id, path);
      return link.kind === 'invalid' ? null : link;
    }
    return path.length > 0 ? { kind: 'resource', value: '', path: path } : null;
  }
  if (host === 'session' || host === 'sessions' || host === 'chat' || host === 's') {
    if (rawValue.length === 0) {
      return null;
    }
    const part: number = rawValue.indexOf('/');
    const id: string = safeDecode(part < 0 ? rawValue : rawValue.substring(0, part));
    const path: string = part < 0 ? '' : safeDecode(rawValue.substring(part + 1));
    const link: DeepLink = sessionLink(id, path);
    return link.kind === 'invalid' ? null : link;
  }
  if (host === 'task') {
    if (rawValue.length === 0) {
      return null;
    }
    return { kind: 'task', value: rawValue };
  }
  if (host === 'settings') {
    return { kind: 'settings', value: safeDecode(rawValue) };
  }
  if (host === 'views' && rawValue === 'alarm') {
    return { kind: 'alarm', value: '' };
  }
  return null;
}
