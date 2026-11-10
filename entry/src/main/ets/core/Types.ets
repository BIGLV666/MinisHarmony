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

import { ModelOverride, normalizeModelOverrides } from './ModelOverride';
import { McpServerConfig, normalizeMcpServers } from './McpProtocol';
import { SubAgentDefinition, defaultAgents, normalizeAgents } from './SubAgentRoster';
import { t } from './I18n';

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

export type ProviderPreset =
  'opencode' | 'custom' | 'anthropic' | 'gemini' | 'copilot' | 'codex';
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
  /** Tried in order when a request fails before producing any output. */
  fallbackModels: string[];
  systemPrompt: string;
  temperature: number;
  maxTokens: number;
  /** Let the model call tools at all. */
  toolsEnabled: boolean;
  /** Local file writes need an explicit opt-in. */
  allowWriteTools: boolean;
  /** Expose read_image; only enable when the selected model accepts images. */
  imageToolsEnabled: boolean;
  /** Expose generate_image, which calls /images/generations. */
  imageGenEnabled: boolean;
  /** Allow the model to read and write the device clipboard. */
  clipboardToolsEnabled: boolean;
  /** Device-data tools; all off until the user opts in. */
  calendarToolsEnabled: boolean;
  contactsToolsEnabled: boolean;
  locationToolsEnabled: boolean;
  weatherToolsEnabled: boolean;
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
  /** Summarise old turns automatically when usage crosses the threshold. */
  autoCompact: boolean;
  /** Usage percentage (50–95) that triggers auto compaction. */
  autoCompactPercent: number;
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
  /** Reading scale for assistant/user message bodies. */
  messageFontScale: number;
  /** Reading scale for the composer input. */
  inputFontScale: number;
  /** Open settled reasoning blocks instead of only while streaming. */
  autoExpandThinking: boolean;
  /** Focus the composer when a reply finishes. */
  autoFocusInput: boolean;
  /** Let the model name new conversations automatically. */
  autoTitleEnabled: boolean;
  /** Offer existing folders to the title request and file the session. */
  autoGroupingEnabled: boolean;
  /** Ask eligible providers for priority service (`service_tier`). */
  fastMode: boolean;
  /** Built-in persona prepended to the system prompt. */
  soulId: string;
  /** Skill ids (imported SKILL.md files) injected into the system prompt. */
  enabledSkills: string[];
  /** Optional per-model request overrides (temperature, top_p, headers, body). */
  modelOverrides: ModelOverride[];
  /** MCP servers whose tools are exposed as `mcp_<server>_<tool>`. */
  mcpServers: McpServerConfig[];
  /** WebDAV collection used for encrypted remote backups; empty disables it. */
  webDavUrl: string;
  webDavUser: string;
  /** Basic-auth password, kept in the Asset Store like the API key. */
  webDavPassword: string;
  /** Pull-merge-push after changes and at startup; off by default. */
  webDavAutoSync: boolean;
  /** Epoch ms of the last successful sync; 0 when never synced. */
  webDavLastSyncAt: number;
  /** User-created sidebar folders; sessions reference them by `folderId`. */
  sessionFolders: SessionFolder[];
  /** Named subagents; the built-in `helper` is always first. */
  subAgents: SubAgentDefinition[];
  /**
   * Runtime-only access token from an OAuth login. Never persisted and never
   * exported; request builders switch to `Authorization: Bearer` when set.
   */
  oauthToken?: string;
  /** ChatGPT account id for the Codex OAuth route; runtime-only like the token. */
  oauthAccountId?: string;
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
/**
 * The budget is in characters, so 2,000,000 is roughly 500k–700k tokens.
 * Anything larger than that no current model accepts; the old 400k cap was
 * below what users of 1M-token models need (600k/1M were silently clamped).
 */
export const MAX_CONTEXT_BUDGET_CHARS: number = 2000000;

export const DEFAULT_AUTO_COMPACT_PERCENT: number = 80;
export const MIN_AUTO_COMPACT_PERCENT: number = 50;
export const MAX_AUTO_COMPACT_PERCENT: number = 95;

/** Clamp the auto-compaction threshold; invalid input falls back to 80%. */
export function clampAutoCompactPercent(value: number): number {
  if (Number.isNaN(value) || !Number.isFinite(value)) {
    return DEFAULT_AUTO_COMPACT_PERCENT;
  }
  const rounded: number = Math.floor(value);
  if (rounded < MIN_AUTO_COMPACT_PERCENT) {
    return MIN_AUTO_COMPACT_PERCENT;
  }
  if (rounded > MAX_AUTO_COMPACT_PERCENT) {
    return MAX_AUTO_COMPACT_PERCENT;
  }
  return rounded;
}

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

/** One user-created sidebar folder; the list itself lives in `AppSettings`. */
export interface SessionFolder {
  id: string;
  name: string;
  collapsed: boolean;
}

export const MAX_SESSION_FOLDERS: number = 30;

/** Trim, drop empty names/ids, dedupe ids and cap the list. */
export function normalizeSessionFolders(value: SessionFolder[] | undefined): SessionFolder[] {
  const result: SessionFolder[] = [];
  if (value === undefined || !Array.isArray(value)) {
    return result;
  }
  for (let i = 0; i < value.length && result.length < MAX_SESSION_FOLDERS; i++) {
    const item: SessionFolder = value[i];
    if (item === null || item === undefined) {
      continue;
    }
    const id: string = typeof item.id === 'string' ? item.id.trim() : '';
    const name: string = typeof item.name === 'string' ? item.name.trim() : '';
    if (id.length === 0 || name.length === 0) {
      continue;
    }
    let duplicate: boolean = false;
    for (let j = 0; j < result.length; j++) {
      if (result[j].id === id) {
        duplicate = true;
        break;
      }
    }
    if (!duplicate) {
      result.push({ id: id, name: name, collapsed: item.collapsed === true });
    }
  }
  return result;
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
  /** Sidebar folder; empty/undefined means "ungrouped". */
  folderId?: string;
  /** MCP server ids switched off for this session only. */
  mcpDisabled?: string[];
  /** Transient sidebar badge: background / interrupted / syncing. */
  statusBadge?: string;
}

/** Unknown or stale badge values are dropped when sessions load. */
export function normalizeSessionBadge(value: string | undefined): string {
  if (value === 'background' || value === 'interrupted' || value === 'syncing') {
    return value;
  }
  return '';
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
    groups.push({ label: t('置顶'), sessions: pinned });
  }
  if (today.length > 0) {
    groups.push({ label: t('今天'), sessions: today });
  }
  if (yesterday.length > 0) {
    groups.push({ label: t('昨天'), sessions: yesterday });
  }
  if (week.length > 0) {
    groups.push({ label: t('最近 7 天'), sessions: week });
  }
  if (older.length > 0) {
    groups.push({ label: t('更早'), sessions: older });
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

/** Stable identity for a tool-call part; imported histories may lack ids. */
export function toolPartKey(part: MessagePart): string {
  return part.toolCallId.length > 0
    ? part.toolCallId
    : part.toolName + ':' + part.argumentsText;
}

/**
 * Block-boundary rerun, mirroring OpenMinis' "Re-run From Here": keep every
 * block before the target tool call, drop the call itself, its later blocks
 * and all later messages. When nothing meaningful precedes the call in its
 * turn, dropping the whole assistant turn is equivalent and cheaper.
 *
 * Returns null when the part cannot be found, is not a tool call, or the cut
 * would leave no history to send.
 */
export function rerunCutFromTool(messages: ChatMessage[], messageId: string,
  key: string): ChatMessage[] | null {
  for (let i = 0; i < messages.length; i++) {
    const message: ChatMessage = messages[i];
    if (message.id !== messageId) {
      continue;
    }
    let partIndex: number = -1;
    for (let j = 0; j < message.parts.length; j++) {
      const part: MessagePart = message.parts[j];
      if (part.kind === PART_TOOL_CALL && toolPartKey(part) === key) {
        partIndex = j;
        break;
      }
    }
    if (partIndex < 0) {
      return null;
    }
    let hasPreceding: boolean = false;
    for (let j = 0; j < partIndex; j++) {
      const part: MessagePart = message.parts[j];
      if (part.kind === PART_TOOL_CALL ||
        (part.kind === PART_TEXT && part.text.trim().length > 0)) {
        hasPreceding = true;
        break;
      }
    }
    if (!hasPreceding) {
      return i > 0 ? messages.slice(0, i) : null;
    }
    const kept: ChatMessage = {
      id: message.id,
      role: message.role,
      parts: message.parts.slice(0, partIndex),
      createdAt: message.createdAt,
      streaming: false,
      error: false,
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0
    };
    const trimmed: ChatMessage[] = messages.slice(0, i);
    trimmed.push(kept);
    return trimmed;
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

/** A picked image waiting to be sent with the next user message. */
export interface ChatAttachment {
  /** `attachment:<file name>` persisted in the message part. */
  uri: string;
  mimeType: string;
  /** Absolute sandbox path used by the composer thumbnail. */
  path: string;
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
    fallbackModels: [],
    systemPrompt: '',
    temperature: 1.0,
    maxTokens: 8192,
    toolsEnabled: true,
    allowWriteTools: false,
    imageToolsEnabled: false,
    imageGenEnabled: false,
    clipboardToolsEnabled: false,
    calendarToolsEnabled: false,
    contactsToolsEnabled: false,
    locationToolsEnabled: false,
    weatherToolsEnabled: false,
    confirmWriteTools: false,
    sandboxMode: 'local',
    sandboxUrl: '',
    sandboxToken: '',
    maxAgentTurns: DEFAULT_MAX_AGENT_TURNS,
    contextBudgetChars: DEFAULT_CONTEXT_BUDGET_CHARS,
    autoCompact: true,
    autoCompactPercent: DEFAULT_AUTO_COMPACT_PERCENT,
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
    messageFontScale: 1,
    inputFontScale: 1,
    autoExpandThinking: false,
    autoFocusInput: true,
    autoTitleEnabled: true,
    autoGroupingEnabled: true,
    fastMode: false,
    soulId: 'general',
    enabledSkills: [],
    modelOverrides: [],
    mcpServers: [],
    webDavUrl: '',
    webDavUser: '',
    webDavPassword: '',
    webDavAutoSync: false,
    webDavLastSyncAt: 0,
    sessionFolders: [],
    subAgents: defaultAgents()
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

/**
 * Split a comma/semicolon/newline separated model list typed by the user.
 * Whitespace is trimmed and duplicates are dropped; order is preserved.
 */
export function parseModelList(text: string): string[] {
  const parts: string[] = text.split(/[,\n;，；]+/);
  const clean: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const id: string = parts[i].trim();
    if (id.length === 0) {
      continue;
    }
    clean.push(id);
  }
  return normalizeToolNames(clean);
}

/**
 * Primary model followed by fallbacks, trimmed and de-duplicated. A fallback
 * equal to the primary (or repeated) is ignored, matching "try each in order".
 */
export function modelChain(primary: string, fallbacks: string[]): string[] {
  const chain: string[] = [];
  const first: string = primary.trim();
  if (first.length > 0) {
    chain.push(first);
  }
  for (let i = 0; i < fallbacks.length; i++) {
    const id: string = fallbacks[i].trim();
    if (id.length > 0 && chain.indexOf(id) < 0) {
      chain.push(id);
    }
  }
  return chain;
}

export function cloneSettings(source: AppSettings): AppSettings {
  return {
    preset: source.preset,
    baseUrl: source.baseUrl,
    apiKey: source.apiKey,
    modelId: source.modelId,
    fallbackModels: normalizeToolNames(source.fallbackModels),
    systemPrompt: source.systemPrompt,
    temperature: source.temperature,
    maxTokens: source.maxTokens,
    toolsEnabled: source.toolsEnabled,
    allowWriteTools: source.allowWriteTools,
    imageToolsEnabled: source.imageToolsEnabled === true,
    imageGenEnabled: source.imageGenEnabled === true,
    clipboardToolsEnabled: source.clipboardToolsEnabled === true,
    calendarToolsEnabled: source.calendarToolsEnabled === true,
    contactsToolsEnabled: source.contactsToolsEnabled === true,
    locationToolsEnabled: source.locationToolsEnabled === true,
    weatherToolsEnabled: source.weatherToolsEnabled === true,
    confirmWriteTools: source.confirmWriteTools === true,
    sandboxMode: source.sandboxMode,
    sandboxUrl: source.sandboxUrl,
    sandboxToken: source.sandboxToken,
    maxAgentTurns: clampMaxTurns(source.maxAgentTurns),
    contextBudgetChars: clampContextBudget(source.contextBudgetChars),
    autoCompact: source.autoCompact !== false,
    autoCompactPercent: clampAutoCompactPercent(source.autoCompactPercent),
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
    messageFontScale: clampFontScale(source.messageFontScale !== undefined
      ? source.messageFontScale : source.fontScale),
    inputFontScale: clampFontScale(source.inputFontScale !== undefined
      ? source.inputFontScale : source.fontScale),
    autoExpandThinking: source.autoExpandThinking === true,
    autoFocusInput: source.autoFocusInput !== false,
    autoTitleEnabled: source.autoTitleEnabled !== false,
    autoGroupingEnabled: source.autoGroupingEnabled !== false,
    fastMode: source.fastMode === true,
    soulId: source.soulId !== undefined && source.soulId.length > 0
      ? source.soulId
      : 'general',
    enabledSkills: normalizeToolNames(source.enabledSkills),
    modelOverrides: normalizeModelOverrides(source.modelOverrides),
    mcpServers: normalizeMcpServers(source.mcpServers),
    webDavUrl: source.webDavUrl !== undefined ? source.webDavUrl : '',
    webDavUser: source.webDavUser !== undefined ? source.webDavUser : '',
    webDavPassword: source.webDavPassword !== undefined ? source.webDavPassword : '',
    webDavAutoSync: source.webDavAutoSync === true,
    sessionFolders: normalizeSessionFolders(source.sessionFolders),
    subAgents: normalizeAgents(source.subAgents),
    oauthToken: source.oauthToken !== undefined ? source.oauthToken : '',
    oauthAccountId: source.oauthAccountId !== undefined ? source.oauthAccountId : '',
    webDavLastSyncAt: source.webDavLastSyncAt !== undefined &&
      source.webDavLastSyncAt > 0 ? source.webDavLastSyncAt : 0
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

/** User attachment. `uri` is `attachment:<file name>` inside the app sandbox. */
export function imagePart(uri: string, mimeType: string): MessagePart {
  const part: MessagePart = makePart(PART_IMAGE);
  part.uri = uri;
  part.mimeType = mimeType;
  return part;
}

/**
 * Non-image attachment (video/audio). Models receive a text placeholder; the
 * part stays in history so the bubble can play the file inline.
 */
export function filePart(uri: string, mimeType: string): MessagePart {
  const part: MessagePart = makePart(PART_FILE);
  part.uri = uri;
  part.mimeType = mimeType;
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
