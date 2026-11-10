import { ChatMessage, textOf } from './Types';

interface TitleReply {
  title?: string | null;
  folder?: string | null;
}

export interface TitleSuggestion {
  title: string;
  /** An offered folder name, or '' when the model did not pick one. */
  folder: string;
}

/**
 * Model-written session titles. The model is asked for one short line, but
 * providers still add quotes, a "标题：" prefix or a trailing full stop; the
 * helpers here turn any answer into a single clean line and build the small
 * transcript sent with the request.
 */

/** Matches the sidebar's comfortable width for Chinese and Latin titles. */
export const TITLE_MAX_CHARS: number = 20;
/** Characters kept from each of the first user/assistant messages. */
const FIRST_TURN_LIMIT: number = 600;
/** Characters kept from each of the last messages in a long conversation. */
const TAIL_TURN_LIMIT: number = 300;
/** Above this many messages the transcript also includes the current tail. */
const LONG_CONVERSATION: number = 8;

const PREFIXES: string[] = [
  '标题：', '标题:', '会话标题：', '会话标题:', 'Title:', 'Title：', 'title:', '# '
];

const QUOTE_PAIRS: string[] = [
  '""', "''", '“”', '‘’', '「」', '『』', '《》', '``'
];

const TRAILING: string = '。．.!！?？;；:：,，、 ';

function stripQuotes(value: string): string {
  let text: string = value.trim();
  let changed: boolean = true;
  while (changed && text.length >= 2) {
    changed = false;
    for (let i = 0; i < QUOTE_PAIRS.length; i++) {
      const pair: string = QUOTE_PAIRS[i];
      if (text.startsWith(pair.substring(0, 1)) && text.endsWith(pair.substring(1, 2))) {
        text = text.substring(1, text.length - 1).trim();
        changed = true;
        break;
      }
    }
  }
  return text;
}

function stripPrefix(value: string): string {
  let text: string = value;
  let changed: boolean = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < PREFIXES.length; i++) {
      const prefix: string = PREFIXES[i];
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        changed = true;
        break;
      }
    }
  }
  return text;
}

/** Collapse runs of whitespace (including newlines) into single spaces. */
export function collapseSpaces(value: string): string {
  const normalized: string = value.split('\t').join(' ').split('\r').join(' ')
    .split('\n').join(' ');
  const pieces: string[] = normalized.split(' ');
  const kept: string[] = [];
  for (let i = 0; i < pieces.length; i++) {
    if (pieces[i].length > 0) {
      kept.push(pieces[i]);
    }
  }
  return kept.join(' ');
}

function trimTrailing(value: string): string {
  let text: string = value;
  while (text.length > 0 && TRAILING.indexOf(text.substring(text.length - 1)) >= 0) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/**
 * Turn a raw model answer into a sidebar title, or '' when nothing usable is
 * left. Cuts to `TITLE_MAX_CHARS` and marks the cut with an ellipsis.
 */
export function cleanTitle(raw: string): string {
  const lines: string[] = raw.split('\n');
  let line: string = '';
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim().length > 0) {
      line = lines[i].trim();
      break;
    }
  }
  let text: string = stripPrefix(line);
  text = stripQuotes(text);
  text = stripPrefix(text);
  text = trimTrailing(collapseSpaces(text));
  if (text.length === 0) {
    return '';
  }
  if (text.length <= TITLE_MAX_CHARS) {
    return text;
  }
  let cut: string = text.substring(0, TITLE_MAX_CHARS);
  cut = trimTrailing(cut);
  return cut + '…';
}

function matchFolder(value: string | null | undefined, folders: string[]): string {
  if (value === undefined || value === null) {
    return '';
  }
  const wanted: string = value.trim().toLowerCase();
  if (wanted.length === 0) {
    return '';
  }
  for (let i = 0; i < folders.length; i++) {
    const name: string = folders[i].trim();
    if (name.length > 0 && name.toLowerCase() === wanted) {
      return name;
    }
  }
  return '';
}

/**
 * Read the optional JSON form used when folders were offered. A plain-text
 * answer still works (the title-only prompt); an unrecognised folder collapses
 * to '' so a hallucinated group can never create or move a session.
 */
export function parseTitleSuggestion(raw: string, folders: string[]): TitleSuggestion {
  const start: number = raw.indexOf('{');
  const end: number = raw.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      const reply: TitleReply = JSON.parse(raw.substring(start, end + 1)) as TitleReply;
      if (reply !== null && reply.title !== undefined && reply.title !== null) {
        const title: string = cleanTitle(reply.title);
        if (title.length > 0) {
          return { title: title, folder: matchFolder(reply.folder, folders) };
        }
      }
    } catch (e) {
      // Fall through to the plain-text form.
    }
  }
  if (raw.indexOf('{') >= 0 || raw.indexOf('}') >= 0) {
    return { title: '', folder: '' };
  }
  return { title: cleanTitle(raw), folder: '' };
}

/** True when a message contributed text worth titling (tool-only turns do not). */
function sayable(message: ChatMessage): boolean {
  return message.role !== 'system' && !message.error && textOf(message).trim().length > 0;
}

export function firstUserText(messages: ChatMessage[]): string {
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].role === 'user' && sayable(messages[i])) {
      return textOf(messages[i]).trim();
    }
  }
  return '';
}

export function firstAssistantText(messages: ChatMessage[]): string {
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].role === 'assistant' && sayable(messages[i])) {
      return textOf(messages[i]).trim();
    }
  }
  return '';
}

/** At least one assistant answer exists, so a title can describe the exchange. */
export function hasAnswer(messages: ChatMessage[]): boolean {
  return firstUserText(messages).length > 0 &&
    firstAssistantText(messages).length > 0;
}

function excerpt(value: string, limit: number): string {
  const trimmed: string = value.trim();
  return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit) + '…';
}

/**
 * Small transcript for the title request: the first user/assistant exchange,
 * plus the current tail once the conversation has moved past the opening.
 * Tool calls, reasoning and images are omitted; the title only needs intent.
 */
export function titleTranscript(messages: ChatMessage[]): string {
  const firstUser: string = firstUserText(messages);
  const firstAssistant: string = firstAssistantText(messages);
  if (firstUser.length === 0) {
    return '';
  }
  let text: string = '用户：' + excerpt(firstUser, FIRST_TURN_LIMIT) + '\n';
  if (firstAssistant.length > 0) {
    text += '助手：' + excerpt(firstAssistant, FIRST_TURN_LIMIT) + '\n';
  }
  if (messages.length > LONG_CONVERSATION) {
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === 'assistant' && sayable(messages[i])) {
        text += '最近助手：' + excerpt(textOf(messages[i]), TAIL_TURN_LIMIT) + '\n';
        break;
      }
    }
  }
  return text.trim();
}
