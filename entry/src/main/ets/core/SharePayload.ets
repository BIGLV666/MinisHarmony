/**
 * Normalise an implicit "share" Want into text and file URIs.
 *
 * HarmonyOS shares content with `ohos.want.action.sendData`; senders have used
 * a few parameter names over time, and file shares arrive as a list of URIs
 * under `ability.params.stream`. This module only inspects values, so the
 * caller can decide whether to read files or just prefill the composer.
 */

export const SHARE_TEXT_KEYS: string[] = [
  'ability.params.content',
  'ohos.extra.param.key.content',
  'content',
  'text',
  'sharedText'
];

export const SHARE_STREAM_KEY: string = 'ability.params.stream';

export interface SharedContent {
  text: string;
  uris: string[];
}

export function sharedFromWant(
  parameters: Record<string, Object> | undefined,
  uri: string,
  type: string
): SharedContent {
  let text: string = '';
  const uris: string[] = [];
  if (parameters !== undefined && parameters !== null) {
    for (let i = 0; i < SHARE_TEXT_KEYS.length; i++) {
      const value: Object = parameters[SHARE_TEXT_KEYS[i]];
      if (typeof value === 'string' && (value as string).trim().length > 0) {
        text = (value as string).trim();
        break;
      }
    }
    const stream: Object = parameters[SHARE_STREAM_KEY];
    if (Array.isArray(stream)) {
      const list: Object[] = stream as Object[];
      for (let i = 0; i < list.length; i++) {
        const item: Object = list[i];
        if (typeof item === 'string' && (item as string).length > 0) {
          uris.push(item as string);
        }
      }
    }
  }
  if (text.length === 0 && uri.length > 0 &&
    (type.indexOf('text/') === 0 || type.length === 0)) {
    text = uri;
  }
  return { text: text, uris: uris };
}

/** True when the MIME type is something the composer can show as text. */
export function isTextualShare(type: string): boolean {
  return type.length === 0 || type.indexOf('text/') === 0 ||
    type === 'application/json' || type === 'application/xml';
}

const IMAGE_SUFFIXES: string[] = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];

function isImageUri(uri: string, type: string): boolean {
  if (type.indexOf('image/') === 0) {
    return true;
  }
  const lower: string = uri.toLowerCase();
  for (let i = 0; i < IMAGE_SUFFIXES.length; i++) {
    if (lower.endsWith(IMAGE_SUFFIXES[i])) {
      return true;
    }
  }
  return false;
}

/**
 * Collect image URIs from a share Want (direct `uri` plus
 * `ability.params.stream`), preserving order and de-duplicating. The caller
 * copies them into the attachment directory; at most four are accepted.
 */
export function imageUrisFromShare(
  parameters: Record<string, Object> | undefined,
  uri: string,
  type: string
): string[] {
  const content: SharedContent = sharedFromWant(parameters, uri, type);
  const uris: string[] = [];
  if (uri.length > 0 && isImageUri(uri, type)) {
    uris.push(uri);
  }
  for (let i = 0; i < content.uris.length; i++) {
    const candidate: string = content.uris[i];
    if (isImageUri(candidate, type) && uris.indexOf(candidate) < 0) {
      uris.push(candidate);
    }
  }
  return uris.slice(0, 4);
}
