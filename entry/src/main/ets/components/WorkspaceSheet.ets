import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { FileEntry, formatFileSize, parentRelative } from '../core/FileListing';
import {
  WorkspaceListing,
  WorkspacePreview,
  listWorkspace,
  previewWorkspaceFile
} from '../service/WorkspaceFiles';
import { ExportOutcome, saveFileCopy } from '../service/ExportService';
import { t } from '../core/I18n';

/**
 * Read-only browser for the app-private workspace. It uses the same path
 * rules as the tools, so it cannot show anything the model could not read.
 */
@Component
export struct WorkspaceSheet {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop workspaceRoot: string = '';
  /** A `minis://workspace/...` link opens straight into this file. */
  @Prop initialPath: string = '';
  onClose: () => void = () => {
  };
  onToast: (message: string) => void = (message: string) => {
  };

  @State path: string = '';
  @State entries: FileEntry[] = [];
  @State error: string = '';
  @State previewName: string = '';
  @State previewText: string = '';
  @State previewError: string = '';
  @State previewTruncated: boolean = false;
  @State previewHtml: boolean = false;
  @State previewPath: string = '';
  private htmlController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    if (this.initialPath.length > 0) {
      this.reveal(this.initialPath);
      return;
    }
    this.reload();
  }

  private isHtml(name: string): boolean {
    const lower: string = name.toLowerCase();
    return lower.endsWith('.html') || lower.endsWith('.htm');
  }

  /** `file://` URL that keeps relative CSS/JS/image references working. */
  private htmlSource(relative: string): string {
    const encoded: string = relative.split('/').map(
      (part: string) => encodeURIComponent(part)).join('/');
    return 'file://' + this.workspaceRoot + '/' + encoded;
  }

  /**
   * Show the containing directory and open the linked file beside it. HTML
   * artifacts render in a Web view (matching OpenMinis's file preview); every
   * other type keeps the read-only text preview.
   */
  private reveal(relative: string): void {
    this.path = parentRelative(relative);
    this.reload();
    const cut: number = relative.lastIndexOf('/');
    const name: string = cut < 0 ? relative : relative.substring(cut + 1);
    if (this.isHtml(name)) {
      this.htmlController = new webview.WebviewController();
      this.previewName = name;
      this.previewPath = relative;
      this.previewError = '';
      this.previewText = '';
      this.previewTruncated = false;
      this.previewHtml = true;
      return;
    }
    const preview: WorkspacePreview =
      previewWorkspaceFile(this.workspaceRoot, relative);
    this.previewName = name;
    this.previewPath = relative;
    this.previewHtml = false;
    this.previewError = preview.ok ? '' : preview.error;
    this.previewText = preview.text;
    this.previewTruncated = preview.truncated;
  }

  private reload(): void {
    const listing: WorkspaceListing = listWorkspace(this.workspaceRoot, this.path);
    this.entries = listing.entries;
    this.error = listing.ok ? '' : listing.error;
    this.closePreview();
  }

  private closePreview(): void {
    this.previewName = '';
    this.previewText = '';
    this.previewError = '';
    this.previewTruncated = false;
    this.previewHtml = false;
    this.previewPath = '';
  }

  private enterDir(entry: FileEntry): void {
    this.path = entry.path;
    this.reload();
  }

  private openFile(entry: FileEntry): void {
    if (this.isHtml(entry.name)) {
      this.htmlController = new webview.WebviewController();
      this.previewName = entry.name;
      this.previewPath = entry.path;
      this.previewError = '';
      this.previewText = '';
      this.previewTruncated = false;
      this.previewHtml = true;
      return;
    }
    const preview: WorkspacePreview =
      previewWorkspaceFile(this.workspaceRoot, entry.path);
    this.previewName = entry.name;
    this.previewPath = entry.path;
    this.previewError = preview.ok ? '' : preview.error;
    this.previewText = preview.text;
    this.previewTruncated = preview.truncated;
    this.previewHtml = false;
  }

  /** Hand the current file to the system picker, including binaries. */
  private async exportPreview(): Promise<void> {
    if (this.previewPath.length === 0) {
      return;
    }
    const outcome: ExportOutcome = await saveFileCopy(
      getContext(this) as common.UIAbilityContext,
      this.workspaceRoot + '/' + this.previewPath,
      this.previewName,
      t('已导出文件')
    );
    this.onToast(outcome.message);
  }

  private goUp(): void {
    if (this.path.length === 0) {
      return;
    }
    this.path = parentRelative(this.path);
    this.reload();
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text(t('工作区文件'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.path.length > 0 ? '/' + this.path : '/')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('✕')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .padding(6)
        .onClick(() => this.onClose())
    }
    .width('100%')
  }

  @Builder
  fileList() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.path.length > 0 ? t('↑ 上级目录') : t('根目录'))
          .fontSize(11)
          .fontColor(this.path.length > 0
            ? $r('app.color.accent')
            : $r('app.color.text_tertiary'))
          .onClick(() => this.goUp())
        Blank()
        Text(t('刷新'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => this.reload())
      }
      .width('100%')

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
      } else if (this.entries.length === 0) {
        Text(t('空目录'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.entries, (entry: FileEntry) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(entry.isDir ? '▸' : t('·'))
                  .fontSize(12)
                  .fontColor(entry.isDir
                    ? $r('app.color.accent')
                    : $r('app.color.text_tertiary'))
                Text(entry.name)
                  .fontSize(12)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (!entry.isDir) {
                  Text(formatFileSize(entry.size))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                }
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 7, bottom: 7 })
              .borderRadius(7)
              .backgroundColor($r('app.color.surface_alt'))
              .onClick(() => {
                if (entry.isDir) {
                  this.enterDir(entry);
                } else {
                  this.openFile(entry);
                }
              })
            }
          }, (entry: FileEntry) => entry.path + ':' + entry.size.toString() +
            ':' + (entry.isDir ? 'd' : 'f'))
        }
        .width('100%')
        .constraintSize({ maxHeight: 380 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
  }

  @Builder
  preview() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(t('‹ 返回列表'))
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .onClick(() => this.closePreview())
        Blank()
        Text(this.previewName)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '50%' })
        Text(t('导出'))
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .accessibilityText(t('导出文件'))
          .onClick(() => this.exportPreview())
      }
      .width('100%')

      if (this.previewError.length > 0) {
        Text(this.previewError)
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
      } else if (this.previewHtml) {
        // Render HTML artifacts instead of showing their source, like
        // OpenMinis's file preview. Relative CSS/JS/images resolve against
        // the file URL, so pages generated by the browser tool look right.
        Web({ src: this.htmlSource(this.previewPath), controller: this.htmlController })
          .width('100%')
          .height(400)
          .fileAccess(true)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onlineImageAccess(true)
          .mixedMode(MixedMode.All)
          .backgroundColor($r('app.color.code_bg'))
          .borderRadius(9)
      } else {
        Scroll() {
          Text(this.previewText)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 400 })
        .padding(10)
        .backgroundColor($r('app.color.code_bg'))
        .borderRadius(9)
        .scrollBar(BarState.Auto)
        if (this.previewTruncated) {
          Text(t('仅显示前 256 KB'))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => this.onClose())
      Column({ space: 12 }) {
        this.header()
        if (this.previewName.length > 0) {
          this.preview()
        } else {
          this.fileList()
        }
      }
      .width('88%')
      .constraintSize({ maxWidth: 480 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
