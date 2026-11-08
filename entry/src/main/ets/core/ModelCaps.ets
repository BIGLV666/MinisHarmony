import { t } from './I18n';
/**
 * Built-in model capability estimates. HarmonyOS cannot reach models.dev
 * offline, so this is a prefix table covering the OpenCode Go families with a
 * conservative fallback. It is display/limit metadata only: it never blocks a
 * model from being used, and the request still sends the user's maxTokens
 * unless it exceeds the estimated output cap.
 */
export interface ModelCaps {
  /** Estimated context window in tokens. */
  contextWindow: number;
  /** Estimated maximum completion tokens. */
  maxOutput: number;
  /** Model family accepts image parts. */
  vision: boolean;
  /** Model family accepts reasoning_effort. */
  reasoning: boolean;
  /** Model family accepts OpenAI-style tools. */
  tools: boolean;
}

const UNKNOWN_CONTEXT_WINDOW: number = 128000;
const UNKNOWN_MAX_OUTPUT: number = 8192;

export const DEFAULT_MODEL_CAPS: ModelCaps = {
  contextWindow: UNKNOWN_CONTEXT_WINDOW,
  maxOutput: UNKNOWN_MAX_OUTPUT,
  vision: false,
  reasoning: false,
  tools: true
};

interface CapsRule {
  prefix: string;
  caps: ModelCaps;
}

function caps(
  contextWindow: number,
  maxOutput: number,
  vision: boolean,
  reasoning: boolean
): ModelCaps {
  return {
    contextWindow: contextWindow,
    maxOutput: maxOutput,
    vision: vision,
    reasoning: reasoning,
    tools: true
  };
}

/** Longest prefixes first so `gemini` never shadows a more specific id. */
const RULES: CapsRule[] = [
  { prefix: 'gpt-6', caps: caps(400000, 32768, true, true) },
  { prefix: 'gpt-5', caps: caps(400000, 32768, true, true) },
  { prefix: 'claude', caps: caps(200000, 32000, true, true) },
  { prefix: 'gemini', caps: caps(1000000, 65536, true, true) },
  { prefix: 'grok', caps: caps(256000, 16384, true, true) },
  { prefix: 'kimi-k3', caps: caps(256000, 16384, true, true) },
  { prefix: 'kimi-k2', caps: caps(256000, 16384, false, true) },
  { prefix: 'minimax', caps: caps(256000, 16384, false, true) },
  { prefix: 'qwen', caps: caps(128000, 8192, false, true) },
  { prefix: 'glm', caps: caps(128000, 16384, false, true) },
  { prefix: 'deepseek', caps: caps(128000, 8192, false, true) }
];

export function capsForModel(modelId: string): ModelCaps {
  const id: string = modelId.trim().toLowerCase();
  for (let i = 0; i < RULES.length; i++) {
    if (id.startsWith(RULES[i].prefix)) {
      return RULES[i].caps;
    }
  }
  return DEFAULT_MODEL_CAPS;
}

/** Keeps the user's value but never asks for more output than the model allows. */
export function clampMaxTokens(requested: number, caps: ModelCaps): number {
  if (requested <= 0) {
    return caps.maxOutput;
  }
  return requested > caps.maxOutput ? caps.maxOutput : requested;
}

/** Compact label such as `128k · 视觉`, used by the model picker. */
export function capsLabel(caps: ModelCaps): string {
  let label: string = formatWindow(caps.contextWindow);
  if (caps.vision) {
    label += t(' · 视觉');
  }
  if (caps.reasoning) {
    label += t(' · 推理');
  }
  return label;
}

export function formatWindow(tokens: number): string {
  if (tokens >= 1000000) {
    return (tokens / 1000000).toString() + 'm';
  }
  if (tokens >= 1000) {
    const k: number = Math.round(tokens / 1000);
    return k.toString() + 'k';
  }
  return tokens.toString();
}

/** Percentage of the window used, capped at 100 for display. */
export function contextPercent(used: number, window: number): number {
  if (used <= 0 || window <= 0) {
    return 0;
  }
  const percent: number = Math.round((used / window) * 100);
  return percent > 100 ? 100 : percent;
}
