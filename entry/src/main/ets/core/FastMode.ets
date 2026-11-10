/**
 * Fast mode / priority processing. The OpenAI-compatible wire field is
 * `service_tier: "priority"`; only providers that document it may receive the
 * key, because strict relays 400 on unknown body fields. OpenMinis enables it
 * for xAI and for its Codex (Responses API) fast path, and reads the toggle at
 * request-build time so a flip applies to the next request.
 */

/** Lowercased host without port, or '' when the URL is unusable. */
export function hostOf(baseUrl: string): string {
  let value: string = baseUrl.trim().toLowerCase();
  if (value.length === 0) {
    return '';
  }
  const scheme: number = value.indexOf('://');
  if (scheme >= 0) {
    value = value.substring(scheme + 3);
  }
  const slash: number = value.indexOf('/');
  if (slash >= 0) {
    value = value.substring(0, slash);
  }
  const colon: number = value.indexOf(':');
  if (colon >= 0) {
    value = value.substring(0, colon);
  }
  return value;
}

/**
 * Codex' Responses endpoint accepts priority tier. Custom OpenAI-compatible
 * endpoints only when they point at xAI directly; relays such as OpenCode are
 * left untouched.
 */
export function supportsFastMode(preset: string, baseUrl: string): boolean {
  if (preset === 'codex') {
    return true;
  }
  return preset === 'custom' && hostOf(baseUrl) === 'api.x.ai';
}

/** `'priority'` when fast mode is on and the provider supports it, else ''. */
export function serviceTierFor(fastMode: boolean, preset: string,
  baseUrl: string): string {
  return fastMode && supportsFastMode(preset, baseUrl) ? 'priority' : '';
}
