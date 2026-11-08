/**
 * Context compaction helpers.
 *
 * Two separate concerns live here, both pure so they can be tested under Node:
 *
 * - `planCompact` / `transcriptForSummary`: split a long conversation into the
 *   part that gets replaced by a model-written summary and the recent turns
 *   that stay verbatim.
 * - `fitHistoryToBudget`: shrink *old tool results* for one request without
 *   touching the stored transcript. The UI keeps the full output; the model
 *   receives a trimmed view only when the prompt would be too large.
 */

import {
  ChatMessage,
  MessagePart,
  PART_TOOL_CALL,
  newChatMessage,
  textOf
} from './Types';
import { t } from './I18n';

export const COMPACT_DEFAULT_KEEP_TURNS: number = 3;
export const COMPACT_MIN_MESSAGES: number = 6;
export const SUMMARY_TRANSCRIPT_LIMIT: number = 24000;

/** Below this a tool result is already small enough to leave alone. */
export const TOOL_TRIM_THRESHOLD: number = 800;
export const TOOL_TRIM_KEEP: number = 400;

export interface CompactPlan {
  /** Old turns replaced by the summary. */
  head: ChatMessage[];
  /** Recent turns kept verbatim; always starts with a user message. */
  tail: ChatMessage[];
}

function userTurnStarts(messages: ChatMessage[]): number[] {
  const starts: number[] = [];
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].role === 'user') {
      starts.push(i);
    }
  }
  return starts;
}

/**
 * Split at the start of the `keepTurns`-th newest user turn. Keeping the tail
 * aligned on a user message means tool results in the tail stay paired with
 * the assistant request that produced them. Returns null when the conversation
 * is too short or already fits.
 */
export function planCompact(messages: ChatMessage[], keepTurns: number): CompactPlan | null {
  if (messages.length < COMPACT_MIN_MESSAGES) {
    return null;
  }
  const starts: number[] = userTurnStarts(messages);
  if (starts.length <= keepTurns) {
    return null;
  }
  const boundary: number = starts[starts.length - keepTurns];
  if (boundary <= 0) {
    return null;
  }
  return {
    head: messages.slice(0, boundary),
    tail: messages.slice(boundary)
  };
}

function clip(value: string, limit: number): string {
  if (value.length <= limit) {
    return value;
  }
  return value.substring(0, limit) + t('…（截断）');
}

/**
 * Flatten old turns into a plain transcript for the summarisation request.
 * Tool results are clipped harder than text because they dominate the size.
 */
export function transcriptForSummary(messages: ChatMessage[], maxChars: number): string {
  let out: string = '';
  for (let i = 0; i < messages.length; i++) {
    if (out.length >= maxChars) {
      break;
    }
    const message: ChatMessage = messages[i];
    const body: string = textOf(message).trim();
    if (body.length > 0) {
      out += (message.role === 'user' ? t('用户：') : t('助手：')) + body + '\n\n';
    }
    for (let j = 0; j < message.parts.length; j++) {
      const part: MessagePart = message.parts[j];
      if (part.kind !== PART_TOOL_CALL) {
        continue;
      }
      out += t('[工具 ') + part.toolName + t('] 参数：') +
        clip(part.argumentsText, 300) + t('\n结果：') +
        clip(part.resultText, 600) + '\n\n';
    }
  }
  if (out.length > maxChars) {
    out = out.substring(0, maxChars) + t('\n…（更早内容已省略）');
  }
  return out;
}

/** The synthetic system message that replaces the compacted head. */
export function makeSummaryMessage(id: string, summary: string): ChatMessage {
  return newChatMessage(
    id,
    'system',
    t('以下是本次对话较早部分的摘要，请把它当作已读上下文：\n\n') + summary.trim()
  );
}

export interface BudgetResult {
  /** Request-only copy; the caller's stored messages are never mutated. */
  messages: ChatMessage[];
  trimmedParts: number;
  savedChars: number;
}

function cloneMessage(source: ChatMessage): ChatMessage {
  const parts: MessagePart[] = [];
  for (let i = 0; i < source.parts.length; i++) {
    const part: MessagePart = source.parts[i];
    parts.push({
      kind: part.kind,
      text: part.text,
      toolCallId: part.toolCallId,
      toolName: part.toolName,
      argumentsText: part.argumentsText,
      resultText: part.resultText,
      status: part.status,
      isError: part.isError,
      mimeType: part.mimeType,
      uri: part.uri
    });
  }
  return {
    id: source.id,
    role: source.role,
    parts: parts,
    createdAt: source.createdAt,
    streaming: false,
    error: source.error,
    promptTokens: source.promptTokens,
    completionTokens: source.completionTokens,
    totalTokens: source.totalTokens
  };
}

function historyChars(messages: ChatMessage[]): number {
  let total: number = 0;
  for (let i = 0; i < messages.length; i++) {
    total += textOf(messages[i]).length;
    for (let j = 0; j < messages[i].parts.length; j++) {
      const part: MessagePart = messages[i].parts[j];
      if (part.kind === PART_TOOL_CALL) {
        total += part.argumentsText.length + part.resultText.length;
      }
    }
  }
  return total;
}

/**
 * Keep the last `keepTailMessages` messages untouched and replace oversized
 * tool results in the rest with a short prefix. Returns the original array
 * when nothing needs trimming, so the common path allocates nothing.
 */
export function fitHistoryToBudget(
  messages: ChatMessage[],
  maxChars: number,
  keepTailMessages: number = 6
): BudgetResult {
  const total: number = historyChars(messages);
  if (total <= maxChars || maxChars <= 0) {
    return { messages: messages, trimmedParts: 0, savedChars: 0 };
  }

  const copies: ChatMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    copies.push(cloneMessage(messages[i]));
  }
  const tailStart: number = Math.max(0, copies.length - keepTailMessages);
  let trimmedParts: number = 0;
  let savedChars: number = 0;

  for (let i = 0; i < tailStart; i++) {
    for (let j = 0; j < copies[i].parts.length; j++) {
      const part: MessagePart = copies[i].parts[j];
      if (part.kind !== PART_TOOL_CALL || part.resultText.length <= TOOL_TRIM_THRESHOLD) {
        continue;
      }
      const originalLength: number = part.resultText.length;
      part.resultText = part.resultText.substring(0, TOOL_TRIM_KEEP) +
        t('\n…（为控制上下文，较早的工具结果已省略 ') +
        (originalLength - TOOL_TRIM_KEEP).toString() + t(' 字符）');
      trimmedParts++;
      savedChars += originalLength - part.resultText.length;
    }
  }

  return {
    messages: copies,
    trimmedParts: trimmedParts,
    savedChars: savedChars
  };
}
