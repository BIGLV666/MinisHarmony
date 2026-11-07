import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatMessage,
  SessionMeta,
  StoredSession,
  cloneSettings,
  defaultSettings
} from '../core/Types';
import { ToolRuntime } from '../core/ToolTypes';
import { AgentRuntime } from '../service/AgentRuntime';
import { LocalStore } from '../service/LocalStore';
import { LocalToolRuntime } from '../service/LocalToolRuntime';
import { RemoteToolRuntime } from '../service/RemoteToolRuntime';
import { titleFrom } from '../service/Format';
import { ChatView } from '../components/ChatView';
import { ModelPicker } from '../components/ModelPicker';
import { SettingsSheet } from '../components/SettingsSheet';
import { SidebarView } from '../components/SidebarView';

@Entry
@Component
struct Index {
  @State settings: AppSettings = defaultSettings();
  @State sessions: SessionMeta[] = [];
  @State messages: ChatMessage[] = [];
  @State currentId: string = '';
  @State draft: string = '';
  @State streaming: boolean = false;
  @State isWide: boolean = true;
  @State mobileChat: boolean = false;
  @State query: string = '';
  @State showSettings: boolean = false;
  @State showModels: boolean = false;
  @State deleteId: string = '';
  @State ready: boolean = false;

  private store: StoredSession[] = [];
  private agent: AgentRuntime | null = null;
  private workspaceRoot: string = '';
  private saveTimer: number = -1;

  aboutToAppear(): void {
    this.bootstrap();
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
  }

  private async bootstrap(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.workspaceRoot = context.filesDir + '/workspace';
    try {
      await LocalStore.init(context);
    } catch (e) {
      this.toast('本地存储初始化失败，本次会话不会保存');
    }
    this.settings = await LocalStore.loadSettings();
    const loaded: StoredSession[] = await LocalStore.loadSessions();
    this.store = loaded;
    this.sessions = this.buildMetaList();
    if (loaded.length > 0) {
      this.currentId = loaded[0].meta.id;
      this.messages = loaded[0].messages.slice();
      this.mobileChat = true;
    } else {
      this.createChat(false);
      this.mobileChat = false;
    }
    this.ready = true;
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
    metas.sort((a: SessionMeta, b: SessionMeta): number => b.updatedAt - a.updatedAt);
    return metas;
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
      messageCount: 0
    };
    const session: StoredSession = { meta: meta, messages: [] };
    this.store = [session].concat(this.store);
    this.sessions = this.buildMetaList();
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

  private performDelete(): void {
    const id: string = this.deleteId;
    this.deleteId = '';
    if (this.streaming && this.currentId === id) {
      this.toast('请先停止当前生成');
      return;
    }
    this.store = this.store.filter((session: StoredSession): boolean => session.meta.id !== id);
    this.sessions = this.buildMetaList();
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
    if (this.settings.apiKey.trim().length === 0) {
      this.showSettings = true;
      this.toast('请先填写 API Key');
      return;
    }
    if (this.settings.baseUrl.trim().length === 0) {
      this.showSettings = true;
      this.toast('请先填写 API 地址');
      return;
    }
    if (this.settings.toolsEnabled && this.settings.sandboxMode === 'remote' &&
      this.settings.sandboxUrl.trim().length === 0) {
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
    session.meta.modelId = this.settings.modelId;

    const runtime: ToolRuntime = this.makeToolRuntime();
    this.streaming = true;
    this.draft = '';
    this.agent = new AgentRuntime(this.settings, runtime, session, {
      onUpdate: (messages: ChatMessage[], running: boolean) => {
        this.messages = messages;
        this.streaming = running;
        this.sessions = this.buildMetaList();
        this.persistSoon();
        if (!running) {
          this.agent = null;
        }
      },
      onError: (message: string) => {
        this.toast(message);
      }
    });
    this.agent.start(text);
    this.sessions = this.buildMetaList();
    this.persistSoon();
  }

  private makeToolRuntime(): ToolRuntime {
    if (this.settings.sandboxMode === 'remote') {
      return new RemoteToolRuntime(
        this.settings.sandboxUrl,
        this.settings.sandboxToken,
        this.settings.allowWriteTools
      );
    }
    return new LocalToolRuntime(this.workspaceRoot, this.settings.allowWriteTools);
  }

  private stopStream(): void {
    if (this.agent !== null) {
      this.agent.cancel();
      this.agent = null;
    }
    this.streaming = false;
    this.persistSoon();
  }

  private applySettings(next: AppSettings): void {
    this.settings = next;
    this.showSettings = false;
    LocalStore.saveSettings(next).catch((error: Error) => {
      this.toast('设置保存失败');
    });
    const session: StoredSession | null = this.findSession(this.currentId);
    if (session !== null) {
      session.meta.modelId = next.modelId;
    }
    this.sessions = this.buildMetaList();
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
    this.sessions = this.buildMetaList();
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
        .color($r('app.color.accent'))
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
  sidebar() {
    SidebarView({
      sessions: this.sessions,
      currentId: this.currentId,
      query: $query,
      onNew: () => this.createChat(),
      onSelect: (id: string) => this.selectSession(id),
      onDelete: (id: string) => this.requestDelete(id),
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
      onNew: () => this.createChat()
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

      if (this.deleteId.length > 0) {
        this.deleteDialog()
      }

      if (this.showSettings) {
        SettingsSheet({
          settings: this.settings,
          onCancel: () => {
            this.showSettings = false;
          },
          onSave: (next: AppSettings) => this.applySettings(next),
          onToast: (message: string) => this.toast(message)
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
