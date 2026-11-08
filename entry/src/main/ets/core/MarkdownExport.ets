/**
 * Markdown export for a conversation.
 *
 * Pure string building so the output can be tested without the file picker.
 * The service layer only chooses a destination and writes the returned text.
 */

import {
  ChatMessage,
  MessagePart,
  PART_REASONING,
  PART_TOOL_CALL,
  StoredSession,
  modelName,
  textOf
} from './Types';
import { t } from './I18n';

const MAX_TOOL_EXPORT_CHARS: number = 20000;

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

export function exportStamp(now: Date): string {
  return now.getFullYear().toString() + '-' + pad2(now.getMonth() + 1) + '-' +
    pad2(now.getDate());
}

/** Replace characters that are illegal in user-facing file names. */
export function safeFileBase(title: string): string {
  const source: string = title.trim();
  if (source.length === 0) {
    return t('对话');
  }
  const forbidden: string = '\\/:*?"<>|';
  let out: string = '';
  for (let i = 0; i < source.length; i++) {
    const ch: string = source.charAt(i);
    out += forbidden.indexOf(ch) >= 0 ? '_' : ch;
  }
  out = out.trim();
  if (out.length > 60) {
    out = out.substring(0, 60);
  }
  return out.length > 0 ? out : t('对话');
}

export function exportFileName(title: string, now: Date): string {
  return safeFileBase(title) + '-' + exportStamp(now) + '.md';
}

function fence(content: string, language: string): string {
  const body: string = content.length > MAX_TOOL_EXPORT_CHARS
    ? content.substring(0, MAX_TOOL_EXPORT_CHARS) + t('\n…（已截断）')
    : content;
  return '````' + language + '\n' + body + '\n````';
}

function messageRole(role: string): string {
  if (role === 'user') {
    return t('## 用户');
  }
  if (role === 'assistant') {
    return t('## 助手');
  }
  return t('## 系统');
}

function renderMessage(message: ChatMessage): string {
  let out: string = messageRole(message.role) + '\n\n';
  for (let i = 0; i < message.parts.length; i++) {
    const part: MessagePart = message.parts[i];
    if (part.kind === PART_REASONING) {
      if (part.text.trim().length > 0) {
        out += t('> 思考过程\n\n') + quote(part.text) + '\n\n';
      }
    } else if (part.kind === PART_TOOL_CALL) {
      out += t('**工具：') + part.toolName + '**\n\n';
      if (part.argumentsText.length > 0) {
        out += fence(part.argumentsText, 'json') + '\n\n';
      }
      if (part.resultText.length > 0) {
        out += fence(part.resultText, 'text') + '\n\n';
      }
    }
  }
  const text: string = textOf(message).trim();
  if (text.length > 0) {
    out += text + '\n\n';
  }
  return out;
}

function quote(value: string): string {
  const lines: string[] = value.split('\n');
  let out: string = '';
  for (let i = 0; i < lines.length; i++) {
    out += '> ' + lines[i] + '\n';
  }
  return out;
}

export function exportMarkdown(session: StoredSession, now: Date): string {
  const meta = session.meta;
  let out: string = '# ' + meta.title + '\n\n';
  out += t('> 模型：') + modelName(meta.modelId) + t(' · 导出时间：') +
    exportStamp(now) + '\n\n';

  let wrote: boolean = false;
  for (let i = 0; i < session.messages.length; i++) {
    const message: ChatMessage = session.messages[i];
    if (message.parts.length === 0) {
      continue;
    }
    out += renderMessage(message);
    out += '---\n\n';
    wrote = true;
  }
  if (!wrote) {
    out += t('（空对话）\n');
  }
  return out;
}
