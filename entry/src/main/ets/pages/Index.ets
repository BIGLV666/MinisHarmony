import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatAttachment,
  ChatMessage,
  MessagePart,
  PART_TEXT,
  SessionMeta,
  SessionSearchEntry,
  StoredSession,
  ThinkingLevel,
  cloneSettings,
  cycleThinkingLevel,
  defaultSettings,
  imagePart,
  newChatMessage,
  rewindMessages,
  searchableText,
  sortSessionMetas,
  textOf,
  textPart
} from '../core/Types';
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
import { SummaryResult, summarizeConversation } from '../service/ChatApi';
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
import { SettingsImageGen } from '../service/ImageGen';
import { DeviceTools } from '../service/DeviceTools';
import { ShellTool } from '../service/ShellTool';
import { SandboxIsh } from '../service/SandboxIsh';
import { OAuthService } from '../service/OAuth';
import { ScreenshotOutcome, saveShareCard } from '../service/Screenshot';
import { shareCardFileName } from '../core/ShareCard';
import { shareCardView } from '../components/ShareCardView';
import { AttachmentStore } from '../service/AttachmentStore';
import { MemoryStore } from '../service/MemoryStore';
import { SkillDoc, SkillCommand, matchSkillCommand } from '../core/SkillDoc';
import { SkillStore } from '../service/SkillStore';
import { keepScreenOn } from '../service/ScreenWake';
import { RemoteToolRuntime } from '../service/RemoteToolRuntime';
import { McpRegistry, McpRuntime } from '../service/McpRuntime';
import { WidgetBridge } from '../service/WidgetBridge';
import { widgetExcerpt } from '../core/WidgetData';
import { mergeBackupSettings } from '../core/Backup';
import { parseBackupSessions } from '../core/SessionExport';
import { SyncMergeResult, mergeSessionSets } from '../core/SyncMerge';
import { parseDeepLink, DeepLink } from '../core/DeepLink';
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
  @State compacting: boolean = false;
  /** One-line notice shown above the composer after a compaction. */
  @State compactNotice: string = '';
  /** False once a newer message makes the snapshot unsafe to restore. */
  @State canUndoCompact: boolean = false;
  @State isWide: boolean = true;
  @State mobileChat: boolean = false;
  @State query: string = '';
  @State showSettings: boolean = false;
  @State showModels: boolean = false;
  @State showWorkspace: boolean = false;
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
  @State paramModel: string = '';
  @State paramThinking: string = '';
  @State paramPrompt: string = '';
  @State rewindId: string = '';
  @State showArchived: boolean = false;
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
    this.applyAppearance(this.settings);
    AppLogger.init(context, this.settings.loggingEnabled);
    CrashLog.init(context);
    // Discovery is best-effort; an offline server just contributes no tools.
    McpRegistry.refresh(this.settings.mcpServers).catch((error: Error) => {});
    const loaded: StoredSession[] = await LocalStore.loadSessions();
    this.store = loaded;
    this.refreshSessions();
    this.tasks = await LocalStore.loadScheduledTasks();
    this.taskRuns = await LocalStore.loadTaskRuns();
    if (loaded.length > 0) {
      this.currentId = loaded[0].meta.id;
      this.messages = loaded[0].messages.slice();
      this.syncThinkingOverride();
      this.mobileChat = true;
      if (this.hasPendingBackgroundResult(loaded[0])) {
        this.runAgent(loaded[0], '', false);
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

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
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

  private createChat(persist: boolean = true): void {
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
    const session: StoredSession = { meta: meta, messages: [] };
    this.store = [session].concat(this.store);
    this.refreshSessions();
    this.currentId = meta.id;
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

  private selectSession(id: string): void {
    if (this.streaming) {
      this.toast(t('请先停止当前生成'));
      return;
    }
    const session: StoredSession | null = this.findSession(id);
    if (session === null) {
      return;
    }
    this.currentId = id;
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
      McpRegistry.refresh(merged.mcpServers).catch((error: Error) => {});
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
      promptOverride: source.meta.promptOverride
    };
    const copied: ChatMessage[] =
      JSON.parse(JSON.stringify(source.messages)) as ChatMessage[];
    const session: StoredSession = { meta: meta, messages: copied };
    this.store = [session].concat(this.store);
    this.refreshSessions();
    this.currentId = meta.id;
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
  }

  private saveSessionParams(): void {
    const id: string = this.paramsId;
    const session: StoredSession | null = this.findSession(id);
    this.paramsId = '';
    if (session === null) {
      return;
    }
    applySessionParams(session.meta, this.paramModel, this.paramThinking, this.paramPrompt);
    session.meta.updatedAt = Date.now();
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
    session.meta.updatedAt = Date.now();
    if (id === this.currentId) {
      this.syncThinkingOverride();
    }
    this.refreshSessions();
    this.persistSoon();
    this.toast(t('已恢复为全局设置'));
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
    if ((text.length === 0 && attachments.length === 0) || this.streaming) {
      return;
    }
    if (this.compacting) {
      this.toast(t('正在压缩上下文，请稍候'));
      return;
    }
    if (text.length > 0 && text.startsWith('/')) {
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
          this.scheduleAutoSync();
          BackgroundGuard.end().catch((error: Error) => {});
          keepScreenOn(getContext(this) as common.UIAbilityContext, false)
            .catch((error: Error) => {});
          if (!this.pageVisible) {
            const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
            publishDone(context, this.currentTitle());
          }
        }
      },
      onError: (message: string) => {
        this.toast(message);
      }
    }, effective.confirmWriteTools
      ? (name: string, argumentsText: string) =>
        this.askToolPermission(name, argumentsText)
      : null);
    if (fresh) {
      const parts: MessagePart[] = [];
      for (let i = 0; i < attachments.length; i++) {
        parts.push(imagePart(attachments[i].uri, attachments[i].mimeType));
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
        shell
      );
    }
    return new McpRuntime(base, settings.disabledTools);
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
  }

  private applySettings(next: AppSettings): void {
    this.settings = next;
    this.applyAppearance(next);
    AppLogger.setEnabled(next.loggingEnabled);
    this.showSettings = false;
    LocalStore.saveSettings(next).catch((error: Error) => {
      this.toast(t('设置保存失败'));
    });
    McpRegistry.refresh(next.mcpServers).catch((error: Error) => {});
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
      attachments: this.pendingAttachments,
      onSend: () => this.sendMessage(),
      onStop: () => this.stopStream(),
      onPickImage: () => this.pickImages(),
      onRemoveAttachment: (index: number) => this.removeAttachment(index),
      onSettings: () => {
        this.showSettings = true;
      },
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
      onSnapshot: (message: ChatMessage, question: string) => {
        this.shareTurn(message, question);
      },
      onOpenLink: (url: string) => {
        this.browserUrl = url;
        this.showBrowser = true;
      }
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
        HiddenBrowser()
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

      if (this.paramsId.length > 0) {
        this.sessionParamsDialog()
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
          onCancel: () => {
            this.showSettings = false;
          },
          onSave: (next: AppSettings) => this.applySettings(next),
          onToast: (message: string) => this.toast(message),
          onBrowseWorkspace: () => {
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
          onClose: () => {
            this.showWorkspace = false;
          }
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
