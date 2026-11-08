# Architecture

## 目标

1. **平板优先**：横屏双栏、内容最大宽度、键盘弹出不挤压输入区。
2. **OpenCode Go 正确路由**：每个对话一个稳定 ID，首次请求即发送。
3. **纯 ArkTS / ArkUI**：Stage 模型，API 20，无 WebView、无 Flutter、无兼容层。
4. **工具调用可插拔**：模型循环与工具执行解耦，本机 / 远程 / 未来 QEMU 共用协议。
5. **核心逻辑可测试**：不依赖 ohos 的部分单独成文件，可在 Node 下运行。

## 分层

```text
pages/Index.ets
  状态编排：会话切换、Agent 生命周期、弹层、断点
        │
        ├── components/        ArkUI 展示层（无网络、无持久化）
        │     SidebarView / ChatView / MessageBubble / MarkdownView
        │     SettingsSheet / ModelPicker
        │
        ├── service/           运行时能力
        │     AgentRuntime     一轮用户消息内的模型/工具循环
        │     ChatApi          HTTP + SSE + OpenCode header
        │     LocalToolRuntime 应用工作区工具
        │     RemoteToolRuntime 远程 HTTP 工具服务
        │     SubagentRunner   subagent_task 的独立会话与并行/超时控制
        │     MemoryStore      每日记忆文件读写、注入上下文、检索
        │     LocalStore       preferences 读写与旧数据迁移
        │     AppLogger        事件日志落盘、轮转、清理
        │     BackgroundGuard  生成期间的 dataTransfer 长时任务
        │     ExportService    文档选择器保存 Markdown
        │     Format           时间 / 标题 / token 格式化
        │
        └── core/              纯逻辑（Node 可测）
              Types             parts 消息模型、设置、默认值、搜索索引
              ToolTypes         ToolRuntime / ToolDefinition / ToolResult
              ToolCatalog       内置工具定义
              ToolProtocol      内部 parts ↔ OpenAI tool_calls
              EditPatch         file_edit 的唯一锚点 / replace_all
              ContextBudget     压缩切分、摘要文本、请求前预算裁剪
              Memory            记忆条目、关键词检索、上下文拼装
              EventLog          日志事件、脱敏、JSONL 文件名
              Workspace         相对路径规范化、路径 jail、截断
              OpenCodeRules     域名 / 草稿键 / URL
              SseParser         SSE 与 OpenAI chunk（含 tool_calls / usage）
              Markdown          块级 + 行内解析
              MarkdownExport    会话转 Markdown、文件名清洗
```

依赖方向严格向下：`components` 不直接发请求，`core` 不 import `@kit.*`。
`AgentRuntime` 不关心工具在哪里执行；`ChatApi` 不关心工具循环。

## 消息模型：parts

消息不再是一个 `content` 字符串，而是有序的 `MessagePart[]`：

```ts
interface MessagePart {
  kind: 'text' | 'reasoning' | 'tool_call' | 'image' | 'file';
  text: string;          // text / reasoning
  toolCallId: string;    // tool_call
  toolName: string;
  argumentsText: string; // 模型生成的 JSON 字符串
  resultText: string;    // 工具结果
  status: 'pending' | 'running' | 'done' | 'error';
  isError: boolean;
  mimeType: string;      // image / file，预留
  uri: string;
}
```

这样做的好处：

- 思考过程、正文、工具调用可以分别渲染、折叠、复制；
- 工具结果随会话持久化，重启后仍能看到“调用了什么、返回了什么”；
- 发请求时可以把 assistant 的 tool_call parts 还原成 OpenAI 的
  `assistant.tool_calls` + 后续 `tool` 消息；
- 旧版 `content` / `reasoning` 字段在 `LocalStore` 里迁移为 text / reasoning parts。

流式追加只扩展**尾部同类 part**，否则新建 part。因此模型交替输出
reasoning → content → tool_call 时，顺序不会被后来的增量打乱。

## 会话 ID 的不变量

OpenCode Go 的要求原文是：

> Send a stable session ID in `x-opencode-session` for each conversation so we
> can optimize routing and prompt caching.

落地为四条不变量：

| 不变量 | 实现 |
|---|---|
| 非敏感、唯一 | `util.generateRandomUUID(true)`，不含账号 / Key / 设备信息 |
| 每个对话稳定 | 与 `SessionMeta.id` 同值，和消息一起持久化 |
| 首次请求就有 | `createChat()` 先写入 `store` 再启动 `AgentRuntime` |
| 不会误发给第三方 | `isOpenCodeBase()` 精确匹配或点锚定子域 |
| 拒绝草稿键 | `isPersistedSessionId()` 拒绝空串与 `__` 前缀 |

`ChatApi` 在**构造请求时**读取当前会话 ID，而不是在 provider 创建时快照，
所以换模型、重试、重启都不会改变这个值。

## Agent 循环

一次用户发送会创建一个 `AgentRuntime`。它拥有“这一轮”的循环，直到模型不再
请求工具、达到上限或被用户停止：

```text
start(userText)
  ├─ push user message
  ├─ push assistant placeholder (streaming = true)
  └─ runStep()
        ├─ ChatApi.startChatStream(history, tools)
        │     ├─ onDelta   → append text/reasoning, accumulate tool_calls
        │     ├─ onDone    → 有 tool_calls ?
        │     └─ onError   → 写入错误提示并结束
        ├─ 有 tool_calls:
        │     ├─ Promise.all 并发执行 ToolRuntime.execute(name, arguments)
        │     ├─ 每个结果写回各自的 part（done / error）
        │     ├─ 全部完成后 push 新的 assistant placeholder
        │     └─ runStep()（最多 maxAgentTurns 轮，默认 200）
        └─ 无 tool_calls: finish()
```

`regenerate()` 与 `start()` 共用一个 `beginRun()`：调用方先把消息截断到目标
user 消息，再启动循环，因此「重新生成」和「编辑后重发」不需要第二套状态机。

`maxAgentTurns` 与 OpenMinis 的 `MAX_AGENT_TURNS = 200` 对齐，可在设置中改到
1–1000。达到上限后本轮结束，但历史、工具结果和 part 状态全部保留；末尾写入
「继续发送即可接着执行」的提示，下一轮用户可以无缝续跑。这是有意的 resumable
语义，不是失败。

细节：

- 流式 tool_call 按 `index` 累加到 `Map<number, ToolAccumulator>`；
  `id` / `name` / `arguments` 都可能分片到达；
- 同一轮的多个工具**并行**执行（`Promise.all`），结果仍写回各自的 part，
  所以记录顺序与模型请求顺序一致；下一轮模型请求会等全部工具结束；
- 每个结果截断到 20000 字符，避免把超长输出塞回上下文；
- `onDelta` 只改内存，50ms 合并一次 `onUpdate`，避免每个 token 都重绘整个列表；
- 停止时 `ChatStreamHandle.cancel()` 销毁请求，未完成的工具标记为 error，
  不会留下永远转圈的卡片；
- `finish_reason=length` 会追加“已达到最大输出长度”的提示；
- `ForEach` 的 key 由 `messageKey()` 生成，包含 part 数量、文本长度、工具状态和
  结果长度，确保 ArkUI 在嵌套对象不可观察时仍会重建气泡。

## 工具执行边界

```ts
interface ToolRuntime {
  definitions(): ToolDefinition[];
  execute(name: string, argumentsJson: string): Promise<ToolResult>;
}
```

`AgentRuntime` 只依赖这个接口。当前有两个实现：

### LocalToolRuntime

- 根目录：`context.filesDir/workspace`；
- `normalizeRelativePath()` 拒绝绝对路径与任何 `..` 段；
- 逐段 `lstat` 拒绝符号链接；
- `read_file` 上限 1 MB、拒绝二进制；
- `search_text` 上限 2000 个文件 / 512 KB，跳过 `node_modules`、`.git` 等；
- `write_file` 默认关闭，设置里显式开启后才允许；
- `file_edit` 与 `write_file` 共用写入开关；锚点必须唯一，或用 `replace_all`
  显式允许多处替换，避免模型改错位置；
- `memory_write` / `memory_get` 只在记忆开启时出现，写入 `filesDir/memory`
  而不是工作区；
- `fetch_url` 只接受 `http(s)`，30 秒读超时。

### 写入确认

`AgentRuntime.runTool()` 在执行 `write_file` 或 `file_edit` 前，如果构造时传入了
确认回调，会先 `await` 用户的选择。UI 把工具名与参数（截断到 1500 字符）显示在弹层里，
「允许」继续执行，「拒绝」把该 part 写成 `error` 并附带「用户拒绝了这次工具调用」，
模型下一轮能看到并调整策略。停止生成时 `Index.stopStream()` 先以拒绝结算挂起的
Promise，避免循环卡在未决的确认上。子代理不传回调，因此不会被弹窗阻塞。

### 逐工具开关

`AppSettings.disabledTools` 保存被关闭的工具名。`definitions()` 先按总开关、
写入、记忆、读图片等条件筛选，再用 `isToolDisabled()` 去掉用户关闭的项；`execute()`
也做同样检查，防止模型凭历史上下文直接调用已关闭的工具。远程 runtime 与子代理都
读取同一份列表，子代理通过 `cloneSettings()` 继承，因此开关行为一致。

### RemoteToolRuntime

把同一组工具名转发到你配置的 HTTP 服务：

```text
POST <endpoint>
Authorization: Bearer <token>   (可选)
{ "name": "read_file", "arguments": "{\"path\":\"a.txt\"}" }

→ { "ok": true, "content": "..." }
```

远程端必须自己做根目录隔离、鉴权和超时。应用只负责转发，不能替远程端校验路径。
写入与本地模式共用 `allowWriteTools` 开关：关闭时 `write_file` / `file_edit`
既不暴露给模型，`execute()` 也会直接拒绝。记忆工具**只在本机模式**出现：
记忆属于设备，不应让远程服务读取或写入。

### SubagentRunner

`subagent_task` 只在本机模式暴露（`LocalToolRuntime` 的第四个构造参数为 null 时
不声明该工具）。执行时：

- 克隆父设置，关闭记忆，追加“你是独立子代理”的系统提示；
- 用同一工作区与写权限新建一个 `LocalToolRuntime`，嵌套深度 < 2 时继续传入
  `SubagentRunner`，否则不再暴露子代理；
- 子会话只存在内存中（不进入 `sessions` 列表），标题取 `label`；
- 只把最后一条 assistant 文本作为工具结果返回；
- 静态计数器限制同时 3 个，超出直接返回错误；10 分钟未完成则 `cancel()`。

远程模式与参考服务都不实现子代理，`RemoteToolRuntime` 会过滤并拒绝该工具。

### 未来的 QEMU 后端

HiSH 风格的 QEMU/Alpine 后端只需要实现 `ToolRuntime`，把 `execute()` 映射到
guest 内的命令或文件操作即可。AgentRuntime、ChatApi、UI 和设置页都不用改。

## 持久化

`preferences` 单库，两个 key：

```jsonc
{
  "settings": {
    "preset": "opencode",
    "baseUrl": "https://opencode.ai/zen/go/v1",
    "apiKey": "",            // 正常情况下为空，密钥在 Asset Store
    "modelId": "kimi-k3",
    "systemPrompt": "",
    "temperature": 1.0,
    "maxTokens": 8192,
    "toolsEnabled": true,
    "allowWriteTools": false,
    "sandboxMode": "local",
    "sandboxUrl": "",
    "sandboxToken": "",
    "maxAgentTurns": 200,
    "contextBudgetChars": 60000,
    "loggingEnabled": false,
    "memoryEnabled": false
  },
  "sessions": [
    {
      "meta": { "id": "uuid", "title": "…", "updatedAt": 0, "modelId": "…",
                "messageCount": 2, "pinned": false, "archived": false },
      "messages": [
        {
          "id": "uuid",
          "role": "assistant",
          "parts": [
            { "kind": "text", "text": "…" },
            { "kind": "tool_call", "toolCallId": "call_1", "toolName": "read_file",
              "argumentsText": "{\"path\":\"a.txt\"}", "resultText": "…",
              "status": "done", "isError": false }
          ],
          "createdAt": 0,
          "streaming": false,
          "error": false,
          "promptTokens": 0,
          "completionTokens": 0,
          "totalTokens": 0
        }
      ]
    }
  ]
}
```

密钥（`apiKey` / `sandboxToken`）不写进 preferences：`LocalStore.saveSettings()`
先调用 `SecureStore`（Asset Store Kit，`DEVICE_FIRST_UNLOCKED`）写入，成功后把
JSON 中的字段置空。加载时从 Asset Store 读回；若读到旧版本留下的明文，会自动
迁移并在下一次保存时清除。Asset Store 在无锁屏设备或服务不可用时返回失败，
此时保留 preferences 中的明文作为兼容回退——设置页不会因此报错。

读取时会做字段级归一化：未知 role 丢弃、未知 part kind 归为 text、缺失字段补默认值、
`streaming` 一律归零。上次运行中处于 `pending` / `running` 的工具调用会改成
`error` 并补一条“上次运行中断”，这样下一次请求不会出现没有结果的 tool_call。

写入使用 500ms 防抖，流结束、删除、切换设置时立即落盘。

> 版本化：当前库名带 `_v1`。字段结构再次变更时应迁移到新库名或增加
> `schemaVersion`，不要原地改变消息结构。

## 事件日志

`core/EventLog.ets` 还提供 `formatEventLine()`，把一行 JSONL 转成
`11-08 12:30:05 model_done · kimi-k3 ✓ 4210ms · …` 的查看器文本，损坏行原样返回；
`AppLogger.recent(limit)` 用独立句柄从最新的日文件往前读，不影响正在追加的写入器。

`core/EventLog.ets` 只负责事件形状、脱敏与文件名；`service/AppLogger.ets` 负责
文件 I/O。两者分开后，格式与脱敏可以在 Node 下测试，文件 API 只在真机路径上运行。

```text
AgentRuntime / Settings
        │  LogEvent（元数据）
        ▼
    AppLogger.log()
        ├─ loggingEnabled ? 继续 : 丢弃
        ├─ 每天一个 events-YYYY-MM-DD.jsonl
        ├─ 启动时清理 14 天前的文件
        └─ 单日 8 MB 后停止写入
```

不变量：

- 默认关闭；`loggingEnabled` 与设置一起持久化；
- **绝不写入** prompt、消息正文、工具参数、API Key、沙箱 Token；
- `detail` 只允许短状态串，序列化前经过 `redactSecrets()` 与 300 字符截断；
- 会话 ID 只出现前 8 位（`sessionTag()`）；
- 每次模型请求生成 8 位 `req`（UUID 前缀），写进 `model_start` / `model_done` /
  `model_error` 与同轮工具事件；`turn_cap`、`cancelled` 等没有对应请求的行留空。
  查看器把它显示在事件名后（`req=`），用来判断一次慢请求是模型还是工具造成的；
  它由随机 UUID 派生，不包含任何请求正文；
- 日志 I/O 失败会把 logger 置为 broken 并静默降级，不打断对话。

## 用量与上下文压力

请求体固定带 `stream_options: { include_usage: true }`。兼容服务会在最后一个
chunk 里返回 `usage`，且该 chunk 常常是 `choices: []` —— `SseParser` 在
“空 choices 提前返回”之前先读 `usage`，否则用量会被丢掉。`AgentRuntime.onUsage`
把 `promptTokens` / `completionTokens` / `totalTokens` 写进当前 assistant 消息并
持久化，所以重启后每条回复的 `↑X ↓Y` 仍可见；顶栏取最近一条有 token 的消息显示
上下文大小。上游不返回 usage 时三个字段保持 0，UI 不显示。

## 上下文预算与压缩

两个独立机制，都在 `core/ContextBudget.ets`（纯函数，可 Node 测试）：

1. **发送前裁剪**：`fitHistoryToBudget()` 估算字符数，超过
   `settings.contextBudgetChars` 时克隆一份历史，只截断**较早**（最后 6 条之外）
   且超过 800 字符的工具结果。存储中的消息与 UI 不变，所以工具卡片仍可展开查看
   完整输出；下一轮请求会重新计算。
2. **显式压缩 `/compact`**：`planCompact()` 以用户消息为边界，保留最近 3 个
   用户轮次，其余交给 `ChatApi.summarizeConversation()`（非流式、无工具、
   同会话 ID）。返回摘要后用 `makeSummaryMessage()` 生成一条 `system` 消息，
   与最近轮次组成新历史。失败时原历史不变。

`transcriptForSummary()` 对工具参数/结果分别按 300 / 600 字符裁剪，总长上限
24000 字符，避免摘要请求本身超限。

## 持久记忆

记忆是**本机**能力，默认关闭，开启后：

```text
filesDir/memory/
  GLOBAL.md              # 长期、跨天
  YYYY-MM-DD.md          # 当天追加
```

- `memory_write` 追加到当天的 `YYYY-MM-DD.md`（带时间前缀），不覆盖；
- `MemoryStore.context()` 读取 `GLOBAL.md` + 最近 3 天，交给
  `core/Memory.buildMemoryContext()` 截断到约 4000 字符，拼在系统提示词之后；
- `memory_get` 对所有记忆文件做关键词检索，按命中词数排序，返回带日期的片段；
- 上下文有 3 秒缓存，避免同一轮多次工具调用重复读盘；
- 设置页可「清空每日记忆」，保留 `GLOBAL.md`；
- 设置页也可「查看 / 编辑记忆」：`MemoryStore.editable()` 返回每日文件 + 始终存在的
  `GLOBAL.md`，`saveText()` 只接受 `GLOBAL.md` 或 `YYYY-MM-DD.md`（由
  `core/Memory.isEditableMemoryFile()` 校验），写入后立即让上下文缓存失效；
- 远程工具模式不暴露记忆工具，避免把设备记忆发给远程服务。

## 侧栏分组

`groupSessionMetas()` 是 `core/Types.ets` 里的纯函数：输入已经由
`sortSessionMetas()` 排好序（置顶优先、其余按更新时间倒序），输出
`置顶 / 今天 / 昨天 / 最近 7 天 / 更早` 五组，组内保持原顺序。日期以**本地零点**
为边界，用 `Math.round` 计算相差天数，避免夏令时造成的边界抖动。侧栏用
`ListItemGroup` 渲染组头；搜索时同一函数照常分组，因此搜索结果也带日期上下文。

## 全文搜索

`SessionSearchEntry` 是预计算的小写文本块：标题 + 模型 + 所有 text part +
工具名/参数/结果，单会话截断到 6000 字符。侧栏输入时只做 `indexOf`，不重复
遍历 parts。索引在会话列表变化时重建，**流式输出期间不重建**，避免每个 token
扫描全部历史。

## 导出 Markdown / JSON

`core/MarkdownExport.ets` 是纯函数：把 `StoredSession` 渲染成标题、模型/日期、
按角色分隔的正文，思考以引用块呈现，工具调用与结果放进四反引号围栏（避免与
输出里的三反引号冲突）。文件名由 `safeFileBase()` 清洗 `\/:*?"<>|`，截断到
60 字符，再拼上 `YYYY-MM-DD.md`。

`service/ExportService.ets` 只做设备侧动作：打开
`picker.DocumentViewPicker`，让用户选择保存位置（`newFileNames` 预填文件名，
`fileSuffixChoices` 限定 `.md`），再用 `fileIo` 写入返回的 URI。因此不需要
申请宽泛的存储权限，也不会上传到应用之外，除非用户自己选择云盘目录。

`core/SessionExport.ets` 生成带版本号的 JSON：`{app, version, exportedAt,
exportedOn, session}`，其中 `session` 与 `LocalStore` 的 `StoredSession` 同构，
保留每个 part 的工具参数与结果。导出时会复制消息并把 `streaming` 置为 `false`，
不修改内存里的会话；`exportedAt` 用 ISO-8601 UTC，`exportedOn` 便于人读。
`ExportService.saveSessionJson()` 复用同一套选择器写入流程，`fileSuffixChoices`
为 `.json`。

导入走 `parseSessionExport(text, newId, now)`：只接受 `app` 匹配且 `version` 在
1..当前版本内的文件，逐条重建 message/part（未知字段丢弃、未知角色丢弃、空消息丢弃）。
导入的会话总是换新 ID，标题追加「（导入）」，`updatedAt` 设为当前时间以便排在顶部；
状态仍是 pending/running 的工具调用改为 error，已有部分结果保留。文件读取限制 8 MB，
在 `ExportService.importSessionJson()` 里完成；解析本身不碰文件系统，可单测。

## 工具参数修复与循环检测

每个工具调用执行前，`core/ToolArgs.ets` 的 `repairToolArguments()` 会尝试三种修复：
去掉 Markdown 代码围栏、为被截断的对象补闭合符号、删除对象/数组尾逗号。只有修复结果
能被 `JSON.parse` 接受才采用，并把修复后的 JSON 写回 part，保证重试与重新生成
发送的是同一份有效参数；全部失败时保留原文，让工具照常报解析错误。

`core/ToolLoop.ets` 的 `ToolLoopGuard` 只统计**连续**相同的 `name + arguments`
调用。达到 3 次时，`AgentRuntime` 在该次工具结果前追加一条警告，提示模型换方法
或直接回答。交替调用不同工具不会被误判，守卫随每次用户轮次新建。

## 斜杠命令与思考档位

`Index.handleCommand()` 在发送前拦截以 `/` 开头的输入。`/new` `/clear` `/compact`
`/help` 是本地操作；`/memory` 翻转 `settings.memoryEnabled` 并立即落盘；
`/thinking` 在 `off` 与 `medium` 之间切换 `settings.thinkingLevel`。

`thinkingLevel` 不为 `off` 时，`ChatApi` 在请求体里带 `reasoning_effort`
（`low` / `medium` / `high`）。这是一个通用 OpenAI 兼容字段，不是所有模型都支持：
本项目没有 models.dev 那样的模型能力元数据，所以不会偷偷发送，只有用户显式输入
`/thinking` 才会开启；不支持时再次输入即可关闭。关闭只会省略字段，无法阻止那些
服务端默认就推理的模型继续返回 `reasoning_content`。

## 输入框回车行为

`AppSettings.enterToSend`（默认关闭）由设置页与 `ChatView` 的 `@Prop` 共享。
开启时 `TextArea.enterKeyType` 为 `EnterKeyType.Send`，并挂 `onSubmit`；关闭时用
`EnterKeyType.NEW_LINE`。按 SDK 约定 `NEW_LINE` 不会触发 `onSubmit`，因此同一段
回调不会在换行模式下误发送。`onSubmit` 复用了发送按钮的 `canSend()`
（非空且不在流式输出中），流式期间按 Enter 不会打断或重复发起请求。
输入框下方的提示文字随设置切换，避免用户猜测当前行为。

## 视觉输入

`read_image`（默认关闭，设置里需显式开启）只检查路径、格式与大小，最多 5 MB。
它把**相对路径**写进工具调用 part 的 `uri`/`mimeType`，不把 base64 存进会话，
避免 preferences 膨胀。

真正发请求时，`AgentRuntime` 把 `ToolRuntime.imageDataUrl()` 作为解析器传给
`ChatApi` → `ToolProtocol.toApiMessages()`。这个纯函数把图片变成
`data:<mime>;base64,...`，并在 `role:"tool"` 消息**之后**追加一条合成的
`role:"user"` 多模态消息——Chat Completions 的 schema 禁止在 tool 消息里放
`image_url`。`LocalToolRuntime` 按 `uri + size + mtime` 缓存编码结果，同一张图在
多轮工具调用中只编码一次；`RemoteToolRuntime` 返回空字符串，因此远程模式永远不会
发送本地图片。

纯文本模型会拒绝 `image_url`，所以该工具默认不出现，必须由用户确认当前模型支持
视觉后开启。

## 后台生成

`settings.backgroundEnabled`（默认开启）打开时，`Index.runAgent()` 在开始生成前调用
`BackgroundGuard.begin(context)`，结束时（含停止生成、页面销毁）调用 `end()`。
实现用 `backgroundTaskManager.startBackgroundRunning()` 申请
`BackgroundMode.DATA_TRANSFER` 长时任务，让进程在切换应用后不被挂起，SSE 连接得以
继续。`module.json5` 声明 `ohos.permission.KEEP_BACKGROUND_RUNNING` 与
`backgroundModes: ["dataTransfer"]`。

`BackgroundGuard` 内部用 `wanted` 与递增的 `token` 处理竞态：如果请求还没返回本轮
就已经结束，`begin()` 会在拿到任务后立刻 `end()`，不会留下悬挂的持续通知。任何
失败（未授权、设备不支持、通知被关闭）都被吞掉，聊天继续在前台运行，不影响功能。

## 工作区浏览

`components/WorkspaceSheet.ets` 是设置页里的只读文件浏览器。目录 I/O 在
`service/WorkspaceFiles.ets`：列表用 `fs.lstatSync()` 跳过符号链接，预览只读前
256 KB，按扩展名白名单拒绝二进制文件。路径先经过 `normalizeRelativePath()`，
与工具共享同一套「绝对路径 / `..` 拒绝」规则，因此浏览器能看到的范围不会超过模型。
排序、相对路径计算与大小格式化放在 `core/FileListing.ets`，可在 Node 下单测。

## 首次引导

`components/OnboardingView.ets` 只在 `settings.onboardingDone === false` 且 API Key
为空时出现，因此已有配置的升级用户不会被引导打断。第 2 步只收集 Key，其他选项保持
安全默认；「开始使用」把 Key 交给 `Index.finishOnboarding()`，经 `LocalStore` 保存
（Key 仍优先进入 Asset Store）。「跳过」只置 `onboardingDone`，之后可在设置里补 Key。

## 平板布局

- 根节点 `onAreaChange` 读取宽度，`>= 840vp` 进入双栏；
- 双栏：侧栏固定 300vp，对话区 `layoutWeight(1)`，内部最大宽度 940vp 居中；
- 单栏：`mobileChat` 控制列表 / 对话切换，对话页左上角返回；
- 弹层：设置 90% 高、最大 720vp；模型选择 84% 高、最大 560vp；
- 颜色全部走 `app.color.*`，`resources/dark/element/color.json` 自动跟随系统。

## 错误模型

| 场景 | 行为 |
|---|---|
| 无 API Key / 基址 / 远程沙箱地址 | 打开设置并 toast，不创建消息 |
| 401 / 402 / 403 / 404 / 429 / 5xx | 中文前缀 + 上游 `error.message` |
| 网络失败 | `BusinessError.code` + message |
| SSE 内 `error` 事件 | 立即中断并保留已收内容 |
| 工具失败 | 结果写入 part，`status=error`，模型下一轮可看到并自行纠正 |
| 停止生成 | 保留已收内容；未完成工具标记 error |
| 200 但空内容 | 显示“模型没有返回内容” |
| `finish_reason=length` | 追加“已达到最大输出长度”提示 |
| 达到 `maxAgentTurns` | 本轮结束并提示可继续；历史与工具结果保留 |

## 可测试性

`core/` 十七个文件不 import `@kit.*`，由 `scripts/test-core.mjs` 复制为 `.mts` 后
用 Node 类型剥离执行（复制时把无扩展名的相对 import 改成 `.mts`）。
UI、HTTP、文件与网络工具需要 DevEco Studio 编译与真机验证。
