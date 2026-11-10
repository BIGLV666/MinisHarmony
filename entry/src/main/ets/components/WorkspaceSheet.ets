import { FileEntry, formatFileSize, parentRelative } from '../core/FileListing';
import {
  WorkspaceListing,
  WorkspacePreview,
  listWorkspace,
  previewWorkspaceFile
} from '../service/WorkspaceFiles';
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

  @State path: string = '';
  @State entries: FileEntry[] = [];
  @State error: string = '';
  @State previewName: string = '';
  @State previewText: string = '';
  @State previewError: string = '';
  @State previewTruncated: boolean = false;

  aboutToAppear(): void {
    if (this.initialPath.length > 0) {
      this.reveal(this.initialPath);
      return;
    }
    this.reload();
  }

  /** Show the containing directory and open the linked file beside it. */
  private reveal(relative: string): void {
    this.path = parentRelative(relative);
    this.reload();
    const preview: WorkspacePreview =
      previewWorkspaceFile(this.workspaceRoot, relative);
    const cut: number = relative.lastIndexOf('/');
    this.previewName = cut < 0 ? relative : relative.substring(cut + 1);
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
  }

  private enterDir(entry: FileEntry): void {
    this.path = entry.path;
    this.reload();
  }

  private openFile(entry: FileEntry): void {
    const preview: WorkspacePreview =
      previewWorkspaceFile(this.workspaceRoot, entry.path);
    this.previewName = entry.name;
    this.previewError = preview.ok ? '' : preview.error;
    this.previewText = preview.text;
    this.previewTruncated = preview.truncated;
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
      }
      .width('100%')

      if (this.previewError.length > 0) {
        Text(this.previewError)
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
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
