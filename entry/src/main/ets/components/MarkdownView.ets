import { pasteboard } from '@kit.BasicServicesKit';
import {
  MdBlock,
  MdBlockKind,
  MdInline,
  parseInline,
  parseMarkdown
} from '../core/Markdown';

@Component
export struct MarkdownView {
  @Prop @Watch('onTextChanged') text: string = '';
  @State blocks: MdBlock[] = [];

  aboutToAppear(): void {
    this.blocks = parseMarkdown(this.text);
  }

  onTextChanged(): void {
    this.blocks = parseMarkdown(this.text);
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return 22;
    }
    if (level === 2) {
      return 19;
    }
    if (level === 3) {
      return 17;
    }
    return 15;
  }

  private copy(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    });
  }

  @Builder
  inlineText(text: string, fontSize: number, color: ResourceColor, weight: FontWeight) {
    Text() {
      ForEach(parseInline(text), (segment: MdInline) => {
        Span(segment.text)
          .fontWeight(segment.bold ? FontWeight.Bold : weight)
          .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontColor(segment.code ? $r('app.color.accent') : color)
          .fontFamily(segment.code ? 'monospace' : 'HarmonyOS Sans')
          .decoration({ type: segment.link.length > 0 ? TextDecorationType.Underline : TextDecorationType.None })
      })
    }
    .fontSize(fontSize)
    .fontColor(color)
    .lineHeight(fontSize * 1.62)
    .width('100%')
    .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  codeBlock(block: MdBlock) {
    Column() {
      Row() {
        Text(block.lang.length > 0 ? block.lang : 'code')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text('复制')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => this.copy(block.text))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 6 })

      Text(block.text)
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .lineHeight(20)
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  listItem(block: MdBlock) {
    Row() {
      Text(block.ordered ? block.index.toString() + '.' : '•')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .width(block.ordered ? 26 : 14)
      Column() {
        this.inlineText(block.text, 15, $r('app.color.text_primary'), FontWeight.Normal)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  quoteBlock(block: MdBlock) {
    Column() {
      this.inlineText(block.text, 15, $r('app.color.text_secondary'), FontWeight.Normal)
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 2, bottom: 2 })
    .border({ width: { left: 3 }, color: { left: $r('app.color.quote_bar') } })
  }

  @Builder
  renderBlock(block: MdBlock) {
    if (block.kind === MdBlockKind.Code) {
      this.codeBlock(block)
    } else if (block.kind === MdBlockKind.Heading) {
      Column() {
        this.inlineText(block.text, this.headingSize(block.level), $r('app.color.text_primary'), FontWeight.Bold)
      }
      .width('100%')
      .margin({ top: block.level <= 2 ? 10 : 4, bottom: 2 })
    } else if (block.kind === MdBlockKind.ListItem) {
      this.listItem(block)
    } else if (block.kind === MdBlockKind.Quote) {
      this.quoteBlock(block)
    } else if (block.kind === MdBlockKind.Divider) {
      Divider()
        .color($r('app.color.border'))
        .margin({ top: 8, bottom: 8 })
    } else {
      this.inlineText(block.text, 15, $r('app.color.text_primary'), FontWeight.Normal)
    }
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.blocks, (block: MdBlock, index: number) => {
        this.renderBlock(block)
      }, (block: MdBlock, index: number) => index.toString() + block.kind + block.text.length)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
