import {
  ChatAttachment,
  ChatMessage,
  messageKey,
  modelName,
  scaleFont,
  textOf
} from '../core/Types';
import { capsForModel, contextPercent, formatWindow } from '../core/ModelCaps';
import { formatTokens } from '../service/Format';
import { MessageBubble } from './MessageBubble';
import { t } from '../core/I18n';

const SUGGESTIONS: string[] = [
  '帮我写一个鸿蒙 ArkTS 页面',
  '解释这段代码并指出风险',
  '把这个需求拆成可执行任务',
  '翻译并润色下面这段话'
];

@Component
export struct ChatView {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop @Watch('onMessagesChanged') messages: ChatMessage[] = [];
  @Prop streaming: boolean = false;
  @Prop modelId: string = '';
  @Prop title: string = t('新对话');
  @Prop isWide: boolean = true;
  @Prop hasKey: boolean = false;
  /** Enter submits instead of inserting a newline (physical + soft keyboard). */
  @Prop enterToSend: boolean = false;
  /** False for protocols/models that do not accept reasoning_effort. */
  @Prop canThink: boolean = false;
  /** Effective level for this conversation: off / low / medium / high. */
  @Prop thinkingLevel: string = 'off';
  /** Non-empty right after a compaction, until dismissed. */
  @Prop compactNotice: string = '';
  @Prop canUndoCompact: boolean = false;
  @StorageProp('accentColor') accent: string = '#2F6BFF';
  @StorageProp('fontScale') fontScale: number = 1;
  @Link draft: string;
  @Prop attachments: ChatAttachment[] = [];
  onSend: () => void = () => {
  };
  onPickImage: () => void = () => {
  };
  onRemoveAttachment: (index: number) => void = (index: number) => {
  };
  onStop: () => void = () => {
  };
  onSettings: () => void = () => {
  };
  onScheduledTasks: () => void = () => {
  };
  onPickModel: () => void = () => {
  };
  /** Writes the conversation-level override; empty string inherits global. */
  onThinkingLevel: (value: string) => void = (value: string) => {
  };
  onUndoCompact: () => void = () => {
  };
  onDismissCompactNotice: () => void = () => {
  };
  onBack: () => void = () => {
  };
  onNew: () => void = () => {
  };
  onRegenerate: () => void = () => {
  };
  onEdit: (id: string) => void = (id: string) => {
  };
  onRewind: (id: string) => void = (id: string) => {
  };
  /** Receives the assistant turn plus the question it answers. */
  onSnapshot: (message: ChatMessage, question: string) => void =
    (message: ChatMessage, question: string) => {
    };
  onOpenLink: ((url: string) => void) | null = null;

  /** Nearest preceding user message, used as the header question on the card. */
  private questionFor(message: ChatMessage): string {
    let index: number = -1;
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === message.id) {
        index = i;
        break;
      }
    }
    for (let i = index - 1; i >= 0; i--) {
      if (this.messages[i].role === 'user') {
        return textOf(this.messages[i]);
      }
    }
    return '';
  }

  private scroller: Scroller = new Scroller();

  private lastMessageId(): string {
    if (this.messages.length === 0) {
      return '';
    }
    return this.messages[this.messages.length - 1].id;
  }

  /** Only the final assistant answer can be regenerated. */
  private lastAssistantId(): string {
    if (this.streaming || this.messages.length === 0) {
      return '';
    }
    const last: ChatMessage = this.messages[this.messages.length - 1];
    return last.role === 'assistant' ? last.id : '';
  }

  /** The newest user message is the one edit-and-resend rewinds to. */
  private lastUserId(): string {
    if (this.streaming) {
      return '';
    }
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === 'user') {
        return this.messages[i].id;
      }
    }
    return '';
  }

  aboutToAppear(): void {
    // Focus after the first layout pass so the keyboard follows the composer.
    setTimeout(() => {
      try {
        focusControl.requestFocus('composerInput');
      } catch (e) {
        // The input may not be attached yet; the user can tap it normally.
      }
    }, 350);
  }

  onMessagesChanged(): void {
    setTimeout(() => {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (e) {
        // The list is not attached yet (empty -> first message transition).
      }
    }, 40);
  }

  private canSend(): boolean {
    return (this.draft.trim().length > 0 || this.attachments.length > 0) &&
      !this.streaming;
  }

  /**
   * Context pressure: the latest assistant turn reports how many tokens were
   * sent plus generated, which is the best on-device approximation of the
   * conversation's current size.
   */
  private subtitle(): string {
    let value: string = this.messages.length.toString() + t(' 条消息 · ') +
      modelName(this.modelId);
    for (let i = this.messages.length - 1; i >= 0; i--) {
      const message: ChatMessage = this.messages[i];
      if (message.role === 'assistant' && message.totalTokens > 0) {
        const used: number = message.promptTokens + message.completionTokens;
        const window: number = capsForModel(this.modelId).contextWindow;
        value += t(' · 上下文 ') + formatTokens(used) + ' / ' + formatWindow(window) +
          ' (' + contextPercent(used, window).toString() + '%)';
        break;
      }
    }
    return value;
  }

  private thinkingLabel(value: string): string {
    if (value === 'low') {
      return t('低');
    }
    if (value === 'medium') {
      return t('中');
    }
    if (value === 'high') {
      return t('高');
    }
    return t('关');
  }

  @Builder
  thinkingMenu() {
    Column({ space: 2 }) {
      Text(t('思考等级'))
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 4 })
      ForEach(['off', 'low', 'medium', 'high'], (value: string) => {
        Row({ space: 10 }) {
          Text(this.thinkingLabel(value))
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          Text(value === 'off' ? t('不发送 reasoning_effort') : 'reasoning_effort=' + value)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
          Blank()
          if (this.thinkingLevel === value) {
            Text('✓')
              .fontSize(12)
              .fontColor(this.accent)
          }
        }
        .width(230)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(8)
        .backgroundColor(this.thinkingLevel === value
          ? $r('app.color.surface_alt')
          : Color.Transparent)
        .onClick(() => this.onThinkingLevel(value))
      }, (value: string) => value)
    }
    .padding(6)
  }

  @Builder
  headerMenu() {
    Column({ space: 2 }) {
      Text(t('定时任务'))
        .width(160)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .padding(10)
        .onClick(() => this.onScheduledTasks())
      Text(t('设置'))
        .width(160)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .padding(10)
        .onClick(() => this.onSettings())
    }
    .padding(4)
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      if (!this.isWide) {
        Text('‹')
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
          .width(30)
          .textAlign(TextAlign.Center)
          .onClick(() => this.onBack())
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitle())
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 5 }) {
        Text(modelName(this.modelId))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 150 })
        Text('▾')
          .fontSize(9)
          .fontColor($r('app.color.text_tertiary'))
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(9)
      .onClick(() => this.onPickModel())

      if (this.canThink) {
        Row({ space: 4 }) {
          Text(t('思考'))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.thinkingLabel(this.thinkingLevel))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Text('▾')
            .fontSize(8)
            .fontColor($r('app.color.text_tertiary'))
        }
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(9)
        .bindMenu(this.thinkingMenu())
      }

      if (!this.isWide) {
        Text('＋')
          .fontSize(19)
          .fontColor($r('app.color.text_secondary'))
          .padding(6)
          .onClick(() => this.onNew())
      }

      if (this.isWide) {
        Text(t('任务'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .onClick(() => this.onScheduledTasks())

        Text(t('设置'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .onClick(() => this.onSettings())
      } else {
        Text(t('更多'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .bindMenu(this.headerMenu())
      }
    }
    .width('100%')
    .height(62)
    .padding({ left: 18, right: 18 })
    .backgroundColor($r('app.color.bg'))
    .border({ width: { bottom: 1 }, color: { bottom: $r('app.color.border') } })
  }

  @Builder
  hero() {
    Column({ space: 10 }) {
      Text('M')
        .width(62)
        .height(62)
        .borderRadius(20)
        .textAlign(TextAlign.Center)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accent)
        .margin({ bottom: 8 })
      Text(t('新对话'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(SUGGESTIONS, (item: string) => {
          Text(t(item))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .margin(5)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(10)
            .border({ width: 1, color: $r('app.color.border') })
            .onClick(() => {
              this.draft = item;
            })
        }, (item: string) => item)
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  keyBanner() {
    Row({ space: 8 }) {
      Text(t('尚未配置 API Key'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(t('去设置'))
        .fontSize(12)
        .fontColor(this.accent)
        .onClick(() => this.onSettings())
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.accent_soft'))
    .borderRadius(10)
    .margin({ bottom: 10 })
  }

  @Builder
  compactBanner() {
    Row({ space: 8 }) {
      Text(this.compactNotice)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      if (this.canUndoCompact) {
        Text(t('撤销'))
          .fontSize(11)
          .fontColor(this.accent)
          .onClick(() => this.onUndoCompact())
      }
      Text(t('知道了'))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .onClick(() => this.onDismissCompactNotice())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(9)
    .margin({ left: 16, right: 16, bottom: 6 })
  }

  @Builder
  composer() {
    Column({ space: 6 }) {
      if (this.attachments.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.attachments, (item: ChatAttachment, index: number) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              Image('file://' + item.path)
                .width(56)
                .height(56)
                .borderRadius(9)
                .objectFit(ImageFit.Cover)
              Text('✕')
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor('#99000000')
                .borderRadius(8)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .onClick(() => this.onRemoveAttachment(index))
            }
          }, (item: ChatAttachment) => item.uri)
        }
        .width('100%')
        .padding({ left: 10, right: 10 })
      }

      Row({ space: 8 }) {
        if (!this.streaming) {
          Text(t('图片'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 6, right: 6, top: 10, bottom: 10 })
            .onClick(() => this.onPickImage())
        }
        TextArea({ text: this.draft, placeholder: t('问点什么…') })
          .id('composerInput')
          .layoutWeight(1)
          .constraintSize({ minHeight: 42, maxHeight: 150 })
          .fontSize(scaleFont(15, this.fontScale))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .borderWidth(0)
          .padding({ left: 8, right: 8, top: 10, bottom: 10 })
          .onChange((value: string) => {
            this.draft = value;
          })
          .enterKeyType(this.enterToSend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
          .onSubmit(() => {
            // NEW_LINE never fires onSubmit; Send does. Ignore while streaming
            // so Enter cannot restart a run from a half-written draft.
            if (this.canSend()) {
              this.onSend();
            }
          })

        Text(this.streaming ? '■' : '↑')
          .width(38)
          .height(38)
          .borderRadius(19)
          .textAlign(TextAlign.Center)
          .fontSize(this.streaming ? 13 : 19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.streaming ? $r('app.color.on_accent') :
            (this.canSend() ? $r('app.color.on_accent') : $r('app.color.text_tertiary')))
          .backgroundColor(this.streaming ? $r('app.color.danger') :
            (this.canSend() ? this.accent : $r('app.color.surface_alt')))
          .onClick(() => {
            if (this.streaming) {
              this.onStop();
            } else if (this.canSend()) {
              this.onSend();
            }
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 14 })
    .backgroundColor($r('app.color.bg'))
  }

  build() {
    Column() {
      this.header()

      Column() {
        if (!this.hasKey) {
          this.keyBanner()
        }

        if (this.messages.length === 0) {
          Column() {
            this.hero()
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller, space: 18 }) {
            ForEach(this.messages, (message: ChatMessage) => {
              ListItem() {
                MessageBubble({
                  message: message,
                  canRegenerate: message.id === this.lastAssistantId(),
                  canEdit: message.id === this.lastUserId(),
                  canRewind: !this.streaming && message.id !== this.lastMessageId(),
                  onRegenerate: () => this.onRegenerate(),
                  onEdit: () => this.onEdit(message.id),
                  onRewind: () => this.onRewind(message.id),
                  onSnapshot: () => this.onSnapshot(message, this.questionFor(message)),
                  onOpenLink: this.onOpenLink
                })
              }
              .width('100%')
            }, (message: ChatMessage) => messageKey(message))
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 20, right: 20, top: 14, bottom: 6 })
          .scrollBar(BarState.Auto)
        }

        if (this.compactNotice.length > 0) {
          this.compactBanner()
        }

        this.composer()
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ maxWidth: 940 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .alignItems(HorizontalAlign.Center)
  }
}
