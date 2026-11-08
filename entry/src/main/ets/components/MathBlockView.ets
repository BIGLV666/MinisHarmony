import { webview } from '@kit.ArkWeb';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { latexToText } from '../core/Latex';
import { scaleFont } from '../core/Types';

/**
 * Bridge object for the bundled KaTeX page. ArkWeb needs a plain object with
 * a fixed method list; keeping it separate from the component avoids exposing
 * ArkUI state to page scripts.
 */
class MathBridge {
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
 * Display math rendered by real KaTeX inside an ArkWeb view, matching
 * OpenMinis's bundled katex/mhchem assets. The page measures the formula and
 * reports its height, so the row grows to fit; wide formulas scroll sideways.
 * On a KaTeX syntax error the block falls back to the Unicode approximation
 * used for inline math.
 */
@Component
export struct MathBlockView {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop @Watch('onSourceChanged') source: string = '';
  @StorageProp('fontScale') fontScale: number = 1;
  @State boxHeight: number = 48;
  @State failed: boolean = false;
  @State fallback: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: MathBridge = new MathBridge();
  private ready: boolean = false;

  aboutToAppear(): void {
    this.fallback = latexToText(this.source);
    this.bridge.setHandler((width: number, height: number, error: string): void => {
      if (error.length > 0) {
        this.failed = true;
        return;
      }
      const next: number = Math.max(28, Math.ceil(height) + 6);
      if (next !== this.boxHeight) {
        this.boxHeight = next;
      }
    });
  }

  aboutToDisappear(): void {
    this.bridge.setHandler(null);
  }

  onSourceChanged(): void {
    this.fallback = latexToText(this.source);
    this.failed = false;
    if (this.ready) {
      this.draw();
    }
  }

  private isDark(): boolean {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      return false;
    }
  }

  private draw(): void {
    const script: string = 'renderMath(' + JSON.stringify(this.source) + ', true, ' +
      scaleFont(16, this.fontScale).toString() + ', ' +
      (this.isDark() ? 'true' : 'false') + ');';
    this.controller.runJavaScript(script).catch((error: Error) => {
      this.failed = true;
    });
  }

  @Builder
  fallbackBlock() {
    Text(this.fallback)
      .fontSize(scaleFont(14, this.fontScale))
      .fontFamily('monospace')
      .fontColor($r('app.color.text_primary'))
      .lineHeight(scaleFont(22, this.fontScale))
      .width('100%')
      .textAlign(TextAlign.Center)
      .copyOption(CopyOptions.LocalDevice)
  }

  build() {
    Column() {
      if (this.failed) {
        this.fallbackBlock()
      } else {
        Web({ src: $rawfile('katex/katex-render.html'), controller: this.controller })
          .width('100%')
          .height(this.boxHeight)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .javaScriptProxy({
            object: this.bridge,
            name: 'MinisBridge',
            methodList: ['onRendered'],
            controller: this.controller
          })
          // The formula box is fixed-height; let the chat list keep scrolling
          // when the finger drags vertically inside the Web view.
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.PARENT_FIRST
          })
          .onPageEnd(() => {
            this.ready = true;
            this.draw();
          })
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
  }
}
