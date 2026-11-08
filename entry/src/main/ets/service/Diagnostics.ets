import { bundleManager, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { AppSettings, StoredSession } from '../core/Types';
import {
  DiagnosticsCounts,
  DiagnosticsEnvironment,
  DiagnosticsSettingsSummary,
  MAX_DIAGNOSTIC_CRASH_LINES,
  MAX_DIAGNOSTIC_EVENT_LINES,
  buildDiagnostics,
  diagnosticsFileName
} from '../core/Diagnostics';
import { AppLogger } from './AppLogger';
import { CrashLog } from './CrashLog';
import { ExportOutcome, saveText } from './ExportService';
import { t } from '../core/I18n';

function environment(): DiagnosticsEnvironment {
  let versionName: string = '';
  let versionCode: number = 0;
  try {
    const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    versionName = info.versionName;
    versionCode = info.versionCode;
  } catch (e) {
    // A stripped-down build may not expose bundle info; leave it blank.
  }
  let locale: string = '';
  try {
    locale = i18n.getSystemLanguage();
  } catch (e) {
    locale = '';
  }
  let model: string = '';
  let osVersion: string = '';
  let sdkApi: number = 0;
  try {
    model = deviceInfo.productModel;
    osVersion = deviceInfo.osFullName;
    sdkApi = deviceInfo.sdkApiVersion;
  } catch (e) {
    // deviceInfo is unavailable on the emulator in rare configurations.
  }
  const env: DiagnosticsEnvironment = {
    versionName: versionName,
    versionCode: versionCode,
    sdkApi: sdkApi,
    deviceModel: model,
    osVersion: osVersion,
    locale: locale
  };
  return env;
}

/**
 * Only non-secret, non-content configuration. The base URL is omitted because
 * it can embed credentials; the system prompt is omitted because it is user
 * content.
 */
function settingsSummary(settings: AppSettings): DiagnosticsSettingsSummary {
  const summary: DiagnosticsSettingsSummary = {
    preset: settings.preset,
    modelId: settings.modelId,
    thinkingLevel: settings.thinkingLevel,
    temperature: settings.temperature,
    maxTokens: settings.maxTokens,
    fallbackModels: settings.fallbackModels.length,
    toolsEnabled: settings.toolsEnabled,
    allowWriteTools: settings.allowWriteTools,
    confirmWriteTools: settings.confirmWriteTools,
    imageToolsEnabled: settings.imageToolsEnabled,
    imageGenEnabled: settings.imageGenEnabled,
    clipboardToolsEnabled: settings.clipboardToolsEnabled,
    memoryEnabled: settings.memoryEnabled,
    backgroundEnabled: settings.backgroundEnabled,
    remoteSandbox: settings.sandboxMode === 'remote',
    mcpServers: settings.mcpServers.length,
    disabledTools: settings.disabledTools.slice(0),
    appLockEnabled: settings.appLockEnabled,
    loggingEnabled: settings.loggingEnabled
  };
  return summary;
}

function countMessages(sessions: StoredSession[]): number {
  let total: number = 0;
  for (let i = 0; i < sessions.length; i++) {
    total += sessions[i].messages.length;
  }
  return total;
}

/**
 * Build and save a diagnostics bundle. Crash records and event lines are
 * metadata only; no prompt, message body or credential is included.
 */
export async function saveDiagnostics(
  context: common.UIAbilityContext,
  settings: AppSettings,
  sessions: StoredSession[]
): Promise<ExportOutcome> {
  const now: Date = new Date();
  const counts: DiagnosticsCounts = {
    sessions: sessions.length,
    messages: countMessages(sessions)
  };
  let text: string = '';
  try {
    text = buildDiagnostics({
      generatedAt: now.getTime(),
      environment: environment(),
      counts: counts,
      settings: settingsSummary(settings),
      crashLines: CrashLog.recent(MAX_DIAGNOSTIC_CRASH_LINES),
      eventLines: AppLogger.recent(MAX_DIAGNOSTIC_EVENT_LINES)
    });
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('生成诊断包失败：') + error.message };
  }
  return saveText(
    context,
    diagnosticsFileName(now),
    'JSON|.json',
    text,
    t('已导出诊断包')
  );
}
