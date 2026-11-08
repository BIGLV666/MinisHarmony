import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { normalizeWebUrl, webHost } from '../core/WebUrl';
import { t } from '../core/I18n';

/**
 * In-app browser for links in chat, mirroring OpenMinis's single-sheet web
 * preview: page title plus host, close, reload/stop, back/forward, address bar
 * and "open in system browser". Like the reference it is one page at a time;
 * tabs, a history list and download management are not part of that design.
 */
@Component
export struct BrowserPage {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop initialUrl: string = '';
  onClose: () => void = () => {
  };
  @State url: string = '';
  @State address: string = '';
  @State title: string = '';
  @State hostHint: string = '';
  @State progress: number = 0;
  @State loading: boolean = false;
  @State canBack: boolean = false;
  @State canForward: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.url = this.initialUrl;
    this.address = this.initialUrl;
    this.hostHint = webHost(this.initialUrl);
  }

  private navigate(): void {
    const target: string = normalizeWebUrl(this.address);
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
      this.getUIContext().getPromptAction().showToast({ message: t('没有可打开该链接的应用') });
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
        this.toolbarButton(this.loading ? '⏹' : '⟳', true, () => {
          if (this.loading) {
            this.controller.stop();
            this.loading = false;
          } else {
            this.controller.refresh();
          }
        })
        TextInput({ text: this.address, placeholder: t('输入网址') })
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

      if (this.title.length > 0 || this.hostHint.length > 0) {
        Column({ space: 1 }) {
          if (this.title.length > 0) {
            Text(this.title)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.hostHint.length > 0) {
            Text(this.hostHint)
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
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
          this.hostHint = webHost(event.url);
          this.loading = true;
        })
        .onPageEnd((event) => {
          this.canBack = this.controller.accessBackward();
          this.canForward = this.controller.accessForward();
          this.hostHint = webHost(this.url);
          this.loading = false;
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
