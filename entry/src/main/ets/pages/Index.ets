import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatAttachment,
  ChatMessage,
  MessagePart,
  PART_TEXT,
  ProviderPreset,
  SandboxMode,
  SessionFolder,
  SessionMeta,
  SessionSearchEntry,
  StoredSession,
  ThinkingLevel,
  cloneSettings,
  cycleThinkingLevel,
  PART_FILE,
  PART_IMAGE,
  defaultSettings,
  filePart,
  imagePart,
  newChatMessage,
  rerunCutFromTool,
  rewindMessages,
  searchableText,
  sortSessionMetas,
  textOf,
  textPart,
  toolPartKey
} from '../core/Types';
import {
  QueuedPrompt,
  dropQueued,
  enqueueQueued,
  queuedParts
} from '../core/PromptQueue';
import {
  addFolder,
  countFolderSessions,
  findFolder,
  newFolderId,
  removeFolder,
  renameFolder,
  setFolderCollapsed
} from '../core/SessionFolder';
import { capsForModel } from '../core/ModelCaps';
import { BACKGROUND_PREFIX, PROGRESS_PREFIX } from '../core/SubagentJob';
import { ToolRuntime } from '../core/ToolTypes';
import {
  applySessionParams,
  clearSessionParams,
  effectiveSettings,
  isThinkingOverride
} from '../core/SessionParams';
import {
  COMPACT_DEFAULT_KEEP_TURNS,
  CompactPlan,
  SUMMARY_TRANSCRIPT_LIMIT,
  makeSummaryMessage,
  planCompact,
  transcriptForSummary
} from '../core/ContextBudget';
import { AgentRuntime } from '../service/AgentRuntime';
import {
  SummaryResult,
  generateSessionTitle,
  requestModelText,
  summarizeConversation
} from '../service/ChatApi';
import { ModelTestOutcome } from '../core/ModelTest';
import { supportsImageGen } from '../core/ImageGen';
import { supportsFastMode } from '../core/FastMode';
import {
  CONFIG_AUDIT_LIMIT,
  ConfigAuditEntry,
  diffConfig,
  mergeConfigAudit
} from '../core/ConfigAudit';
import { ConfigAuditStore, configSnapshot } from '../service/ConfigAuditStore';
import { UiStateStore } from '../service/UiStateStore';
import {
  TitleSuggestion,
  firstUserText,
  hasAnswer,
  parseTitleSuggestion,
  titleTranscript
} from '../core/SessionTitle';
import { AppLogger } from '../service/AppLogger';
import { CrashLog } from '../service/CrashLog';
import { saveDiagnostics } from '../service/Diagnostics';
import {
  WebDavDownload,
  WebDavOutcome,
  downloadLatestBackup,
  uploadEncryptedBackup
} from '../service/WebDav';
import { BackgroundGuard } from '../service/BackgroundGuard';
import { LocalStore } from '../service/LocalStore';
import { UsageStore } from '../service/UsageStore';
import { LocalToolRuntime } from '../service/LocalToolRuntime';
import {
  BundleImportOutcome,
  ExportOutcome,
  PickedImport,
  importSessionsText,
  pickImportText,
  saveBackup,
  saveEncryptedBackup,
  saveSessionBundle,
  saveSessionJson,
  saveSessionMarkdown
} from '../service/ExportService';
import { BACKUP_MIN_PASSWORD, isEncryptedBackup } from '../core/BackupCrypto';
import { decryptBackupText, DecryptOutcome } from '../service/BackupCrypto';
import { SettingsImageGen, generateImage } from '../service/ImageGen';
import { DeviceTools } from '../service/DeviceTools';
import { ShellTool } from '../service/ShellTool';
import { SandboxIsh } from '../service/SandboxIsh';
import { OAuthService } from '../service/OAuth';
import { ScreenshotOutcome, saveShareCard } from '../service/Screenshot';
import { shareCardFileName } from '../core/ShareCard';
import { shareCardView } from '../components/ShareCardView';
import { AttachmentStore } from '../service/AttachmentStore';
import { MemoryStore } from '../service/MemoryStore';
import { SessionAttachmentUsage, SessionStorageTotal } from '../core/SessionStorage';
import {
  LedgerClearResult,
  SessionWriteRecorder,
  WorkspaceLedger
} from '../service/WorkspaceLedger';
import {
  MemoryFile,
  MemoryLine,
  MemoryLogEntry,
  memoryLineAt,
  memoryLines,
  removeMemoryLine,
  replaceMemoryLine
} from '../core/Memory';
import {
  isMcpEnabled,
  mcpServerActive,
  normalizeMcpDisabled,
  normalizeMcpEnabled,
  setMcpDisabled,
  setMcpEnabled
} from '../core/McpOverrides';
import { SkillDoc, SkillCommand, matchSkillCommand } from '../core/SkillDoc';
import { SkillStore } from '../service/SkillStore';
import { keepScreenOn } from '../service/ScreenWake';
import { RemoteToolRuntime } from '../service/RemoteToolRuntime';
import { McpRegistry, McpRuntime } from '../service/McpRuntime';
import { McpServerConfig } from '../core/McpProtocol';
import { WidgetBridge } from '../service/WidgetBridge';
import { widgetExcerpt } from '../core/WidgetData';
import { mergeBackupSettings } from '../core/Backup';
import { parseBackupSessions } from '../core/SessionExport';
import { SyncMergeResult, mergeSessionSets } from '../core/SyncMerge';
import { parseDeepLink, DeepLink } from '../core/DeepLink';
import {
  BROWSER_ARTIFACT_DIR,
  MINIS_ATTACHMENTS,
  MINIS_BROWSER,
  MINIS_WORKSPACE,
  MinisResource,
  resourceUrl
} from '../core/MinisResource';
import {
  PASTED_DIR,
  isPastedAttachment,
  pasteFileName,
  pastePlaceholder,
  pasteRelativePath,
  pastedRelativePath
} from '../core/Paste';
import {
  ScheduledTask,
  TaskRun,
  formatTaskTime,
  makeRun,
  makeTask,
  normalizeTaskPrompt,
  sortTasks,
  trimRuns,
  validateTaskAt
} from '../core/ScheduledTask';
import {
  ReminderOutcome,
  cancelTaskReminder,
  scheduleTaskReminder
} from '../service/ReminderScheduler';
import { SubagentRunner } from '../service/SubagentRunner';
import { titleFrom } from '../service/Format';
import { ChatView } from '../components/ChatView';
import { ModelPicker } from '../components/ModelPicker';
import { SettingsSheet } from '../components/SettingsSheet';
import { ScheduledTasksSheet } from '../components/ScheduledTasksSheet';
import { WorkspaceSheet } from '../components/WorkspaceSheet';
import { previewWorkspaceFile, WorkspacePreview } from '../service/WorkspaceFiles';
import { OnboardingView } from '../components/OnboardingView';
import { authenticate } from '../service/AppLock';
import {
  clearGenerationNotification,
  publishDone,
  publishGenerating
} from '../service/Notify';
import { SidebarView } from '../components/SidebarView';
import { BrowserPage } from '../components/BrowserPage';
import { HiddenBrowser } from '../components/HiddenBrowser';
import { InlineMathHost } from '../components/InlineMathHost';
import { BrowserTool } from '../service/BrowserTool';
import { t } from '../core/I18n';

/** Snapshot kept only until the compaction notice is dismissed. */
interface CompactUndo {
  sessionId: string;
  messages: ChatMessage[];
  messageCount: number;
}

@Entry
@Component
struct Index {
  @StorageProp('i18nVersion') @Watch('onI18nChanged') i18nVersion: number = 0;
  /**
   * Flipped by onI18nChanged so the whole page subtree is destroyed
   * and built again: ArkUI only refreshes nodes whose bindings
   * changed, and t() lookups are not bindings.
   */
  @State i18nEpoch: number = 0;
  @StorageProp('accentColor') accent: string = '#2F6BFF';
  @StorageProp('fontScale') fontScale: number = 1;
  @StorageProp('pendingShareText') @Watch('onSharedText') sharedText: string = '';
  @StorageProp('pendingShareImages') @Watch('onSharedImages') sharedImages: string = '';
  @StorageProp('pendingDeepLink') @Watch('onDeepLink') deepLink: string = '';
  @State settings: AppSettings = defaultSettings();
  /** Session-level thinking override mirrored for the chat header. */
  @State thinkingOverride: string = '';
  @State sessions: SessionMeta[] = [];
  @State searchEntries: SessionSearchEntry[] = [];
  @State messages: ChatMessage[] = [];
  @State currentId: string = '';
  @State draft: string = '';
  @State pendingAttachments: ChatAttachment[] = [];
  @State streaming: boolean = false;
  /** Prompts typed while generating; injected at the next model boundary. */
  @State queuedPrompts: QueuedPrompt[] = [];
  @State compacting: boolean = false;
  /** One-line notice shown above the composer after a compaction. */
  @State compactNotice: string = '';
  /** False once a newer message makes the snapshot unsafe to restore. */
  @State canUndoCompact: boolean = false;
  @State isWide: boolean = true;
  @State mobileChat: boolean = false;
  @State query: string = '';
  @State showSettings: boolean = false;
  @State configAudit: ConfigAuditEntry[] = [];
  @State showModels: boolean = false;
  @State showWorkspace: boolean = false;
  @State workspaceInitial: string = '';
  @State previewImageOpen: boolean = false;
  @State previewImagePath: string = '';
  @State previewTextOpen: boolean = false;
  @State previewTextTitle: string = '';
  @State previewTextBody: string = '';
  @State previewTextError: string = '';
  @State showTasks: boolean = false;
  @State tasks: ScheduledTask[] = [];
  @State taskRuns: TaskRun[] = [];
  @State showBrowser: boolean = false;
  @State browserUrl: string = '';
  @State showOnboarding: boolean = false;
  @State locked: boolean = false;
  @State unlocking: boolean = false;
  @State deleteId: string = '';
  @State actionId: string = '';
  @State paramsId: string = '';
  /** Session ids whose title request already ran (in-memory; avoids repeats). */
  private titleJobs: string[] = [];
  /** Assistant message ids already counted in the local usage rollup. */
  private usageRecorded: string[] = [];
  @State paramModel: string = '';
  @State paramThinking: string = '';
  @State paramPrompt: string = '';
  @State paramMcpDisabled: string[] = [];
  @State paramMcpEnabled: string[] = [];
  @State memoryOpen: boolean = false;
  @State memoryInjected: string = '';
  @State memoryFiles: MemoryFile[] = [];
  @State memoryDrafts: string[] = [];
  @State memoryOriginals: string[] = [];
  @State memoryLogs: MemoryLogEntry[] = [];
  @State memoryNotice: string = '';
  /** Which file is showing its per-entry list, and which entry is open. */
  @State memoryLineFile: number = -1;
  @State memoryLineIndex: number = -1;
  @State memoryLineDraft: string = '';
  @State rewindId: string = '';
  @State showArchived: boolean = false;
  @State showFolderManager: boolean = false;
  @State folderDraft: string = '';
  @State folderEditId: string = '';
  @State folderEditDraft: string = '';
  /** Session being moved; its action dialog closes while this is open. */
  @State folderMoveId: string = '';
  @State ready: boolean = false;
  @State editing: boolean = false;
  @State editId: string = '';
  @State editText: string = '';
  /** Pending write-tool confirmation; the agent loop waits on it. */
  @State confirmVisible: boolean = false;
  @State confirmName: string = '';
  @State confirmArgs: string = '';
  /** 'encrypt' or 'decrypt' while the backup-password dialog is open. */
  @State passwordVisible: boolean = false;
  @State passwordMode: string = '';
  @State passwordValue: string = '';
  @State passwordConfirm: string = '';
  @State passwordBusy: boolean = false;

  private store: StoredSession[] = [];
  private pendingImportText: string = '';
  private agent: AgentRuntime | null = null;
  private compactUndo: CompactUndo | null = null;
  /** Last turn that triggered auto compaction; prevents a repeat loop. */
  private autoCompactMarker: string = '';
  private browserTool: BrowserTool = new BrowserTool();
  private workspaceRoot: string = '';
  private saveTimer: number = -1;
  private confirmResolve: ((allowed: boolean) => void) | null = null;
  private pageVisible: boolean = true;
  /** Skill body queued by a `/skill-id` command, consumed by the next run. */
  private pendingSkillBody: string = '';
  /** Deep link received before bootstrap finished. */
  private pendingDeepLinkUri: string = '';
  /** Prompt prefilled by a fired task; attributed only if sent unchanged. */
  private pendingTaskId: string = '';
  private pendingTaskPrompt: string = '';
  /** Task whose run is currently streaming, for the run history entry. */
  private activeTaskId: string = '';
  private activeTaskStartedAt: number = 0;
  /** Debounced WebDAV auto-sync; one request at a time. */
  private syncTimer: number = -1;
  private syncRunning: boolean = false;

  aboutToAppear(): void {
    this.bootstrap();
    this.onSharedText();
    this.onSharedImages();
    this.onDeepLink();
  }

  private onDeepLink(): void {
    const uri: string = this.deepLink;
    if (uri.length === 0) {
      return;
    }
    AppStorage.setOrCreate<string>('pendingDeepLink', '');
    if (!this.ready) {
      this.pendingDeepLinkUri = uri;
      return;
    }
    this.applyDeepLink(uri);
  }

  private applyDeepLink(uri: string): void {
    const link: DeepLink | null = parseDeepLink(uri);
    if (link === null) {
      this.toast(t('无法识别的链接'));
      return;
    }
    if (link.kind === 'new') {
      this.mobileChat = true;
      this.createChat();
      return;
    }
    if (link.kind === 'camera') {
      this.mobileChat = true;
      this.createChat();
      this.takePhoto();
      return;
    }
    if (link.kind === 'settings') {
      const sub: string = link.value.toLowerCase();
      if (sub === 'scheduled' || sub === 'scheduled-tasks' ||
        sub === 'scheduled_tasks') {
        this.showTasks = true;
      } else {
        this.showSettings = true;
      }
      return;
    }
    if (link.kind === 'alarm') {
      this.showTasks = true;
      return;
    }
    if (link.kind === 'resource') {
      this.openLinkedResource(link.path !== undefined ? link.path : '');
      return;
    }
    if (link.kind === 'task') {
      const task: ScheduledTask | null = this.findTask(link.value);
      if (task === null) {
        this.toast(t('定时任务已不存在'));
        return;
      }
      // The reminder only restores the prompt; sending stays a user action.
      this.pendingTaskId = task.id;
      this.pendingTaskPrompt = task.prompt;
      this.draft = task.prompt;
      if (task.triggeredAt === 0) {
        this.markTaskTriggered(task);
      }
      this.mobileChat = true;
      this.toast(t('定时任务已填入输入框，确认后发送'));
      return;
    }
    if (this.findSession(link.value) === null) {
      this.toast(t('链接指向的会话不存在'));
      return;
    }
    this.mobileChat = true;
    this.selectSession(link.value);
    if (link.path !== undefined && link.path.length > 0) {
      this.openLinkedResource(link.path);
    }
  }

  /**
   * Deep-link resource paths follow OpenMinis (`/browser/x.html`,
   * `/workspace/a.md`, `/attachments/p.png`). Bare paths are workspace files.
   */
  private openLinkedResource(raw: string): void {
    let path: string = raw;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.length === 0) {
      return;
    }
    const cut: number = path.indexOf('/');
    const scope: string = (cut < 0 ? path : path.substring(0, cut)).toLowerCase();
    const rest: string = cut < 0 ? '' : path.substring(cut + 1);
    if (rest.length > 0 &&
      (scope === MINIS_WORKSPACE || scope === MINIS_BROWSER ||
        scope === MINIS_ATTACHMENTS)) {
      this.openMinisResource({ scope: scope, path: rest });
      return;
    }
    this.openMinisResource({ scope: MINIS_WORKSPACE, path: path });
  }

  private findTask(id: string): ScheduledTask | null {
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === id) {
        return this.tasks[i];
      }
    }
    return null;
  }

  /** Replaces the list through a fresh array so @State observers fire. */
  private replaceTasks(next: ScheduledTask[]): void {
    this.tasks = sortTasks(next);
    LocalStore.saveScheduledTasks(this.tasks).catch((error: Error) => {
      this.toast(t('定时任务保存失败'));
    });
  }

  private markTaskTriggered(task: ScheduledTask): void {
    const next: ScheduledTask[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      const item: ScheduledTask = this.tasks[i];
      if (item.id !== task.id) {
        next.push(item);
      } else {
        next.push({
          id: item.id,
          prompt: item.prompt,
          at: item.at,
          reminderId: item.reminderId,
          createdAt: item.createdAt,
          triggeredAt: Date.now()
        });
      }
    }
    this.replaceTasks(next);
  }

  private async createScheduledTask(prompt: string, at: number): Promise<void> {
    const text: string = normalizeTaskPrompt(prompt);
    const reason: string = validateTaskAt(at, Date.now());
    if (text.length === 0) {
      this.toast(t('请填写提示词'));
      return;
    }
    if (reason.length > 0) {
      this.toast(reason);
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const task: ScheduledTask =
      makeTask(util.generateRandomUUID(true), text, at, Date.now());
    const outcome: ReminderOutcome = await scheduleTaskReminder(context, task);
    if (!outcome.ok) {
      this.toast(outcome.message);
      return;
    }
    task.reminderId = outcome.reminderId;
    this.replaceTasks(this.tasks.concat([task]));
    this.toast(t('已安排提醒：') + formatTaskTime(at, Date.now()));
  }

  private async cancelScheduledTask(id: string): Promise<void> {
    const task: ScheduledTask | null = this.findTask(id);
    if (task === null) {
      return;
    }
    await cancelTaskReminder(task.reminderId);
    const next: ScheduledTask[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id !== id) {
        next.push(this.tasks[i]);
      }
    }
    this.replaceTasks(next);
    if (this.pendingTaskId === id) {
      this.pendingTaskId = '';
      this.pendingTaskPrompt = '';
    }
    this.toast(t('已删除定时任务'));
  }

  private fillTask(id: string): void {
    const task: ScheduledTask | null = this.findTask(id);
    if (task === null) {
      return;
    }
    this.pendingTaskId = task.id;
    this.pendingTaskPrompt = task.prompt;
    this.draft = task.prompt;
    this.showTasks = false;
    this.toast(t('已填入输入框，确认后发送'));
  }

  private clearTaskRuns(): void {
    this.taskRuns = [];
    LocalStore.saveTaskRuns([]).catch((error: Error) => {
      this.toast(t('历史记录保存失败'));
    });
  }

  /** A run counts as the task's only when the prefilled prompt was sent as-is. */
  private attributeTaskSend(text: string): void {
    if (this.pendingTaskId.length === 0) {
      return;
    }
    if (text.trim() === this.pendingTaskPrompt) {
      this.activeTaskId = this.pendingTaskId;
      this.activeTaskStartedAt = Date.now();
    }
    this.pendingTaskId = '';
    this.pendingTaskPrompt = '';
  }

  private appendTaskRun(
    task: ScheduledTask,
    startedAt: number,
    replyText: string,
    errorText: string
  ): void {
    const run: TaskRun = makeRun(util.generateRandomUUID(true), task, startedAt,
      replyText, errorText, Date.now());
    this.taskRuns = trimRuns([run].concat(this.taskRuns));
    LocalStore.saveTaskRuns(this.taskRuns).catch((error: Error) => {
      this.toast(t('运行历史保存失败'));
    });
    // One-shot: the reminder has served its purpose.
    const remaining: ScheduledTask[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id !== task.id) {
        remaining.push(this.tasks[i]);
      }
    }
    this.replaceTasks(remaining);
  }

  private finishTaskRun(session: StoredSession): void {
    const taskId: string = this.activeTaskId;
    if (taskId.length === 0) {
      return;
    }
    const started: number = this.activeTaskStartedAt > 0
      ? this.activeTaskStartedAt
      : Date.now();
    this.activeTaskId = '';
    this.activeTaskStartedAt = 0;
    const task: ScheduledTask | null = this.findTask(taskId);
    if (task === null) {
      return;
    }
    let reply: string = '';
    let failed: boolean = false;
    for (let i = session.messages.length - 1; i >= 0; i--) {
      const message: ChatMessage = session.messages[i];
      if (message.role === 'assistant') {
        reply = textOf(message);
        failed = message.error;
        break;
      }
    }
    this.appendTaskRun(task, started, failed ? '' : reply, failed ? reply : '');
  }

  /** Stopping keeps a short record instead of losing the run silently. */
  private abandonTaskRun(): void {
    const taskId: string = this.activeTaskId;
    if (taskId.length === 0) {
      return;
    }
    const started: number = this.activeTaskStartedAt > 0
      ? this.activeTaskStartedAt
      : Date.now();
    this.activeTaskId = '';
    this.activeTaskStartedAt = 0;
    const task: ScheduledTask | null = this.findTask(taskId);
    if (task !== null) {
      this.appendTaskRun(task, started, '', t('已取消'));
    }
  }

  /** Another app shared text: prefill the composer, never auto-send. */
  private onSharedText(): void {
    const text: string = this.sharedText;
    if (text.length === 0) {
      return;
    }
    this.draft = text;
    AppStorage.setOrCreate<string>('pendingShareText', '');
    this.toast(t('已填入分享内容'));
  }

  /** Another app shared images: copy them into the attachment directory. */
  private onSharedImages(): void {
    const raw: string = this.sharedImages;
    if (raw.length === 0) {
      return;
    }
    AppStorage.setOrCreate<string>('pendingShareImages', '');
    this.importSharedImages(raw).catch((error: Error) => {
    });
  }

  private async importSharedImages(raw: string): Promise<void> {
    const uris: string[] = [];
    try {
      const parsed: Object = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return;
      }
      const list: Object[] = parsed as Object[];
      for (let i = 0; i < list.length; i++) {
        const item: Object = list[i];
        if (typeof item === 'string' && (item as string).length > 0) {
          uris.push(item as string);
        }
      }
    } catch (e) {
      return;
    }
    const next: ChatAttachment[] = this.pendingAttachments.slice();
    let failed: number = 0;
    let added: number = 0;
    for (let i = 0; i < uris.length; i++) {
      const info = await AttachmentStore.saveFromUri(uris[i]);
      if (info === null) {
        failed++;
        continue;
      }
      next.push({
        uri: AttachmentStore.uriFor(info.name),
        mimeType: info.mimeType,
        path: AttachmentStore.absolutePath(info.name)
      });
      added++;
    }
    this.pendingAttachments = next;
    if (failed > 0) {
      this.toast(failed.toString() + t(' 张图片无法读取（格式或大小不支持）'));
    }
    if (added > 0) {
      const session: StoredSession | null = this.findSession(this.currentId);
      const modelId: string = session !== null
        ? effectiveSettings(this.settings, session.meta).modelId
        : this.settings.modelId;
      if (!capsForModel(modelId).vision) {
        this.toast(t('当前模型未标记视觉能力，图片可能被拒绝'));
      }
    }
  }

  onPageShow(): void {
    this.pageVisible = true;
    clearGenerationNotification();
  }

  /** Background generation continues; the notification centre reports it. */
  onPageHide(): void {
    this.pageVisible = false;
    if (this.streaming) {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      publishGenerating(context, this.currentTitle());
    }
  }

  aboutToDisappear(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    if (this.syncTimer !== -1) {
      clearTimeout(this.syncTimer);
      this.syncTimer = -1;
    }
    this.persistNow();
    if (this.agent !== null) {
      this.agent.cancel();
      this.agent = null;
    }
    BackgroundGuard.end().catch((error: Error) => {});
  }

  private async bootstrap(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.workspaceRoot = context.filesDir + '/workspace';
    WorkspaceLedger.init(
      context.filesDir + '/workspace-ledger.json', this.workspaceRoot);
    MemoryStore.init(context.filesDir + '/memory');
    SkillStore.init(context.filesDir + '/skills');
    AttachmentStore.init(context.filesDir + '/attachments');
    try {
      await LocalStore.init(context);
      await OAuthService.init();
      await SubagentRunner.restore();
    } catch (e) {
      this.toast(t('本地存储初始化失败，本次会话不会保存'));
    }
    this.settings = await LocalStore.loadSettings();
    this.configAudit = ConfigAuditStore.load(context);
    this.applyAppearance(this.settings);
    AppLogger.init(context, this.settings.loggingEnabled);
    CrashLog.init(context);
    // Discovery is best-effort; an offline server just contributes no tools.
    McpRegistry.refresh(this.settings.mcpServers, false, this.hasMcpForceEnabled())
      .catch((error: Error) => {});
    const loaded: StoredSession[] = await LocalStore.loadSessions();
    this.store = loaded;
    // A result that arrived while the app was closed has not been answered
    // yet; the sidebar says so until the session is opened.
    for (let i = 0; i < loaded.length; i++) {
      if (this.hasPendingBackgroundResult(loaded[i])) {
        loaded[i].meta.statusBadge = 'background';
      }
    }
    this.refreshSessions();
    this.tasks = await LocalStore.loadScheduledTasks();
    this.taskRuns = await LocalStore.loadTaskRuns();
    if (loaded.length > 0) {
      const lastId: string = UiStateStore.lastSession(context);
      let initial: StoredSession = loaded[0];
      for (let i = 0; i < loaded.length; i++) {
        if (loaded[i].meta.id === lastId) {
          initial = loaded[i];
          break;
        }
      }
      this.currentId = initial.meta.id;
      this.messages = initial.messages.slice();
      this.syncThinkingOverride();
      this.mobileChat = true;
      // Opening a session acknowledges whatever badge it carried.
      if (initial.meta.statusBadge !== undefined && initial.meta.statusBadge.length > 0) {
        initial.meta.statusBadge = '';
        this.refreshSessions();
      }
      if (this.hasPendingBackgroundResult(initial)) {
        this.runAgent(initial, '', false);
      }
    } else {
      this.createChat(false);
      this.mobileChat = false;
    }
    // Only first-time users without a key see the guide; existing installs
    // already configured are left alone.
    this.showOnboarding = !this.settings.onboardingDone &&
      this.settings.apiKey.trim().length === 0;
    this.ready = true;
    // Refresh the home-screen card once the component is attached.
    setTimeout(() => this.publishWidget(), 0);
    this.scheduleAutoSync();
    if (this.pendingDeepLinkUri.length > 0) {
      const uri: string = this.pendingDeepLinkUri;
      this.pendingDeepLinkUri = '';
      this.applyDeepLink(uri);
    }
    if (this.settings.appLockEnabled) {
      this.lockApp();
    }
  }

  private async lockApp(): Promise<void> {
    if (this.unlocking) {
      return;
    }
    this.locked = true;
    this.unlocking = true;
    const unlocked: boolean = await authenticate(t('解锁 Minis Harmony'));
    this.unlocking = false;
    if (unlocked) {
      this.locked = false;
    }
  }

  private finishOnboarding(apiKey: string, skipped: boolean): void {
    const next: AppSettings = cloneSettings(this.settings);
    next.onboardingDone = true;
    if (!skipped && apiKey.length > 0) {
      next.apiKey = apiKey;
    }
    this.settings = next;
    this.showOnboarding = false;
    LocalStore.saveSettings(next).catch((error: Error) => {
      this.toast(t('设置保存失败'));
    });
    if (!skipped && apiKey.length > 0) {
      this.toast(t('已保存 API Key'));
    }
  }

  private findSession(id: string): StoredSession | null {
    for (let i = 0; i < this.store.length; i++) {
      if (this.store[i].meta.id === id) {
        return this.store[i];
      }
    }
    return null;
  }

  private buildMetaList(): SessionMeta[] {
    const metas: SessionMeta[] = this.store.map((session: StoredSession): SessionMeta => session.meta);
    return sortSessionMetas(metas);
  }

  private buildSearchIndex(): SessionSearchEntry[] {
    const entries: SessionSearchEntry[] = [];
    for (let i = 0; i < this.store.length; i++) {
      const entry: SessionSearchEntry = {
        id: this.store[i].meta.id,
        text: searchableText(this.store[i])
      };
      entries.push(entry);
    }
    return entries;
  }

  /** Metadata list plus the full-text index; use on non-hot paths only. */
  private refreshSessions(): void {
    this.sessions = this.buildMetaList();
    this.searchEntries = this.buildSearchIndex();
  }

  private currentTitle(): string {
    const session: StoredSession | null = this.findSession(this.currentId);
    return session === null ? t('新对话') : session.meta.title;
  }

  /**
   * After a settled turn, replace the derived first-line title with a model
   * title. Runs once per session and silently keeps the derived title when the
   * request fails, so offline use is unaffected.
   */
  private maybeAutoTitle(session: StoredSession): void {
    if (!this.settings.autoTitleEnabled) {
      return;
    }
    if (this.titleJobs.indexOf(session.meta.id) >= 0 || !hasAnswer(session.messages)) {
      return;
    }
    const first: string = firstUserText(session.messages);
    const derived: string = first.length > 0 ? titleFrom(first) : t('图片对话');
    const current: string = session.meta.title;
    if (current.length > 0 && current !== derived && current !== t('新对话')) {
      return;
    }
    this.requestTitle(session, false);
  }

  /**
   * Add the settled turn's last reported token usage to the local rollup.
   * Only assistant messages that carry usage are counted, and each id once.
   */
  private recordUsage(session: StoredSession): void {
    let last: ChatMessage | null = null;
    for (let i = session.messages.length - 1; i >= 0; i--) {
      const message: ChatMessage = session.messages[i];
      if (message.role === 'assistant' && message.totalTokens > 0) {
        last = message;
        break;
      }
    }
    if (last === null || this.usageRecorded.indexOf(last.id) >= 0) {
      return;
    }
    this.usageRecorded.push(last.id);
    if (this.usageRecorded.length > 300) {
      this.usageRecorded = this.usageRecorded.slice(this.usageRecorded.length - 300);
    }
    const effective: AppSettings = effectiveSettings(this.settings, session.meta);
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    UsageStore.record(context, effective.modelId, effective.preset,
      last.promptTokens, last.completionTokens);
  }

  private forgetTitle(sessionId: string): void {
    const at: number = this.titleJobs.indexOf(sessionId);
    if (at >= 0) {
      this.titleJobs.splice(at, 1);
    }
  }

  /**
   * Folder names offered to title generation. Auto-grouping only applies to
   * conversations the user has not filed yet, and only when the setting is on.
   * Names are deduped case-insensitively so the model sees each group once.
   */
  private offeredFolderNames(session: StoredSession): string[] {
    if (!this.settings.autoGroupingEnabled) {
      return [];
    }
    const current: string = session.meta.folderId !== undefined
      ? session.meta.folderId : '';
    if (current.length > 0) {
      return [];
    }
    const names: string[] = [];
    for (let i = 0; i < this.settings.sessionFolders.length; i++) {
      const name: string = this.settings.sessionFolders[i].name.trim();
      if (name.length === 0) {
        continue;
      }
      let seen: boolean = false;
      for (let j = 0; j < names.length; j++) {
        if (names[j].toLowerCase() === name.toLowerCase()) {
          seen = true;
          break;
        }
      }
      if (!seen) {
        names.push(name);
      }
    }
    return names;
  }

  /** Apply a folder the model picked; never create a group from its answer. */
  private applyTitleFolder(session: StoredSession, folder: string): void {
    if (folder.length === 0) {
      return;
    }
    const current: string = session.meta.folderId !== undefined
      ? session.meta.folderId : '';
    if (current.length > 0) {
      return;
    }
    for (let i = 0; i < this.settings.sessionFolders.length; i++) {
      if (this.settings.sessionFolders[i].name.toLowerCase() === folder.toLowerCase()) {
        session.meta.folderId = this.settings.sessionFolders[i].id;
        return;
      }
    }
  }

  /** Ask the model for a title; `manual` also reports failures to the user. */
  private async requestTitle(session: StoredSession, manual: boolean): Promise<void> {
    if (this.titleJobs.indexOf(session.meta.id) >= 0) {
      if (!manual) {
        return;
      }
      this.forgetTitle(session.meta.id);
    }
    const transcript: string = titleTranscript(session.messages);
    if (transcript.length === 0) {
      if (manual) {
        this.toast(t('对话还太短，无法生成标题'));
      }
      return;
    }
    this.titleJobs.push(session.meta.id);
    if (manual) {
      this.toast(t('正在生成标题…'));
    }
    const settings: AppSettings =
      await OAuthService.decorate(effectiveSettings(this.settings, session.meta));
    const folders: string[] = this.offeredFolderNames(session);
    const result: SummaryResult = await generateSessionTitle(
      settings, session.meta.id, transcript, folders);
    if (!result.ok) {
      this.forgetTitle(session.meta.id);
      if (manual) {
        this.toast(t('标题生成失败：') + result.message);
      }
      return;
    }
    const suggestion: TitleSuggestion = parseTitleSuggestion(result.text, folders);
    const title: string = suggestion.title;
    if (title.length === 0) {
      this.forgetTitle(session.meta.id);
      if (manual) {
        this.toast(t('标题生成失败：模型返回了空标题'));
      }
      return;
    }
    session.meta.title = title;
    this.applyTitleFolder(session, suggestion.folder);
    this.refreshSessions();
    this.persistSoon();
    if (manual) {
      this.toast(t('已更新标题'));
    }
  }

  /** One tiny non-streaming request against a model from the picker. */
  private async testModel(id: string): Promise<ModelTestOutcome> {
    const next: AppSettings = cloneSettings(this.settings);
    next.modelId = id;
    const settings: AppSettings = await OAuthService.decorate(next);
    const started: number = Date.now();
    const result: SummaryResult = await requestModelText(
      settings, 'model-test', 'Ping',
      t('这是一次连通性测试，请只回复 OK。'), 32);
    return {
      ok: result.ok,
      text: result.text,
      message: result.message,
      elapsedMs: Date.now() - started
    };
  }

  /**
   * Image self-test from the picker. OpenMinis picks this test for models
   * whose output modalities include images; our catalog has no modality
   * metadata, so the entry is offered whenever image generation is enabled
   * and the preset speaks the OpenAI-compatible image API.
   */
  private async testModelImage(id: string): Promise<ModelTestOutcome> {
    const started: number = Date.now();
    if (!this.settings.imageGenEnabled) {
      return {
        ok: false,
        text: '',
        message: t('图像生成未开启。请先在设置中允许图像生成。'),
        elapsedMs: Date.now() - started
      };
    }
    if (!supportsImageGen(this.settings.preset)) {
      return {
        ok: false,
        text: '',
        message: t('图像生成仅支持 OpenAI 兼容协议，请切换预设或使用自定义端点'),
        elapsedMs: Date.now() - started
      };
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.modelId = id;
    const result = await generateImage(
      next,
      'A friendly cute mascot logo for an app called Minis, minimalist, centered, soft colors',
      '1024x1024', id);
    if (!result.ok || result.attachment === null) {
      return {
        ok: false,
        text: '',
        message: result.message,
        elapsedMs: Date.now() - started
      };
    }
    return {
      ok: true,
      text: '',
      message: t('已生成图片'),
      elapsedMs: Date.now() - started,
      imageUri: AttachmentStore.uriFor(result.attachment.name)
    };
  }

  /** Model actually used for the current conversation (override wins). */
  private effectiveModelId(): string {
    const session: StoredSession | null = this.findSession(this.currentId);
    const override: string = session !== null && session.meta.modelOverride !== undefined
      ? session.meta.modelOverride.trim()
      : '';
    return override.length > 0 ? override : this.settings.modelId;
  }

  private effectiveThinking(): ThinkingLevel {
    return isThinkingOverride(this.thinkingOverride)
      ? this.thinkingOverride as ThinkingLevel
      : this.settings.thinkingLevel;
  }

  /** Anthropic/Gemini ignore reasoning_effort, so the entry is hidden there. */
  private canSetThinking(): boolean {
    if (this.settings.preset === 'anthropic' || this.settings.preset === 'gemini') {
      return false;
    }
    return capsForModel(this.effectiveModelId()).reasoning;
  }

  private syncThinkingOverride(): void {
    const session: StoredSession | null = this.findSession(this.currentId);
    const value: string = session !== null && session.meta.thinkingOverride !== undefined
      ? session.meta.thinkingOverride
      : '';
    this.thinkingOverride = isThinkingOverride(value) ? value : '';
  }

  private setThinkingLevel(value: string): void {
    if (!isThinkingOverride(value)) {
      return;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    session.meta.thinkingOverride = value;
    session.meta.updatedAt = Date.now();
    this.thinkingOverride = value;
    this.refreshSessions();
    this.persistSoon();
    this.toast(value === 'off' ? t('本会话思考已关闭') : t('本会话思考强度：') + this.thinkingLabel(value));
  }

  /**
   * Global fast mode. Providers that do not document `service_tier` are refused
   * instead of being sent a body field that some relays reject.
   */
  private setFastMode(on: boolean): void {
    if (on && !supportsFastMode(this.settings.preset, this.settings.baseUrl)) {
      this.toast(t('当前供应商不支持快速模式'));
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.fastMode = on;
    this.recordConfigChanges(this.settings, next);
    this.settings = next;
    LocalStore.saveSettings(next).catch((error: Error) => {
      this.toast(t('设置保存失败'));
    });
    this.toast(on ? t('已开启快速模式') : t('已关闭快速模式'));
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
  }

  private isImagePath(path: string): boolean {
    const lower: string = path.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') || lower.endsWith('.gif') || lower.endsWith('.bmp') ||
      lower.endsWith('.svg') || lower.endsWith('.heic');
  }

  /**
   * A `minis://workspace/<path>` link in a reply opens the file preview;
   * image links open the full-screen viewer instead. Attachment links point
   * into the chat attachment directory and use the same viewer.
   */
  private openMinisResource(resource: MinisResource): void {
    if (resource.scope === MINIS_WORKSPACE) {
      if (this.isImagePath(resource.path)) {
        this.previewImagePath = this.workspaceRoot + '/' + resource.path;
        this.previewImageOpen = true;
        return;
      }
      this.workspaceInitial = resource.path;
      this.showWorkspace = true;
      return;
    }
    if (resource.scope === MINIS_BROWSER) {
      const path: string = BROWSER_ARTIFACT_DIR + '/' + resource.path;
      if (this.isImagePath(resource.path)) {
        this.previewImagePath = this.workspaceRoot + '/' + path;
        this.previewImageOpen = true;
        return;
      }
      this.workspaceInitial = path;
      this.showWorkspace = true;
      return;
    }
    if (resource.scope === MINIS_ATTACHMENTS) {
      if (this.isImagePath(resource.path)) {
        this.previewImagePath = AttachmentStore.absolutePath(resource.path);
        this.previewImageOpen = true;
        return;
      }
      this.openAttachmentPreview(resource.path);
      return;
    }
    this.toast(t('不支持的链接类型'));
  }

  /** Read-only preview for text-like chat attachments (md, txt, json, csv…). */
  private openAttachmentPreview(path: string): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const preview: WorkspacePreview =
      previewWorkspaceFile(context.filesDir + '/attachments', path);
    const slash: number = path.lastIndexOf('/');
    this.previewTextTitle = slash < 0 ? path : path.substring(slash + 1);
    this.previewTextBody = preview.text;
    this.previewTextError = preview.ok ? '' : preview.error;
    this.previewTextOpen = true;
  }

  /**
   * Render the turn offscreen (full height, independent of the scroll
   * position) and save it as a PNG through the system document picker.
   */
  private async shareTurn(message: ChatMessage, question: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const title: string = this.currentTitle();
    const outcome: ScreenshotOutcome = await saveShareCard(
      context,
      this.getUIContext(),
      () => {
        shareCardView(question, message, title, this.accent);
      },
      shareCardFileName(title, new Date())
    );
    this.toast(outcome.message);
  }

  private createChat(persist: boolean = true, folderId: string = ''): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const meta: SessionMeta = {
      id: util.generateRandomUUID(true),
      title: t('新对话'),
      updatedAt: Date.now(),
      modelId: this.settings.modelId,
      messageCount: 0,
      pinned: false,
      archived: false
    };
    if (folderId.length > 0) {
      meta.folderId = folderId;
    }
    const session: StoredSession = { meta: meta, messages: [] };
    this.store = [session].concat(this.store);
    this.refreshSessions();
    this.currentId = meta.id;
    this.rememberSession(meta.id);
    this.messages = [];
    this.thinkingOverride = '';
    this.compactNotice = '';
    this.compactUndo = null;
    this.canUndoCompact = false;
    this.draft = '';
    this.mobileChat = true;
    if (persist) {
      this.persistSoon();
    }
  }

  /** Restored at launch so the app reopens where the user left off. */
  private rememberSession(id: string): void {
    if (id.length === 0) {
      return;
    }
    try {
      const context: common.UIAbilityContext =
        getContext(this) as common.UIAbilityContext;
      UiStateStore.rememberSession(context, id);
    } catch (e) {
    }
  }

  /** Set or clear the transient sidebar badge and refresh the list. */
  private setSessionBadge(id: string, badge: string, persist: boolean): void {
    const session: StoredSession | null = this.findSession(id);
    if (session === null || session.meta.statusBadge === badge) {
      return;
    }
    session.meta.statusBadge = badge;
    // Badges do not affect the search index, so skip the full rebuild.
    this.sessions = this.buildMetaList();
    if (persist) {
      this.persistSoon();
    }
  }

  private markSyncing(on: boolean): void {
    for (let i = 0; i < this.store.length; i++) {
      if (on) {
        this.store[i].meta.statusBadge = 'syncing';
      } else if (this.store[i].meta.statusBadge === 'syncing') {
        this.store[i].meta.statusBadge = '';
      }
    }
    this.sessions = this.buildMetaList();
  }

  private selectSession(id: string): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const session: StoredSession | null = this.findSession(id);
    if (session === null) {
      return;
    }
    this.setSessionBadge(id, '', true);
    this.currentId = id;
    this.rememberSession(id);
    this.messages = session.messages.slice();
    this.syncThinkingOverride();
    this.compactNotice = '';
    this.compactUndo = null;
    this.canUndoCompact = false;
    this.draft = '';
    this.mobileChat = true;
    this.publishWidget();
    if (!this.streaming && this.hasPendingBackgroundResult(session)) {
      this.runAgent(session, '', false);
    }
  }

  private requestDelete(id: string): void {
    this.deleteId = id;
  }

  private requestActions(id: string): void {
    this.actionId = id;
  }

  private actionPinned(): boolean {
    const session: StoredSession | null = this.findSession(this.actionId);
    return session !== null && session.meta.pinned;
  }

  private actionArchived(): boolean {
    const session: StoredSession | null = this.findSession(this.actionId);
    return session !== null && session.meta.archived;
  }

  private togglePin(): void {
    const session: StoredSession | null = this.findSession(this.actionId);
    this.actionId = '';
    if (session === null) {
      return;
    }
    session.meta.pinned = !session.meta.pinned;
    this.refreshSessions();
    this.persistSoon();
    this.toast(session.meta.pinned ? t('已置顶') : t('已取消置顶'));
  }

  private toggleArchive(): void {
    const session: StoredSession | null = this.findSession(this.actionId);
    this.actionId = '';
    if (session === null) {
      return;
    }
    session.meta.archived = !session.meta.archived;
    if (!session.meta.archived && !this.showArchived) {
      this.showArchived = true;
    }
    this.refreshSessions();
    this.persistSoon();
    this.toast(session.meta.archived ? t('已归档') : t('已取消归档'));
  }

  private folderCount(folderId: string): number {
    return countFolderSessions(this.sessions, folderId);
  }

  private toggleFolder(id: string): void {
    const folder = findFolder(this.settings.sessionFolders, id);
    if (folder === null) {
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.sessionFolders = setFolderCollapsed(next.sessionFolders, id, !folder.collapsed);
    this.settings = next;
    this.persistSoon();
  }

  private createFolder(): void {
    const name: string = this.folderDraft.trim();
    if (name.length === 0) {
      return;
    }
    const current: AppSettings = cloneSettings(this.settings);
    const id: string = newFolderId(current.sessionFolders, Date.now());
    const next: SessionFolder[] = addFolder(current.sessionFolders, name, id);
    if (next === current.sessionFolders) {
      return;
    }
    current.sessionFolders = next;
    this.settings = current;
    this.folderDraft = '';
    this.persistSoon();
  }

  private beginFolderRename(id: string): void {
    const folder = findFolder(this.settings.sessionFolders, id);
    if (folder === null) {
      return;
    }
    this.folderEditId = id;
    this.folderEditDraft = folder.name;
  }

  private commitFolderRename(): void {
    if (this.folderEditId.length === 0) {
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.sessionFolders = renameFolder(next.sessionFolders,
      this.folderEditId, this.folderEditDraft);
    this.settings = next;
    this.folderEditId = '';
    this.folderEditDraft = '';
    this.persistSoon();
  }

  /** Deleting a folder keeps its conversations, now under "未分组". */
  private deleteFolder(id: string): void {
    const next: AppSettings = cloneSettings(this.settings);
    next.sessionFolders = removeFolder(next.sessionFolders, id);
    this.settings = next;
    for (let i = 0; i < this.store.length; i++) {
      if (this.store[i].meta.folderId === id) {
        this.store[i].meta.folderId = '';
      }
    }
    if (this.folderEditId === id) {
      this.folderEditId = '';
      this.folderEditDraft = '';
    }
    this.refreshSessions();
    this.persistSoon();
  }

  private moveSessionToFolder(folderId: string): void {
    const session: StoredSession | null = this.findSession(this.folderMoveId);
    this.folderMoveId = '';
    if (session === null) {
      return;
    }
    session.meta.folderId = folderId;
    this.refreshSessions();
    this.persistSoon();
  }

  private createChatInFolder(folderId: string): void {
    this.createChat(true, folderId);
  }

  /**
   * Rewind to an earlier message: everything after it is dropped, the message
   * itself is kept as the new end of the conversation. The user can then edit
   * it or send a new turn from that checkpoint.
   */
  private requestRewind(id: string): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    this.rewindId = id;
  }

  private rewindCount(): number {
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return 0;
    }
    for (let i = 0; i < session.messages.length; i++) {
      if (session.messages[i].id === this.rewindId) {
        return session.messages.length - i - 1;
      }
    }
    return 0;
  }

  private performRewind(): void {
    const id: string = this.rewindId;
    this.rewindId = '';
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    const trimmed: ChatMessage[] | null =
      rewindMessages(session.messages, id);
    if (trimmed === null) {
      return;
    }
    session.messages = trimmed;
    session.meta.messageCount = trimmed.length;
    session.meta.updatedAt = Date.now();
    this.messages = trimmed.slice();
    this.refreshSessions();
    this.persistSoon();
    this.toast(t('已回退到该消息'));
  }

  /**
   * Re-run from a tool call: trim the transcript at the block boundary and
   * let the model decide again with the same history it had just before the
   * call. Matches OpenMinis' "Re-run From Here" (including its rule that only
   * an idle session may be trimmed).
   */
  private rerunFromTool(messageId: string, part: MessagePart): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    const trimmed: ChatMessage[] | null =
      rerunCutFromTool(session.messages, messageId, toolPartKey(part));
    if (trimmed === null) {
      this.toast(t('无法从此处重跑'));
      return;
    }
    session.messages = trimmed;
    session.meta.messageCount = trimmed.length;
    session.meta.updatedAt = Date.now();
    this.messages = trimmed.slice();
    this.refreshSessions();
    this.persistSoon();
    this.runAgent(session, '', false);
  }

  private async exportSession(id: string): Promise<void> {
    const session: StoredSession | null = this.findSession(id);
    this.actionId = '';
    if (session === null) {
      return;
    }
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ExportOutcome = await saveSessionMarkdown(context, session);
    this.toast(outcome.message);
  }

  private async exportSessionJson(id: string): Promise<void> {
    const session: StoredSession | null = this.findSession(id);
    this.actionId = '';
    if (session === null) {
      return;
    }
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ExportOutcome = await saveSessionJson(context, session);
    this.toast(outcome.message);
  }

  private async importSessionFromFile(): Promise<void> {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const picked: PickedImport = await pickImportText(context);
    if (!picked.ok) {
      this.toast(picked.message);
      return;
    }
    if (isEncryptedBackup(picked.text)) {
      this.openPasswordDialog('decrypt', picked.text);
      return;
    }
    const outcome: BundleImportOutcome = importSessionsText(picked.text,
      () => util.generateRandomUUID(true));
    this.applyImportOutcome(outcome);
  }

  private applyImportOutcome(outcome: BundleImportOutcome): void {
    if (!outcome.ok || outcome.sessions.length === 0) {
      this.toast(outcome.message);
      return;
    }
    const imported: StoredSession[] = outcome.sessions;
    if (outcome.settings !== null) {
      const merged: AppSettings = mergeBackupSettings(this.settings, outcome.settings);
      this.settings = merged;
      this.applyAppearance(merged);
      AppLogger.setEnabled(merged.loggingEnabled);
      LocalStore.saveSettings(merged).catch((error: Error) => {
        this.toast(t('设置保存失败'));
      });
      McpRegistry.refresh(merged.mcpServers, false, this.hasMcpForceEnabled())
        .catch((error: Error) => {});
    }
    this.store = imported.concat(this.store);
    this.refreshSessions();
    this.currentId = imported[0].meta.id;
    this.messages = imported[0].messages.slice();
    this.draft = '';
    this.mobileChat = true;
    this.persistSoon();
    this.toast(outcome.message);
  }

  private openPasswordDialog(mode: string, importText: string): void {
    this.passwordMode = mode;
    this.passwordValue = '';
    this.passwordConfirm = '';
    this.passwordBusy = false;
    this.pendingImportText = importText;
    this.passwordVisible = true;
  }

  private closePasswordDialog(): void {
    if (this.passwordBusy) {
      return;
    }
    this.passwordVisible = false;
    this.passwordValue = '';
    this.passwordConfirm = '';
    this.pendingImportText = '';
  }

  /** Create an encrypted backup, or decrypt the pending import file. */
  private async submitPassword(): Promise<void> {
    if (this.passwordBusy) {
      return;
    }
    if (this.passwordMode === 'encrypt') {
      if (this.passwordValue.length < BACKUP_MIN_PASSWORD) {
        this.toast(t('密码至少 ') + BACKUP_MIN_PASSWORD.toString() + t(' 位'));
        return;
      }
      if (this.passwordValue !== this.passwordConfirm) {
        this.toast(t('两次输入的密码不一致'));
        return;
      }
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      this.passwordBusy = true;
      const outcome: ExportOutcome = await saveEncryptedBackup(
        context, this.settings, this.store, this.passwordValue);
      this.passwordBusy = false;
      if (outcome.ok) {
        this.passwordVisible = false;
        this.passwordValue = '';
        this.passwordConfirm = '';
      }
      this.toast(outcome.message);
      return;
    }
    if (this.passwordMode !== 'decrypt') {
      return;
    }
    if (this.passwordValue.length === 0) {
      this.toast(t('请输入备份密码'));
      return;
    }
    this.passwordBusy = true;
    const decrypted: DecryptOutcome = await decryptBackupText(
      this.pendingImportText, this.passwordValue);
    this.passwordBusy = false;
    if (!decrypted.ok) {
      this.toast(decrypted.message);
      return;
    }
    this.passwordVisible = false;
    this.pendingImportText = '';
    this.passwordValue = '';
    this.applyImportOutcome(importSessionsText(decrypted.text,
      () => util.generateRandomUUID(true)));
  }

  /** Ask for a password, then export the whole library encrypted. */
  private exportEncryptedBackup(): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    this.openPasswordDialog('encrypt', '');
  }

  /**
   * Diagnostics: environment, non-secret settings summary, counts, collected
   * crash/freeze records and the redacted event log. Never prompts or keys.
   */
  private async exportDiagnostics(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ExportOutcome = await saveDiagnostics(
      context, this.settings, this.store);
    this.toast(outcome.message);
  }

  /**
   * Upload the whole library to WebDAV. The settings sheet passes its draft
   * credentials so a user can back up before saving; the payload is encrypted
   * with the same password and never contains the credential itself.
   */
  private async uploadRemoteBackup(
    url: string,
    user: string,
    password: string
  ): Promise<void> {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.webDavUrl = url;
    next.webDavUser = user;
    next.webDavPassword = password;
    const outcome: WebDavOutcome =
      await uploadEncryptedBackup(next, this.store, new Date());
    this.toast(outcome.message);
  }

  /** Download `latest`, decrypt and merge by session id (never duplicates). */
  private async restoreRemoteBackup(
    url: string,
    user: string,
    password: string
  ): Promise<void> {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.webDavUrl = url;
    next.webDavUser = user;
    next.webDavPassword = password;
    const download: WebDavDownload = await downloadLatestBackup(next);
    if (!download.ok) {
      this.toast(download.message);
      return;
    }
    const decrypted: DecryptOutcome = await decryptBackupText(download.text, password);
    if (!decrypted.ok) {
      this.toast(decrypted.message);
      return;
    }
    const parsed = parseBackupSessions(decrypted.text, new Date());
    if (!parsed.ok) {
      this.toast(parsed.error);
      return;
    }
    const merge: SyncMergeResult = mergeSessionSets(this.store, parsed.sessions);
    this.store = merge.sessions;
    this.refreshSessions();
    const current: StoredSession | null = this.findSession(this.currentId);
    if (current !== null) {
      this.messages = current.messages.slice();
    }
    this.persistSoon();
    this.toast(t('已合并远端备份：新增 ') + merge.addedFromRemote.toString() +
      t('，更新 ') + merge.updatedFromRemote.toString());
  }

  /** Merge with the remote copy, then push the merged library back. */
  private async syncRemoteBackup(
    url: string,
    user: string,
    password: string
  ): Promise<void> {
    const draft: AppSettings = cloneSettings(this.settings);
    draft.webDavUrl = url;
    draft.webDavUser = user;
    draft.webDavPassword = password;
    await this.syncBackup(draft, true);
  }

  private scheduleAutoSync(): void {
    if (!this.settings.webDavAutoSync) {
      return;
    }
    if (this.syncRunning || this.streaming) {
      return;
    }
    if (this.settings.webDavUrl.trim().length === 0 ||
      this.settings.webDavPassword.length === 0) {
      return;
    }
    if (this.syncTimer !== -1) {
      clearTimeout(this.syncTimer);
    }
    this.syncTimer = setTimeout(() => {
      this.syncTimer = -1;
      this.syncBackup(cloneSettings(this.settings), false);
    }, 15000);
  }

  /**
   * Pull-merge-push. A missing remote backup is not an error (first run).
   * Only failures visible to a user who pressed the button are toasted.
   */
  private async syncBackup(settings: AppSettings, manual: boolean): Promise<void> {
    if (this.syncRunning) {
      if (manual) {
        this.toast(t('正在同步，请稍候'));
      }
      return;
    }
    if (this.streaming) {
      if (manual) {
        this.toast(t('请先停止当前生成'));
      }
      return;
    }
    if (settings.webDavUrl.trim().length === 0 || settings.webDavPassword.length === 0) {
      if (manual) {
        this.toast(t('请先填写 WebDAV 地址与密码'));
      }
      return;
    }
    this.syncRunning = true;
    this.markSyncing(true);
    try {
      const download: WebDavDownload = await downloadLatestBackup(settings);
      let remote: StoredSession[] = [];
      if (download.ok) {
        const decrypted: DecryptOutcome =
          await decryptBackupText(download.text, settings.webDavPassword);
        if (!decrypted.ok) {
          if (manual) {
            this.toast(decrypted.message);
          }
          return;
        }
        const parsed = parseBackupSessions(decrypted.text, new Date());
        if (!parsed.ok) {
          if (manual) {
            this.toast(parsed.error);
          }
          return;
        }
        remote = parsed.sessions;
      } else if (download.message !== t('远端还没有备份')) {
        if (manual) {
          this.toast(download.message);
        }
        return;
      }
      const merge: SyncMergeResult = mergeSessionSets(this.store, remote);
      const changed: boolean =
        merge.addedFromRemote > 0 || merge.updatedFromRemote > 0;
      if (changed) {
        this.store = merge.sessions;
        this.refreshSessions();
        const current: StoredSession | null = this.findSession(this.currentId);
        if (current !== null) {
          this.messages = current.messages.slice();
        }
        await LocalStore.saveSessions(this.store);
      }
      const upload: WebDavOutcome =
        await uploadEncryptedBackup(settings, this.store, new Date(), false);
      if (!upload.ok) {
        if (manual) {
          this.toast(upload.message);
        }
        return;
      }
      settings.webDavLastSyncAt = Date.now();
      this.settings = settings;
      await LocalStore.saveSettings(settings);
      if (manual || changed) {
        this.toast(t('已同步：新增 ') + merge.addedFromRemote.toString() +
          t('，更新 ') + merge.updatedFromRemote.toString());
      }
    } catch (e) {
      if (manual) {
        this.toast(t('同步失败，请检查 WebDAV 配置'));
      }
    } finally {
      this.syncRunning = false;
      this.markSyncing(false);
    }
  }

  /** Export every session plus a secret-free settings snapshot. */
  private async exportBackup(): Promise<void> {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ExportOutcome = await saveBackup(context, this.settings, this.store);
    this.toast(outcome.message);
  }

  /** Export the sidebar selection as one JSON bundle. */
  private async exportSelectedSessions(ids: string[]): Promise<void> {
    const picked: StoredSession[] = [];
    for (let i = 0; i < ids.length; i++) {
      const session: StoredSession | null = this.findSession(ids[i]);
      if (session !== null) {
        picked.push(session);
      }
    }
    if (picked.length === 0) {
      this.toast(t('没有可导出的会话'));
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ExportOutcome = await saveSessionBundle(context, picked);
    this.toast(outcome.message);
  }

  /** Deep-copy a session into a new id, keeping its messages and tool results. */
  private forkSession(id: string): void {
    const source: StoredSession | null = this.findSession(id);
    this.actionId = '';
    if (source === null) {
      return;
    }
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const meta: SessionMeta = {
      id: util.generateRandomUUID(true),
      title: source.meta.title + t(' 副本'),
      updatedAt: Date.now(),
      modelId: source.meta.modelId,
      messageCount: source.messages.length,
      pinned: false,
      archived: false,
      modelOverride: source.meta.modelOverride,
      thinkingOverride: source.meta.thinkingOverride,
      promptOverride: source.meta.promptOverride,
      folderId: source.meta.folderId,
      mcpDisabled: source.meta.mcpDisabled !== undefined
        ? source.meta.mcpDisabled.slice() : [],
      mcpEnabled: source.meta.mcpEnabled !== undefined
        ? source.meta.mcpEnabled.slice() : []
    };
    const copied: ChatMessage[] =
      JSON.parse(JSON.stringify(source.messages)) as ChatMessage[];
    const session: StoredSession = { meta: meta, messages: copied };
    this.store = [session].concat(this.store);
    this.refreshSessions();
    this.currentId = meta.id;
    this.rememberSession(meta.id);
    this.messages = copied.slice();
    this.syncThinkingOverride();
    this.mobileChat = true;
    this.persistSoon();
    this.toast(t('已复制为新会话'));
  }

  private openSessionParams(id: string): void {
    const session: StoredSession | null = this.findSession(id);
    this.actionId = '';
    if (session === null) {
      return;
    }
    this.paramsId = id;
    this.paramModel = session.meta.modelOverride !== undefined ? session.meta.modelOverride : '';
    this.paramThinking = session.meta.thinkingOverride !== undefined ? session.meta.thinkingOverride : '';
    this.paramPrompt = session.meta.promptOverride !== undefined ? session.meta.promptOverride : '';
    this.paramMcpDisabled = normalizeMcpDisabled(
      session.meta.mcpDisabled !== undefined ? session.meta.mcpDisabled : []);
    this.paramMcpEnabled = normalizeMcpEnabled(
      session.meta.mcpEnabled !== undefined ? session.meta.mcpEnabled : []);
  }

  private saveSessionParams(): void {
    const id: string = this.paramsId;
    const session: StoredSession | null = this.findSession(id);
    this.paramsId = '';
    if (session === null) {
      return;
    }
    applySessionParams(session.meta, this.paramModel, this.paramThinking, this.paramPrompt);
    session.meta.mcpDisabled = normalizeMcpDisabled(this.paramMcpDisabled);
    session.meta.mcpEnabled = normalizeMcpEnabled(this.paramMcpEnabled);
    session.meta.updatedAt = Date.now();
    if (session.meta.mcpEnabled.length > 0) {
      McpRegistry.refresh(this.settings.mcpServers, true, true)
        .catch((error: Error) => {});
    }
    if (id === this.currentId) {
      this.syncThinkingOverride();
    }
    this.refreshSessions();
    this.persistSoon();
    this.toast(t('会话参数已保存'));
  }

  private resetSessionParams(): void {
    const id: string = this.paramsId;
    const session: StoredSession | null = this.findSession(id);
    this.paramsId = '';
    if (session === null) {
      return;
    }
    clearSessionParams(session.meta);
    session.meta.mcpDisabled = [];
    session.meta.mcpEnabled = [];
    session.meta.updatedAt = Date.now();
    if (id === this.currentId) {
      this.syncThinkingOverride();
    }
    this.refreshSessions();
    this.persistSoon();
    this.toast(t('已恢复为全局设置'));
  }

  private openMemoryPanel(): void {
    this.memoryOpen = true;
    this.memoryNotice = this.settings.memoryEnabled
      ? '' : t('持久记忆未开启；到设置 → 工具与沙箱打开后，模型才能读写记忆。');
    this.memoryLineFile = -1;
    this.memoryLineIndex = -1;
    this.memoryLineDraft = '';
    this.refreshMemoryPanel();
  }

  private refreshMemoryPanel(): void {
    this.memoryInjected = this.settings.memoryEnabled ? MemoryStore.context() : '';
    const files: MemoryFile[] = MemoryStore.editable();
    const drafts: string[] = [];
    const originals: string[] = [];
    for (let i = 0; i < files.length; i++) {
      drafts.push(files[i].text);
      originals.push(files[i].text);
    }
    this.memoryFiles = files;
    this.memoryDrafts = drafts;
    this.memoryOriginals = originals;
    this.memoryLogs = MemoryStore.logs();
  }

  private saveMemoryAt(index: number): void {
    if (index < 0 || index >= this.memoryFiles.length) {
      return;
    }
    const name: string = this.memoryFiles[index].name;
    this.memoryNotice = MemoryStore.saveText(name, this.memoryDrafts[index]);
    this.memoryInjected = this.settings.memoryEnabled ? MemoryStore.context() : '';
    this.memoryLogs = MemoryStore.logs();
  }

  /** Restore the text this file had when the panel opened, then reread it. */
  private undoMemoryAt(index: number): void {
    if (index < 0 || index >= this.memoryFiles.length) {
      return;
    }
    const name: string = this.memoryFiles[index].name;
    const original: string = this.memoryOriginals[index];
    const next: string[] = this.memoryDrafts.slice();
    next[index] = original;
    this.memoryDrafts = next;
    this.memoryNotice = MemoryStore.saveText(name, original);
    this.memoryInjected = this.settings.memoryEnabled ? MemoryStore.context() : '';
    this.memoryLogs = MemoryStore.logs();
    this.closeMemoryLine();
  }

  private memoryLinesAt(fileIndex: number): MemoryLine[] {
    if (fileIndex < 0 || fileIndex >= this.memoryDrafts.length) {
      return [];
    }
    return memoryLines(this.memoryDrafts[fileIndex]);
  }

  private toggleMemoryLines(fileIndex: number): void {
    this.memoryLineFile = this.memoryLineFile === fileIndex ? -1 : fileIndex;
    this.closeMemoryLine();
  }

  private beginMemoryLine(fileIndex: number, line: MemoryLine): void {
    this.memoryLineFile = fileIndex;
    this.memoryLineIndex = line.index;
    this.memoryLineDraft = line.text;
  }

  private closeMemoryLine(): void {
    this.memoryLineIndex = -1;
    this.memoryLineDraft = '';
  }

  /**
   * Persist one rewritten file. The in-memory draft only follows the disk when
   * `MemoryStore.saveText` reports success, so a failed write stays visible.
   */
  private commitMemoryLine(
    fileIndex: number,
    nextText: string,
    message: string
  ): void {
    if (fileIndex < 0 || fileIndex >= this.memoryFiles.length) {
      return;
    }
    const name: string = this.memoryFiles[fileIndex].name;
    const result: string = MemoryStore.saveText(name, nextText);
    this.memoryNotice = result;
    if (result !== t('已保存 ') + name) {
      return;
    }
    const next: string[] = this.memoryDrafts.slice();
    next[fileIndex] = nextText;
    this.memoryDrafts = next;
    this.memoryInjected = this.settings.memoryEnabled ? MemoryStore.context() : '';
    this.memoryLogs = MemoryStore.logs();
    this.memoryNotice = message;
    this.closeMemoryLine();
  }

  private saveMemoryLine(): void {
    const fileIndex: number = this.memoryLineFile;
    const index: number = this.memoryLineIndex;
    if (fileIndex < 0 || index < 0 || fileIndex >= this.memoryDrafts.length) {
      return;
    }
    if (this.memoryLineDraft.trim().length === 0) {
      this.memoryNotice = t('这一条不能为空。');
      return;
    }
    this.commitMemoryLine(
      fileIndex,
      replaceMemoryLine(this.memoryDrafts[fileIndex], index, this.memoryLineDraft),
      t('已保存这一条')
    );
  }

  private deleteMemoryLine(): void {
    const fileIndex: number = this.memoryLineFile;
    const index: number = this.memoryLineIndex;
    if (fileIndex < 0 || index < 0 || fileIndex >= this.memoryDrafts.length) {
      return;
    }
    this.commitMemoryLine(
      fileIndex,
      removeMemoryLine(this.memoryDrafts[fileIndex], index),
      t('已删除这一条')
    );
  }

  /** Put the line back to the text it had when the panel opened. */
  private restoreMemoryLine(): void {
    const fileIndex: number = this.memoryLineFile;
    const index: number = this.memoryLineIndex;
    if (fileIndex < 0 || index < 0 || fileIndex >= this.memoryDrafts.length ||
      fileIndex >= this.memoryOriginals.length) {
      return;
    }
    const original: string = memoryLineAt(this.memoryOriginals[fileIndex], index);
    if (original.length === 0) {
      this.memoryNotice = t('原始文件里没有这一条。');
      return;
    }
    this.commitMemoryLine(
      fileIndex,
      replaceMemoryLine(this.memoryDrafts[fileIndex], index, original),
      t('已恢复这一条')
    );
  }

  private attachmentBytes(uri: string): number {
    if (!AttachmentStore.isAttachmentUri(uri)) {
      return 0;
    }
    try {
      return fs.statSync(AttachmentStore.absolutePath(uri)).size;
    } catch (e) {
      return 0;
    }
  }

  /** Per-session workspace ledger plus attachment references in messages. */
  private sessionStorageRows(): SessionStorageTotal[] {
    const attachments: SessionAttachmentUsage[] = [];
    for (let i = 0; i < this.store.length; i++) {
      const session: StoredSession = this.store[i];
      for (let m = 0; m < session.messages.length; m++) {
        const parts: MessagePart[] = session.messages[m].parts;
        for (let p = 0; p < parts.length; p++) {
          const part: MessagePart = parts[p];
          if ((part.kind === PART_FILE || part.kind === PART_IMAGE) &&
            AttachmentStore.isAttachmentUri(part.uri)) {
            attachments.push({
              sessionId: session.meta.id,
              uri: part.uri,
              bytes: this.attachmentBytes(part.uri)
            });
          }
        }
      }
    }
    return WorkspaceLedger.totals(attachments);
  }

  private sessionTitleById(sessionId: string): string {
    const session: StoredSession | null = this.findSession(sessionId);
    if (session === null || session.meta.title.length === 0) {
      return t('新对话');
    }
    return session.meta.title;
  }

  private clearSessionStorage(sessionId: string): void {
    const result: LedgerClearResult = WorkspaceLedger.clearSession(sessionId);
    this.toast(result.files > 0
      ? t('已删除 ') + result.files.toString() + t(' 个工作区文件')
      : t('该会话没有可清理的工作区文件。'));
  }

  private memoryClock(at: number): string {
    const date: Date = new Date(at);
    const hour: number = date.getHours();
    const minute: number = date.getMinutes();
    return (hour < 10 ? '0' : '') + hour.toString() + ':' +
      (minute < 10 ? '0' : '') + minute.toString();
  }

  private performDelete(): void {
    const id: string = this.deleteId;
    this.deleteId = '';
    if (this.streaming && this.currentId === id) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    this.store = this.store.filter((session: StoredSession): boolean => session.meta.id !== id);
    this.refreshSessions();
    if (this.currentId === id) {
      const metas: SessionMeta[] = this.buildMetaList();
      if (metas.length > 0) {
        this.currentId = metas[0].id;
        const next: StoredSession | null = this.findSession(metas[0].id);
        this.messages = next === null ? [] : next.messages.slice();
        this.syncThinkingOverride();
      } else {
        this.createChat(false);
      }
    }
    this.persistSoon();
  }

  /** Pick up to four photos and copy them into the app sandbox. */
  private async pickImages(): Promise<void> {
    try {
      const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 4;
      const photoPicker: picker.PhotoViewPicker = new picker.PhotoViewPicker();
      const result: picker.PhotoSelectResult = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      const next: ChatAttachment[] = this.pendingAttachments.slice();
      let failed: number = 0;
      for (let i = 0; i < result.photoUris.length; i++) {
        const info = await AttachmentStore.saveFromUri(result.photoUris[i]);
        if (info === null) {
          failed++;
          continue;
        }
        next.push({
          uri: AttachmentStore.uriFor(info.name),
          mimeType: info.mimeType,
          path: AttachmentStore.absolutePath(info.name)
        });
      }
      this.pendingAttachments = next;
      if (failed > 0) {
        this.toast(failed.toString() + t(' 张图片无法读取（格式或大小不支持）'));
      }
      const session: StoredSession | null = this.findSession(this.currentId);
      const modelId: string = session !== null
        ? effectiveSettings(this.settings, session.meta).modelId
        : this.settings.modelId;
      if (!capsForModel(modelId).vision) {
        this.toast(t('当前模型未标记视觉能力，图片可能被拒绝'));
      }
    } catch (e) {
      this.toast(t('选择图片失败'));
    }
  }

  /** Launch the system camera picker and attach the captured photo. */
  private async takePhoto(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context, [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode !== 0 || result.resultUri.length === 0) {
        return;
      }
      const info = await AttachmentStore.saveFromUri(result.resultUri);
      if (info === null) {
        this.toast(t('照片无法读取（格式或大小不支持）'));
        return;
      }
      const next: ChatAttachment[] = this.pendingAttachments.slice();
      next.push({
        uri: AttachmentStore.uriFor(info.name),
        mimeType: info.mimeType,
        path: AttachmentStore.absolutePath(info.name)
      });
      this.pendingAttachments = next;
      const session: StoredSession | null = this.findSession(this.currentId);
      const modelId: string = session !== null
        ? effectiveSettings(this.settings, session.meta).modelId
        : this.settings.modelId;
      if (!capsForModel(modelId).vision) {
        this.toast(t('当前模型未标记视觉能力，图片可能被拒绝'));
      }
    } catch (e) {
      this.toast(t('拍照失败'));
    }
  }

  /**
   * A >15k paste is written to `<workspace>/pasted/` and attached instead of
   * staying in the composer. The file is a normal workspace document, so the
   * model can read it with `read_file`; only a short marker travels in chat.
   * Returns false when the write failed, letting the composer keep the text.
   */
  private attachHugePaste(text: string): boolean {
    // Without local file tools the model could not read the attachment, and a
    // remote sandbox cannot see this workspace; keep the text in the composer.
    if (this.workspaceRoot.length === 0 || !this.settings.toolsEnabled ||
      this.settings.sandboxMode === 'remote') {
      return false;
    }
    const dir: string = this.workspaceRoot + '/' + PASTED_DIR;
    const name: string = pasteFileName(new Date());
    const absolute: string = dir + '/' + name;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const file = fs.openSync(absolute,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      this.toast(t('长文本保存失败，已保留在输入框'));
      return false;
    }
    const next: ChatAttachment[] = this.pendingAttachments.slice();
    next.push({
      uri: resourceUrl(MINIS_WORKSPACE, pastedRelativePath(name)),
      mimeType: 'text/plain',
      path: absolute
    });
    this.pendingAttachments = next;
    this.toast(t('长文本已保存为工作区附件'));
    return true;
  }

  /** Copy picked media into the sandbox and append it to the composer. */
  private async attachPicked(uris: string[], failedLabel: string): Promise<void> {
    const next: ChatAttachment[] = this.pendingAttachments.slice();
    let failed: number = 0;
    for (let i = 0; i < uris.length; i++) {
      const info = await AttachmentStore.saveFromUri(uris[i]);
      if (info === null) {
        failed++;
        continue;
      }
      next.push({
        uri: AttachmentStore.uriFor(info.name),
        mimeType: info.mimeType,
        path: AttachmentStore.absolutePath(info.name)
      });
    }
    this.pendingAttachments = next;
    if (failed > 0) {
      this.toast(failed.toString() + failedLabel);
    }
  }

  /** Pick up to four videos from the gallery. */
  private async pickVideos(): Promise<void> {
    try {
      const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = 4;
      const photoPicker: picker.PhotoViewPicker = new picker.PhotoViewPicker();
      const result: picker.PhotoSelectResult = await photoPicker.select(options);
      await this.attachPicked(result.photoUris,
        t(' 个视频无法读取（格式或大小不支持）'));
    } catch (e) {
      this.toast(t('选择视频失败'));
    }
  }

  /** Pick up to four audio clips from the system audio picker. */
  private async pickAudio(): Promise<void> {
    try {
      const options: picker.AudioSelectOptions = new picker.AudioSelectOptions();
      options.maxSelectNumber = 4;
      const audioPicker: picker.AudioViewPicker = new picker.AudioViewPicker();
      const uris: string[] = await audioPicker.select(options);
      await this.attachPicked(uris,
        t(' 个音频无法读取（格式或大小不支持）'));
    } catch (e) {
      this.toast(t('选择音频失败'));
    }
  }

  private removeAttachment(index: number): void {
    const next: ChatAttachment[] = [];
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      if (i !== index) {
        next.push(this.pendingAttachments[i]);
      }
    }
    this.pendingAttachments = next;
  }

  private async sendMessage(): Promise<void> {
    const text: string = this.draft.trim();
    const attachments: ChatAttachment[] = this.pendingAttachments.slice();
    if (text.length === 0 && attachments.length === 0) {
      return;
    }
    if (this.compacting) {
      this.toast(t('正在压缩上下文，请稍候'));
      return;
    }
    if (text.length > 0 && text.startsWith('/')) {
      if (this.streaming) {
        this.toast(t('请先停止当前生成'));
        return;
      }
      this.handleCommand(text);
      return;
    }
    const claudeLogin: boolean =
      this.settings.preset === 'anthropic' && OAuthService.hasClaudeToken();
    const copilotLogin: boolean =
      this.settings.preset === 'copilot' && OAuthService.hasCopilotToken();
    const codexLogin: boolean =
      this.settings.preset === 'codex' && OAuthService.hasCodexToken();
    if (this.settings.apiKey.trim().length === 0 && !claudeLogin &&
      !copilotLogin && !codexLogin) {
      this.pendingSkillBody = '';
      this.showSettings = true;
      this.toast(t('请先填写 API Key 或登录账号'));
      return;
    }
    if (this.settings.baseUrl.trim().length === 0) {
      this.pendingSkillBody = '';
      this.showSettings = true;
      this.toast(t('请先填写 API 地址'));
      return;
    }
    if (this.settings.toolsEnabled && this.settings.sandboxMode === 'remote' &&
      this.settings.sandboxUrl.trim().length === 0) {
      this.pendingSkillBody = '';
      this.showSettings = true;
      this.toast(t('请先填写远程沙箱地址'));
      return;
    }

    // A prompt sent mid-generation is queued instead of rejected: the runtime
    // injects it before the next model request, or the UI resends it once the
    // current run settles.
    if (this.streaming) {
      this.queuePrompt(text, attachments);
      return;
    }

    // Summarise old turns before the next request when the last reported
    // usage is already near the window. A failure keeps the history as-is.
    await this.autoCompactBeforeSend();
    // A new user turn makes the pre-compaction snapshot stale.
    this.compactUndo = null;
    this.canUndoCompact = false;

    this.attributeTaskSend(text);

    let session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      this.createChat(false);
      session = this.findSession(this.currentId);
    }
    if (session === null) {
      return;
    }

    if (session.messages.length === 0) {
      session.meta.title = text.length > 0 ? titleFrom(text) : t('图片对话');
    }
    session.meta.updatedAt = Date.now();
    session.meta.modelId = effectiveSettings(this.settings, session.meta).modelId;

    this.draft = '';
    this.pendingAttachments = [];
    this.runAgent(session, text, true, attachments);
  }

  /** Queue a mid-generation prompt and hand it to the running agent. */
  private queuePrompt(text: string, attachments: ChatAttachment[]): void {
    const item: QueuedPrompt = new QueuedPrompt(text, attachments, this.currentId);
    this.queuedPrompts = enqueueQueued(this.queuedPrompts, item);
    this.draft = '';
    this.pendingAttachments = [];
    if (this.agent !== null &&
      this.agent.injectUserMessage(text, queuedParts(item))) {
      // The runtime reports back how many entries it inserted; then the
      // matching FIFO heads are dropped.
      return;
    }
    // The run settled between the click and here; send it as a fresh turn.
    setTimeout(() => this.flushQueuedPrompts(), 0);
  }

  private clearQueuedPrompts(): void {
    this.queuedPrompts = [];
    // Also discard the runtime copies, otherwise prompts the user just cleared
    // would still appear in the transcript at the next request boundary.
    if (this.agent !== null) {
      this.agent.clearUserQueued();
    }
  }

  /**
   * Send the oldest queued prompt as a normal turn. Entries the runtime
   * already injected were removed by the `onInputsDrained` callback, so this
   * only handles leftovers from stopped/cancelled runs.
   */
  private flushQueuedPrompts(): void {
    if (this.streaming || this.compacting || this.agent !== null ||
      this.queuedPrompts.length === 0 || !this.ready) {
      return;
    }
    const item: QueuedPrompt = this.queuedPrompts[0];
    if (item.sessionId !== this.currentId) {
      // Switching sessions while a run is stopping must not leak the prompt
      // into another conversation.
      this.queuedPrompts = dropQueued(this.queuedPrompts, 1);
      this.toast(t('已取消'));
      setTimeout(() => this.flushQueuedPrompts(), 0);
      return;
    }
    this.queuedPrompts = dropQueued(this.queuedPrompts, 1);
    this.sendQueuedPrompt(item);
  }

  private sendQueuedPrompt(item: QueuedPrompt): void {
    const text: string = item.text.trim();
    const attachments: ChatAttachment[] = item.attachments.slice();
    const claudeLogin: boolean =
      this.settings.preset === 'anthropic' && OAuthService.hasClaudeToken();
    const copilotLogin: boolean =
      this.settings.preset === 'copilot' && OAuthService.hasCopilotToken();
    const codexLogin: boolean =
      this.settings.preset === 'codex' && OAuthService.hasCodexToken();
    if (this.settings.apiKey.trim().length === 0 && !claudeLogin &&
      !copilotLogin && !codexLogin) {
      this.showSettings = true;
      this.toast(t('请先填写 API Key 或登录账号'));
      return;
    }
    if (this.settings.baseUrl.trim().length === 0) {
      this.showSettings = true;
      this.toast(t('请先填写 API 地址'));
      return;
    }
    this.autoCompactBeforeSend().then(() => {
      if (item.sessionId !== this.currentId) {
        this.toast(t('已取消'));
        return;
      }
      let session: StoredSession | null = this.findSession(this.currentId);
      if (session === null) {
        this.createChat(false);
        session = this.findSession(this.currentId);
      }
      if (session === null) {
        return;
      }
      if (session.messages.length === 0) {
        session.meta.title = text.length > 0 ? titleFrom(text) : t('图片对话');
      }
      session.meta.updatedAt = Date.now();
      session.meta.modelId = effectiveSettings(this.settings, session.meta).modelId;
      this.attributeTaskSend(text);
      this.runAgent(session, text, true, attachments);
    }).catch(() => {
      // auto compaction failure is already non-fatal elsewhere; still send.
      const session: StoredSession | null = this.findSession(this.currentId);
      if (session !== null && !this.streaming && item.sessionId === this.currentId) {
        this.runAgent(session, text, true, attachments);
      }
    });
  }

  private async runAgent(
    session: StoredSession,
    userText: string,
    fresh: boolean,
    attachments: ChatAttachment[] = []
  ): Promise<void> {
    let effective: AppSettings = effectiveSettings(this.settings, session.meta);
    // Resolve/refresh the OAuth token before the first request; API-key users
    // get the settings back unchanged.
    effective = await OAuthService.decorate(effective);
    const skills: string = SkillStore.block(effective.enabledSkills);
    if (skills.length > 0) {
      effective.systemPrompt = effective.systemPrompt.trim().length > 0
        ? effective.systemPrompt + '\n\n' + skills
        : skills;
    }
    if (this.pendingSkillBody.length > 0) {
      effective.systemPrompt = effective.systemPrompt.trim().length > 0
        ? effective.systemPrompt + '\n\n' + this.pendingSkillBody
        : this.pendingSkillBody;
      this.pendingSkillBody = '';
    }
    const runtime: ToolRuntime = this.makeToolRuntime(effective, session.meta.id);
    // A new turn supersedes an earlier stop or an unread background result.
    if (session.meta.statusBadge === 'interrupted' || session.meta.statusBadge === 'background') {
      session.meta.statusBadge = '';
    }
    this.streaming = true;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    keepScreenOn(context, true).catch((error: Error) => {});
    if (effective.backgroundEnabled) {
      BackgroundGuard.begin(context).catch((error: Error) => {});
    }
    this.agent = new AgentRuntime(effective, runtime, session, {
      onUpdate: (messages: ChatMessage[], running: boolean) => {
        this.messages = messages;
        this.streaming = running;
        // Re-sorting on every flush is cheap; rebuilding the full-text blob
        // is not, so only refresh the index once the turn settles.
        this.sessions = this.buildMetaList();
        this.persistSoon();
        if (!running) {
          this.agent = null;
          this.searchEntries = this.buildSearchIndex();
          this.finishTaskRun(session);
          this.maybeAutoTitle(session);
          this.recordUsage(session);
          this.scheduleAutoSync();
          BackgroundGuard.end().catch((error: Error) => {});
          keepScreenOn(getContext(this) as common.UIAbilityContext, false)
            .catch((error: Error) => {});
          if (!this.pageVisible) {
            const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
            publishDone(context, this.currentTitle());
          }
          // Leftovers from a stopped run become the next turn.
          setTimeout(() => this.flushQueuedPrompts(), 0);
        }
      },
      onError: (message: string) => {
        this.toast(message);
      },
      onInputsDrained: (count: number) => {
        this.queuedPrompts = dropQueued(this.queuedPrompts, count);
      }
    }, effective.confirmWriteTools
      ? (name: string, argumentsText: string) =>
        this.askToolPermission(name, argumentsText)
      : null);
    if (fresh) {
      const parts: MessagePart[] = [];
      for (let i = 0; i < attachments.length; i++) {
        const uri: string = attachments[i].uri;
        const mime: string = attachments[i].mimeType;
        if (isPastedAttachment(uri, mime)) {
          parts.push(textPart(pastePlaceholder(pasteRelativePath(uri))));
          parts.push(filePart(uri, mime));
        } else if (mime.startsWith('video/') || mime.startsWith('audio/')) {
          const label: string = mime.startsWith('video/') ? t('视频') : t('音频');
          parts.push(textPart('[' + label + '] ' +
            AttachmentStore.nameFromUri(uri)));
          parts.push(filePart(uri, mime));
        } else {
          parts.push(imagePart(uri, mime));
        }
      }
      this.agent.start(userText, parts);
    } else {
      this.agent.regenerate();
    }
    this.messages = session.messages.slice();
    this.refreshSessions();
    this.persistSoon();
  }

  /** Re-run the last user turn after dropping the assistant answer. */
  private regenerateLast(): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    while (session.messages.length > 0 &&
      session.messages[session.messages.length - 1].role === 'assistant') {
      session.messages.pop();
    }
    if (session.messages.length === 0 ||
      session.messages[session.messages.length - 1].role !== 'user') {
      this.toast(t('没有可重新生成的回复'));
      return;
    }
    this.runAgent(session, '', false);
  }

  /** Open the composer overlay with the message text for editing. */
  private beginEdit(id: string): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    for (let i = 0; i < session.messages.length; i++) {
      const message: ChatMessage = session.messages[i];
      if (message.id === id && message.role === 'user') {
        this.editId = id;
        this.editText = textOf(message);
        this.editing = true;
        return;
      }
    }
  }

  /**
   * Replace the edited user message and discard everything after it, then
   * continue from that point — the same semantics as OpenMinis edit-and-resend.
   */
  private confirmEdit(): void {
    const text: string = this.editText.trim();
    if (text.length === 0) {
      this.toast(t('消息不能为空'));
      return;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      this.editing = false;
      return;
    }
    let index: number = -1;
    for (let i = 0; i < session.messages.length; i++) {
      if (session.messages[i].id === this.editId &&
        session.messages[i].role === 'user') {
        index = i;
        break;
      }
    }
    if (index < 0) {
      this.editing = false;
      return;
    }
    session.messages = session.messages.slice(0, index + 1);
    const message: ChatMessage = session.messages[index];
    const parts: MessagePart[] = [textPart(text)];
    for (let i = 0; i < message.parts.length; i++) {
      if (message.parts[i].kind !== PART_TEXT) {
        parts.push(message.parts[i]);
      }
    }
    message.parts = parts;
    message.createdAt = Date.now();
    if (index === 0) {
      session.meta.title = titleFrom(text);
      this.forgetTitle(session.meta.id);
    }
    this.editing = false;
    this.editId = '';
    this.editText = '';
    this.runAgent(session, '', false);
  }

  /**
   * Replace old turns with a model-written summary. The recent turns are kept
   * verbatim, so tool results from the current task stay available.
   *
   * The transcript is only mutated after a successful summary, so a failed or
   * timed-out request leaves the conversation untouched. `auto` silences the
   * "too short" case and labels the notice as automatic.
   */
  private async compactSession(auto: boolean = false): Promise<boolean> {
    if (this.streaming) {
      if (!auto) {
        this.toast(t('请先停止当前生成'));
      }
      return false;
    }
    if (this.compacting) {
      if (!auto) {
        this.toast(t('正在压缩上下文'));
      }
      return false;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return false;
    }
    const plan: CompactPlan | null =
      planCompact(session.messages, COMPACT_DEFAULT_KEEP_TURNS);
    if (plan === null) {
      if (!auto) {
        this.toast(t('对话还太短，或最近几轮已覆盖全部内容'));
      }
      return false;
    }
    const original: ChatMessage[] = session.messages.slice();
    const originalCount: number = session.meta.messageCount;
    const transcript: string =
      transcriptForSummary(plan.head, SUMMARY_TRANSCRIPT_LIMIT);
    this.compacting = true;
    this.toast(auto ? t('上下文接近上限，正在自动压缩…') : t('正在生成摘要…'));
    const summarySettings: AppSettings =
      await OAuthService.decorate(effectiveSettings(this.settings, session.meta));
    const result: SummaryResult = await summarizeConversation(
      summarySettings, session.meta.id, transcript
    );
    this.compacting = false;
    if (!result.ok) {
      // Keep the original history; tell the user instead of silently failing.
      this.toast(t('压缩失败，原对话已保留：') + result.message);
      return false;
    }
    const summary: ChatMessage =
      makeSummaryMessage(util.generateRandomUUID(true), result.text);
    this.compactUndo = {
      sessionId: session.meta.id,
      messages: original,
      messageCount: originalCount
    };
    this.canUndoCompact = true;
    session.messages = [summary].concat(plan.tail);
    session.meta.messageCount = session.messages.length;
    session.meta.updatedAt = Date.now();
    this.messages = session.messages.slice();
    this.autoCompactMarker = this.currentId + ':' +
      session.messages[session.messages.length - 1].id;
    this.compactNotice = (auto ? t('上下文接近上限，已自动把较早的 ') :
      t('已把较早的 ')) + plan.head.length.toString() +
      t(' 条消息压缩为摘要。');
    this.refreshSessions();
    this.persistNow();
    this.toast(auto ? t('已自动压缩较早的对话') :
      t('已压缩 ') + plan.head.length.toString() + t(' 条早期消息'));
    return true;
  }

  private dismissCompactNotice(): void {
    this.compactUndo = null;
    this.compactNotice = '';
    this.canUndoCompact = false;
  }

  /** Restore the transcript captured just before the last compaction. */
  private undoCompact(): void {
    const undo: CompactUndo | null = this.compactUndo;
    this.compactUndo = null;
    this.compactNotice = '';
    this.canUndoCompact = false;
    if (undo === null || undo.sessionId !== this.currentId) {
      return;
    }
    const session: StoredSession | null = this.findSession(undo.sessionId);
    if (session === null) {
      return;
    }
    session.messages = undo.messages;
    session.meta.messageCount = undo.messageCount > 0
      ? undo.messageCount
      : undo.messages.length;
    session.meta.updatedAt = Date.now();
    this.messages = session.messages.slice();
    this.autoCompactMarker = '';
    this.refreshSessions();
    this.persistNow();
    this.toast(t('已恢复压缩前的对话'));
  }

  /** Latest reported prompt+completion, the best local estimate we have. */
  private contextUsageTokens(): number {
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return 0;
    }
    for (let i = session.messages.length - 1; i >= 0; i--) {
      const message: ChatMessage = session.messages[i];
      if (message.role === 'assistant' && message.totalTokens > 0) {
        return message.promptTokens + message.completionTokens;
      }
    }
    return 0;
  }

  private shouldAutoCompact(): boolean {
    if (!this.settings.autoCompact || this.streaming || this.compacting) {
      return false;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null || session.messages.length === 0) {
      return false;
    }
    if (planCompact(session.messages, COMPACT_DEFAULT_KEEP_TURNS) === null) {
      return false;
    }
    const last: ChatMessage = session.messages[session.messages.length - 1];
    // One compaction per settled turn: the transcript still reports the old
    // usage until the model answers again, so without this guard every send
    // would summarise the same conversation again.
    if (this.autoCompactMarker === this.currentId + ':' + last.id) {
      return false;
    }
    const used: number = this.contextUsageTokens();
    if (used <= 0) {
      return false;
    }
    const window: number = capsForModel(this.effectiveModelId()).contextWindow;
    return used * 100 >= window * this.settings.autoCompactPercent;
  }

  private async autoCompactBeforeSend(): Promise<void> {
    if (!this.shouldAutoCompact()) {
      return;
    }
    await this.compactSession(true);
  }

  /**
   * Local slash commands. They never reach the model, which mirrors the way
   * OpenMinis handles /clear and friends.
   */
  private handleCommand(raw: string): void {
    const command: string = raw.trim().toLowerCase();
    this.draft = '';
    if (command === '/new') {
      this.createChat();
      return;
    }
    if (command === '/compact') {
      this.compactSession();
      return;
    }
    if (command === '/help') {
      let help: string =
        t('可用命令：\n') +
          t('/new — 新建对话\n') +
          t('/clear — 清空当前对话\n') +
          t('/compact — 用模型摘要较早的对话，保留最近几轮\n') +
          t('/memory — 开启/关闭持久记忆与记忆工具\n') +
          t('/thinking — 循环切换思考档位（off → low → medium → high）\n') +
          t('/help — 显示本帮助\n');
      const docs: SkillDoc[] = SkillStore.list();
      let skillLines: string = '';
      for (let i = 0; i < docs.length; i++) {
        if (this.settings.enabledSkills.indexOf(docs[i].id) >= 0) {
          skillLines += '\n/' + docs[i].id + t(' — 使用技能：') + docs[i].name;
        }
      }
      if (skillLines.length > 0) {
        help += t('\n已启用的技能命令：') + skillLines;
      }
      help += t('\n\n长对话接近上下文预算时，发送前会自动裁剪较早的工具结果。');
      this.appendLocalNotice(help);
      return;
    }
    if (command === '/clear') {
      const session: StoredSession | null = this.findSession(this.currentId);
      if (session === null) {
        return;
      }
      session.messages = [];
      session.meta.title = t('新对话');
      session.meta.messageCount = 0;
      session.meta.updatedAt = Date.now();
      this.messages = [];
      this.refreshSessions();
      this.persistSoon();
      this.toast(t('当前对话已清空'));
      return;
    }
    if (command === '/memory') {
      this.settings.memoryEnabled = !this.settings.memoryEnabled;
      const on: boolean = this.settings.memoryEnabled;
      LocalStore.saveSettings(this.settings).catch((error: Error) => {
        this.toast(t('设置保存失败'));
      });
      this.toast(on ? t('持久记忆已开启') : t('持久记忆已关闭'));
      this.appendLocalNotice(on
        ? t('持久记忆已开启：模型可以读写本机记忆，并会在后续对话中看到它。')
        : t('持久记忆已关闭：不再注入记忆，记忆工具也会从工具列表移除。'));
      return;
    }
    if (command === '/thinking') {
      const next: ThinkingLevel = cycleThinkingLevel(this.effectiveThinking());
      this.setThinkingLevel(next);
      this.appendLocalNotice(next === 'off'
        ? t('已关闭本会话的思考：请求不再携带 reasoning_effort。部分模型仍可能返回推理内容。')
        : t('已设置本会话思考强度：reasoning_effort=') + next +
          t('。再次输入 /thinking 会切换到下一档；新会话仍使用全局设置。'));
      return;
    }
    const skill: SkillCommand | null = matchSkillCommand(raw, this.settings.enabledSkills);
    if (skill !== null) {
      const doc: SkillDoc | null = SkillStore.get(skill.id);
      if (doc === null || doc.body.trim().length === 0) {
        this.toast(t('技能内容为空：') + skill.id);
        return;
      }
      this.pendingSkillBody = t('# 技能：') + doc.name + '\n\n' + doc.body;
      this.draft = skill.rest.length > 0
        ? skill.rest
        : t('请按照技能「') + doc.name + t('」的说明处理当前任务。');
      this.sendMessage();
      return;
    }
    this.toast(t('未知命令，输入 /help 查看'));
  }

  private appendLocalNotice(text: string): void {
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    const notice: ChatMessage = newChatMessage(
      util.generateRandomUUID(true), 'system', text
    );
    session.messages.push(notice);
    session.meta.updatedAt = Date.now();
    session.meta.messageCount = session.messages.length;
    this.messages = session.messages.slice();
    this.refreshSessions();
    this.persistSoon();
  }

  /** Any session turns a globally disabled MCP server back on. */
  private hasMcpForceEnabled(): boolean {
    for (let i = 0; i < this.store.length; i++) {
      const ids: string[] | undefined = this.store[i].meta.mcpEnabled;
      if (ids !== undefined && ids.length > 0) {
        return true;
      }
    }
    return false;
  }

  private makeToolRuntime(settings: AppSettings, sessionId: string): ToolRuntime {
    let base: ToolRuntime;
    if (settings.sandboxMode === 'remote') {
      base = new RemoteToolRuntime(
        settings.sandboxUrl,
        settings.sandboxToken,
        settings.allowWriteTools,
        settings.disabledTools
      );
    } else {
      // One handler per runtime: it owns nothing but the context and paths,
      // and SandboxIsh itself is a process-wide singleton daemon.
      const shell: ShellTool = new ShellTool(
        getContext(this) as common.UIAbilityContext);
      SubagentRunner.setShell(shell);
      base = new LocalToolRuntime(
        this.workspaceRoot,
        settings.allowWriteTools,
        settings.memoryEnabled,
        settings.imageToolsEnabled,
        new SubagentRunner(
          settings,
          this.workspaceRoot,
          settings.allowWriteTools,
          sessionId,
          0,
          (session: StoredSession) => this.adoptSubagentSession(session),
          (parentSessionId: string, text: string) =>
            this.deliverSubagentResult(parentSessionId, text),
          shell
        ),
        settings.disabledTools,
        settings.clipboardToolsEnabled,
        this.browserTool,
        settings.imageGenEnabled ? new SettingsImageGen(settings) : null,
        new DeviceTools(getContext(this) as common.UIAbilityContext, settings),
        shell,
        new SessionWriteRecorder(sessionId)
      );
    }
    const meta: StoredSession | null = this.findSession(sessionId);
    const disabledServers: string[] = meta !== null && meta.meta.mcpDisabled !== undefined
      ? normalizeMcpDisabled(meta.meta.mcpDisabled) : [];
    const enabledServers: string[] = meta !== null && meta.meta.mcpEnabled !== undefined
      ? normalizeMcpEnabled(meta.meta.mcpEnabled) : [];
    return new McpRuntime(base, settings.disabledTools, disabledServers, enabledServers);
  }

  /**
   * A background subagent finished. If its conversation is streaming, queue
   * the text for that run's next request boundary; otherwise add it as a user
   * message and let the model answer it, exactly like the user had typed it.
   */
  private deliverSubagentResult(parentSessionId: string, text: string): void {
    const session: StoredSession | null = this.findSession(parentSessionId);
    if (session === null) {
      return;
    }
    const progress: boolean = text.startsWith(PROGRESS_PREFIX);
    if (parentSessionId === this.currentId && this.streaming && this.agent !== null) {
      // An unread progress report is replaced by the newer one.
      this.agent.injectInput(text, progress ? PROGRESS_PREFIX : '');
      return;
    }
    if (progress && session.messages.length > 0) {
      const last: ChatMessage = session.messages[session.messages.length - 1];
      if (last.role === 'user' && textOf(last).startsWith(PROGRESS_PREFIX)) {
        // The parent never answered the previous report: supersede it.
        last.parts = [textPart(text)];
        session.meta.updatedAt = Date.now();
        this.persistSoon();
        if (parentSessionId === this.currentId) {
          this.messages = session.messages.slice();
          if (!this.streaming) {
            this.runAgent(session, '', false);
          }
        }
        return;
      }
    }
    const notice: ChatMessage = newChatMessage(
      util.generateRandomUUID(true), 'user', text);
    session.messages.push(notice);
    session.meta.updatedAt = Date.now();
    session.meta.messageCount = session.messages.length;
    this.refreshSessions();
    this.persistSoon();
    if (parentSessionId === this.currentId) {
      this.messages = session.messages.slice();
      if (!this.streaming) {
        this.runAgent(session, '', false);
      }
    }
  }

  /** The last message is a background result the model has not answered yet. */
  private hasPendingBackgroundResult(session: StoredSession): boolean {
    if (session.messages.length === 0) {
      return false;
    }
    const last: ChatMessage = session.messages[session.messages.length - 1];
    return last.role === 'user' && textOf(last).startsWith(BACKGROUND_PREFIX);
  }

  private stopStream(): void {
    // Unblock a tool waiting for confirmation, otherwise the loop would keep
    // a pending promise after the generation was stopped.
    this.settleToolPermission(false);
    // A shell command cannot be interrupted inside the guest; stopping the
    // daemon is what lets the queue move on instead of waiting out its
    // timeout. Queued commands are unaffected and boot a fresh shell.
    SandboxIsh.cancel();
    // Children the turn is synchronously waiting on would otherwise keep
    // running with nobody to receive their result; background jobs survive.
    SubagentRunner.cancelBlocking(this.currentId);
    this.abandonTaskRun();
    if (this.agent !== null) {
      this.agent.cancel();
      this.agent = null;
    }
    this.streaming = false;
    // The partial turn stays in the transcript; the sidebar flags it so the
    // user knows this conversation ended early.
    this.setSessionBadge(this.currentId, 'interrupted', true);
    BackgroundGuard.end().catch((error: Error) => {});
    keepScreenOn(getContext(this) as common.UIAbilityContext, false)
      .catch((error: Error) => {});
    if (!this.pageVisible) {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      publishDone(context, this.currentTitle());
    }
    this.persistSoon();
  }

  private askToolPermission(name: string, argumentsText: string): Promise<boolean> {
    this.confirmName = name;
    this.confirmArgs = argumentsText.length > 1500
      ? argumentsText.substring(0, 1500) + t('\n…（已截断）')
      : argumentsText;
    this.confirmVisible = true;
    return new Promise<boolean>((resolve: (allowed: boolean) => void) => {
      this.confirmResolve = resolve;
    });
  }

  private settleToolPermission(allowed: boolean): void {
    const resolve: ((allowed: boolean) => void) | null = this.confirmResolve;
    this.confirmResolve = null;
    this.confirmVisible = false;
    if (resolve !== null) {
      resolve(allowed);
    }
  }

  /** Publish appearance values so nested components update without prop drilling. */
  private applyAppearance(settings: AppSettings): void {
    AppStorage.setOrCreate<string>('accentColor', settings.accentColor);
    AppStorage.setOrCreate<number>('fontScale', settings.fontScale);
    AppStorage.setOrCreate<number>('messageFontScale', settings.messageFontScale);
    AppStorage.setOrCreate<number>('inputFontScale', settings.inputFontScale);
    AppStorage.setOrCreate<boolean>('autoExpandThinking', settings.autoExpandThinking);
    AppStorage.setOrCreate<boolean>('autoFocusInput', settings.autoFocusInput);
  }

  /** Record which settings keys changed, without touching secret values. */
  private recordConfigChanges(prev: AppSettings, next: AppSettings): void {
    const added: ConfigAuditEntry[] = diffConfig(
      configSnapshot(prev), configSnapshot(next), Date.now(), 'user');
    if (added.length === 0) {
      return;
    }
    this.configAudit = mergeConfigAudit(this.configAudit, added, CONFIG_AUDIT_LIMIT);
    try {
      const context: common.UIAbilityContext =
        getContext(this) as common.UIAbilityContext;
      ConfigAuditStore.save(context, this.configAudit);
    } catch (e) {
    }
  }

  private auditStringList(parsed: Object): string[] | null {
    if (!Array.isArray(parsed)) {
      return null;
    }
    const list: Object[] = parsed as Object[];
    const result: string[] = [];
    for (let i = 0; i < list.length; i++) {
      if (typeof list[i] !== 'string') {
        return null;
      }
      result.push(list[i] as string);
    }
    return result;
  }

  /** Write one audited value back into a settings copy. */
  private applyAuditedValue(next: AppSettings, key: string,
    encoded: string): boolean {
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(encoded) as Object;
    } catch (e) {
      return false;
    }
    if (parsed === null) {
      return false;
    }
    const list: string[] | null = this.auditStringList(parsed);
    if (key === 'fallbackModels') {
      if (list === null) {
        return false;
      }
      next.fallbackModels = list;
      return true;
    }
    if (key === 'disabledTools') {
      if (list === null) {
        return false;
      }
      next.disabledTools = list;
      return true;
    }
    if (key === 'enabledSkills') {
      if (list === null) {
        return false;
      }
      next.enabledSkills = list;
      return true;
    }
    if (key === 'temperature' || key === 'maxTokens' ||
      key === 'maxAgentTurns' || key === 'contextBudgetChars' ||
      key === 'autoCompactPercent' || key === 'fontScale' ||
      key === 'messageFontScale' || key === 'inputFontScale') {
      if (typeof parsed !== 'number') {
        return false;
      }
      const value: number = parsed as number;
      if (!Number.isFinite(value)) {
        return false;
      }
      if (key === 'temperature') {
        next.temperature = value;
      } else if (key === 'maxTokens') {
        next.maxTokens = value;
      } else if (key === 'maxAgentTurns') {
        next.maxAgentTurns = value;
      } else if (key === 'contextBudgetChars') {
        next.contextBudgetChars = value;
      } else if (key === 'autoCompactPercent') {
        next.autoCompactPercent = value;
      } else if (key === 'messageFontScale') {
        next.messageFontScale = value;
      } else if (key === 'inputFontScale') {
        next.inputFontScale = value;
      } else {
        next.fontScale = value;
      }
      return true;
    }
    if (key === 'toolsEnabled' || key === 'allowWriteTools' ||
      key === 'imageToolsEnabled' || key === 'imageGenEnabled' ||
      key === 'clipboardToolsEnabled' || key === 'calendarToolsEnabled' ||
      key === 'contactsToolsEnabled' || key === 'locationToolsEnabled' ||
      key === 'weatherToolsEnabled' || key === 'confirmWriteTools' ||
      key === 'autoCompact' || key === 'loggingEnabled' ||
      key === 'memoryEnabled' || key === 'backgroundEnabled' ||
      key === 'enterToSend' || key === 'appLockEnabled' ||
      key === 'autoExpandThinking' || key === 'autoFocusInput' ||
      key === 'autoTitleEnabled' || key === 'autoGroupingEnabled' ||
      key === 'fastMode' || key === 'webDavAutoSync') {
      if (typeof parsed !== 'boolean') {
        return false;
      }
      const value: boolean = parsed as boolean;
      if (key === 'toolsEnabled') {
        next.toolsEnabled = value;
      } else if (key === 'allowWriteTools') {
        next.allowWriteTools = value;
      } else if (key === 'imageToolsEnabled') {
        next.imageToolsEnabled = value;
      } else if (key === 'imageGenEnabled') {
        next.imageGenEnabled = value;
      } else if (key === 'clipboardToolsEnabled') {
        next.clipboardToolsEnabled = value;
      } else if (key === 'calendarToolsEnabled') {
        next.calendarToolsEnabled = value;
      } else if (key === 'contactsToolsEnabled') {
        next.contactsToolsEnabled = value;
      } else if (key === 'locationToolsEnabled') {
        next.locationToolsEnabled = value;
      } else if (key === 'weatherToolsEnabled') {
        next.weatherToolsEnabled = value;
      } else if (key === 'confirmWriteTools') {
        next.confirmWriteTools = value;
      } else if (key === 'autoCompact') {
        next.autoCompact = value;
      } else if (key === 'loggingEnabled') {
        next.loggingEnabled = value;
      } else if (key === 'memoryEnabled') {
        next.memoryEnabled = value;
      } else if (key === 'backgroundEnabled') {
        next.backgroundEnabled = value;
      } else if (key === 'enterToSend') {
        next.enterToSend = value;
      } else if (key === 'appLockEnabled') {
        next.appLockEnabled = value;
      } else if (key === 'autoExpandThinking') {
        next.autoExpandThinking = value;
      } else if (key === 'autoFocusInput') {
        next.autoFocusInput = value;
      } else if (key === 'autoTitleEnabled') {
        next.autoTitleEnabled = value;
      } else if (key === 'autoGroupingEnabled') {
        next.autoGroupingEnabled = value;
      } else if (key === 'fastMode') {
        next.fastMode = value;
      } else {
        next.webDavAutoSync = value;
      }
      return true;
    }
    if (typeof parsed !== 'string') {
      return false;
    }
    const value: string = parsed as string;
    if (key === 'preset') {
      if (value !== 'opencode' && value !== 'custom' && value !== 'anthropic' &&
        value !== 'gemini' && value !== 'copilot' && value !== 'codex') {
        return false;
      }
      next.preset = value as ProviderPreset;
    } else if (key === 'sandboxMode') {
      if (value !== 'local' && value !== 'remote') {
        return false;
      }
      next.sandboxMode = value as SandboxMode;
    } else if (key === 'thinkingLevel') {
      if (value !== 'off' && value !== 'low' && value !== 'medium' &&
        value !== 'high') {
        return false;
      }
      next.thinkingLevel = value as ThinkingLevel;
    } else if (key === 'baseUrl') {
      next.baseUrl = value;
    } else if (key === 'modelId') {
      next.modelId = value;
    } else if (key === 'systemPrompt') {
      next.systemPrompt = value;
    } else if (key === 'sandboxUrl') {
      next.sandboxUrl = value;
    } else if (key === 'accentColor') {
      next.accentColor = value;
    } else if (key === 'soulId') {
      next.soulId = value;
    } else if (key === 'webDavUrl') {
      next.webDavUrl = value;
    } else if (key === 'webDavUser') {
      next.webDavUser = value;
    } else {
      return false;
    }
    return true;
  }

  private restoreConfigAudit(id: string): void {
    let entry: ConfigAuditEntry | null = null;
    for (let i = 0; i < this.configAudit.length; i++) {
      if (this.configAudit[i].id === id) {
        entry = this.configAudit[i];
        break;
      }
    }
    if (entry === null) {
      this.toast(t('该配置记录已不存在'));
      return;
    }
    if (!entry.restorable) {
      this.toast(t('该配置项不支持还原'));
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    if (!this.applyAuditedValue(next, entry.key, entry.before)) {
      this.toast(t('该配置值无法还原'));
      return;
    }
    const key: string = entry.key;
    this.applySettings(next);
    this.toast(t('已还原配置 ') + key);
  }

  private clearConfigAudit(): void {
    this.configAudit = [];
    try {
      const context: common.UIAbilityContext =
        getContext(this) as common.UIAbilityContext;
      ConfigAuditStore.clear(context);
    } catch (e) {
    }
    this.toast(t('配置变更记录已清空'));
  }

  private applySettings(next: AppSettings): void {
    this.recordConfigChanges(this.settings, next);
    this.settings = next;
    this.applyAppearance(next);
    AppLogger.setEnabled(next.loggingEnabled);
    this.showSettings = false;
    LocalStore.saveSettings(next).catch((error: Error) => {
      this.toast(t('设置保存失败'));
    });
    McpRegistry.refresh(next.mcpServers, false, this.hasMcpForceEnabled())
      .catch((error: Error) => {});
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session !== null) {
      session.meta.modelId = next.modelId;
    }
    this.refreshSessions();
    this.scheduleAutoSync();
    this.toast(t('设置已保存'));
  }

  private pickModel(id: string): void {
    if (id.length === 0) {
      return;
    }
    const next: AppSettings = cloneSettings(this.settings);
    next.modelId = id;
    this.recordConfigChanges(this.settings, next);
    this.settings = next;
    this.showModels = false;
    LocalStore.saveSettings(next).catch((error: Error) => {
      this.toast(t('模型设置保存失败'));
    });
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session !== null) {
      session.meta.modelId = id;
    }
    this.refreshSessions();
    this.toast(t('已切换到 ') + id);
  }

  /**
   * A subagent finished: keep its transcript as a normal stored session. The
   * sidebar shows it immediately, so the user can read the work or continue
   * that conversation manually.
   */
  private adoptSubagentSession(session: StoredSession): void {
    session.meta.messageCount = session.messages.length;
    session.meta.updatedAt = Date.now();
    let replaced: boolean = false;
    const next: StoredSession[] = [];
    for (let i = 0; i < this.store.length; i++) {
      if (this.store[i].meta.id === session.meta.id) {
        next.push(session);
        replaced = true;
      } else {
        next.push(this.store[i]);
      }
    }
    if (!replaced) {
      next.unshift(session);
    }
    this.store = next;
    this.refreshSessions();
    this.persistSoon();
  }

  private persistSoon(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.persistNow();
    }, 500);
  }

  private persistNow(): void {
    const snapshot: StoredSession[] = this.store.slice();
    LocalStore.saveSessions(snapshot).catch((error: Error) => {
      // Persistence failures should not interrupt the conversation.
    });
    this.publishWidget();
  }

  /** Mirror the current conversation into the home-screen card. */
  private publishWidget(): void {
    let title: string = 'Minis';
    let body: string = t('打开应用开始新对话');
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session !== null) {
      title = session.meta.title.length > 0 ? session.meta.title : t('未命名对话');
      for (let i = session.messages.length - 1; i >= 0; i--) {
        const message: ChatMessage = session.messages[i];
        if (message.role !== 'assistant') {
          continue;
        }
        const text: string = textOf(message).trim();
        if (text.length === 0) {
          continue;
        }
        body = widgetExcerpt(text, 120);
        break;
      }
    }
    const hint: string = this.streaming ? t('生成中') : '';
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    WidgetBridge.publish(context, title, body, hint).catch((error: Error) => {
      // The card is decorative; never disturb the conversation for it.
    });
  }

  @Builder
  loadingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.accent)
      Text(t('正在加载…'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg'))
  }

  @Builder
  sessionActionsDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.actionId = '';
        })
      Column({ space: 10 }) {
        Text(t('会话操作'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Column({ space: 4 }) {
          Text(this.actionPinned() ? t('取消置顶') : t('置顶'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.togglePin())
          Text(this.actionArchived() ? t('取消归档') : t('归档'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.toggleArchive())
          Text(t('移动到分组'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => {
              this.folderMoveId = this.actionId;
              this.actionId = '';
            })
          Text(t('复制为新会话'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.forkSession(this.actionId))
          Text(t('会话参数'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.openSessionParams(this.actionId))
          Text(t('重新生成标题'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => {
              const session: StoredSession | null = this.findSession(this.actionId);
              this.actionId = '';
              if (session !== null) {
                this.requestTitle(session, true);
              }
            })
          Text(t('导出为 Markdown'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.exportSession(this.actionId))
          Text(t('导出为 JSON'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.exportSessionJson(this.actionId))
          Text(t('删除会话'))
            .fontSize(14)
            .fontColor($r('app.color.danger'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => {
              this.deleteId = this.actionId;
              this.actionId = '';
            })
        }
        .width('100%')

        Button(t('取消'), { type: ButtonType.Normal })
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.actionId = '';
          })
      }
      .width('82%')
      .constraintSize({ maxWidth: 360 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  private moveTargetFolder(): string {
    const session: StoredSession | null = this.findSession(this.folderMoveId);
    return session !== null && session.meta.folderId !== undefined
      ? session.meta.folderId
      : '';
  }

  @Builder
  folderMoveDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.folderMoveId = '';
        })
      Column({ space: 10 }) {
        Text(t('移动到分组'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Column({ space: 4 }) {
          Text((this.moveTargetFolder().length === 0 ? '✓ ' : '') + t('未分组'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.moveSessionToFolder(''))
          ForEach(this.settings.sessionFolders, (folder: SessionFolder) => {
            Text((this.moveTargetFolder() === folder.id ? '✓ ' : '') + folder.name)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .padding({ left: 12, right: 12, top: 11, bottom: 11 })
              .borderRadius(10)
              .backgroundColor($r('app.color.surface_alt'))
              .onClick(() => this.moveSessionToFolder(folder.id))
          }, (folder: SessionFolder) => folder.id + ':' + folder.name + ':' +
            (this.moveTargetFolder() === folder.id ? '1' : '0'))
        }
        .width('100%')
        Button(t('取消'), { type: ButtonType.Normal })
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.folderMoveId = '';
          })
      }
      .width('82%')
      .constraintSize({ maxWidth: 360 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  folderManagerDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.showFolderManager = false;
          this.folderEditId = '';
        })
      Column({ space: 10 }) {
        Text(t('管理分组'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Row({ space: 8 }) {
          TextInput({ text: this.folderDraft, placeholder: t('分组名称') })
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.folderDraft = value;
            })
            .onSubmit(() => this.createFolder())
          Text(t('新建分组'))
            .fontSize(12)
            .fontColor($r('app.color.on_accent'))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.accent)
            .borderRadius(10)
            .onClick(() => this.createFolder())
        }
        .width('100%')

        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.settings.sessionFolders, (folder: SessionFolder) => {
              Column({ space: 6 }) {
                if (this.folderEditId === folder.id) {
                  Row({ space: 8 }) {
                    TextInput({ text: this.folderEditDraft, placeholder: t('分组名称') })
                      .layoutWeight(1)
                      .height(36)
                      .fontSize(13)
                      .fontColor($r('app.color.text_primary'))
                      .backgroundColor($r('app.color.surface_alt'))
                      .borderRadius(9)
                      .padding({ left: 10, right: 10 })
                      .onChange((value: string) => {
                        this.folderEditDraft = value;
                      })
                      .onSubmit(() => this.commitFolderRename())
                    Text(t('保存'))
                      .fontSize(12)
                      .fontColor(this.accent)
                      .onClick(() => this.commitFolderRename())
                  }
                  .width('100%')
                } else {
                  Row({ space: 8 }) {
                    Text(folder.collapsed ? '▸' : '▾')
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                    Text(folder.name)
                      .fontSize(13)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(this.folderCount(folder.id).toString())
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                    Text(t('重命名'))
                      .fontSize(11)
                      .fontColor(this.accent)
                      .onClick(() => this.beginFolderRename(folder.id))
                    Text(t('删除分组'))
                      .fontSize(11)
                      .fontColor($r('app.color.danger'))
                      .onClick(() => this.deleteFolder(folder.id))
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 9, bottom: 9 })
                  .borderRadius(10)
                  .backgroundColor($r('app.color.surface_alt'))
                }
              }
              .width('100%')
            }, (folder: SessionFolder) => folder.id + ':' + folder.name + ':' +
              this.folderCount(folder.id).toString() + ':' +
              (this.folderEditId === folder.id ? this.folderEditDraft : ''))
            if (this.settings.sessionFolders.length === 0) {
              Text(t('还没有分组'))
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ top: 8, bottom: 8 })
            }
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .scrollBar(BarState.Off)

        Button(t('取消'), { type: ButtonType.Normal })
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showFolderManager = false;
            this.folderEditId = '';
          })
      }
      .width('82%')
      .constraintSize({ maxWidth: 380 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  private thinkingLabel(value: string): string {
    if (value === 'low') {
      return t('低');
    }
    if (value === 'medium') {
      return t('中');
    }
    if (value === 'high') {
      return t('高');
    }
    if (value === 'off') {
      return t('关闭');
    }
    return t('跟随全局');
  }

  @Builder
  sessionParamsDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.paramsId = '';
        })
      Column({ space: 10 }) {
        Text(t('会话参数'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(t('只影响当前对话；留空或「跟随全局」即继承设置。'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Text(t('模型 ID'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({ text: this.paramModel, placeholder: t('留空则使用全局模型') })
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .onChange((value: string) => {
            this.paramModel = value;
          })

        Text(t('思考档位'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Row({ space: 6 }) {
          ForEach(['', 'off', 'low', 'medium', 'high'], (value: string) => {
            Text(this.thinkingLabel(value))
              .fontSize(12)
              .fontColor(this.paramThinking === value
                ? $r('app.color.on_accent')
                : $r('app.color.text_primary'))
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .borderRadius(9)
              .backgroundColor(this.paramThinking === value
                ? this.accent
                : $r('app.color.surface_alt'))
              .onClick(() => {
                this.paramThinking = value;
              })
          })
        }
        .width('100%')

        Text(t('追加系统提示词'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextArea({ text: this.paramPrompt, placeholder: t('只在本会话追加，留空则不加') })
          .width('100%')
          .height(84)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .onChange((value: string) => {
            this.paramPrompt = value;
          })

        Text(t('MCP 服务'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(t('只影响当前对话；关闭后本轮不向模型提供该服务的工具。全局关闭的服务可在此仅为本会话重新打开。'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        if (this.settings.mcpServers.length === 0) {
          Text(t('尚未配置 MCP 服务。'))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        } else {
          ForEach(this.settings.mcpServers, (server: McpServerConfig) => {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text(server.name)
                  .fontSize(13)
                  .fontColor(server.enabled
                    ? $r('app.color.text_primary')
                    : $r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(server.enabled
                  ? server.id
                  : (isMcpEnabled(this.paramMcpEnabled, server.id)
                    ? server.id + ' · ' + t('本会话启用') : t('全局已关闭')))
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch,
                isOn: mcpServerActive(server.enabled, this.paramMcpDisabled,
                  this.paramMcpEnabled, server.id) })
                .selectedColor(this.accent)
                .onChange((on: boolean) => {
                  this.paramMcpDisabled = setMcpDisabled(
                    this.paramMcpDisabled, server.id, server.enabled && !on);
                  this.paramMcpEnabled = setMcpEnabled(
                    this.paramMcpEnabled, server.id, !server.enabled && on);
                })
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }, (server: McpServerConfig) => server.id)
        }

        Row({ space: 8 }) {
          Button(t('恢复全局'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => this.resetSessionParams())
          Button(t('取消'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.paramsId = '';
            })
          Button(t('保存'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accent)
            .borderRadius(11)
            .onClick(() => this.saveSessionParams())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 440 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  memoryPanel() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.memoryOpen = false;
        })
      Column({ space: 10 }) {
        Row() {
          Column({ space: 2 }) {
            Text(t('记忆'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(t('查看本轮注入的记忆、编辑记忆文件，并回看近期读写。'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .padding(6)
            .onClick(() => {
              this.memoryOpen = false;
            })
        }
        .width('100%')

        if (this.memoryNotice.length > 0) {
          Text(this.memoryNotice)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(8)
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(8)
        }

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 6 }) {
              Text(t('本轮注入的系统提示'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              if (this.memoryInjected.length === 0) {
                Text(t('当前没有可注入的记忆内容。'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              } else {
                Text(this.memoryInjected)
                  .fontSize(11)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(17)
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
              }
            }
            .width('100%')

            Divider().color($r('app.color.border'))

            Column({ space: 10 }) {
              Text(t('记忆文件'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              ForEach(this.memoryFiles, (file: MemoryFile, index: number) => {
                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    Text(file.name)
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Text(t('撤销'))
                      .fontSize(11)
                      .fontColor(this.memoryDrafts[index] === this.memoryOriginals[index]
                        ? $r('app.color.text_tertiary')
                        : $r('app.color.text_secondary'))
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .enabled(this.memoryDrafts[index] !== this.memoryOriginals[index])
                      .onClick(() => this.undoMemoryAt(index))
                    Text(t('保存'))
                      .fontSize(11)
                      .fontColor($r('app.color.on_accent'))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor(this.accent)
                      .borderRadius(7)
                      .onClick(() => this.saveMemoryAt(index))
                  }
                  .width('100%')
                  TextArea({
                    text: this.memoryDrafts[index],
                    placeholder: t('这个记忆文件还是空的')
                  })
                    .width('100%')
                    .height(76)
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                    .placeholderColor($r('app.color.text_tertiary'))
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(9)
                    .onChange((value: string) => {
                      const next: string[] = this.memoryDrafts.slice();
                      next[index] = value;
                      this.memoryDrafts = next;
                    })
                  Row({ space: 6 }) {
                    Text(this.memoryLineFile === index ? '▾' : '▸')
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                    Text(t('逐条编辑'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                  }
                  .width('100%')
                  .padding({ top: 2, bottom: 2 })
                  .onClick(() => this.toggleMemoryLines(index))
                  .accessibilityText(t('逐条编辑'))
                  if (this.memoryLineFile === index) {
                    Column({ space: 5 }) {
                      if (this.memoryLinesAt(index).length === 0) {
                        Text(t('这个记忆文件还没有条目。'))
                          .fontSize(11)
                          .fontColor($r('app.color.text_tertiary'))
                          .width('100%')
                      } else {
                        ForEach(this.memoryLinesAt(index), (line: MemoryLine) => {
                          Row({ space: 8 }) {
                            Text(line.text)
                              .fontSize(11)
                              .fontColor($r('app.color.text_primary'))
                              .layoutWeight(1)
                              .maxLines(2)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text(t('编辑'))
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                              .onClick(() => this.beginMemoryLine(index, line))
                          }
                          .width('100%')
                          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                          .backgroundColor($r('app.color.surface_alt'))
                          .borderRadius(7)
                        }, (line: MemoryLine) =>
                          file.name + '#' + line.index.toString())
                      }
                      if (this.memoryLineIndex >= 0) {
                        TextArea({
                          text: this.memoryLineDraft,
                          placeholder: t('编辑这一条记忆')
                        })
                          .width('100%')
                          .height(56)
                          .fontSize(12)
                          .fontColor($r('app.color.text_primary'))
                          .placeholderColor($r('app.color.text_tertiary'))
                          .backgroundColor($r('app.color.surface_alt'))
                          .borderRadius(9)
                          .onChange((value: string) => {
                            this.memoryLineDraft = value;
                          })
                        Row({ space: 12 }) {
                          Text(t('取消'))
                            .fontSize(11)
                            .fontColor($r('app.color.text_secondary'))
                            .onClick(() => this.closeMemoryLine())
                          Text(t('还原'))
                            .fontSize(11)
                            .fontColor($r('app.color.text_secondary'))
                            .onClick(() => this.restoreMemoryLine())
                          Blank()
                          Text(t('删除'))
                            .fontSize(11)
                            .fontColor($r('app.color.danger'))
                            .onClick(() => this.deleteMemoryLine())
                          Text(t('保存'))
                            .fontSize(11)
                            .fontColor($r('app.color.on_accent'))
                            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                            .backgroundColor(this.accent)
                            .borderRadius(7)
                            .onClick(() => this.saveMemoryLine())
                        }
                        .width('100%')
                      }
                    }
                    .width('100%')
                    .padding({ left: 2, right: 2 })
                  }
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(11)
                .border({ width: 1, color: $r('app.color.border') })
              }, (file: MemoryFile) => file.name)
            }
            .width('100%')

            Divider().color($r('app.color.border'))

            Column({ space: 6 }) {
              Text(t('近期读写'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              if (this.memoryLogs.length === 0) {
                Text(t('本次启动后还没有记忆读写。'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              } else {
                ForEach(this.memoryLogs, (entry: MemoryLogEntry, index: number) => {
                  Row({ space: 8 }) {
                    Text(this.memoryClock(entry.at))
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                    Text(entry.text)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .layoutWeight(1)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ top: 3, bottom: 3 })
                }, (entry: MemoryLogEntry, index: number) =>
                  entry.at.toString() + '_' + index.toString())
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding({ right: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('92%')
      .constraintSize({ maxWidth: 560 })
      .height('86%')
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  deleteDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.deleteId = '';
        })
      Column({ space: 12 }) {
        Text(t('删除这个对话？'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(t('对话内容与全部上下文会从本机移除，无法恢复。'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        Row({ space: 10 }) {
          Button(t('取消'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => {
              this.deleteId = '';
            })
          Button(t('删除'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.danger'))
            .borderRadius(11)
            .onClick(() => this.performDelete())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 380 })
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  lockScreen() {
    Column({ space: 12 }) {
      Text(t('Minis Harmony 已锁定'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(t('验证系统锁屏密码、人脸或指纹后继续。'))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
      Button(this.unlocking ? t('验证中…') : t('解锁'), { type: ButtonType.Normal })
        .height(38)
        .width(160)
        .fontSize(13)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accent)
        .borderRadius(10)
        .enabled(!this.unlocking)
        .onClick(() => {
          this.lockApp();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  toolPermissionDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
      Column({ space: 10 }) {
        Text(t('允许模型修改文件？'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(t('工具：') + this.confirmName)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Scroll() {
          Text(this.confirmArgs)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 200 })
        .padding(10)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(9)
        .scrollBar(BarState.Auto)
        Row({ space: 10 }) {
          Button(t('拒绝'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => this.settleToolPermission(false))
          Button(t('允许'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accent)
            .borderRadius(11)
            .onClick(() => this.settleToolPermission(true))
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * Backup password prompt. Passwords stay in component state only and are
   * never logged or persisted; closing the dialog clears them.
   */
  @Builder
  passwordDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
      Column({ space: 12 }) {
        Text(this.passwordMode === 'encrypt' ? t('加密备份') : t('解密备份'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.passwordMode === 'encrypt'
          ? t('设置一个备份密码（AES-256-GCM）。忘记密码后这份备份无法恢复，请妥善保存。')
          : t('这是加密备份，请输入导出时设置的密码。'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        TextInput({
          text: this.passwordValue,
          placeholder: this.passwordMode === 'encrypt' ? t('密码（至少 6 位）') : t('备份密码')
        })
          .type(InputType.Password)
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.passwordValue = value;
          })
        if (this.passwordMode === 'encrypt') {
          TextInput({ text: this.passwordConfirm, placeholder: t('再次输入密码') })
            .type(InputType.Password)
            .width('100%')
            .height(42)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.passwordConfirm = value;
            })
        }
        Row({ space: 10 }) {
          Button(t('取消'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .enabled(!this.passwordBusy)
            .onClick(() => this.closePasswordDialog())
          Button(this.passwordBusy ? t('处理中…') :
            (this.passwordMode === 'encrypt' ? t('导出加密备份') : t('解密并导入')),
            { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accent)
            .borderRadius(11)
            .enabled(!this.passwordBusy)
            .onClick(() => {
              this.submitPassword();
            })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  editDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.editing = false;
        })
      Column({ space: 12 }) {
        Text(t('编辑消息'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(t('修改后会删除这条消息之后的回复，并从这里重新开始。'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        TextArea({ text: this.editText, placeholder: t('输入消息…') })
          .width('100%')
          .height(140)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .padding(10)
          .onChange((value: string) => {
            this.editText = value;
          })
        Row({ space: 10 }) {
          Button(t('取消'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => {
              this.editing = false;
            })
          Button(t('保存并重发'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accent)
            .borderRadius(11)
            .onClick(() => this.confirmEdit())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 480 })
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  rewindDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.rewindId = '';
        })
      Column({ space: 12 }) {
        Text(t('回退到这条消息？'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(t('其后的 ') + this.rewindCount().toString() +
          t(' 条消息（含工具结果）会被删除，当前消息保留。可用「编辑」修改后再发送。'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        Row({ space: 10 }) {
          Button(t('取消'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => {
              this.rewindId = '';
            })
          Button(t('回退'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accent)
            .borderRadius(11)
            .onClick(() => this.performRewind())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 400 })
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sidebar() {
    SidebarView({
      sessions: this.sessions,
      searchEntries: this.searchEntries,
      folders: this.settings.sessionFolders,
      currentId: this.currentId,
      query: $query,
      showArchived: this.showArchived,
      onToggleArchived: () => {
        this.showArchived = !this.showArchived;
      },
      onNew: () => this.createChat(),
      onImport: () => this.importSessionFromFile(),
      onBackup: () => this.exportBackup(),
      onEncryptedBackup: () => this.exportEncryptedBackup(),
      onSelect: (id: string) => this.selectSession(id),
      onMore: (id: string) => this.requestActions(id),
      onSettings: () => {
        this.showSettings = true;
      },
      onExportSelected: (ids: string[]) => {
        this.exportSelectedSessions(ids);
      },
      onToggleFolder: (id: string) => this.toggleFolder(id),
      onNewInFolder: (id: string) => this.createChatInFolder(id),
      onManageFolders: () => {
        this.showFolderManager = true;
      }
    })
  }

  @Builder
  chat() {
    ChatView({
      messages: this.messages,
      streaming: this.streaming,
      modelId: this.effectiveModelId(),
      title: this.currentTitle(),
      isWide: this.isWide,
      // A language switch rebuilds the page; do not pop the keyboard then.
      autoFocusComposer: this.i18nEpoch === 0,
      hasKey: this.settings.apiKey.trim().length > 0,
      enterToSend: this.settings.enterToSend,
      canThink: this.canSetThinking(),
      thinkingLevel: this.effectiveThinking(),
      onThinkingLevel: (value: string) => this.setThinkingLevel(value),
      compactNotice: this.compactNotice,
      canUndoCompact: this.canUndoCompact,
      onUndoCompact: () => this.undoCompact(),
      onDismissCompactNotice: () => this.dismissCompactNotice(),
      draft: $draft,
      workspaceRoot: this.workspaceRoot,
      attachments: this.pendingAttachments,
      onHugePaste: (text: string) => this.attachHugePaste(text),
      queuedCount: this.queuedPrompts.length,
      canFastMode: supportsFastMode(this.settings.preset, this.settings.baseUrl),
      fastMode: this.settings.fastMode,
      onFastMode: (on: boolean) => this.setFastMode(on),
      onSend: () => this.sendMessage(),
      onQueue: () => this.sendMessage(),
      onClearQueued: () => this.clearQueuedPrompts(),
      onStop: () => this.stopStream(),
      onPickImage: () => this.pickImages(),
      onPickVideo: () => this.pickVideos(),
      onPickAudio: () => this.pickAudio(),
      onTakePhoto: () => this.takePhoto(),
      onRemoveAttachment: (index: number) => this.removeAttachment(index),
      onSettings: () => {
        this.showSettings = true;
      },
      onMemory: () => this.openMemoryPanel(),
      onScheduledTasks: () => {
        this.showTasks = true;
      },
      onPickModel: () => {
        this.showModels = true;
      },
      onBack: () => {
        this.mobileChat = false;
      },
      onNew: () => this.createChat(),
      onRegenerate: () => this.regenerateLast(),
      onEdit: (id: string) => this.beginEdit(id),
      onRewind: (id: string) => this.requestRewind(id),
      onRerunTool: (messageId: string, part: MessagePart) =>
        this.rerunFromTool(messageId, part),
      onSnapshot: (message: ChatMessage, question: string) => {
        this.shareTurn(message, question);
      },
      onOpenLink: (url: string) => {
        this.browserUrl = url;
        this.showBrowser = true;
      },
      onOpenMinis: (resource: MinisResource) => this.openMinisResource(resource)
    })
  }

  @Builder
  browserOverlay() {
    BrowserPage({
      initialUrl: this.browserUrl,
      onClose: () => {
        this.showBrowser = false;
      }
    })
  }

  @Builder
  imageOverlay() {
    Column({ space: 12 }) {
      Image('file://' + this.previewImagePath)
        .width('100%')
        .layoutWeight(1)
        .objectFit(ImageFit.Contain)
      Text(t('点击任意处关闭'))
        .fontSize(12)
        .fontColor('#CCFFFFFF')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#000000')
    .onClick(() => {
      this.previewImageOpen = false;
    })
  }

  @Builder
  textOverlay() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(this.previewTextTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(t('关闭'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.previewTextOpen = false;
          })
      }
      .width('100%')

      Scroll() {
        Column() {
          if (this.previewTextError.length > 0) {
            Text(this.previewTextError)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else {
            Text(this.previewTextBody)
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_primary'))
              .fontFamily('monospace')
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor($r('app.color.bg'))
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // The two branches are identical on purpose: ArkUI treats them
      // as different branches, so changing i18nEpoch rebuilds every
      // descendant instead of reusing cached t() text.
      if (this.i18nEpoch % 2 === 0) {
        this.pageBody()
      } else {
        this.pageBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width: number = Number.parseFloat(newValue.width.toString());
      if (!Number.isNaN(width) && width > 0) {
        this.isWide = width >= 840;
      }
    })
    .bindContentCover($$this.showBrowser, this.browserOverlay())
    .bindContentCover($$this.previewImageOpen, this.imageOverlay())
    .bindContentCover($$this.previewTextOpen, this.textOverlay())
  }

  onI18nChanged(): void {
    // Defer past the click handler: the language sheet is part of the
    // subtree about to be recreated.
    setTimeout(() => {
      this.i18nEpoch++;
    }, 60);
  }

  @Builder
  pageBody() {
      if (this.ready) {
        HiddenBrowser({ workspaceRoot: this.workspaceRoot })
        InlineMathHost()
      }

      if (!this.ready) {
        this.loadingView()
      } else if (this.isWide) {
        Row() {
          Column() {
            this.sidebar()
          }
          .width(300)
          .height('100%')

          Column() {
            this.chat()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else if (this.mobileChat) {
        Column() {
          this.chat()
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          this.sidebar()
        }
        .width('100%')
        .height('100%')
      }

      if (this.actionId.length > 0) {
        this.sessionActionsDialog()
      }

      if (this.folderMoveId.length > 0) {
        this.folderMoveDialog()
      }

      if (this.showFolderManager) {
        this.folderManagerDialog()
      }

      if (this.paramsId.length > 0) {
        this.sessionParamsDialog()
      }

      if (this.memoryOpen) {
        this.memoryPanel()
      }

      if (this.deleteId.length > 0) {
        this.deleteDialog()
      }

      if (this.editing) {
        this.editDialog()
      }

      if (this.confirmVisible) {
        this.toolPermissionDialog()
      }

      if (this.passwordVisible) {
        this.passwordDialog()
      }

      if (this.rewindId.length > 0) {
        this.rewindDialog()
      }

      if (this.showSettings) {
        SettingsSheet({
          settings: this.settings,
          mcpIncludeDisabled: this.hasMcpForceEnabled(),
          loadSessionStorage: () => this.sessionStorageRows(),
          sessionTitle: (id: string) => this.sessionTitleById(id),
          onClearSessionStorage: (id: string) => this.clearSessionStorage(id),
          auditEntries: this.configAudit.slice(0, 30),
          onRestoreAudit: (id: string) => this.restoreConfigAudit(id),
          onClearAudit: () => this.clearConfigAudit(),
          onCancel: () => {
            this.showSettings = false;
          },
          onSave: (next: AppSettings) => this.applySettings(next),
          onToast: (message: string) => this.toast(message),
          onBrowseWorkspace: () => {
            this.workspaceInitial = '';
            this.showWorkspace = true;
          },
          onExportDiagnostics: () => this.exportDiagnostics(),
          onUploadRemoteBackup: (url: string, user: string, password: string) => {
            this.uploadRemoteBackup(url, user, password);
          },
          onSyncRemoteBackup: (url: string, user: string, password: string) => {
            this.syncRemoteBackup(url, user, password);
          },
          onDownloadRemoteBackup: (url: string, user: string, password: string) => {
            this.restoreRemoteBackup(url, user, password);
          }
        })
      }

      if (this.showTasks) {
        ScheduledTasksSheet({
          tasks: this.tasks,
          runs: this.taskRuns,
          onCreate: (prompt: string, at: number) => {
            this.createScheduledTask(prompt, at);
          },
          onCancelTask: (id: string) => {
            this.cancelScheduledTask(id);
          },
          onFill: (id: string) => {
            this.fillTask(id);
          },
          onClearRuns: () => {
            this.clearTaskRuns();
          },
          onClose: () => {
            this.showTasks = false;
          }
        })
      }

      if (this.showWorkspace) {
        WorkspaceSheet({
          workspaceRoot: this.workspaceRoot,
          initialPath: this.workspaceInitial,
          onClose: () => {
            this.showWorkspace = false;
            this.workspaceInitial = '';
          },
          onToast: (message: string) => this.toast(message)
        })
      }

      if (this.showOnboarding) {
        OnboardingView({
          initialKey: this.settings.apiKey,
          onFinish: (apiKey: string) => this.finishOnboarding(apiKey, false),
          onSkip: () => this.finishOnboarding('', true)
        })
      }

      if (this.showModels) {
        ModelPicker({
          currentId: this.settings.modelId,
          onPick: (id: string) => this.pickModel(id),
          onTestModel: (id: string) => this.testModel(id),
          imageTestAvailable: this.settings.imageGenEnabled &&
            supportsImageGen(this.settings.preset),
          onTestImage: (id: string) => this.testModelImage(id),
          onClose: () => {
            this.showModels = false;
          }
        })
      }

      if (this.locked) {
        this.lockScreen()
      }
  }
}
