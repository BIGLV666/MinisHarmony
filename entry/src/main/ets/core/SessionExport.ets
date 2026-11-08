/**
 * Session JSON export.
 *
 * The envelope is intentionally small and versioned so a later restore
 * feature can accept files written today. The payload is the same
 * `StoredSession` shape used by `LocalStore`, including every part and its
 * tool metadata; nothing is filtered out except in-memory streaming flags,
 * which are meaningless after the run ended.
 */

import { ChatMessage, StoredSession } from './Types';
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

/**
 * Serialise one session as pretty-printed JSON. `now` is injected so the
 * output is deterministic in tests.
 */
export function sessionExportJson(session: StoredSession, now: Date): string {
  const messages: ChatMessage[] = [];
  for (let i = 0; i < session.messages.length; i++) {
    messages.push(settledMessage(session.messages[i]));
  }
  const envelope: SessionExportEnvelope = {
    app: SESSION_EXPORT_APP,
    version: SESSION_EXPORT_VERSION,
    exportedAt: now.toISOString(),
    exportedOn: exportStamp(now),
    session: {
      meta: {
        id: session.meta.id,
        title: session.meta.title,
        updatedAt: session.meta.updatedAt,
        modelId: session.meta.modelId,
        messageCount: messages.length,
        pinned: session.meta.pinned,
        archived: session.meta.archived
      },
      messages: messages
    }
  };
  return JSON.stringify(envelope, null, 2);
}

export function sessionJsonFileName(title: string, now: Date): string {
  return safeFileBase(title) + '-' + exportStamp(now) + '.json';
}
