import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { normalizeWebUrl, webHost } from '../core/WebUrl';
import {
  BrowserDownloadEntry,
  BrowserHistoryEntry,
  cookieOrigins,
  filterHistory,
  formatBytes,
  webOrigin
} from '../core/BrowserHistory';
import { VIEWPORT_MAX, VIEWPORT_MIN, customViewport, parseViewportSize } from '../core/BrowserViewport';
import { BrowserStore, userAgentFor } from '../service/BrowserStore';
import { formatRelative } from '../service/Format';
import { t } from '../core/I18n';

interface ActiveDownload {
  guid: string;
  name: string;
  percent: number;
}

interface CookieOriginRow {
  origin: string;
  host: string;
  count: number;
}

/**
 * In-app browser for links in chat. Mirrors OpenMinis's browser sheet: page
 * chrome (back/forward/reload/address/open-external/close) plus local history,
 * a download list and settings for the user agent, wide viewport and cookies.
 * Tabs stay in the hidden automation browser; this sheet is one page at a
 * time.
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
  /** 0 page, 1 history, 2 downloads, 3 settings. */
  @State panel: number = 0;
  @State history: BrowserHistoryEntry[] = [];
  @State downloads: BrowserDownloadEntry[] = [];
  @State historyQuery: string = '';
  @State uaPreset: string = 'default';
  @State uaCustom: string = '';
  @State wideViewport: boolean = false;
  /** Fixed page surface in vp; 0 means fill the panel. */
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  @State viewportWidthText: string = '';
  @State viewportHeightText: string = '';
  @State cookieCount: number = 0;
  @State cookieRows: CookieOriginRow[] = [];
  @State activeDownloads: ActiveDownload[] = [];
  private controller: webview.WebviewController = new webview.WebviewController();
  private downloadDelegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private context: common.UIAbilityContext | null = null;
  private downloadDir: string = '';
  /** Guid → destination path chosen in `onBeforeDownload`. */
  private downloadPaths: Map<string, string> = new Map();

  aboutToAppear(): void {
    this.url = this.initialUrl;
    this.address = this.initialUrl;
    this.hostHint = webHost(this.initialUrl);
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.context = context;
    this.history = BrowserStore.history(context);
    this.downloads = BrowserStore.downloads(context);
    this.uaPreset = BrowserStore.uaPreset(context);
    this.uaCustom = BrowserStore.customUserAgent(context);
    this.wideViewport = BrowserStore.wideViewport(context);
    this.viewportWidth = BrowserStore.viewportWidth(context);
    this.viewportHeight = BrowserStore.viewportHeight(context);
    this.viewportWidthText = this.viewportWidth > 0 ? this.viewportWidth.toString() : '';
    this.viewportHeightText = this.viewportHeight > 0 ? this.viewportHeight.toString() : '';
    this.downloadDir = context.filesDir + '/browser-downloads';
    try {
      if (!fileIo.accessSync(this.downloadDir)) {
        fileIo.mkdirSync(this.downloadDir);
      }
    } catch (e) {
    }
  }

  private navigate(): void {
    const target: string = normalizeWebUrl(this.address);
    if (target.length === 0) {
      return;
    }
    this.address = target;
    this.panel = 0;
    this.controller.loadUrl(target);
  }

  private openHistory(url: string): void {
    this.panel = 0;
    this.url = url;
    this.address = url;
    this.hostHint = webHost(url);
    this.controller.loadUrl(url);
  }

  private openDownload(item: BrowserDownloadEntry): void {
    if (!item.ok) {
      this.getUIContext().getPromptAction().showToast({ message: t('打开') + ': ' + item.name });
      return;
    }
    this.panel = 0;
    this.controller.loadUrl('file://' + item.path);
  }

  private openPanel(index: number): void {
    if (this.context === null) {
      return;
    }
    this.panel = index;
    if (index === 1) {
      this.history = BrowserStore.history(this.context);
    } else if (index === 2) {
      this.downloads = BrowserStore.downloads(this.context);
    } else if (index === 3) {
      this.refreshCookieCount();
      this.refreshCookieRows();
    }
  }

  private cookieCountFor(url: string): number {
    if (url.length === 0) {
      return 0;
    }
    try {
      const raw: string = webview.WebCookieManager.fetchCookieSync(url);
      let count: number = 0;
      const parts: string[] = raw.split(';');
      for (let i = 0; i < parts.length; i++) {
        if (parts[i].trim().length > 0) {
          count++;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  private refreshCookieCount(): void {
    this.cookieCount = this.cookieCountFor(this.url);
  }

  private refreshCookieRows(): void {
    const origins: string[] = cookieOrigins(this.history, this.url, 20);
    const rows: CookieOriginRow[] = [];
    for (let i = 0; i < origins.length; i++) {
      const origin: string = origins[i];
      rows.push({
        origin: origin,
        host: webHost(origin),
        count: this.cookieCountFor(origin + '/')
      });
    }
    this.cookieRows = rows;
  }

  private clearOriginCookies(origin: string): void {
    try {
      webview.WebCookieManager.configCookieSync(origin + '/', '');
    } catch (e) {
    }
    this.refreshCookieCount();
    this.refreshCookieRows();
    this.getUIContext().getPromptAction().showToast({ message: t('清除') });
  }

  private applyUserAgent(): void {
    let ua: string = userAgentFor(this.uaPreset, this.uaCustom);
    if (this.uaPreset === 'default') {
      try {
        ua = webview.WebviewController.getDefaultUserAgent();
      } catch (e) {
        ua = '';
      }
    }
    if (ua.length === 0) {
      return;
    }
    try {
      this.controller.setCustomUserAgent(ua);
    } catch (e) {
    }
  }

  private saveBrowserSettings(): void {
    if (this.context === null) {
      return;
    }
    const width: number = parseViewportSize(this.viewportWidthText);
    const height: number = parseViewportSize(this.viewportHeightText);
    const wantsCustom: boolean = this.viewportWidthText.trim().length > 0 ||
      this.viewportHeightText.trim().length > 0;
    if (wantsCustom && !customViewport(width, height)) {
      this.getUIContext().getPromptAction().showToast({
        message: t('视口宽高需同时填写数字，范围 200–2000。')
      });
      return;
    }
    this.viewportWidth = width;
    this.viewportHeight = height;
    BrowserStore.saveViewport(this.context, width, height);
    BrowserStore.saveUserAgent(this.context, this.uaPreset, this.uaCustom);
    BrowserStore.saveWideViewport(this.context, this.wideViewport);
    this.applyUserAgent();
    this.controller.refresh();
  }

  private clearCurrentCookies(): void {
    try {
      webview.WebCookieManager.configCookieSync(this.url, '');
    } catch (e) {
    }
    this.refreshCookieCount();
    this.refreshCookieRows();
    this.getUIContext().getPromptAction().showToast({ message: t('清除') });
  }

  private clearAllCookies(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (e) {
    }
    this.refreshCookieCount();
    this.refreshCookieRows();
    this.getUIContext().getPromptAction().showToast({ message: t('清除') });
  }

  private safeFileName(suggested: string, url: string): string {
    let name: string = suggested.trim();
    if (name.length === 0) {
      const slash: number = url.lastIndexOf('/');
      name = slash >= 0 ? url.substring(slash + 1) : 'download';
    }
    name = name.replace(/[\\/:*?"<>|]/g, '_').replace(/^\.+/, '').trim();
    if (name.length === 0) {
      name = 'download';
    }
    let path: string = this.downloadDir + '/' + name;
    if (fileIo.accessSync(path)) {
      const dot: number = name.lastIndexOf('.');
      const suffix: string = dot > 0 ? name.substring(dot) : '';
      const base: string = dot > 0 ? name.substring(0, dot) : name;
      path = this.downloadDir + '/' + base + '-' + Date.now().toString() + suffix;
    }
    return path;
  }

  private configureDownloads(): void {
    this.downloadDelegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      try {
        const path: string = this.safeFileName(item.getSuggestedFileName(), item.getUrl());
        this.downloadPaths.set(item.getGuid(), path);
        const next: ActiveDownload[] = this.activeDownloads.slice();
        next.push({
          guid: item.getGuid(),
          name: item.getSuggestedFileName(),
          percent: 0
        });
        this.activeDownloads = next;
        item.start(path);
      } catch (e) {
      }
    });
    this.downloadDelegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      this.updateActiveDownload(item);
    });
    this.downloadDelegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.finishDownload(item, true);
    });
    this.downloadDelegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.finishDownload(item, false);
    });
    try {
      this.controller.setDownloadDelegate(this.downloadDelegate);
    } catch (e) {
    }
  }

  private updateActiveDownload(item: webview.WebDownloadItem): void {
    let percent: number = -1;
    try {
      percent = item.getPercentComplete();
    } catch (e) {
      percent = -1;
    }
    const guid: string = item.getGuid();
    const next: ActiveDownload[] = [];
    for (let i = 0; i < this.activeDownloads.length; i++) {
      const row: ActiveDownload = this.activeDownloads[i];
      if (row.guid === guid) {
        if (row.percent === percent) {
          next.push(row);
        } else {
          next.push({ guid: row.guid, name: row.name, percent: percent });
        }
      } else {
        next.push(row);
      }
    }
    this.activeDownloads = next;
  }

  private removeActiveDownload(guid: string): void {
    const next: ActiveDownload[] = [];
    for (let i = 0; i < this.activeDownloads.length; i++) {
      if (this.activeDownloads[i].guid !== guid) {
        next.push(this.activeDownloads[i]);
      }
    }
    this.activeDownloads = next;
  }

  private downloadBadgeLabel(): string {
    const count: number = this.activeDownloads.length;
    return count === 0 ? '⬇' : (count > 9 ? '⬇9+' : '⬇' + count.toString());
  }

  private finishDownload(item: webview.WebDownloadItem, ok: boolean): void {
    this.removeActiveDownload(item.getGuid());
    if (this.context === null) {
      return;
    }
    let path: string = '';
    const known: string | undefined = this.downloadPaths.get(item.getGuid());
    if (known !== undefined) {
      path = known;
    } else {
      try {
        path = item.getFullPath();
      } catch (e) {
        path = '';
      }
    }
    if (path.length === 0) {
      return;
    }
    let name: string = item.getSuggestedFileName();
    if (name.length === 0) {
      const slash: number = path.lastIndexOf('/');
      name = slash >= 0 ? path.substring(slash + 1) : path;
    }
    const entry: BrowserDownloadEntry = {
      name: name,
      path: path,
      at: Date.now(),
      bytes: item.getReceivedBytes(),
      ok: ok
    };
    this.downloads = BrowserStore.recordDownload(this.context, entry);
    this.downloadPaths.delete(item.getGuid());
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
      .fontSize(16)
      .fontColor(enabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
      .width(30)
      .height(34)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .onClick(() => {
        if (enabled) {
          action();
        }
      })
  }

  @Builder
  panelHeader(title: string) {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize(22)
        .fontColor($r('app.color.text_primary'))
        .width(32)
        .height(36)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.panel = 0;
        })
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(t('清空'))
        .fontSize(12)
        .fontColor($r('app.color.danger'))
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => this.clearPanel())
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface'))
  }

  private clearPanel(): void {
    if (this.context === null) {
      return;
    }
    if (this.panel === 1) {
      BrowserStore.clearHistory(this.context);
      this.history = [];
    } else if (this.panel === 2) {
      BrowserStore.clearDownloads(this.context);
      this.downloads = [];
    }
  }

  @Builder
  historyPanel() {
    Column() {
      this.panelHeader(t('历史'))
      TextInput({ text: this.historyQuery, placeholder: t('搜索对话') })
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .margin({ left: 12, right: 12, bottom: 6 })
        .onChange((value: string) => {
          this.historyQuery = value;
        })
      Scroll() {
        Column({ space: 4 }) {
          if (filterHistory(this.history, this.historyQuery).length === 0) {
            Text(t('暂无记录'))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .padding(20)
          } else {
            ForEach(filterHistory(this.history, this.historyQuery),
              (item: BrowserHistoryEntry) => {
                Column({ space: 2 }) {
                  Text(item.title)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row({ space: 6 }) {
                    Text(webHost(item.url))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(formatRelative(item.at))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .width('100%')
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                .borderRadius(10)
                .backgroundColor($r('app.color.surface_alt'))
                .onClick(() => this.openHistory(item.url))
              }, (item: BrowserHistoryEntry) => item.url + ':' + item.at.toString())
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }

  @Builder
  downloadsPanel() {
    Column() {
      this.panelHeader(t('下载'))
      Scroll() {
        Column({ space: 4 }) {
          if (this.activeDownloads.length > 0) {
            Text(t('正在下载'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 12, right: 12, top: 6 })
            ForEach(this.activeDownloads, (item: ActiveDownload) => {
              Column({ space: 5 }) {
                Row({ space: 8 }) {
                  Text(item.name)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.percent >= 0 ? item.percent.toString() + '%' : '…')
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                Progress({
                  value: item.percent >= 0 ? item.percent : 0,
                  total: 100,
                  type: ProgressType.Linear
                })
                  .width('100%')
                  .height(4)
                  .color($r('app.color.accent'))
                  .backgroundColor($r('app.color.border'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .borderRadius(10)
              .backgroundColor($r('app.color.surface_alt'))
            }, (item: ActiveDownload) => item.guid)
          }
          if (this.downloads.length === 0) {
            Text(t('暂无记录'))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .padding(20)
          } else {
            ForEach(this.downloads, (item: BrowserDownloadEntry) => {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(item.name)
                    .fontSize(13)
                    .fontColor(item.ok ? $r('app.color.text_primary')
                      : $r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(formatBytes(item.bytes) + (item.ok ? '' : ' · ' + t('取消')))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text(formatRelative(item.at))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .borderRadius(10)
              .backgroundColor($r('app.color.surface_alt'))
              .onClick(() => this.openDownload(item))
            }, (item: BrowserDownloadEntry) => item.path + ':' + item.at.toString())
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }

  @Builder
  uaOption(label: string, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.uaPreset === value ? $r('app.color.on_accent')
        : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(9)
      .backgroundColor(this.uaPreset === value ? $r('app.color.accent')
        : $r('app.color.surface_alt'))
      .onClick(() => {
        this.uaPreset = value;
      })
  }

  @Builder
  settingsPanel() {
    Column({ space: 10 }) {
      this.panelHeader(t('浏览器设置'))
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 6 }) {
            Text(t('用户代理'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Row({ space: 6 }) {
              this.uaOption(t('默认'), 'default')
              this.uaOption(t('移动'), 'mobile')
              this.uaOption(t('桌面'), 'desktop')
              this.uaOption(t('自定义'), 'custom')
            }
            .width('100%')
            if (this.uaPreset === 'custom') {
              TextInput({ text: this.uaCustom, placeholder: 'Mozilla/5.0 …' })
                .width('100%')
                .height(38)
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.uaCustom = value;
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(t('视口'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Text(t('桌面'))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.wideViewport })
              .selectedColor($r('app.color.accent'))
              .onChange((value: boolean) => {
                this.wideViewport = value;
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(t('宽'))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
              TextInput({ text: this.viewportWidthText, placeholder: t('自动') })
                .type(InputType.Number)
                .fontSize(12)
                .height(36)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(8)
                .placeholderColor($r('app.color.text_tertiary'))
                .onChange((value: string) => {
                  this.viewportWidthText = value;
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Column({ space: 2 }) {
              Text(t('高'))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
              TextInput({ text: this.viewportHeightText, placeholder: t('自动') })
                .type(InputType.Number)
                .fontSize(12)
                .height(36)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(8)
                .placeholderColor($r('app.color.text_tertiary'))
                .onChange((value: string) => {
                  this.viewportHeightText = value;
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Text(t('页面宽高（vp），留空跟随面板；') + VIEWPORT_MIN.toString() + '–' +
            VIEWPORT_MAX.toString())
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')

          Column({ space: 6 }) {
            Text('Cookie')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(t('当前网站') + ': ' + webHost(this.url) + ' · ' + this.cookieCount.toString())
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
            if (this.cookieRows.length === 0) {
              Text(t('还没有可列出的网站 Cookie。'))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            } else {
              ForEach(this.cookieRows, (row: CookieOriginRow) => {
                Row({ space: 8 }) {
                  Text(row.host)
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.count.toString())
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                  Text(t('清除'))
                    .fontSize(11)
                    .fontColor($r('app.color.danger'))
                    .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                    .onClick(() => this.clearOriginCookies(row.origin))
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              }, (row: CookieOriginRow) => row.origin)
            }
            Row({ space: 10 }) {
              Text(t('清除') + ' (' + t('全部') + ')')
                .fontSize(12)
                .fontColor($r('app.color.danger'))
                .onClick(() => this.clearAllCookies())
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Button(t('保存'), { type: ButtonType.Normal })
            .width('100%')
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(10)
            .onClick(() => this.saveBrowserSettings())
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 6, bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }

  @Builder
  pageSurface() {
    Web({ src: this.url, controller: this.controller })
      .width(this.viewportWidth > 0 ? this.viewportWidth : '100%')
      .height(this.viewportHeight > 0 ? this.viewportHeight : '100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .wideViewModeAccess(this.wideViewport)
      .overviewModeAccess(this.wideViewport)
      // Default autosizing inflates text ~4x once the layout viewport is much
      // narrower than the window, which defeats a numeric phone-width viewport.
      .textAutosizing(false)
      .onControllerAttached(() => {
        // Delegates and UA need an attached controller.
        this.applyUserAgent();
        this.configureDownloads();
      })
      .onPageBegin((event) => {
        this.url = event.url;
        this.address = event.url;
        this.hostHint = webHost(event.url);
        this.title = '';
        this.loading = true;
      })
      .onPageEnd((event) => {
        this.canBack = this.controller.accessBackward();
        this.canForward = this.controller.accessForward();
        this.hostHint = webHost(this.url);
        this.loading = false;
        if (this.context !== null) {
          this.history = BrowserStore.recordHistory(this.context, {
            url: this.url,
            title: this.title.length > 0 ? this.title : webHost(this.url),
            at: Date.now()
          });
        }
      })
      .onTitleReceive((event) => {
        this.title = event.title;
      })
      .onProgressChange((event) => {
        this.progress = event.newProgress;
      })
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 2 }) {
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
          this.toolbarButton('🕘', true, () => this.openPanel(1))
          this.toolbarButton(this.downloadBadgeLabel(), true, () => this.openPanel(2))
          this.toolbarButton('⚙', true, () => this.openPanel(3))
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
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
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

        if (this.viewportWidth > 0 && this.viewportHeight > 0) {
          Scroll() {
            Column() {
              this.pageSurface()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 4, bottom: 4 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        } else {
          Column() {
            this.pageSurface()
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      if (this.panel === 1) {
        this.historyPanel()
      } else if (this.panel === 2) {
        this.downloadsPanel()
      } else if (this.panel === 3) {
        this.settingsPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
