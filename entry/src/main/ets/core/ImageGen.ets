/**
 * OpenAI-compatible image generation (`POST /images/generations`). Pure
 * request/response helpers live here; the HTTP call and file save are in
 * `service/ImageGen.ets`. Anthropic and Gemini presets are rejected by the
 * service because their native APIs use different image endpoints.
 */

import { normalizeBaseUrl } from './OpenCodeRules';

export const IMAGE_SIZES: string[] = ['1024x1024', '1024x1792', '1792x1024'];
export const DEFAULT_IMAGE_SIZE: string = '1024x1024';
export const MAX_IMAGE_BYTES: number = 10 * 1024 * 1024;

export function normalizeImageSize(value: string): string {
  const trimmed: string = value.trim();
  return IMAGE_SIZES.indexOf(trimmed) >= 0 ? trimmed : DEFAULT_IMAGE_SIZE;
}

/** Append the image endpoint to the configured OpenAI-compatible base URL. */
export function imageGenEndpoint(baseUrl: string): string {
  const base: string = normalizeBaseUrl(baseUrl);
  if (base.length === 0) {
    return '';
  }
  return base + '/images/generations';
}

export function buildImageGenBody(
  model: string,
  prompt: string,
  size: string
): string {
  const body: string = '{"model":' + JSON.stringify(model) +
    ',"prompt":' + JSON.stringify(prompt) +
    ',"n":1,"size":' + JSON.stringify(normalizeImageSize(size)) +
    ',"response_format":"b64_json"}';
  return body;
}

/** Detect the container from magic bytes so the saved file has the right type. */
export function detectImageExtension(bytes: Uint8Array): string {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4E && bytes[3] === 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 &&
    bytes[2] === 0xFF) {
    return 'jpg';
  }
  if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 &&
    bytes[11] === 0x50) {
    return 'webp';
  }
  if (bytes.length >= 4 && bytes[0] === 0x47 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x38) {
    return 'gif';
  }
  return '';
}

export interface ImageGenPayload {
  /** Base64 PNG/JPEG returned inline, empty when the API sent only a URL. */
  b64: string;
  /** Fallback URL; only http(s) is accepted. */
  url: string;
  /** Provider error text, empty on success. */
  error: string;
}

interface RawImageData {
  b64_json?: string;
  url?: string;
}

interface RawImageResponse {
  data?: RawImageData[];
  error?: RawImageError;
  message?: string;
}

interface RawImageError {
  message?: string;
}

/**
 * Parse an image response. Bounded and defensive: malformed JSON, missing
 * data and non-http URLs all become an error string rather than an exception.
 */
export function parseImageGenResponse(body: string): ImageGenPayload {
  let root: RawImageResponse;
  try {
    root = JSON.parse(body) as RawImageResponse;
  } catch (e) {
    return { b64: '', url: '', error: '接口返回的不是 JSON' };
  }
  if (root === null || root === undefined) {
    return { b64: '', url: '', error: '接口返回为空' };
  }
  if (root.error !== undefined && root.error !== null) {
    const message: string = root.error.message !== undefined &&
      root.error.message.length > 0 ? root.error.message : '图片生成失败';
    return { b64: '', url: '', error: message };
  }
  if (root.data === undefined || !Array.isArray(root.data) || root.data.length === 0) {
    const fallback: string = root.message !== undefined && root.message.length > 0
      ? root.message : '接口没有返回图片';
    return { b64: '', url: '', error: fallback };
  }
  const first: RawImageData = root.data[0];
  const b64: string = typeof first.b64_json === 'string' ? first.b64_json : '';
  const url: string = typeof first.url === 'string' ? first.url : '';
  if (b64.length > 0) {
    return { b64: b64, url: '', error: '' };
  }
  if (url.startsWith('https://') || url.startsWith('http://')) {
    return { b64: '', url: url, error: '' };
  }
  return { b64: '', url: '', error: '接口没有返回可用图片' };
}
