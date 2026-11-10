import {
  ChatAttachment,
  ChatMessage,
  MessagePart,
  messageKey,
  modelName,
  scaleFont,
  textOf
} from '../core/Types';
import { capsForModel, contextPercent, formatWindow } from '../core/ModelCaps';
import { formatTokens } from '../service/Format';
import { MessageBubble } from './MessageBubble';
import { t } from '../core/I18n';
import { MinisResource } from '../core/MinisResource';
import { FileEntry } from '../core/FileListing';
import {
  MentionQuery,
  activeMentionAt,
  filterMentionFiles,
  replaceMentionRange
} from '../core/Mention';
import { listWorkspaceFiles } from '../service/WorkspaceFiles';
import { hugePasteInsertion, isPastedAttachment } from '../core/Paste';
import { KeyCode } from '@kit.InputKit';

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
  @Prop @Watch('onStreamingChanged') streaming: boolean = false;
  @Prop modelId: string = '';
  @Prop title: string = t('新对话');
  @Prop isWide: boolean = true;
  /** False when recreated by a language rebuild, which must not pop the keyboard. */
  @Prop autoFocusComposer: boolean = true;
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
  @StorageProp('inputFontScale') inputFontScale: number = 1;
  @StorageProp('autoFocusInput') autoFocusInput: boolean = true;
  @Link @Watch('onDraftChanged') draft: string;
  @Prop attachments: ChatAttachment[] = [];
  /** Hand a >15k paste to the host; true means it became an attachment. */
  onHugePaste: (text: string) => boolean = () => false;
  /** Workspace whose files are offered by the `@` menu. */
  @Prop workspaceRoot: string = '';
  @State mentionOpen: boolean = false;
  @State mentionStart: number = -1;
  @State mentionQuery: string = '';
  @State mentionIndex: number = 0;
  /** Caret end of the `@query` token, reported by the TextArea. */
  @State mentionCaret: number = 0;
  @State mentionSelectionEnd: number = 0;
  /** Cached flat listing; loaded the first time the menu opens. */
  @State mentionFiles: FileEntry[] = [];
  /** Prompts waiting for the current run to reach a model boundary. */
  @Prop queuedCount: number = 0;
  /** Current provider accepts `service_tier: priority`. */
  @Prop canFastMode: boolean = false;
  @Prop fastMode: boolean = false;
  onSend: () => void = () => {
  };
  onQueue: () => void = () => {
  };
  onClearQueued: () => void = () => {
  };
  onPickImage: () => void = () => {
  };
  onPickVideo: () => void = () => {
  };
  onPickAudio: () => void = () => {
  };
  onTakePhoto: () => void = () => {
  };
  onRemoveAttachment: (index: number) => void = (index: number) => {
  };
  onStop: () => void = () => {
  };
  /** Global fast mode; the next request picks the new value up. */
  onFastMode: (on: boolean) => void = (on: boolean) => {
  };
  onSettings: () => void = () => {
  };
  onMemory: () => void = () => {
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
  /** Trim at a tool call (block boundary) and let the model run again. */
  onRerunTool: (messageId: string, part: MessagePart) => void =
    (messageId: string, part: MessagePart) => {
    };
  /** Receives the assistant turn plus the question it answers. */
  onSnapshot: (message: ChatMessage, question: string) => void =
    (message: ChatMessage, question: string) => {
    };
  onOpenLink: ((url: string) => void) | null = null;
  onOpenMinis: ((resource: MinisResource) => void) | null = null;

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
  private inputController: TextAreaController = new TextAreaController();

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
    if (!this.autoFocusComposer) {
      return;
    }
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

  /** Put the cursor back in the composer once a reply settles. */
  onStreamingChanged(): void {
    if (this.streaming || !this.autoFocusInput) {
      return;
    }
    setTimeout(() => {
      try {
        focusControl.requestFocus('composerInput');
      } catch (e) {
        // The composer may be hidden behind another panel.
      }
    }, 120);
  }

  private canSend(): boolean {
    return (this.draft.trim().length > 0 || this.attachments.length > 0) &&
      !this.streaming;
  }

  private canQueue(): boolean {
    return (this.draft.trim().length > 0 || this.attachments.length > 0) &&
      this.streaming;
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
      if (this.canFastMode) {
        Row({ space: 6 }) {
          Text(this.fastMode ? '✓' : '')
            .fontSize(12)
            .width(14)
            .fontColor(this.accent)
          Column({ space: 1 }) {
            Text(t('快速模式'))
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
            Text(t('优先处理，仅部分供应商支持'))
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width(200)
        .padding(10)
        .accessibilityText(t('快速模式'))
        .onClick(() => this.onFastMode(!this.fastMode))
      }
      Text(t('记忆'))
        .width(160)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .padding(10)
        .onClick(() => this.onMemory())
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
        Text(t('记忆'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .onClick(() => this.onMemory())

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

  private onDraftChanged(): void {
    this.refreshMention(this.draft, this.mentionCaret);
  }

  private isPastedFile(item: ChatAttachment): boolean {
    return isPastedAttachment(item.uri, item.mimeType);
  }

  private fileLabel(item: ChatAttachment): string {
    const cut: number = item.path.lastIndexOf('/');
    return cut < 0 ? item.path : item.path.substring(cut + 1);
  }

  private isVideo(item: ChatAttachment): boolean {
    return item.mimeType.startsWith('video/');
  }

  private isAudio(item: ChatAttachment): boolean {
    return item.mimeType.startsWith('audio/');
  }

  private mediaName(item: ChatAttachment): string {
    const prefix: string = 'attachment:';
    return item.uri.startsWith(prefix) ? item.uri.substring(prefix.length) : item.uri;
  }

  private mentionMatches(): FileEntry[] {
    return filterMentionFiles(this.mentionFiles, this.mentionQuery, 5);
  }

  /** Open/update the menu for the `@query` token ending at the caret. */
  private refreshMention(value: string, caret: number): void {
    const active: MentionQuery | null = activeMentionAt(value, caret);
    if (active === null) {
      this.mentionOpen = false;
      return;
    }
    if (this.mentionFiles.length === 0 && this.workspaceRoot.length > 0) {
      this.mentionFiles = listWorkspaceFiles(this.workspaceRoot, 300);
    }
    const changed: boolean = this.mentionQuery !== active.query;
    this.mentionStart = active.start;
    this.mentionQuery = active.query;
    this.mentionOpen = this.mentionMatches().length > 0;
    if (changed) {
      this.mentionIndex = 0;
    }
  }

  /** Move the highlight with wrapping; used by the physical arrow keys. */
  private stepMention(delta: number): void {
    const count: number = this.mentionMatches().length;
    if (count <= 0) {
      return;
    }
    this.mentionIndex = (this.mentionIndex + delta + count) % count;
  }

  private chooseMention(entry: FileEntry): void {
    const end: number = Math.max(this.mentionCaret, this.mentionSelectionEnd);
    const next: string = replaceMentionRange(this.draft, this.mentionStart,
      end, entry.path);
    const caret: number = this.mentionStart + entry.path.length + 2;
    this.draft = next;
    this.mentionCaret = caret;
    this.mentionSelectionEnd = caret;
    this.mentionOpen = false;
    this.mentionStart = -1;
    this.mentionQuery = '';
    setTimeout(() => {
      this.inputController.caretPosition(caret);
    }, 0);
  }

  /** Insert an `@` trigger at the caret, replacing any selection. */
  private startMention(): void {
    const length: number = this.draft.length;
    const a: number = this.mentionCaret >= 0 && this.mentionCaret <= length
      ? this.mentionCaret : length;
    const b: number = this.mentionSelectionEnd >= 0 && this.mentionSelectionEnd <= length
      ? this.mentionSelectionEnd : length;
    const from: number = Math.min(a, b);
    const to: number = Math.max(a, b);
    const before: string = this.draft.substring(0, from);
    const after: string = this.draft.substring(to);
    const space: string = before.length > 0 && !before.endsWith(' ') ? ' ' : '';
    const insert: string = space + '@';
    const caret: number = from + insert.length;
    this.draft = before + insert + after;
    this.mentionCaret = caret;
    this.mentionSelectionEnd = caret;
    this.refreshMention(this.draft, caret);
    setTimeout(() => {
      this.inputController.caretPosition(caret);
    }, 0);
  }

  @Builder
  mentionPanel() {
    Column({ space: 2 }) {
      ForEach(this.mentionMatches(), (entry: FileEntry, index: number) => {
        Row({ space: 8 }) {
          Text('@')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.accent)
          Column({ space: 1 }) {
            Text(entry.name)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (entry.path !== entry.name) {
              Text(entry.path)
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(index === this.mentionIndex
          ? $r('app.color.surface_alt') : Color.Transparent)
        .onClick(() => this.chooseMention(entry))
      }, (entry: FileEntry) => entry.path)
    }
    .width('100%')
    .constraintSize({ maxHeight: 230 })
    .padding(4)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
    .border({ width: 1, color: $r('app.color.border') })
    .margin({ left: 12, right: 12 })
  }

  @Builder
  composer() {
    Column({ space: 6 }) {
      if (this.queuedCount > 0) {
        Row({ space: 8 }) {
          Text(t('排队中') + ' ' + this.queuedCount.toString())
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(t('清空'))
            .fontSize(11)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onClearQueued())
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }

      if (this.attachments.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.attachments, (item: ChatAttachment, index: number) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              if (this.isPastedFile(item)) {
                Column({ space: 2 }) {
                  Text('📄')
                    .fontSize(17)
                  Text(this.fileLabel(item))
                    .fontSize(7)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(48)
                    .textAlign(TextAlign.Center)
                }
                .width(56)
                .height(56)
                .justifyContent(FlexAlign.Center)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(9)
              } else if (this.isVideo(item) || this.isAudio(item)) {
                Column({ space: 2 }) {
                  Text(this.isVideo(item) ? '▶' : '♪')
                    .fontSize(17)
                    .fontColor(Color.White)
                  Text(this.mediaName(item))
                    .fontSize(7)
                    .fontColor('#CCFFFFFF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(48)
                    .textAlign(TextAlign.Center)
                }
                .width(56)
                .height(56)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#1A1A1A')
                .borderRadius(9)
              } else {
                Image('file://' + item.path)
                  .width(56)
                  .height(56)
                  .borderRadius(9)
                  .objectFit(ImageFit.Cover)
              }
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

      if (this.mentionOpen && this.mentionMatches().length > 0) {
        this.mentionPanel()
      }

      Row({ space: 8 }) {
        if (!this.streaming) {
          Text('@')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 6, right: 6, top: 9, bottom: 9 })
            .onClick(() => this.startMention())
          Text(t('图片'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 5, right: 5, top: 10, bottom: 10 })
            .onClick(() => this.onPickImage())
          Text(t('视频'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 5, right: 5, top: 10, bottom: 10 })
            .onClick(() => this.onPickVideo())
          Text(t('音频'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 5, right: 5, top: 10, bottom: 10 })
            .onClick(() => this.onPickAudio())
          Text(t('拍照'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 6, right: 6, top: 10, bottom: 10 })
            .onClick(() => this.onTakePhoto())
        }
        TextArea({
          text: this.draft,
          placeholder: t('问点什么…'),
          controller: this.inputController
        })
          .id('composerInput')
          .layoutWeight(1)
          .constraintSize({ minHeight: 42, maxHeight: 150 })
          .fontSize(scaleFont(15, this.inputFontScale))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .borderWidth(0)
          .padding({ left: 8, right: 8, top: 10, bottom: 10 })
          .onChange((value: string) => {
            const pasted: string = hugePasteInsertion(this.draft, value);
            if (pasted.length > 0 && this.onHugePaste(pasted)) {
              // Show the paste once so TextArea accepts the edit, then restore
              // the draft without the inserted body on the next tick.
              const restore: string = this.draft;
              this.draft = value;
              setTimeout(() => {
                this.draft = restore;
              }, 0);
              return;
            }
            this.draft = value;
          })
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.mentionCaret = selectionStart;
            this.mentionSelectionEnd = selectionEnd;
            this.refreshMention(this.draft, selectionStart);
          })
          // While the mention menu is open Enter must submit so onSubmit can
          // pick the highlighted file instead of inserting a newline.
          .enterKeyType(this.enterToSend || this.mentionOpen
            ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
          .onKeyEvent((event: KeyEvent) => {
            if (!this.mentionOpen || event.type !== KeyType.Down) {
              return;
            }
            if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
              this.stepMention(1);
              event.stopPropagation();
            } else if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
              this.stepMention(-1);
              event.stopPropagation();
            } else if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
              this.mentionOpen = false;
              event.stopPropagation();
            }
          })
          .onSubmit(() => {
            // Enter picks the highlighted file while the mention menu is open.
            if (this.mentionOpen) {
              const matches: FileEntry[] = this.mentionMatches();
              if (matches.length > 0) {
                this.chooseMention(matches[Math.min(this.mentionIndex,
                  matches.length - 1)]);
                return;
              }
            }
            // NEW_LINE never fires onSubmit; Send does. Ignore while streaming
            // so Enter cannot restart a run from a half-written draft.
            if (this.canSend()) {
              this.onSend();
            }
          })

        if (this.streaming && this.canQueue()) {
          Text('↑')
            .width(38)
            .height(38)
            .borderRadius(19)
            .textAlign(TextAlign.Center)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accent)
            .onClick(() => this.onQueue())
        }

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
                  onStop: () => this.onStop(),
                  onRerunTool: (part: MessagePart) => this.onRerunTool(message.id, part),
                  onSnapshot: () => this.onSnapshot(message, this.questionFor(message)),
                  onOpenLink: this.onOpenLink,
                  onOpenMinis: this.onOpenMinis
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
