# Porting notes

## 参考对象

| 项目 | 技术栈 | 与本项目的关系 |
|---|---|---|
| [OpenMinis](https://github.com/OpenMinis/OpenMinis) | Kotlin / Compose（Android）、SwiftUI（iOS） | 产品形态、OpenCode Go 会话头实现细节 |
| [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) | Flutter / Dart | 平板横屏排版、会话切换、流式交互 |

本项目是**行为参考后的 HarmonyOS 原生重写**，没有复制上述仓库的源码。
除 Linux 沙箱外的逐项对齐状态与优先级见
[docs/OPENMINIS-PARITY.md](OPENMINIS-PARITY.md)。

## 对照表

| OpenMinis / dsh-Go | Minis Harmony | 说明 |
|---|---|---|
| Android `OpenCodeSessionHeader.headersFor()` | `core/OpenCodeRules.ets` + `service/ChatApi.ets` | 域名门控、草稿键拒绝、逐请求注入 |
| iOS `OpenCodeChannel.attach()` | 同上 | 本项目在会话创建时就生成 UUID，不存在 draft→real 的补发问题 |
| Kotlin `ChatViewModel.ensureSession()` | `pages/Index.ets#createChat()` | 先持久化会话再发首个请求 |
| Compose / Flutter 平板断点 | `onAreaChange` + 840vp | 双栏 / 单栏切换 |
| SSE 流式 provider | `core/SseParser.ets` | 增量、CRLF、多 data 行、错误体 |
| OpenAI tool calling | `core/ToolProtocol.ets` + `service/AgentRuntime.ets` | 流式 tool_calls、结果回填、重复 id 去重、空名跳过、默认 200 轮（与 OpenMinis 对齐，可配置） |
| Android 日志 / 埋点 | `core/EventLog.ets` + `service/AppLogger.ets` | 默认关闭、脱敏、按天轮转；不上报远端 |
| Kotlin `file_edit` 工具 | `core/EditPatch.ets` + `LocalToolRuntime` | 唯一锚点、`replace_all`；纯逻辑可测 |
| iOS / Android token 用量 | `SseParser.usage` + `ChatMessage.*Tokens` | `stream_options.include_usage`，落库并在气泡显示 |
| 重新生成 / 编辑重发 | `AgentRuntime.regenerate()` | 截断到目标 user 消息后复用同一循环 |
| OpenMinis 持久记忆 | `core/Memory.ets` + `service/MemoryStore.ets` | `GLOBAL.md` + 每日文件、关键词检索、系统提示注入 |
| 会话全文搜索 | `core/Types.ets#searchableText` | 预计算小写文本块，侧栏 `indexOf` |
| OpenMinis `/compact` | `core/ContextBudget.ets` + `ChatApi.summarizeConversation()` | 按用户轮次切分，模型摘要替换旧轮次 |
| 工具结果预算裁剪 | `core/ContextBudget.ets#fitHistoryToBudget` | 只改请求副本，界面与存储保持完整 |
| OpenMinis `subagent_task` | `service/SubagentRunner.ets` | 独立内存会话、3 并行、10 分钟超时、2 层嵌套；无 steer/resume |
| Keychain / EncryptedPrefs | `service/SecureStore.ets` | Asset Store Kit，失败时回退 preferences 明文 |
| 会话导出 Markdown | `core/MarkdownExport.ets` + `service/ExportService.ets` | 纯函数渲染，系统文档选择器选位置写入；不做 zip / 分享卡 |
| 请求检查器 | `LogEvent.req` | 每次模型请求 8 位随机 id，关联同轮工具事件；不含正文 |
| 应用锁 | `service/AppLock.ets` | 启动时系统 PIN/人脸/指纹；无凭据 fail-open；仅启动锁 |
| 首次引导 | `OnboardingView` + `onboardingDone` | 三步、可跳过；只收集 API Key；已有配置不触发 |
| 工作区浏览 | `WorkspaceFiles` + `WorkspaceSheet` | 只读列表/预览；复用工作区路径规则；跳过符号链接 |
| 写入前确认 | `AgentRuntime.runTool()` + Index 弹层 | 仅写工具；拒绝作为工具错误返回；停止时结算为拒绝 |
| 逐工具开关 | `AppSettings.disabledTools` + `isToolDisabled()` | 设置页开关；definitions/execute 双重检查；子代理继承 |
| 会话导出 / 导入 JSON | `core/SessionExport.ets` + `service/ExportService.ets` | 版本化信封 `{app,version,exportedAt,session}`；导入时校验、重建 parts、分配新 ID，未完成工具标记为 error；多选导出为 `sessions` bundle，同一导入器兼容两种形状 |
| Android 前台服务 / iOS background task | `service/BackgroundGuard.ets` | `dataTransfer` 长时任务，仅生成期间持有；失败静默回退 |
| OpenMinis 生成通知 | `service/Notify.ets` + `Index` 生命周期 | 后台生成常驻通知、完成替换、前台清除；点按经 `wantAgent` 回应用；未授权时静默 |
| 消息内链接 | `core/Markdown.ets#isOpenableUrl` + `MarkdownView` | 裸 URL 与 Markdown 链接可点；协议白名单；经系统浏览器打开 |
| Markdown 表格 | `MdBlockKind.Table` + `MarkdownView.tableBlock` | GFM 表头/分隔行；等宽列；无 LaTeX 与代码高亮 |
| OpenMinis 每会话参数 | `core/SessionParams.ets` + 会话操作弹窗 | 模型/思考/追加提示词覆盖；空串继承全局；撤销即恢复全局 |
| OpenMinis 主题/字号 | `AppSettings.accentColor` / `fontScale` + `AppStorage` | 六种强调色、四档字号；主界面即时生效；设置页不缩放 |
| OpenMinis Soul | `core/Soul.ets` + `ChatApi.buildMessages()` | 五个内置人格作为系统提示前缀；不支持载入 `SOUL.md` |
| OpenMinis Skills | `core/SkillDoc.ets` + `service/SkillStore.ets` | 单个 SKILL.md 导入；目录注入 + `read_skill` 惰性正文；已启用技能自动成为 `/技能id` 命令；全局启用 |
| OpenMinis 常亮 | `service/ScreenWake.ets` | 仅生成期间保持屏幕常亮；自动聚焦未做 |
| OpenMinis 剪贴板 | `LocalToolRuntime.clipboardRead/Write()` | `pasteboard` 纯文本读写；默认关闭、24k/100k 字符上限；仅本机模式 |
| OpenMinis `read_image`（原生视觉分支） | `core/ToolProtocol.ets` + `LocalToolRuntime.imageDataUrl()` | tool 消息后追加合成 user `image_url` 消息；无 Vision Group 文本回退 |
| OpenMinis 图片附件 / 预览 | `service/AttachmentStore.ets` + `MessageBubble` | 相册多选复制到私有目录；消息 part 存 `attachment:` 路径；多模态 `image_url`；气泡缩略图与全屏查看 |
| OpenMinis `/memory` `/thinking` | `Index.handleCommand()` | 记忆为全局开关；思考映射到 `reasoning_effort`，无模型元数据 |
| Android `ToolJsonRepair.kt` | `core/ToolArgs.ets` | 覆盖围栏/截断/尾逗号；未做类型强转与字段名模糊匹配 |
| OpenMinis 工具循环保护 | `core/ToolLoop.ets` + `AgentRuntime` | 连续相同调用 3 次追加警告 |
| 本地文件 / shell 工具 | `service/LocalToolRuntime.ets`、`RemoteToolRuntime.ets` | 应用工作区或远程 HTTP 服务，共用 `ToolRuntime` |
| OpenMinis MCP 工具 | `core/McpProtocol.ets` + `service/McpClient.ets` + `McpRuntime` | Streamable HTTP JSON-RPC；自动发现与调用；工具名前缀；无 stdio / OAuth |
| OpenCode Go 模型发现 | `ChatApi.fetchModelIds()` | 规范基址 `/zen/go/v1/models`；旧基址自动换算 |
| OpenMinis 模型能力目录 | `core/ModelCaps.ets` | 家族前缀估计上下文/最大输出/视觉/推理；顶栏占比与模型列表标签；离线，不做 models.dev 拉取 |
| OpenMinis 逐模型参数 | `core/ModelOverride.ets` + `ChatApi` | 按模型 ID 覆盖 temperature/top_p/max_tokens、追加请求头与 extra_body；空值继承全局 |
| Android `preferences` / DB | `service/LocalStore.ets` | 单库 JSON；后续可换 RDB |

## 这一阶段做了什么

原计划第一阶段只做 Chat，后来把「原生工具调用 + 可插拔沙箱」一起落了地，
因为这两件事决定了后续所有能力（文件、搜索、命令、浏览器）的宿主形态：

1. 消息从纯文本升级为 parts，思考、正文、工具调用分开存储与渲染；
2. 实现 OpenAI 流式 `tool_calls` 解析与 Agent 循环；
3. 本机工作区工具，带路径 jail、只读默认、写入开关；
4. 远程工具转发协议，让平板可以把真实文件系统留在 PC / NAS；
5. 设置页增加工具开关、沙箱模式、远程地址与 Token；
6. Agent 轮次上限改为可配置（默认 200，对齐 OpenMinis）并支持续跑；
7. 增加可关闭的本地事件日志：耗时、轮次、工具状态、错误，脱敏且不记录正文；
8. 补齐日常手感：`file_edit`、重新生成、编辑后重发、全文搜索、token 用量与
   上下文大小、斜杠命令（`/new` `/clear` `/help`）；
9. 工具调用改为同一轮并行执行，减少多工具任务的等待；
10. 持久记忆：`memory_write` / `memory_get`、每日文件 + `GLOBAL.md`、
    系统提示注入、设置开关与清空——默认关闭，仅本机模式。

这样即使平板端暂时没有本地 shell，产品也已经具备“给模型工具”的完整链路，
后续换后端不需要重写循环和 UI。

## 沙箱路线：为什么先做本机工作区，而不是板载 Linux

### 已确认的限制

- 普通 HarmonyOS 应用**不能 exec 子进程**。SELinux 策略对 `normal_hap` 有
  `neverallow ... execute_no_trans`，没有 `posix_spawn` / `fork+exec` 可用；
- 原生子进程 API 只能 `dlopen` 一个 `.so`，不提供主机 pty；
- `chroot`、`mount`、namespaces 对普通应用不可用；
- PRoot / iSH 依赖的“拦截系统调用 + 改路径”路线，最终仍要 exec 目标程序，
  因此在普通 HAP 里不可行；
- QEMU 用户态 / vroot 方案在 HarmonyOS PC 上有先例，但平板端没有公开验证。

### 可行的方向

HiSH 一类项目证明 **QEMU 全系统模拟**可以在 HarmonyOS 平板上运行 Alpine：

- 应用内置 `libqemu-system-aarch64.so` 与 Alpine qcow2；
- 用 TCI 解释器，不要求可写代码内存，速度较慢但可用；
- 若启用 JIT，需要 `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`
  （system_basic + AGC ACL），普通开发者签名通常拿不到；
- QEMU 是 GPLv2，分发时要遵守许可证。

因此当前把沙箱抽象成 `ToolRuntime`：

```text
LocalToolRuntime   → 应用私有工作区（已实现）
RemoteToolRuntime  → PC / NAS / VPS 上的 HTTP 工具服务（已实现）
QemuToolRuntime    → guest 内命令与文件操作（预留）
```

### 远程模式的定位

远程模式不是“临时凑合”，而是与本地模式平级的后端：

- 平板离线时用本机工作区；
- 需要真实 shell、编译、Git、浏览器时切远程；
- 两者共用工具定义，模型提示词不变；
- 远程端可以用任意语言实现，只要满足 `{name, arguments} → {ok, content}`；
- `scripts/sandbox-server.mjs` 是 Node 22 参考实现，带路径 jail、Token 与超时，
  可直接在 PC / NAS 上运行。

## 如何扩展

### 增加一个 OpenAI 兼容服务

不需要改代码：

1. 设置 → 服务商选「自定义」；
2. 填基址（到 `/v1` 为止）；
3. 填 Key 与模型 ID；
4. 保存。

如果服务需要额外的静态请求头（例如某些中转要求 `X-Title`），在
`ChatApi.startChatStream()` 的 `headers` 里增加即可；注意不要在该层硬编码任何密钥。

### 增加一个工具

1. 在 `core/ToolCatalog.ets` 增加 JSON Schema 定义；
2. 在 `LocalToolRuntime.execute()` 增加分支（或让远程端支持同名工具）；
3. 若工具有副作用，默认关闭或增加设置开关；
4. 在 `scripts/test-core.mjs` 增加协议/路径相关的纯逻辑测试。

工具结果会自动进入下一轮模型上下文，无需改 AgentRuntime。

### 增加会话头规则

如果未来出现第二个需要稳定会话头的上游：

1. 在 `OpenCodeRules.ets` 增加纯函数 `isXxxBase()`；
2. 在 `shouldAttachSessionHeader()` 中组合；
3. 在 `ChatApi` 里按上游写入对应 header 名；
4. 在 `scripts/test-core.mjs` 增加正例与负例（尤其是“相似域名”负例）。

### 后续建议顺序

1. **上下文压缩与子代理**：`/compact`、达到窗口上限自动裁剪、`subagent_task`；
2. **QEMU 后端验证**：先在平板上跑通 TCI + Alpine，再把 `execute()` 接进来；
3. **密钥安全**：API Key / 远程 Token 迁移到 `@kit.AssetStoreKit`；
4. **数据层**：会话量上来后从 preferences 换 `relationalStore`，支持全文搜索；
5. **附件**：图片选择 → base64 / 文件上传，按模型能力开关；
6. **长时任务**：`backgroundTaskManager` + 通知，支持切后台继续生成；
7. **浏览器 / MCP / Skills**：在 `ToolRuntime` 之上增加新的工具族；
8. **多端同步**：WebDAV / 自建同步，保留端到端加密选项。

### 暂不建议做的

- 在未做权限模型前开放任意 shell；
- 在客户端内置第三方 API Key；
- 用 WebView 承载主对话界面；
- 在没有真机验证前扩大设备类型到车机 / 智慧屏；
- 把无鉴权的远程工具服务暴露到公网。

## 版本与兼容

- 工程声明 `compatibleSdkVersion: "6.0.0(20)"`，即 HarmonyOS 6.0.0 / API 20；
- 用到的 Kit：`@kit.AbilityKit`、`@kit.ArkUI`、`@kit.ArkData`、`@kit.ArkTS`、
  `@kit.NetworkKit`、`@kit.BasicServicesKit`、`@kit.CoreFileKit`、
  `@kit.PerformanceAnalysisKit`；
- 这些 Kit 导入形式在 API 12+ 可用，API 20 保持兼容；
- 若你的 DevEco 版本号不同，以 SDK Manager 显示的实际版本为准调整
  `build-profile.json5` 与 `hvigor/hvigor-config.json5` 的 `modelVersion`。

## 已知风险

1. **编译验证范围**：已用公共 OpenHarmony 6.0.0.49 SDK（API 20）跑通
   `assembleHap`，但产物未签名；华为 HarmonyOS SDK 与 AGC 签名仍需 DevEco Studio。
   真机安装前请在 DevEco 中完成自动签名配置。
2. **`@kit.CoreFileKit` 文件 API**：`statSync`、`lstatSync`、`mkdirSync(path, true)`、
   `writeSync` 按 API 20 声明使用，尚未在真机验证权限与行为。
3. **`requestInStream` 回调时序**：不同 API 版本对 `dataEnd` 与完成回调的顺序可能
   有差异；当前实现把最终判定放在完成回调，`dataEnd` 只做解码 flush。
4. **工具调用兼容性**：不同 OpenAI 兼容模型对 `tool_choice` / 流式 tool_calls 的
   支持不一致；若模型不支持工具，设置里可关闭。
5. **超长代码块排版**：当前代码块自动换行，未做横向滚动与语法高亮。
6. **模型列表时效性**：内置列表是 2026-11 的常用集合，权威来源是「获取」按钮拉取的
   实时列表。
