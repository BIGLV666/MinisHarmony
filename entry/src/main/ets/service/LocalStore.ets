import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, ChatMessage, StoredSession, defaultSettings } from '../core/Types';

const STORE_NAME: string = 'minis_harmony_store_v1';
const KEY_SETTINGS: string = 'settings';
const KEY_SESSIONS: string = 'sessions';

function normalizeSettings(source: AppSettings): AppSettings {
  const fallback: AppSettings = defaultSettings();
  let preset: 'opencode' | 'custom' = 'opencode';
  if (source.preset === 'custom') {
    preset = 'custom';
  }
  const baseUrl: string = source.baseUrl !== undefined && source.baseUrl.length > 0
    ? source.baseUrl
    : fallback.baseUrl;
  const modelId: string = source.modelId !== undefined && source.modelId.length > 0
    ? source.modelId
    : fallback.modelId;
  const temperature: number = source.temperature !== undefined &&
    source.temperature >= 0 && source.temperature <= 2
    ? source.temperature
    : fallback.temperature;
  const maxTokens: number = source.maxTokens !== undefined && source.maxTokens > 0
    ? Math.floor(source.maxTokens)
    : fallback.maxTokens;
  return {
    preset: preset,
    baseUrl: baseUrl,
    apiKey: source.apiKey !== undefined ? source.apiKey : '',
    modelId: modelId,
    systemPrompt: source.systemPrompt !== undefined ? source.systemPrompt : '',
    temperature: temperature,
    maxTokens: maxTokens
  };
}

function normalizeMessage(source: ChatMessage): ChatMessage | null {
  if (source === null || source === undefined) {
    return null;
  }
  const role: string = source.role;
  if (role !== 'user' && role !== 'assistant') {
    return null;
  }
  return {
    id: source.id !== undefined ? source.id : '',
    role: role,
    content: source.content !== undefined ? source.content : '',
    reasoning: source.reasoning !== undefined ? source.reasoning : '',
    createdAt: source.createdAt !== undefined ? source.createdAt : 0,
    streaming: false,
    error: source.error !== undefined ? source.error : false
  };
}

function normalizeSession(source: StoredSession): StoredSession | null {
  if (source === null || source === undefined || source.meta === undefined) {
    return null;
  }
  const id: string = source.meta.id;
  if (id === undefined || id.length === 0) {
    return null;
  }
  const messages: ChatMessage[] = [];
  if (source.messages !== undefined) {
    for (let i = 0; i < source.messages.length; i++) {
      const message: ChatMessage | null = normalizeMessage(source.messages[i]);
      if (message !== null) {
        messages.push(message);
      }
    }
  }
  return {
    meta: {
      id: id,
      title: source.meta.title !== undefined && source.meta.title.length > 0
        ? source.meta.title
        : '新对话',
      updatedAt: source.meta.updatedAt !== undefined ? source.meta.updatedAt : 0,
      modelId: source.meta.modelId !== undefined ? source.meta.modelId : '',
      messageCount: messages.length
    },
    messages: messages
  };
}

/**
 * Local persistence. Preferences is sufficient for the text-only data this
 * build stores; it is not a secret vault. The API key is kept there for
 * convenience (same trade-off as most desktop chat clients) and can be moved
 * to the Asset Store Kit in a later iteration.
 */
export class LocalStore {
  private static prefs: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (LocalStore.prefs === null) {
      LocalStore.prefs = await preferences.getPreferences(context, STORE_NAME);
    }
  }

  static async loadSettings(): Promise<AppSettings> {
    const prefs: preferences.Preferences | null = LocalStore.prefs;
    if (prefs === null) {
      return defaultSettings();
    }
    try {
      const raw: string = await prefs.get(KEY_SETTINGS, '') as string;
      if (raw.length === 0) {
        return defaultSettings();
      }
      const parsed: AppSettings = JSON.parse(raw) as AppSettings;
      return normalizeSettings(parsed);
    } catch (e) {
      return defaultSettings();
    }
  }

  static async saveSettings(settings: AppSettings): Promise<void> {
    const prefs: preferences.Preferences | null = LocalStore.prefs;
    if (prefs === null) {
      return;
    }
    await prefs.put(KEY_SETTINGS, JSON.stringify(settings));
    await prefs.flush();
  }

  static async loadSessions(): Promise<StoredSession[]> {
    const prefs: preferences.Preferences | null = LocalStore.prefs;
    if (prefs === null) {
      return [];
    }
    try {
      const raw: string = await prefs.get(KEY_SESSIONS, '') as string;
      if (raw.length === 0) {
        return [];
      }
      const parsed: StoredSession[] = JSON.parse(raw) as StoredSession[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const sessions: StoredSession[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const session: StoredSession | null = normalizeSession(parsed[i]);
        if (session !== null) {
          sessions.push(session);
        }
      }
      sessions.sort((a: StoredSession, b: StoredSession): number => b.meta.updatedAt - a.meta.updatedAt);
      return sessions;
    } catch (e) {
      return [];
    }
  }

  static async saveSessions(sessions: StoredSession[]): Promise<void> {
    const prefs: preferences.Preferences | null = LocalStore.prefs;
    if (prefs === null) {
      return;
    }
    await prefs.put(KEY_SESSIONS, JSON.stringify(sessions));
    await prefs.flush();
  }
}
