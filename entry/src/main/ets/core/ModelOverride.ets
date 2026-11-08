/**
 * Per-model request overrides.
 *
 * OpenCode Go is OpenAI-compatible, but self-hosted proxies often need a
 * different temperature, `top_p`, an extra auth header, or provider-specific
 * fields such as `extra_body`. Rather than adding a setting for every future
 * provider, one table is keyed by exact model id and applied only to that
 * model's requests.
 *
 * JSON text is kept as a string in preferences so the stored shape stays
 * versionable; parsing happens here, and invalid text is ignored at request
 * time (the settings UI rejects it before saving).
 */

export interface ModelOverride {
  modelId: string;
  /** -1 means "inherit the global temperature". */
  temperature: number;
  /** -1 means "do not send top_p". */
  topP: number;
  /** 0 means "inherit the global max_tokens". */
  maxTokens: number;
  /** JSON object of additional request headers, or empty. */
  extraHeaders: string;
  /** JSON object merged over the request body, or empty. */
  extraBody: string;
}

export const OVERRIDE_INHERIT: number = -1;

export function defaultModelOverride(modelId: string): ModelOverride {
  return {
    modelId: modelId,
    temperature: OVERRIDE_INHERIT,
    topP: OVERRIDE_INHERIT,
    maxTokens: 0,
    extraHeaders: '',
    extraBody: ''
  };
}

/** Drop rows without a model id and de-duplicate by model id (first wins). */
export function normalizeModelOverrides(list: ModelOverride[] | undefined): ModelOverride[] {
  const out: ModelOverride[] = [];
  if (list === undefined || !Array.isArray(list)) {
    return out;
  }
  for (let i = 0; i < list.length; i++) {
    const item: ModelOverride = list[i];
    if (item === null || item === undefined) {
      continue;
    }
    const id: string = item.modelId !== undefined ? item.modelId.trim() : '';
    if (id.length === 0) {
      continue;
    }
    let duplicate: boolean = false;
    for (let j = 0; j < out.length; j++) {
      if (out[j].modelId === id) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) {
      continue;
    }
    out.push({
      modelId: id,
      temperature: normalizeTemperature(item.temperature),
      topP: normalizeTopP(item.topP),
      maxTokens: normalizeMaxTokens(item.maxTokens),
      extraHeaders: item.extraHeaders !== undefined ? item.extraHeaders : '',
      extraBody: item.extraBody !== undefined ? item.extraBody : ''
    });
  }
  return out;
}

export function findModelOverride(list: ModelOverride[], modelId: string): ModelOverride | null {
  const wanted: string = modelId.trim();
  if (wanted.length === 0) {
    return null;
  }
  for (let i = 0; i < list.length; i++) {
    if (list[i].modelId === wanted) {
      return list[i];
    }
  }
  return null;
}

function normalizeTemperature(value: number): number {
  if (typeof value !== 'number' || Number.isNaN(value)) {
    return OVERRIDE_INHERIT;
  }
  if (value < 0) {
    return OVERRIDE_INHERIT;
  }
  return Math.min(2, Math.round(value * 100) / 100);
}

function normalizeTopP(value: number): number {
  if (typeof value !== 'number' || Number.isNaN(value)) {
    return OVERRIDE_INHERIT;
  }
  if (value < 0) {
    return OVERRIDE_INHERIT;
  }
  return Math.min(1, Math.round(value * 1000) / 1000);
}

function normalizeMaxTokens(value: number): number {
  if (typeof value !== 'number' || Number.isNaN(value) || value <= 0) {
    return 0;
  }
  return Math.floor(value);
}

/**
 * Parse a JSON object whose values must all be strings. Blank text means
 * "no headers" and returns an empty record; anything malformed returns null.
 */
export function parseExtraHeaders(text: string): Record<string, string> | null {
  const trimmed: string = text.trim();
  const out: Record<string, string> = {};
  if (trimmed.length === 0) {
    return out;
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    return null;
  }
  const record: Record<string, Object> = parsed as Record<string, Object>;
  if (record === null || record === undefined || typeof record !== 'object' || Array.isArray(record)) {
    return null;
  }
  const keys: string[] = Object.keys(record);
  for (let i = 0; i < keys.length; i++) {
    const key: string = keys[i];
    if (key.length === 0) {
      return null;
    }
    const value: Object = record[key];
    if (typeof value !== 'string') {
      return null;
    }
    out[key] = value as string;
  }
  return out;
}

/**
 * Parse a JSON object for `extra_body`. Only top-level keys are considered;
 * each value replaces whatever the base request had under the same key.
 * Blank text returns an empty record, malformed text returns null.
 */
export function parseExtraBody(text: string): Record<string, Object> | null {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return {};
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return null;
  }
  return parsed as Record<string, Object>;
}

/** Same contract as parseExtraBody, kept for callers that only validate. */
export function isValidExtraBody(text: string): boolean {
  return parseExtraBody(text) !== null;
}

export function isValidExtraHeaders(text: string): boolean {
  return parseExtraHeaders(text) !== null;
}

/**
 * Merge additional headers over a copy of `base`. Invalid JSON is ignored
 * rather than failing the request, so a bad stored value cannot brick chat.
 */
export function mergeExtraHeaders(base: Record<string, string>, extraText: string): Record<string, string> {
  const out: Record<string, string> = {};
  const baseKeys: string[] = Object.keys(base);
  for (let i = 0; i < baseKeys.length; i++) {
    out[baseKeys[i]] = base[baseKeys[i]];
  }
  const extra: Record<string, string> | null = parseExtraHeaders(extraText);
  if (extra === null) {
    return out;
  }
  const extraKeys: string[] = Object.keys(extra);
  for (let i = 0; i < extraKeys.length; i++) {
    out[extraKeys[i]] = extra[extraKeys[i]];
  }
  return out;
}

/**
 * Merge extra body fields into an already-serialized request body. Doing it
 * textually keeps `ChatRequestBody` strictly typed; the result is parsed and
 * re-serialized, so the output is always valid JSON. Invalid input returns
 * the original body unchanged.
 */
export function applyExtraBody(baseJson: string, extraText: string): string {
  const extra: Record<string, Object> | null = parseExtraBody(extraText);
  if (extra === null) {
    return baseJson;
  }
  const keys: string[] = Object.keys(extra);
  if (keys.length === 0) {
    return baseJson;
  }
  let merged: Record<string, Object>;
  try {
    merged = JSON.parse(baseJson) as Record<string, Object>;
  } catch (e) {
    return baseJson;
  }
  if (merged === null || typeof merged !== 'object' || Array.isArray(merged)) {
    return baseJson;
  }
  for (let i = 0; i < keys.length; i++) {
    merged[keys[i]] = extra[keys[i]];
  }
  try {
    return JSON.stringify(merged);
  } catch (e) {
    return baseJson;
  }
}

/** Short one-line summary used in the settings list. */
export function overrideSummary(item: ModelOverride): string {
  const bits: string[] = [];
  if (item.temperature >= 0) {
    bits.push('t=' + item.temperature.toString());
  }
  if (item.topP >= 0) {
    bits.push('top_p=' + item.topP.toString());
  }
  if (item.maxTokens > 0) {
    bits.push('max=' + item.maxTokens.toString());
  }
  if (item.extraHeaders.trim().length > 0) {
    bits.push('headers');
  }
  if (item.extraBody.trim().length > 0) {
    bits.push('body');
  }
  return bits.length === 0 ? '未设置覆盖项' : bits.join(' · ');
}
