import { pasteboard } from '@kit.BasicServicesKit';
import {
  ChatMessage,
  MessagePart,
  PART_FILE,
  PART_IMAGE,
  TOOL_DONE,
  TOOL_ERROR,
  TOOL_RUNNING,
  reasoningOf,
  scaleFont,
  textOf,
  toolCallsOf,
  toolPartKey
} from '../core/Types';
import { AttachmentStore } from '../service/AttachmentStore';
import { formatRelative, formatTokens } from '../service/Format';
import { MarkdownView } from './MarkdownView';
import { i18nVariants, t } from '../core/I18n';
import { MinisResource } from '../core/MinisResource';

/**
 * Per-message reasoning display state. The list rebuilds a bubble whenever
 * streamed text grows (the ForEach key includes the text length), so local
 * component state alone cannot remember a manual expand/collapse. Keying by
 * message id keeps the user's choice across rebuilds and lets us time the
 * thinking phase without storing a duration in the transcript.
 */
interface ReasoningState {
  manual: boolean;
  open: boolean;
  startedAt: number;
  endedAt: number;
  sawStreaming: boolean;
}

const reasoningStates: Map<string, ReasoningState> = new Map<string, ReasoningState>();

@Component
export struct MessageBubble {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
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
  @StorageProp('autoExpandThinking') autoExpandThinking: boolean = false;
  @StorageProp('messageFontScale') messageFontScale: number = 1;
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
  /** Running tool cards expose the same global stop as the composer. */
  onStop: () => void = () => {
  };
  /** Trim the transcript at this tool call and let the model run again. */
  onRerunTool: (part: MessagePart) => void = (part: MessagePart) => {
  };
  /** Render this turn into a shareable PNG (host builds the offscreen card). */
  onSnapshot: () => void = () => {
  };
  onOpenLink: ((url: string) => void) | null = null;
  onOpenMinis: ((resource: MinisResource) => void) | null = null;

  private isUser(): boolean {
    return this.message.role === 'user';
  }

  private isSystem(): boolean {
    return this.message.role === 'system';
  }

  /** Compaction summaries get a distinct label from ordinary notices. */
  private isSummary(): boolean {
    if (!this.isSystem()) {
      return false;
    }
    // Summaries created before a language switch keep the old prefix.
    const prefixes: string[] = i18nVariants('以下是本次对话较早部分的摘要');
    for (let i = 0; i < prefixes.length; i++) {
      if (this.content().startsWith(prefixes[i])) {
        return true;
      }
    }
    return false;
  }

  private content(): string {
    return textOf(this.message);
  }

  private reasoning(): string {
    return reasoningOf(this.message);
  }

  aboutToAppear(): void {
    const state: ReasoningState = this.reasoningState();
    // Follow the stream by default; once the user toggles, respect that
    // choice for the rest of the turn and after it settles.
    this.reasoningOpen = state.manual
      ? state.open
      : ((this.message.streaming || this.autoExpandThinking) &&
        this.reasoning().length > 0);
  }

  private reasoningState(): ReasoningState {
    let state: ReasoningState | undefined = reasoningStates.get(this.message.id);
    if (state === undefined) {
      state = {
        manual: false,
        open: false,
        startedAt: 0,
        endedAt: 0,
        sawStreaming: false
      };
      reasoningStates.set(this.message.id, state);
    }
    if (this.reasoning().length > 0 && state.startedAt === 0) {
      state.startedAt = Date.now();
    }
    if (this.message.streaming) {
      state.sawStreaming = true;
    } else if (state.sawStreaming && state.endedAt === 0) {
      state.endedAt = Date.now();
    }
    return state;
  }

  private reasoningExcerpt(): string {
    const text: string = this.reasoning().trim();
    if (text.length === 0) {
      return '';
    }
    const lines: string[] = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length > 0) {
        return line.length > 42 ? line.substring(0, 42) + t('…') : line;
      }
    }
    return '';
  }

  /** One collapsed line: elapsed thinking time plus a readable excerpt. */
  private reasoningSummary(): string {
    const state: ReasoningState = this.reasoningState();
    const excerpt: string = this.reasoningExcerpt();
    let head: string = t('思考过程');
    if (state.sawStreaming && state.startedAt > 0) {
      const end: number = state.endedAt > 0 ? state.endedAt : Date.now();
      const seconds: number = Math.max(1, Math.round((end - state.startedAt) / 1000));
      head = t('思考了 ') + seconds.toString() + t(' 秒');
    }
    return excerpt.length > 0 ? head + t(' · ') + excerpt : head;
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

  /** Video/audio attachments stay as file parts and play inline. */
  private media(kind: string): MessagePart[] {
    const result: MessagePart[] = [];
    for (let i = 0; i < this.message.parts.length; i++) {
      const part: MessagePart = this.message.parts[i];
      if (part.kind === PART_FILE && part.uri.length > 0 &&
        part.mimeType.startsWith(kind)) {
        result.push(part);
      }
    }
    return result;
  }

  private videos(): MessagePart[] {
    return this.media('video/');
  }

  private audios(): MessagePart[] {
    return this.media('audio/');
  }

  private toolKey(part: MessagePart): string {
    return toolPartKey(part);
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
      return t('执行中…');
    }
    if (status === TOOL_DONE) {
      return t('完成');
    }
    if (status === TOOL_ERROR) {
      return t('失败');
    }
    return t('等待执行');
  }

  /** The last few lines are what matter while a build or install streams. */
  private liveTail(text: string): string {
    const lines: string[] = text.split('\n');
    const start: number = lines.length > 4 ? lines.length - 4 : 0;
    const tail: string[] = [];
    for (let i = start; i < lines.length; i++) {
      tail.push(lines[i]);
    }
    return tail.join('\n').trim();
  }

  private copy(): void {
    const data: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      this.content()
    );
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: t('已复制') });
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: t('复制失败') });
    });
  }

  @Builder
  systemCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(this.isSummary() ? t('对话摘要') : t('提示'))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        if (this.isSummary()) {
          Text(t('较早内容已压缩'))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        Blank()
        Text(formatRelative(this.message.createdAt))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      MarkdownView({
        text: this.content(),
        onOpenLink: this.onOpenLink,
        onOpenMinis: this.onOpenMinis
      })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
    .border({ width: 1, color: $r('app.color.border') })
    .alignItems(HorizontalAlign.Start)
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
        if (this.message.streaming) {
          LoadingProgress()
            .width(13)
            .height(13)
            .color(this.accent)
        }
        Text(this.message.streaming ? t('思考中…') : this.reasoningSummary())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.reasoningOpen ? t('收起') : t('展开'))
          .fontSize(11)
          .fontColor(this.accent)
      }
      .width('100%')
      .onClick(() => {
        const state: ReasoningState = this.reasoningState();
        state.manual = true;
        state.open = !this.reasoningOpen;
        this.reasoningOpen = state.open;
      })

      if (this.reasoningOpen) {
        // Long chains scroll inside the panel instead of stretching the bubble.
        Scroll() {
          Text(this.reasoning())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(19)
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .constraintSize({ maxHeight: 260 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
    .border({ width: { left: 2 }, color: { left: $r('app.color.border') } })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  toolCard(part: MessagePart) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
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
        .layoutWeight(1)
        .onClick(() => this.toggleTool(part))

        // OpenMinis exposes a small red stop square on running tool cards.
        // It routes to the turn-wide stop: tools have no per-call cancel API.
        if (part.status === TOOL_RUNNING) {
          Text('■')
            .fontSize(10)
            .fontColor($r('app.color.on_accent'))
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.danger'))
            .borderRadius(4)
            .accessibilityText(t('停止本次生成'))
            .onClick(() => this.onStop())
        }
      }
      .width('100%')

      // Live output while running, even when the card is collapsed. The model
      // still reads the complete (bounded) result once the call finishes.
      if (part.status === TOOL_RUNNING && part.resultText.length > 0) {
        Column({ space: 2 }) {
          Text(t('实时输出'))
            .fontSize(9)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          Text(this.liveTail(part.resultText))
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(15)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(6)
      }

      // Generated or read images arrive as an attachment URI on the tool part.
      if (part.uri.length > 0) {
        Image('file://' + AttachmentStore.imagePath(part.uri))
          .width(180)
          .height(180)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .onClick(() => {
            this.previewPath = AttachmentStore.imagePath(part.uri);
            this.previewOpen = true;
          })
      }

      if (this.isToolOpen(part)) {
        Text(t('参数'))
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
          Text(t('结果'))
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
        // Block-boundary retry: keep earlier parts, drop this call and
        // everything after it, then let the model decide again.
        if (!this.message.streaming) {
          Text(t('从此处重跑'))
            .fontSize(11)
            .fontColor(this.accent)
            .padding({ top: 2 })
            .width('100%')
            .onClick(() => this.onRerunTool(part))
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
      Text(t('正在思考…'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  userBubble() {
    Column({ space: 6 }) {
      ForEach(this.videos(), (part: MessagePart) => {
        Video({ src: 'file://' + AttachmentStore.absolutePath(part.uri) })
          .width(240)
          .height(150)
          .borderRadius(10)
          .backgroundColor('#000000')
          .objectFit(ImageFit.Contain)
          .autoPlay(false)
          .controls(true)
      }, (part: MessagePart) => 'video:' + part.uri)
      ForEach(this.audios(), (part: MessagePart) => {
        Video({ src: 'file://' + AttachmentStore.absolutePath(part.uri) })
          .width(240)
          .height(54)
          .borderRadius(10)
          .backgroundColor('#000000')
          .objectFit(ImageFit.Contain)
          .autoPlay(false)
          .controls(true)
      }, (part: MessagePart) => 'audio:' + part.uri)
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
        .fontSize(scaleFont(15, this.messageFontScale))
        .lineHeight(scaleFont(23, this.messageFontScale))
        .fontColor($r('app.color.on_accent'))
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
      Row({ space: 12 }) {
        if (this.canEdit) {
          Text(t('编辑'))
            .fontSize(10)
            .fontColor($r('app.color.on_accent'))
            .opacity(0.82)
            .onClick(() => this.onEdit())
        }
        if (this.canRewind) {
          Text(t('回到这里'))
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
        MarkdownView({
          text: this.content(),
          onOpenLink: this.onOpenLink,
          onOpenMinis: this.onOpenMinis
        })
      } else if (this.message.streaming && this.calls().length === 0) {
        this.thinking()
      }

      if (this.message.error) {
        Text(t('生成中断'))
          .fontSize(11)
          .fontColor($r('app.color.danger'))
      }

      // Actions wrap instead of pushing past the bubble on narrow screens.
      Flex({ wrap: FlexWrap.Wrap }) {
        Text(formatRelative(this.message.createdAt))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ right: 12, bottom: 2 })
        if (this.message.totalTokens > 0) {
          Text('↑' + formatTokens(this.message.promptTokens) +
            ' ↓' + formatTokens(this.message.completionTokens))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ right: 12, bottom: 2 })
        }
        if (this.content().length > 0 && !this.message.streaming) {
          Text(t('复制'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ right: 12, bottom: 2 })
            .onClick(() => this.copy())
          Text(t('截图'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ right: 12, bottom: 2 })
            .onClick(() => this.onSnapshot())
        }
        if (this.canRegenerate) {
          Text(this.message.error ? t('重试') : t('重新生成'))
            .fontSize(11)
            .fontColor(this.accent)
            .margin({ right: 12, bottom: 2 })
            .onClick(() => this.onRegenerate())
        }
        if (this.canRewind) {
          Text(t('回到这里'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ right: 12, bottom: 2 })
            .onClick(() => this.onRewind())
        }
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 11, bottom: 9 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 5, topRight: 16, bottomLeft: 16, bottomRight: 16 })
    .border({ width: 1, color: $r('app.color.border') })
    // Full width. A percentage maxWidth clamps the bubble *after* its children
    // are measured against the unclamped row width, so inner panels that use
    // width('100%') (reasoning, tool cards, action rows) ended up wider than
    // the card and spilled past its right edge. A definite width here makes
    // every child's 100% resolve to the same box.
    .width('100%')
  }

  @Builder
  previewOverlay() {
    Column({ space: 12 }) {
      Image('file://' + this.previewPath)
        .width('100%')
        .layoutWeight(1)
        .objectFit(ImageFit.Contain)
      Text(t('点击任意处关闭'))
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
    if (this.isSystem()) {
      this.systemCard()
    } else {
      Row({ space: 10 }) {
        if (!this.isUser()) {
          this.avatar()
        }
        // A weighted column gives the bubble a definite parent width, so the
        // percentage maxWidth below actually clamps instead of letting long
        // code lines push the bubble past the screen edge.
        Column() {
          if (this.isUser()) {
            this.userBubble()
          } else {
            this.assistantBubble()
          }
        }
        .layoutWeight(1)
        .alignItems(this.isUser() ? HorizontalAlign.End : HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .bindContentCover($$this.previewOpen, this.previewOverlay())
    }
  }
}
