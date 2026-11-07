/**
 * OpenCode Go routing rules.
 *
 * OpenCode Go rejects requests that do not carry a stable per-conversation
 * `x-opencode-session` id. The header must be:
 *   - present on every request of a conversation (including retries),
 *   - stable across restarts and provider re-creation,
 *   - never a placeholder such as a draft key,
 *   - only sent to opencode.ai (not to arbitrary custom relays).
 *
 * This file is deliberately dependency-free and mirrors the behaviour that
 * OpenMinis implements in OpenCodeSessionHeader (Android) and
 * OpenCodeChannel (iOS).
 */

export const OPENCODE_HOST: string = 'opencode.ai';
export const OPENCODE_SESSION_HEADER: string = 'x-opencode-session';

export function normalizeBaseUrl(raw: string): string {
  let value: string = raw.trim();
  if (value.length === 0) {
    return '';
  }
  if (value.indexOf('://') < 0) {
    value = 'https://' + value;
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/** Host without scheme, path, port, credentials or IPv6 brackets. */
export function hostOf(raw: string): string {
  const value: string = normalizeBaseUrl(raw);
  const scheme: number = value.indexOf('://');
  if (scheme < 0) {
    return '';
  }
  let rest: string = value.substring(scheme + 3);
  const slash: number = rest.indexOf('/');
  if (slash >= 0) {
    rest = rest.substring(0, slash);
  }
  const at: number = rest.lastIndexOf('@');
  if (at >= 0) {
    rest = rest.substring(at + 1);
  }
  if (rest.startsWith('[')) {
    const close: number = rest.indexOf(']');
    if (close > 0) {
      return rest.substring(1, close).toLowerCase();
    }
  }
  const colon: number = rest.indexOf(':');
  if (colon >= 0) {
    rest = rest.substring(0, colon);
  }
  return rest.toLowerCase();
}

/**
 * True only for opencode.ai itself or a dot-anchored subdomain.
 * `not-opencode.ai` and `opencode.ai.example.com` must not match.
 */
export function isOpenCodeBase(raw: string): boolean {
  const host: string = hostOf(raw);
  if (host.length === 0) {
    return false;
  }
  return host === OPENCODE_HOST || host.endsWith('.' + OPENCODE_HOST);
}

/** True when the id is a real persisted conversation id, not a draft key. */
export function isPersistedSessionId(sessionId: string): boolean {
  const value: string = sessionId.trim();
  return value.length > 0 && !value.startsWith('__');
}

export function shouldAttachSessionHeader(baseUrl: string, sessionId: string): boolean {
  return isOpenCodeBase(baseUrl) && isPersistedSessionId(sessionId);
}

export function chatCompletionsUrl(raw: string): string {
  const base: string = normalizeBaseUrl(raw);
  if (base.endsWith('/chat/completions')) {
    return base;
  }
  return base + '/chat/completions';
}

function originOf(raw: string): string {
  const value: string = normalizeBaseUrl(raw);
  const scheme: number = value.indexOf('://');
  if (scheme < 0) {
    return value;
  }
  const slash: number = value.indexOf('/', scheme + 3);
  if (slash < 0) {
    return value;
  }
  return value.substring(0, slash);
}

/**
 * OpenCode serves model discovery from a different path than inference:
 *   canonical base  https://opencode.ai/zen/go/v1
 *   models          https://opencode.ai/zen/go/v1/models
 * The older /inference/go/openai/v1 base keeps a separate models path.
 * Everything else uses the conventional `<base>/models`.
 */
export function modelsUrl(raw: string): string {
  const base: string = normalizeBaseUrl(raw);
  if (isOpenCodeBase(base)) {
    const origin: string = originOf(base);
    if (base.indexOf('/inference/go/') >= 0) {
      return origin + '/inference/go/v1/models';
    }
    if (base.indexOf('/zen/go/') >= 0) {
      return origin + '/zen/go/v1/models';
    }
  }
  if (base.endsWith('/chat/completions')) {
    return base.substring(0, base.length - '/chat/completions'.length) + '/models';
  }
  return base + '/models';
}
