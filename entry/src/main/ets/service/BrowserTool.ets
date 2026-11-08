import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { BrowserHandler, ToolResult } from '../core/ToolTypes';
import { normalizeWebUrl } from '../core/WebUrl';

const PAGE_LOAD_TIMEOUT_MS: number = 20000;
const DEFAULT_MAX_CHARS: number = 8000;
const MAX_CHARS: number = 20000;

/**
 * The hidden ArkWeb view registers its controller here. Keeping the binding in
 * a module singleton lets the tool runtime reach the UI-owned webview without
 * threading a controller through every service.
 */
export class BrowserHostRegistry {
  private controller: webview.WebviewController | null = null;
  private pageEnd: (() => void) | null = null;
  private waitToken: number = 0;

  attach(controller: webview.WebviewController): void {
    this.controller = controller;
  }

  detach(controller: webview.WebviewController): void {
    if (this.controller === controller) {
      this.controller = null;
      this.pageEnd = null;
      this.waitToken++;
    }
  }

  ready(): boolean {
    return this.controller !== null;
  }

  get(): webview.WebviewController | null {
    return this.controller;
  }

  /** Navigate and resolve true on page end, false on timeout. */
  load(url: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      const controller: webview.WebviewController | null = this.controller;
      if (controller === null) {
        resolve(false);
        return;
      }
      const token: number = ++this.waitToken;
      let settled: boolean = false;
      const done = (loaded: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(loaded);
      };
      this.pageEnd = () => {
        if (this.waitToken === token) {
          this.pageEnd = null;
          done(true);
        }
      };
      setTimeout(() => {
        if (this.waitToken === token && !settled) {
          this.pageEnd = null;
          done(false);
        }
      }, PAGE_LOAD_TIMEOUT_MS);
      try {
        controller.loadUrl(url);
      } catch (e) {
        done(false);
      }
    });
  }

  notifyPageEnd(): void {
    const callback: (() => void) | null = this.pageEnd;
    if (callback !== null) {
      this.pageEnd = null;
      callback();
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
  return text.substring(0, maxChars) + '\n…（已截断，共 ' + text.length.toString() + ' 字符）';
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

/**
 * `browser_use` implementation. Actions run against a hidden ArkWeb view so
 * they do not disturb the visible in-app browser. JavaScript is evaluated in
 * the page context; selectors and text are JSON-encoded before injection.
 */
export class BrowserTool implements BrowserHandler {
  private async evaluate(script: string): Promise<string> {
    const controller: webview.WebviewController | null = BrowserHost.get();
    if (controller === null) {
      throw new Error('内置浏览器尚未就绪');
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

  async execute(argumentsJson: string): Promise<ToolResult> {
    if (!BrowserHost.ready()) {
      return { ok: false, content: '内置浏览器尚未就绪，请稍后重试。' };
    }
    let args: BrowserArgs;
    try {
      args = JSON.parse(argumentsJson) as BrowserArgs;
    } catch (e) {
      return { ok: false, content: 'browser_use 参数不是合法 JSON。' };
    }
    const action: string = args.action !== undefined ? args.action.trim().toLowerCase() : '';
    const selector: string = args.selector !== undefined ? args.selector : '';
    const maxChars: number = clampNumber(args.max_chars, DEFAULT_MAX_CHARS, 100, MAX_CHARS);
    const controller: webview.WebviewController | null = BrowserHost.get();
    if (controller === null) {
      return { ok: false, content: '内置浏览器尚未就绪，请稍后重试。' };
    }

    try {
      if (action === 'open' || action === 'navigate') {
        const url: string = normalizeWebUrl(args.url !== undefined ? args.url : '');
        if (url.length === 0) {
          return { ok: false, content: 'open 需要 url。' };
        }
        const loaded: boolean = await BrowserHost.load(url);
        let title: string = '';
        try {
          title = await this.evaluate('document.title');
        } catch (e) {
          title = '';
        }
        let text: string = '已打开 ' + url;
        if (title.length > 0) {
          text += '\n标题：' + title;
        }
        if (!loaded) {
          text += '\n（页面加载超时，内容可能仍在加载）';
        }
        return { ok: true, content: text };
      }

      if (action === 'click') {
        if (selector.length === 0) {
          return { ok: false, content: 'click 需要 selector。' };
        }
        const result: string = await this.evaluate(
          '(() => { const el = document.querySelector(' + js(selector) + ');' +
          ' if (!el) return "NOT_FOUND"; el.scrollIntoView({block:"center"});' +
          ' el.click(); return "CLICKED"; })()');
        if (result === 'NOT_FOUND') {
          return { ok: false, content: '没有找到元素：' + selector };
        }
        return { ok: true, content: '已点击 ' + selector };
      }

      if (action === 'type') {
        if (selector.length === 0) {
          return { ok: false, content: 'type 需要 selector。' };
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
          return { ok: false, content: '没有找到元素：' + selector };
        }
        return { ok: true, content: '已向 ' + selector + ' 输入 ' + value.length.toString() + ' 个字符' };
      }

      if (action === 'text' || action === 'html') {
        const property: string = action === 'text' ? 'innerText' : 'outerHTML';
        const script: string = selector.length > 0
          ? '(() => { const el = document.querySelector(' + js(selector) + ');' +
            ' return el ? el.' + property + ' : "NOT_FOUND"; })()'
          : 'document.body ? document.body.' + property + ' : ""';
        const result: string = await this.evaluate(script);
        if (result === 'NOT_FOUND') {
          return { ok: false, content: '没有找到元素：' + selector };
        }
        const body: string = result.trim();
        if (body.length === 0) {
          return { ok: false, content: '页面或元素没有可读取的内容。' };
        }
        return { ok: true, content: truncate(body, maxChars) };
      }

      if (action === 'eval') {
        const script: string = args.script !== undefined ? args.script : '';
        if (script.trim().length === 0) {
          return { ok: false, content: 'eval 需要 script。' };
        }
        const result: string = await this.evaluate(script);
        return { ok: true, content: truncate(result, maxChars) };
      }

      if (action === 'title') {
        const title: string = await this.evaluate('document.title');
        return { ok: true, content: title.length > 0 ? title : '（页面没有标题）' };
      }

      if (action === 'url') {
        const url: string = await this.evaluate('location.href');
        return { ok: true, content: url };
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
        return { ok: true, content: action === 'back' ? '已后退'
          : (action === 'forward' ? '已前进' : '已刷新') };
      }

      if (action === 'wait') {
        const ms: number = clampNumber(args.milliseconds, 500, 50, 10000);
        await sleep(ms);
        return { ok: true, content: '已等待 ' + ms.toString() + ' 毫秒' };
      }

      return {
        ok: false,
        content: '未知动作：' + action +
          '（可用 open/click/type/text/html/eval/back/forward/reload/wait/title/url）'
      };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: '浏览器操作失败：' + error.message };
    }
  }
}
