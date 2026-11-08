import { webview } from '@kit.ArkWeb';
import { BrowserHost } from '../service/BrowserTool';

/**
 * Off-screen ArkWeb view driven by the `browser_use` tool. It stays mounted
 * for the whole session so the agent can navigate between tool calls. One
 * pixel with zero opacity keeps it out of the layout while still allowing
 * pages to run scripts.
 */
@Component
export struct HiddenBrowser {
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    BrowserHost.attach(this.controller);
  }

  aboutToDisappear(): void {
    BrowserHost.detach(this.controller);
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(1)
      .height(1)
      .opacity(0)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(false)
      .onPageEnd(() => {
        BrowserHost.notifyPageEnd();
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
