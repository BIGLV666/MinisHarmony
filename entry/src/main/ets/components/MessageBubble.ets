import { pasteboard } from '@kit.BasicServicesKit';
import {
  ChatMessage,
  MessagePart,
  PART_IMAGE,
  TOOL_DONE,
  TOOL_ERROR,
  TOOL_RUNNING,
  reasoningOf,
  textOf,
  toolCallsOf
} from '../core/Types';
import { AttachmentStore } from '../service/AttachmentStore';
import { formatRelative, formatTokens } from '../service/Format';
import { MarkdownView } from './MarkdownView';

@Component
export struct MessageBubble {
  @Prop message: ChatMessage = {
    id: '',
    role: 'assistant',
    parts: [],
    createdAt: 0,
    streaming: false,
    error: false,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0
  };
  @StorageProp('accentColor') accent: string = '#2F6BFF';
  @State reasoningOpen: boolean = false;
  @State openToolId: string = '';
  @State previewOpen: boolean = false;
  @State previewPath: string = '';
  @Prop canRegenerate: boolean = false;
  @Prop canEdit: boolean = false;
  /** Earlier messages offer a checkpoint; the latest one has nothing to trim. */
  @Prop canRewind: boolean = false;
  onRegenerate: () => void = () => {
  };
  onEdit: () => void = () => {
  };
  onRewind: () => void = () => {
  };

  private isUser(): boolean {
    return this.message.role === 'user';
  }

  private content(): string {
    return textOf(this.message);
  }

  private reasoning(): string {
    return reasoningOf(this.message);
  }

  private calls(): MessagePart[] {
    return toolCallsOf(this.message);
  }

  private images(): MessagePart[] {
    const result: MessagePart[] = [];
    for (let i = 0; i < this.message.parts.length; i++) {
      const part: MessagePart = this.message.parts[i];
      if (part.kind === PART_IMAGE && part.uri.length > 0) {
        result.push(part);
      }
    }
    return result;
  }

  private openPreview(part: MessagePart): void {
    this.previewPath = AttachmentStore.absolutePath(part.uri);
    this.previewOpen = true;
  }

  private toolKey(part: MessagePart): string {
    return part.toolCallId.length > 0
      ? part.toolCallId
      : part.toolName + ':' + part.argumentsText;
  }

  private isToolOpen(part: MessagePart): boolean {
    return this.openToolId.length > 0 && this.openToolId === this.toolKey(part);
  }

  private toggleTool(part: MessagePart): void {
    const key: string = this.toolKey(part);
    this.openToolId = this.openToolId === key ? '' : key;
  }

  private toolStatus(status: string): string {
    if (status === TOOL_RUNNING) {
      return '执行中…';
    }
    if (status === TOOL_DONE) {
      return '完成';
    }
    if (status === TOOL_ERROR) {
      return '失败';
    }
    return '等待执行';
  }

  private copy(): void {
    const data: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      this.content()
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
      .fontColor(this.accent)
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
          .fontColor(this.accent)
        Blank()
        if (this.message.streaming && this.content().length === 0) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(this.accent)
        }
      }
      .width('100%')
      .onClick(() => {
        this.reasoningOpen = !this.reasoningOpen;
      })

      if (this.reasoningOpen) {
        Text(this.reasoning())
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
  toolCard(part: MessagePart) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(part.status === TOOL_RUNNING ? '◌' : (part.isError ? '✕' : '✓'))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(part.isError ? $r('app.color.danger') : this.accent)
        Text(part.toolName)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(this.toolStatus(part.status))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .onClick(() => this.toggleTool(part))

      if (this.isToolOpen(part)) {
        Text('参数')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Text(part.argumentsText.length > 0 ? part.argumentsText : '{}')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(17)
          .maxLines(8)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
        if (part.resultText.length > 0) {
          Text('结果')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          Text(part.resultText)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(17)
            .maxLines(14)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
    .border({
      width: 1,
      color: part.isError ? $r('app.color.danger') : $r('app.color.border')
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  thinking() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(15)
        .height(15)
        .color(this.accent)
      Text('正在思考…')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  userBubble() {
    Column({ space: 6 }) {
      if (this.images().length > 0) {
        ForEach(this.images(), (part: MessagePart) => {
          Image('file://' + AttachmentStore.absolutePath(part.uri))
            .width(180)
            .height(130)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .onClick(() => this.openPreview(part))
        }, (part: MessagePart) => part.uri)
      }
      Text(this.content())
        .fontSize(15)
        .lineHeight(23)
        .fontColor($r('app.color.on_accent'))
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
      Row({ space: 12 }) {
        if (this.canEdit) {
          Text('编辑')
            .fontSize(10)
            .fontColor($r('app.color.on_accent'))
            .opacity(0.82)
            .onClick(() => this.onEdit())
        }
        if (this.canRewind) {
          Text('回到这里')
            .fontSize(10)
            .fontColor($r('app.color.on_accent'))
            .opacity(0.82)
            .onClick(() => this.onRewind())
        }
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
    .backgroundColor(this.accent)
    .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 5 })
    .constraintSize({ maxWidth: '80%' })
  }

  @Builder
  assistantBubble() {
    Column({ space: 9 }) {
      if (this.reasoning().length > 0) {
        this.reasoningPanel()
      }

      if (this.calls().length > 0) {
        ForEach(this.calls(), (part: MessagePart) => {
          this.toolCard(part)
        }, (part: MessagePart) => part.toolCallId + ':' + part.status + ':' +
          part.argumentsText.length + ':' + part.resultText.length)
      }

      if (this.content().length > 0) {
        MarkdownView({ text: this.content() })
      } else if (this.message.streaming && this.calls().length === 0) {
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
        if (this.message.totalTokens > 0) {
          Text('↑' + formatTokens(this.message.promptTokens) +
            ' ↓' + formatTokens(this.message.completionTokens))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        if (this.content().length > 0 && !this.message.streaming) {
          Text('复制')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => this.copy())
        }
        if (this.canRegenerate) {
          Text(this.message.error ? '重试' : '重新生成')
            .fontSize(11)
            .fontColor(this.accent)
            .onClick(() => this.onRegenerate())
        }
        if (this.canRewind) {
          Text('回到这里')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => this.onRewind())
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

  @Builder
  previewOverlay() {
    Column({ space: 12 }) {
      Image('file://' + this.previewPath)
        .width('100%')
        .layoutWeight(1)
        .objectFit(ImageFit.Contain)
      Text('点击任意处关闭')
        .fontSize(12)
        .fontColor('#CCFFFFFF')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#000000')
    .onClick(() => {
      this.previewOpen = false;
    })
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
    .bindContentCover($$this.previewOpen, this.previewOverlay())
  }
}
