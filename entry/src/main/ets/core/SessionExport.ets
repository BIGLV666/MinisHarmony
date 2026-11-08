/**
 * Session JSON export.
 *
 * The envelope is intentionally small and versioned so a later restore
 * feature can accept files written today. The payload is the same
 * `StoredSession` shape used by `LocalStore`, including every part and its
 * tool metadata; nothing is filtered out except in-memory streaming flags,
 * which are meaningless after the run ended.
 */

import { ChatMessage, MessagePart, StoredSession } from './Types';
import {
  PART_FILE,
  PART_IMAGE,
  PART_REASONING,
  PART_TEXT,
  PART_TOOL_CALL,
  TOOL_DONE,
  TOOL_ERROR,
  TOOL_PENDING,
  TOOL_RUNNING,
  makePart
} from './Types';
import { exportStamp, safeFileBase } from './MarkdownExport';

export const SESSION_EXPORT_APP: string = 'MinisHarmony';
export const SESSION_EXPORT_VERSION: number = 1;

export interface SessionExportEnvelope {
  app: string;
  version: number;
  /** ISO-8601 UTC timestamp. */
  exportedAt: string;
  /** Local wall-clock date, for humans reading the file. */
  exportedOn: string;
  session: StoredSession;
}

function settledMessage(message: ChatMessage): ChatMessage {
  return {
    id: message.id,
    role: message.role,
    parts: message.parts,
    createdAt: message.createdAt,
    streaming: false,
    error: message.error,
    promptTokens: message.promptTokens,
    completionTokens: message.completionTokens,
    totalTokens: message.totalTokens
  };
}

function settledMessages(session: StoredSession): ChatMessage[] {
  const messages: ChatMessage[] = [];
  for (let i = 0; i < session.messages.length; i++) {
    messages.push(settledMessage(session.messages[i]));
  }
  return messages;
}

function settledSession(session: StoredSession, messages: ChatMessage[]): StoredSession {
  return {
    meta: {
      id: session.meta.id,
      title: session.meta.title,
      updatedAt: session.meta.updatedAt,
      modelId: session.meta.modelId,
      messageCount: messages.length,
      pinned: session.meta.pinned,
      archived: session.meta.archived,
      modelOverride: session.meta.modelOverride,
      thinkingOverride: session.meta.thinkingOverride,
      promptOverride: session.meta.promptOverride
    },
    messages: messages
  };
}

/**
 * Serialise one session as pretty-printed JSON. `now` is injected so the
 * output is deterministic in tests.
 */
export function sessionExportJson(session: StoredSession, now: Date): string {
  const messages: ChatMessage[] = settledMessages(session);
  const envelope: SessionExportEnvelope = {
    app: SESSION_EXPORT_APP,
    version: SESSION_EXPORT_VERSION,
    exportedAt: now.toISOString(),
    exportedOn: exportStamp(now),
    session: settledSession(session, messages)
  };
  return JSON.stringify(envelope, null, 2);
}

export interface SessionBundleEnvelope {
  app: string;
  version: number;
  exportedAt: string;
  exportedOn: string;
  sessions: StoredSession[];
}

/** One file for a multi-session selection; the array replaces `session`. */
export function sessionBundleJson(sessions: StoredSession[], now: Date): string {
  const copies: StoredSession[] = [];
  for (let i = 0; i < sessions.length; i++) {
    const messages: ChatMessage[] = settledMessages(sessions[i]);
    copies.push(settledSession(sessions[i], messages));
  }
  const envelope: SessionBundleEnvelope = {
    app: SESSION_EXPORT_APP,
    version: SESSION_EXPORT_VERSION,
    exportedAt: now.toISOString(),
    exportedOn: exportStamp(now),
    sessions: copies
  };
  return JSON.stringify(envelope, null, 2);
}

export function sessionJsonFileName(title: string, now: Date): string {
  return safeFileBase(title) + '-' + exportStamp(now) + '.json';
}

export function sessionBundleFileName(now: Date): string {
  return 'minis-sessions-' + exportStamp(now) + '.json';
}

export interface SessionImportResult {
  ok: boolean;
  error: string;
  session: StoredSession | null;
}

interface RawPart {
  kind?: string;
  text?: string;
  toolCallId?: string;
  toolName?: string;
  argumentsText?: string;
  resultText?: string;
  status?: string;
  isError?: boolean;
  mimeType?: string;
  uri?: string;
}

interface RawMessage {
  id?: string;
  role?: string;
  parts?: RawPart[];
  createdAt?: number;
  error?: boolean;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
}

interface RawMeta {
  id?: string;
  title?: string;
  updatedAt?: number;
  modelId?: string;
  pinned?: boolean;
  archived?: boolean;
  modelOverride?: string;
  thinkingOverride?: string;
  promptOverride?: string;
}

interface RawSession {
  meta?: RawMeta;
  messages?: RawMessage[];
}

function importPart(source: RawPart): MessagePart | null {
  if (source === null || source === undefined) {
    return null;
  }
  let kind: string = source.kind !== undefined ? source.kind : PART_TEXT;
  if (kind !== PART_TEXT && kind !== PART_REASONING && kind !== PART_TOOL_CALL &&
    kind !== PART_IMAGE && kind !== PART_FILE) {
    kind = PART_TEXT;
  }
  const part: MessagePart = makePart(kind);
  part.text = source.text !== undefined ? source.text : '';
  part.toolCallId = source.toolCallId !== undefined ? source.toolCallId : '';
  part.toolName = source.toolName !== undefined ? source.toolName : '';
  part.argumentsText = source.argumentsText !== undefined ? source.argumentsText : '';
  part.resultText = source.resultText !== undefined ? source.resultText : '';
  part.status = source.status !== undefined ? source.status : '';
  part.isError = source.isError === true;
  part.mimeType = source.mimeType !== undefined ? source.mimeType : '';
  part.uri = source.uri !== undefined ? source.uri : '';
  if (kind === PART_TOOL_CALL &&
    (part.status === TOOL_PENDING || part.status === TOOL_RUNNING)) {
    part.status = TOOL_ERROR;
    part.isError = true;
    if (part.resultText.length === 0) {
      part.resultText = '导入的文件里该工具调用尚未完成。';
    }
  }
  if (kind === PART_TOOL_CALL && part.status.length === 0) {
    part.status = TOOL_DONE;
  }
  return part;
}

function importMessage(source: RawMessage): ChatMessage | null {
  if (source === null || source === undefined) {
    return null;
  }
  const role: string = source.role !== undefined ? source.role : '';
  if (role !== 'user' && role !== 'assistant' && role !== 'system') {
    return null;
  }
  const parts: MessagePart[] = [];
  if (source.parts !== undefined && Array.isArray(source.parts)) {
    for (let i = 0; i < source.parts.length; i++) {
      const part: MessagePart | null = importPart(source.parts[i]);
      if (part !== null) {
        parts.push(part);
      }
    }
  }
  if (parts.length === 0) {
    return null;
  }
  return {
    id: source.id !== undefined ? source.id : '',
    role: role,
    parts: parts,
    createdAt: source.createdAt !== undefined ? source.createdAt : 0,
    streaming: false,
    error: source.error === true,
    promptTokens: source.promptTokens !== undefined ? source.promptTokens : 0,
    completionTokens: source.completionTokens !== undefined ? source.completionTokens : 0,
    totalTokens: source.totalTokens !== undefined ? source.totalTokens : 0
  };
}

/**
 * Parse a file produced by `sessionExportJson`. The imported session always
 * gets a fresh id so it cannot overwrite an existing conversation, and its
 * `updatedAt` becomes "now" so it lands at the top of the sidebar. Unknown
 * parts are dropped rather than stored half-valid.
 */
export function parseSessionExport(
  text: string,
  newId: string,
  now: Date
): SessionImportResult {
  let root: SessionExportEnvelope;
  try {
    root = JSON.parse(text) as SessionExportEnvelope;
  } catch (e) {
    return { ok: false, error: '文件不是有效的 JSON', session: null };
  }
  if (root === null || root === undefined || root.app !== SESSION_EXPORT_APP) {
    return { ok: false, error: '不是 MinisHarmony 导出的会话', session: null };
  }
  if (root.version === undefined || root.version < 1 ||
    root.version > SESSION_EXPORT_VERSION) {
    return { ok: false, error: '不支持的导出版本：' + (root.version === undefined
      ? '未知' : root.version.toString()), session: null };
  }
  const raw: RawSession = root.session as RawSession;
  const result: RawImport = importRawSession(raw, newId, now);
  if (result.session === null) {
    return { ok: false, error: result.error, session: null };
  }
  return { ok: true, error: '', session: result.session };
}

interface RawImport {
  session: StoredSession | null;
  error: string;
}

function importRawSession(
  raw: RawSession,
  newId: string,
  now: Date,
  preserve: boolean = false
): RawImport {
  if (raw === null || raw === undefined || raw.meta === undefined ||
    !Array.isArray(raw.messages)) {
    return { session: null, error: '文件里没有会话数据' };
  }
  const messages: ChatMessage[] = [];
  for (let i = 0; i < raw.messages.length; i++) {
    const message: ChatMessage | null = importMessage(raw.messages[i]);
    if (message !== null) {
      messages.push(message);
    }
  }
  if (messages.length === 0) {
    return { session: null, error: '会话里没有可导入的消息' };
  }
  let title: string = raw.meta.title !== undefined && raw.meta.title.trim().length > 0
    ? raw.meta.title.trim()
    : '导入的对话';
  if (!preserve && !title.endsWith('（导入）')) {
    title = title + '（导入）';
  }
  const rawId: string = raw.meta.id !== undefined && raw.meta.id.length > 0
    ? raw.meta.id
    : '';
  const id: string = preserve && rawId.length > 0 ? rawId : newId;
  const updatedAt: number = preserve && raw.meta.updatedAt !== undefined &&
    raw.meta.updatedAt > 0
    ? raw.meta.updatedAt
    : now.getTime();
  return {
    session: {
      meta: {
        id: id,
        title: title,
        updatedAt: updatedAt,
        modelId: raw.meta.modelId !== undefined ? raw.meta.modelId : '',
        messageCount: messages.length,
        pinned: preserve ? raw.meta.pinned === true : false,
        archived: preserve ? raw.meta.archived === true : false,
        modelOverride: raw.meta.modelOverride !== undefined ? raw.meta.modelOverride : '',
        thinkingOverride: raw.meta.thinkingOverride !== undefined ? raw.meta.thinkingOverride : '',
        promptOverride: raw.meta.promptOverride !== undefined ? raw.meta.promptOverride : ''
      },
      messages: messages
    },
    error: ''
  };
}

export interface SessionBundleImportResult {
  ok: boolean;
  error: string;
  sessions: StoredSession[];
}

interface RawEnvelopeRoot {
  app?: string;
  version?: number;
  session?: RawSession;
  sessions?: RawSession[];
}

/**
 * Accepts either a single-session export or a bundle. Each imported session
 * gets an id from `newId()` so a bundle cannot collide with local ids; an
 * unreadable entry is skipped and only reported when nothing could be read.
 */
export function parseSessionsExport(
  text: string,
  newId: () => string,
  now: Date,
  preserveIds: boolean = false
): SessionBundleImportResult {
  let root: RawEnvelopeRoot;
  try {
    root = JSON.parse(text) as RawEnvelopeRoot;
  } catch (e) {
    return { ok: false, error: '文件不是有效的 JSON', sessions: [] };
  }
  if (root === null || root === undefined || root.app !== SESSION_EXPORT_APP) {
    return { ok: false, error: '不是 MinisHarmony 导出的会话', sessions: [] };
  }
  if (root.version === undefined || root.version < 1 ||
    root.version > SESSION_EXPORT_VERSION) {
    return {
      ok: false,
      error: '不支持的导出版本：' + (root.version === undefined
        ? '未知' : root.version.toString()),
      sessions: []
    };
  }
  const rawList: RawSession[] = [];
  if (Array.isArray(root.sessions)) {
    for (let i = 0; i < root.sessions.length; i++) {
      rawList.push(root.sessions[i]);
    }
  } else if (root.session !== undefined && root.session !== null) {
    rawList.push(root.session);
  }
  if (rawList.length === 0) {
    return { ok: false, error: '文件里没有会话数据', sessions: [] };
  }
  const imported: StoredSession[] = [];
  let firstError: string = '';
  for (let i = 0; i < rawList.length; i++) {
    const result: RawImport =
      importRawSession(rawList[i], newId(), now, preserveIds);
    if (result.session !== null) {
      imported.push(result.session);
    } else if (firstError.length === 0) {
      firstError = result.error;
    }
  }
  if (imported.length === 0) {
    return {
      ok: false,
      error: firstError.length > 0 ? firstError : '没有可导入的会话',
      sessions: []
    };
  }
  return { ok: true, error: '', sessions: imported };
}

/**
 * Restore/sync path: keeps the original session ids, timestamps, titles and
 * flags so a downloaded backup can be merged with the local library instead
 * of being imported as a duplicate copy.
 */
export function parseBackupSessions(
  text: string,
  now: Date
): SessionBundleImportResult {
  return parseSessionsExport(text, (): string => '', now, true);
}
