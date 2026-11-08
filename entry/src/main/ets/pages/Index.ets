import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatMessage,
  MessagePart,
  SessionMeta,
  SessionSearchEntry,
  StoredSession,
  ThinkingLevel,
  cloneSettings,
  cycleThinkingLevel,
  defaultSettings,
  newChatMessage,
  rewindMessages,
  searchableText,
  sortSessionMetas,
  textOf,
  textPart
} from '../core/Types';
import { ToolRuntime } from '../core/ToolTypes';
import {
  applySessionParams,
  clearSessionParams,
  effectiveSettings
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
import { BackgroundGuard } from '../service/BackgroundGuard';
import { LocalStore } from '../service/LocalStore';
import { LocalToolRuntime } from '../service/LocalToolRuntime';
import {
  ExportOutcome,
  ImportOutcome,
  importSessionJson,
  saveSessionJson,
  saveSessionMarkdown
} from '../service/ExportService';
import { MemoryStore } from '../service/MemoryStore';
import { SkillDoc, SkillCommand, matchSkillCommand } from '../core/SkillDoc';
import { SkillStore } from '../service/SkillStore';
import { keepScreenOn } from '../service/ScreenWake';
import { RemoteToolRuntime } from '../service/RemoteToolRuntime';
import { SubagentRunner } from '../service/SubagentRunner';
import { titleFrom } from '../service/Format';
import { ChatView } from '../components/ChatView';
import { ModelPicker } from '../components/ModelPicker';
import { SettingsSheet } from '../components/SettingsSheet';
import { WorkspaceSheet } from '../components/WorkspaceSheet';
import { OnboardingView } from '../components/OnboardingView';
import { authenticate } from '../service/AppLock';
import {
  clearGenerationNotification,
  publishDone,
  publishGenerating
} from '../service/Notify';
import { SidebarView } from '../components/SidebarView';

@Entry
@Component
struct Index {
  @StorageProp('accentColor') accent: string = '#2F6BFF';
  @StorageProp('fontScale') fontScale: number = 1;
  @State settings: AppSettings = defaultSettings();
  @State sessions: SessionMeta[] = [];
  @State searchEntries: SessionSearchEntry[] = [];
  @State messages: ChatMessage[] = [];
  @State currentId: string = '';
  @State draft: string = '';
  @State streaming: boolean = false;
  @State compacting: boolean = false;
  @State isWide: boolean = true;
  @State mobileChat: boolean = false;
  @State query: string = '';
  @State showSettings: boolean = false;
  @State showModels: boolean = false;
  @State showWorkspace: boolean = false;
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

  private store: StoredSession[] = [];
  private agent: AgentRuntime | null = null;
  private workspaceRoot: string = '';
  private saveTimer: number = -1;
  private confirmResolve: ((allowed: boolean) => void) | null = null;
  private pageVisible: boolean = true;
  /** Skill body queued by a `/skill-id` command, consumed by the next run. */
  private pendingSkillBody: string = '';

  aboutToAppear(): void {
    this.bootstrap();
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
    try {
      await LocalStore.init(context);
    } catch (e) {
      this.toast('本地存储初始化失败，本次会话不会保存');
    }
    this.settings = await LocalStore.loadSettings();
    this.applyAppearance(this.settings);
    AppLogger.init(context, this.settings.loggingEnabled);
    const loaded: StoredSession[] = await LocalStore.loadSessions();
    this.store = loaded;
    this.refreshSessions();
    if (loaded.length > 0) {
      this.currentId = loaded[0].meta.id;
      this.messages = loaded[0].messages.slice();
      this.mobileChat = true;
    } else {
      this.createChat(false);
      this.mobileChat = false;
    }
    // Only first-time users without a key see the guide; existing installs
    // already configured are left alone.
    this.showOnboarding = !this.settings.onboardingDone &&
      this.settings.apiKey.trim().length === 0;
    this.ready = true;
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
    const unlocked: boolean = await authenticate('解锁 Minis Harmony');
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
      this.toast('设置保存失败');
    });
    if (!skipped && apiKey.length > 0) {
      this.toast('已保存 API Key');
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
    return session === null ? '新对话' : session.meta.title;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
  }

  private createChat(persist: boolean = true): void {
    if (this.streaming) {
      this.toast('请先停止当前生成');
      return;
    }
    const meta: SessionMeta = {
      id: util.generateRandomUUID(true),
      title: '新对话',
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
    this.draft = '';
    this.mobileChat = true;
    if (persist) {
      this.persistSoon();
    }
  }

  private selectSession(id: string): void {
    if (this.streaming) {
      this.toast('请先停止当前生成');
      return;
    }
    const session: StoredSession | null = this.findSession(id);
    if (session === null) {
      return;
    }
    this.currentId = id;
    this.messages = session.messages.slice();
    this.draft = '';
    this.mobileChat = true;
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
    this.toast(session.meta.pinned ? '已置顶' : '已取消置顶');
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
    this.toast(session.meta.archived ? '已归档' : '已取消归档');
  }

  /**
   * Rewind to an earlier message: everything after it is dropped, the message
   * itself is kept as the new end of the conversation. The user can then edit
   * it or send a new turn from that checkpoint.
   */
  private requestRewind(id: string): void {
    if (this.streaming) {
      this.toast('请先停止当前生成');
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
    this.toast('已回退到该消息');
  }

  private async exportSession(id: string): Promise<void> {
    const session: StoredSession | null = this.findSession(id);
    this.actionId = '';
    if (session === null) {
      return;
    }
    if (this.streaming) {
      this.toast('请先停止当前生成');
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
      this.toast('请先停止当前生成');
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ExportOutcome = await saveSessionJson(context, session);
    this.toast(outcome.message);
  }

  private async importSessionFromFile(): Promise<void> {
    if (this.streaming) {
      this.toast('请先停止当前生成');
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const outcome: ImportOutcome =
      await importSessionJson(context, util.generateRandomUUID(true));
    if (!outcome.ok || outcome.session === null) {
      this.toast(outcome.message);
      return;
    }
    const session: StoredSession = outcome.session;
    this.store = [session].concat(this.store);
    this.refreshSessions();
    this.currentId = session.meta.id;
    this.messages = session.messages.slice();
    this.draft = '';
    this.mobileChat = true;
    this.persistSoon();
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
      this.toast('请先停止当前生成');
      return;
    }
    const meta: SessionMeta = {
      id: util.generateRandomUUID(true),
      title: source.meta.title + ' 副本',
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
    this.mobileChat = true;
    this.persistSoon();
    this.toast('已复制为新会话');
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
    const session: StoredSession | null = this.findSession(this.paramsId);
    this.paramsId = '';
    if (session === null) {
      return;
    }
    applySessionParams(session.meta, this.paramModel, this.paramThinking, this.paramPrompt);
    session.meta.updatedAt = Date.now();
    this.refreshSessions();
    this.persistSoon();
    this.toast('会话参数已保存');
  }

  private resetSessionParams(): void {
    const session: StoredSession | null = this.findSession(this.paramsId);
    this.paramsId = '';
    if (session === null) {
      return;
    }
    clearSessionParams(session.meta);
    session.meta.updatedAt = Date.now();
    this.refreshSessions();
    this.persistSoon();
    this.toast('已恢复为全局设置');
  }

  private performDelete(): void {
    const id: string = this.deleteId;
    this.deleteId = '';
    if (this.streaming && this.currentId === id) {
      this.toast('请先停止当前生成');
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
      } else {
        this.createChat(false);
      }
    }
    this.persistSoon();
  }

  private sendMessage(): void {
    const text: string = this.draft.trim();
    if (text.length === 0 || this.streaming) {
      return;
    }
    if (this.compacting) {
      this.toast('正在压缩上下文，请稍候');
      return;
    }
    if (text.startsWith('/')) {
      this.handleCommand(text);
      return;
    }
    if (this.settings.apiKey.trim().length === 0) {
      this.pendingSkillBody = '';
      this.showSettings = true;
      this.toast('请先填写 API Key');
      return;
    }
    if (this.settings.baseUrl.trim().length === 0) {
      this.pendingSkillBody = '';
      this.showSettings = true;
      this.toast('请先填写 API 地址');
      return;
    }
    if (this.settings.toolsEnabled && this.settings.sandboxMode === 'remote' &&
      this.settings.sandboxUrl.trim().length === 0) {
      this.pendingSkillBody = '';
      this.showSettings = true;
      this.toast('请先填写远程沙箱地址');
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
      session.meta.title = titleFrom(text);
    }
    session.meta.updatedAt = Date.now();
    session.meta.modelId = effectiveSettings(this.settings, session.meta).modelId;

    this.draft = '';
    this.runAgent(session, text, true);
  }

  private runAgent(session: StoredSession, userText: string, fresh: boolean): void {
    const effective: AppSettings = effectiveSettings(this.settings, session.meta);
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
    const runtime: ToolRuntime = this.makeToolRuntime(effective);
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
      this.agent.start(userText);
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
      this.toast('请先停止当前生成');
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
      this.toast('没有可重新生成的回复');
      return;
    }
    this.runAgent(session, '', false);
  }

  /** Open the composer overlay with the message text for editing. */
  private beginEdit(id: string): void {
    if (this.streaming) {
      this.toast('请先停止当前生成');
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
      this.toast('消息不能为空');
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
   */
  private async compactSession(): Promise<void> {
    if (this.streaming) {
      this.toast('请先停止当前生成');
      return;
    }
    if (this.compacting) {
      this.toast('正在压缩上下文');
      return;
    }
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session === null) {
      return;
    }
    const plan: CompactPlan | null =
      planCompact(session.messages, COMPACT_DEFAULT_KEEP_TURNS);
    if (plan === null) {
      this.toast('对话还太短，或最近几轮已覆盖全部内容');
      return;
    }
    const transcript: string =
      transcriptForSummary(plan.head, SUMMARY_TRANSCRIPT_LIMIT);
    this.compacting = true;
    this.toast('正在生成摘要…');
    const result: SummaryResult = await summarizeConversation(
      effectiveSettings(this.settings, session.meta), session.meta.id, transcript
    );
    this.compacting = false;
    if (!result.ok) {
      this.toast('压缩失败：' + result.message);
      return;
    }
    const summary: ChatMessage =
      makeSummaryMessage(util.generateRandomUUID(true), result.text);
    session.messages = [summary].concat(plan.tail);
    session.meta.messageCount = session.messages.length;
    session.meta.updatedAt = Date.now();
    this.messages = session.messages.slice();
    this.refreshSessions();
    this.persistNow();
    this.toast('已压缩 ' + plan.head.length.toString() + ' 条早期消息');
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
        '可用命令：\n' +
          '/new — 新建对话\n' +
          '/clear — 清空当前对话\n' +
          '/compact — 用模型摘要较早的对话，保留最近几轮\n' +
          '/memory — 开启/关闭持久记忆与记忆工具\n' +
          '/thinking — 循环切换思考档位（off → low → medium → high）\n' +
          '/help — 显示本帮助\n';
      const docs: SkillDoc[] = SkillStore.list();
      let skillLines: string = '';
      for (let i = 0; i < docs.length; i++) {
        if (this.settings.enabledSkills.indexOf(docs[i].id) >= 0) {
          skillLines += '\n/' + docs[i].id + ' — 使用技能：' + docs[i].name;
        }
      }
      if (skillLines.length > 0) {
        help += '\n已启用的技能命令：' + skillLines;
      }
      help += '\n\n长对话接近上下文预算时，发送前会自动裁剪较早的工具结果。';
      this.appendLocalNotice(help);
      return;
    }
    if (command === '/clear') {
      const session: StoredSession | null = this.findSession(this.currentId);
      if (session === null) {
        return;
      }
      session.messages = [];
      session.meta.title = '新对话';
      session.meta.messageCount = 0;
      session.meta.updatedAt = Date.now();
      this.messages = [];
      this.refreshSessions();
      this.persistSoon();
      this.toast('当前对话已清空');
      return;
    }
    if (command === '/memory') {
      this.settings.memoryEnabled = !this.settings.memoryEnabled;
      const on: boolean = this.settings.memoryEnabled;
      LocalStore.saveSettings(this.settings).catch((error: Error) => {
        this.toast('设置保存失败');
      });
      this.toast(on ? '持久记忆已开启' : '持久记忆已关闭');
      this.appendLocalNotice(on
        ? '持久记忆已开启：模型可以读写本机记忆，并会在后续对话中看到它。'
        : '持久记忆已关闭：不再注入记忆，记忆工具也会从工具列表移除。');
      return;
    }
    if (command === '/thinking') {
      const next: ThinkingLevel = cycleThinkingLevel(this.settings.thinkingLevel);
      this.settings.thinkingLevel = next;
      LocalStore.saveSettings(this.settings).catch((error: Error) => {
        this.toast('设置保存失败');
      });
      this.toast(next === 'off' ? '思考已关闭' : '思考强度：' + next);
      this.appendLocalNotice(next === 'off'
        ? '已关闭思考：请求不再携带 reasoning_effort。部分模型仍可能返回推理内容。'
        : '已设置思考强度：reasoning_effort=' + next +
          '。再次输入 /thinking 会切换到下一档；到 high 后再切换即关闭。');
      return;
    }
    const skill: SkillCommand | null = matchSkillCommand(raw, this.settings.enabledSkills);
    if (skill !== null) {
      const doc: SkillDoc | null = SkillStore.get(skill.id);
      if (doc === null || doc.body.trim().length === 0) {
        this.toast('技能内容为空：' + skill.id);
        return;
      }
      this.pendingSkillBody = '# 技能：' + doc.name + '\n\n' + doc.body;
      this.draft = skill.rest.length > 0
        ? skill.rest
        : '请按照技能「' + doc.name + '」的说明处理当前任务。';
      this.sendMessage();
      return;
    }
    this.toast('未知命令，输入 /help 查看');
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

  private makeToolRuntime(settings: AppSettings): ToolRuntime {
    if (settings.sandboxMode === 'remote') {
      return new RemoteToolRuntime(
        settings.sandboxUrl,
        settings.sandboxToken,
        settings.allowWriteTools,
        settings.disabledTools
      );
    }
    return new LocalToolRuntime(
      this.workspaceRoot,
      settings.allowWriteTools,
      settings.memoryEnabled,
      settings.imageToolsEnabled,
      new SubagentRunner(
        settings,
        this.workspaceRoot,
        settings.allowWriteTools
      ),
      settings.disabledTools,
      settings.clipboardToolsEnabled
    );
  }

  private stopStream(): void {
    // Unblock a tool waiting for confirmation, otherwise the loop would keep
    // a pending promise after the generation was stopped.
    this.settleToolPermission(false);
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
      ? argumentsText.substring(0, 1500) + '\n…（已截断）'
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
      this.toast('设置保存失败');
    });
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session !== null) {
      session.meta.modelId = next.modelId;
    }
    this.refreshSessions();
    this.toast('设置已保存');
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
      this.toast('模型设置保存失败');
    });
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session !== null) {
      session.meta.modelId = id;
    }
    this.refreshSessions();
    this.toast('已切换到 ' + id);
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
  }

  @Builder
  loadingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.accent)
      Text('正在加载…')
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
        Text('会话操作')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Column({ space: 4 }) {
          Text(this.actionPinned() ? '取消置顶' : '置顶')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.togglePin())
          Text(this.actionArchived() ? '取消归档' : '归档')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.toggleArchive())
          Text('复制为新会话')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.forkSession(this.actionId))
          Text('会话参数')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.openSessionParams(this.actionId))
          Text('导出为 Markdown')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.exportSession(this.actionId))
          Text('导出为 JSON')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => this.exportSessionJson(this.actionId))
          Text('删除会话')
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

        Button('取消', { type: ButtonType.Normal })
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
      return '低';
    }
    if (value === 'medium') {
      return '中';
    }
    if (value === 'high') {
      return '高';
    }
    if (value === 'off') {
      return '关闭';
    }
    return '跟随全局';
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
        Text('会话参数')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('只影响当前对话；留空或「跟随全局」即继承设置。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Text('模型 ID')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({ text: this.paramModel, placeholder: '留空则使用全局模型' })
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

        Text('思考档位')
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

        Text('追加系统提示词')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextArea({ text: this.paramPrompt, placeholder: '只在本会话追加，留空则不加' })
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
          Button('恢复全局', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => this.resetSessionParams())
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.paramsId = '';
            })
          Button('保存', { type: ButtonType.Normal })
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
        Text('删除这个对话？')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('对话内容与全部上下文会从本机移除，无法恢复。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        Row({ space: 10 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => {
              this.deleteId = '';
            })
          Button('删除', { type: ButtonType.Normal })
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
      Text('🔒')
        .fontSize(30)
      Text('Minis Harmony 已锁定')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('验证系统锁屏密码、人脸或指纹后继续。')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
      Button(this.unlocking ? '验证中…' : '解锁', { type: ButtonType.Normal })
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
        Text('允许模型修改文件？')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('工具：' + this.confirmName)
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
          Button('拒绝', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => this.settleToolPermission(false))
          Button('允许', { type: ButtonType.Normal })
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
        Text('编辑消息')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('修改后会删除这条消息之后的回复，并从这里重新开始。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        TextArea({ text: this.editText, placeholder: '输入消息…' })
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
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => {
              this.editing = false;
            })
          Button('保存并重发', { type: ButtonType.Normal })
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
        Text('回退到这条消息？')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('其后的 ' + this.rewindCount().toString() +
          ' 条消息（含工具结果）会被删除，当前消息保留。可用「编辑」修改后再发送。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
        Row({ space: 10 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(11)
            .onClick(() => {
              this.rewindId = '';
            })
          Button('回退', { type: ButtonType.Normal })
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
      onSelect: (id: string) => this.selectSession(id),
      onMore: (id: string) => this.requestActions(id),
      onSettings: () => {
        this.showSettings = true;
      }
    })
  }

  @Builder
  chat() {
    ChatView({
      messages: this.messages,
      streaming: this.streaming,
      modelId: this.settings.modelId,
      title: this.currentTitle(),
      isWide: this.isWide,
      hasKey: this.settings.apiKey.trim().length > 0,
      enterToSend: this.settings.enterToSend,
      draft: $draft,
      onSend: () => this.sendMessage(),
      onStop: () => this.stopStream(),
      onSettings: () => {
        this.showSettings = true;
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
      onRewind: (id: string) => this.requestRewind(id)
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
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
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width: number = Number.parseFloat(newValue.width.toString());
      if (!Number.isNaN(width) && width > 0) {
        this.isWide = width >= 840;
      }
    })
  }
}
