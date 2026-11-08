/**
 * Whole-library backup: every session plus a settings snapshot.
 *
 * The file is plain JSON (encryption is a separate, later feature), so
 * secrets are stripped before writing: the API key, the sandbox token, MCP
 * request headers and per-model extra headers never leave the device.
 * Restoring keeps the current secrets and only adopts the non-secret
 * settings, which is the behaviour users expect from "restore my config"
 * without silently overwriting credentials.
 */

import {
  AppSettings,
  StoredSession,
  cloneSettings,
  defaultSettings,
  normalizeThinkingLevel,
  normalizeToolNames
} from './Types';
import {
  SESSION_EXPORT_APP,
  SESSION_EXPORT_VERSION,
  SessionBundleEnvelope,
  sessionBundleJson,
  sessionBundleFileName
} from './SessionExport';
import { ModelOverride } from './ModelOverride';
import { McpServerConfig } from './McpProtocol';

export const BACKUP_KIND: string = 'backup';

export interface BackupEnvelope {
  app: string;
  version: number;
  kind: string;
  exportedAt: string;
  exportedOn: string;
  settings: AppSettings;
  sessions: StoredSession[];
}

interface RawBackupRoot {
  app?: string;
  version?: number;
  kind?: string;
  settings?: AppSettings;
  sessions?: StoredSession[];
}

/** Copy settings with every credential-bearing field blanked. */
export function redactedSettings(settings: AppSettings): AppSettings {
  const copy: AppSettings = cloneSettings(settings);
  copy.apiKey = '';
  copy.sandboxToken = '';
  const overrides: ModelOverride[] = [];
  for (let i = 0; i < copy.modelOverrides.length; i++) {
    const item: ModelOverride = copy.modelOverrides[i];
    overrides.push({
      modelId: item.modelId,
      temperature: item.temperature,
      topP: item.topP,
      maxTokens: item.maxTokens,
      extraHeaders: '',
      extraBody: item.extraBody
    });
  }
  copy.modelOverrides = overrides;
  const servers: McpServerConfig[] = [];
  for (let i = 0; i < copy.mcpServers.length; i++) {
    const server: McpServerConfig = copy.mcpServers[i];
    servers.push({
      id: server.id,
      name: server.name,
      url: server.url,
      headers: '',
      enabled: server.enabled
    });
  }
  copy.mcpServers = servers;
  return copy;
}

export function backupFileName(now: Date): string {
  const stamp: string = sessionBundleFileName(now)
    .replace('minis-sessions-', '')
    .replace('.json', '');
  return 'minis-backup-' + stamp + '.json';
}

export function backupJson(
  settings: AppSettings,
  sessions: StoredSession[],
  now: Date
): string {
  const bundle: SessionBundleEnvelope =
    JSON.parse(sessionBundleJson(sessions, now)) as SessionBundleEnvelope;
  const envelope: BackupEnvelope = {
    app: SESSION_EXPORT_APP,
    version: SESSION_EXPORT_VERSION,
    kind: BACKUP_KIND,
    exportedAt: bundle.exportedAt,
    exportedOn: bundle.exportedOn,
    settings: redactedSettings(settings),
    sessions: bundle.sessions
  };
  return JSON.stringify(envelope, null, 2);
}

function numberOr(value: number | undefined, fallback: number): number {
  return typeof value === 'number' && !Number.isNaN(value) ? value : fallback;
}

function boolOr(value: boolean | undefined, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function stringOr(value: string | undefined, fallback: string): string {
  return typeof value === 'string' ? value : fallback;
}

/**
 * Extract the settings snapshot from a backup file. Returns null for a plain
 * session bundle (which has no settings) or any malformed input.
 */
export function parseBackupSettings(text: string): AppSettings | null {
  let root: RawBackupRoot;
  try {
    root = JSON.parse(text) as RawBackupRoot;
  } catch (e) {
    return null;
  }
  if (root === null || root === undefined || root.kind !== BACKUP_KIND ||
    root.app !== SESSION_EXPORT_APP ||
    root.settings === undefined || root.settings === null) {
    return null;
  }
  const raw: AppSettings = root.settings;
  const base: AppSettings = defaultSettings();
  base.preset = raw.preset === 'custom' || raw.preset === 'anthropic' ||
    raw.preset === 'gemini' ? raw.preset : 'opencode';
  base.baseUrl = stringOr(raw.baseUrl, base.baseUrl);
  base.modelId = stringOr(raw.modelId, base.modelId);
  base.fallbackModels = normalizeToolNames(raw.fallbackModels);
  base.systemPrompt = stringOr(raw.systemPrompt, '');
  base.temperature = numberOr(raw.temperature, base.temperature);
  base.maxTokens = numberOr(raw.maxTokens, base.maxTokens);
  base.toolsEnabled = boolOr(raw.toolsEnabled, true);
  base.allowWriteTools = boolOr(raw.allowWriteTools, false);
  base.imageToolsEnabled = boolOr(raw.imageToolsEnabled, false);
  base.imageGenEnabled = boolOr(raw.imageGenEnabled, false);
  base.clipboardToolsEnabled = boolOr(raw.clipboardToolsEnabled, false);
  base.confirmWriteTools = boolOr(raw.confirmWriteTools, false);
  base.sandboxMode = raw.sandboxMode === 'remote' ? 'remote' : 'local';
  base.sandboxUrl = stringOr(raw.sandboxUrl, '');
  base.maxAgentTurns = numberOr(raw.maxAgentTurns, base.maxAgentTurns);
  base.contextBudgetChars = numberOr(raw.contextBudgetChars, base.contextBudgetChars);
  base.loggingEnabled = boolOr(raw.loggingEnabled, false);
  base.memoryEnabled = boolOr(raw.memoryEnabled, false);
  base.backgroundEnabled = boolOr(raw.backgroundEnabled, true);
  base.thinkingLevel = normalizeThinkingLevel(raw.thinkingLevel);
  base.enterToSend = boolOr(raw.enterToSend, false);
  base.disabledTools = normalizeToolNames(raw.disabledTools);
  base.onboardingDone = boolOr(raw.onboardingDone, false);
  base.appLockEnabled = boolOr(raw.appLockEnabled, false);
  base.accentColor = stringOr(raw.accentColor, base.accentColor);
  base.fontScale = numberOr(raw.fontScale, 1);
  base.soulId = stringOr(raw.soulId, 'general');
  base.enabledSkills = normalizeToolNames(raw.enabledSkills);
  base.modelOverrides = Array.isArray(raw.modelOverrides) ? raw.modelOverrides : [];
  base.mcpServers = Array.isArray(raw.mcpServers) ? raw.mcpServers : [];
  // cloneSettings normalizes/clamps every field a second time.
  return cloneSettings(base);
}

/**
 * Apply a restored snapshot without touching credentials: the API key and
 * sandbox token always come from `current`.
 */
export function mergeBackupSettings(
  current: AppSettings,
  backup: AppSettings
): AppSettings {
  const next: AppSettings = cloneSettings(backup);
  next.apiKey = current.apiKey;
  next.sandboxToken = current.sandboxToken;
  return next;
}
