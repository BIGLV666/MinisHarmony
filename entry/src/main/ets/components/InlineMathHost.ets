import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  InlineMathBitmap,
  InlineMathCache,
  InlineMathRenderer
} from '../service/InlineMathCache';

const HOST_WIDTH: number = 720;
const HOST_HEIGHT: number = 180;
const MEASURE_TIMEOUT_MS: number = 4000;
const READY_TIMEOUT_MS: number = 8000;

class InlineMathBridge {
  private handler: ((width: number, height: number, error: string) => void) | null = null;

  setHandler(handler: ((width: number, height: number, error: string) => void) | null): void {
    this.handler = handler;
  }

  onRendered(width: number, height: number, error: string): void {
    const target: ((width: number, height: number, error: string) => void) | null =
      this.handler;
    if (target !== null) {
      target(width, height, error);
    }
  }
}

/**
 * Offscreen KaTeX host for inline math. Mounted once at the app root, behind
 * the chat UI, it renders one formula at a time and snapshots the tiny region
 * into a PixelMap. `MarkdownView` then displays that bitmap with `ImageSpan`,
 * which is the HarmonyOS equivalent of the Android WebView-pool + inline
 * placeholder pipeline in OpenMinis.
 */
@Component
export struct InlineMathHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: InlineMathBridge = new InlineMathBridge();
  private ready: boolean = false;
  private measuring: ((width: number, height: number, error: string) => void) | null = null;

  aboutToAppear(): void {
    this.bridge.setHandler((width: number, height: number, error: string): void => {
      const target: ((width: number, height: number, error: string) => void) | null =
        this.measuring;
      this.measuring = null;
      if (target !== null) {
        target(width, height, error);
      }
    });
    const renderer: InlineMathRenderer =
      (latex: string, fontSize: number, dark: boolean): Promise<InlineMathBitmap> =>
        this.render(latex, fontSize, dark);
    InlineMathCache.setRenderer(renderer);
  }

  aboutToDisappear(): void {
    InlineMathCache.setRenderer(null);
    this.bridge.setHandler(null);
    this.measuring = null;
  }

  private waitReady(): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      const started: number = Date.now();
      const poll = (): void => {
        if (this.ready) {
          resolve();
          return;
        }
        if (Date.now() - started > READY_TIMEOUT_MS) {
          reject(new Error('inline math host not ready'));
          return;
        }
        setTimeout(poll, 100);
      };
      poll();
    });
  }

  private measure(latex: string, fontSize: number, dark: boolean): Promise<number[]> {
    return new Promise<number[]>((resolve: (value: number[]) => void,
      reject: (reason: Error) => void) => {
      let settled: boolean = false;
      const timer: number = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        this.measuring = null;
        reject(new Error('inline math measure timeout'));
      }, MEASURE_TIMEOUT_MS);
      this.measuring = (width: number, height: number, error: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        if (error.length > 0) {
          reject(new Error(error));
          return;
        }
        resolve([width, height]);
      };
      const script: string = 'renderMath(' + JSON.stringify(latex) + ', false, ' +
        fontSize.toFixed(1) + ', ' + (dark ? 'true' : 'false') + ');';
      this.controller.runJavaScript(script).catch((error: Error) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        this.measuring = null;
        reject(error);
      });
    });
  }

  private snapshot(width: number, height: number): Promise<webview.SnapshotResult> {
    const info: webview.SnapshotInfo = {
      id: 'minis-inline-math',
      size: {
        width: Math.max(1, Math.min(HOST_WIDTH, Math.ceil(width))),
        height: Math.max(1, Math.min(HOST_HEIGHT, Math.ceil(height)))
      }
    };
    return new Promise<webview.SnapshotResult>(
      (resolve: (value: webview.SnapshotResult) => void,
        reject: (reason: Error) => void) => {
        let settled: boolean = false;
        // A destroyed controller never calls back; time out so the shared
        // queue cannot stay busy forever after a page rebuild.
        const timer: number = setTimeout(() => {
          if (settled) {
            return;
          }
          settled = true;
          reject(new Error('inline math snapshot timeout'));
        }, MEASURE_TIMEOUT_MS);
        this.controller.webPageSnapshot(info,
          (error: BusinessError, result: webview.SnapshotResult) => {
            if (settled) {
              return;
            }
            settled = true;
            clearTimeout(timer);
            if (error) {
              reject(new Error(error.message));
              return;
            }
            resolve(result);
          });
      });
  }

  private async render(latex: string, fontSize: number,
    dark: boolean): Promise<InlineMathBitmap> {
    await this.waitReady();
    const size: number[] = await this.measure(latex, fontSize, dark);
    if (size[0] <= 0 || size[1] <= 0) {
      throw new Error('empty formula');
    }
    // The page has already waited two animation frames; the extra tick
    // covers the bridge round trip so the snapshot sees this frame.
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 32);
    });
    const shot: webview.SnapshotResult = await this.snapshot(size[0], size[1]);
    const pixelMap: image.PixelMap | undefined = shot.imagePixelMap;
    if (shot.status !== true || pixelMap === undefined) {
      throw new Error('inline math snapshot failed');
    }
    const info: image.ImageInfo = pixelMap.getImageInfoSync();
    return new InlineMathBitmap(pixelMap, info.size.width, info.size.height);
  }

  build() {
    Web({ src: $rawfile('katex/katex-render.html'), controller: this.controller })
      .width(HOST_WIDTH)
      .height(HOST_HEIGHT)
      .opacity(0)
      .zIndex(-1)
      .focusable(false)
      .hitTestBehavior(HitTestMode.None)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .javaScriptProxy({
        object: this.bridge,
        name: 'MinisBridge',
        methodList: ['onRendered'],
        controller: this.controller
      })
      .onPageEnd(() => {
        this.ready = true;
        InlineMathCache.setRenderer(
          (latex: string, fontSize: number, dark: boolean): Promise<InlineMathBitmap> =>
            this.render(latex, fontSize, dark));
      })
  }
}
