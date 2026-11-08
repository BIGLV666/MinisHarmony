import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SecureStore } from './SecureStore';
import {
  AppSettings,
  ChatMessage,
  MessagePart,
  PART_FILE,
  PART_IMAGE,
  PART_REASONING,
  PART_TEXT,
  PART_TOOL_CALL,
  SandboxMode,
  StoredSession,
  TOOL_ERROR,
  TOOL_PENDING,
  TOOL_RUNNING,
  clampContextBudget,
  clampMaxTurns,
  cloneSettings,
  defaultSettings,
  normalizeThinkingLevel,
  normalizeToolNames,
  reasoningPart,
  textPart
} from '../core/Types';

const STORE_NAME: string = 'minis_harmony_store_v1';
const KEY_SETTINGS: string = 'settings';
const KEY_SESSIONS: string = 'sessions';

interface LegacyMessage {
  content?: string;
  reasoning?: string;
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
  let sandboxMode: SandboxMode = 'local';
  if (source.sandboxMode === 'remote') {
    sandboxMode = 'remote';
  }
  return {
    preset: preset,
    baseUrl: baseUrl,
    apiKey: source.apiKey !== undefined ? source.apiKey : '',
    modelId: modelId,
    systemPrompt: source.systemPrompt !== undefined ? source.systemPrompt : '',
    temperature: temperature,
    maxTokens: maxTokens,
    toolsEnabled: source.toolsEnabled !== false,
    allowWriteTools: source.allowWriteTools === true,
    imageToolsEnabled: source.imageToolsEnabled === true,
    confirmWriteTools: source.confirmWriteTools === true,
    sandboxMode: sandboxMode,
    sandboxUrl: source.sandboxUrl !== undefined ? source.sandboxUrl : '',
    sandboxToken: source.sandboxToken !== undefined ? source.sandboxToken : '',
    maxAgentTurns: clampMaxTurns(source.maxAgentTurns),
    contextBudgetChars: clampContextBudget(source.contextBudgetChars),
    loggingEnabled: source.loggingEnabled === true,
    memoryEnabled: source.memoryEnabled === true,
    backgroundEnabled: source.backgroundEnabled !== false,
    thinkingLevel: normalizeThinkingLevel(source.thinkingLevel),
    enterToSend: source.enterToSend === true,
    disabledTools: normalizeToolNames(source.disabledTools),
    onboardingDone: source.onboardingDone === true,
    appLockEnabled: source.appLockEnabled === true
  };
}

function normalizePart(source: MessagePart): MessagePart | null {
  if (source === null || source === undefined) {
    return null;
  }
  const raw: RawPart = source as RawPart;
  let kind: string = raw.kind !== undefined ? raw.kind : PART_TEXT;
  if (kind !== PART_TEXT && kind !== PART_REASONING && kind !== PART_TOOL_CALL &&
    kind !== PART_IMAGE && kind !== PART_FILE) {
    kind = PART_TEXT;
  }
  const part: MessagePart = {
    kind: kind,
    text: raw.text !== undefined ? raw.text : '',
    toolCallId: raw.toolCallId !== undefined ? raw.toolCallId : '',
    toolName: raw.toolName !== undefined ? raw.toolName : '',
    argumentsText: raw.argumentsText !== undefined ? raw.argumentsText : '',
    resultText: raw.resultText !== undefined ? raw.resultText : '',
    status: raw.status !== undefined ? raw.status : '',
    isError: raw.isError === true,
    mimeType: raw.mimeType !== undefined ? raw.mimeType : '',
    uri: raw.uri !== undefined ? raw.uri : ''
  };
  if (part.kind === PART_TOOL_CALL &&
    (part.status === TOOL_PENDING || part.status === TOOL_RUNNING)) {
    part.status = TOOL_ERROR;
    part.isError = true;
    if (part.resultText.length === 0) {
      part.resultText = '上次运行中断，工具未完成。';
    }
  }
  return part;
}

function normalizeMessage(source: ChatMessage): ChatMessage | null {
  if (source === null || source === undefined) {
    return null;
  }
  const role: string = source.role;
  if (role !== 'user' && role !== 'assistant' && role !== 'system') {
    return null;
  }
  const legacy: LegacyMessage = source as LegacyMessage;
  const parts: MessagePart[] = [];
  if (source.parts !== undefined && Array.isArray(source.parts)) {
    for (let i = 0; i < source.parts.length; i++) {
      const part: MessagePart | null = normalizePart(source.parts[i]);
      if (part !== null) {
        parts.push(part);
      }
    }
  }
  // Migration from the pre-parts schema.
  if (parts.length === 0) {
    if (legacy.reasoning !== undefined && legacy.reasoning.length > 0) {
      parts.push(reasoningPart(legacy.reasoning));
    }
    if (legacy.content !== undefined && legacy.content.length > 0) {
      parts.push(textPart(legacy.content));
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
    error: source.error !== undefined ? source.error : false,
    promptTokens: source.promptTokens !== undefined ? source.promptTokens : 0,
    completionTokens: source.completionTokens !== undefined ? source.completionTokens : 0,
    totalTokens: source.totalTokens !== undefined ? source.totalTokens : 0
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
      messageCount: messages.length,
      pinned: source.meta.pinned === true,
      archived: source.meta.archived === true,
      modelOverride: source.meta.modelOverride !== undefined ? source.meta.modelOverride : '',
      thinkingOverride: source.meta.thinkingOverride !== undefined ? source.meta.thinkingOverride : '',
      promptOverride: source.meta.promptOverride !== undefined ? source.meta.promptOverride : ''
    },
    messages: messages
  };
}

/**
 * Local persistence. Preferences is sufficient for the transcript and tool
 * metadata this build stores; it is not a secret vault. The API key and remote sandbox
 * token are kept there for convenience and can move to the Asset Store Kit in
 * a later iteration.
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
      const settings: AppSettings = normalizeSettings(parsed);
      return await LocalStore.hydrateSecrets(settings);
    } catch (e) {
      return defaultSettings();
    }
  }

  /**
   * Move legacy plaintext secrets from preferences into the Asset Store, and
   * preload the current values. `null` from SecureStore means the kit is not
   * usable here, in which case the preferences value is kept as a fallback.
   */
  private static async hydrateSecrets(settings: AppSettings): Promise<AppSettings> {
    let migrated: boolean = false;

    const secureKey: string | null = await SecureStore.get(SecureStore.apiKeyAlias());
    if (secureKey !== null) {
      if (secureKey.length > 0) {
        settings.apiKey = secureKey;
      } else if (settings.apiKey.length > 0) {
        if (await SecureStore.set(SecureStore.apiKeyAlias(), settings.apiKey)) {
          migrated = true;
        }
      }
    }

    const secureToken: string | null =
      await SecureStore.get(SecureStore.sandboxTokenAlias());
    if (secureToken !== null) {
      if (secureToken.length > 0) {
        settings.sandboxToken = secureToken;
      } else if (settings.sandboxToken.length > 0) {
        if (await SecureStore.set(SecureStore.sandboxTokenAlias(), settings.sandboxToken)) {
          migrated = true;
        }
      }
    }

    if (migrated) {
      // Rewrites preferences without the plaintext copies.
      await LocalStore.saveSettings(settings);
    }
    return settings;
  }

  static async saveSettings(settings: AppSettings): Promise<void> {
    const prefs: preferences.Preferences | null = LocalStore.prefs;
    if (prefs === null) {
      return;
    }
    const stored: AppSettings = cloneSettings(settings);

    // Only strip a secret from preferences once the Asset Store accepted it.
    // On devices where the kit is unavailable the old behaviour is retained.
    if (await SecureStore.set(SecureStore.apiKeyAlias(), settings.apiKey)) {
      stored.apiKey = '';
    }
    if (await SecureStore.set(SecureStore.sandboxTokenAlias(), settings.sandboxToken)) {
      stored.sandboxToken = '';
    }

    await prefs.put(KEY_SETTINGS, JSON.stringify(stored));
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
