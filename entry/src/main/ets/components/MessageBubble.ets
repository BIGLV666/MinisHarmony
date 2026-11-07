import { pasteboard } from '@kit.BasicServicesKit';
import { ChatMessage } from '../core/Types';
import { formatRelative } from '../service/Format';
import { MarkdownView } from './MarkdownView';

@Component
export struct MessageBubble {
  @Prop message: ChatMessage = {
    id: '',
    role: 'assistant',
    content: '',
    reasoning: '',
    createdAt: 0,
    streaming: false,
    error: false
  };
  @State reasoningOpen: boolean = false;

  private isUser(): boolean {
    return this.message.role === 'user';
  }

  private copy(): void {
    const data: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      this.message.content
    );
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    });
  }

  @Builder
  avatar() {
    Text('M')
      .width(30)
      .height(30)
      .borderRadius(15)
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.accent'))
      .backgroundColor($r('app.color.accent_soft'))
  }

  @Builder
  reasoningPanel() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(this.message.streaming ? '思考中…' : '思考过程')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text(this.reasoningOpen ? '收起' : '展开')
          .fontSize(11)
          .fontColor($r('app.color.accent'))
        Blank()
        if (this.message.streaming && this.message.content.length === 0) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color($r('app.color.accent'))
        }
      }
      .width('100%')
      .onClick(() => {
        this.reasoningOpen = !this.reasoningOpen;
      })

      if (this.reasoningOpen) {
        Text(this.message.reasoning)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(19)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  thinking() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(15)
        .height(15)
        .color($r('app.color.accent'))
      Text('正在思考…')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  userBubble() {
    Column({ space: 6 }) {
      Text(this.message.content)
        .fontSize(15)
        .lineHeight(23)
        .fontColor($r('app.color.on_accent'))
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
      Row() {
        Blank()
        Text(formatRelative(this.message.createdAt))
          .fontSize(10)
          .fontColor($r('app.color.on_accent'))
          .opacity(0.62)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 10, bottom: 8 })
    .backgroundColor($r('app.color.accent'))
    .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 5 })
    .constraintSize({ maxWidth: '80%' })
  }

  @Builder
  assistantBubble() {
    Column({ space: 9 }) {
      if (this.message.reasoning.length > 0) {
        this.reasoningPanel()
      }

      if (this.message.content.length > 0) {
        MarkdownView({ text: this.message.content })
      } else if (this.message.streaming) {
        this.thinking()
      }

      if (this.message.error) {
        Text('生成中断')
          .fontSize(11)
          .fontColor($r('app.color.danger'))
      }

      Row({ space: 12 }) {
        Text(formatRelative(this.message.createdAt))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        if (this.message.content.length > 0 && !this.message.streaming) {
          Text('复制')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => this.copy())
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 11, bottom: 9 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 5, topRight: 16, bottomLeft: 16, bottomRight: 16 })
    .border({ width: 1, color: $r('app.color.border') })
    .constraintSize({ maxWidth: '82%' })
  }

  build() {
    Row({ space: 10 }) {
      if (!this.isUser()) {
        this.avatar()
      }
      if (this.isUser()) {
        Blank()
        this.userBubble()
      } else {
        this.assistantBubble()
        Blank()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
