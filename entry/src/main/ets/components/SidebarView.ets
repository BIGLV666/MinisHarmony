import {
  SessionFolder,
  SessionGroup,
  SessionMeta,
  SessionSearchEntry,
  groupSessionMetas,
  modelName
} from '../core/Types';
import { FolderGroup, groupByFolder } from '../core/SessionFolder';
import { formatRelative } from '../service/Format';
import { t } from '../core/I18n';

@Component
export struct SidebarView {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @StorageProp('accentColor') accent: string = '#2F6BFF';
  @Prop sessions: SessionMeta[] = [];
  @Prop searchEntries: SessionSearchEntry[] = [];
  @Prop folders: SessionFolder[] = [];
  @Prop currentId: string = '';
  @Prop showArchived: boolean = false;
  @Link query: string;
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];
  onToggleArchived: () => void = () => {
  };
  onNew: () => void = () => {
  };
  onImport: () => void = () => {
  };
  onBackup: () => void = () => {
  };
  onEncryptedBackup: () => void = () => {
  };
  onSelect: (id: string) => void = (id: string) => {
  };
  onMore: (id: string) => void = (id: string) => {
  };
  onSettings: () => void = () => {
  };
  onExportSelected: (ids: string[]) => void = (ids: string[]) => {
  };
  onToggleFolder: (id: string) => void = (id: string) => {
  };
  onNewInFolder: (id: string) => void = (id: string) => {
  };
  onManageFolders: () => void = () => {
  };

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private hasBadge(item: SessionMeta): boolean {
    return item.statusBadge !== undefined && item.statusBadge.length > 0;
  }

  private badgeLabel(value: string): string {
    if (value === 'background') {
      return t('后台');
    }
    if (value === 'interrupted') {
      return t('已中断');
    }
    if (value === 'syncing') {
      return t('同步中');
    }
    return '';
  }

  private toggleSelected(id: string): void {
    const next: string[] = [];
    let removed: boolean = false;
    for (let i = 0; i < this.selectedIds.length; i++) {
      if (this.selectedIds[i] === id) {
        removed = true;
      } else {
        next.push(this.selectedIds[i]);
      }
    }
    if (!removed) {
      next.push(id);
    }
    this.selectedIds = next;
  }

  private setSelecting(on: boolean): void {
    this.selecting = on;
    this.selectedIds = [];
  }

  private exportSelected(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    this.onExportSelected(this.selectedIds.slice());
    this.setSelecting(false);
  }

  private blobFor(id: string): string {
    for (let i = 0; i < this.searchEntries.length; i++) {
      if (this.searchEntries[i].id === id) {
        return this.searchEntries[i].text;
      }
    }
    return '';
  }

  private archivedCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].archived) {
        count++;
      }
    }
    return count;
  }

  /**
   * Archived sessions stay out of the default list but remain searchable:
   * search is how users retrieve an archived conversation they forgot about.
   */
  private grouped(): SessionGroup[] {
    return groupSessionMetas(this.filtered(), Date.now());
  }

  /** Folders only replace the date buckets in the unfiltered list. */
  private usingFolders(): boolean {
    return this.folders.length > 0 && this.query.trim().length === 0;
  }

  private folderGroups(): FolderGroup[] {
    return groupByFolder(this.filtered(), this.folders);
  }

  private filtered(): SessionMeta[] {
    const keyword: string = this.query.trim().toLowerCase();
    const result: SessionMeta[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const item: SessionMeta = this.sessions[i];
      if (keyword.length === 0) {
        if (!item.archived || this.showArchived) {
          result.push(item);
        }
      } else if (item.title.toLowerCase().indexOf(keyword) >= 0 ||
        item.modelId.toLowerCase().indexOf(keyword) >= 0 ||
        this.blobFor(item.id).indexOf(keyword) >= 0) {
        result.push(item);
      }
    }
    return result;
  }

  @Builder
  brand() {
    Row({ space: 10 }) {
      Text('M')
        .width(34)
        .height(34)
        .borderRadius(11)
        .textAlign(TextAlign.Center)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accent)
      Text('Minis')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(t('设置'))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => this.onSettings())
    }
    .width('100%')
  }

  @Builder
  groupHeader(label: string) {
    Text(label)
      .fontSize(10)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 12, top: 8, bottom: 4 })
  }

  @Builder
  folderHeader(group: FolderGroup) {
    Row({ space: 5 }) {
      if (group.id.length > 0) {
        Text(group.collapsed ? '▸' : '▾')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      Text(group.id.length > 0 ? group.label : t('未分组'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(group.id.length > 0 ? $r('app.color.text_secondary')
          : $r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(group.sessions.length.toString())
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
      if (group.id.length > 0) {
        Text('＋')
          .fontSize(13)
          .fontColor(this.accent)
          .padding({ left: 6, right: 2 })
          .onClick(() => this.onNewInFolder(group.id))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 4 })
    .onClick(() => {
      if (group.id.length > 0) {
        this.onToggleFolder(group.id);
      }
    })
  }

  @Builder
  sessionRow(item: SessionMeta) {
    Column({ space: 4 }) {
      Row({ space: 5 }) {
        if (this.selecting) {
          Text(this.isSelected(item.id) ? '☑' : '☐')
            .fontSize(15)
            .fontColor(this.accent)
        }
        if (item.pinned) {
          Text(t('置顶'))
            .fontSize(9)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(4)
        }
        Text(item.title)
          .layoutWeight(1)
          .fontSize(14)
          .fontWeight(this.currentId === item.id ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentId === item.id ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.hasBadge(item)) {
          Text(this.badgeLabel(item.statusBadge !== undefined ? item.statusBadge : ''))
            .fontSize(9)
            .fontColor(item.statusBadge === 'interrupted'
              ? $r('app.color.danger')
              : (item.statusBadge === 'syncing'
                ? $r('app.color.accent')
                : $r('app.color.text_secondary')))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(4)
        }
        if (item.archived) {
          Text(t('归档'))
            .fontSize(9)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(4)
        }
      }
      .width('100%')
      Row({ space: 5 }) {
        Text(modelName(item.modelId))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(formatRelative(item.updatedAt))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.selecting && this.isSelected(item.id)
      ? $r('app.color.accent_soft')
      : (this.currentId === item.id ? $r('app.color.accent_soft') : Color.Transparent))
    .onClick(() => {
      if (this.selecting) {
        this.toggleSelected(item.id);
      } else {
        this.onSelect(item.id);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 520 })
        .onAction(() => {
          if (!this.selecting) {
            this.onMore(item.id);
          }
        })
    )
  }

  build() {
    Column({ space: 14 }) {
      this.brand()

      Row({ space: 8 }) {
        Text('＋')
          .fontSize(18)
          .fontColor($r('app.color.on_accent'))
        Text(t('新建对话'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.accent)
      .borderRadius(12)
      .onClick(() => this.onNew())

      TextInput({ text: this.query, placeholder: t('搜索对话') })
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.query = value;
        })

      if (this.archivedCount() > 0) {
        Row({ space: 4 }) {
          Text(this.showArchived ? t('隐藏已归档') : t('显示已归档'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          if (!this.showArchived) {
            Text('(' + this.archivedCount().toString() + ')')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
        .onClick(() => this.onToggleArchived())
      }

      Row({ space: 8 }) {
        Text(this.selecting ? t('取消选择') : t('选择会话'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => this.setSelecting(!this.selecting))
        Text(t('管理分组'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => this.onManageFolders())
        Blank()
        if (this.selecting) {
          Text(t('导出所选 (') + this.selectedIds.length.toString() + ')')
            .fontSize(11)
            .fontColor(this.selectedIds.length > 0 ? this.accent : $r('app.color.text_tertiary'))
            .onClick(() => this.exportSelected())
        }
      }
      .width('100%')
      .padding({ left: 4, right: 4 })

      if (this.filtered().length === 0 && !this.usingFolders()) {
        Column({ space: 6 }) {
          Text(this.sessions.length === 0 ? t('还没有对话') : t('没有匹配的对话'))
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.sessions.length === 0 ? t('点上方按钮开始') : t('换个关键词试试'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.usingFolders()) {
        List({ space: 3 }) {
          ForEach(this.folderGroups(), (group: FolderGroup) => {
            ListItemGroup({ header: this.folderHeader(group) }) {
              if (!group.collapsed) {
                ForEach(group.sessions, (item: SessionMeta) => {
                  ListItem() {
                    this.sessionRow(item)
                  }
                }, (item: SessionMeta) => item.id + ':' + item.title + ':' + item.updatedAt + ':' +
                  item.modelId + ':' + (this.currentId === item.id ? '1' : '0') + ':' +
                  (item.pinned ? 'p' : '') + ':' + (item.archived ? 'a' : '') + ':' +
                (item.statusBadge !== undefined ? item.statusBadge : '') + ':' +
                  (this.selecting && this.isSelected(item.id) ? 's' : ''))
              }
            }
          }, (group: FolderGroup) => group.id + ':' + group.label + ':' +
            (group.collapsed ? 'c' : 'o') + ':' + group.sessions.length.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      } else {
        List({ space: 3 }) {
          ForEach(this.grouped(), (group: SessionGroup) => {
            ListItemGroup({ header: this.groupHeader(group.label) }) {
              ForEach(group.sessions, (item: SessionMeta) => {
                ListItem() {
                  this.sessionRow(item)
                }
              }, (item: SessionMeta) => item.id + ':' + item.title + ':' + item.updatedAt + ':' +
                item.modelId + ':' + (this.currentId === item.id ? '1' : '0') + ':' +
                (item.pinned ? 'p' : '') + ':' + (item.archived ? 'a' : '') + ':' +
                (item.statusBadge !== undefined ? item.statusBadge : '') + ':' +
                (this.selecting && this.isSelected(item.id) ? 's' : ''))
            }
          }, (group: SessionGroup) => group.label + ':' + group.sessions.length.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }

      Column({ space: 3 }) {
        Text(t('长按对话可复制或删除'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(t('数据仅保存在本机'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(t('备份整库（不含密钥）'))
          .fontSize(11)
          .fontColor(this.accent)
          .padding({ top: 4, bottom: 2 })
          .onClick(() => this.onBackup())
        Text(t('加密备份（密码保护）'))
          .fontSize(11)
          .fontColor(this.accent)
          .padding({ top: 2, bottom: 2 })
          .onClick(() => this.onEncryptedBackup())
        Text(t('导入会话 / 恢复备份'))
          .fontSize(11)
          .fontColor(this.accent)
          .padding({ top: 2, bottom: 2 })
          .onClick(() => this.onImport())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 18, bottom: 14 })
    .backgroundColor($r('app.color.surface_alt'))
    .border({ width: { right: 1 }, color: { right: $r('app.color.border') } })
  }
}
