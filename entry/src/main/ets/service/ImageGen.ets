import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppSettings } from '../core/Types';
import {
  ImageGenPayload,
  MAX_IMAGE_BYTES,
  buildImageGenBody,
  detectImageExtension,
  imageGenEndpoint,
  normalizeImageSize,
  parseImageGenResponse
} from '../core/ImageGen';
import { AttachmentInfo, AttachmentStore } from './AttachmentStore';
import { ImageGenHandler, ImageGenRequest, ToolResult } from '../core/ToolTypes';
import { t } from '../core/I18n';

const base64: util.Base64Helper = new util.Base64Helper();

export interface GeneratedImage {
  ok: boolean;
  message: string;
  attachment: AttachmentInfo | null;
}

function requestHeaders(settings: AppSettings): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + settings.apiKey.trim()
  };
  return headers;
}

function bodyText(result: string | Object | ArrayBuffer): string {
  return typeof result === 'string' ? result : '';
}

function validBytes(bytes: Uint8Array | null): Uint8Array | null {
  if (bytes === null || bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) {
    return null;
  }
  return bytes;
}

/** Download an image URL returned instead of inline base64. */
async function download(url: string): Promise<Uint8Array | null> {
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    connectTimeout: 20000,
    readTimeout: 120000,
    expectDataType: http.HttpDataType.ARRAY_BUFFER,
    usingCache: false
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(url, options);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return null;
    }
    if (response.result instanceof ArrayBuffer) {
      return validBytes(new Uint8Array(response.result));
    }
    return null;
  } catch (e) {
    return null;
  } finally {
    request.destroy();
  }
}

/**
 * Call an OpenAI-compatible `/images/generations` endpoint and store the
 * result in the attachment directory, the same place user images live.
 * Anthropic/Gemini native presets have different image APIs and are refused
 * with an explicit message instead of sending a request that cannot work.
 */
export async function generateImage(
  settings: AppSettings,
  prompt: string,
  size: string,
  model: string
): Promise<GeneratedImage> {
  if (settings.preset === 'anthropic' || settings.preset === 'gemini') {
    return {
      ok: false,
      message: t('图像生成仅支持 OpenAI 兼容协议，请切换预设或使用自定义端点'),
      attachment: null
    };
  }
  const endpoint: string = imageGenEndpoint(settings.baseUrl);
  if (endpoint.length === 0) {
    return { ok: false, message: t('请先在设置中填写 API 地址'), attachment: null };
  }
  if (settings.apiKey.trim().length === 0) {
    return { ok: false, message: t('请先在设置中填写 API Key'), attachment: null };
  }
  const imageModel: string = model.trim().length > 0 ? model.trim() : settings.modelId;
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: requestHeaders(settings),
    extraData: buildImageGenBody(imageModel, prompt, normalizeImageSize(size)),
    connectTimeout: 20000,
    readTimeout: 180000,
    expectDataType: http.HttpDataType.STRING,
    usingCache: false
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(endpoint, options);
    const text: string = bodyText(response.result);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      const detail: string = text.length > 200 ? text.substring(0, 200) : text;
      return {
        ok: false,
        message: 'HTTP ' + response.responseCode.toString() +
          (detail.length > 0 ? t('：') + detail : ''),
        attachment: null
      };
    }
    const payload: ImageGenPayload = parseImageGenResponse(text);
    if (payload.error.length > 0) {
      return { ok: false, message: payload.error, attachment: null };
    }
    let bytes: Uint8Array | null = null;
    if (payload.b64.length > 0) {
      let raw: string = payload.b64;
      const comma: number = raw.indexOf(',');
      if (raw.startsWith('data:') && comma > 0) {
        raw = raw.substring(comma + 1);
      }
      try {
        bytes = validBytes(base64.decodeSync(raw));
      } catch (e) {
        bytes = null;
      }
    } else if (payload.url.length > 0) {
      bytes = await download(payload.url);
    }
    if (bytes === null) {
      return { ok: false, message: t('图片数据无效或超过 10 MB'), attachment: null };
    }
    const ext: string = detectImageExtension(bytes);
    if (ext.length === 0) {
      return { ok: false, message: t('无法识别的图片格式'), attachment: null };
    }
    const saved: AttachmentInfo | null = AttachmentStore.saveBytes(bytes, ext);
    if (saved === null) {
      return { ok: false, message: t('图片保存失败'), attachment: null };
    }
    return { ok: true, message: t('已生成图片'), attachment: saved };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('请求失败：') + error.message, attachment: null };
  } finally {
    request.destroy();
  }
}

/**
 * Binds the current settings to the tool interface. The runtime only sees the
 * handler, so API keys never travel through tool arguments or logs.
 */
export class SettingsImageGen implements ImageGenHandler {
  private settings: AppSettings;

  constructor(settings: AppSettings) {
    this.settings = settings;
  }

  async generate(request: ImageGenRequest): Promise<ToolResult> {
    const result: GeneratedImage = await generateImage(
      this.settings, request.prompt, request.size, request.model);
    if (!result.ok || result.attachment === null) {
      return { ok: false, content: result.message };
    }
    const uri: string = AttachmentStore.uriFor(result.attachment.name);
    return {
      ok: true,
      content: t('已生成图片并保存到本机：') + result.attachment.name +
        t('（可点开工具卡片查看）'),
      imageUri: uri,
      imageMimeType: result.attachment.mimeType
    };
  }
}
