import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';

/**
 * Minimal in-app browser for links in chat. One page per session: back,
 * forward, reload, address bar and "open in system browser". Multi-tab,
 * history and download management are not implemented.
 */
@Component
export struct BrowserPage {
  @Prop initialUrl: string = '';
  onClose: () => void = () => {
  };
  @State url: string = '';
  @State address: string = '';
  @State title: string = '';
  @State progress: number = 0;
  @State canBack: boolean = false;
  @State canForward: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  private normalize(input: string): string {
    let value: string = input.trim();
    if (value.length === 0) {
      return '';
    }
    const lower: string = value.toLowerCase();
    if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) {
      value = 'https://' + value;
    }
    return value;
  }

  aboutToAppear(): void {
    this.url = this.initialUrl;
    this.address = this.initialUrl;
  }

  private navigate(): void {
    const target: string = this.normalize(this.address);
    if (target.length === 0) {
      return;
    }
    this.address = target;
    this.controller.loadUrl(target);
  }

  private openExternal(): void {
    const target: string = this.url.length > 0 ? this.url : this.address;
    if (target.length === 0) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: target
    };
    context.startAbility(want).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: '没有可打开该链接的应用' });
    });
  }

  @Builder
  toolbarButton(label: string, enabled: boolean, action: () => void) {
    Text(label)
      .fontSize(18)
      .fontColor(enabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
      .width(34)
      .height(34)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .onClick(() => {
        if (enabled) {
          action();
        }
      })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        this.toolbarButton('‹', this.canBack, () => {
          this.controller.backward();
        })
        this.toolbarButton('›', this.canForward, () => {
          this.controller.forward();
        })
        this.toolbarButton('⟳', true, () => {
          this.controller.refresh();
        })
        TextInput({ text: this.address, placeholder: '输入网址' })
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .enterKeyType(EnterKeyType.Go)
          .onChange((value: string) => {
            this.address = value;
          })
          .onSubmit(() => this.navigate())
        this.toolbarButton('↗', true, () => this.openExternal())
        this.toolbarButton('✕', true, () => this.onClose())
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface'))

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.accent'))
          .backgroundColor($r('app.color.border'))
      }

      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.surface'))
      }

      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .onPageBegin((event) => {
          this.url = event.url;
          this.address = event.url;
        })
        .onPageEnd((event) => {
          this.canBack = this.controller.accessBackward();
          this.canForward = this.controller.accessForward();
        })
        .onTitleReceive((event) => {
          this.title = event.title;
        })
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
