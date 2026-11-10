import { webview, WebNetErrorList } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { BrowserHandler, ToolResult } from '../core/ToolTypes';
import { normalizeWebUrl } from '../core/WebUrl';
import {
  MINIS_ATTACHMENTS,
  MINIS_WORKSPACE,
  MinisResource,
  parseMinisResource
} from '../core/MinisResource';
import { t } from '../core/I18n';

const PAGE_LOAD_TIMEOUT_MS: number = 20000;
const DEFAULT_MAX_CHARS: number = 8000;
const MAX_CHARS: number = 20000;
const MAX_ELEMENTS: number = 50;
const MAX_TABS: number = 4;
const MAX_RESOURCE_BYTES: number = 64 * 1024 * 1024;

/**
 * Register the `minis` scheme before any Web component is created. Local HTML
 * opened through file:// can then load absolute `minis://workspace/...`
 * subresources (scripts, styles, images) through the scheme handler installed
 * on each hidden tab.
 */
export function registerMinisScheme(): void {
  try {
    const schemes: webview.WebCustomScheme[] = [{
      schemeName: 'minis',
      isSupportCORS: true,
      isSupportFetch: true,
      isStandard: true,
      isLocal: true
    }];
    webview.WebviewController.customizeSchemes(schemes);
  } catch (error) {
    // Another Web component already initialized the engine; file:// pages and
    // relative subresources still work, only absolute minis:// subresources
    // are affected.
  }
}

/** MIME type by file extension for scheme-handler responses. */
function mimeForPath(path: string): string {
  const dot: number = path.lastIndexOf('.');
  const ext: string = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'html':
    case 'htm':
      return 'text/html';
    case 'js':
    case 'mjs':
      return 'text/javascript';
    case 'css':
      return 'text/css';
    case 'json':
    case 'map':
      return 'application/json';
    case 'svg':
      return 'image/svg+xml';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    case 'ico':
      return 'image/x-icon';
    case 'woff':
      return 'font/woff';
    case 'woff2':
      return 'font/woff2';
    case 'ttf':
      return 'font/ttf';
    case 'otf':
      return 'font/otf';
    case 'xml':
      return 'application/xml';
    case 'pdf':
      return 'application/pdf';
    case 'wasm':
      return 'application/wasm';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'md':
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

/**
 * The hidden ArkWeb tabs register their controllers here. Keeping the binding
 * in a module singleton lets the tool runtime reach UI-owned webviews without
 * threading controllers through every service. Tab ids are allocated by the
 * tool and mirrored by the UI; ids start at 0 for the always-present tab.
 */
export class BrowserHostRegistry {
  private tabs: Map<number, webview.WebviewController> =
    new Map<number, webview.WebviewController>();
  private active: number = 0;
  private nextTabId: number = 1;
  private waiters: Map<number, (loaded: boolean) => void> =
    new Map<number, (loaded: boolean) => void>();
  private tabUrls: Map<number, string> = new Map<number, string>();
  private pendingAttach: Map<number, (ok: boolean) => void> =
    new Map<number, (ok: boolean) => void>();
  private createHandler: ((id: number) => void) | null = null;
  private closeHandler: ((id: number) => void) | null = null;
  private activeHandler: ((id: number) => void) | null = null;
  private workspace: string = '';
  private attachments: string = '';
  private viewportHandler: ((width: number, height: number) => void) | null = null;

  attach(id: number, controller: webview.WebviewController): void {
    this.tabs.set(id, controller);
    if (!this.tabs.has(this.active)) {
      this.active = id;
      this.publishActive();
    }
    const pending: ((ok: boolean) => void) | undefined = this.pendingAttach.get(id);
    if (pending !== undefined) {
      this.pendingAttach.delete(id);
      pending(true);
    }
  }

  detach(id: number, controller: webview.WebviewController): void {
    if (this.tabs.get(id) !== controller) {
      return;
    }
    this.tabs.delete(id);
    this.tabUrls.delete(id);
    const waiter: ((loaded: boolean) => void) | undefined = this.waiters.get(id);
    if (waiter !== undefined) {
      this.waiters.delete(id);
      waiter(false);
    }
    if (this.active === id) {
      this.active = this.firstTab();
      this.publishActive();
    }
  }

  private publishActive(): void {
    const handler: ((id: number) => void) | null = this.activeHandler;
    if (handler !== null) {
      handler(this.active);
    }
  }

  ready(): boolean {
    return this.tabs.size > 0;
  }

  private firstTab(): number {
    const ids: number[] = Array.from(this.tabs.keys());
    return ids.length > 0 ? ids[0] : 0;
  }

  private current(): webview.WebviewController | null {
    const controller: webview.WebviewController | undefined = this.tabs.get(this.active);
    if (controller !== undefined) {
      return controller;
    }
    const id: number = this.firstTab();
    const fallback: webview.WebviewController | undefined = this.tabs.get(id);
    if (fallback === undefined) {
      return null;
    }
    this.active = id;
    return fallback;
  }

  get(): webview.WebviewController | null {
    return this.current();
  }

  activeId(): number {
    return this.active;
  }

  hasTab(id: number): boolean {
    return this.tabs.has(id);
  }

  setActive(id: number): boolean {
    if (!this.tabs.has(id)) {
      return false;
    }
    this.active = id;
    this.publishActive();
    return true;
  }

  openIds(): number[] {
    return Array.from(this.tabs.keys()).sort((a: number, b: number) => a - b);
  }

  urlOf(id: number): string {
    const url: string | undefined = this.tabUrls.get(id);
    return url !== undefined ? url : '';
  }

  setTabHandlers(create: (id: number) => void, close: (id: number) => void): void {
    this.createHandler = create;
    this.closeHandler = close;
  }

  /** Lets the UI raise the active surface above the other hidden tabs. */
  setActiveHandler(handler: ((id: number) => void) | null): void {
    this.activeHandler = handler;
  }

  clearTabHandlers(): void {
    this.createHandler = null;
    this.closeHandler = null;
    this.activeHandler = null;
  }

  /** Ask the UI to mount a new hidden tab and wait for its controller. */
  createTab(): Promise<number> {
    return new Promise<number>((resolve: (id: number) => void) => {
      const create: ((id: number) => void) | null = this.createHandler;
      if (create === null || this.tabs.size >= MAX_TABS) {
        resolve(-1);
        return;
      }
      let id: number = this.nextTabId++;
      while (this.tabs.has(id)) {
        id = this.nextTabId++;
      }
      this.pendingAttach.set(id, (ok: boolean) => {
        if (ok) {
          this.active = id;
          this.publishActive();
        }
        resolve(ok ? id : -1);
      });
      setTimeout(() => {
        const pending: ((ok: boolean) => void) | undefined = this.pendingAttach.get(id);
        if (pending !== undefined) {
          this.pendingAttach.delete(id);
          pending(false);
        }
      }, 3000);
      create(id);
    });
  }

  closeTab(id: number): boolean {
    if (this.tabs.size <= 1 || !this.tabs.has(id)) {
      return false;
    }
    this.tabs.delete(id);
    this.tabUrls.delete(id);
    const waiter: ((loaded: boolean) => void) | undefined = this.waiters.get(id);
    if (waiter !== undefined) {
      this.waiters.delete(id);
      waiter(false);
    }
    if (this.active === id) {
      this.active = this.firstTab();
      this.publishActive();
    }
    const close: ((id: number) => void) | null = this.closeHandler;
    if (close !== null) {
      close(id);
    }
    return true;
  }

  /** Directory where screenshots and downloads are written. */
  setWorkspace(root: string): void {
    this.workspace = root;
  }

  workspaceRoot(): string {
    return this.workspace;
  }

  setAttachments(root: string): void {
    this.attachments = root;
  }

  /**
   * Map an in-app `minis://workspace/...` or `minis://attachments/...` URL to
   * a file URL the hidden webview can load. Returns an empty string for other
   * scopes or before the roots are known.
   */
  resolveResource(url: string): string {
    const full: string = this.resourcePath(url);
    if (full.length === 0) {
      return '';
    }
    return 'file://' + full.split('/').map((segment: string): string =>
      encodeURIComponent(segment)).join('/');
  }

  /** Absolute filesystem path for a `minis://` URL, or '' when unknown. */
  resourcePath(url: string): string {
    const resource: MinisResource | null = parseMinisResource(url);
    if (resource === null) {
      return '';
    }
    let base: string = '';
    if (resource.scope === MINIS_WORKSPACE) {
      base = this.workspace;
    } else if (resource.scope === MINIS_ATTACHMENTS) {
      base = this.attachments;
    }
    if (base.length === 0) {
      return '';
    }
    return base + '/' + resource.path;
  }

  /**
   * Install the `minis` scheme handler on one hidden tab. Custom-scheme
   * subresources bypass file:// origin rules, so local HTML can reference
   * workspace assets with absolute `minis://` URLs.
   */
  installSchemeHandler(controller: webview.WebviewController): void {
    const handler: webview.WebSchemeHandler = new webview.WebSchemeHandler();
    handler.onRequestStart((request: webview.WebSchemeHandlerRequest,
      resource: webview.WebResourceHandler): boolean => {
      const path: string = this.resourcePath(request.getRequestUrl());
      if (path.length === 0) {
        return false;
      }
      this.serveResource(path, resource);
      return true;
    });
    try {
      controller.setWebSchemeHandler('minis', handler);
    } catch (error) {
      // Controller not attached yet or scheme rejected; relative file://
      // assets keep working.
    }
  }

  private serveResource(path: string, handler: webview.WebResourceHandler): void {
    let fd: number = -1;
    try {
      const stat = fs.statSync(path);
      if (!stat.isFile() || stat.size > MAX_RESOURCE_BYTES) {
        handler.didFail(WebNetErrorList.ERR_FILE_NOT_FOUND);
        return;
      }
      const size: number = stat.size;
      let body: ArrayBuffer = new ArrayBuffer(0);
      if (size > 0) {
        const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        fd = file.fd;
        const allocated: ArrayBuffer = new ArrayBuffer(size);
        const read: number = fs.readSync(fd, allocated);
        body = read === size ? allocated : allocated.slice(0, read);
      }
      const mime: string = mimeForPath(path);
      const response = new webview.WebSchemeHandlerResponse();
      response.setStatus(200);
      response.setStatusText('OK');
      response.setMimeType(mime);
      response.setEncoding('utf-8');
      response.setHeaderByName('Content-Type', mime, true);
      response.setHeaderByName('Access-Control-Allow-Origin', '*', true);
      response.setHeaderByName('Cache-Control', 'no-cache', true);
      handler.didReceiveResponse(response);
      if (body.byteLength > 0) {
        handler.didReceiveResponseBody(body);
      }
      handler.didFinish();
    } catch (error) {
      try {
        handler.didFail(WebNetErrorList.ERR_FILE_NOT_FOUND);
      } catch (ignored) {
      }
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (ignored) {
        }
      }
    }
  }

  /**
   * The hidden view is full-screen behind the UI; pages need a real viewport
   * rather than the old 1x1 surface. `set_viewport` resizes it when the model
   * wants a specific layout size.
   */
  setViewportHandler(handler: ((width: number, height: number) => void) | null): void {
    this.viewportHandler = handler;
  }

  resizeViewport(width: number, height: number): boolean {
    if (this.viewportHandler === null) {
      return false;
    }
    this.viewportHandler(width, height);
    return true;
  }

  /** Navigate the active tab and resolve true on page end, false on timeout. */
  load(url: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      const controller: webview.WebviewController | null = this.current();
      if (controller === null) {
        resolve(false);
        return;
      }
      const id: number = this.active;
      // A newer navigation supersedes the previous one on this tab.
      const previous: ((loaded: boolean) => void) | undefined = this.waiters.get(id);
      if (previous !== undefined) {
        this.waiters.delete(id);
        previous(false);
      }
      let settled: boolean = false;
      const done = (loaded: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (this.waiters.get(id) === done) {
          this.waiters.delete(id);
        }
        resolve(loaded);
      };
      this.waiters.set(id, done);
      this.tabUrls.set(id, url);
      setTimeout(() => {
        done(false);
      }, PAGE_LOAD_TIMEOUT_MS);
      try {
        controller.loadUrl(url);
      } catch (e) {
        done(false);
      }
    });
  }

  notifyPageEnd(id: number): void {
    const callback: ((loaded: boolean) => void) | undefined = this.waiters.get(id);
    if (callback !== undefined) {
      this.waiters.delete(id);
      callback(true);
    }
  }
}

export const BrowserHost: BrowserHostRegistry = new BrowserHostRegistry();

interface BrowserArgs {
  action?: string;
  url?: string;
  selector?: string;
  text?: string;
  script?: string;
  max_chars?: number;
  milliseconds?: number;
  direction?: string;
  amount?: number;
  item_selector?: string;
  scroll_count?: number;
  cookies?: string;
  user_agent?: string;
  max_depth?: number;
  timeout?: number;
  viewport_width?: number;
  viewport_height?: number;
  reset?: boolean;
  keyword?: string;
  fuzzy?: boolean;
  tab_id?: number;
}

interface ViewportInfo {
  w: number;
  h: number;
}

interface CookieInput {
  name?: string;
  value?: string;
  domain?: string;
  path?: string;
  secure?: boolean;
  http_only?: boolean;
  httpOnly?: boolean;
  expires?: number;
}

function clampNumber(value: number | undefined, fallback: number, min: number, max: number): number {
  if (value === undefined || Number.isNaN(value)) {
    return fallback;
  }
  const rounded: number = Math.floor(value);
  if (rounded < min) {
    return min;
  }
  if (rounded > max) {
    return max;
  }
  return rounded;
}

/** JSON-encode a value for safe embedding inside generated JavaScript. */
function js(value: string): string {
  return JSON.stringify(value);
}

function truncate(text: string, maxChars: number): string {
  if (text.length <= maxChars) {
    return text;
  }
  return text.substring(0, maxChars) + t('\n…（已截断，共 ') + text.length.toString() + t(' 字符）');
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

function headerOf(headers: Record<string, string>, name: string): string {
  const keys: string[] = Object.keys(headers);
  const wanted: string = name.toLowerCase();
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === wanted) {
      const value: string = headers[keys[i]];
      return typeof value === 'string' ? value : '';
    }
  }
  return '';
}

function dispositionName(value: string): string {
  if (value.length === 0) {
    return '';
  }
  const star: RegExpMatchArray | null = value.match(/filename\*=UTF-8''([^;]+)/i);
  if (star !== null) {
    try {
      return decodeURIComponent(star[1]);
    } catch (e) {
      return star[1];
    }
  }
  const plain: RegExpMatchArray | null = value.match(/filename="?([^";]+)"?/i);
  return plain !== null ? plain[1] : '';
}

function urlFileName(url: string): string {
  const noHash: string = url.split('#')[0];
  const noQuery: string = noHash.split('?')[0];
  const cut: number = noQuery.lastIndexOf('/');
  const raw: string = cut >= 0 ? noQuery.substring(cut + 1) : '';
  if (raw.length === 0) {
    return '';
  }
  try {
    return decodeURIComponent(raw);
  } catch (e) {
    return raw;
  }
}

function extensionForMime(mime: string): string {
  const lower: string = mime.toLowerCase();
  if (lower.indexOf('text/html') >= 0) {
    return 'html';
  }
  if (lower.indexOf('application/json') >= 0) {
    return 'json';
  }
  if (lower.indexOf('text/plain') >= 0) {
    return 'txt';
  }
  if (lower.indexOf('text/css') >= 0) {
    return 'css';
  }
  if (lower.indexOf('javascript') >= 0) {
    return 'js';
  }
  if (lower.indexOf('image/png') >= 0) {
    return 'png';
  }
  if (lower.indexOf('image/jpeg') >= 0) {
    return 'jpg';
  }
  if (lower.indexOf('image/gif') >= 0) {
    return 'gif';
  }
  if (lower.indexOf('image/webp') >= 0) {
    return 'webp';
  }
  if (lower.indexOf('image/svg') >= 0) {
    return 'svg';
  }
  if (lower.indexOf('application/pdf') >= 0) {
    return 'pdf';
  }
  if (lower.indexOf('application/zip') >= 0) {
    return 'zip';
  }
  if (lower.indexOf('video/mp4') >= 0) {
    return 'mp4';
  }
  if (lower.indexOf('audio/mpeg') >= 0) {
    return 'mp3';
  }
  if (lower.indexOf('text/csv') >= 0) {
    return 'csv';
  }
  if (lower.indexOf('xml') >= 0) {
    return 'xml';
  }
  return 'bin';
}

function safeFileName(name: string): string {
  let out: string = name.replace(/[\\/:*?"<>|]/g, '_').replace(/^\.+/, '').trim();
  if (out.length === 0 || out === '.' || out === '..') {
    out = 'fetch.bin';
  }
  if (out.length > 80) {
    out = out.substring(out.length - 80);
  }
  return out;
}

function shellQuote(value: string): string {
  return "'" + value.replace(/'/g, "'\\''") + "'";
}

function formatBytes(size: number): string {
  if (size < 1024) {
    return size.toString() + ' B';
  }
  const kb: number = size / 1024;
  if (kb < 1024) {
    return kb.toFixed(1) + ' KB';
  }
  return (kb / 1024).toFixed(1) + ' MB';
}

const MOBILE_SAFARI_UA: string =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
const DESKTOP_SAFARI_UA: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

/**
 * `browser_use` implementation. Actions run against a hidden ArkWeb view so
 * they do not disturb the visible in-app browser. JavaScript is evaluated in
 * the page context; selectors and text are JSON-encoded before injection.
 */
export class BrowserTool implements BrowserHandler {
  private async evaluate(script: string): Promise<string> {
    const controller: webview.WebviewController | null = BrowserHost.get();
    if (controller === null) {
      throw new Error(t('内置浏览器尚未就绪'));
    }
    return new Promise<string>((resolve: (value: string) => void,
      reject: (reason: Error) => void) => {
      controller.runJavaScript(script, (error: BusinessError, result: string) => {
        if (error) {
          reject(new Error(error.message));
          return;
        }
        resolve(result !== undefined && result !== null ? result : '');
      });
    });
  }

  private async currentUrl(): Promise<string> {
    try {
      return await this.evaluate('location.href');
    } catch (e) {
      return '';
    }
  }

  /** Save a PNG of the current viewport into the workspace. */
  private async screenshot(maxChars: number): Promise<ToolResult> {
    const controller: webview.WebviewController | null = BrowserHost.get();
    if (controller === null) {
      return { ok: false, content: t('内置浏览器尚未就绪，请稍后重试。') };
    }
    const root: string = BrowserHost.workspaceRoot();
    if (root.length === 0) {
      return { ok: false, content: t('工作区尚未就绪，无法保存截图。') };
    }
    let viewport: ViewportInfo = { w: 412, h: 915 };
    try {
      const raw: string = await this.evaluate(
        'JSON.stringify({w: window.innerWidth || 412, h: window.innerHeight || 915})');
      const parsed: ViewportInfo = JSON.parse(raw) as ViewportInfo;
      if (parsed.w > 0 && parsed.h > 0) {
        viewport = parsed;
      }
    } catch (e) {
      // Fall back to a phone-sized viewport.
    }
    const width: number = clampNumber(viewport.w, 412, 100, 4000);
    const height: number = clampNumber(viewport.h, 915, 100, 4000);
    const info: webview.SnapshotInfo = {
      id: 'minis-browser',
      size: { width: width, height: height }
    };
    let shot: webview.SnapshotResult;
    try {
      shot = await new Promise<webview.SnapshotResult>(
        (resolve: (value: webview.SnapshotResult) => void,
          reject: (reason: Error) => void) => {
          controller.webPageSnapshot(info,
            (error: BusinessError, result: webview.SnapshotResult) => {
              if (error) {
                reject(new Error(error.message));
                return;
              }
              resolve(result);
            });
        });
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('截图失败：') + error.message };
    }
    const pixelMap: image.PixelMap | undefined = shot.imagePixelMap;
    if (shot.status !== true || pixelMap === undefined) {
      return { ok: false, content: t('截图失败：页面尚未完成渲染。') };
    }
    const dir: string = root + '/.minis-browser';
    const name: string = 'shot-' + Date.now().toString() + '.png';
    const path: string = dir + '/' + name;
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      fs.mkdirSync(dir, true);
      const option: image.PackingOption = { format: 'image/png', quality: 100 };
      const data: ArrayBuffer = await packer.packToData(pixelMap, option);
      const file: fs.File = fs.openSync(path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, data);
      } finally {
        fs.closeSync(file);
      }
      return {
        ok: true,
        content: truncate(t('截图已保存：') + path + '\n' +
          t('Markdown 链接：') + '[.minis-browser/' + name + '](minis://workspace/.minis-browser/' +
          name + ')', maxChars),
        imageUri: '.minis-browser/' + name,
        imageMimeType: 'image/png'
      };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('保存截图失败：') + error.message };
    } finally {
      pixelMap.release();
      packer.release().catch(() => {
        // Releasing a short-lived packer is best effort.
      });
    }
  }

  /**
   * Read cookies without echoing values into the transcript. Matching pairs
   * go to a shell-sourceable env file in the workspace (the OpenMinis
   * offload pattern); the tool result only lists names and lengths.
   */
  private async readCookies(keyword: string, fuzzy: boolean): Promise<ToolResult> {
    const url: string = await this.currentUrl();
    if (url.length === 0) {
      return { ok: false, content: t('页面尚未打开，无法读取 Cookie。') };
    }
    const root: string = BrowserHost.workspaceRoot();
    try {
      const raw: string = webview.WebCookieManager.fetchCookieSync(url);
      if (raw.length === 0) {
        return { ok: true, content: t('当前页面没有 Cookie。') };
      }
      const wanted: string = keyword.trim().toLowerCase();
      const names: string[] = [];
      const envLines: string[] = [];
      const used: Set<string> = new Set<string>();
      const parts: string[] = raw.split(';');
      for (let i = 0; i < parts.length; i++) {
        const pair: string = parts[i].trim();
        const eq: number = pair.indexOf('=');
        if (eq <= 0) {
          continue;
        }
        const name: string = pair.substring(0, eq).trim();
        const value: string = pair.substring(eq + 1);
        const lower: string = name.toLowerCase();
        if (wanted.length > 0 &&
          (fuzzy ? lower.indexOf(wanted) < 0 : lower !== wanted)) {
          continue;
        }
        names.push(name + ' · ' + value.length.toString() + t(' 字符'));
        let envName: string = 'MINIS_COOKIE_' +
          name.replace(/[^A-Za-z0-9]/g, '_').toUpperCase();
        if (used.has(envName)) {
          let suffix: number = 2;
          while (used.has(envName + '_' + suffix.toString())) {
            suffix++;
          }
          envName = envName + '_' + suffix.toString();
        }
        used.add(envName);
        envLines.push('export ' + envName + '=' + shellQuote(value));
      }
      if (names.length === 0) {
        return {
          ok: true,
          content: t('没有匹配的 Cookie（共 ') + parts.length.toString() + t(' 项）。')
        };
      }
      let content: string = t('Cookie（') + url + t('）：') +
        names.length.toString() + t(' 条\n') + names.join('\n');
      if (root.length > 0) {
        const dir: string = root + '/.minis-browser';
        const name: string = 'env_cookies_' + Date.now().toString() + '.sh';
        const path: string = dir + '/' + name;
        fs.mkdirSync(dir, true);
        const file: fs.File = fs.openSync(path,
          fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, envLines.join('\n') + '\n');
        } finally {
          fs.closeSync(file);
        }
        const relative: string = '.minis-browser/' + name;
        content += t('\n已写入 ') + relative + t('，可在 shell 中执行 ') +
          '. /var/minis/workspace/' + relative + t(' 后使用 MINIS_COOKIE_* 变量');
      }
      return { ok: true, content: truncate(content, MAX_CHARS) };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('读取 Cookie 失败：') + error.message };
    }
  }

  private async writeCookies(raw: string): Promise<ToolResult> {
    if (raw.trim().length === 0) {
      return { ok: false, content: t('set_cookies 需要 cookies（JSON 数组）。') };
    }
    let list: CookieInput[];
    try {
      list = JSON.parse(raw) as CookieInput[];
    } catch (e) {
      return { ok: false, content: t('cookies 不是合法 JSON 数组。') };
    }
    if (!Array.isArray(list)) {
      return { ok: false, content: t('cookies 必须是 JSON 数组。') };
    }
    const pageUrl: string = await this.currentUrl();
    let written: number = 0;
    try {
      for (let i = 0; i < list.length; i++) {
        const item: CookieInput = list[i];
        const name: string = item.name !== undefined ? item.name : '';
        if (name.length === 0) {
          continue;
        }
        const value: string = item.value !== undefined ? item.value : '';
        let cookie: string = name + '=' + value;
        if (item.path !== undefined && item.path.length > 0) {
          cookie += '; Path=' + item.path;
        }
        if (item.domain !== undefined && item.domain.length > 0) {
          cookie += '; Domain=' + item.domain;
        }
        if (item.secure === true) {
          cookie += '; Secure';
        }
        if (item.http_only === true || item.httpOnly === true) {
          cookie += '; HttpOnly';
        }
        if (item.expires !== undefined && item.expires > 0) {
          cookie += '; Expires=' + new Date(item.expires * 1000).toUTCString();
        }
        let target: string = pageUrl;
        if (item.domain !== undefined && item.domain.length > 0) {
          target = 'https://' + item.domain + '/';
        }
        if (target.length === 0) {
          return { ok: false, content: t('页面尚未打开，无法写入 Cookie。') };
        }
        const existing: string = webview.WebCookieManager.fetchCookieSync(target);
        const merged: string = existing.length > 0 ? existing + '; ' + cookie : cookie;
        webview.WebCookieManager.configCookieSync(target, merged);
        written++;
      }
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('写入 Cookie 失败：') + error.message };
    }
    return { ok: true, content: t('已写入 ') + written.toString() + t(' 条 Cookie') };
  }

  /**
   * Download a URL and store the raw bytes in the workspace, mirroring
   * OpenMinis' `fetch` action (which reports metadata and hands the file to
   * the agent rather than pasting a potentially binary body into the chat).
   */
  private async fetchResource(url: string): Promise<ToolResult> {
    if (url.trim().length === 0) {
      return { ok: false, content: t('fetch 需要 url。') };
    }
    const root: string = BrowserHost.workspaceRoot();
    if (root.length === 0) {
      return { ok: false, content: t('工作区尚未就绪，无法保存下载文件。') };
    }
    let target: string = url.trim();
    if (target.indexOf('http://') !== 0 && target.indexOf('https://') !== 0) {
      try {
        target = await this.evaluate('new URL(' + js(target) + ', location.href).href');
      } catch (e) {
        return { ok: false, content: t('无法解析相对地址：') + url };
      }
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      try {
        const cookie: string = webview.WebCookieManager.fetchCookieSync(target);
        if (cookie.length > 0) {
          headers['Cookie'] = cookie;
        }
      } catch (e) {
        // The cookie store may not be ready yet; fetch without it.
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 20000,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        header: headers
      };
      const response: http.HttpResponse = await request.request(target, options);
      const status: number = response.responseCode;
      const data: ArrayBuffer = response.result as ArrayBuffer;
      const headerText: string = JSON.stringify(response.header);
      const responseHeaders: Record<string, string> = JSON.parse(headerText) as Record<string, string>;
      const contentType: string = headerOf(responseHeaders, 'content-type');
      const disposition: string = headerOf(responseHeaders, 'content-disposition');
      let name: string = dispositionName(disposition);
      if (name.length === 0) {
        name = urlFileName(target);
      }
      if (name.length === 0) {
        name = 'fetch.' + extensionForMime(contentType);
      }
      const stamp: string = Date.now().toString();
      const fileName: string = stamp + '_' + safeFileName(name);
      const dir: string = root + '/.minis-browser';
      const path: string = dir + '/' + fileName;
      fs.mkdirSync(dir, true);
      const file: fs.File = fs.openSync(path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, data);
      } finally {
        fs.closeSync(file);
      }
      const relative: string = '.minis-browser/' + fileName;
      const lines: string = t('已下载 ') + target + '\n' +
        t('状态：') + status.toString() + '\n' +
        t('类型：') + (contentType.length > 0 ? contentType : t('未知')) + '\n' +
        t('大小：') + formatBytes(data.byteLength) + '\n' +
        t('文件：') + relative + '\n' +
        t('Markdown 链接：') + '[' + fileName + '](minis://workspace/' + relative + ')';
      return { ok: true, content: lines };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('请求失败：') + error.message };
    } finally {
      request.destroy();
    }
  }

  async execute(argumentsJson: string): Promise<ToolResult> {
    if (!BrowserHost.ready()) {
      return { ok: false, content: t('内置浏览器尚未就绪，请稍后重试。') };
    }
    let args: BrowserArgs;
    try {
      args = JSON.parse(argumentsJson) as BrowserArgs;
    } catch (e) {
      return { ok: false, content: t('browser_use 参数不是合法 JSON。') };
    }
    const action: string = args.action !== undefined ? args.action.trim().toLowerCase() : '';
    const selector: string = args.selector !== undefined ? args.selector : '';
    const maxChars: number = clampNumber(args.max_chars, DEFAULT_MAX_CHARS, 100, MAX_CHARS);
    if (args.tab_id !== undefined && action !== 'new_tab' && action !== 'list_tabs') {
      if (!BrowserHost.setActive(args.tab_id)) {
        return { ok: false, content: t('标签页不存在：') + args.tab_id.toString() };
      }
    }
    const controller: webview.WebviewController | null = BrowserHost.get();
    if (controller === null) {
      return { ok: false, content: t('内置浏览器尚未就绪，请稍后重试。') };
    }

    try {
      if (action === 'open' || action === 'navigate') {
        const requested: string = args.url !== undefined ? args.url.trim() : '';
        if (requested.length === 0) {
          return { ok: false, content: t('open 需要 url。') };
        }
        let target: string = '';
        if (parseMinisResource(requested) !== null) {
          target = BrowserHost.resolveResource(requested);
          if (target.length === 0) {
            return { ok: false, content: t('无法打开本地资源：') + requested };
          }
        } else {
          target = normalizeWebUrl(requested);
        }
        const loaded: boolean = await BrowserHost.load(target);
        let title: string = '';
        try {
          title = await this.evaluate('document.title');
        } catch (e) {
          title = '';
        }
        let text: string = t('已打开 ') + requested;
        if (title.length > 0) {
          text += t('\n标题：') + title;
        }
        if (!loaded) {
          text += t('\n（页面加载超时，内容可能仍在加载）');
        }
        return { ok: true, content: text };
      }

      if (action === 'click') {
        if (selector.length === 0) {
          return { ok: false, content: t('click 需要 selector。') };
        }
        const result: string = await this.evaluate(
          '(() => { const el = document.querySelector(' + js(selector) + ');' +
          ' if (!el) return "NOT_FOUND"; el.scrollIntoView({block:"center"});' +
          ' el.click(); return "CLICKED"; })()');
        if (result === 'NOT_FOUND') {
          return { ok: false, content: t('没有找到元素：') + selector };
        }
        return { ok: true, content: t('已点击 ') + selector };
      }

      if (action === 'type') {
        if (selector.length === 0) {
          return { ok: false, content: t('type 需要 selector。') };
        }
        const value: string = args.text !== undefined ? args.text : '';
        const result: string = await this.evaluate(
          '(() => { const el = document.querySelector(' + js(selector) + ');' +
          ' if (!el) return "NOT_FOUND";' +
          ' const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype' +
          ' : HTMLInputElement.prototype;' +
          ' const setter = Object.getOwnPropertyDescriptor(proto, "value").set;' +
          ' setter.call(el, ' + js(value) + ');' +
          ' el.dispatchEvent(new Event("input", {bubbles:true}));' +
          ' el.dispatchEvent(new Event("change", {bubbles:true}));' +
          ' return "TYPED"; })()');
        if (result === 'NOT_FOUND') {
          return { ok: false, content: t('没有找到元素：') + selector };
        }
        return { ok: true, content: t('已向 ') + selector + t(' 输入 ') + value.length.toString() + t(' 个字符') };
      }

      if (action === 'text' || action === 'get_text' || action === 'html') {
        const property: string = action === 'html' ? 'outerHTML' : 'innerText';
        const script: string = selector.length > 0
          ? '(() => { const el = document.querySelector(' + js(selector) + ');' +
            ' return el ? el.' + property + ' : "NOT_FOUND"; })()'
          : 'document.body ? document.body.' + property + ' : ""';
        const result: string = await this.evaluate(script);
        if (result === 'NOT_FOUND') {
          return { ok: false, content: t('没有找到元素：') + selector };
        }
        const body: string = result.trim();
        if (body.length === 0) {
          return { ok: false, content: t('页面或元素没有可读取的内容。') };
        }
        return { ok: true, content: truncate(body, maxChars) };
      }

      if (action === 'eval' || action === 'execute_js') {
        const script: string = args.script !== undefined ? args.script : '';
        if (script.trim().length === 0) {
          return { ok: false, content: t('eval 需要 script。') };
        }
        const result: string = await this.evaluate(script);
        return { ok: true, content: truncate(result, maxChars) };
      }

      if (action === 'title') {
        const title: string = await this.evaluate('document.title');
        return { ok: true, content: title.length > 0 ? title : t('（页面没有标题）') };
      }

      if (action === 'url') {
        const url: string = await this.evaluate('location.href');
        return { ok: true, content: url };
      }

      if (action === 'scroll') {
        const down: boolean = (args.direction !== undefined ?
          args.direction.toLowerCase() : 'down') !== 'up';
        const amount: number = clampNumber(args.amount, 600, 1, 20000);
        const delta: number = down ? amount : -amount;
        const script: string = selector.length > 0
          ? '(() => { const el = document.querySelector(' + js(selector) + ');' +
            ' if (!el) return "NOT_FOUND"; el.scrollBy({top:' + delta.toString() +
            ', behavior:"instant"}); return "OK"; })()'
          : 'window.scrollBy({top:' + delta.toString() + ', behavior:"instant"}); "OK"';
        const result: string = await this.evaluate(script);
        if (result === 'NOT_FOUND') {
          return { ok: false, content: t('没有找到元素：') + selector };
        }
        const position: string = await this.evaluate(
          'JSON.stringify({x: window.scrollX, y: window.scrollY, h: window.innerHeight})');
        return { ok: true, content: t('已滚动 ') + amount.toString() + t(' 像素，') + position };
      }

      if (action === 'get_page_info') {
        const info: string = await this.evaluate(
          'JSON.stringify({' +
          'url: location.href, title: document.title, readyState: document.readyState,' +
          'viewport: {width: window.innerWidth, height: window.innerHeight},' +
          'scroll: {x: window.scrollX, y: window.scrollY},' +
          'page: {width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight},' +
          'links: document.links.length, forms: document.forms.length,' +
          'images: document.images.length, textLength: (document.body ? document.body.innerText.length : 0)' +
          '})');
        return { ok: true, content: truncate(info, maxChars) };
      }

      if (action === 'find_elements') {
        if (selector.length === 0) {
          return { ok: false, content: t('find_elements 需要 selector。') };
        }
        const limit: number = clampNumber(args.amount, MAX_ELEMENTS, 1, MAX_ELEMENTS);
        const result: string = await this.evaluate(
          '(() => { const nodes = Array.from(document.querySelectorAll(' + js(selector) + '))' +
          '.slice(0, ' + limit.toString() + ');' +
          ' const out = nodes.map((el) => {' +
          ' const r = el.getBoundingClientRect();' +
          ' return {tag: el.tagName.toLowerCase(), id: el.id || "",' +
          ' classes: (el.className && typeof el.className === "string") ? el.className : "",' +
          ' text: (el.innerText || el.value || "").trim().slice(0, 120),' +
          ' href: el.href || "", rect: {x: Math.round(r.x), y: Math.round(r.y),' +
          ' width: Math.round(r.width), height: Math.round(r.height)}};' +
          ' }); return JSON.stringify({count: nodes.length, elements: out}); })()');
        return { ok: true, content: truncate(result, maxChars) };
      }

      if (action === 'hover') {
        if (selector.length === 0) {
          return { ok: false, content: t('hover 需要 selector。') };
        }
        const result: string = await this.evaluate(
          '(() => { const el = document.querySelector(' + js(selector) + ');' +
          ' if (!el) return "NOT_FOUND"; el.scrollIntoView({block:"center"});' +
          ' for (const type of ["mouseover", "mouseenter", "mousemove"]) {' +
          ' el.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true, view: window})); }' +
          ' return "HOVERED"; })()');
        if (result === 'NOT_FOUND') {
          return { ok: false, content: t('没有找到元素：') + selector };
        }
        return { ok: true, content: t('已悬停 ') + selector };
      }

      if (action === 'get_readable') {
        const result: string = await this.evaluate(
          '(() => {' +
          ' let source = null;' +
          (selector.length > 0
            ? ' source = document.querySelector(' + js(selector) + ');'
            : ' const candidates = ["article", "[role=\\"main\\"]", "main", ".post-content",' +
              ' ".article-body", ".entry-content", "#content", ".content"];' +
              ' for (const sel of candidates) {' +
              ' const found = document.querySelector(sel);' +
              ' if (found && getComputedStyle(found).display !== "none" &&' +
              ' (found.innerText || "").length > 0) { source = found; break; } }') +
          ' if (!source) source = document.body;' +
          ' if (!source) return "";' +
          ' const copy = source.cloneNode(true);' +
          ' copy.querySelectorAll("script,style,noscript,nav,footer,header,aside,form,svg,iframe").forEach((el) => el.remove());' +
          ' const body = (copy.innerText || copy.textContent || "").replace(/\\s+/g, " ").trim();' +
          ' const title = (document.title || "").trim();' +
          ' return title.length > 0 ? title + "\\n\\n" + body : body; })()');
        const body: string = result.trim();
        if (body.length === 0) {
          return { ok: false, content: t('页面没有可读正文。') };
        }
        return { ok: true, content: truncate(body, maxChars) };
      }

      if (action === 'get_backbone') {
        const depth: number = clampNumber(args.max_depth, 5, 1, 12);
        const result: string = await this.evaluate(
          '(() => { const interesting = new Set(["A","BUTTON","INPUT","SELECT","TEXTAREA",' +
          '"H1","H2","H3","H4","IMG","FORM","TABLE","NAV","MAIN","ARTICLE"]);' +
          ' const walk = (el, level) => {' +
          ' if (!el || level > ' + depth.toString() + ') return null;' +
          ' const tag = el.tagName ? el.tagName.toLowerCase() : "";' +
          ' const children = Array.from(el.children || []);' +
          ' const keep = interesting.has(el.tagName) || el.id || el.getAttribute("role");' +
          ' if (!keep && children.length === 0) return null;' +
          ' const node = {tag: tag, id: el.id || "", role: el.getAttribute ? (el.getAttribute("role") || "") : ""};' +
          ' if (el.href) node.href = el.href;' +
          ' const text = (el.innerText || "").trim();' +
          ' if (text) node.text = text.slice(0, 80);' +
          ' const kids = children.map((c) => walk(c, level + 1)).filter((n) => n);' +
          ' if (kids.length) node.children = kids;' +
          ' return node; };' +
          ' const tree = walk(document.body, 0);' +
          ' return JSON.stringify({backbone: tree ? [tree] : [], maxDepth: ' + depth.toString() + '}); })()');
        return { ok: true, content: truncate(result, maxChars) };
      }

      if (action === 'get_cookies') {
        const keyword: string = args.keyword !== undefined ? args.keyword : '';
        return await this.readCookies(keyword, args.fuzzy !== false);
      }

      if (action === 'set_cookies') {
        return await this.writeCookies(args.cookies !== undefined ? args.cookies : '');
      }

      if (action === 'set_user_agent') {
        const raw: string = args.user_agent !== undefined ? args.user_agent.trim() : '';
        const lower: string = raw.toLowerCase();
        let ua: string = raw;
        if (lower === 'mobile_safari' || lower === 'mobile') {
          ua = MOBILE_SAFARI_UA;
        } else if (lower === 'desktop_safari' || lower === 'desktop') {
          ua = DESKTOP_SAFARI_UA;
        } else if (lower === 'default' || lower.length === 0) {
          ua = webview.WebviewController.getDefaultUserAgent();
        }
        const before: string = await this.currentUrl();
        controller.setCustomUserAgent(ua);
        // ArkWeb applies a custom UA on the next load, so re-open the page.
        if (before.length > 0 && before !== 'about:blank') {
          try {
            controller.loadUrl(before);
          } catch (e) {
            // Keep the UA even if reload fails.
          }
        }
        await sleep(300);
        return { ok: true, content: t('已设置 User-Agent：') + ua };
      }

      if (action === 'set_viewport') {
        if (args.reset === true) {
          if (!BrowserHost.resizeViewport(0, 0)) {
            return { ok: false, content: t('当前视图无法调整视口。') };
          }
          await sleep(200);
          return { ok: true, content: t('已恢复默认视口。') };
        }
        const width: number = clampNumber(args.viewport_width, 412, 200, 4000);
        const height: number = clampNumber(args.viewport_height, 915, 200, 4000);
        if (!BrowserHost.resizeViewport(width, height)) {
          return { ok: false, content: t('当前视图无法调整视口。') };
        }
        await sleep(300);
        return { ok: true, content: t('已设置视口：') + width.toString() + '×' + height.toString() };
      }

      if (action === 'wait_for_dom_stable') {
        const limit: number = clampNumber(args.timeout, 10000, 500, 20000);
        const began: number = Date.now();
        let previous: string = '';
        let stable: number = 0;
        while (Date.now() - began < limit) {
          let signature: string = '';
          try {
            signature = await this.evaluate(
              'JSON.stringify({n: document.getElementsByTagName("*").length,' +
              ' t: document.body ? document.body.innerText.length : 0})');
          } catch (e) {
            signature = '';
          }
          if (signature.length > 0 && signature === previous) {
            stable++;
            if (stable >= 2) {
              return {
                ok: true,
                content: t('DOM 已稳定（') + (Date.now() - began).toString() + t(' ms）') +
                  '\n' + signature
              };
            }
          } else {
            stable = 0;
          }
          previous = signature;
          await sleep(500);
        }
        return { ok: true, content: t('等待 DOM 稳定超时（') + limit.toString() + t(' ms），页面可能仍在更新。') };
      }

      if (action === 'scroll_and_collect') {
        const down: boolean = (args.direction !== undefined ?
          args.direction.toLowerCase() : 'down') !== 'up';
        const amount: number = clampNumber(args.amount, 800, 100, 20000);
        const count: number = clampNumber(args.scroll_count, 5, 1, 20);
        const itemSelector: string = args.item_selector !== undefined ? args.item_selector : '';
        const seen: Set<string> = new Set<string>();
        const lines: string[] = [];
        for (let i = 0; i < count; i++) {
          const chunk: string = await this.evaluate(itemSelector.length > 0
            ? '(() => { const out = Array.from(document.querySelectorAll(' + js(itemSelector) + '))' +
              '.map((el) => (el.innerText || "").trim()).filter(Boolean);' +
              ' return out.join("\\n"); })()'
            : 'document.body ? document.body.innerText : ""');
          const rows: string[] = chunk.split('\n');
          for (let row = 0; row < rows.length; row++) {
            const line: string = rows[row].trim();
            if (line.length > 0 && !seen.has(line)) {
              seen.add(line);
              lines.push(line);
            }
          }
          if (i + 1 < count) {
            const delta: number = down ? amount : -amount;
            await this.evaluate('window.scrollBy({top:' + delta.toString() +
              ', behavior:"instant"}); "OK"');
            await sleep(350);
          }
        }
        if (lines.length === 0) {
          return { ok: false, content: t('页面没有可读取的内容。') };
        }
        return { ok: true, content: truncate(lines.join('\n'), maxChars) };
      }

      if (action === 'screenshot' || action === 'capture') {
        return await this.screenshot(maxChars);
      }

      if (action === 'fetch') {
        return await this.fetchResource(args.url !== undefined ? args.url : '');
      }

      if (action === 'new_tab') {
        const id: number = await BrowserHost.createTab();
        if (id < 0) {
          return {
            ok: false,
            content: t('无法新建标签页：浏览器未就绪或已达到 4 个上限。')
          };
        }
        let text: string = t('已新建标签页 #') + id.toString();
        const requested: string = args.url !== undefined ? args.url.trim() : '';
        if (requested.length > 0) {
          let target: string = '';
          if (parseMinisResource(requested) !== null) {
            target = BrowserHost.resolveResource(requested);
          } else {
            target = normalizeWebUrl(requested);
          }
          if (target.length === 0) {
            text += t('，但地址无法打开：') + requested;
          } else {
            const loaded: boolean = await BrowserHost.load(target);
            text += t('，已打开 ') + requested;
            if (!loaded) {
              text += t('（加载超时）');
            }
          }
        }
        return { ok: true, content: text };
      }

      if (action === 'close_tab') {
        const id: number = args.tab_id !== undefined ? args.tab_id : BrowserHost.activeId();
        if (!BrowserHost.closeTab(id)) {
          return {
            ok: false,
            content: t('无法关闭标签页：它不存在或这是最后一个标签页。')
          };
        }
        return { ok: true, content: t('已关闭标签页 #') + id.toString() };
      }

      if (action === 'list_tabs') {
        const ids: number[] = BrowserHost.openIds();
        const active: number = BrowserHost.activeId();
        const lines: string[] = [];
        for (let i = 0; i < ids.length; i++) {
          const mark: string = ids[i] === active ? '* ' : '  ';
          const url: string = BrowserHost.urlOf(ids[i]);
          lines.push(mark + '#' + ids[i].toString() + (url.length > 0 ? ' ' + url : ''));
        }
        return { ok: true, content: t('标签页：\n') + lines.join('\n') };
      }

      if (action === 'back' || action === 'forward' || action === 'reload') {
        if (action === 'back') {
          controller.backward();
        } else if (action === 'forward') {
          controller.forward();
        } else {
          controller.refresh();
        }
        await sleep(400);
        return { ok: true, content: action === 'back' ? t('已后退')
          : (action === 'forward' ? t('已前进') : t('已刷新')) };
      }

      if (action === 'wait') {
        const ms: number = clampNumber(args.milliseconds, 500, 50, 10000);
        await sleep(ms);
        return { ok: true, content: t('已等待 ') + ms.toString() + t(' 毫秒') };
      }

      return {
        ok: false,
        content: t('未知动作：') + action +
          t('（可用 open/navigate/click/type/text/get_text/html/eval/execute_js/back/forward/reload/wait/title/url/') +
          t('scroll/get_page_info/find_elements/hover/get_readable/get_backbone/get_cookies/set_cookies/') +
          t('set_user_agent/set_viewport/wait_for_dom_stable/scroll_and_collect/screenshot/fetch/') +
          t('new_tab/close_tab/list_tabs）')
      };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: t('浏览器操作失败：') + error.message };
    }
  }
}
