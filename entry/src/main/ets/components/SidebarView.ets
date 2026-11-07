import { SessionMeta, modelName } from '../core/Types';
import { formatRelative } from '../service/Format';

@Component
export struct SidebarView {
  @Prop sessions: SessionMeta[] = [];
  @Prop currentId: string = '';
  @Link query: string;
  onNew: () => void = () => {
  };
  onSelect: (id: string) => void = (id: string) => {
  };
  onDelete: (id: string) => void = (id: string) => {
  };
  onSettings: () => void = () => {
  };

  private filtered(): SessionMeta[] {
    const keyword: string = this.query.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.sessions;
    }
    const result: SessionMeta[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const item: SessionMeta = this.sessions[i];
      if (item.title.toLowerCase().indexOf(keyword) >= 0 ||
        item.modelId.toLowerCase().indexOf(keyword) >= 0) {
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
        .backgroundColor($r('app.color.accent'))
      Column({ space: 1 }) {
        Text('Minis')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('鸿蒙平板版')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text('⚙')
        .fontSize(18)
        .fontColor($r('app.color.text_secondary'))
        .padding(6)
        .onClick(() => this.onSettings())
    }
    .width('100%')
  }

  @Builder
  sessionRow(item: SessionMeta) {
    Column({ space: 4 }) {
      Text(item.title)
        .fontSize(14)
        .fontWeight(this.currentId === item.id ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentId === item.id ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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
    .backgroundColor(this.currentId === item.id ? $r('app.color.accent_soft') : Color.Transparent)
    .onClick(() => this.onSelect(item.id))
    .gesture(
      LongPressGesture({ repeat: false, duration: 520 })
        .onAction(() => this.onDelete(item.id))
    )
  }

  build() {
    Column({ space: 14 }) {
      this.brand()

      Row({ space: 8 }) {
        Text('＋')
          .fontSize(18)
          .fontColor($r('app.color.on_accent'))
        Text('新建对话')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.accent'))
      .borderRadius(12)
      .onClick(() => this.onNew())

      TextInput({ text: this.query, placeholder: '搜索对话' })
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

      if (this.filtered().length === 0) {
        Column({ space: 6 }) {
          Text(this.sessions.length === 0 ? '还没有对话' : '没有匹配的对话')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.sessions.length === 0 ? '点上方按钮开始' : '换个关键词试试')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 3 }) {
          ForEach(this.filtered(), (item: SessionMeta) => {
            ListItem() {
              this.sessionRow(item)
            }
          }, (item: SessionMeta) => item.id + ':' + item.title + ':' + item.updatedAt + ':' +
            item.modelId + ':' + (this.currentId === item.id ? '1' : '0'))
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }

      Column({ space: 3 }) {
        Text('长按对话可删除')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text('数据仅保存在本机')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
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
