import {
  AppSettings,
  OPENCODE_DEFAULT_MODEL,
  OPENCODE_GO_BASE,
  ProviderPreset,
  SandboxMode,
  cloneSettings,
  defaultSettings
} from '../core/Types';
import { isOpenCodeBase, normalizeBaseUrl } from '../core/OpenCodeRules';
import { fetchModelIds, ModelsResult } from '../service/ChatApi';

@Component
export struct SettingsSheet {
  @Prop settings: AppSettings = defaultSettings();
  onCancel: () => void = () => {
  };
  onSave: (settings: AppSettings) => void = (settings: AppSettings) => {
  };
  onToast: (message: string) => void = (message: string) => {
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
  @State sandboxMode: SandboxMode = 'local';
  @State sandboxUrl: string = '';
  @State sandboxToken: string = '';

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
    this.sandboxMode = copy.sandboxMode;
    this.sandboxUrl = copy.sandboxUrl;
    this.sandboxToken = copy.sandboxToken;
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
      sandboxToken: this.sandboxToken.trim()
    };
    return next;
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
