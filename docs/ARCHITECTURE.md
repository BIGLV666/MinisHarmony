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

`ToolProtocol.toApiMessages()` 在发送前再做一层配对加固：同一段历史里重复的
`toolCallId`（导入文件、旧版本数据或中断后重试都可能产生）会让 API 把结果配给
错误的调用，因此第一次出现保持原 id，后续追加 `_2`、`_3` 后缀，并让对应的
`role:"tool"` 消息使用同一后缀；`toolName` 为空白的调用直接跳过，不生成
`assistant.tool_calls` 与结果。尚未完成的调用仍回填“已中断”的合成结果，保证
每个 `tool_call` 都有且只有一个结果。

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

估算窗口来自 `core/ModelCaps.ets`：按模型 id 前缀（`gpt-6`、`claude`、`gemini`、
`kimi-k3` 等）给出上下文窗口、最大输出、是否支持视觉与推理，未知模型回退
128k / 8192。顶栏因此显示 `上下文 12.3k / 128k (10%)`，模型列表显示
`400k · 视觉 · 推理`。该表是**离线估计**，不做强校验：`max_tokens` 只在用户值
超过估计上限时夹取，不因表里没有视觉能力就禁用 `read_image`，避免误判自定义模型。

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

## 自动会话标题

会话标题先由 `titleFrom()` 取首条用户消息第一行（26 字内）作为即时占位。每轮
生成结束后，`Index.maybeAutoTitle()` 检查标题是否仍是这个派生值（或「新对话」），
是则异步请求一次模型标题；`titleJobs` 记录已请求的会话，避免每轮重复。

- 提示词由 `ChatApi.titleInstruction()` 给出，要求 ≤20 字、只输出标题本身；
- 请求复用非流式摘要通道 `requestModelText()`：按 `preset` 走 OpenAI 兼容 /
  Anthropic / Gemini / Codex，`max_tokens` 200，OpenCode 会话头保持不变；
- `core/SessionTitle.ets` 负责纯逻辑：`cleanTitle()` 去引号、「标题：」/`Title:`
  前缀与句末标点，超过 20 字截断加省略号；`titleTranscript()` 只取首轮用户+
  助手文本（各 600 字），超过 8 条消息再补最近一条助手消息（300 字）；失败轮
  （`error`）不算回答；
- 成功写 `SessionMeta.title` 并持久化，失败**静默**保留派生标题，离线不受影响；
- 会话操作菜单可「重新生成标题」，手动请求会显示进度、失败原因与成功提示；
  编辑首条用户消息会清掉 `titleJobs` 记录，下一轮重新生成。

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

### 自定义文件夹

用户创建文件夹后（`AppSettings.sessionFolders`），无搜索词时的侧栏改用
`groupByFolder()`：按文件夹顺序输出，空文件夹也保留，成员按原有排序（置顶优先、
更新时间倒序），不属于任何现存文件夹的会话进入末尾的「未分组」。折叠状态由
`SessionFolder.collapsed` 控制，只影响渲染，不改变数据。搜索时仍用日期分组，
这样结果不会散落在多个文件夹里。

文件夹是纯配置：`SessionMeta.folderId` 只存 id，`core/SessionFolder.ets` 的
`addFolder` / `renameFolder` / `removeFolder` / `setFolderCollapsed` 全部返回新
数组，`Index` 通过 `cloneSettings()` 生成新的 `AppSettings` 再整体赋值，保证
`@State` 与侧栏 `@Prop` 都会刷新。删除文件夹只清空成员上的 `folderId`，会话本身
不动。新建/移动都不需要模型参与，因此不进事件日志。

## 全文搜索

`SessionSearchEntry` 是预计算的小写文本块：标题 + 模型 + 所有 text part +
工具名/参数/结果，单会话截断到 6000 字符。侧栏输入时只做 `indexOf`，不重复
遍历 parts。索引在会话列表变化时重建，**流式输出期间不重建**，避免每个 token
扫描全部历史。

## 消息渲染与链接

`core/Markdown.ets` 把回复拆成块（段落、标题、列表、引用、代码、分割线、表格），行内再拆成
`bold / italic / code / link` 片段。表格要求「含 `|` 的表头行 + 只含 `|-: ` 的分隔行」；
对齐符号被接受但不参与布局，短行自动补齐到表头列数，渲染为等宽列的只读表格。除 `[文本](url)` 外，`parseInline()` 也识别裸
`http://` / `https://`，并在遇到空白、中文标点或右括号处截断；句末的 `.,;:!?` 会留在
正文里，不会进入链接目标。`MarkdownView` 为链接片段加下划线并绑定 `Span.onClick`，
点击后通过 `Want`（`ohos.want.action.viewData` + `entity.system.browsable`）交给系统
浏览器。`isOpenableUrl()` 只放行 http / https / mailto / tel，`javascript:`、`file:`
等协议直接拒绝并提示。

## 内置浏览器

聊天里的 http(s) 链接由 `components/BrowserPage.ets` 全屏打开；它是一页一实例的
前台浏览器，自动化用的 4 标签池在 `HiddenBrowser` 里，两者互不复用 controller。
工具栏按「后退 / 前进 / 刷新或停止 / 历史 / 下载 / 设置 / 地址栏 / 系统打开 / 关闭」
排列，地址栏接受裸域名并补全 `https://`。

历史与下载记录只存本机 preferences（`service/BrowserStore.ets`）：历史是
`{url, title, at}`，同 URL 只保留最近一次并在 `onPageEnd` 写入，上限 200；
`file://`、`data:` 等非 http(s) 页面不记录。下载通过 controller 的
`setDownloadDelegate` 启动，文件名按 `\/:*?"<>|` 清洗后写入
`filesDir/browser-downloads`，同名追加时间戳；完成/失败后记录
`{name, path, at, bytes, ok}`，上限 100。面板里的下载项用 `file://` 在当前
Web 中打开，因此 `fileAccess` 必须开启。`onDownloadUpdated` 用
`getPercentComplete()` 维护进行中列表，下载面板顶部显示文件名与进度条，工具栏
⬇ 按钮附带进行中数量；完成或失败即从列表移除并写入记录。

设置面板保存 UA 预设（默认/移动/桌面/自定义）与宽视口开关，UA 在
`onControllerAttached` 应用。ArkWeb 没有「列出全部 Cookie」的接口，因此
`core/BrowserHistory.cookieOrigins()` 从当前页与历史里提取去重后的 origin（最多
20 个），逐个 `fetchCookieSync(origin + '/')` 计数并在设置里列出，可单站清除或
全部清除；不展示 Cookie 值与过期时间。视口只提供桌面宽视口开关，尚未提供数值
宽高（ArkWeb 未暴露对应设置）。

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
在 `ExportService.importSessionsJson()` 里完成；解析本身不碰文件系统，可单测。

多选导出复用同一套消息清洗，把信封里的 `session` 换成 `sessions` 数组
（`sessionBundleJson()`，文件名 `minis-sessions-YYYY-MM-DD.json`）。侧栏的「选择会话」
模式在行首显示复选框，选中后一次写入一个文件；导入端统一走
`parseSessionsExport(text, newId, now)`，它同时接受单会话信封与 bundle，为每个会话
调用 `newId()` 分配新 ID，无法解析的条目跳过——只有全部失败时才报错，避免一个坏
会话毁掉整包。bundle 不打包附件（当前会话还没有附件），因此没有 zip。

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
`/thinking` 用 `cycleThinkingLevel()` 在 `off → low → medium → high → off` 之间循环，
设置页也有同样的四档按钮，两者写同一份 `settings.thinkingLevel`。

`thinkingLevel` 不为 `off` 时，`ChatApi` 在请求体里带 `reasoning_effort`
（`low` / `medium` / `high`）。这是一个通用 OpenAI 兼容字段，不是所有模型都支持：
本项目没有 models.dev 那样的模型能力元数据，所以不会偷偷发送，只有用户显式输入
`/thinking` 才会开启；不支持时再次输入即可关闭。关闭只会省略字段，无法阻止那些
服务端默认就推理的模型继续返回 `reasoning_content`。

## 输入框回车行为

`AppSettings.enterToSend`（默认关闭）由设置页与 `ChatView` 的 `@Prop` 共享。
开启时 `TextArea.enterKeyType` 为 `EnterKeyType.Send`，并挂 `onSubmit`；关闭时用
`EnterKeyType.NEW_LINE`。按 SDK 约定 `NEW_LINE` 不会触发 `onSubmit`，因此同一段
回调不会在换行模式下误发送。`onSubmit` 与发送按钮走同一个 `sendMessage()`：
生成中不会打断或重复发起请求，而是把内容放进排队队列（见下节）。
输入框下方的提示文字随设置切换，避免用户猜测当前行为。

## @ 文件提及

输入框支持 `@` 提及工作区文件：

- `core/Mention.ets` 的 `activeMention()` 只看草稿**末尾**的 `@query`——`@` 必须
  位于开头或空白之后，query 不含空白（所以 `a@b.com` 和已插入的 `@path ` 都不会
  再次弹出菜单）；ArkUI 的 `TextArea` 不暴露光标，光标在中间时暂不触发；
- `ChatView` 首次打开菜单时调用 `listWorkspaceFiles()` 取一份扁平列表（递归 4 层，
  跳过隐藏目录与 `node_modules` / `oh_modules` / `.hvigor` / `build` /
  `.minis-browser`，上限 300 个文件），之后在内存里过滤；
- `filterMentionFiles()` 跳过目录，按相对路径不区分大小写匹配，最多显示 5 条；
- 点按或回车后 `replaceMention()` 把尾部 token 换成 `@path `，发送时模型从消息里
  看到路径，可用文件工具读取；工具栏的 `@` 按钮插入触发符；
- 草稿被清空或 token 含空白时菜单自动关闭，不需要额外的取消逻辑。

## 长粘贴转工作区附件

ArkUI 的 `TextArea` 没有粘贴事件，只在 `onChange` 给出完整新值。`core/Paste.ets`
的 `hugePasteInsertion(before, after)` 先比较长度差是否超过 `PASTE_FILE_THRESHOLD`
（15000），再用公共前缀/公共后缀夹出本次编辑的片段。这样粘贴落在开头、中间、末尾
甚至替换选区都能还原，而不必依赖光标位置。范围较小、但整段草稿已经超过 15000 字的
编辑不会被误判，因为判断依据是单次增量。

`ChatView` 检测到长片段后调用 `onHugePaste`。宿主 `Index.attachHugePaste()` 把正文
写入 `<workspace>/pasted/Pasted_<本地时间>_<毫秒>.txt`，再追加一个
`minis://workspace/pasted/...` 的 `text/plain` 附件；写入失败时返回 false，输入框
保留原文。成功时组件先让 `TextArea` 接受一次新值，再在下一个 tick 把草稿恢复为
粘贴前的内容——直接赋回旧值可能与框架的旧渲染比较相等而不刷新。

发送（以及生成中排队注入的 `queuedParts`）把该附件转换成一段
`[粘贴文本] pasted/...（长文本已保存为工作区文件，可用 read_file 读取完整内容）`
文本加一个文件 part。气泡只渲染文本标记和 📄 附件卡片，正文不进入界面；模型按需
读取文件。工具关闭或使用远程沙箱时不做转换：前者模型没有读取工具，后者看不到本机
工作区，保留原文在输入框反而不会丢内容。

## 自动归入分组

自动分组复用「会话结束后生成标题」这一次模型请求，不额外发请求。`Index.requestTitle()`
在调用 `generateSessionTitle()` 前用 `offeredFolderNames()` 取候选：开关
`autoGroupingEnabled` 打开、会话还没有 `folderId` 时才收集 `settings.sessionFolders`
的名称（trim 后按大小写不敏感去重）。已有分组的会话不提供列表，避免模型把它挪走。

`ChatApi.titleInstruction()` 在列表非空时把提示换成 JSON 形式：要求标题不超过 20 字、
分组只能从给定名称中选、不确定填空串、只输出 `{"title":"…","folder":""}`；列表为空
时保持原来的纯标题提示，旧行为不受影响。

回复由 `core/SessionTitle.parseTitleSuggestion()` 解析：取第一个 `{` 到最后一个 `}`，
`title` 缺失、为 `null` 或清洗后为空都回退纯文本路径；`folder` 交给 `matchFolder()`，
只有与提供名称大小写不敏感**完全相等**才返回该名称，`null`、空串或模型编造的名称
一律折叠为空串。`Index.applyTitleFolder()` 再按 id 查一次，且只在会话仍无 `folderId`
时写入，因此模型回答永远不能新建分组或覆盖用户已有的归类。标题与分组在同一次刷新里
写回并 `persistSoon()`。

## 工具卡片停止与「从此处重跑」

运行中的工具卡片在标题行右侧显示一个红色方块。它调用的是整轮停止
（`ChatView.onStop` → `Index.stopStream()`），不是单工具取消——工具执行器没有
逐调用的取消句柄，OpenMinis 的同类按钮也接到全局取消上，这里保持一致的语义，
避免让用户以为只有一张卡片会停。

已结算的卡片展开后提供「从此处重跑」，语义与 OpenMinis 的 *Re-run From Here*
一致，是**块边界**而不是轮次边界：

- `core/Types.rerunCutFromTool(messages, messageId, key)` 先按 `toolPartKey()`
  （`toolCallId`，缺失时退回 `名称:参数`）定位工具调用；
- 保留同一助手消息里目标之前的文本/工具块（`hasPreceding`），删掉目标调用、
  它之后的块以及之后的所有消息；目标之前只有推理或什么都没有时，整条助手轮次
  一起丢掉，等价且更简单；
- 裁剪后历史为空（目标就在第一条消息且没有前置内容）时返回 `null`，不产生无法
  发送的请求；
- `Index.rerunFromTool()` 在流式生成时拒绝并提示先停止，否则写回
  `session.messages`、同步 `messageCount`/`updatedAt`、刷新侧栏并调用
  `runAgent(session, '', false)`。模型看到的历史正好停在原工具调用之前，因此会
  重新决定下一步；已删除部分的工具结果不会残留在请求里。

## 生成中排队发送

生成期间 `sendMessage()` 不再直接拒绝：本地命令仍提示「请先停止当前生成」，普通
输入交给 `queuePrompt()`。队列元素是 `QueuedPrompt`（文本、附件快照、入队时的
会话 ID），`enqueueQueued()` / `dropQueued()` 都返回新数组，方便 `@State` 触发
刷新。队列同时存在于两处：

- **运行时**：`AgentRuntime.injectUserMessage()` 把消息与图片 part 推入
  `pendingInputs`，在下一个模型请求边界（工具结果全部回填后）调用
  `drainPendingInputs()` 插入为真实 user 消息。插入发生在请求之间，因此不会破坏
  当前流式响应的 tool_call 配对。
- **界面**：`Index.queuedPrompts` 用于显示「排队中 N / 清空」与「↑ 排队」按钮。
  运行时真正注入后经 `onInputsDrained(count)` 回传条数，界面据此扣减，避免停止后
  把已经进入历史的条目再发一遍。

停止、出错或工具循环自然结束后，`flushQueuedPrompts()` 在没有活动运行时执行队首
（必要时先创建会话、自动压缩），一次只发一条，剩余条目继续等待下一轮结束。切换
会话时属于旧会话的条目直接丢弃并提示「已取消」——与 OpenMinis 一样，排队消息
不会跨会话迁移。

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

## 图片附件

`AttachmentStore` 把相册选择器返回的临时 URI 复制到 `filesDir/attachments/<uuid>.<ext>`
（只接受 png/jpg/jpeg/webp/gif/bmp，单张 10 MB），消息 part 只存
`attachment:<文件名>` 与 mimeType，不把 base64 写进持久化 JSON。输入栏最多同时挂
4 张，发送时 `AgentRuntime.start()` 把它们追加为 `PART_IMAGE` part；编辑消息时保留
非文本 part，因此改文案不会丢图。

发请求时 `AgentRuntime` 的解析器按前缀分流：`attachment:` 走 `AttachmentStore.dataUrl()`
（编码结果按文件名缓存），其余仍走 `LocalToolRuntime.imageDataUrl()`。
`ToolProtocol.toApiMessages()` 对 user 角色收集图片，有图时把 `content` 从字符串换成
`[{type:'text'},{type:'image_url',...}]`；解析失败或没有图片时退回纯文本，不会产生
空消息。`read_image` 与用户附件共用同一条 `image_url` 通路，但开关互不影响。
模型能力表未标记视觉时只提示，不阻止发送。

### 视频与音频附件

输入栏的「视频」用 `PhotoViewPicker`（`VIDEO_TYPE`，最多 4 个），「音频」用
`AudioViewPicker`（最多 4 个）。`AttachmentStore` 接受 mp4/webm/mov/m4v/mkv 与
mp3/m4a/wav/ogg/aac/flac，大小上限按类型分为视频 100 MB、音频 20 MB、图片 10 MB；
`dataUrl()` 对音视频直接返回空串，媒体永远不会变成 base64 进入请求。

发送时 `Index.runAgent()` 为媒体生成两部分：一条
`[视频]/[音频] <文件名>` 文本 part（模型据此知道附件存在），以及 `PART_FILE`
媒体 part（uri + mimeType）。协议转换只读取文本，忽略 `PART_FILE`；如果一条消息
没有任何文本，只有媒体 part，转换会跳过它——所以文本提示是必需的。
`MessageBubble` 按 mime 前缀把 `PART_FILE` 分成视频/音频，用 ArkUI `Video`
控件内联播放（`controls(true)`、`autoPlay(false)`），输入栏预览则用 ▶/♪ 占位块。
编辑消息时保留非文本 part，媒体不会丢失。

## 用量统计与存储

`core/UsageStats.ets` 是纯函数层：`dayKey` 按设备本地时区生成 `YYYY-MM-DD`；
`recordUsage` 把一次请求并入「日期 + 模型 + 预设」同一行并累加请求数，行数超过
`USAGE_RECORD_LIMIT=400` 时按日期保留最新行；`usageTotal` / `usageByModel` /
`usageByProvider` / `usageByDay` 做总量、按模型、按供应商 preset（两者都按总 token
降序）与按日（倒序）汇总。`parseUsage` 对坏 JSON、非数组、缺日期或模型的条目直接
跳过，计数统一归一为非负整数。

`service/UsageStore.ets` 把 JSON 存在 preferences `minis_usage_store`，只保存
token 计数与请求数，不保存提示词或回复内容。`Index` 在每轮结束时取最后一条
`totalTokens > 0` 的助手消息，用消息 id 去重后调用 `UsageStore.record()`，模型
取 `activeModelId()`（含备用模型切换）；统计失败静默，不影响聊天。

`service/StorageUsage.ets` 递归统计目录的文件数与字节（深度 8，读取失败即跳过），
`clearDirectory` 删除目录内容但保留目录本身，单个文件失败不中断其余清理。设置页
「用量统计与存储」展示累计、按模型前 5、按供应商、最近 7 天，以及附件、工作区、
浏览器下载三类占用；清空统计和三类清理都要求二次点按确认。工作区是全局目录，
目前没有按会话归属的文件统计。

## 配置变更审计与回滚

`service/ConfigAuditStore.ets` 的 `configSnapshot` 把设置展开为 44 个 `ConfigPair`：
标量与字符串数组存 JSON，API Key / 沙箱令牌 / WebDAV 密码只存 `"set"` 或 `""`，
MCP / 模型覆盖 / 分组 / 子代理只存条目数，密钥原文与结构化内容都不进审计表。
`Index.applySettings` 与 `pickModel` 在写入前用 `diffConfig` 比较旧快照与新快照，
差异经 `mergeConfigAudit` 插到最前（上限 200）并写入 preferences
`minis_config_audit`。

设置页「配置变更记录」显示最近 30 条：键名、旧值 → 新值、时间。可还原的键由
`CONFIG_RESTORABLE_KEYS` 限定为标量、字符串与字符串数组；`applyAuditedValue`
逐键校验 JSON 类型（枚举只接受已知值，数字要求有限），成功后走正常保存流程，
因此还原动作本身也会生成一条反向记录。密钥与结构化设置的行标为「仅记录」。
当前没有面向代理的 `config` 写入工具，`actor` 字段预留为 `user` / `agent`。

## 会话级 MCP 开关

`SessionMeta.mcpDisabled` 只记录本会话关闭的服务 id，其余服务跟随全局设置；
`core/McpOverrides.ets` 负责归一化、判断与切换（全部返回新数组）。`LocalStore`
加载时归一化，fork 复制，导出与备份恢复保留，普通导入清空。

`McpRuntime` 持有本会话的关闭名单：`definitions()` 在合并 MCP 工具时跳过这些
服务发现的全部工具，`execute()` 对绕过定义直接调用的请求也返回错误。全局关闭的
服务在发现阶段本来就不会拉取，因此会话内只能关闭、不能强制启用；会话参数弹窗把
这类服务标注为「全局已关闭」并禁用开关。

## 记忆面板

`MemoryStore` 维护最近 50 条读写日志（代理写入、检索、手动保存），只存在内存里，
重启清空。聊天页「记忆」面板打开时读取当前 `MemoryStore.context()`（即下一轮会
注入的系统提示）、`editable()` 列出的全部记忆文件与日志。每个文件可独立编辑，
「保存」写回磁盘并刷新注入文本与日志；「撤销」把内容恢复为面板打开时的原文并写回。
面板按文件编辑，不提供按行撤销。

## 模型快速测试

模型选择器每行与自定义 ID 输入框都可发一次连通性测试。`Index.testModel(id)` 克隆
当前设置、只替换 `modelId`，经 `OAuthService.decorate` 补齐 OAuth 头，再调用
`ChatApi.requestModelText`（非流式，`maxTokens=32`，提示语要求只回复 OK）；返回
`ModelTestOutcome { ok, text, message, elapsedMs }`。

`core/ModelTest.ets` 的 `modelTestLine` 把结果压成一行：失败优先显示服务端错误，
成功但正文为空提示「模型没有返回内容」，否则显示「耗时 ms · 首段回复」，回复压平
换行并截断到 80 字。选择器用 `testIds/testLines/testingIds` 三个数组按模型 id
分别记录状态，因此多个模型可并行测试，后完成的请求不会覆盖前一个的结果，也不会
误清另一个模型的「测试中」。测试不修改全局模型选择，只有点「使用」才切换。

图像自检复用同一套行内状态，但单独一组 `imageIds/imageLines/imageUris/imageTestingIds`，
所以文本测试与图像测试互不覆盖。OpenMinis 按模型目录里的输出模态决定是否提供图像
测试；本项目的模型表没有模态元数据，因此以「设置里开启图像生成 + 预设是 OpenAI
兼容协议」为条件（`core/ImageGen.supportsImageGen`，Anthropic/Gemini 原生预设排除）。
`Index.testModelImage(id)` 用固定英文提示词请求 1024×1024，成功后把
`AttachmentStore.uriFor()` 写进 `ModelTestOutcome.imageUri`，选择器据此显示缩略图；
`modelTestLine` 对图像结果显示「耗时 ms · 图像已生成」，失败仍优先显示错误。

## 深链

`module.json5` 注册 `minis` scheme，action 为 `ohos.want.action.viewData`，并带
`entity.system.browsable`。`EntryAbility` 先试深链再试分享：`handleDeepLinkWant()`
只认 `minis://` 前缀，命中后写入 `AppStorage.pendingDeepLink` 并返回 true，
避免把链接当分享文本塞进输入框。

`core/DeepLink.ets` 按 OpenMinis 的路由表解析：会话支持
`session` / `sessions` / `chat` / `s` 加 id，`session/<id>/<资源路径>` 在进入会话后
再打开资源；`open?session=<id>&path=<路径>` 是 launcher 回跳形式，只有 `path` 时
留在当前会话；`new`、`action/new_chat`、`action/camera_chat`（新建会话并打开系统
相机）、`task/<id>`、`settings[/<子页>]`（`scheduled*` 与 `views/alarm` 直接打开
定时任务面板）都有对应动作。路径与查询参数只解码一次，空 id、未知 host 与
`voice_chat` 返回 null。UI 收到链接时清空 AppStorage；如果 bootstrap 还没结束就
先缓存，等会话列表加载完再跳转，否则冷启动会找不到目标。

资源链接由 `core/MinisResource.ets` 解析 `workspace` / `browser` / `attachments`
三个作用域：图片进全屏查看器；`.html`/`.htm` 在工作区面板里用 ArkWeb 渲染；
其余文本类打开只读预览，二进制给出不可预览原因。`minis://file/...` 在 OpenMinis
里没有对应实现，本实现同样不接。

## 接收应用分享

`module.json5` 为 EntryAbility 增加一个 skill：action `ohos.want.action.sendData`、
URI `file` + `text/plain`，让本应用出现在系统的分享目标里。`EntryAbility.onCreate`
与 `onNewWant` 都把 Want 交给 `handleShareWant()`，因此冷启动和运行中分享都生效。

`core/SharePayload.ets` 负责归一化：依次尝试 `ability.params.content`、
`ohos.extra.param.key.content`、`content`、`text`、`sharedText` 几个历史键名；
文件分享从 `ability.params.stream` 取 URI 列表，只读看起来是文本的文件
（扩展名或 MIME 判断），上限 512 KB。图片分享由 `imageUrisFromShare()` 从
`want.uri` 与 `ability.params.stream` 中挑出（MIME 或常见图片后缀，去重，最多
4 张），`ShareReceiver` 把 URI 列表写入 `AppStorage.pendingShareImages`，`Index`
逐张经 `AttachmentStore.saveFromUri()` 复制到应用私有目录后加入待发送附件。
文本写入 `AppStorage.pendingShareText`，`Index` 的 `@StorageProp` 监听后只把
文本填进输入框并清空该键——分享不会替用户发送消息。

## 代码高亮

`core/CodeHighlight.ets` 是一个字符扫描器：按语言选择行注释符（`//` 或 `#`）、
是否支持块注释以及关键字表，然后依次识别块注释、行注释、字符串（含转义）、
数字与标识符；标识符后紧跟 `(` 视为函数调用。相邻同类型片段合并，渲染时
`MarkdownView` 用 `Text { ForEach(Span) }` 输出，每类给一个资源颜色（浅/深色
各一组）。未知语言、空文本或超过 20000 字符的代码直接返回单个纯文本片段，
避免流式生成时反复分词拖慢渲染。

## 数学公式

独立成块的 `$$...$$` 交给 `MathBlockView`：每个公式一个 ArkWeb，加载内置
KaTeX（含 mhchem），页面测量实际宽高后回报，超宽横向滚动，渲染失败退回
`core/Latex.ets` 的 Unicode 近似。

行内 `$...$` 复刻 OpenMinis Android 的离屏 WebView 池：`InlineMathHost` 在聊天
界面背后常驻一个透明 ArkWeb，`InlineMathCache` 按「LaTeX + 字号 + 深浅色」
串行渲染并缓存 `PixelMap`（重复公式共享，上限 256 条），`MarkdownView` 先用
Unicode 近似占位，位图返回后把对应的 `Span` 换成 `ImageSpan`（基线对齐）。
正文、标题、列表、引用与表格单元格都走这条路径；`plainMath`（离屏分享卡）
没有 ArkWeb 宿主，保持近似文本。渲染或截图失败、测量超时都会保留近似文本，
不会留下空白。

## 整库备份

`core/Backup.ets` 在 `sessionBundleJson()` 的信封上增加 `kind: "backup"` 与
`settings` 快照：会话部分复用同一套序列化（流式标记归零），因此备份文件仍能被
普通会话导入器识别。写盘前 `redactedSettings()` 清空 `apiKey`、`sandboxToken`，
以及 `modelOverrides[].extraHeaders` 和 `mcpServers[].headers`——这些字段常放
Bearer Token；`extraBody` 与提示词保留，因为它们是配置的一部分。

恢复分两步：`parseBackupSettings()` 从文件里挑出白名单字段并交给
`cloneSettings()` 归一化；`mergeBackupSettings()` 再用当前设置的 API Key 与
沙箱 Token 覆盖回去。因此“恢复备份”不会把旧密钥写回设备，也不会因为备份文件
外泄而暴露当前凭据。文件与普通会话包共用同一个导入入口：
`parseSessionsExport()` 只看 `app/version/sessions`，额外字段被忽略。
加密归档仍未实现，文件是明文 JSON。

## MCP 工具

`McpClient` 走 MCP 的 Streamable HTTP 传输：每个 JSON-RPC 消息都 POST 到服务
地址，`initialize` 后发送 `notifications/initialized`，再 `tools/list` 发现工具。
响应既可能是 `application/json`，也可能是 `text/event-stream`；`rpcPayloads()`
把 SSE 的 `data:` 行拆出来，`parseRpcBody()` 优先匹配请求 id，找不到时退回第一个
带 `result`/`error` 的事件。服务返回的 `Mcp-Session-Id` 会被保存并在后续请求中带上。

发现结果缓存在进程级的 `McpRegistry` 里：启动、保存设置时后台刷新，设置页的
「刷新」强制重查；签名（启用服务的 JSON）未变时跳过重复发现。发送消息时
`runAgent` 不会等待发现，因此离线或慢服务只会少几个工具，不会卡住对话。
`McpRuntime` 包住本机/远程 `ToolRuntime`，把 MCP 工具追加在 definitions 末尾，
执行时先按 `mcp_` 前缀查表，未命中再交给原运行时。

工具名经 `slug()` 清洗为 `[A-Za-z0-9_-]` 并截断到 64 字符（OpenAI 限制），
形如 `mcp_<服务>_<工具>`。`tools/call` 的 `content` 数组只展开文本项，图片/音频
用占位符表示；`isError` 映射为工具错误。MCP 的 JSON Schema 通过
`ToolDefinition.schemaJson` 原样发给模型，因为内置的 `ToolParameters` 只能表达
扁平属性。stdio 服务无法在鸿蒙应用内启动，因此只支持 HTTP；OAuth 也未接。

## 逐模型参数

`AppSettings.modelOverrides` 是一张按模型 ID 精确匹配的表（不走前缀、不做
大小写折叠）：每条记录可带 temperature、top_p、max_tokens 三个数值覆盖，
以及两个 JSON 文本字段 `extraHeaders` / `extraBody`。数值用 `-1` / `0`
表示“继承全局”，空字符串表示没有额外内容。

`ChatApi.startChatStream()` 在组装完基础请求体和默认请求头后应用覆盖：
数值直接写入类型化字段，`max_tokens` 仍按 `ModelCaps` 夹取；请求头经
`mergeExtraHeaders()` 合并（同名时覆盖）；最后把 body 序列化后交给
`applyExtraBody()`，它只合并顶层键、同名时覆盖，再重新序列化，因此
`ChatRequestBody` 保持严格类型，同时能携带任意 provider 字段。

两个 JSON 字段在设置页保存前校验：请求头必须是“字符串到字符串”的对象，
extra_body 必须是 JSON 对象；失败时提示并拒绝保存。运行时若读到历史遗留的
坏值，解析失败会退回原始请求而不阻断对话。覆盖只作用于聊天请求，
`/compact` 摘要与子代理沿用各自构建的请求体。

## 剪贴板工具

`clipboard_read` / `clipboard_write` 走 `@kit.BasicServicesKit` 的 `pasteboard`，
只处理 `MIMETYPE_TEXT_PLAIN`。两者默认关闭（`clipboardToolsEnabled=false`）：
剪贴板可能含密码、验证码等敏感内容，开启意味着允许模型把它送进请求。读取结果
按 24k 字符截断，写入上限 100k 字符；系统若弹出粘贴授权而用户拒绝，`getData()`
抛错会转成工具错误而不是崩溃。工具只在本机模式注册，`RemoteToolRuntime` 的
定义与执行都拒绝这两个名字；子代理继承主会话开关。

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

预览头部有「导出」：`ExportService.saveFileCopy()` 用 `DocumentViewPicker.save`
取得用户选择的目标 URI，再 `fs.copyFileSync` 复制原文件，二进制文件同样可导出。
导出不经过文本编码，因此不会截断 256 KB，也不需要宽泛存储权限；取消选择返回
「已取消导出」，失败带系统错误信息，结果经 `onToast` 回到聊天页的全局提示。

## 应用锁

`service/AppLock.ets` 在 `appLockEnabled` 时调用 `userAuth.getUserAuthInstance()`，
认证方式为 PIN / 人脸 / 指纹，信任等级 ATL3。`Index.bootstrap()` 在加载完成后请求；
取消或失败时保留全屏锁定页，用户可再次点击解锁。设备未录入任何凭据或 API 不可用
时会以「放行」结算——应用锁的目标是防止旁人随手打开，而不是在无凭据设备上把用户
永久锁在外面。锁只发生在启动时，从系统文件选择器返回不会再次弹窗。

## 生成状态通知

`service/Notify.ets` 使用 `notificationManager` 发布一条固定 ID（1010）的通知。
`Index.onPageHide()` 在仍有生成任务时发布「正在生成回复…」并标记 `isOngoing`；
生成完成（`onUpdate(running=false)`）或用户停止时，同一 ID 被替换为「回复已完成」，
`wantAgent` 让点按通知回到应用。`onPageShow()` 会取消该通知，因此前台用户不会看到
重复提醒。所有调用先检查 `isNotificationEnabled()`，失败一律静默——通知被用户关闭
或设备不支持时，对话本身不受影响。

## 会话状态角标

`SessionMeta.statusBadge` 是一个可选的展示字段，不参与排序、搜索或模型请求。
`core/Types.ets` 的 `normalizeSessionBadge()` 只保留 `background`、`interrupted`、
`syncing` 三个值，其余一律清空。`LocalStore` 读盘时再做一次归一化，并把持久化的
`syncing` 去掉——同步状态只属于当前进程，进程被杀后残留的值会误导用户。

写入点都很短：用户点停止时 `Index.stopStream()` 标 `interrupted`；WebDAV 同步在
`syncBackup()` 开始时把全部会话标 `syncing`，`finally` 只清除仍为 `syncing` 的项，
因此不会覆盖期间新产生的其他角标；启动时若某会话最后一条是 `[后台任务]` 用户消息，
说明后台结果还没被模型回应，标 `background`。`selectSession()`、新一轮 `runAgent()`
与启动恢复的当前会话都会清除角标。`SidebarView` 用 `ForEach` 的 key 包含角标值，
否则仅角标变化时会命中旧 key、复用未更新的行。

`background` 表达「有后台结果待处理」，不是每秒钟的后台进度；后者仍由
`service/Notify.ets` 的系统通知承担。

## 屏幕常亮

`service/ScreenWake.ets` 用 `window.getLastWindow()` + `setWindowKeepScreenOn()`
在生成开始时点亮保持，完成或停止时关闭；窗口已销毁或平台拒绝时静默忽略。它只跟随
本次生成，不改变系统超时设置，因此不会影响应用外的时间行。

## 技能（Skills）

`service/SkillStore.ets` 把导入的 `SKILL.md` 存到 `filesDir/skills/<id>.md`，`id`
由文件名清洗得到（重名自动加 `-2`），启动时读入内存缓存。`core/SkillDoc.ets` 解析
可选的 frontmatter（`name`、`description`），缺少 description 时截取正文前 120 字。
发送时 `Index.runAgent()` 只把已启用技能的短目录拼进系统提示；模型需要细节时调用
`read_skill`，工具返回该文件正文。这样技能库再大也只占几行上下文。未启用任何技能时，
`read_skill` 不会出现在工具列表里。导入走系统文档选择器，上限 512 KB。

每个已启用技能同时注册为斜杠命令：`matchSkillCommand()` 对输入首词做大小写不敏感
的 id 匹配，命中后 `Index` 把技能正文放进 `pendingSkillBody`，下一轮 `runAgent()`
把它追加到系统提示（不进入气泡），命令后的文字作为本轮用户输入；没有附加文字时
发送一句默认指令。`/help` 会按当前启用列表动态列出这些命令。未启用的技能不响应
命令，也不会出现在 `/help` 里。

## 人格（Soul）

`core/Soul.ets` 提供五种内置人格的固定提示词；`AppSettings.soulId` 记录选择，
`normalizeSoulId()` 对未知值回退 `general`。`ChatApi.buildMessages()` 按
「人格 → 用户系统提示词 → 持久记忆」的顺序拼接 system 消息，因此人格是身份底色，
用户的提示词和记忆在其后细化。会话级「追加系统提示词」由 `effectiveSettings()`
先并进系统提示词，最终仍排在人设之后。当前不读取外部 `SOUL.md` 文件。

## 主题色与字号

`AppSettings.accentColor`（`#RRGGBB`，默认 `#2F6BFF`）与三个字号
（`fontScale` / `messageFontScale` / `inputFontScale`，均 0.9–1.3）由
`normalizeAccentColor()` / `clampFontScale()` 校验。旧数据只有 `fontScale` 时，
消息与输入框字号在 `cloneSettings` / `LocalStore.normalizeSettings` 中回退到它。
`Index` 在启动和保存设置时调用 `AppStorage.setOrCreate()`，`MarkdownView`、
`MessageBubble`、`ChatView`、`SidebarView` 用 `@StorageProp` 读取，因此不需要逐层
传参。`fontScale` 用于侧栏、设置与界面控件，`messageFontScale` 用于消息正文、代码
与表格，`inputFontScale` 只用于输入框；`scaleFont()` 负责换算。强调色替换了发送
按钮、用户气泡、工具卡片、链接与选中态。颜色预设与档位标签放在
`core/Appearance.ets`，其余为纯设置字段。

## 启动恢复与输入焦点

`service/UiStateStore.ets` 用 preferences `minis_ui_state` 保存 `lastSessionId`。
`Index.selectSession`、`createChat` 与 fork 后都会更新；`bootstrap` 加载完会话后优先
打开这个 id，不存在（已删除/被导入覆盖）则回退到排序后的第一条。该状态不属于设置，
因此不进入备份或配置审计。

`autoFocusInput`（默认开）由 `ChatView` 监听 `streaming` 从 true 变为 false：延迟
120ms 后 `focusControl.requestFocus('composerInput')`，避免键盘被仍在收尾的列表
挤掉。`autoExpandThinking` 写入 AppStorage，`MessageBubble` 在创建时决定思考块的
初始展开状态：手动切换过的消息仍以用户选择为准。`autoTitleEnabled`（默认开）关闭后
`maybeAutoTitle` 直接返回，标题保留首句截断。

## 每会话参数

`SessionMeta` 上有三个可选覆盖：`modelOverride`、`thinkingOverride`、`promptOverride`，
空串表示继承全局。`core/SessionParams.ets#effectiveSettings()` 复制全局设置后逐项覆盖
（追加提示词非空时拼在全局提示词之后，中间空一行）。发送消息、`/compact` 摘要、
子代理运行时都使用合并后的设置，子代理因此继承父会话的模型与提示词。会话操作弹窗
写入覆盖，「恢复全局」清空；导出 JSON 携带这三个字段，导入与 fork 会保留。全局设置
页仍保持独立，修改全局值不会影响已覆盖的会话。

## 快速模式（service_tier）

快速模式是全局设置 `AppSettings.fastMode`，只影响请求体：打开且供应商支持时，
OpenAI 兼容的 Chat Completions 与 `/compact` 摘要写 `service_tier: "priority"`，
Codex 的 Responses 请求同样写 `priority`。`core/FastMode.ets#supportsFastMode()`
刻意保守：Codex 预设恒支持；自定义端点只有主机正好是 `api.x.ai` 才支持；OpenCode、
Anthropic、Gemini 等一律不发该字段，因为严格的继电器会把未知字段当成 400。
`hostOf()` 负责去掉协议、路径与端口，兼容带尾斜杠或大小写不同的地址。

四条请求路径都在**构建请求体时**读取开关，而不是在发送前缓存，因此切换后下一条
请求立即生效，进行中的流不受影响。入口在对话头部菜单顶部的「快速模式」勾选行，
只在当前供应商支持时出现；`Index.setFastMode()` 对不支持的供应商再次拒绝，克隆
设置、写配置审计并保存。设置页只透传该值（`SettingsSheet` 的 `@State fastMode`），
避免其他设置保存时把它重置为默认值。该键同时进入备份与配置审计的可还原列表。

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

`core/` 二十二个文件不 import `@kit.*`，由 `scripts/test-core.mjs` 复制为 `.mts` 后
用 Node 类型剥离执行（复制时把无扩展名的相对 import 改成 `.mts`）。
UI、HTTP、文件与网络工具需要 DevEco Studio 编译与真机验证。
