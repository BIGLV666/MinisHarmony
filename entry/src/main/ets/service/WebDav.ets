import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppSettings, StoredSession } from '../core/Types';
import { backupJson } from '../core/Backup';
import {
  WEBDAV_LATEST_NAME,
  normalizeWebDavUrl,
  webDavFileUrl,
  webDavUploadTargets
} from '../core/WebDav';
import { encryptBackupText } from './BackupCrypto';
import { t } from '../core/I18n';

const encoder: util.TextEncoder = new util.TextEncoder();
const base64: util.Base64Helper = new util.Base64Helper();
const MAX_REMOTE_CHARS: number = 32 * 1024 * 1024;

export interface WebDavOutcome {
  ok: boolean;
  message: string;
}

export interface WebDavDownload {
  ok: boolean;
  message: string;
  text: string;
}

function authHeader(settings: AppSettings): string {
  const raw: Uint8Array = encoder.encodeInto(
    settings.webDavUser + ':' + settings.webDavPassword);
  return 'Basic ' + base64.encodeToStringSync(raw);
}

function requestOptions(settings: AppSettings): http.HttpRequestOptions {
  const headers: Record<string, string> = {
    'Authorization': authHeader(settings),
    'Accept': 'application/json'
  };
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: headers,
    connectTimeout: 20000,
    readTimeout: 120000,
    expectDataType: http.HttpDataType.STRING,
    usingCache: false
  };
  return options;
}

function statusMessage(action: string, status: number, body: string): string {
  const detail: string = body.length > 160 ? body.substring(0, 160) : body;
  return action + t('失败：HTTP ') + status.toString() +
    (detail.length > 0 ? t('（') + detail + t('）') : '');
}

function configured(settings: AppSettings): string {
  if (normalizeWebDavUrl(settings.webDavUrl).length === 0) {
    return t('请先填写 WebDAV 地址（http 或 https）');
  }
  if (settings.webDavPassword.length === 0) {
    return t('请先填写 WebDAV 密码');
  }
  return '';
}

async function put(url: string, settings: AppSettings, body: string): Promise<WebDavOutcome> {
  const options: http.HttpRequestOptions = requestOptions(settings);
  options.method = http.RequestMethod.PUT;
  options.header = {
    'Authorization': authHeader(settings),
    'Content-Type': 'application/json; charset=utf-8'
  };
  options.extraData = body;
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(url, options);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        message: statusMessage(t('上传'), response.responseCode,
          typeof response.result === 'string' ? response.result : '')
      };
    }
    return { ok: true, message: '' };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('上传失败：') + error.message };
  } finally {
    request.destroy();
  }
}

/**
 * Encrypt the whole library with the WebDAV password and PUT a dated snapshot
 * plus `latest` (or only `latest` for automatic sync, to avoid one dated file
 * per turn). If the server rejects the first copy nothing is considered
 * uploaded.
 */
export async function uploadEncryptedBackup(
  settings: AppSettings,
  sessions: StoredSession[],
  now: Date,
  includeDated: boolean = true
): Promise<WebDavOutcome> {
  const problem: string = configured(settings);
  if (problem.length > 0) {
    return { ok: false, message: problem };
  }
  const targets: string[] = includeDated
    ? webDavUploadTargets(settings.webDavUrl, now)
    : [webDavFileUrl(settings.webDavUrl, WEBDAV_LATEST_NAME)];
  if (targets.length === 0 || targets[0].length === 0) {
    return { ok: false, message: t('WebDAV 地址无效') };
  }
  let sealed: string = '';
  try {
    const plain: string = backupJson(settings, sessions, now);
    sealed = await encryptBackupText(plain, settings.webDavPassword, now);
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('加密备份失败：') + error.message };
  }
  for (let i = 0; i < targets.length; i++) {
    const outcome: WebDavOutcome = await put(targets[i], settings, sealed);
    if (!outcome.ok) {
      return outcome;
    }
  }
  return {
    ok: true,
    message: t('已上传加密备份：') + sessions.length.toString() + t(' 个会话')
  };
}

/** Fetch the `latest` object; decryption and import happen in the caller. */
export async function downloadLatestBackup(
  settings: AppSettings
): Promise<WebDavDownload> {
  const problem: string = configured(settings);
  if (problem.length > 0) {
    return { ok: false, message: problem, text: '' };
  }
  const url: string = webDavFileUrl(settings.webDavUrl, WEBDAV_LATEST_NAME);
  if (url.length === 0) {
    return { ok: false, message: t('WebDAV 地址无效'), text: '' };
  }
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse =
      await request.request(url, requestOptions(settings));
    if (response.responseCode === 404) {
      return { ok: false, message: t('远端还没有备份'), text: '' };
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        message: statusMessage(t('下载'), response.responseCode,
          typeof response.result === 'string' ? response.result : ''),
        text: ''
      };
    }
    const text: string = typeof response.result === 'string' ? response.result : '';
    if (text.length === 0) {
      return { ok: false, message: t('远端备份是空的'), text: '' };
    }
    if (text.length > MAX_REMOTE_CHARS) {
      return { ok: false, message: t('远端备份超过 32 MB，拒绝导入'), text: '' };
    }
    return { ok: true, message: '', text: text };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('下载失败：') + error.message, text: '' };
  } finally {
    request.destroy();
  }
}
