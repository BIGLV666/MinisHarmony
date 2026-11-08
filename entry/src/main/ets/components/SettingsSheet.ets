import {
  AppSettings,
  OPENCODE_DEFAULT_MODEL,
  OPENCODE_GO_BASE,
  ProviderPreset,
  SandboxMode,
  clampContextBudget,
  clampMaxTurns,
  cloneSettings,
  defaultSettings
} from '../core/Types';
import { isOpenCodeBase, normalizeBaseUrl } from '../core/OpenCodeRules';
import { formatEventLine } from '../core/EventLog';
import { MemoryFile } from '../core/Memory';
import { fetchModelIds, ModelsResult } from '../service/ChatApi';
import { AppLogger } from '../service/AppLogger';
import { MemoryStore } from '../service/MemoryStore';

interface ToolChoice {
  name: string;
  label: string;
}

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
  { name: 'fetch_url', label: '抓取网页' },
  { name: 'now', label: '当前时间' },
  { name: 'subagent_task', label: '子代理' }
];

@Component
export struct SettingsSheet {
  @Prop settings: AppSettings = defaultSettings();
  onCancel: () => void = () => {
  };
  onSave: (settings: AppSettings) => void = (settings: AppSettings) => {
  };
  onToast: (message: string) => void = (message: string) => {
  };
  onBrowseWorkspace: () => void = () => {
  };

  @State preset: ProviderPreset = 'opencode';
  @State baseUrl: string = OPENCODE_GO_BASE;
  @State apiKey: string = '';
  @State modelId: string = OPENCODE_DEFAULT_MODEL;
  @State systemPrompt: string = '';
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
  @State maxTurnsText: string = '200';
  @State contextBudgetText: string = '60000';
  @State loggingEnabled: boolean = false;
  @State memoryEnabled: boolean = false;
  @State imageToolsEnabled: boolean = false;
  @State backgroundEnabled: boolean = true;
  @State enterToSend: boolean = false;
  @State disabledTools: string[] = [];
  @State showLogs: boolean = false;
  @State logLines: string[] = [];
  @State showMemory: boolean = false;
  @State memoryFiles: MemoryFile[] = [];
  @State memoryIndex: number = 0;
  @State memoryText: string = '';

  aboutToAppear(): void {
    const copy: AppSettings = cloneSettings(this.settings);
    this.preset = copy.preset;
    this.baseUrl = copy.baseUrl;
    this.apiKey = copy.apiKey;
    this.modelId = copy.modelId;
    this.systemPrompt = copy.systemPrompt;
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
    this.loggingEnabled = copy.loggingEnabled;
    this.memoryEnabled = copy.memoryEnabled;
    this.imageToolsEnabled = copy.imageToolsEnabled;
    this.backgroundEnabled = copy.backgroundEnabled;
    this.enterToSend = copy.enterToSend;
    this.disabledTools = copy.disabledTools.slice();
  }

  private toolEnabled(name: string): boolean {
    return this.disabledTools.indexOf(name) < 0;
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

  private selectPreset(value: ProviderPreset): void {
    this.preset = value;
    if (value === 'opencode') {
      this.baseUrl = OPENCODE_GO_BASE;
      if (this.modelId.trim().length === 0) {
        this.modelId = OPENCODE_DEFAULT_MODEL;
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

  private draftSettings(): AppSettings {
    const next: AppSettings = {
      preset: this.preset,
      baseUrl: normalizeBaseUrl(this.baseUrl),
      apiKey: this.apiKey.trim(),
      modelId: this.modelId.trim(),
      systemPrompt: this.systemPrompt,
      temperature: this.temperature,
      maxTokens: this.maxTokensValue(),
      toolsEnabled: this.toolsEnabled,
      allowWriteTools: this.allowWriteTools,
      sandboxMode: this.sandboxMode,
      sandboxUrl: this.sandboxUrl.trim(),
      sandboxToken: this.sandboxToken.trim(),
      maxAgentTurns: clampMaxTurns(Number(this.maxTurnsText)),
      contextBudgetChars: clampContextBudget(Number(this.contextBudgetText)),
      loggingEnabled: this.loggingEnabled,
      memoryEnabled: this.memoryEnabled,
      imageToolsEnabled: this.imageToolsEnabled,
      confirmWriteTools: this.confirmWriteTools,
      backgroundEnabled: this.backgroundEnabled,
      thinkingLevel: this.settings.thinkingLevel,
      enterToSend: this.enterToSend,
      disabledTools: this.disabledTools.slice()
    };
    return next;
  }

  private clearLogs(): void {
    const removed: number = AppLogger.clear();
    this.logLines = [];
    this.showLogs = false;
    this.onToast(removed > 0 ? '已删除 ' + removed.toString() + ' 个日志文件' : '没有可删除的日志文件');
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
    if (!result.startsWith('已保存')) {
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
    const raw: string[] = AppLogger.recent(200);
    const lines: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      lines.push(formatEventLine(raw[i]));
    }
    this.logLines = lines;
    this.showLogs = true;
  }

  private clearMemory(): void {
    const removed: number = MemoryStore.clearDaily();
    this.onToast(removed > 0 ? '已清空 ' + removed.toString() + ' 个记忆文件' : '没有可清空的记忆');
  }

  private async probe(): Promise<void> {
    if (this.probing) {
      return;
    }
    this.probing = true;
    this.probeMessage = '正在连接…';
    const result: ModelsResult = await fetchModelIds(this.draftSettings());
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
      this.probeMessage = 'API 地址不能为空';
      return;
    }
    if (next.modelId.length === 0) {
      this.probeMessage = '模型 ID 不能为空';
      return;
    }
    if (next.toolsEnabled && next.sandboxMode === 'remote') {
      if (next.sandboxUrl.length === 0) {
        this.probeMessage = '远程沙箱地址不能为空';
        return;
      }
      if (!next.sandboxUrl.startsWith('http://') &&
        !next.sandboxUrl.startsWith('https://')) {
        this.probeMessage = '远程沙箱地址必须以 http:// 或 https:// 开头';
        return;
      }
    }
    this.onSave(next);
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
        Text(isOpenCodeBase(this.baseUrl) ? '会话头已自动启用' : '当前地址不发送会话头')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(isOpenCodeBase(this.baseUrl)
          ? '每个对话使用固定 UUID，作为 x-opencode-session 随请求发送，用于上游路由与缓存。'
          : '只有 opencode.ai 域名会附加 x-opencode-session，避免把会话标识泄露给自定义中转。')
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
            Text('设置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('OpenAI 兼容接口 · OpenCode Go 预设')
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
            this.sectionTitle('服务商', 'OpenCode Go 使用订阅 API Key；自定义可接任意 OpenAI 兼容服务')
            Row({ space: 10 }) {
              this.presetCard('OpenCode Go', '自动填写当前基址，注入会话头', 'opencode')
              this.presetCard('自定义', '自建中转 / 其他兼容服务', 'custom')
            }
            .width('100%')

            Column() {
              this.fieldLabel('API 地址')
              TextInput({ text: this.baseUrl, placeholder: OPENCODE_GO_BASE })
                .width('100%')
                .height(42)
                .fontSize(13)
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(10)
                .onChange((value: string) => {
                  this.baseUrl = value;
                })
              Text('推理：' + normalizeBaseUrl(this.baseUrl) + '/chat/completions')
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
                TextInput({ text: this.apiKey, placeholder: '在 OpenCode Console 的 Go 订阅页复制' })
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .type(this.showKey ? InputType.Normal : InputType.Password)
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(10)
                  .onChange((value: string) => {
                    this.apiKey = value;
                  })
                Text(this.showKey ? '隐藏' : '显示')
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

            Column() {
              this.fieldLabel('模型 ID')
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
                Button(this.probing ? '…' : '获取')
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

            this.sectionTitle('生成参数', '按模型能力调整；不确定时保持默认')
            Column() {
              Row({ space: 10 }) {
                Text('温度')
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
                Text('最大输出')
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

            this.sectionTitle('Agent 与日志', '工具往返上限与 OpenMinis 一致；日志只记录元数据')
            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Text('每轮最多往返')
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
                Text('轮')
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')

              Text('默认 200。达到上限后本轮结束，已完成的上下文与工具结果会保留，继续发送消息即可接着执行。')
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')

              Row({ space: 10 }) {
                Text('上下文预算')
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
                Text('字符')
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')

              Text('默认 60000。估算请求超过预算时，较早的工具结果会在发送前被截断；界面与已保存的记录不受影响。可用 /compact 让模型生成摘要。')
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(14)
                .width('100%')

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('记录本地事件日志')
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text('记录请求耗时、模型、工具状态与错误；不记录对话内容、API Key 或沙箱 Token。按天轮转，保留 14 天。')
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
                  Text('切到后台继续生成')
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text('生成期间启动长时任务，切换到其他应用时保持连接；系统会显示一条持续通知。不可用时自动退回前台生成。')
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
                  Text('Enter 键发送')
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text('开启后按 Enter 直接发送，适合外接键盘；关闭时 Enter 换行，点箭头发送。')
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

              Row({ space: 8 }) {
                Button(this.showLogs ? '收起日志' : '查看事件日志')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onClick(() => this.loadLogs())
                Button('清空事件日志')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(9)
                  .onClick(() => this.clearLogs())
              }
              .width('100%')

              if (this.showLogs) {
                Column({ space: 4 }) {
                  if (this.logLines.length === 0) {
                    Text('没有日志。需要先打开「记录本地事件日志」，之后产生的事件才会写入。')
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(16)
                  } else {
                    Scroll() {
                      Column({ space: 3 }) {
                        ForEach(this.logLines, (line: string, index: number) => {
                          Text(line)
                            .fontSize(10)
                            .fontColor($r('app.color.text_secondary'))
                            .width('100%')
                            .textAlign(TextAlign.Start)
                        }, (line: string, index: number) => index.toString() + ':' + line)
                      }
                      .width('100%')
                    }
                    .height(220)
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

            this.sectionTitle('工具与沙箱', '工具默认在应用私有工作区执行，也可以转发到电脑上的兼容服务')
            Row({ space: 10 }) {
              Text('允许模型调用工具')
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
                this.sandboxCard('本机', '应用私有目录，离线可用', 'local')
                this.sandboxCard('远程', '转发到 PC / NAS 的工具服务', 'remote')
              }
              .width('100%')

              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('允许写入工作区文件')
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.sandboxMode === 'local'
                    ? '关闭时只读；开启后模型可创建和覆盖文件'
                    : '关闭时远程端只读；开启后允许远程写入')
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
                    Text('写入前逐次确认')
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text('每次 write_file / file_edit 执行前弹窗，可选择允许或拒绝；拒绝会作为错误结果返回给模型。')
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
                    Text('允许读取图片')
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text('开启后模型可调用 read_image 查看工作区图片；仅对支持视觉的模型有效，纯文本模型会报错。')
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
              }

              Column({ space: 6 }) {
                Column({ space: 3 }) {
                  Text('逐工具开关')
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text('关闭的工具不会出现在模型可见的工具列表里；写入、记忆与读图片仍由上面的总开关控制。')
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                ForEach(TOOL_CHOICES, (tool: ToolChoice) => {
                  Row({ space: 8 }) {
                    Text(tool.label + '  ·  ' + tool.name)
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

              if (this.sandboxMode === 'local') {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text('工作区文件')
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                    Text('浏览应用私有工作区；只能查看，不能在这里修改。')
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                      .lineHeight(14)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button('浏览', { type: ButtonType.Normal })
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
                  Text('持久记忆')
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.sandboxMode === 'local'
                    ? '开启后模型可写入本机记忆，并在每轮请求前作为背景注入'
                    : '持久记忆只在本机模式下可用，远程沙箱不转发记忆工具')
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
                  Text('清空每日记忆（保留 GLOBAL.md）')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text('清空')
                    .fontSize(11)
                    .fontColor($r('app.color.danger'))
                    .onClick(() => this.clearMemory())
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(11)

                Row() {
                  Text(this.showMemory ? '收起记忆编辑' : '查看 / 编辑记忆')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.showMemory ? '收起' : '打开')
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
                      placeholder: '这个文件是空的，可以直接输入内容'
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

                    Button('保存记忆文件')
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
                Text('本机工作区位于应用沙箱的 workspace/ 目录。路径必须是相对路径，不能包含 .. 或符号链接。')
                  .fontSize(9)
                  .fontColor($r('app.color.text_tertiary'))
                  .lineHeight(14)
                  .width('100%')
              } else {
                Column() {
                  this.fieldLabel('远程工具服务地址')
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
                  Text('协议：POST {name, arguments} → {ok, content}；接受与原工具相同的工具名。')
                    .fontSize(9)
                    .fontColor($r('app.color.text_tertiary'))
                    .lineHeight(14)
                    .margin({ top: 4 })
                    .width('100%')
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                Column() {
                  this.fieldLabel('远程访问令牌（可选）')
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
            }

            Column() {
              this.fieldLabel('系统提示词（可选）')
              TextArea({ text: this.systemPrompt, placeholder: '例如：你是一名资深鸿蒙应用开发工程师…' })
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

            Text('API Key 保存在本机应用数据中，仅发送到你填写的服务地址。卸载应用会清除全部对话与密钥。')
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
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(12)
            .onClick(() => this.onCancel())
          Button('保存', { type: ButtonType.Normal })
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
