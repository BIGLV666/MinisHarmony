/**
 * Shared data types and defaults.
 *
 * Kept free of HarmonyOS imports so the pure parts can be exercised by the
 * Node test harness in scripts/test-core.mjs.
 *
 * Messages are stored as an ordered list of parts instead of a single
 * `content` string. Text, reasoning, tool calls and their results therefore
 * survive persistence and can be rendered independently. Tool calls use the
 * OpenAI `tool_calls` shape when converted back into a request.
 */

export const OPENCODE_GO_BASE: string = 'https://opencode.ai/zen/go/v1';
export const OPENCODE_DEFAULT_MODEL: string = 'kimi-k3';
export const APP_VERSION: string = '1.0.0';

export const PART_TEXT: string = 'text';
export const PART_REASONING: string = 'reasoning';
export const PART_TOOL_CALL: string = 'tool_call';
export const PART_IMAGE: string = 'image';
export const PART_FILE: string = 'file';

export const TOOL_PENDING: string = 'pending';
export const TOOL_RUNNING: string = 'running';
export const TOOL_DONE: string = 'done';
export const TOOL_ERROR: string = 'error';

export type ProviderPreset = 'opencode' | 'custom';
export type SandboxMode = 'local' | 'remote';
/** Request-level reasoning effort; `off` omits the field entirely. */
export type ThinkingLevel = 'off' | 'low' | 'medium' | 'high';

export function normalizeThinkingLevel(value: string | undefined): ThinkingLevel {
  if (value === 'low' || value === 'medium' || value === 'high') {
    return value;
  }
  return 'off';
}

/** `/thinking` cycles off → low → medium → high → off. */
export function cycleThinkingLevel(value: ThinkingLevel): ThinkingLevel {
  if (value === 'off') {
    return 'low';
  }
  if (value === 'low') {
    return 'medium';
  }
  if (value === 'medium') {
    return 'high';
  }
  return 'off';
}

export interface AppSettings {
  preset: ProviderPreset;
  baseUrl: string;
  apiKey: string;
  modelId: string;
  systemPrompt: string;
  temperature: number;
  maxTokens: number;
  /** Let the model call tools at all. */
  toolsEnabled: boolean;
  /** Local file writes need an explicit opt-in. */
  allowWriteTools: boolean;
  /** Expose read_image; only enable when the selected model accepts images. */
  imageToolsEnabled: boolean;
  /** Ask the user before every write_file / file_edit call. */
  confirmWriteTools: boolean;
  /** Where tool calls execute: in the app sandbox or a remote helper. */
  sandboxMode: SandboxMode;
  sandboxUrl: string;
  sandboxToken: string;
  /** Upper bound for model/tool round trips in one user turn. */
  maxAgentTurns: number;
  /** Character budget before old tool results are trimmed from requests. */
  contextBudgetChars: number;
  /** Write structured, redacted event logs to the app sandbox. */
  loggingEnabled: boolean;
  /** Enable the persistent memory files and memory tools. */
  memoryEnabled: boolean;
  /** Keep a running reply alive when the app moves to the background. */
  backgroundEnabled: boolean;
  /** Sent as `reasoning_effort` when not `off`. */
  thinkingLevel: ThinkingLevel;
  /** Physical/soft Enter sends instead of inserting a newline. */
  enterToSend: boolean;
  /** Tool names switched off individually; empty means every available tool. */
  disabledTools: string[];
  /** First-run guide finished or skipped; never show it again when true. */
  onboardingDone: boolean;
  /** Ask for the system credential before showing the app at launch. */
  appLockEnabled: boolean;
  /** Accent colour as `#RRGGBB`; applied to buttons, links and bubbles. */
  accentColor: string;
  /** Reading scale for chat text, 0.9–1.3. */
  fontScale: number;
  /** Built-in persona prepended to the system prompt. */
  soulId: string;
  /** Skill ids (imported SKILL.md files) injected into the system prompt. */
  enabledSkills: string[];
}

export const DEFAULT_ACCENT_COLOR: string = '#2F6BFF';
export const MIN_FONT_SCALE: number = 0.9;
export const MAX_FONT_SCALE: number = 1.3;

export function normalizeAccentColor(value: string | undefined): string {
  if (value === undefined || value.length !== 7 || value.charAt(0) !== '#') {
    return DEFAULT_ACCENT_COLOR;
  }
  const digits: string = '0123456789abcdefABCDEF';
  for (let i = 1; i < 7; i++) {
    if (digits.indexOf(value.charAt(i)) < 0) {
      return DEFAULT_ACCENT_COLOR;
    }
  }
  return value;
}

export function clampFontScale(value: number): number {
  if (Number.isNaN(value) || !Number.isFinite(value)) {
    return 1;
  }
  if (value < MIN_FONT_SCALE) {
    return MIN_FONT_SCALE;
  }
  if (value > MAX_FONT_SCALE) {
    return MAX_FONT_SCALE;
  }
  return Math.round(value * 100) / 100;
}

export function scaleFont(size: number, scale: number): number {
  return Math.round(size * clampFontScale(scale));
}

export const DEFAULT_MAX_AGENT_TURNS: number = 200;
export const MIN_MAX_AGENT_TURNS: number = 1;
export const MAX_MAX_AGENT_TURNS: number = 1000;

export const DEFAULT_CONTEXT_BUDGET_CHARS: number = 60000;
export const MIN_CONTEXT_BUDGET_CHARS: number = 4000;
export const MAX_CONTEXT_BUDGET_CHARS: number = 400000;

/** Clamp the request budget; invalid input falls back to the default. */
export function clampContextBudget(value: number): number {
  if (Number.isNaN(value) || !Number.isFinite(value)) {
    return DEFAULT_CONTEXT_BUDGET_CHARS;
  }
  const rounded: number = Math.floor(value);
  if (rounded < MIN_CONTEXT_BUDGET_CHARS) {
    return MIN_CONTEXT_BUDGET_CHARS;
  }
  if (rounded > MAX_CONTEXT_BUDGET_CHARS) {
    return MAX_CONTEXT_BUDGET_CHARS;
  }
  return rounded;
}

/** Clamp a user-entered turn budget; non-finite values fall back to the default. */
export function clampMaxTurns(value: number): number {
  if (Number.isNaN(value) || !Number.isFinite(value)) {
    return DEFAULT_MAX_AGENT_TURNS;
  }
  const rounded: number = Math.floor(value);
  if (rounded < MIN_MAX_AGENT_TURNS) {
    return MIN_MAX_AGENT_TURNS;
  }
  if (rounded > MAX_MAX_AGENT_TURNS) {
    return MAX_MAX_AGENT_TURNS;
  }
  return rounded;
}

export interface MessagePart {
  kind: string;
  text: string;
  toolCallId: string;
  toolName: string;
  argumentsText: string;
  resultText: string;
  status: string;
  isError: boolean;
  mimeType: string;
  uri: string;
}

export interface ChatMessage {
  id: string;
  role: string;
  parts: MessagePart[];
  createdAt: number;
  streaming: boolean;
  error: boolean;
  /** Provider-reported usage for this assistant turn; zero when unknown. */
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
}

export interface SessionMeta {
  id: string;
  title: string;
  updatedAt: number;
  modelId: string;
  messageCount: number;
  /** Pinned sessions sort above everything else in the sidebar. */
  pinned: boolean;
  /** Archived sessions are hidden unless the sidebar toggle is on. */
  archived: boolean;
  /** Per-session overrides; empty strings mean "follow the global setting". */
  modelOverride?: string;
  thinkingOverride?: string;
  promptOverride?: string;
}

export interface StoredSession {
  meta: SessionMeta;
  messages: ChatMessage[];
}

/** Pinned conversations first, then most recently updated. */
export function sortSessionMetas(metas: SessionMeta[]): SessionMeta[] {
  metas.sort((a: SessionMeta, b: SessionMeta): number => {
    if (a.pinned !== b.pinned) {
      return a.pinned ? -1 : 1;
    }
    return b.updatedAt - a.updatedAt;
  });
  return metas;
}

export interface SessionGroup {
  label: string;
  sessions: SessionMeta[];
}

const DAY_MS: number = 24 * 60 * 60 * 1000;

function startOfLocalDay(ts: number): number {
  const date: Date = new Date(ts);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

/**
 * Split the already-sorted sidebar list into pinned + relative-day groups.
 * Input order is preserved inside each bucket, so callers keep updatedAt
 * ordering without re-sorting.
 */
export function groupSessionMetas(metas: SessionMeta[], now: number): SessionGroup[] {
  const pinned: SessionMeta[] = [];
  const today: SessionMeta[] = [];
  const yesterday: SessionMeta[] = [];
  const week: SessionMeta[] = [];
  const older: SessionMeta[] = [];
  const todayStart: number = startOfLocalDay(now);
  for (let i = 0; i < metas.length; i++) {
    const item: SessionMeta = metas[i];
    if (item.pinned) {
      pinned.push(item);
      continue;
    }
    const days: number = Math.round(
      (todayStart - startOfLocalDay(item.updatedAt)) / DAY_MS
    );
    if (days <= 0) {
      today.push(item);
    } else if (days === 1) {
      yesterday.push(item);
    } else if (days < 7) {
      week.push(item);
    } else {
      older.push(item);
    }
  }
  const groups: SessionGroup[] = [];
  if (pinned.length > 0) {
    groups.push({ label: '置顶', sessions: pinned });
  }
  if (today.length > 0) {
    groups.push({ label: '今天', sessions: today });
  }
  if (yesterday.length > 0) {
    groups.push({ label: '昨天', sessions: yesterday });
  }
  if (week.length > 0) {
    groups.push({ label: '最近 7 天', sessions: week });
  }
  if (older.length > 0) {
    groups.push({ label: '更早', sessions: older });
  }
  return groups;
}

/**
 * Keep the transcript through `messageId` and drop everything after it.
 * Returns null when the id is missing or is already the last message, so the
 * caller can leave the session untouched.
 */
export function rewindMessages(messages: ChatMessage[], messageId: string): ChatMessage[] | null {
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].id === messageId) {
      if (i >= messages.length - 1) {
        return null;
      }
      return messages.slice(0, i + 1);
    }
  }
  return null;
}

/** Pre-computed lowercase blob used by sidebar full-text search. */
export interface SessionSearchEntry {
  id: string;
  text: string;
}

export const SEARCH_BLOB_LIMIT: number = 6000;

/**
 * Flatten a session into one searchable string. Tool arguments and results
 * are included so "which conversation read config.json" is answerable, while
 * reasoning is skipped to keep the blob small.
 */
export function searchableText(session: StoredSession): string {
  let value: string = session.meta.title + '\n' + session.meta.modelId + '\n';
  for (let i = 0; i < session.messages.length; i++) {
    if (value.length >= SEARCH_BLOB_LIMIT) {
      break;
    }
    const message: ChatMessage = session.messages[i];
    for (let j = 0; j < message.parts.length; j++) {
      const part: MessagePart = message.parts[j];
      if (part.kind === PART_TEXT) {
        value += part.text + '\n';
      } else if (part.kind === PART_TOOL_CALL) {
        value += part.toolName + ' ' + part.argumentsText + ' ' +
          part.resultText + '\n';
      }
      if (value.length >= SEARCH_BLOB_LIMIT) {
        break;
      }
    }
  }
  return value.substring(0, SEARCH_BLOB_LIMIT).toLowerCase();
}

export interface ModelInfo {
  id: string;
  name: string;
  note: string;
}

/**
 * Model ids exposed by OpenCode Go as of 2026-11. The list is only a picker
 * convenience: Settings also accepts any custom model id, and the "fetch
 * models" action asks the service for the live list.
 */
export const BUILTIN_MODELS: ModelInfo[] = [
  { id: 'kimi-k3', name: 'Kimi K3', note: '通用 / 长上下文' },
  { id: 'kimi-k3.1-pro', name: 'Kimi K3.1 Pro', note: '通用' },
  { id: 'kimi-k2.7-code', name: 'Kimi K2.7 Code', note: '代码' },
  { id: 'gpt-6-luna', name: 'GPT 6 Luna', note: '通用' },
  { id: 'gpt-5.6-luna', name: 'GPT 5.6 Luna', note: '通用' },
  { id: 'claude-haiku-5-5', name: 'Claude Haiku 5.5', note: '快速' },
  { id: 'gemini-4-argon', name: 'Gemini 4 Argon', note: '多模态' },
  { id: 'grok-4.7', name: 'Grok 4.7', note: '通用' },
  { id: 'glm-5.3', name: 'GLM-5.3', note: '通用' },
  { id: 'glm-5.3-flash', name: 'GLM-5.3-Flash', note: '快速' },
  { id: 'glm-5.2', name: 'GLM-5.2', note: '通用' },
  { id: 'deepseek-v4.1-flash', name: 'DeepSeek V4.1 Flash', note: '快速' },
  { id: 'deepseek-v4-pro', name: 'DeepSeek V4 Pro', note: '通用' },
  { id: 'qwen3.8-max', name: 'Qwen3.8 Max', note: '通用' },
  { id: 'qwen3.8-flash', name: 'Qwen3.8 Flash', note: '快速' },
  { id: 'qwen3.7-plus', name: 'Qwen3.7 Plus', note: '通用' },
  { id: 'minimax-m3', name: 'MiniMax-M3', note: '通用' },
  { id: 'minimax-m3.1-flash', name: 'MiniMax M3.1 Flash', note: '快速' },
  { id: 'mimo-v2.6-pro', name: 'MiMo-V2.6-Pro', note: '通用' },
  { id: 'mimo-v2.6-flash', name: 'MiMo-V2.6-Flash', note: '快速' },
  { id: 'mimo-v2.5-pro', name: 'MiMo-V2.5-Pro', note: '通用' },
  { id: 'mimo-v2.5', name: 'MiMo-V2.5', note: '通用' },
  { id: 'longcat-2.0', name: 'LongCat-2.0', note: '通用' },
  { id: 'hy4', name: 'Hy4', note: '通用' },
  { id: 'hy4-preview', name: 'Hy4 preview', note: '预览' },
  { id: 'hy3', name: 'Hy3', note: '通用' },
  { id: 'step-5-preview', name: 'Step 5 Preview', note: '预览' },
  { id: 'muse-spark-1.3-contributor', name: 'Muse Spark 1.3 Contributor', note: '受限区域' },
  { id: 'muse-spark-1.2-contributor', name: 'Muse Spark 1.2 Contributor', note: '受限区域' }
];

export function defaultSettings(): AppSettings {
  return {
    preset: 'opencode',
    baseUrl: OPENCODE_GO_BASE,
    apiKey: '',
    modelId: OPENCODE_DEFAULT_MODEL,
    systemPrompt: '',
    temperature: 1.0,
    maxTokens: 8192,
    toolsEnabled: true,
    allowWriteTools: false,
    imageToolsEnabled: false,
    confirmWriteTools: false,
    sandboxMode: 'local',
    sandboxUrl: '',
    sandboxToken: '',
    maxAgentTurns: DEFAULT_MAX_AGENT_TURNS,
    contextBudgetChars: DEFAULT_CONTEXT_BUDGET_CHARS,
    loggingEnabled: false,
    memoryEnabled: false,
    backgroundEnabled: true,
    thinkingLevel: 'off',
    enterToSend: false,
    disabledTools: [],
    onboardingDone: false,
    appLockEnabled: false,
    accentColor: DEFAULT_ACCENT_COLOR,
    fontScale: 1,
    soulId: 'general',
    enabledSkills: []
  };
}

/** Keep only non-empty unique names; anything else in stored JSON is ignored. */
export function normalizeToolNames(value: string[] | undefined): string[] {
  const names: string[] = [];
  if (value === undefined || !Array.isArray(value)) {
    return names;
  }
  for (let i = 0; i < value.length; i++) {
    const name: string = value[i];
    if (typeof name !== 'string' || name.length === 0) {
      continue;
    }
    if (names.indexOf(name) < 0) {
      names.push(name);
    }
  }
  return names;
}

export function cloneSettings(source: AppSettings): AppSettings {
  return {
    preset: source.preset,
    baseUrl: source.baseUrl,
    apiKey: source.apiKey,
    modelId: source.modelId,
    systemPrompt: source.systemPrompt,
    temperature: source.temperature,
    maxTokens: source.maxTokens,
    toolsEnabled: source.toolsEnabled,
    allowWriteTools: source.allowWriteTools,
    imageToolsEnabled: source.imageToolsEnabled === true,
    confirmWriteTools: source.confirmWriteTools === true,
    sandboxMode: source.sandboxMode,
    sandboxUrl: source.sandboxUrl,
    sandboxToken: source.sandboxToken,
    maxAgentTurns: clampMaxTurns(source.maxAgentTurns),
    contextBudgetChars: clampContextBudget(source.contextBudgetChars),
    loggingEnabled: source.loggingEnabled === true,
    memoryEnabled: source.memoryEnabled === true,
    backgroundEnabled: source.backgroundEnabled !== false,
    thinkingLevel: normalizeThinkingLevel(source.thinkingLevel),
    enterToSend: source.enterToSend === true,
    disabledTools: normalizeToolNames(source.disabledTools),
    onboardingDone: source.onboardingDone === true,
    appLockEnabled: source.appLockEnabled === true,
    accentColor: normalizeAccentColor(source.accentColor),
    fontScale: clampFontScale(source.fontScale),
    soulId: source.soulId !== undefined && source.soulId.length > 0
      ? source.soulId
      : 'general',
    enabledSkills: normalizeToolNames(source.enabledSkills)
  };
}

export function modelName(modelId: string): string {
  for (let i = 0; i < BUILTIN_MODELS.length; i++) {
    if (BUILTIN_MODELS[i].id === modelId) {
      return BUILTIN_MODELS[i].name;
    }
  }
  return modelId;
}

/** A fully initialised part. Keeping every field present makes JSON stable. */
export function makePart(kind: string): MessagePart {
  return {
    kind: kind,
    text: '',
    toolCallId: '',
    toolName: '',
    argumentsText: '',
    resultText: '',
    status: '',
    isError: false,
    mimeType: '',
    uri: ''
  };
}

export function textPart(text: string): MessagePart {
  const part: MessagePart = makePart(PART_TEXT);
  part.text = text;
  return part;
}

export function reasoningPart(text: string): MessagePart {
  const part: MessagePart = makePart(PART_REASONING);
  part.text = text;
  return part;
}

export function toolCallPart(id: string, name: string, argumentsText: string): MessagePart {
  const part: MessagePart = makePart(PART_TOOL_CALL);
  part.toolCallId = id;
  part.toolName = name;
  part.argumentsText = argumentsText;
  part.status = TOOL_PENDING;
  return part;
}

export function newChatMessage(id: string, role: string, content: string): ChatMessage {
  const parts: MessagePart[] = [];
  if (content.length > 0) {
    parts.push(textPart(content));
  }
  return {
    id: id,
    role: role,
    parts: parts,
    createdAt: Date.now(),
    streaming: false,
    error: false,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0
  };
}

/** Concatenated text parts, in order. */
export function textOf(message: ChatMessage): string {
  let value: string = '';
  for (let i = 0; i < message.parts.length; i++) {
    if (message.parts[i].kind === PART_TEXT) {
      value += message.parts[i].text;
    }
  }
  return value;
}

/** Concatenated reasoning parts, in order. */
export function reasoningOf(message: ChatMessage): string {
  let value: string = '';
  for (let i = 0; i < message.parts.length; i++) {
    if (message.parts[i].kind === PART_REASONING) {
      value += message.parts[i].text;
    }
  }
  return value;
}

export function toolCallsOf(message: ChatMessage): MessagePart[] {
  const calls: MessagePart[] = [];
  for (let i = 0; i < message.parts.length; i++) {
    if (message.parts[i].kind === PART_TOOL_CALL) {
      calls.push(message.parts[i]);
    }
  }
  return calls;
}

/**
 * Append streamed text. Only a trailing text part is extended, so the parts
 * list preserves the order in which the model emitted reasoning, content and
 * tool calls. A new part starts after reasoning or a tool call.
 */
export function appendText(message: ChatMessage, text: string): void {
  if (text.length === 0) {
    return;
  }
  const last: MessagePart | null = message.parts.length > 0
    ? message.parts[message.parts.length - 1]
    : null;
  if (last !== null && last.kind === PART_TEXT) {
    last.text += text;
    return;
  }
  message.parts.push(textPart(text));
}

export function appendReasoning(message: ChatMessage, text: string): void {
  if (text.length === 0) {
    return;
  }
  const last: MessagePart | null = message.parts.length > 0
    ? message.parts[message.parts.length - 1]
    : null;
  if (last !== null && last.kind === PART_REASONING) {
    last.text += text;
    return;
  }
  message.parts.push(reasoningPart(text));
}

/**
 * Stable-ish key for ForEach. ArkUI does not deeply observe nested part
 * mutation, so the key must change whenever streamed content or tool state
 * changes.
 */
export function messageKey(message: ChatMessage): string {
  let key: string = message.id + ':' + (message.streaming ? '1' : '0') +
    ':' + (message.error ? '1' : '0') + ':' + message.totalTokens.toString();
  for (let i = 0; i < message.parts.length; i++) {
    const part: MessagePart = message.parts[i];
    key += ':' + part.kind + ':' + part.text.length + ':' + part.status +
      ':' + part.resultText.length + ':' + (part.isError ? '1' : '0');
  }
  return key;
}
