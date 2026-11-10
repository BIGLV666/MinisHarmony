import { AppSettings, ThinkingLevel, cloneSettings } from './Types';
import { t } from './I18n';

/**
 * The agent-facing `config` tool. It deliberately exposes only presentation
 * and generation knobs: credentials, endpoints, tool permissions, MCP servers
 * and prompt/skill content stay user-only. Every successful change goes
 * through the normal settings save path and is audited with actor `agent`.
 */
export const AGENT_CONFIG_KEYS: string[] = [
  'temperature',
  'maxTokens',
  'thinkingLevel',
  'enterToSend',
  'autoExpandThinking',
  'autoFocusInput',
  'autoTitleEnabled',
  'autoGroupingEnabled',
  'fontScale',
  'messageFontScale',
  'inputFontScale',
  'accentColor'
];

export interface AgentConfigOutcome {
  ok: boolean;
  settings: AppSettings;
  message: string;
  changed: boolean;
}

export function agentConfigKeyAllowed(key: string): boolean {
  return AGENT_CONFIG_KEYS.indexOf(key) >= 0;
}

function boolText(value: boolean): string {
  return value ? 'true' : 'false';
}

/** One `key = value` line per writable setting, with no secrets. */
export function agentConfigValue(settings: AppSettings, key: string): string {
  if (key === 'temperature') {
    return settings.temperature.toString();
  }
  if (key === 'maxTokens') {
    return settings.maxTokens.toString();
  }
  if (key === 'thinkingLevel') {
    return settings.thinkingLevel;
  }
  if (key === 'enterToSend') {
    return boolText(settings.enterToSend);
  }
  if (key === 'autoExpandThinking') {
    return boolText(settings.autoExpandThinking);
  }
  if (key === 'autoFocusInput') {
    return boolText(settings.autoFocusInput);
  }
  if (key === 'autoTitleEnabled') {
    return boolText(settings.autoTitleEnabled);
  }
  if (key === 'autoGroupingEnabled') {
    return boolText(settings.autoGroupingEnabled);
  }
  if (key === 'fontScale') {
    return settings.fontScale.toString();
  }
  if (key === 'messageFontScale') {
    return settings.messageFontScale.toString();
  }
  if (key === 'inputFontScale') {
    return settings.inputFontScale.toString();
  }
  if (key === 'accentColor') {
    return settings.accentColor;
  }
  return '';
}

export function agentConfigSnapshot(settings: AppSettings): string {
  const lines: string[] = [];
  for (let i = 0; i < AGENT_CONFIG_KEYS.length; i++) {
    const key: string = AGENT_CONFIG_KEYS[i];
    lines.push(key + ' = ' + agentConfigValue(settings, key));
  }
  return lines.join('\n');
}

function failure(settings: AppSettings, message: string): AgentConfigOutcome {
  return { ok: false, settings: settings, message: message, changed: false };
}

function parseBool(value: string): boolean | null {
  if (value === 'true') {
    return true;
  }
  if (value === 'false') {
    return false;
  }
  return null;
}

function parseNumber(value: string): number {
  return Number(value);
}

function scaleValid(value: number): boolean {
  return Number.isFinite(value) && value >= 0.9 && value <= 1.3;
}

/** Validate and apply one key; returns a cloned settings object. */
export function applyAgentConfig(
  settings: AppSettings,
  key: string,
  rawValue: string
): AgentConfigOutcome {
  const name: string = key.trim();
  const value: string = rawValue.trim();
  if (!agentConfigKeyAllowed(name)) {
    return failure(settings, t('这个配置项不允许由代理修改：') + name);
  }
  if (value.length === 0) {
    return failure(settings, t('配置值不能为空。'));
  }
  const next: AppSettings = cloneSettings(settings);
  if (name === 'temperature') {
    const number: number = parseNumber(value);
    if (!Number.isFinite(number) || number < 0 || number > 2) {
      return failure(settings, t('温度需要 0–2 之间的数字。'));
    }
    next.temperature = number;
  } else if (name === 'maxTokens') {
    const number: number = parseNumber(value);
    if (!Number.isFinite(number) || number < 1 || number > 1000000 ||
      Math.floor(number) !== number) {
      return failure(settings, t('最大输出需要 1–1000000 之间的整数。'));
    }
    next.maxTokens = number;
  } else if (name === 'thinkingLevel') {
    if (value !== 'off' && value !== 'low' && value !== 'medium' &&
      value !== 'high') {
      return failure(settings, t('思考级别只能是 off、low、medium 或 high。'));
    }
    next.thinkingLevel = value as ThinkingLevel;
  } else if (name === 'enterToSend' || name === 'autoExpandThinking' ||
    name === 'autoFocusInput' || name === 'autoTitleEnabled' ||
    name === 'autoGroupingEnabled') {
    const parsed: boolean | null = parseBool(value);
    if (parsed === null) {
      return failure(settings, t('这个配置项需要 true 或 false。'));
    }
    if (name === 'enterToSend') {
      next.enterToSend = parsed;
    } else if (name === 'autoExpandThinking') {
      next.autoExpandThinking = parsed;
    } else if (name === 'autoFocusInput') {
      next.autoFocusInput = parsed;
    } else if (name === 'autoTitleEnabled') {
      next.autoTitleEnabled = parsed;
    } else {
      next.autoGroupingEnabled = parsed;
    }
  } else if (name === 'fontScale' || name === 'messageFontScale' ||
    name === 'inputFontScale') {
    const number: number = parseNumber(value);
    if (!scaleValid(number)) {
      return failure(settings, t('字号需要 0.9–1.3 之间的数字。'));
    }
    if (name === 'fontScale') {
      next.fontScale = number;
    } else if (name === 'messageFontScale') {
      next.messageFontScale = number;
    } else {
      next.inputFontScale = number;
    }
  } else if (name === 'accentColor') {
    if (!new RegExp('^#[0-9a-fA-F]{6}$').test(value)) {
      return failure(settings, t('强调色需要 #RRGGBB 格式。'));
    }
    next.accentColor = value;
  }
  const changed: boolean =
    agentConfigValue(settings, name) !== agentConfigValue(next, name);
  return {
    ok: true,
    settings: next,
    message: changed
      ? t('已更新配置：') + name + ' = ' + agentConfigValue(next, name)
      : t('配置未变化：') + name,
    changed: changed
  };
}
