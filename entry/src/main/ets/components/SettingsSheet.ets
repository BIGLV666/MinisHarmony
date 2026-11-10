import {
  AppSettings,
  OPENCODE_DEFAULT_MODEL,
  OPENCODE_GO_BASE,
  ProviderPreset,
  SandboxMode,
  ThinkingLevel,
  clampAutoCompactPercent,
  clampContextBudget,
  clampMaxTurns,
  cloneSettings,
  defaultSettings,
  parseModelList
} from '../core/Types';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { SandboxProbe } from '../service/SandboxProbe';
import {
  SandboxIsh,
  SandboxOptions,
  SandboxRunResult,
  SandboxStatus
} from '../service/SandboxIsh';
import {
  ACCENT_PRESETS,
  AccentPreset,
  FONT_SCALE_OPTIONS,
  fontScaleLabel
} from '../core/Appearance';
import { SkillDoc } from '../core/SkillDoc';
import { I18N_LANGUAGES, I18nLanguage } from '../core/I18n';
import { I18nService } from '../service/I18n';
import { SkillStore } from '../service/SkillStore';
import { isOpenCodeBase, normalizeBaseUrl } from '../core/OpenCodeRules';
import {
  LOG_ERROR,
  LOG_INFO,
  LOG_WARN,
  ParsedEventLine,
  formatEventLine,
  parseEventLine
} from '../core/EventLog';
import { formatCrashRecord } from '../core/Diagnostics';
import { CrashLog } from '../service/CrashLog';
import { formatDateTime } from '../core/Device';
import { MemoryFile } from '../core/Memory';
import { SoulPreset, soulPresets } from '../core/Soul';
import {
  MAX_SUB_AGENTS,
  SubAgentDefinition,
  SUB_AGENT_DESCRIPTION_MAX,
  defaultAgents,
  normalizeAgentName,
  normalizeAgents
} from '../core/SubAgentRoster';
import { fetchModelIds, ModelsResult } from '../service/ChatApi';
import { AppLogger } from '../service/AppLogger';
import { MemoryStore } from '../service/MemoryStore';
import {
  UsageDayTotal,
  UsageModelTotal,
  UsageProviderTotal,
  usageByDay,
  usageByModel,
  usageByProvider,
  usageTotal
} from '../core/UsageStats';
import { UsageStore } from '../service/UsageStore';
import { DirUsage, clearDirectory, directoryUsage } from '../service/StorageUsage';
import { formatBytes } from '../core/BrowserHistory';
import { ConfigAuditEntry, auditValueLabel } from '../core/ConfigAudit';
import { formatTokens } from '../service/Format';
import {
  ClaudeLoginStart,
  CodexLoginStart,
  CopilotLoginStart,
  OAuthOutcome,
  OAuthService
} from '../service/OAuth';
import { COPILOT_API_BASE, DeviceAuthorization } from '../core/OAuth';
import {
  ModelOverride,
  OVERRIDE_INHERIT,
  isValidExtraBody,
  isValidExtraHeaders,
  normalizeModelOverrides,
  overrideSummary
} from '../core/ModelOverride';
import { McpServerConfig, normalizeMcpServers } from '../core/McpProtocol';
import {
  McpOAuthConfig,
  McpOAuthLoginStart,
  McpOAuthOutcome,
  emptyMcpOAuth,
  isMcpOAuthConfigured,
  normalizeMcpOAuth
} from '../core/McpOAuth';
import { McpRegistry, McpServerStatus } from '../service/McpRuntime';
import { McpOAuthService } from '../service/McpOAuth';
import {
  ANTHROPIC_DEFAULT_BASE,
  ANTHROPIC_DEFAULT_MODEL
} from '../core/AnthropicProtocol';
import {
  GEMINI_DEFAULT_BASE,
  GEMINI_DEFAULT_MODEL
} from '../core/GeminiProtocol';
import { CODEX_API_BASE } from '../core/ResponsesProtocol';
import { t } from '../core/I18n';

const COPILOT_DEFAULT_MODEL: string = 'gpt-4o';
const CODEX_DEFAULT_MODEL: string = 'gpt-5.5';

interface ToolChoice {
  name: string;
  label: string;
}

interface ThinkingChoice {
  value: ThinkingLevel;
  label: string;
}

/** Formatted viewer line plus the fields the filters need. */
interface LogRow {
  line: string;
  parsed: ParsedEventLine;
}

// Labels stay as source keys and are translated at render time, because
// module-level constants are evaluated before the catalog is loaded.
const THINKING_CHOICES: ThinkingChoice[] = [
  { value: 'off', label: '关闭' },
  { value: 'low', label: '低' },
  { value: 'medium', label: '中' },
  { value: 'high', label: '高' }
];

/**
 * Switches with their own settings (write access, memory, read_image) are not
 * repeated here; this list only covers individually disableable tools.
 */
const TOOL_CHOICES: ToolChoice[] = [
  { name: 'list_dir', label: '列目录' },
  { name: 'read_file', label: '读文件' },
  { name: 'search_text', label: '搜索文本' },
  { name: 'write_file', label: '写文件' },
  { name: 'file_edit', label: '精确编辑' },
  { name: 'shell_execute', label: 'Linux 沙箱' },
  { name: 'python_execute', label: 'Python 解释器' },
  { name: 'fetch_url', label: '抓取网页' },
  { name: 'now', label: '当前时间' },
  { name: 'subagent_task', label: '子代理' }
];

@Component
export struct SettingsSheet {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop settings: AppSettings = defaultSettings();
  onCancel: () => void = () => {
  };
  onSave: (settings: AppSettings) => void = (settings: AppSettings) => {
  };
  onToast: (message: string) => void = (message: string) => {
  };
  onBrowseWorkspace: () => void = () => {
  };
  /** Host builds and saves the diagnostics bundle (needs the session store). */
  onExportDiagnostics: () => void = () => {
  };
  /** Draft credentials are passed straight to the host; nothing is logged. */
  onUploadRemoteBackup: (url: string, user: string, password: string) => void =
    (url: string, user: string, password: string) => {
    };
  onSyncRemoteBackup: (url: string, user: string, password: string) => void =
    () => {
    };
  onDownloadRemoteBackup: (url: string, user: string, password: string) => void =
    (url: string, user: string, password: string) => {
    };
  /** Recent settings changes, newest first; host owns persistence. */
  @Prop auditEntries: ConfigAuditEntry[] = [];
  onRestoreAudit: (id: string) => void = (id: string) => {
  };
  onClearAudit: () => void = () => {
  };

  @State preset: ProviderPreset = 'opencode';
  @State baseUrl: string = OPENCODE_GO_BASE;
  @State apiKey: string = '';
  @State modelId: string = OPENCODE_DEFAULT_MODEL;
  /** Comma/newline separated fallback model ids. */
  @State fallbackText: string = '';
  @State systemPrompt: string = '';
  @State soulId: string = 'general';
  @State skills: SkillDoc[] = [];
  @State enabledSkills: string[] = [];
  @State temperature: number = 1.0;
  @State maxTokensText: string = '8192';
  @State showKey: boolean = false;
  @State probing: boolean = false;
  @State probeMessage: string = '';
  @State probeModels: string[] = [];
  @State toolsEnabled: boolean = true;
  @State allowWriteTools: boolean = false;
  @State confirmWriteTools: boolean = false;
  @State sandboxMode: SandboxMode = 'local';
  @State sandboxUrl: string = '';
  @State sandboxToken: string = '';
  @State probeRunning: boolean = false;
  @State probeReport: string = '';
  @State ishRunning: boolean = false;
  @State ishReport: string = '';
  @State language: string = 'zh-Hans';
  @State sandboxStatus: string = t('正在读取…');
  @State sandboxBytes: string = '';
  @State sandboxResetting: boolean = false;
  @State resetArmed: boolean = false;
  @State maxTurnsText: string = '200';
  @State contextBudgetText: string = '60000';
  @State autoCompact: boolean = true;
  @State autoCompactText: string = '80';
  @State loggingEnabled: boolean = false;
  @State memoryEnabled: boolean = false;
  @State imageToolsEnabled: boolean = false;
  @State imageGenEnabled: boolean = false;
  @State clipboardToolsEnabled: boolean = false;
  @State calendarToolsEnabled: boolean = false;
  @State contactsToolsEnabled: boolean = false;
  @State locationToolsEnabled: boolean = false;
  @State weatherToolsEnabled: boolean = false;
  @State backgroundEnabled: boolean = true;
  @State enterToSend: boolean = false;
  @State thinkingLevel: ThinkingLevel = 'off';
  @State appLockEnabled: boolean = false;
  @State accentColor: string = '#2F6BFF';
  @State fontScale: number = 1;
  @State messageFontScale: number = 1;
  @State inputFontScale: number = 1;
  @State autoExpandThinking: boolean = false;
  @State autoFocusInput: boolean = true;
  @State autoTitleEnabled: boolean = true;
  @State autoGroupingEnabled: boolean = true;
  /** Carried through the sheet untouched; toggled from the chat header. */
  @State fastMode: boolean = false;
  @State disabledTools: string[] = [];
  @State showLogs: boolean = false;
  @State logRows: LogRow[] = [];
  /** all / info / warn / error */
  @State logLevel: string = 'all';
  @State logEvent: string = 'all';
  @State logQuery: string = '';
  @State logTall: boolean = false;
  @State showCrashes: boolean = false;
  @State crashRows: string[] = [];
  @State usageTotalLine: string = '';
  @State usageModelLines: string[] = [];
  @State usageProviderLines: string[] = [];
  @State usageDayLines: string[] = [];
  @State storageLines: string[] = [];
  /** Which cleanup needs a second tap: attachments / workspace / downloads. */
  @State storageClear: string = '';
  @State showMemory: boolean = false;
  @State memoryFiles: MemoryFile[] = [];
  @State memoryIndex: number = 0;
  @State memoryText: string = '';
  @State modelOverrides: ModelOverride[] = [];
  @State editingOverride: boolean = false;
  @State ovIndex: number = -1;
  @State ovModelId: string = '';
  @State ovTemperatureText: string = '';
  @State ovTopPText: string = '';
  @State ovMaxTokensText: string = '';
  @State ovHeadersText: string = '';
  @State ovBodyText: string = '';
  @State mcpServers: McpServerConfig[] = [];
  @State editingMcp: boolean = false;
  @State mcpIndex: number = -1;
  @State mcpName: string = '';
  @State mcpUrl: string = '';
  @State mcpHeadersText: string = '';
  @State mcpEnabled: boolean = true;
  @State mcpRefreshing: boolean = false;
  @State mcpStatusText: string = '';
  @State mcpOAuthExpanded: boolean = false;
  @State mcpOAuthClientId: string = '';
  @State mcpOAuthAuthorizeUrl: string = '';
  @State mcpOAuthTokenUrl: string = '';
  @State mcpOAuthScopes: string = '';
  @State mcpOAuthRedirect: string = '';
  @State mcpOAuthResource: string = '';
  @State mcpOAuthSecret: string = '';
  /** Index of the saved server whose login panel is open; -1 closes it. */
  @State mcpOAuthIndex: number = -1;
  @State mcpOAuthLoggedIn: boolean = false;
  @State mcpOAuthMask: string = '';
  @State mcpOAuthVerifier: string = '';
  @State mcpOAuthState: string = '';
  @State mcpOAuthPaste: string = '';
  @State mcpOAuthBusy: boolean = false;
  @State mcpOAuthStatus: string = '';
  @State webDavUrl: string = '';
  @State webDavUser: string = '';
  @State webDavPassword: string = '';
  @State webDavAutoSync: boolean = false;
  @State webDavLastSyncAt: number = 0;
  @State showWebDavPassword: boolean = false;
  @State claudeLoggedIn: boolean = false;
  @State claudeMask: string = '';
  @State oauthExpanded: boolean = false;
  @State oauthBusy: boolean = false;
  @State oauthVerifier: string = '';
  @State oauthState: string = '';
  @State oauthPaste: string = '';
  @State copilotLoggedIn: boolean = false;
  @State copilotMask: string = '';
  @State copilotUserCode: string = '';
  @State copilotVerifyUri: string = '';
  @State copilotBusy: boolean = false;
  private copilotDevice: DeviceAuthorization | null = null;
  @State codexLoggedIn: boolean = false;
  @State codexMask: string = '';
  @State codexPlan: string = '';
  @State codexVerifier: string = '';
  @State codexState: string = '';
  @State subAgents: SubAgentDefinition[] = defaultAgents();
  @State agentEditing: boolean = false;
  @State agentIndex: number = -1;
  @State agentName: string = '';
  @State agentDescription: string = '';
  @State agentInstructions: string = '';

  aboutToAppear(): void {
    // UIContext is not attached yet during aboutToAppear; read status on the
    // first idle frame instead.
    setTimeout(() => this.refreshSandboxStatus(), 0);
    setTimeout(() => this.refreshUsage(), 0);
    this.language = I18nService.current();
    const copy: AppSettings = cloneSettings(this.settings);
    this.preset = copy.preset;
    this.baseUrl = copy.baseUrl;
    this.apiKey = copy.apiKey;
    this.modelId = copy.modelId;
    this.fallbackText = copy.fallbackModels.join(', ');
    this.systemPrompt = copy.systemPrompt;
    this.soulId = copy.soulId;
    this.enabledSkills = copy.enabledSkills.slice();
    this.skills = SkillStore.list();
    this.temperature = copy.temperature;
    this.maxTokensText = copy.maxTokens.toString();
    this.toolsEnabled = copy.toolsEnabled;
    this.allowWriteTools = copy.allowWriteTools;
    this.confirmWriteTools = copy.confirmWriteTools;
    this.sandboxMode = copy.sandboxMode;
    this.sandboxUrl = copy.sandboxUrl;
    this.sandboxToken = copy.sandboxToken;
    this.maxTurnsText = copy.maxAgentTurns.toString();
    this.contextBudgetText = copy.contextBudgetChars.toString();
    this.autoCompact = copy.autoCompact;
    this.autoCompactText = copy.autoCompactPercent.toString();
    this.loggingEnabled = copy.loggingEnabled;
    this.memoryEnabled = copy.memoryEnabled;
    this.imageToolsEnabled = copy.imageToolsEnabled;
    this.imageGenEnabled = copy.imageGenEnabled;
    this.clipboardToolsEnabled = copy.clipboardToolsEnabled;
    this.calendarToolsEnabled = copy.calendarToolsEnabled;
    this.contactsToolsEnabled = copy.contactsToolsEnabled;
    this.locationToolsEnabled = copy.locationToolsEnabled;
    this.weatherToolsEnabled = copy.weatherToolsEnabled;
    this.backgroundEnabled = copy.backgroundEnabled;
    this.enterToSend = copy.enterToSend;
    this.thinkingLevel = copy.thinkingLevel;
    this.appLockEnabled = copy.appLockEnabled;
    this.accentColor = copy.accentColor;
    this.fontScale = copy.fontScale;
    this.messageFontScale = copy.messageFontScale;
    this.inputFontScale = copy.inputFontScale;
    this.autoExpandThinking = copy.autoExpandThinking;
    this.autoFocusInput = copy.autoFocusInput;
    this.autoTitleEnabled = copy.autoTitleEnabled;
    this.autoGroupingEnabled = copy.autoGroupingEnabled;
    this.fastMode = copy.fastMode;
    this.disabledTools = copy.disabledTools.slice();
    this.modelOverrides = normalizeModelOverrides(copy.modelOverrides);
    this.mcpServers = normalizeMcpServers(copy.mcpServers);
    this.webDavUrl = copy.webDavUrl;
    this.webDavUser = copy.webDavUser;
    this.webDavPassword = copy.webDavPassword;
    this.webDavAutoSync = copy.webDavAutoSync;
    this.webDavLastSyncAt = copy.webDavLastSyncAt;
    this.claudeLoggedIn = OAuthService.hasClaudeToken();
    this.claudeMask = OAuthService.claudeMaskedToken();
    this.copilotLoggedIn = OAuthService.hasCopilotToken();
    this.copilotMask = OAuthService.copilotMaskedToken();
    this.codexLoggedIn = OAuthService.hasCodexToken();
    this.codexMask = OAuthService.codexMaskedToken();
    this.codexPlan = OAuthService.codexPlan();
    this.subAgents = normalizeAgents(copy.subAgents);
    this.agentEditing = false;
    this.agentIndex = -1;
  }

  private async startClaudeLogin(): Promise<void> {
    if (this.oauthBusy) {
      return;
    }
    this.oauthBusy = true;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const start: ClaudeLoginStart | null = await OAuthService.beginClaudeLogin(context);
    this.oauthBusy = false;
    if (start === null) {
      this.onToast(t('无法打开浏览器，请稍后重试'));
      return;
    }
    this.oauthVerifier = start.verifier;
    this.oauthState = start.state;
    this.oauthExpanded = true;
    this.onToast(t('已打开浏览器，完成授权后复制回调地址'));
  }

  private async completeClaudeLogin(): Promise<void> {
    if (this.oauthBusy) {
      return;
    }
    const pasted: string = this.oauthPaste.trim();
    if (pasted.length === 0) {
      this.onToast(t('请先粘贴回调地址或授权码'));
      return;
    }
    this.oauthBusy = true;
    const outcome: OAuthOutcome = await OAuthService.completeClaudeLogin(
      this.oauthVerifier, this.oauthState, pasted);
    this.oauthBusy = false;
    this.onToast(outcome.message);
    if (outcome.ok) {
      this.oauthPaste = '';
      this.oauthExpanded = false;
      this.claudeLoggedIn = OAuthService.hasClaudeToken();
      this.claudeMask = OAuthService.claudeMaskedToken();
      if (this.baseUrl.trim().length === 0 || this.isStockBase(this.baseUrl)) {
        this.baseUrl = ANTHROPIC_DEFAULT_BASE;
      }
    }
  }

  private async logoutClaude(): Promise<void> {
    await OAuthService.forgetClaude();
    this.claudeLoggedIn = false;
    this.claudeMask = '';
    this.oauthExpanded = false;
    this.oauthPaste = '';
    this.onToast(t('已退出 Claude 账号'));
  }

  private async startCodexLogin(): Promise<void> {
    if (this.oauthBusy) {
      return;
    }
    this.oauthBusy = true;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const start: CodexLoginStart | null = await OAuthService.beginCodexLogin(context);
    this.oauthBusy = false;
    if (start === null) {
      this.onToast(t('无法打开浏览器，请稍后重试'));
      return;
    }
    this.codexVerifier = start.verifier;
    this.codexState = start.state;
    this.oauthExpanded = true;
    this.onToast(t('已打开浏览器，完成授权后复制回调地址'));
  }

  private async completeCodexLogin(): Promise<void> {
    if (this.oauthBusy) {
      return;
    }
    const pasted: string = this.oauthPaste.trim();
    if (pasted.length === 0) {
      this.onToast(t('请先粘贴回调地址或授权码'));
      return;
    }
    this.oauthBusy = true;
    const outcome: OAuthOutcome = await OAuthService.completeCodexLogin(
      this.codexVerifier, this.codexState, pasted);
    this.oauthBusy = false;
    this.onToast(outcome.message);
    if (outcome.ok) {
      this.oauthPaste = '';
      this.oauthExpanded = false;
      this.codexLoggedIn = OAuthService.hasCodexToken();
      this.codexMask = OAuthService.codexMaskedToken();
      this.codexPlan = OAuthService.codexPlan();
      if (this.baseUrl.trim().length === 0 || this.isStockBase(this.baseUrl)) {
        this.baseUrl = CODEX_API_BASE;
      }
      if (this.isStockModel(this.modelId)) {
        this.modelId = CODEX_DEFAULT_MODEL;
      }
    }
  }

  private async logoutCodex(): Promise<void> {
    await OAuthService.forgetCodex();
    this.codexLoggedIn = false;
    this.codexMask = '';
    this.codexPlan = '';
    this.codexVerifier = '';
    this.codexState = '';
    this.oauthExpanded = false;
    this.oauthPaste = '';
    this.onToast(t('已退出 ChatGPT 账号'));
  }

  private async startCopilotLogin(): Promise<void> {
    if (this.copilotBusy) {
      return;
    }
    this.copilotBusy = true;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const start: CopilotLoginStart | null = await OAuthService.beginCopilotLogin(context);
    this.copilotBusy = false;
    if (start === null) {
      this.onToast(t('无法获取 GitHub 设备码，请稍后重试'));
      return;
    }
    this.copilotDevice = start.device;
    this.copilotUserCode = start.device.userCode;
    this.copilotVerifyUri = start.device.verificationUri;
    this.onToast(t('在浏览器中输入设备码完成授权'));
  }

  private async waitCopilotLogin(): Promise<void> {
    if (this.copilotBusy) {
      return;
    }
    const device: DeviceAuthorization | null = this.copilotDevice;
    if (device === null) {
      this.onToast(t('请先获取设备码'));
      return;
    }
    this.copilotBusy = true;
    const outcome: OAuthOutcome = await OAuthService.pollCopilotLogin(device);
    this.copilotBusy = false;
    this.onToast(outcome.message);
    if (outcome.ok) {
      this.copilotDevice = null;
      this.copilotUserCode = '';
      this.copilotVerifyUri = '';
      this.copilotLoggedIn = OAuthService.hasCopilotToken();
      this.copilotMask = OAuthService.copilotMaskedToken();
    }
  }

  private async logoutCopilot(): Promise<void> {
    await OAuthService.forgetCopilot();
    this.copilotLoggedIn = false;
    this.copilotMask = '';
    this.copilotUserCode = '';
    this.copilotVerifyUri = '';
    this.copilotDevice = null;
    this.onToast(t('已退出 GitHub Copilot'));
  }

  private toolEnabled(name: string): boolean {
    return this.disabledTools.indexOf(name) < 0;
  }

  private skillEnabled(id: string): boolean {
    return this.enabledSkills.indexOf(id) >= 0;
  }

  private setSkillEnabled(id: string, enabled: boolean): void {
    const next: string[] = [];
    for (let i = 0; i < this.enabledSkills.length; i++) {
      if (this.enabledSkills[i] !== id) {
        next.push(this.enabledSkills[i]);
      }
    }
    if (enabled) {
      next.push(id);
    }
    this.enabledSkills = next;
  }

  private async importSkill(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const message: string = await SkillStore.pickAndImport(context);
    this.skills = SkillStore.list();
    this.onToast(message);
  }

  private removeSkill(id: string): void {
    if (!SkillStore.remove(id)) {
      this.onToast(t('删除失败'));
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.enabledSkills.length; i++) {
      if (this.enabledSkills[i] !== id) {
        next.push(this.enabledSkills[i]);
      }
    }
    this.enabledSkills = next;
    this.skills = SkillStore.list();
    this.onToast(t('已删除技能'));
  }

  private setToolEnabled(name: string, enabled: boolean): void {
    const next: string[] = [];
    for (let i = 0; i < this.disabledTools.length; i++) {
      if (this.disabledTools[i] !== name) {
        next.push(this.disabledTools[i]);
      }
    }
    if (!enabled) {
      next.push(name);
    }
    this.disabledTools = next;
  }

  /** True when the field still holds one of the built-in preset values. */
  private isStockBase(value: string): boolean {
    const v: string = value.trim();
    return v.length === 0 || v === OPENCODE_GO_BASE ||
      v === ANTHROPIC_DEFAULT_BASE || v === GEMINI_DEFAULT_BASE ||
      v === COPILOT_API_BASE || v === CODEX_API_BASE;
  }

  private isStockModel(value: string): boolean {
    const v: string = value.trim();
    return v.length === 0 || v === OPENCODE_DEFAULT_MODEL ||
      v === ANTHROPIC_DEFAULT_MODEL || v === GEMINI_DEFAULT_MODEL ||
      v === COPILOT_DEFAULT_MODEL || v === CODEX_DEFAULT_MODEL;
  }

  private selectPreset(value: ProviderPreset): void {
    this.preset = value;
    if (value === 'opencode') {
      this.baseUrl = OPENCODE_GO_BASE;
      if (this.isStockModel(this.modelId)) {
        this.modelId = OPENCODE_DEFAULT_MODEL;
      }
    } else if (value === 'anthropic') {
      if (this.isStockBase(this.baseUrl)) {
        this.baseUrl = ANTHROPIC_DEFAULT_BASE;
      }
      if (this.isStockModel(this.modelId)) {
        this.modelId = ANTHROPIC_DEFAULT_MODEL;
      }
    } else if (value === 'gemini') {
      if (this.isStockBase(this.baseUrl)) {
        this.baseUrl = GEMINI_DEFAULT_BASE;
      }
      if (this.isStockModel(this.modelId)) {
        this.modelId = GEMINI_DEFAULT_MODEL;
      }
    } else if (value === 'copilot') {
      if (this.isStockBase(this.baseUrl)) {
        this.baseUrl = COPILOT_API_BASE;
      }
      if (this.isStockModel(this.modelId)) {
        this.modelId = COPILOT_DEFAULT_MODEL;
      }
    } else if (value === 'codex') {
      if (this.isStockBase(this.baseUrl)) {
        this.baseUrl = CODEX_API_BASE;
      }
      if (this.isStockModel(this.modelId)) {
        this.modelId = CODEX_DEFAULT_MODEL;
      }
    }
  }

  private maxTokensValue(): number {
    const parsed: number = Number(this.maxTokensText);
    if (Number.isNaN(parsed) || parsed <= 0) {
      return 8192;
    }
    return Math.floor(parsed);
  }

  /** Human-readable form of the budget that save() will actually store. */
  private budgetSummary(): string {
    const text: string = this.contextBudgetText.trim();
    if (text.length === 0) {
      return t('请输入字符数，范围 4000–2000000');
    }
    const raw: number = Number(text);
    if (Number.isNaN(raw) || !Number.isFinite(raw)) {
      return t('请输入数字，范围 4000–2000000');
    }
    const effective: number = clampContextBudget(raw);
    let summary: string = t('实际保存 ') + effective.toString() + t(' 字符');
    if (effective >= 10000) {
      const wan: number = Math.round(effective / 1000) / 10;
      summary += t('（约 ') + wan.toString() + t(' 万字符）');
    }
    if (Math.floor(raw) !== effective) {
      summary += t('，已按范围调整');
    }
    return summary;
  }

  private budgetAdjusted(): boolean {
    const text: string = this.contextBudgetText.trim();
    const raw: number = Number(text);
    if (text.length === 0 || Number.isNaN(raw) || !Number.isFinite(raw)) {
      return true;
    }
    return Math.floor(raw) !== clampContextBudget(raw);
  }

  private draftSettings(): AppSettings {
    const next: AppSettings = {
      preset: this.preset,
      baseUrl: normalizeBaseUrl(this.baseUrl),
      apiKey: this.apiKey.trim(),
      modelId: this.modelId.trim(),
      fallbackModels: parseModelList(this.fallbackText),
      systemPrompt: this.systemPrompt,
      soulId: this.soulId,
      temperature: this.temperature,
      maxTokens: this.maxTokensValue(),
      toolsEnabled: this.toolsEnabled,
      allowWriteTools: this.allowWriteTools,
      sandboxMode: this.sandboxMode,
      sandboxUrl: this.sandboxUrl.trim(),
      sandboxToken: this.sandboxToken.trim(),
      maxAgentTurns: clampMaxTurns(Number(this.maxTurnsText)),
      contextBudgetChars: clampContextBudget(Number(this.contextBudgetText)),
      autoCompact: this.autoCompact,
      autoCompactPercent: clampAutoCompactPercent(Number(this.autoCompactText)),
      loggingEnabled: this.loggingEnabled,
      memoryEnabled: this.memoryEnabled,
      imageToolsEnabled: this.imageToolsEnabled,
      imageGenEnabled: this.imageGenEnabled,
      clipboardToolsEnabled: this.clipboardToolsEnabled,
      calendarToolsEnabled: this.calendarToolsEnabled,
      contactsToolsEnabled: this.contactsToolsEnabled,
      locationToolsEnabled: this.locationToolsEnabled,
      weatherToolsEnabled: this.weatherToolsEnabled,
      confirmWriteTools: this.confirmWriteTools,
      backgroundEnabled: this.backgroundEnabled,
      thinkingLevel: this.thinkingLevel,
      enterToSend: this.enterToSend,
      disabledTools: this.disabledTools.slice(),
      onboardingDone: this.settings.onboardingDone,
      appLockEnabled: this.appLockEnabled,
      accentColor: this.accentColor,
      fontScale: this.fontScale,
      messageFontScale: this.messageFontScale,
      inputFontScale: this.inputFontScale,
      autoExpandThinking: this.autoExpandThinking,
      autoFocusInput: this.autoFocusInput,
      autoTitleEnabled: this.autoTitleEnabled,
      autoGroupingEnabled: this.autoGroupingEnabled,
      fastMode: this.fastMode,
      enabledSkills: this.enabledSkills.slice(),
      modelOverrides: normalizeModelOverrides(this.modelOverrides),
      mcpServers: normalizeMcpServers(this.mcpServers),
      webDavUrl: this.webDavUrl.trim(),
      webDavUser: this.webDavUser.trim(),
      webDavPassword: this.webDavPassword,
      webDavAutoSync: this.webDavAutoSync,
      webDavLastSyncAt: this.webDavLastSyncAt,
      sessionFolders: this.settings.sessionFolders !== undefined
        ? this.settings.sessionFolders
        : [],
      subAgents: normalizeAgents(this.subAgents)
    };
    return next;
  }

  private beginAgent(index: number): void {
    this.agentEditing = true;
    this.agentIndex = index;
    if (index >= 0 && index < this.subAgents.length) {
      const agent: SubAgentDefinition = this.subAgents[index];
      this.agentName = agent.name;
      this.agentDescription = agent.description;
      this.agentInstructions = agent.instructions;
    } else {
      this.agentIndex = -1;
      this.agentName = '';
      this.agentDescription = '';
      this.agentInstructions = '';
    }
  }

  private saveAgent(): void {
    const name: string = normalizeAgentName(this.agentName);
    if (name.length === 0) {
      this.onToast(t('名字只能包含小写字母、数字、- 和 _'));
      return;
    }
    for (let i = 0; i < this.subAgents.length; i++) {
      if (i !== this.agentIndex && this.subAgents[i].name === name) {
        this.onToast(t('已经有同名子代理：') + name);
        return;
      }
    }
    const agent: SubAgentDefinition = {
      id: this.agentIndex >= 0 && this.agentIndex < this.subAgents.length
        ? this.subAgents[this.agentIndex].id
        : util.generateRandomUUID(true),
      name: name,
      description: this.agentDescription.trim(),
      instructions: this.agentInstructions.trim(),
      builtIn: false
    };
    const list: SubAgentDefinition[] = this.subAgents.slice();
    if (this.agentIndex >= 0 && this.agentIndex < list.length) {
      list[this.agentIndex] = agent;
    } else {
      list.push(agent);
    }
    this.subAgents = normalizeAgents(list);
    this.agentEditing = false;
    this.agentIndex = -1;
  }

  private deleteAgent(index: number): void {
    if (index < 0 || index >= this.subAgents.length || this.subAgents[index].builtIn) {
      return;
    }
    const list: SubAgentDefinition[] = [];
    for (let i = 0; i < this.subAgents.length; i++) {
      if (i !== index) {
        list.push(this.subAgents[i]);
      }
    }
    this.subAgents = normalizeAgents(list);
    if (this.agentEditing) {
      this.agentEditing = false;
      this.agentIndex = -1;
    }
  }

  private beginOverride(index: number): void {
    if (this.editingOverride && index < 0) {
      this.editingOverride = false;
      return;
    }
    this.editingOverride = true;
    this.ovIndex = index;
    if (index >= 0 && index < this.modelOverrides.length) {
      const item: ModelOverride = this.modelOverrides[index];
      this.ovModelId = item.modelId;
      this.ovTemperatureText = item.temperature >= 0 ? item.temperature.toString() : '';
      this.ovTopPText = item.topP >= 0 ? item.topP.toString() : '';
      this.ovMaxTokensText = item.maxTokens > 0 ? item.maxTokens.toString() : '';
      this.ovHeadersText = item.extraHeaders;
      this.ovBodyText = item.extraBody;
    } else {
      this.ovIndex = -1;
      this.ovModelId = this.modelId.trim();
      this.ovTemperatureText = '';
      this.ovTopPText = '';
      this.ovMaxTokensText = '';
      this.ovHeadersText = '';
      this.ovBodyText = '';
    }
  }

  private parseOptionalNumber(text: string, min: number, max: number): number {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return OVERRIDE_INHERIT;
    }
    const value: number = Number(trimmed);
    if (Number.isNaN(value) || value < min || value > max) {
      return Number.NaN;
    }
    return value;
  }

  private saveOverride(): void {
    const id: string = this.ovModelId.trim();
    if (id.length === 0) {
      this.onToast(t('请填写模型 ID'));
      return;
    }
    if (!isValidExtraHeaders(this.ovHeadersText)) {
      this.onToast(t('请求头需为 JSON 对象，且每个值都是字符串'));
      return;
    }
    if (!isValidExtraBody(this.ovBodyText)) {
      this.onToast(t('附加请求体需为 JSON 对象'));
      return;
    }
    const temperature: number = this.parseOptionalNumber(this.ovTemperatureText, 0, 2);
    if (Number.isNaN(temperature)) {
      this.onToast(t('温度需在 0–2 之间，留空表示继承'));
      return;
    }
    const topP: number = this.parseOptionalNumber(this.ovTopPText, 0, 1);
    if (Number.isNaN(topP)) {
      this.onToast(t('top_p 需在 0–1 之间，留空表示不发送'));
      return;
    }
    const maxTokens: number = this.parseOptionalNumber(this.ovMaxTokensText, 1, 1000000);
    if (Number.isNaN(maxTokens)) {
      this.onToast(t('最大输出需为正整数，留空表示继承'));
      return;
    }
    const item: ModelOverride = {
      modelId: id,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens > 0 ? Math.floor(maxTokens) : 0,
      extraHeaders: this.ovHeadersText.trim(),
      extraBody: this.ovBodyText.trim()
    };
    const next: ModelOverride[] = [];
    for (let i = 0; i < this.modelOverrides.length; i++) {
      if (i === this.ovIndex) {
        next.push(item);
        continue;
      }
      if (this.modelOverrides[i].modelId === id) {
        continue;
      }
      next.push(this.modelOverrides[i]);
    }
    if (this.ovIndex < 0) {
      next.push(item);
    }
    this.modelOverrides = next;
    this.editingOverride = false;
  }

  private removeOverride(index: number): void {
    const next: ModelOverride[] = [];
    for (let i = 0; i < this.modelOverrides.length; i++) {
      if (i !== index) {
        next.push(this.modelOverrides[i]);
      }
    }
    this.modelOverrides = next;
    if (this.ovIndex === index) {
      this.editingOverride = false;
      this.ovIndex = -1;
    }
  }

  private beginMcp(index: number): void {
    if (this.editingMcp && index < 0) {
      this.editingMcp = false;
      return;
    }
    this.mcpOAuthSecret = '';
    if (index >= 0 && index < this.mcpServers.length) {
      const item: McpServerConfig = this.mcpServers[index];
      this.mcpIndex = index;
      this.mcpName = item.name;
      this.mcpUrl = item.url;
      this.mcpHeadersText = item.headers;
      this.mcpEnabled = item.enabled;
      const config: McpOAuthConfig = normalizeMcpOAuth(item.oauth);
      this.mcpOAuthExpanded = isMcpOAuthConfigured(config) || config.clientSecretSet;
      this.mcpOAuthClientId = config.clientId;
      this.mcpOAuthAuthorizeUrl = config.authorizationEndpoint;
      this.mcpOAuthTokenUrl = config.tokenEndpoint;
      this.mcpOAuthScopes = config.scopes;
      this.mcpOAuthRedirect = config.redirectUri;
      this.mcpOAuthResource = config.resource;
    } else {
      this.mcpIndex = -1;
      this.mcpName = '';
      this.mcpUrl = '';
      this.mcpHeadersText = '';
      this.mcpEnabled = true;
      this.mcpOAuthExpanded = false;
      this.mcpOAuthClientId = '';
      this.mcpOAuthAuthorizeUrl = '';
      this.mcpOAuthTokenUrl = '';
      this.mcpOAuthScopes = '';
      this.mcpOAuthRedirect = '';
      this.mcpOAuthResource = '';
    }
    this.editingMcp = true;
  }

  private draftMcpOAuth(): McpOAuthConfig {
    if (!this.mcpOAuthExpanded) {
      return emptyMcpOAuth();
    }
    const existingSecret: boolean = this.mcpIndex >= 0 &&
      this.mcpIndex < this.mcpServers.length &&
      this.mcpServers[this.mcpIndex].oauth.clientSecretSet;
    const secret: string = this.mcpOAuthSecret.trim();
    const draft: McpOAuthConfig = {
      mode: 'static',
      clientId: this.mcpOAuthClientId,
      authorizationEndpoint: this.mcpOAuthAuthorizeUrl,
      tokenEndpoint: this.mcpOAuthTokenUrl,
      scopes: this.mcpOAuthScopes,
      redirectUri: this.mcpOAuthRedirect,
      resource: this.mcpOAuthResource,
      clientSecretSet: secret.length > 0 || existingSecret
    };
    return normalizeMcpOAuth(draft);
  }

  private saveMcp(): void {
    const url: string = this.mcpUrl.trim();
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      this.onToast(t('MCP 地址需以 http:// 或 https:// 开头'));
      return;
    }
    if (!isValidExtraHeaders(this.mcpHeadersText)) {
      this.onToast(t('MCP 请求头需为 JSON 对象，且每个值都是字符串'));
      return;
    }
    const id: string = this.mcpIndex >= 0
      ? this.mcpServers[this.mcpIndex].id
      : util.generateRandomUUID(true);
    const oauth: McpOAuthConfig = this.draftMcpOAuth();
    const secret: string = this.mcpOAuthSecret.trim();
    if (secret.length > 0) {
      McpOAuthService.setClientSecret(id, secret);
      this.mcpOAuthSecret = '';
    } else if (!this.mcpOAuthExpanded) {
      // Turning OAuth off discards the stored client secret with it.
      McpOAuthService.setClientSecret(id, '');
    }
    const item: McpServerConfig = {
      id: id,
      name: this.mcpName.trim().length > 0 ? this.mcpName.trim() : url,
      url: url,
      headers: this.mcpHeadersText.trim(),
      enabled: this.mcpEnabled,
      oauth: oauth
    };
    const next: McpServerConfig[] = [];
    for (let i = 0; i < this.mcpServers.length; i++) {
      if (i === this.mcpIndex) {
        next.push(item);
      } else {
        next.push(this.mcpServers[i]);
      }
    }
    if (this.mcpIndex < 0) {
      next.push(item);
    }
    this.mcpServers = next;
    this.editingMcp = false;
    this.mcpOAuthIndex = -1;
    this.mcpStatusText = t('已保存，点「刷新」发现工具');
  }

  private removeMcp(index: number): void {
    const removedId: string = index >= 0 && index < this.mcpServers.length
      ? this.mcpServers[index].id
      : '';
    const next: McpServerConfig[] = [];
    for (let i = 0; i < this.mcpServers.length; i++) {
      if (i !== index) {
        next.push(this.mcpServers[i]);
      }
    }
    this.mcpServers = next;
    if (this.mcpIndex === index) {
      this.editingMcp = false;
      this.mcpIndex = -1;
    }
    if (this.mcpOAuthIndex === index) {
      this.mcpOAuthIndex = -1;
    } else if (this.mcpOAuthIndex > index) {
      this.mcpOAuthIndex--;
    }
    if (removedId.length > 0) {
      McpOAuthService.purge(removedId);
    }
  }

  private setMcpEnabled(index: number, enabled: boolean): void {
    const next: McpServerConfig[] = [];
    for (let i = 0; i < this.mcpServers.length; i++) {
      const item: McpServerConfig = this.mcpServers[i];
      next.push({
        id: item.id,
        name: item.name,
        url: item.url,
        headers: item.headers,
        enabled: i === index ? enabled : item.enabled,
        oauth: item.oauth
      });
    }
    this.mcpServers = next;
  }

  private openMcpOAuth(index: number): void {
    if (index < 0 || index >= this.mcpServers.length) {
      return;
    }
    this.mcpOAuthIndex = index;
    this.mcpOAuthPaste = '';
    this.mcpOAuthVerifier = '';
    this.mcpOAuthState = '';
    this.mcpOAuthStatus = '';
    const server: McpServerConfig = this.mcpServers[index];
    McpOAuthService.maskedToken(server.id).then((mask: string) => {
      if (this.mcpOAuthIndex !== index) {
        return;
      }
      this.mcpOAuthMask = mask;
      this.mcpOAuthLoggedIn = mask.length > 0;
    });
  }

  private async startMcpOAuthLogin(): Promise<void> {
    if (this.mcpOAuthBusy || this.mcpOAuthIndex < 0 ||
      this.mcpOAuthIndex >= this.mcpServers.length) {
      return;
    }
    const server: McpServerConfig = this.mcpServers[this.mcpOAuthIndex];
    if (!isMcpOAuthConfigured(server.oauth)) {
      this.onToast(t('请先在编辑页填写 Client ID 与授权/令牌端点'));
      return;
    }
    this.mcpOAuthBusy = true;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const start: McpOAuthLoginStart | null =
      await McpOAuthService.beginLogin(context, server);
    this.mcpOAuthBusy = false;
    if (start === null) {
      this.onToast(t('无法打开浏览器，请稍后重试'));
      return;
    }
    this.mcpOAuthVerifier = start.verifier;
    this.mcpOAuthState = start.state;
    this.mcpOAuthStatus = t('已在浏览器打开授权页，完成后把回调地址粘贴到下方');
  }

  private async completeMcpOAuthLogin(): Promise<void> {
    if (this.mcpOAuthBusy || this.mcpOAuthIndex < 0 ||
      this.mcpOAuthIndex >= this.mcpServers.length) {
      return;
    }
    const pasted: string = this.mcpOAuthPaste.trim();
    if (pasted.length === 0) {
      this.onToast(t('请先粘贴回调地址或授权码'));
      return;
    }
    const server: McpServerConfig = this.mcpServers[this.mcpOAuthIndex];
    this.mcpOAuthBusy = true;
    const outcome: McpOAuthOutcome = await McpOAuthService.completeLogin(
      server, this.mcpOAuthVerifier, this.mcpOAuthState, pasted);
    this.mcpOAuthBusy = false;
    this.mcpOAuthStatus = outcome.message;
    if (outcome.ok) {
      const mask: string = await McpOAuthService.maskedToken(server.id);
      this.mcpOAuthLoggedIn = mask.length > 0;
      this.mcpOAuthMask = mask;
      this.mcpOAuthVerifier = '';
      this.mcpOAuthState = '';
      this.mcpOAuthPaste = '';
      this.refreshMcp();
    }
  }

  private async logoutMcpOAuth(): Promise<void> {
    if (this.mcpOAuthIndex < 0 || this.mcpOAuthIndex >= this.mcpServers.length) {
      return;
    }
    const server: McpServerConfig = this.mcpServers[this.mcpOAuthIndex];
    await McpOAuthService.signOut(server.id);
    this.mcpOAuthLoggedIn = false;
    this.mcpOAuthMask = '';
    this.mcpOAuthVerifier = '';
    this.mcpOAuthState = '';
    this.mcpOAuthPaste = '';
    this.mcpOAuthStatus = t('已退出 MCP OAuth');
    this.refreshMcp();
  }

  private async refreshMcp(): Promise<void> {
    if (this.mcpRefreshing) {
      return;
    }
    this.mcpRefreshing = true;
    try {
      const statuses: McpServerStatus[] = await McpRegistry.refresh(
        normalizeMcpServers(this.mcpServers), true);
      if (statuses.length === 0) {
        this.mcpStatusText = t('没有启用的 MCP 服务');
      } else {
        const parts: string[] = [];
        for (let i = 0; i < statuses.length; i++) {
          const status: McpServerStatus = statuses[i];
          if (status.error.length > 0) {
            parts.push(status.serverName + t('：') + status.error);
          } else {
            parts.push(status.serverName + t('：') + status.toolCount.toString() + t(' 个工具'));
          }
        }
        this.mcpStatusText = parts.join('\n');
      }
    } finally {
      this.mcpRefreshing = false;
    }
  }

  private filesDir(): string {
    return (getContext(this) as common.UIAbilityContext).filesDir;
  }

  private presetLabel(preset: string): string {
    if (preset === 'opencode') {
      return 'OpenCode Go';
    }
    if (preset === 'anthropic') {
      return 'Anthropic';
    }
    if (preset === 'gemini') {
      return 'Gemini';
    }
    if (preset === 'copilot') {
      return 'GitHub Copilot';
    }
    if (preset === 'codex') {
      return 'ChatGPT Codex';
    }
    return preset === 'custom' ? t('自定义') : t('未知供应商');
  }

  /** Recompute the usage rollups and the three storage buckets. */
  private refreshUsage(): void {
    const records = UsageStore.load(getContext(this) as common.UIAbilityContext);
    const total = usageTotal(records);
    this.usageTotalLine = t('累计 ') +
      formatTokens(total.prompt + total.completion) + ' tokens · ' +
      t('输入 ') + formatTokens(total.prompt) + ' · ' +
      t('输出 ') + formatTokens(total.completion) + ' · ' +
      total.requests.toString() + t(' 次请求');
    const models: UsageModelTotal[] = usageByModel(records);
    const modelLines: string[] = [];
    for (let i = 0; i < models.length && i < 5; i++) {
      const item: UsageModelTotal = models[i];
      modelLines.push(item.model + ' · ' +
        formatTokens(item.prompt + item.completion) + ' tokens · ' +
        item.requests.toString() + t(' 次'));
    }
    this.usageModelLines = modelLines;
    const providers: UsageProviderTotal[] = usageByProvider(records);
    const providerLines: string[] = [];
    for (let i = 0; i < providers.length; i++) {
      const item: UsageProviderTotal = providers[i];
      providerLines.push(this.presetLabel(item.preset) + ' · ' +
        formatTokens(item.prompt + item.completion) + ' tokens · ' +
        item.requests.toString() + t(' 次'));
    }
    this.usageProviderLines = providerLines;
    const days: UsageDayTotal[] = usageByDay(records, 7);
    const dayLines: string[] = [];
    for (let i = 0; i < days.length; i++) {
      const item: UsageDayTotal = days[i];
      dayLines.push(item.date + ' · ' +
        formatTokens(item.prompt + item.completion) + ' tokens · ' +
        item.requests.toString() + t(' 次'));
    }
    this.usageDayLines = dayLines;
    this.refreshStorage();
  }

  private refreshStorage(): void {
    const root: string = this.filesDir();
    const attachments: DirUsage = directoryUsage(root + '/attachments');
    const workspace: DirUsage = directoryUsage(root + '/workspace');
    const downloads: DirUsage = directoryUsage(root + '/browser-downloads');
    this.storageLines = [
      t('附件：') + attachments.files.toString() + t(' 个 · ') +
        formatBytes(attachments.bytes),
      t('工作区：') + workspace.files.toString() + t(' 个 · ') +
        formatBytes(workspace.bytes),
      t('浏览器下载：') + downloads.files.toString() + t(' 个 · ') +
        formatBytes(downloads.bytes)
    ];
  }

  /** Two-tap cleanup; the second tap removes the bucket's contents. */
  private clearStorage(target: string): void {
    if (this.storageClear !== target) {
      this.storageClear = target;
      this.onToast(t('再点一次确认清理；此操作不可撤销'));
      return;
    }
    this.storageClear = '';
    const root: string = this.filesDir();
    let path: string = root + '/attachments';
    if (target === 'workspace') {
      path = root + '/workspace';
    } else if (target === 'downloads') {
      path = root + '/browser-downloads';
    }
    const removed: number = clearDirectory(path);
    this.refreshStorage();
    this.onToast(removed > 0
      ? t('已清理 ') + removed.toString() + t(' 个文件')
      : t('没有可清理的文件'));
  }

  private clearUsage(): void {
    if (this.storageClear !== 'usage') {
      this.storageClear = 'usage';
      this.onToast(t('再点一次确认清空用量统计'));
      return;
    }
    this.storageClear = '';
    UsageStore.clear(getContext(this) as common.UIAbilityContext);
    this.refreshUsage();
    this.onToast(t('已清空用量统计'));
  }

  /** Two-tap clear for the settings audit list. */
  private clearAudit(): void {
    if (this.storageClear !== 'audit') {
      this.storageClear = 'audit';
      this.onToast(t('再点一次确认清空配置变更记录'));
      return;
    }
    this.storageClear = '';
    this.onClearAudit();
  }

  private clearLogs(): void {
    const removed: number = AppLogger.clear();
    this.logRows = [];
    this.showLogs = false;
    this.crashRows = [];
    this.showCrashes = false;
    this.onToast(removed > 0 ? t('已删除 ') + removed.toString() + t(' 个日志文件') : t('没有可删除的日志文件'));
  }

  private loadMemory(): void {
    if (this.showMemory) {
      this.showMemory = false;
      return;
    }
    this.memoryFiles = MemoryStore.editable();
    this.memoryIndex = 0;
    this.memoryText = this.memoryFiles.length > 0 ? this.memoryFiles[0].text : '';
    this.showMemory = true;
  }

  private selectMemory(index: number): void {
    if (index < 0 || index >= this.memoryFiles.length) {
      return;
    }
    this.memoryIndex = index;
    this.memoryText = this.memoryFiles[index].text;
  }

  private saveMemory(): void {
    if (this.memoryFiles.length === 0) {
      return;
    }
    const name: string = this.memoryFiles[this.memoryIndex].name;
    const result: string = MemoryStore.saveText(name, this.memoryText);
    this.onToast(result);
    if (!result.startsWith(t('已保存'))) {
      return;
    }
    const reloaded: MemoryFile[] = MemoryStore.editable();
    this.memoryFiles = reloaded;
    for (let i = 0; i < reloaded.length; i++) {
      if (reloaded[i].name === name) {
        this.memoryIndex = i;
        this.memoryText = reloaded[i].text;
        break;
      }
    }
  }

  private loadLogs(): void {
    if (this.showLogs) {
      this.showLogs = false;
      return;
    }
    const raw: string[] = AppLogger.recent(300);
    const rows: LogRow[] = [];
    for (let i = 0; i < raw.length; i++) {
      rows.push({ line: formatEventLine(raw[i]), parsed: parseEventLine(raw[i]) });
    }
    this.logRows = rows;
    this.logLevel = 'all';
    this.logEvent = 'all';
    this.logQuery = '';
    this.showLogs = true;
  }

  private logLevelLabel(value: string): string {
    if (value === LOG_INFO) {
      return t('信息');
    }
    if (value === LOG_WARN) {
      return t('警告');
    }
    if (value === LOG_ERROR) {
      return t('错误');
    }
    return t('全部');
  }

  /** `all` plus every event name present in the current page of logs. */
  private logEventChoices(): string[] {
    const choices: string[] = ['all'];
    for (let i = 0; i < this.logRows.length; i++) {
      const name: string = this.logRows[i].parsed.event;
      if (name.length > 0 && choices.indexOf(name) < 0) {
        choices.push(name);
      }
    }
    return choices;
  }

  private filteredLogRows(): LogRow[] {
    const keyword: string = this.logQuery.trim().toLowerCase();
    const result: LogRow[] = [];
    for (let i = 0; i < this.logRows.length; i++) {
      const row: LogRow = this.logRows[i];
      if (this.logLevel !== 'all' && row.parsed.level !== this.logLevel) {
        continue;
      }
      if (this.logEvent !== 'all' && row.parsed.event !== this.logEvent) {
        continue;
      }
      if (keyword.length > 0 && row.line.toLowerCase().indexOf(keyword) < 0) {
        continue;
      }
      result.push(row);
    }
    return result;
  }

  private copyText(text: string, toast: string): void {
    if (text.length === 0) {
      this.onToast(t('没有可复制的内容'));
      return;
    }
    const data: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      text
    );
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.onToast(toast);
    }).catch((error: Error) => {
      this.onToast(t('复制失败'));
    });
  }

  private copyVisibleLogs(): void {
    const rows: LogRow[] = this.filteredLogRows();
    const lines: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      lines.push(rows[i].line);
    }
    this.copyText(lines.join('\n'), t('已复制 ') + lines.length.toString() + t(' 条日志'));
  }

  private toggleCrashes(): void {
    if (this.showCrashes) {
      this.showCrashes = false;
      return;
    }
    const raw: string[] = CrashLog.recent(20);
    const rows: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      rows.push(formatCrashRecord(raw[i]));
    }
    this.crashRows = rows;
    this.showCrashes = true;
  }

  private copyCrashes(): void {
    this.copyText(this.crashRows.join('\n\n'), t('已复制崩溃记录'));
  }

  private clearMemory(): void {
    const removed: number = MemoryStore.clearDaily();
    this.onToast(removed > 0 ? t('已清空 ') + removed.toString() + t(' 个记忆文件') : t('没有可清空的记忆'));
  }

  private async runSandboxProbe(): Promise<void> {
    if (this.probeRunning) {
      return;
    }
    this.probeRunning = true;
    this.probeReport = t('正在启动原生子进程…');
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.probeReport = await SandboxProbe.run(context);
    } catch (e) {
      const error: Error = e as Error;
      this.probeReport = t('自检失败：') + error.message;
    }
    this.probeRunning = false;
  }

  private copyProbeReport(): void {
    const data: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      this.probeReport
    );
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.onToast(t('已复制自检结果'));
    }).catch((error: Error) => {
      this.onToast(t('复制失败'));
    });
  }

  /** Reads the local status without booting the kernel. */
  private refreshSandboxStatus(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const status: SandboxStatus = SandboxIsh.status(context);
      if (status.ready) {
        this.sandboxStatus = status.running
          ? t('已启动，内核常驻')
          : t('已就绪，用到时启动内核');
      } else if (status.version.length > 0) {
        this.sandboxStatus = t('需要重新解压（旧版本 ') + status.version + t('）');
      } else {
        this.sandboxStatus = t('尚未解压，首次使用约需十几秒');
      }
      this.sandboxBytes = status.bytes > 0 ? SandboxIsh.formatBytes(status.bytes) : '';
    } catch (e) {
      this.sandboxStatus = t('无法读取沙箱目录');
      this.sandboxBytes = '';
    }
  }

  private async resetSandbox(): Promise<void> {
    if (this.sandboxResetting) {
      return;
    }
    if (!this.resetArmed) {
      this.resetArmed = true;
      this.onToast(t('再点一次确认删除已解压的 rootfs'));
      setTimeout(() => {
        this.resetArmed = false;
      }, 4000);
      return;
    }
    this.resetArmed = false;
    this.sandboxResetting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const ok: boolean = await SandboxIsh.reset(context);
      this.ishReport = '';
      this.onToast(ok ? t('已重置，下次使用沙箱时重新解压') : t('沙箱正在执行命令，稍后再试'));
    } catch (e) {
      const error: Error = e as Error;
      this.onToast(t('重置失败：') + error.message);
    }
    this.sandboxResetting = false;
    this.refreshSandboxStatus();
  }

  private async runIshSmoke(): Promise<void> {
    if (this.ishRunning) {
      return;
    }
    this.ishRunning = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const status: SandboxStatus = SandboxIsh.status(context);
      // decompressFile has no progress callback; at least tell the user when
      // the wait is the one-time extraction rather than the kernel boot.
      this.ishReport = status.ready
        ? t('正在启动 iSH 内核…')
        : t('首次使用：正在解压 rootfs（约 50 MB），可能需要几十秒…');
      const options: SandboxOptions = {
        workspace: context.filesDir + '/workspace',
        memory: context.filesDir + '/memory',
        attachments: context.filesDir + '/attachments',
        skills: context.filesDir + '/skills'
      };
      const result: SandboxRunResult = await SandboxIsh.run(context,
        'echo hello-from-ish; uname -a; id; cat /etc/alpine-release', 180000, options);
      const exit: string = '[exit=' + result.exitCode.toString() + ']';
      this.ishReport = result.error.length > 0
        ? result.error + '\n' + result.output + '\n' + exit
        : result.output + '\n' + exit;
    } catch (e) {
      const error: Error = e as Error;
      this.ishReport = t('沙箱启动失败：') + error.message;
    }
    this.ishRunning = false;
    this.refreshSandboxStatus();
  }

  private copyIshReport(): void {
    const data: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      this.ishReport
    );
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.onToast(t('已复制沙箱输出'));
    }).catch((error: Error) => {
      this.onToast(t('复制失败'));
    });
  }

  private async probe(): Promise<void> {
    if (this.probing) {
      return;
    }
    this.probing = true;
    this.probeMessage = t('正在连接…');
    const draft: AppSettings = this.draftSettings();
    if (draft.preset === 'anthropic') {
      draft.oauthToken = await OAuthService.validClaudeToken();
    } else if (draft.preset === 'copilot') {
      draft.oauthToken = await OAuthService.validCopilotSessionToken();
    } else if (draft.preset === 'codex') {
      draft.oauthToken = await OAuthService.validCodexToken();
      draft.oauthAccountId = OAuthService.codexAccountId();
    }
    const result: ModelsResult = await fetchModelIds(draft);
    this.probing = false;
    this.probeMessage = result.message;
    if (result.ok && result.models.length > 0) {
      this.probeModels = result.models;
    }
    this.onToast(result.message);
  }

  private save(): void {
    const next: AppSettings = this.draftSettings();
    if (next.baseUrl.length === 0) {
      this.probeMessage = t('API 地址不能为空');
      return;
    }
    if (next.modelId.length === 0) {
      this.probeMessage = t('模型 ID 不能为空');
      return;
    }
    if (next.toolsEnabled && next.sandboxMode === 'remote') {
      if (next.sandboxUrl.length === 0) {
        this.probeMessage = t('远程沙箱地址不能为空');
        return;
      }
      if (!next.sandboxUrl.startsWith('http://') &&
        !next.sandboxUrl.startsWith('https://')) {
        this.probeMessage = t('远程沙箱地址必须以 http:// 或 https:// 开头');
        return;
      }
    }
    this.onSave(next);
  }

  @Builder
  claudeOAuthCard() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(this.claudeLoggedIn ? t('已登录 Claude 账号') : t('Claude 账号登录（Pro / Max）'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.claudeLoggedIn) {
          Text(t('退出'))
            .fontSize(11)
            .fontColor($r('app.color.danger'))
            .padding({ left: 6, right: 2 })
            .onClick(() => {
              this.logoutClaude();
            })
        }
      }
      .width('100%')

      if (this.claudeLoggedIn) {
        Text(t('令牌 ') + this.claudeMask)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Text(t('登录态保存在系统 Asset Store；API Key 保持清空即可使用该账号。'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else {
        Text(t('浏览器完成授权后，回调会停在 localhost:54545，复制地址栏里的完整地址粘贴回来。'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        if (this.oauthExpanded) {
          TextInput({ text: this.oauthPaste, placeholder: t('http://localhost:54545/callback?code=…') })
            .width('100%')
            .height(42)
            .fontSize(12)
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .onChange((value: string) => {
              this.oauthPaste = value;
            })
          Row({ space: 8 }) {
            Button(this.oauthBusy ? t('登录中…') : t('完成登录'))
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .borderRadius(10)
              .enabled(!this.oauthBusy)
              .onClick(() => {
                this.completeClaudeLogin();
              })
            Button(t('重新打开'))
              .height(38)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(10)
              .enabled(!this.oauthBusy)
              .onClick(() => {
                this.startClaudeLogin();
              })
          }
          .width('100%')
        } else {
          Button(this.oauthBusy ? t('正在打开…') : t('打开浏览器登录'))
            .width('100%')
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .enabled(!this.oauthBusy)
            .onClick(() => {
              this.startClaudeLogin();
            })
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  copilotOAuthCard() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(this.copilotLoggedIn ? t('已登录 GitHub Copilot') : t('GitHub Copilot 登录'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.copilotLoggedIn) {
          Text(t('退出'))
            .fontSize(11)
            .fontColor($r('app.color.danger'))
            .padding({ left: 6, right: 2 })
            .onClick(() => {
              this.logoutCopilot();
            })
        }
      }
      .width('100%')

      Text(t('非官方接入：GitHub 未公开该接口，账号风控风险由使用者自行承担。'))
        .fontSize(10)
        .fontColor($r('app.color.danger'))
        .width('100%')

      if (this.copilotLoggedIn) {
        Text(t('GitHub 令牌 ') + this.copilotMask)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else if (this.copilotUserCode.length > 0) {
        Text(t('设备码：') + this.copilotUserCode)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(t('在浏览器打开 ') + this.copilotVerifyUri + t(' 并输入上面的设备码，然后点下方按钮。'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Row({ space: 8 }) {
          Button(this.copilotBusy ? t('等待授权…') : t('我已授权，继续'))
            .layoutWeight(1)
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(10)
            .enabled(!this.copilotBusy)
            .onClick(() => {
              this.waitCopilotLogin();
            })
          Button(t('重新获取'))
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .enabled(!this.copilotBusy)
            .onClick(() => {
              this.startCopilotLogin();
            })
        }
        .width('100%')
      } else {
        Button(this.copilotBusy ? t('正在获取…') : t('使用 GitHub 登录'))
          .width('100%')
          .height(38)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .enabled(!this.copilotBusy)
          .onClick(() => {
            this.startCopilotLogin();
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  codexOAuthCard() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(this.codexLoggedIn ? t('已登录 ChatGPT 账号') : t('ChatGPT 账号登录（Plus / Pro）'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.codexLoggedIn) {
          Text(t('退出'))
            .fontSize(11)
            .fontColor($r('app.color.danger'))
            .padding({ left: 6, right: 2 })
            .onClick(() => {
              this.logoutCodex();
            })
        }
      }
      .width('100%')

      if (this.codexLoggedIn) {
        Text(t('令牌 ') + this.codexMask)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        if (this.codexPlan.length > 0) {
          Text(t('订阅：') + this.codexPlan)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        Text(t('走 Codex Responses API；登录态保存在系统 Asset Store，API Key 保持清空即可。'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else {
        Text(t('浏览器完成授权后，回调会停在 localhost:1455，复制地址栏里的完整地址粘贴回来。'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        if (this.oauthExpanded) {
          TextInput({ text: this.oauthPaste, placeholder: t('http://localhost:1455/auth/callback?code=…') })
            .width('100%')
            .height(42)
            .fontSize(12)
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .onChange((value: string) => {
              this.oauthPaste = value;
            })
          Row({ space: 8 }) {
            Button(this.oauthBusy ? t('登录中…') : t('完成登录'))
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .borderRadius(10)
              .enabled(!this.oauthBusy)
              .onClick(() => {
                this.completeCodexLogin();
              })
            Button(t('重新打开'))
              .height(38)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(10)
              .enabled(!this.oauthBusy)
              .onClick(() => {
                this.startCodexLogin();
              })
          }
          .width('100%')
        } else {
          Button(this.oauthBusy ? t('正在打开…') : t('打开浏览器登录'))
            .width('100%')
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .enabled(!this.oauthBusy)
            .onClick(() => {
              this.startCodexLogin();
            })
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sectionTitle(title: string, subtitle: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  presetCard(name: string, desc: string, value: ProviderPreset) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.preset === value) {
          Text('✓')
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
      }
      Text(desc)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(2)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.preset === value ? $r('app.color.accent_soft') : $r('app.color.surface_alt'))
    .border({ width: 1, color: this.preset === value ? $r('app.color.accent') : $r('app.color.border') })
    .onClick(() => this.selectPreset(value))
  }

  @Builder
  sandboxCard(name: string, desc: string, value: SandboxMode) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.sandboxMode === value) {
          Text('✓')
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
      }
      Text(desc)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(2)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(11)
    .borderRadius(11)
    .backgroundColor(this.sandboxMode === value ? $r('app.color.accent_soft') : $r('app.color.surface_alt'))
    .border({ width: 1, color: this.sandboxMode === value ? $r('app.color.accent') : $r('app.color.border') })
    .onClick(() => {
      this.sandboxMode = value;
    })
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ bottom: 5 })
  }

  @Builder
  infoCard() {
    Row({ space: 10 }) {
      Text('S')
        .width(26)
        .height(26)
        .borderRadius(13)
        .textAlign(TextAlign.Center)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.surface'))
      Column({ space: 3 }) {
        Text(isOpenCodeBase(this.baseUrl) ? t('会话头已自动启用') : t('当前地址不发送会话头'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(isOpenCodeBase(this.baseUrl)
          ? t('每个对话使用固定 UUID，作为 x-opencode-session 随请求发送，用于上游路由与缓存。')
          : t('只有 opencode.ai 域名会附加 x-opencode-session，避免把会话标识泄露给自定义中转。'))
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(16)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(12)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  deviceToggleRow(title: string, description: string, value: boolean,
    apply: (next: boolean) => void, available: boolean) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
        Text(description)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .lineHeight(14)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (available) {
        Toggle({ type: ToggleType.Switch, isOn: value })
          .selectedColor($r('app.color.accent'))
          .onChange((next: boolean) => apply(next))
      } else {
        Text(t('暂不可用'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(11)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => this.onCancel())

      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text(t('设置'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(t('OpenAI 兼容接口 · OpenCode Go 预设'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('✕')
            .fontSize(18)
            .fontColor($r('app.color.text_secondary'))
            .padding(6)
            .onClick(() => this.onCancel())
        }
        .width('100%')
        .margin({ bottom: 14 })

        Scroll() {
          Column({ space: 16 }) {
            this.sectionTitle(t('语言'), t('界面文案立即切换；已保存的会话内容保持原文'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(I18N_LANGUAGES, (language: I18nLanguage) => {
                Text(language.label)
                  .fontSize(10)
                  .fontColor(this.language === language.code
                    ? $r('app.color.accent')
                    : $r('app.color.text_secondary'))
                  .padding({ left: 9, right: 9, top: 6, bottom: 6 })
                  .margin(3)
                  .backgroundColor(this.language === language.code
                    ? $r('app.color.accent_soft')
                    : $r('app.color.surface_alt'))
                  .borderRadius(7)
                  .onClick(() => {
                    const context: common.UIAbilityContext =
                      getContext(this) as common.UIAbilityContext;
                    I18nService.setLanguage(context, language.code);
                    this.language = language.code;
                    this.onToast(t('语言已切换'));
                    // Index watches i18nVersion and rebuilds the whole page
                    // subtree, so no restart is needed here.
                  })
              }, (language: I18nLanguage) => language.code)
            }
            .width('100%')

            this.sectionTitle(t('服务商'), t('OpenCode Go 用订阅 Key；Anthropic / Gemini 走原生协议；自定义接任意 OpenAI 兼容服务'))
            Column({ space: 10 }) {
              Row({ space: 10 }) {
                this.presetCard('OpenCode Go', t('自动填写当前基址，注入会话头'), 'opencode')
                this.presetCard('Anthropic', t('原生 Messages API 与工具调用'), 'anthropic')
              }
              .width('100%')
              Row({ space: 10 }) {
                this.presetCard('Gemini', t('原生 generateContent 与函数调用'), 'gemini')
                this.presetCard(t('自定义'), t('自建中转 / 其他兼容服务'), 'custom')
              }
              .width('100%')
              Row({ space: 10 }) {
                this.presetCard('GitHub Copilot', t('设备码登录 · 非官方接入'), 'copilot')
                this.presetCard('ChatGPT Codex', t('账号登录 · Responses API'), 'codex')
              }
              .width('100%')
            }
            .width('100%')

            Column() {
              this.fieldLabel(t('API 地址'))
              TextInput({ text: this.baseUrl, placeholder: OPENCODE_GO_BASE })
                .width('100%')
                .height(42)
                .fontSize(13)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onChange((value: string) => {
                  this.baseUrl = value;
                })
              Text(t('推理：') + normalizeBaseUrl(this.baseUrl) + '/chat/completions')
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 4 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.fieldLabel('API Key')
              Row({ space: 8 }) {
                TextInput({ text: this.apiKey, placeholder: t('在 OpenCode Console 的 Go 订阅页复制') })
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .type(this.showKey ? InputType.Normal : InputType.Password)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(10)
                  .onChange((value: string) => {
                    this.apiKey = value;
                  })
                Text(this.showKey ? t('隐藏') : t('显示'))
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
                  .padding({ left: 4, right: 4 })
                  .onClick(() => {
                    this.showKey = !this.showKey;
                  })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            if (this.preset === 'anthropic') {
              this.claudeOAuthCard()
            }
            if (this.preset === 'copilot') {
              this.copilotOAuthCard()
            }
            if (this.preset === 'codex') {
              this.codexOAuthCard()
            }

            Column() {
              this.fieldLabel(t('模型 ID'))
              Row({ space: 8 }) {
                TextInput({ text: this.modelId, placeholder: 'kimi-k3' })
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(10)
                  .onChange((value: string) => {
                    this.modelId = value;
                  })
                Button(this.probing ? t('…') : t('获取'))
                  .height(42)
                  .fontSize(12)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.accent_soft'))
                  .borderRadius(10)
                  .enabled(!this.probing)
                  .onClick(() => {
                    this.probe();
                  })
              }
              .width('100%')

              if (this.probeMessage.length > 0) {
                Text(this.probeMessage)
                  .fontSize(10)
                  .fontColor(this.probeModels.length > 0 ? $r('app.color.accent') : $r('app.color.text_tertiary'))
                  .margin({ top: 6 })
                  .width('100%')
              }

              if (this.probeModels.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.probeModels, (id: string) => {
                    Text(id)
                      .fontSize(10)
                      .fontColor(this.modelId === id ? $r('app.color.accent') : $r('app.color.text_secondary'))
                      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                      .margin(3)
                      .backgroundColor(this.modelId === id ? $r('app.color.accent_soft') : $r('app.color.surface_alt'))
                      .borderRadius(7)
                      .onClick(() => {
                        this.modelId = id;
                      })
                  }, (id: string) => id)
                }
                .width('100%')
                .margin({ top: 4 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.fieldLabel(t('备用模型（按顺序重试）'))
              TextInput({ text: this.fallbackText, placeholder: t('如 kimi-k3, glm-4.6（可留空）') })
                .width('100%')
                .height(42)
                .fontSize(13)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onChange((value: string) => {
                  this.fallbackText = value;
                })
              Text(t('仅当本次请求尚未产生任何文本、推理或工具调用时才会切换。'))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 4 })
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            this.sectionTitle(t('生成参数'), t('按模型能力调整；不确定时保持默认'))
            Column() {
              Row({ space: 10 }) {
                Text(t('温度'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width(44)
                Slider({ value: this.temperature, min: 0, max: 2, step: 0.1 })
                  .layoutWeight(1)
                  .selectedColor($r('app.color.accent'))
                  .onChange((value: number) => {
                    this.temperature = value;
                  })
                Text(this.temperature.toFixed(1))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width(28)
                  .textAlign(TextAlign.End)
              }
              .width('100%')

              Row({ space: 10 }) {
                Text(t('最大输出'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width(64)
                TextInput({ text: this.maxTokensText })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(12)
                  .type(InputType.Number)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onChange((value: string) => {
                    this.maxTokensText = value;
                  })
                Text('tokens')
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .margin({ top: 8 })
            }
            .width('100%')

            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(t('逐模型参数'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('按模型 ID 精确匹配，覆盖温度、top_p、最大输出，并追加请求头与请求体字段。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text(this.editingOverride ? t('取消') : t('添加'))
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.surface'))
                  .borderRadius(8)
                  .onClick(() => this.beginOverride(-1))
              }
              .width('100%')

              if (this.modelOverrides.length === 0 && !this.editingOverride) {
                Text(t('还没有覆盖项；不添加时所有模型使用上方的全局参数。'))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              }

              ForEach(this.modelOverrides, (item: ModelOverride) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(item.modelId)
                      .fontSize(11)
                      .fontColor($r('app.color.text_primary'))
                    Text(overrideSummary(item))
                      .fontSize(9)
                      .fontColor($r('app.color.text_tertiary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Text(t('编辑'))
                    .fontSize(10)
                    .fontColor($r('app.color.accent'))
                    .onClick(() => this.beginOverride(this.modelOverrides.indexOf(item)))
                  Text(t('删除'))
                    .fontSize(10)
                    .fontColor($r('app.color.danger'))
                    .onClick(() => this.removeOverride(this.modelOverrides.indexOf(item)))
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.surface'))
                .borderRadius(9)
              }, (item: ModelOverride) => item.modelId + ':' + overrideSummary(item))

              if (this.editingOverride) {
                Column({ space: 8 }) {
                  this.fieldLabel(t('模型 ID（与请求里的 model 完全一致）'))
                  TextInput({ text: this.ovModelId, placeholder: t('例如 kimi-k3') })
                    .height(38)
                    .fontSize(12)
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.ovModelId = value;
                    })

                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      this.fieldLabel(t('温度'))
                      TextInput({ text: this.ovTemperatureText, placeholder: t('继承') })
                        .height(36)
                        .fontSize(12)
                        .type(InputType.Number)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.ovTemperatureText = value;
                        })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Column({ space: 4 }) {
                      this.fieldLabel('top_p')
                      TextInput({ text: this.ovTopPText, placeholder: t('不发送') })
                        .height(36)
                        .fontSize(12)
                        .type(InputType.Number)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.ovTopPText = value;
                        })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Column({ space: 4 }) {
                      this.fieldLabel(t('最大输出'))
                      TextInput({ text: this.ovMaxTokensText, placeholder: t('继承') })
                        .height(36)
                        .fontSize(12)
                        .type(InputType.Number)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.ovMaxTokensText = value;
                        })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')

                  this.fieldLabel(t('附加请求头（JSON 对象，值必须是字符串）'))
                  TextArea({ text: this.ovHeadersText, placeholder: '{"X-Title":"MinisHarmony"}' })
                    .height(64)
                    .fontSize(11)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.ovHeadersText = value;
                    })

                  this.fieldLabel(t('附加请求体（JSON 对象，与基础字段同名时覆盖）'))
                  TextArea({ text: this.ovBodyText, placeholder: '{"provider":{"order":["moonshot"]}}' })
                    .height(64)
                    .fontSize(11)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.ovBodyText = value;
                    })

                  Row({ space: 8 }) {
                    Button(t('取消'), { type: ButtonType.Normal })
                      .layoutWeight(1)
                      .height(34)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onClick(() => {
                        this.editingOverride = false;
                      })
                    Button(t('保存覆盖项'), { type: ButtonType.Normal })
                      .layoutWeight(1)
                      .height(34)
                      .fontSize(12)
                      .fontColor($r('app.color.on_accent'))
                      .backgroundColor($r('app.color.accent'))
                      .borderRadius(9)
                      .onClick(() => this.saveOverride())
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(11)
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)

            this.sectionTitle(t('子代理名册'), t('给 subagent_task 起名字；说明会进入系统提示，最多 ') +
              MAX_SUB_AGENTS.toString() + t(' 个（含内置）'))
            Column({ space: 8 }) {
              ForEach(this.subAgents, (agent: SubAgentDefinition, index: number) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Row({ space: 6 }) {
                      Text(agent.name)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                      if (agent.builtIn) {
                        Text(t('内置'))
                          .fontSize(9)
                          .fontColor($r('app.color.text_tertiary'))
                          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                          .backgroundColor($r('app.color.surface_alt'))
                          .borderRadius(6)
                      }
                    }
                    Text(agent.description.length > 0 ? agent.description : t('（没有说明）'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (!agent.builtIn) {
                    Text(t('编辑'))
                      .fontSize(11)
                      .fontColor($r('app.color.accent'))
                      .onClick(() => {
                        this.beginAgent(index);
                      })
                    Text(t('删除'))
                      .fontSize(11)
                      .fontColor($r('app.color.danger'))
                      .onClick(() => {
                        this.deleteAgent(index);
                      })
                  }
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
              }, (agent: SubAgentDefinition, index: number) => agent.id + index.toString())

              if (this.agentEditing) {
                Column({ space: 8 }) {
                  TextInput({ text: this.agentName, placeholder: t('名字，例如 research') })
                    .width('100%')
                    .height(38)
                    .fontSize(12)
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.agentName = value;
                    })
                  TextInput({ text: this.agentDescription, placeholder: t('一句话说明它擅长什么') })
                    .width('100%')
                    .height(38)
                    .fontSize(12)
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.agentDescription = value;
                    })
                  Text(t('说明最多 ') + SUB_AGENT_DESCRIPTION_MAX.toString() +
                    t(' 字符，会进入主对话的系统提示'))
                    .fontSize(9)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                  TextArea({
                    text: this.agentInstructions,
                    placeholder: t('附加给这个子代理的系统提示（可选）')
                  })
                    .width('100%')
                    .height(90)
                    .fontSize(11)
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.agentInstructions = value;
                    })
                  Row({ space: 8 }) {
                    Button(t('保存'))
                      .layoutWeight(1)
                      .height(36)
                      .fontSize(12)
                      .fontColor($r('app.color.on_accent'))
                      .backgroundColor($r('app.color.accent'))
                      .borderRadius(9)
                      .onClick(() => {
                        this.saveAgent();
                      })
                    Button(t('取消'))
                      .height(36)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.surface_alt'))
                      .borderRadius(9)
                      .onClick(() => {
                        this.agentEditing = false;
                        this.agentIndex = -1;
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .alignItems(HorizontalAlign.Start)
              } else {
                Button(t('添加子代理'))
                  .width('100%')
                  .height(36)
                  .fontSize(12)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .enabled(this.subAgents.length < MAX_SUB_AGENTS)
                  .onClick(() => {
                    this.beginAgent(-1);
                  })
              }

              Text(t('模型用 subagent_task 的 agent 参数选择名字；不写则使用内置 helper。') +
                t('说明会占用每轮系统提示，名字最多 40 字符。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')
            }
            .width('100%')

            this.sectionTitle(t('Agent 与日志'), t('工具往返上限与 OpenMinis 一致；日志只记录元数据'))
            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Text(t('每轮最多往返'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width(84)
                TextInput({ text: this.maxTurnsText })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(12)
                  .type(InputType.Number)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onChange((value: string) => {
                    this.maxTurnsText = value;
                  })
                Text(t('轮'))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')

              Text(t('默认 200。达到上限后本轮结束，已完成的上下文与工具结果会保留，继续发送消息即可接着执行。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')

              Row({ space: 10 }) {
                Text(t('上下文预算'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width(84)
                TextInput({ text: this.contextBudgetText })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(12)
                  .type(InputType.Number)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onChange((value: string) => {
                    this.contextBudgetText = value;
                  })
                  .onBlur(() => {
                    // Show the value that will actually be saved; otherwise an
                    // out-of-range entry silently comes back as a different
                    // number the next time the sheet opens.
                    const text: string = this.contextBudgetText.trim();
                    const parsed: number = Number(text);
                    if (text.length === 0 || Number.isNaN(parsed) || !Number.isFinite(parsed)) {
                      this.contextBudgetText = this.settings.contextBudgetChars.toString();
                      return;
                    }
                    this.contextBudgetText = clampContextBudget(parsed).toString();
                  })
                Text(t('字符'))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')

              Text(this.budgetSummary())
                .fontSize(9)
                .fontColor(this.budgetAdjusted() ?
                  $r('app.color.danger') : $r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')

              Text(t('默认 60000（6 万字符），可填 4000–2000000。估算请求超过预算时，较早的工具结果会在发送前被截断；界面与已保存的记录不受影响。可用 /compact 让模型生成摘要。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('上下文接近上限时自动压缩'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(t('发送前按最近一次用量判断，先生成摘要再发请求；失败时保留原对话。'))
                    .fontSize(9)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(13)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.autoCompact })
                  .selectedColor(this.accentColor)
                  .onChange((on: boolean) => {
                    this.autoCompact = on;
                  })
              }
              .width('100%')

              if (this.autoCompact) {
                Row({ space: 10 }) {
                  Text(t('触发阈值'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width(84)
                  TextInput({ text: this.autoCompactText })
                    .layoutWeight(1)
                    .height(38)
                    .fontSize(12)
                    .type(InputType.Number)
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      this.autoCompactText = value;
                    })
                  Text('%')
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
              }

              Column({ space: 6 }) {
                Text(t('思考档位'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 6 }) {
                  ForEach(THINKING_CHOICES, (choice: ThinkingChoice) => {
                    Text(t(choice.label))
                      .layoutWeight(1)
                      .height(32)
                      .fontSize(11)
                      .textAlign(TextAlign.Center)
                      .fontColor(this.thinkingLevel === choice.value
                        ? $r('app.color.on_accent')
                        : $r('app.color.text_secondary'))
                      .backgroundColor(this.thinkingLevel === choice.value
                        ? $r('app.color.accent')
                        : $r('app.color.surface'))
                      .borderRadius(8)
                      .onClick(() => {
                        this.thinkingLevel = choice.value;
                      })
                  }, (choice: ThinkingChoice) => choice.value + ':' +
                    (this.thinkingLevel === choice.value ? '1' : '0'))
                }
                .width('100%')
                Text(t('非「关闭」时，请求体带 reasoning_effort。不是所有模型都支持；不支持时会由服务端忽略或报错，可随时改回关闭。'))
                  .fontSize(9)
                  .fontColor($r('app.color.text_tertiary'))
                  .lineHeight(14)
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Column({ space: 10 }) {
                Text(t('主题色'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 8 }) {
                  ForEach(ACCENT_PRESETS, (preset: AccentPreset) => {
                    Column({ space: 3 }) {
                      Column()
                        .width(26)
                        .height(26)
                        .borderRadius(13)
                        .backgroundColor(preset.value)
                        .border({
                          width: this.accentColor === preset.value ? 2 : 0,
                          color: $r('app.color.text_primary')
                        })
                      Text(t(preset.name))
                        .fontSize(9)
                        .fontColor(this.accentColor === preset.value
                          ? $r('app.color.text_primary')
                          : $r('app.color.text_tertiary'))
                    }
                    .layoutWeight(1)
                    .onClick(() => {
                      this.accentColor = preset.value;
                    })
                  }, (preset: AccentPreset) => preset.value)
                }
                .width('100%')

                Text(t('界面字号'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 6 }) {
                  ForEach(FONT_SCALE_OPTIONS, (scale: number) => {
                    Text(fontScaleLabel(scale))
                      .layoutWeight(1)
                      .height(32)
                      .fontSize(11)
                      .textAlign(TextAlign.Center)
                      .fontColor(this.fontScale === scale
                        ? $r('app.color.on_accent')
                        : $r('app.color.text_secondary'))
                      .backgroundColor(this.fontScale === scale
                        ? $r('app.color.accent')
                        : $r('app.color.surface'))
                      .borderRadius(8)
                      .onClick(() => {
                        this.fontScale = scale;
                      })
                  }, (scale: number) => scale.toString())
                }
                .width('100%')
                Text(t('消息字号'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 6 }) {
                  ForEach(FONT_SCALE_OPTIONS, (scale: number) => {
                    Text(fontScaleLabel(scale))
                      .layoutWeight(1)
                      .height(32)
                      .fontSize(11)
                      .textAlign(TextAlign.Center)
                      .fontColor(this.messageFontScale === scale
                        ? $r('app.color.on_accent')
                        : $r('app.color.text_secondary'))
                      .backgroundColor(this.messageFontScale === scale
                        ? $r('app.color.accent')
                        : $r('app.color.surface'))
                      .borderRadius(8)
                      .onClick(() => {
                        this.messageFontScale = scale;
                      })
                  }, (scale: number) => scale.toString())
                }
                .width('100%')
                Text(t('输入框字号'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 6 }) {
                  ForEach(FONT_SCALE_OPTIONS, (scale: number) => {
                    Text(fontScaleLabel(scale))
                      .layoutWeight(1)
                      .height(32)
                      .fontSize(11)
                      .textAlign(TextAlign.Center)
                      .fontColor(this.inputFontScale === scale
                        ? $r('app.color.on_accent')
                        : $r('app.color.text_secondary'))
                      .backgroundColor(this.inputFontScale === scale
                        ? $r('app.color.accent')
                        : $r('app.color.surface'))
                      .borderRadius(8)
                      .onClick(() => {
                        this.inputFontScale = scale;
                      })
                  }, (scale: number) => scale.toString())
                }
                .width('100%')
                Text(t('三处独立调整：界面用于侧栏与设置，消息用于正文与代码，输入框只影响输入区。'))
                  .fontSize(9)
                  .fontColor($r('app.color.text_tertiary'))
                  .lineHeight(14)
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('记录本地事件日志'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('记录请求耗时、模型、工具状态与错误；不记录对话内容、API Key 或沙箱 Token。按天轮转，保留 14 天。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.loggingEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.loggingEnabled = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('切到后台继续生成'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('生成期间启动长时任务，切换到其他应用时保持连接；系统会显示一条持续通知。不可用时自动退回前台生成。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.backgroundEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.backgroundEnabled = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('Enter 键发送'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('开启后按 Enter 直接发送，适合外接键盘；关闭时 Enter 换行，点箭头发送。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.enterToSend })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.enterToSend = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('自动展开思考过程'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('回复完成后仍展开模型返回的思考内容；关闭时只在生成中展开。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.autoExpandThinking })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.autoExpandThinking = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('回复后自动聚焦输入框'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('一轮回复结束后把光标放回输入框，方便继续追问。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.autoFocusInput })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.autoFocusInput = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('自动生成会话标题'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('首轮结束后让模型起一个短标题；关闭时使用首句截断。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.autoTitleEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.autoTitleEnabled = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('自动归入分组'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('生成标题时把已有分组提供给模型；只有明确匹配且会话尚未分组时才归入，不会新建分组。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.autoGroupingEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.autoGroupingEnabled = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('启动时验证系统锁屏'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('打开应用时先通过系统密码 / 人脸 / 指纹；设备没有可用认证时自动放行，避免把自己锁在外面。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.appLockEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.appLockEnabled = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Row({ space: 8 }) {
                Button(this.showLogs ? t('收起日志') : t('查看事件日志'))
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onClick(() => this.loadLogs())
                Button(this.showCrashes ? t('收起崩溃') : t('崩溃记录'))
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onClick(() => this.toggleCrashes())
                Button(t('清空事件日志'))
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onClick(() => this.clearLogs())
              }
              .width('100%')

              Column({ space: 3 }) {
                Button(t('导出诊断包'))
                  .height(34)
                  .width('100%')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onClick(() => this.onExportDiagnostics())
                Text(t('含设备/版本信息、非密钥设置摘要、会话数量、崩溃记录与事件日志；不含提示词、消息正文、API Key 或沙箱 Token。'))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
                  .lineHeight(14)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              if (this.showLogs) {
                Column({ space: 8 }) {
                  Row({ space: 6 }) {
                    ForEach(['all', LOG_INFO, LOG_WARN, LOG_ERROR], (value: string) => {
                      Text(this.logLevelLabel(value))
                        .fontSize(10)
                        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                        .borderRadius(7)
                        .fontColor(this.logLevel === value
                          ? $r('app.color.on_accent')
                          : $r('app.color.text_secondary'))
                        .backgroundColor(this.logLevel === value
                          ? this.accentColor
                          : $r('app.color.surface_alt'))
                        .onClick(() => {
                          this.logLevel = value;
                        })
                    }, (value: string) => value)
                    Blank()
                    Text(t('复制可见'))
                      .fontSize(10)
                      .fontColor(this.accentColor)
                      .onClick(() => this.copyVisibleLogs())
                    Text(this.logTall ? t('还原高度') : t('放大'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_secondary'))
                      .onClick(() => {
                        this.logTall = !this.logTall;
                      })
                  }
                  .width('100%')

                  Scroll() {
                    Row({ space: 6 }) {
                      ForEach(this.logEventChoices(), (value: string) => {
                        Text(value === 'all' ? t('全部事件') : value)
                          .fontSize(10)
                          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                          .borderRadius(7)
                          .fontColor(this.logEvent === value
                            ? $r('app.color.text_primary')
                            : $r('app.color.text_tertiary'))
                          .backgroundColor(this.logEvent === value
                            ? $r('app.color.surface_alt')
                            : Color.Transparent)
                          .border({
                            width: 1,
                            color: this.logEvent === value
                              ? $r('app.color.border')
                              : Color.Transparent
                          })
                          .onClick(() => {
                            this.logEvent = value;
                          })
                      }, (value: string) => value)
                    }
                  }
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Off)
                  .width('100%')

                  TextInput({
                    text: this.logQuery,
                    placeholder: t('按关键词或时间筛选，例如 14:32 或 model_done')
                  })
                    .height(32)
                    .fontSize(11)
                    .fontColor($r('app.color.text_primary'))
                    .placeholderColor($r('app.color.text_tertiary'))
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(8)
                    .onChange((value: string) => {
                      this.logQuery = value;
                    })

                  if (this.logRows.length === 0) {
                    Text(t('没有日志。需要先打开「记录本地事件日志」，之后产生的事件才会写入。'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(16)
                  } else if (this.filteredLogRows().length === 0) {
                    Text(t('没有匹配的日志。'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                  } else {
                    Scroll() {
                      Column({ space: 4 }) {
                        ForEach(this.filteredLogRows(), (row: LogRow, index: number) => {
                          Row({ space: 8 }) {
                            Text(row.line)
                              .fontSize(10)
                              .fontColor(row.parsed.level === LOG_ERROR
                                ? $r('app.color.danger')
                                : $r('app.color.text_secondary'))
                              .layoutWeight(1)
                              .textAlign(TextAlign.Start)
                              .copyOption(CopyOptions.LocalDevice)
                            Text(t('复制'))
                              .fontSize(9)
                              .fontColor($r('app.color.text_tertiary'))
                              .onClick(() => this.copyText(row.line, t('已复制该行')))
                          }
                          .width('100%')
                          .alignItems(VerticalAlign.Top)
                          .gesture(LongPressGesture().onAction(() => {
                            this.copyText(row.line, t('已复制该行'));
                          }))
                        }, (row: LogRow, index: number) =>
                          index.toString() + ':' + row.parsed.raw)
                      }
                      .width('100%')
                    }
                    .height(this.logTall ? 520 : 240)
                    .width('100%')
                    .scrollBar(BarState.Auto)
                  }
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(9)
              }

              if (this.showCrashes) {
                Column({ space: 6 }) {
                  Row() {
                    Text(t('崩溃记录'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(t('复制全部'))
                      .fontSize(10)
                      .fontColor(this.accentColor)
                      .onClick(() => this.copyCrashes())
                  }
                  .width('100%')

                  if (this.crashRows.length === 0) {
                    Text(t('没有崩溃记录。系统崩溃/冻结事件会在这里显示完整堆栈。'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(16)
                  } else {
                    Scroll() {
                      Column({ space: 8 }) {
                        ForEach(this.crashRows, (row: string, index: number) => {
                          Text(row)
                            .fontSize(10)
                            .fontFamily('monospace')
                            .fontColor($r('app.color.text_secondary'))
                            .width('100%')
                            .copyOption(CopyOptions.LocalDevice)
                        }, (row: string, index: number) => index.toString() + ':' + row.length)
                      }
                      .width('100%')
                    }
                    .height(300)
                    .width('100%')
                    .scrollBar(BarState.Auto)
                  }
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(9)
              }
            }
            .width('100%')

            this.sectionTitle(t('用量统计与存储'),
              t('token 按模型与日期累计在本地；附件、工作区与下载可直接清理'))
            Column({ space: 8 }) {
              Text(this.usageTotalLine)
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              if (this.usageModelLines.length > 0) {
                Text(t('按模型'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                ForEach(this.usageModelLines, (line: string) => {
                  Text(line)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }, (line: string) => line)
              }
              if (this.usageProviderLines.length > 0) {
                Text(t('按供应商'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                ForEach(this.usageProviderLines, (line: string) => {
                  Text(line)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }, (line: string) => line)
              }
              if (this.usageDayLines.length > 0) {
                Text(t('最近 7 天'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                ForEach(this.usageDayLines, (line: string) => {
                  Text(line)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }, (line: string) => line)
              }
              Button(t('清空用量统计'))
                .height(34)
                .width('100%')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(9)
                .onClick(() => this.clearUsage())
              Divider()
                .color($r('app.color.border'))
                .margin({ top: 2, bottom: 2 })
              ForEach(this.storageLines, (line: string) => {
                Text(line)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }, (line: string) => line)
              Row({ space: 6 }) {
                Button(t('清理附件'))
                  .layoutWeight(1)
                  .height(32)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(8)
                  .onClick(() => this.clearStorage('attachments'))
                Button(t('清理工作区'))
                  .layoutWeight(1)
                  .height(32)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(8)
                  .onClick(() => this.clearStorage('workspace'))
                Button(t('清理下载'))
                  .layoutWeight(1)
                  .height(32)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(8)
                  .onClick(() => this.clearStorage('downloads'))
              }
              .width('100%')
              Text(t('清理会删除文件且不可撤销；会话历史与消息记录不受影响，但引用的图片/视频将无法再打开。'))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)

            this.sectionTitle(t('配置变更记录'),
              t('记录设置项的旧值与新值；可逐项还原，密钥只记录是否设置'))
            Column({ space: 8 }) {
              if (this.auditEntries.length === 0) {
                Text(t('还没有配置变更记录。'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              }
              ForEach(this.auditEntries, (entry: ConfigAuditEntry) => {
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(entry.key)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    if (entry.restorable) {
                      Text(t('还原'))
                        .fontSize(10)
                        .fontColor($r('app.color.accent'))
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor($r('app.color.surface_alt'))
                        .borderRadius(7)
                        .onClick(() => this.onRestoreAudit(entry.id))
                    } else {
                      Text(t('仅记录'))
                        .fontSize(9)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                  }
                  .width('100%')
                  Text(auditValueLabel(entry.key, entry.before) + ' → ' +
                    auditValueLabel(entry.key, entry.after))
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(formatDateTime(entry.at))
                    .fontSize(9)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                }
                .width('100%')
                .padding(8)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(8)
              }, (entry: ConfigAuditEntry) => entry.id)
              Button(this.storageClear === 'audit'
                ? t('再点一次确认清空')
                : t('清空配置变更记录'))
                .height(32)
                .width('100%')
                .fontSize(10)
                .fontColor(this.storageClear === 'audit'
                  ? $r('app.color.danger')
                  : $r('app.color.text_secondary'))
                .backgroundColor($r('app.color.surface'))
                .borderRadius(8)
                .onClick(() => this.clearAudit())
              Text(t('审计只存在本机；API Key、沙箱令牌与 WebDAV 密码只记录「已设置/未设置」，结构化设置只记录条目数，无法还原。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(13)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)

            this.sectionTitle(t('远程备份（WebDAV）'), t('上传加密备份到你自己的 WebDAV；换机或多端恢复时不用电脑'))
            Column() {
              this.fieldLabel(t('WebDAV 地址'))
              TextInput({ text: this.webDavUrl, placeholder: 'https://dav.example.com/minis' })
                .height(42)
                .fontSize(13)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onChange((value: string) => {
                  this.webDavUrl = value;
                })
              Text(t('填写文件夹地址；上传会写入「minis-backup-日期-enc.json」并覆盖「minis-backup-latest-enc.json」。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 4 })
                .lineHeight(13)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.fieldLabel(t('用户名'))
              TextInput({ text: this.webDavUser, placeholder: t('WebDAV 账号') })
                .height(42)
                .fontSize(13)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onChange((value: string) => {
                  this.webDavUser = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.fieldLabel(t('密码'))
              Row({ space: 8 }) {
                TextInput({
                  text: this.webDavPassword,
                  placeholder: t('同时用于认证和加密备份')
                })
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .type(this.showWebDavPassword ? InputType.Normal : InputType.Password)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(10)
                  .onChange((value: string) => {
                    this.webDavPassword = value;
                  })
                Text(this.showWebDavPassword ? t('隐藏') : t('显示'))
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
                  .padding({ left: 4, right: 4 })
                  .onClick(() => {
                    this.showWebDavPassword = !this.showWebDavPassword;
                  })
              }
              .width('100%')
              Text(t('密码只保存在系统安全存储；远端文件始终用该密码经 PBKDF2 + AES-256-GCM 加密，不会上传明文。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 4 })
                .lineHeight(13)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(t('自动同步'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_primary'))
                Text(t('启动与对话结束后先拉取远端再合并上传；同一会话以更新时间新的一份为准，本机独有会话保留。'))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
                  .lineHeight(14)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.webDavAutoSync })
                .selectedColor($r('app.color.accent'))
                .onChange((on: boolean) => {
                  this.webDavAutoSync = on;
                })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)

            if (this.webDavLastSyncAt > 0) {
              Text(t('上次同步：') + formatDateTime(this.webDavLastSyncAt))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }

            Button(t('立即同步（合并远端）'))
              .width('100%')
              .height(38)
              .fontSize(12)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .borderRadius(10)
              .onClick(() => this.onSyncRemoteBackup(
                this.webDavUrl.trim(), this.webDavUser.trim(), this.webDavPassword))

            Row({ space: 8 }) {
              Button(t('上传加密备份'))
                .layoutWeight(1)
                .height(38)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onClick(() => this.onUploadRemoteBackup(
                  this.webDavUrl.trim(), this.webDavUser.trim(), this.webDavPassword))
              Button(t('从 WebDAV 恢复'))
                .layoutWeight(1)
                .height(38)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onClick(() => this.onDownloadRemoteBackup(
                  this.webDavUrl.trim(), this.webDavUser.trim(), this.webDavPassword))
            }
            .width('100%')

            this.sectionTitle(t('工具与沙箱'), t('工具默认在应用私有工作区执行，也可以转发到电脑上的兼容服务'))
            Row({ space: 10 }) {
              Text(t('允许模型调用工具'))
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.toolsEnabled })
                .selectedColor($r('app.color.accent'))
                .onChange((on: boolean) => {
                  this.toolsEnabled = on;
                })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)

            if (this.toolsEnabled) {
              Row({ space: 10 }) {
                this.sandboxCard(t('本机'), t('应用私有目录，离线可用'), 'local')
                this.sandboxCard(t('远程'), t('转发到 PC / NAS 的工具服务'), 'remote')
              }
              .width('100%')

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('允许写入工作区文件'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.sandboxMode === 'local'
                    ? t('关闭时只读；开启后模型可创建和覆盖文件，并可在 Linux 沙箱里执行命令')
                    : t('关闭时远程端只读；开启后允许远程写入'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.allowWriteTools })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.allowWriteTools = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              if (this.allowWriteTools) {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(t('写入前逐次确认'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('每次 write_file / file_edit / shell_execute / python_execute 执行前弹窗，可选择允许或拒绝；拒绝会作为错误结果返回给模型。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.confirmWriteTools })
                    .selectedColor($r('app.color.accent'))
                    .onChange((on: boolean) => {
                      this.confirmWriteTools = on;
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)
              }

              if (this.sandboxMode === 'local') {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(t('允许读取图片'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('开启后模型可调用 read_image 查看工作区图片；仅对支持视觉的模型有效，纯文本模型会报错。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.imageToolsEnabled })
                    .selectedColor($r('app.color.accent'))
                    .onChange((on: boolean) => {
                      this.imageToolsEnabled = on;
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)

                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(t('允许生成图片'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('开启后模型可调用 generate_image，请求 OpenAI 兼容的 /images/generations；Anthropic / Gemini 原生协议不可用。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.imageGenEnabled })
                    .selectedColor($r('app.color.accent'))
                    .onChange((on: boolean) => {
                      this.imageGenEnabled = on;
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)

                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(t('允许访问剪贴板'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('开启后模型可调用 clipboard_read / clipboard_write；剪贴板内容会发送给模型，请谨慎开启。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.clipboardToolsEnabled })
                    .selectedColor($r('app.color.accent'))
                    .onChange((on: boolean) => {
                      this.clipboardToolsEnabled = on;
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)

                this.deviceToggleRow(t('允许读取日历'),
                  t('开启后模型可调用 calendar 查看事件或新建事件；首次使用会请求系统日历权限。'),
                  this.calendarToolsEnabled, (next: boolean) => {
                    this.calendarToolsEnabled = next;
                  }, true)
                this.deviceToggleRow(t('允许搜索通讯录'),
                  t('通讯录需要受限 ACL 权限，正在申请中；获批并重新签名前暂不可用。'),
                  this.contactsToolsEnabled, (next: boolean) => {
                    this.contactsToolsEnabled = next;
                  }, false)
                this.deviceToggleRow(t('允许获取定位'),
                  t('开启后模型可调用 location 读取当前经纬度；坐标会发送给模型与服务商。'),
                  this.locationToolsEnabled, (next: boolean) => {
                    this.locationToolsEnabled = next;
                  }, true)
                this.deviceToggleRow(t('允许查询天气'),
                  t('开启后模型可调用 weather；未指定城市时使用设备定位（同样需要定位权限）。'),
                  this.weatherToolsEnabled, (next: boolean) => {
                    this.weatherToolsEnabled = next;
                  }, true)
              }

              Column({ space: 6 }) {
                Column({ space: 3 }) {
                  Text(t('逐工具开关'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(t('关闭的工具不会出现在模型可见的工具列表里；写入、记忆与读图片仍由上面的总开关控制。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                ForEach(TOOL_CHOICES, (tool: ToolChoice) => {
                  Row({ space: 8 }) {
                    Text(t(tool.label) + t('  ·  ') + tool.name)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: this.toolEnabled(tool.name) })
                      .selectedColor($r('app.color.accent'))
                      .onChange((on: boolean) => {
                        this.setToolEnabled(tool.name, on);
                      })
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .backgroundColor($r('app.color.surface'))
                  .borderRadius(9)
                }, (tool: ToolChoice) => tool.name + ':' +
                  (this.toolEnabled(tool.name) ? '1' : '0'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(t('技能（Skills）'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('导入 SKILL.md；启用的技能只把名称与简介放进系统提示，模型需要时用 read_skill 读取正文。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Text(t('导入'))
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(8)
                    .onClick(() => {
                      this.importSkill();
                    })
                }
                .width('100%')

                if (this.skills.length === 0) {
                  Text(t('还没有导入技能。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                }

                ForEach(this.skills, (skill: SkillDoc) => {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(skill.name)
                        .fontSize(11)
                        .fontColor($r('app.color.text_primary'))
                      Text(skill.description)
                        .fontSize(9)
                        .fontColor($r('app.color.text_tertiary'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Toggle({ type: ToggleType.Switch, isOn: this.skillEnabled(skill.id) })
                      .selectedColor($r('app.color.accent'))
                      .onChange((on: boolean) => {
                        this.setSkillEnabled(skill.id, on);
                      })
                    Text(t('删除'))
                      .fontSize(10)
                      .fontColor($r('app.color.danger'))
                      .onClick(() => this.removeSkill(skill.id))
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.surface'))
                  .borderRadius(9)
                }, (skill: SkillDoc) => skill.id + ':' +
                  (this.skillEnabled(skill.id) ? '1' : '0'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(t('MCP 工具'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('连接支持 Streamable HTTP 的 MCP 服务，工具以 mcp_服务_工具 命名，与本机/远程工具一起提供给模型。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Text(this.mcpRefreshing ? t('刷新中…') : t('刷新'))
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(8)
                    .onClick(() => {
                      this.refreshMcp();
                    })
                  Text(this.editingMcp ? t('取消') : t('添加'))
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(8)
                    .onClick(() => this.beginMcp(-1))
                }
                .width('100%')

                if (this.mcpServers.length === 0 && !this.editingMcp) {
                  Text(t('还没有 MCP 服务。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                }

                ForEach(this.mcpServers, (server: McpServerConfig) => {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(server.name)
                        .fontSize(11)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(server.url)
                        .fontSize(9)
                        .fontColor($r('app.color.text_tertiary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Toggle({ type: ToggleType.Switch, isOn: server.enabled })
                      .selectedColor($r('app.color.accent'))
                      .onChange((on: boolean) => {
                        this.setMcpEnabled(this.mcpServers.indexOf(server), on);
                      })
                    if (isMcpOAuthConfigured(server.oauth)) {
                      Text('OAuth')
                        .fontSize(10)
                        .fontColor($r('app.color.accent'))
                        .onClick(() => this.openMcpOAuth(this.mcpServers.indexOf(server)))
                    }
                    Text(t('编辑'))
                      .fontSize(10)
                      .fontColor($r('app.color.accent'))
                      .onClick(() => this.beginMcp(this.mcpServers.indexOf(server)))
                    Text(t('删除'))
                      .fontSize(10)
                      .fontColor($r('app.color.danger'))
                      .onClick(() => this.removeMcp(this.mcpServers.indexOf(server)))
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.surface'))
                  .borderRadius(9)
                }, (server: McpServerConfig) => server.id + ':' +
                  (server.enabled ? '1' : '0') + ':' +
                  (isMcpOAuthConfigured(server.oauth) ? '1' : '0'))

                if (this.mcpOAuthIndex >= 0 && this.mcpOAuthIndex < this.mcpServers.length) {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      Text(t('OAuth · ') + this.mcpServers[this.mcpOAuthIndex].name)
                        .fontSize(11)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text(t('关闭'))
                        .fontSize(10)
                        .fontColor($r('app.color.text_secondary'))
                        .onClick(() => {
                          this.mcpOAuthIndex = -1;
                        })
                    }
                    .width('100%')

                    Text(this.mcpOAuthLoggedIn
                      ? t('状态：已授权 ') + this.mcpOAuthMask
                      : t('状态：未授权'))
                      .fontSize(10)
                      .fontColor(this.mcpOAuthLoggedIn
                        ? $r('app.color.accent')
                        : $r('app.color.text_tertiary'))
                      .width('100%')

                    Text(t('回调地址需与 OAuth 应用登记的一致（默认 http://localhost:54546/callback）。') +
                      t('授权后从浏览器地址栏复制完整回调地址，粘贴到下方完成登录。'))
                      .fontSize(9)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                      .width('100%')

                    Row({ space: 8 }) {
                      Button(this.mcpOAuthBusy ? t('请稍候…') : t('开始登录'), { type: ButtonType.Normal })
                        .layoutWeight(1)
                        .height(32)
                        .fontSize(11)
                        .fontColor($r('app.color.on_accent'))
                        .backgroundColor($r('app.color.accent'))
                        .borderRadius(8)
                        .enabled(!this.mcpOAuthBusy)
                        .onClick(() => this.startMcpOAuthLogin())
                      if (this.mcpOAuthLoggedIn) {
                        Button(t('退出登录'), { type: ButtonType.Normal })
                          .layoutWeight(1)
                          .height(32)
                          .fontSize(11)
                          .fontColor($r('app.color.danger'))
                          .backgroundColor($r('app.color.surface'))
                          .borderRadius(8)
                          .enabled(!this.mcpOAuthBusy)
                          .onClick(() => this.logoutMcpOAuth())
                      }
                    }
                    .width('100%')

                    TextInput({
                      text: this.mcpOAuthPaste,
                      placeholder: t('粘贴回调地址或授权码')
                    })
                      .height(36)
                      .fontSize(11)
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onChange((value: string) => {
                        this.mcpOAuthPaste = value;
                      })

                    Button(this.mcpOAuthBusy ? t('请稍候…') : t('完成登录'), { type: ButtonType.Normal })
                      .width('100%')
                      .height(32)
                      .fontSize(11)
                      .fontColor($r('app.color.text_primary'))
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(8)
                      .enabled(!this.mcpOAuthBusy)
                      .onClick(() => this.completeMcpOAuthLogin())

                    if (this.mcpOAuthStatus.length > 0) {
                      Text(this.mcpOAuthStatus)
                        .fontSize(9)
                        .fontColor($r('app.color.text_tertiary'))
                        .lineHeight(14)
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(11)
                  .alignItems(HorizontalAlign.Start)
                }

                if (this.mcpStatusText.length > 0) {
                  Text(this.mcpStatusText)
                    .fontSize(9)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                    .width('100%')
                }

                if (this.editingMcp) {
                  Column({ space: 8 }) {
                    this.fieldLabel(t('名称'))
                    TextInput({ text: this.mcpName, placeholder: t('例如 搜索服务') })
                      .height(36)
                      .fontSize(12)
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onChange((value: string) => {
                        this.mcpName = value;
                      })

                    this.fieldLabel(t('地址（JSON-RPC 端点）'))
                    TextInput({ text: this.mcpUrl, placeholder: 'https://example.com/mcp' })
                      .height(36)
                      .fontSize(12)
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onChange((value: string) => {
                        this.mcpUrl = value;
                      })

                    this.fieldLabel(t('请求头（JSON 对象，可用于鉴权）'))
                    TextArea({ text: this.mcpHeadersText, placeholder: t('{"Authorization":"Bearer …"}') })
                      .height(56)
                      .fontSize(11)
                      .fontColor($r('app.color.text_primary'))
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onChange((value: string) => {
                        this.mcpHeadersText = value;
                      })

                    Row({ space: 8 }) {
                      Column({ space: 2 }) {
                        Text(t('OAuth 登录（静态客户端）'))
                          .fontSize(11)
                          .fontColor($r('app.color.text_primary'))
                        Text(t('填写 OAuth 应用的客户端信息，保存后在服务列表点 OAuth 完成授权。'))
                          .fontSize(9)
                          .fontColor($r('app.color.text_tertiary'))
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      Toggle({ type: ToggleType.Switch, isOn: this.mcpOAuthExpanded })
                        .selectedColor($r('app.color.accent'))
                        .onChange((on: boolean) => {
                          this.mcpOAuthExpanded = on;
                        })
                    }
                    .width('100%')

                    if (this.mcpOAuthExpanded) {
                      this.fieldLabel('Client ID')
                      TextInput({ text: this.mcpOAuthClientId, placeholder: t('OAuth 应用的 client_id') })
                        .height(36)
                        .fontSize(11)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthClientId = value;
                        })

                      this.fieldLabel(t('授权端点'))
                      TextInput({ text: this.mcpOAuthAuthorizeUrl, placeholder: 'https://auth.example.com/authorize' })
                        .height(36)
                        .fontSize(11)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthAuthorizeUrl = value;
                        })

                      this.fieldLabel(t('令牌端点'))
                      TextInput({ text: this.mcpOAuthTokenUrl, placeholder: 'https://auth.example.com/token' })
                        .height(36)
                        .fontSize(11)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthTokenUrl = value;
                        })

                      this.fieldLabel(t('作用域（可选，空格分隔）'))
                      TextInput({ text: this.mcpOAuthScopes, placeholder: 'openid email' })
                        .height(36)
                        .fontSize(11)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthScopes = value;
                        })

                      this.fieldLabel(t('回调地址（可选）'))
                      TextInput({ text: this.mcpOAuthRedirect, placeholder: 'http://localhost:54546/callback' })
                        .height(36)
                        .fontSize(11)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthRedirect = value;
                        })

                      this.fieldLabel(t('资源标识（可选，RFC 8707）'))
                      TextInput({ text: this.mcpOAuthResource, placeholder: t('留空则使用服务地址') })
                        .height(36)
                        .fontSize(11)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthResource = value;
                        })

                      this.fieldLabel(t('Client Secret（可选，保存在安全存储）'))
                      TextInput({
                        text: this.mcpOAuthSecret,
                        placeholder: this.mcpIndex >= 0 &&
                          this.mcpIndex < this.mcpServers.length &&
                          this.mcpServers[this.mcpIndex].oauth.clientSecretSet
                          ? t('已保存，留空保持不变')
                          : t('公共客户端可留空')
                      })
                        .height(36)
                        .fontSize(11)
                        .type(InputType.Password)
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onChange((value: string) => {
                          this.mcpOAuthSecret = value;
                        })
                    }

                    Row({ space: 8 }) {
                      Text(t('启用'))
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)
                      Toggle({ type: ToggleType.Switch, isOn: this.mcpEnabled })
                        .selectedColor($r('app.color.accent'))
                        .onChange((on: boolean) => {
                          this.mcpEnabled = on;
                        })
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Button(t('取消'), { type: ButtonType.Normal })
                        .layoutWeight(1)
                        .height(34)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .backgroundColor($r('app.color.surface'))
                        .borderRadius(9)
                        .onClick(() => {
                          this.editingMcp = false;
                        })
                      Button(t('保存服务'), { type: ButtonType.Normal })
                        .layoutWeight(1)
                        .height(34)
                        .fontSize(12)
                        .fontColor($r('app.color.on_accent'))
                        .backgroundColor($r('app.color.accent'))
                        .borderRadius(9)
                        .onClick(() => this.saveMcp())
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.surface'))
                  .borderRadius(11)
                  .alignItems(HorizontalAlign.Start)
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              if (this.sandboxMode === 'local') {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(t('工作区文件'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text(t('浏览应用私有工作区；只能查看，不能在这里修改。'))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button(t('浏览'), { type: ButtonType.Normal })
                    .height(30)
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(8)
                    .onClick(() => this.onBrowseWorkspace())
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)
              }

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('持久记忆'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.sandboxMode === 'local'
                    ? t('开启后模型可写入本机记忆，并在每轮请求前作为背景注入')
                    : t('持久记忆只在本机模式下可用，远程沙箱不转发记忆工具'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.memoryEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((on: boolean) => {
                    this.memoryEnabled = on;
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              if (this.memoryEnabled && this.sandboxMode === 'local') {
                Row() {
                  Text(t('清空每日记忆（保留 GLOBAL.md）'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(t('清空'))
                    .fontSize(11)
                    .fontColor($r('app.color.danger'))
                    .onClick(() => this.clearMemory())
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)

                Row() {
                  Text(this.showMemory ? t('收起记忆编辑') : t('查看 / 编辑记忆'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.showMemory ? t('收起') : t('打开'))
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .onClick(() => this.loadMemory())
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)

                if (this.showMemory) {
                  Column({ space: 8 }) {
                    Scroll() {
                      Row({ space: 6 }) {
                        ForEach(this.memoryFiles, (file: MemoryFile, index: number) => {
                          Text(file.name)
                            .fontSize(10)
                            .fontColor(this.memoryIndex === index
                              ? $r('app.color.on_accent')
                              : $r('app.color.text_secondary'))
                            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                            .backgroundColor(this.memoryIndex === index
                              ? $r('app.color.accent')
                              : $r('app.color.surface'))
                            .borderRadius(7)
                            .onClick(() => this.selectMemory(index))
                        }, (file: MemoryFile) => file.name)
                      }
                    }
                    .scrollable(ScrollDirection.Horizontal)
                    .scrollBar(BarState.Off)
                    .width('100%')

                    TextArea({
                      text: this.memoryText,
                      placeholder: t('这个文件是空的，可以直接输入内容')
                    })
                      .width('100%')
                      .height(180)
                      .fontSize(11)
                      .fontColor($r('app.color.text_primary'))
                      .placeholderColor($r('app.color.text_tertiary'))
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onChange((value: string) => {
                        this.memoryText = value;
                      })

                    Button(t('保存记忆文件'))
                      .width('100%')
                      .height(34)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.surface'))
                      .borderRadius(9)
                      .onClick(() => this.saveMemory())
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(11)
                }
              }

              if (this.sandboxMode === 'local') {
                Text(t('本机工作区位于应用沙箱的 workspace/ 目录。路径必须是相对路径，不能包含 .. 或符号链接。'))
                  .fontSize(9)
                  .fontColor($r('app.color.text_tertiary'))
                  .lineHeight(14)
                  .width('100%')
              } else {
                Column() {
                  this.fieldLabel(t('远程工具服务地址'))
                  TextInput({
                    text: this.sandboxUrl,
                    placeholder: 'https://pc.example.com:8787/tool'
                  })
                    .width('100%')
                    .height(42)
                    .fontSize(13)
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(10)
                    .onChange((value: string) => {
                      this.sandboxUrl = value;
                    })
                  Text(t('协议：POST {name, arguments} → {ok, content}；接受与原工具相同的工具名。'))
                    .fontSize(9)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                    .margin({ top: 4 })
                    .width('100%')
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                Column() {
                  this.fieldLabel(t('远程访问令牌（可选）'))
                  TextInput({
                    text: this.sandboxToken,
                    placeholder: 'Bearer token'
                  })
                    .width('100%')
                    .height(42)
                    .fontSize(13)
                    .type(InputType.Password)
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(10)
                    .onChange((value: string) => {
                      this.sandboxToken = value;
                    })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }

              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Button(this.probeRunning ? t('自检中…') : t('运行内核自检'))
                    .height(34)
                    .layoutWeight(1)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(9)
                    .onClick(() => {
                      this.runSandboxProbe();
                    })
                  if (this.probeReport.length > 0) {
                    Button(t('复制结果'))
                      .height(34)
                      .width(88)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.surface_alt'))
                      .borderRadius(9)
                      .onClick(() => {
                        this.copyProbeReport();
                      })
                  }
                }
                .width('100%')

                if (this.probeReport.length > 0) {
                  Scroll() {
                    Text(this.probeReport)
                      .fontSize(10)
                      .fontFamily('monospace')
                      .fontColor($r('app.color.text_secondary'))
                      .width('100%')
                      .copyOption(CopyOptions.LocalDevice)
                  }
                  .height(180)
                  .width('100%')
                  .padding(8)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                } else {
                  Text(t('检查当前设备是否允许原生子进程、exec、ptrace、可执行内存与命名空间；结果只保存在本机。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                    .width('100%')
                }
              }
              .width('100%')

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(t('沙箱状态'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.sandboxStatus +
                    (this.sandboxBytes.length > 0 ? t(' · 占用 ') + this.sandboxBytes : ''))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text(this.sandboxResetting
                  ? t('重置中…')
                  : (this.resetArmed ? t('确认重置') : t('重置')))
                  .fontSize(11)
                  .fontColor(this.resetArmed
                    ? $r('app.color.danger')
                    : $r('app.color.text_secondary'))
                  .onClick(() => {
                    this.resetSandbox();
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)

              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Button(this.ishRunning ? t('沙箱启动中…') : t('启动 Linux 沙箱'))
                    .height(34)
                    .layoutWeight(1)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(9)
                    .onClick(() => {
                      this.runIshSmoke();
                    })
                  if (this.ishReport.length > 0) {
                    Button(t('复制输出'))
                      .height(34)
                      .width(88)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.surface_alt'))
                      .borderRadius(9)
                      .onClick(() => {
                        this.copyIshReport();
                      })
                  }
                }
                .width('100%')

                if (this.ishReport.length > 0) {
                  Scroll() {
                    Text(this.ishReport)
                      .fontSize(10)
                      .fontFamily('monospace')
                      .fontColor($r('app.color.text_secondary'))
                      .width('100%')
                      .copyOption(CopyOptions.LocalDevice)
                  }
                  .height(180)
                  .width('100%')
                  .padding(8)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                } else {
                  Text(t('在原生子进程里启动 iSH ARM64 内核并执行一条冒烟命令；rootfs 随应用分发（含 Python 3），首次使用解压到应用私有目录。'))
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                    .width('100%')
                }
              }
              .width('100%')
            }

            Column() {
              Text(t('人格 / Soul'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              Row({ space: 5 }) {
                ForEach(soulPresets(), (preset: SoulPreset) => {
                  Text(t(preset.name))
                    .layoutWeight(1)
                    .height(30)
                    .fontSize(10)
                    .textAlign(TextAlign.Center)
                    .fontColor(this.soulId === preset.id
                      ? $r('app.color.on_accent')
                      : $r('app.color.text_secondary'))
                    .backgroundColor(this.soulId === preset.id
                      ? $r('app.color.accent')
                      : $r('app.color.surface_alt'))
                    .borderRadius(8)
                    .onClick(() => {
                      this.soulId = preset.id;
                    })
                }, (preset: SoulPreset) => preset.id)
              }
              .width('100%')
              Text(t('人格提示词排在系统提示词之前；会话里的「追加系统提示词」仍可进一步覆盖。'))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')

              this.fieldLabel(t('系统提示词（可选）'))
              TextArea({ text: this.systemPrompt, placeholder: t('例如：你是一名资深鸿蒙应用开发工程师…') })
                .width('100%')
                .constraintSize({ minHeight: 80, maxHeight: 140 })
                .fontSize(12)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onChange((value: string) => {
                  this.systemPrompt = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            this.infoCard()

            Text(t('API Key 保存在本机应用数据中，仅发送到你填写的服务地址。卸载应用会清除全部对话与密钥。'))
              .fontSize(9)
              .fontColor($r('app.color.text_tertiary'))
              .lineHeight(14)
              .width('100%')
          }
          .width('100%')
          .padding({ bottom: 10 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)

        Row({ space: 10 }) {
          Button(t('取消'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(12)
            .onClick(() => this.onCancel())
          Button(t('保存'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(12)
            .onClick(() => this.save())
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('92%')
      .height('90%')
      .constraintSize({ maxWidth: 720 })
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .border({ width: 1, color: $r('app.color.border') })
    }
    .width('100%')
    .height('100%')
  }
}
