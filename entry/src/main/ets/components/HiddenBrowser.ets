import { webview } from '@kit.ArkWeb';
import { BrowserHost } from '../service/BrowserTool';

/**
 * Off-screen ArkWeb view driven by the `browser_use` tool. It stays mounted
 * for the whole session so the agent can navigate between tool calls. The
 * surface is full-size (for a real viewport and screenshots) but transparent
 * and non-interactive, so it never covers or intercepts the chat UI.
 */
@Component
export struct HiddenBrowser {
  private controller: webview.WebviewController = new webview.WebviewController();
  @Prop workspaceRoot: string = '';
  @State viewWidth: number = 0;
  @State viewHeight: number = 0;

  aboutToAppear(): void {
    BrowserHost.attach(this.controller);
    BrowserHost.setWorkspace(this.workspaceRoot);
    BrowserHost.setViewportHandler((width: number, height: number) => {
      this.viewWidth = width;
      this.viewHeight = height;
    });
  }

  aboutToDisappear(): void {
    BrowserHost.setViewportHandler(null);
    BrowserHost.detach(this.controller);
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(this.viewWidth > 0 ? this.viewWidth : '100%')
      .height(this.viewHeight > 0 ? this.viewHeight : '100%')
      .opacity(0)
      .focusable(false)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(false)
      .onPageEnd(() => {
        BrowserHost.notifyPageEnd();
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
