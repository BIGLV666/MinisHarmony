import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BrowserHost } from '../service/BrowserTool';

/**
 * One off-screen ArkWeb surface. Tabs are separate components so each keeps
 * its own controller, history and page state; the agent can create up to four.
 */
@Component
struct HiddenTab {
  tabId: number = 0;
  // Raised above the other transparent surfaces; also makes the active tab the
  // last one hit test would consider if the container ever became interactive.
  @Prop active: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    BrowserHost.attach(this.tabId, this.controller);
  }

  aboutToDisappear(): void {
    BrowserHost.detach(this.tabId, this.controller);
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width('100%')
      .height('100%')
      .opacity(0)
      .zIndex(this.active ? 1 : 0)
      .focusable(false)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      // Local workspace/attachment HTML is opened through file:// URLs.
      .fileAccess(true)
      .onControllerAttached(() => {
        BrowserHost.installSchemeHandler(this.controller);
      })
      .onPageEnd(() => {
        BrowserHost.notifyPageEnd(this.tabId);
      })
      .hitTestBehavior(HitTestMode.None)
  }
}

/**
 * Off-screen tab pool driven by the `browser_use` tool. It stays mounted for
 * the whole session so the agent can navigate between tool calls. The tab 0
 * surface exists from the start; new tabs are mounted on demand and removed
 * when closed. Surfaces are transparent and non-interactive, so they never
 * cover or intercept the chat UI.
 */
@Component
export struct HiddenBrowser {
  @Prop workspaceRoot: string = '';
  @State tabIds: number[] = [0];
  @State activeId: number = 0;
  @State viewWidth: number = 0;
  @State viewHeight: number = 0;

  aboutToAppear(): void {
    BrowserHost.setTabHandlers(
      (id: number): void => {
        this.tabIds = this.tabIds.concat([id]);
      },
      (id: number): void => {
        this.tabIds = this.tabIds.filter((item: number) => item !== id);
      }
    );
    BrowserHost.setActiveHandler((id: number): void => {
      this.activeId = id;
    });
    BrowserHost.setWorkspace(this.workspaceRoot);
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    BrowserHost.setAttachments(context.filesDir + '/attachments');
    BrowserHost.setViewportHandler((width: number, height: number) => {
      this.viewWidth = width;
      this.viewHeight = height;
    });
  }

  aboutToDisappear(): void {
    BrowserHost.clearTabHandlers();
    BrowserHost.setViewportHandler(null);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.tabIds, (id: number) => {
        HiddenTab({ tabId: id, active: id === this.activeId })
      }, (id: number) => id.toString())
    }
    .width(this.viewWidth > 0 ? this.viewWidth : '100%')
    .height(this.viewHeight > 0 ? this.viewHeight : '100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
