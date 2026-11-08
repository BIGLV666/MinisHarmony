import { ChatMessage, MessagePart, textOf, toolCallsOf } from '../core/Types';
import { shareCardBody, shareCardStamp, shareCardToolLines } from '../core/ShareCard';
import { formatTokens } from '../service/Format';
import { MarkdownView } from './MarkdownView';

/** Compact ✓/✕ rows, one per tool call in the turn. */
function toolSummary(message: ChatMessage): string[] {
  const calls: MessagePart[] = toolCallsOf(message);
  const out: string[] = [];
  for (let i = 0; i < calls.length; i++) {
    out.push((calls[i].isError ? '✕ ' : '✓ ') + calls[i].toolName);
  }
  return out;
}

/**
 * Offscreen share card: the user question, the assistant answer and a tool
 * summary on one panel. Called through `componentSnapshot.createFromBuilder`,
 * so it must not contain ArkWeb (`plainMath` renders formulas as text).
 */
@Builder
export function shareCardView(
  question: string,
  message: ChatMessage,
  title: string,
  accent: string
): void {
  Column({ space: 12 }) {
    Row({ space: 8 }) {
      Text('MinisHarmony')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
      Text(title)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(shareCardStamp(message.createdAt))
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')

    if (question.length > 0) {
      Column() {
        Text(shareCardBody(question))
          .fontSize(14)
          .lineHeight(21)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .backgroundColor($r('app.color.accent_soft'))
      .borderRadius(10)
    }

    MarkdownView({
      text: shareCardBody(textOf(message)),
      plainMath: true
    })

    if (toolSummary(message).length > 0) {
      Column({ space: 3 }) {
        ForEach(shareCardToolLines(toolSummary(message)), (line: string) => {
          Text(line)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }, (line: string, index: number) => index.toString() + line)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(8)
    }

    Divider()
      .color($r('app.color.border'))

    Row({ space: 8 }) {
      Text('对话截图')
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
      Blank()
      if (message.totalTokens > 0) {
        Text('↑' + formatTokens(message.promptTokens) + ' ↓' +
          formatTokens(message.completionTokens))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
  }
  .width(720)
  .padding({ left: 28, right: 28, top: 22, bottom: 18 })
  .backgroundColor($r('app.color.surface'))
  .alignItems(HorizontalAlign.Start)
}
