import { t } from './I18n';

/** One audited settings value, encoded as JSON so it can be restored. */
export interface ConfigPair {
  key: string;
  value: string;
}

/** A changed settings key produced by the settings sheet or model picker. */
export interface ConfigAuditEntry {
  id: string;
  at: number;
  /** `user` today; reserved for an agent-driven `config` tool later. */
  actor: string;
  key: string;
  /** Encoded value before the change. */
  before: string;
  /** Encoded value after the change. */
  after: string;
  /** False for secrets and structured settings whose old value is not kept. */
  restorable: boolean;
}

/** Newest entries kept; older rows fall off. */
export const CONFIG_AUDIT_LIMIT: number = 200;

/** Values of these keys are never written to the audit table. */
export const CONFIG_SECRET_KEYS: string[] = [
  'apiKey',
  'sandboxToken',
  'webDavPassword'
];

/** Structured settings: only a summary is stored, so they cannot be restored. */
export const CONFIG_COMPLEX_KEYS: string[] = [
  'modelOverrides',
  'mcpServers',
  'sessionFolders',
  'subAgents'
];

/** Keys whose old value can be written back from an audit row. */
export const CONFIG_RESTORABLE_KEYS: string[] = [
  'preset',
  'baseUrl',
  'modelId',
  'fallbackModels',
  'systemPrompt',
  'temperature',
  'maxTokens',
  'toolsEnabled',
  'allowWriteTools',
  'imageToolsEnabled',
  'imageGenEnabled',
  'clipboardToolsEnabled',
  'calendarToolsEnabled',
  'contactsToolsEnabled',
  'locationToolsEnabled',
  'weatherToolsEnabled',
  'confirmWriteTools',
  'sandboxMode',
  'sandboxUrl',
  'maxAgentTurns',
  'contextBudgetChars',
  'autoCompact',
  'autoCompactPercent',
  'loggingEnabled',
  'memoryEnabled',
  'backgroundEnabled',
  'thinkingLevel',
  'enterToSend',
  'disabledTools',
  'appLockEnabled',
  'accentColor',
  'fontScale',
  'messageFontScale',
  'inputFontScale',
  'autoExpandThinking',
  'autoFocusInput',
  'autoTitleEnabled',
  'autoGroupingEnabled',
  'fastMode',
  'soulId',
  'enabledSkills',
  'webDavUrl',
  'webDavUser',
  'webDavAutoSync'
];

export function isSecretConfigKey(key: string): boolean {
  return CONFIG_SECRET_KEYS.indexOf(key) >= 0;
}

export function isComplexConfigKey(key: string): boolean {
  return CONFIG_COMPLEX_KEYS.indexOf(key) >= 0;
}

export function configAuditRestorable(key: string): boolean {
  return CONFIG_RESTORABLE_KEYS.indexOf(key) >= 0;
}

/** Secret values only reveal whether one is set. */
export function secretConfigValue(hasValue: boolean): string {
  return hasValue ? '"set"' : '""';
}

/** Structured values are reduced to a count so tokens inside never persist. */
export function complexConfigValue(count: number): string {
  return JSON.stringify(count.toString() + ' 项');
}

/** Strings and string arrays are stored as JSON. */
export function encodeConfigValue(value: string): string {
  return JSON.stringify(value);
}

function clip(text: string): string {
  const flat: string = text.split('\n').join(' ').split('\r').join(' ')
    .split('\t').join(' ').trim();
  if (flat.length === 0) {
    return t('（空）');
  }
  return flat.length > 48 ? flat.substring(0, 48) + '…' : flat;
}

/** One-line label for an encoded audit value. */
export function auditValueLabel(key: string, value: string): string {
  if (isSecretConfigKey(key)) {
    return value === '""' ? t('未设置') : t('已设置');
  }
  if (isComplexConfigKey(key)) {
    try {
      const summary: Object = JSON.parse(value) as Object;
      return typeof summary === 'string' ? clip(summary as string) : clip(value);
    } catch (e) {
      return clip(value);
    }
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(value) as Object;
  } catch (e) {
    return clip(value);
  }
  if (typeof parsed === 'string') {
    return clip(parsed as string);
  }
  if (typeof parsed === 'number' || typeof parsed === 'boolean') {
    return parsed.toString();
  }
  if (Array.isArray(parsed)) {
    return (parsed as Object[]).length.toString() + t(' 项');
  }
  return clip(value);
}

/** Compare two snapshots and emit one entry per changed key. */
export function diffConfig(
  before: ConfigPair[],
  after: ConfigPair[],
  at: number,
  actor: string
): ConfigAuditEntry[] {
  const result: ConfigAuditEntry[] = [];
  for (let i = 0; i < after.length; i++) {
    const next: ConfigPair = after[i];
    let old: string = '';
    for (let j = 0; j < before.length; j++) {
      if (before[j].key === next.key) {
        old = before[j].value;
        break;
      }
    }
    if (old === next.value) {
      continue;
    }
    result.push({
      id: at.toString() + '-' + i.toString() + '-' + next.key,
      at: at,
      actor: actor,
      key: next.key,
      before: old,
      after: next.value,
      restorable: configAuditRestorable(next.key)
    });
  }
  return result;
}

/** Newest first, capped. Added rows are already in display order. */
export function mergeConfigAudit(
  existing: ConfigAuditEntry[],
  added: ConfigAuditEntry[],
  limit: number
): ConfigAuditEntry[] {
  const merged: ConfigAuditEntry[] = added.concat(existing);
  const cap: number = limit > 0 ? limit : CONFIG_AUDIT_LIMIT;
  return merged.length > cap ? merged.slice(0, cap) : merged;
}

function parseEntry(item: Record<string, Object>): ConfigAuditEntry | null {
  const key: string = typeof item.key === 'string' ? item.key as string : '';
  const at: number = typeof item.at === 'number' ? item.at as number : 0;
  if (key.trim().length === 0 || at <= 0) {
    return null;
  }
  return {
    id: typeof item.id === 'string' ? item.id as string : at.toString() + '-' + key,
    at: at,
    actor: typeof item.actor === 'string' ? item.actor as string : 'user',
    key: key,
    before: typeof item.before === 'string' ? item.before as string : '""',
    after: typeof item.after === 'string' ? item.after as string : '""',
    restorable: item.restorable === true
  };
}

/** Parse the preferences payload, dropping malformed rows. */
export function parseConfigAudit(raw: string): ConfigAuditEntry[] {
  if (raw.trim().length === 0) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const list: Object[] = parsed as Object[];
  const result: ConfigAuditEntry[] = [];
  for (let i = 0; i < list.length; i++) {
    const entry: ConfigAuditEntry | null =
      parseEntry(list[i] as Record<string, Object>);
    if (entry !== null) {
      result.push(entry);
    }
    if (result.length >= CONFIG_AUDIT_LIMIT) {
      break;
    }
  }
  return result;
}
