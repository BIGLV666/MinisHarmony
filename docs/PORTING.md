# Porting notes

## 参考对象

| 项目 | 技术栈 | 与本项目的关系 |
|---|---|---|
| [OpenMinis](https://github.com/OpenMinis/OpenMinis) | Kotlin / Compose（Android）、SwiftUI（iOS） | 产品形态、OpenCode Go 会话头实现细节 |
| [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) | Flutter / Dart | 平板横屏排版、会话切换、流式交互 |

本项目是**行为参考后的 HarmonyOS 原生重写**，没有复制上述仓库的源码。

## 对照表

| OpenMinis / dsh-Go | Minis Harmony | 说明 |
|---|---|---|
| Android `OpenCodeSessionHeader.headersFor()` | `core/OpenCodeRules.ets` + `service/ChatApi.ets` | 域名门控、草稿键拒绝、逐请求注入 |
| iOS `OpenCodeChannel.attach()` | 同上 | 本项目在会话创建时就生成 UUID，不存在 draft→real 的补发问题 |
| Kotlin `ChatViewModel.ensureSession()` | `pages/Index.ets#createChat()` | 先持久化会话再发首个请求 |
| Compose / Flutter 平板断点 | `onAreaChange` + 840vp | 双栏 / 单栏切换 |
| SSE 流式 provider | `core/SseParser.ets` | 增量、CRLF、多 data 行、错误体 |
| OpenCode Go 模型发现 | `ChatApi.fetchModelIds()` | 特殊路径 `/inference/go/v1/models` |
| Android `preferences` / DB | `service/LocalStore.ets` | 单库 JSON；后续可换 RDB |

## 第一阶段的取舍

### 为什么只做 Chat

OpenMinis / dsh-Go 的真正重量在「给模型一台电脑」：Linux 沙箱、文件系统、浏览器、
Skills、MCP、工具调用循环、后台任务、设备能力。把这些一次性搬到 HarmonyOS 需要：

- 原生沙箱能力（HarmonyOS 无 proot/ish 等价物，需要自建命令执行与文件抽象）；
- 长时任务与后台调度；
- 工具调用协议与权限模型；
- 附件、图片、语音的媒体管线。

这些每一项都足以独立成阶段。先把「订阅可用 + 流式体验 + 平板排版」做扎实，
后续能力才有稳定的宿主。

### 为什么不用 WebView / Flutter

- 纯血鸿蒙 6.0 的目标就是原生体验；WebView 会牺牲输入、滚动、字体与深色模式；
- Flutter 的 HarmonyOS 适配链路会增加运行时与包体，且与 ArkUI 的系统能力集成较弱；
- 当前范围（文本流 + 列表 + 设置）用 ArkUI 足够，且能直接使用系统资源与断点能力。

## 如何扩展

### 增加一个 OpenAI 兼容服务

不需要改代码：

1. 设置 → 服务商选「自定义」；
2. 填基址（到 `/v1` 为止）；
3. 填 Key 与模型 ID；
4. 保存。

如果服务需要额外的静态请求头（例如某些中转要求 `X-Title`），在
`ChatApi.startChatStream()` 的 `headers` 里增加即可；注意不要在该层硬编码任何密钥。

### 增加会话头规则

如果未来出现第二个需要稳定会话头的上游：

1. 在 `OpenCodeRules.ets` 增加纯函数 `isXxxBase()`；
2. 在 `shouldAttachSessionHeader()` 中组合；
3. 在 `ChatApi` 里按上游写入对应 header 名；
4. 在 `scripts/test-core.mjs` 增加正例与负例（尤其是“相似域名”负例）。

### 第二阶段建议顺序

1. **密钥安全**：API Key 迁移到 `@kit.AssetStoreKit`，preferences 只存引用；
2. **数据层**：会话量上来后从 preferences 换 `relationalStore`，支持全文搜索；
3. **附件**：图片选择 → base64 / 文件上传，按模型 `modalities` 能力开关；
4. **工具调用**：解析 `tool_calls` → 本地工具注册表 → 结果回填 → 循环；
5. **长时任务**：`backgroundTaskManager` + 通知，支持切后台继续生成；
6. **沙箱**：先做受控的文件工作区（应用沙箱目录 + 命令白名单），再评估完整 shell；
7. **多端同步**：WebDAV / 自建同步，保留端到端加密选项。

### 暂不建议做的

- 在未做权限模型前开放任意 shell；
- 在客户端内置第三方 API Key；
- 用 WebView 承载主对话界面；
- 在没有真机验证前扩大设备类型到车机 / 智慧屏。

## 版本与兼容

- 工程声明 `compatibleSdkVersion: "6.0.0(20)"`，即 HarmonyOS 6.0.0 / API 20；
- 用到的 Kit：`@kit.AbilityKit`、`@kit.ArkUI`、`@kit.ArkData`、`@kit.ArkTS`、
  `@kit.NetworkKit`、`@kit.BasicServicesKit`、`@kit.PerformanceAnalysisKit`；
- 这些 Kit 导入形式在 API 12+ 可用，API 20 保持兼容；
- 若你的 DevEco 版本号不同，以 SDK Manager 显示的实际版本为准调整
  `build-profile.json5` 与 `hvigor/hvigor-config.json5` 的 `modelVersion`。

## 已知风险

1. **未在本机编译**：当前环境没有 DevEco Studio / HarmonyOS SDK，代码按 API 20
   文档编写，首次 Sync 可能出现少量 API 签名差异，需要按 IDE 提示微调。
2. **`requestInStream` 回调时序**：不同 API 版本对 `dataEnd` 与完成回调的顺序可能
   有差异；当前实现把最终判定放在完成回调，`dataEnd` 只做解码 flush。
3. **超长代码块排版**：当前代码块自动换行，未做横向滚动与语法高亮。
4. **模型列表时效性**：内置列表是 2026-11 的常用集合，权威来源是「获取」按钮拉取的
   实时列表。
