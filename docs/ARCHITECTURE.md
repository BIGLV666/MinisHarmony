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
        │     LocalStore       preferences 读写与旧数据迁移
        │     Format           时间 / 标题 / token 估算
        │
        └── core/              纯逻辑（Node 可测）
              Types             parts 消息模型、设置、默认值
              ToolTypes         ToolRuntime / ToolDefinition / ToolResult
              ToolCatalog       内置工具定义
              ToolProtocol      内部 parts ↔ OpenAI tool_calls
              Workspace         相对路径规范化、路径 jail、截断
              OpenCodeRules     域名 / 草稿键 / URL
              SseParser         SSE 与 OpenAI chunk（含 tool_calls）
              Markdown          块级 + 行内解析
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
        │     ├─ 依次执行 ToolRuntime.execute(name, arguments)
        │     ├─ 把结果写回对应 part（done / error）
        │     ├─ push 新的 assistant placeholder
        │     └─ runStep()（最多 12 轮）
        └─ 无 tool_calls: finish()
```

细节：

- 流式 tool_call 按 `index` 累加到 `Map<number, ToolAccumulator>`；
  `id` / `name` / `arguments` 都可能分片到达；
- 工具**串行**执行，保持结果顺序与模型请求顺序一致；
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
- `fetch_url` 只接受 `http(s)`，30 秒读超时。

### RemoteToolRuntime

把同一组工具名转发到你配置的 HTTP 服务：

```text
POST <endpoint>
Authorization: Bearer <token>   (可选)
{ "name": "read_file", "arguments": "{\"path\":\"a.txt\"}" }

→ { "ok": true, "content": "..." }
```

远程端必须自己做根目录隔离、鉴权和超时。应用只负责转发，不能替远程端校验路径。
写入与本地模式共用 `allowWriteTools` 开关：关闭时 `write_file` 既不暴露给模型，
`execute()` 也会直接拒绝。

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
    "apiKey": "…",
    "modelId": "kimi-k3",
    "systemPrompt": "",
    "temperature": 1.0,
    "maxTokens": 8192,
    "toolsEnabled": true,
    "allowWriteTools": false,
    "sandboxMode": "local",
    "sandboxUrl": "",
    "sandboxToken": ""
  },
  "sessions": [
    {
      "meta": { "id": "uuid", "title": "…", "updatedAt": 0, "modelId": "…", "messageCount": 2 },
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
          "error": false
        }
      ]
    }
  ]
}
```

读取时会做字段级归一化：未知 role 丢弃、未知 part kind 归为 text、缺失字段补默认值、
`streaming` 一律归零。上次运行中处于 `pending` / `running` 的工具调用会改成
`error` 并补一条“上次运行中断”，这样下一次请求不会出现没有结果的 tool_call。

写入使用 500ms 防抖，流结束、删除、切换设置时立即落盘。

> 版本化：当前库名带 `_v1`。字段结构再次变更时应迁移到新库名或增加
> `schemaVersion`，不要原地改变消息结构。

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

## 可测试性

`core/` 八个文件不 import `@kit.*`，由 `scripts/test-core.mjs` 复制为 `.mts` 后
用 Node 类型剥离执行（复制时把无扩展名的相对 import 改成 `.mts`）。
UI、HTTP、文件与网络工具需要 DevEco Studio 编译与真机验证。
