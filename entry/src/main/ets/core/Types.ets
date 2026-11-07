/**
 * Shared data types and defaults.
 *
 * Kept free of HarmonyOS imports so the pure parts can be exercised by the
 * Node test harness in scripts/test-core.mjs.
 */

export const OPENCODE_GO_BASE: string = 'https://opencode.ai/inference/go/openai/v1';
export const OPENCODE_DEFAULT_MODEL: string = 'kimi-k3';
export const APP_VERSION: string = '1.0.0';

export type ProviderPreset = 'opencode' | 'custom';

export interface AppSettings {
  preset: ProviderPreset;
  baseUrl: string;
  apiKey: string;
  modelId: string;
  systemPrompt: string;
  temperature: number;
  maxTokens: number;
}

export interface SessionMeta {
  id: string;
  title: string;
  updatedAt: number;
  modelId: string;
  messageCount: number;
}

export interface ChatMessage {
  id: string;
  role: string;
  content: string;
  reasoning: string;
  createdAt: number;
  streaming: boolean;
  error: boolean;
}

export interface StoredSession {
  meta: SessionMeta;
  messages: ChatMessage[];
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
    maxTokens: 8192
  };
}

export function cloneSettings(source: AppSettings): AppSettings {
  return {
    preset: source.preset,
    baseUrl: source.baseUrl,
    apiKey: source.apiKey,
    modelId: source.modelId,
    systemPrompt: source.systemPrompt,
    temperature: source.temperature,
    maxTokens: source.maxTokens
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

export function newChatMessage(id: string, role: string, content: string): ChatMessage {
  return {
    id: id,
    role: role,
    content: content,
    reasoning: '',
    createdAt: Date.now(),
    streaming: false,
    error: false
  };
}
