import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings } from '../core/Types';
import {
  CONFIG_AUDIT_LIMIT,
  ConfigAuditEntry,
  ConfigPair,
  complexConfigValue,
  encodeConfigValue,
  parseConfigAudit,
  secretConfigValue
} from '../core/ConfigAudit';

const STORE_NAME: string = 'minis_config_audit';
const KEY_ENTRIES: string = 'entries';

function num(value: number): string {
  return Number.isFinite(value) ? value.toString() : '0';
}

function bool(value: boolean): string {
  return value ? 'true' : 'false';
}

function strings(value: string[]): string {
  return JSON.stringify(value);
}

/**
 * Audited view of settings. Secrets only record presence, structured values
 * only record their size, so keys and tokens never reach the audit table.
 */
export function configSnapshot(settings: AppSettings): ConfigPair[] {
  return [
    { key: 'preset', value: encodeConfigValue(settings.preset) },
    { key: 'baseUrl', value: encodeConfigValue(settings.baseUrl) },
    { key: 'apiKey', value: secretConfigValue(settings.apiKey.length > 0) },
    { key: 'modelId', value: encodeConfigValue(settings.modelId) },
    { key: 'fallbackModels', value: strings(settings.fallbackModels) },
    { key: 'systemPrompt', value: encodeConfigValue(settings.systemPrompt) },
    { key: 'temperature', value: num(settings.temperature) },
    { key: 'maxTokens', value: num(settings.maxTokens) },
    { key: 'toolsEnabled', value: bool(settings.toolsEnabled) },
    { key: 'allowWriteTools', value: bool(settings.allowWriteTools) },
    { key: 'imageToolsEnabled', value: bool(settings.imageToolsEnabled) },
    { key: 'imageGenEnabled', value: bool(settings.imageGenEnabled) },
    { key: 'clipboardToolsEnabled', value: bool(settings.clipboardToolsEnabled) },
    { key: 'calendarToolsEnabled', value: bool(settings.calendarToolsEnabled) },
    { key: 'contactsToolsEnabled', value: bool(settings.contactsToolsEnabled) },
    { key: 'locationToolsEnabled', value: bool(settings.locationToolsEnabled) },
    { key: 'weatherToolsEnabled', value: bool(settings.weatherToolsEnabled) },
    { key: 'confirmWriteTools', value: bool(settings.confirmWriteTools) },
    { key: 'sandboxMode', value: encodeConfigValue(settings.sandboxMode) },
    { key: 'sandboxUrl', value: encodeConfigValue(settings.sandboxUrl) },
    { key: 'sandboxToken', value: secretConfigValue(settings.sandboxToken.length > 0) },
    { key: 'maxAgentTurns', value: num(settings.maxAgentTurns) },
    { key: 'contextBudgetChars', value: num(settings.contextBudgetChars) },
    { key: 'autoCompact', value: bool(settings.autoCompact) },
    { key: 'autoCompactPercent', value: num(settings.autoCompactPercent) },
    { key: 'loggingEnabled', value: bool(settings.loggingEnabled) },
    { key: 'memoryEnabled', value: bool(settings.memoryEnabled) },
    { key: 'backgroundEnabled', value: bool(settings.backgroundEnabled) },
    { key: 'thinkingLevel', value: encodeConfigValue(settings.thinkingLevel) },
    { key: 'enterToSend', value: bool(settings.enterToSend) },
    { key: 'disabledTools', value: strings(settings.disabledTools) },
    { key: 'appLockEnabled', value: bool(settings.appLockEnabled) },
    { key: 'accentColor', value: encodeConfigValue(settings.accentColor) },
    { key: 'fontScale', value: num(settings.fontScale) },
    { key: 'soulId', value: encodeConfigValue(settings.soulId) },
    { key: 'enabledSkills', value: strings(settings.enabledSkills) },
    { key: 'modelOverrides', value: complexConfigValue(settings.modelOverrides.length) },
    { key: 'mcpServers', value: complexConfigValue(settings.mcpServers.length) },
    { key: 'webDavUrl', value: encodeConfigValue(settings.webDavUrl) },
    { key: 'webDavUser', value: encodeConfigValue(settings.webDavUser) },
    { key: 'webDavPassword', value: secretConfigValue(settings.webDavPassword.length > 0) },
    { key: 'webDavAutoSync', value: bool(settings.webDavAutoSync) },
    { key: 'sessionFolders', value: complexConfigValue(settings.sessionFolders.length) },
    { key: 'subAgents', value: complexConfigValue(settings.subAgents.length) }
  ];
}

/**
 * Local-only settings audit. Rows are plain differences with a timestamp; no
 * prompt text and no secret value is kept beyond a set/unset flag.
 */
export class ConfigAuditStore {
  private static store(context: common.Context): preferences.Preferences {
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  static load(context: common.Context): ConfigAuditEntry[] {
    try {
      const raw: preferences.ValueType =
        ConfigAuditStore.store(context).getSync(KEY_ENTRIES, '');
      return parseConfigAudit(typeof raw === 'string' ? raw as string : '');
    } catch (e) {
      return [];
    }
  }

  static save(context: common.Context, entries: ConfigAuditEntry[]): void {
    try {
      const store: preferences.Preferences = ConfigAuditStore.store(context);
      const capped: ConfigAuditEntry[] = entries.length > CONFIG_AUDIT_LIMIT
        ? entries.slice(0, CONFIG_AUDIT_LIMIT) : entries;
      store.putSync(KEY_ENTRIES, JSON.stringify(capped));
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }

  static clear(context: common.Context): void {
    try {
      const store: preferences.Preferences = ConfigAuditStore.store(context);
      store.putSync(KEY_ENTRIES, '');
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }
}
