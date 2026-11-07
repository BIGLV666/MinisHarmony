# Architecture

## 目标

1. **平板优先**：横屏双栏、内容最大宽度、键盘弹出不挤压输入区。
2. **OpenCode Go 正确路由**：每个对话一个稳定 ID，首次请求即发送。
3. **纯 ArkTS / ArkUI**：Stage 模型，API 20，无 WebView、无 Flutter、无兼容层。
4. **核心逻辑可测试**：不依赖 ohos 的部分单独成文件，可在 Node 下运行。

## 分层

```text
pages/Index.ets
  状态编排：会话切换、流式生命周期、弹层、断点
        │
        ├── components/        ArkUI 展示层（无网络、无持久化）
        │     SidebarView / ChatView / MessageBubble / MarkdownView
        │     SettingsSheet / ModelPicker
        │
        ├── service/           运行时能力
        │     ChatApi          HTTP + SSE + OpenCode header
        │     LocalStore       preferences 读写
        │     Format           时间 / 标题 / token 估算
        │
        └── core/              纯逻辑（Node 可测）
              Types            数据模型与默认值
              OpenCodeRules    域名 / 草稿键 / URL
              SseParser        SSE 与 OpenAI chunk
              Markdown         块级 + 行内解析
```

依赖方向严格向下：`components` 不直接发请求，`core` 不 import `@kit.*`。

## 会话 ID 的不变量

OpenCode Go 的要求原文是：

> Send a stable session ID in `x-opencode-session` for each conversation so we
> can optimize routing and prompt caching.

落地为四条不变量：

| 不变量 | 实现 |
|---|---|
| 非敏感、唯一 | `util.generateRandomUUID(true)`，不含账号 / Key / 设备信息 |
| 每个对话稳定 | 与 `SessionMeta.id` 同值，和消息一起持久化 |
| 首次请求就有 | `createChat()` 先写入 `store` 再调用 `startChatStream` |
| 不会误发给第三方 | `isOpenCodeBase()` 精确匹配或点锚定子域 |
| 拒绝草稿键 | `isPersistedSessionId()` 拒绝空串与 `__` 前缀 |

`ChatApi` 在**构造请求时**读取当前会话 ID，而不是在 provider 创建时快照，
所以换模型、重试、重启都不会改变这个值。

## 流式状态机

```text
idle ──send──► streaming ──onDone────► idle
                    │
                    ├──onError──────► idle（消息标记 error，内容保留）
                    └──cancel───────► idle（保留已收到的部分内容）
```

细节：

- `dataReceive` 解码 `ArrayBuffer`，喂给 `SseParser`；
- 解析出的增量先进入 `pendingContent` / `pendingReasoning`；
- 50ms 合并一次，替换最后一条 assistant 消息的**新对象**并重赋值数组；
- `ForEach` 的 key 包含内容长度，确保 ArkUI 在对象不可观察时仍会重建气泡；
- 取消时 `request.destroy()` 并置 `cancelled`，后续回调全部短路；
- HTTP 状态码在 `requestInStream` 完成回调里拿到，错误体从最近 8KB 原始文本提取。

## 持久化

`preferences` 单库，两个 key：

```jsonc
{
  "settings": {
    "preset": "opencode",
    "baseUrl": "https://opencode.ai/inference/go/openai/v1",
    "apiKey": "…",
    "modelId": "kimi-k3",
    "systemPrompt": "",
    "temperature": 1.0,
    "maxTokens": 8192
  },
  "sessions": [
    {
      "meta": { "id": "uuid", "title": "…", "updatedAt": 0, "modelId": "…", "messageCount": 2 },
      "messages": [
        { "id": "uuid", "role": "user", "content": "…", "reasoning": "", "createdAt": 0, "streaming": false, "error": false }
      ]
    }
  ]
}
```

读取时会做字段级归一化：未知 role 丢弃、缺失字段补默认值、`streaming` 一律归零。
写入使用 500ms 防抖，流结束、删除、切换设置时立即落盘。

> 版本化：当前库名带 `_v1`。字段结构变更时应迁移到新库名或增加 `schemaVersion`，
> 不要原地改变消息结构。

## 平板布局

- 根节点 `onAreaChange` 读取宽度，`>= 840vp` 进入双栏；
- 双栏：侧栏固定 300vp，对话区 `layoutWeight(1)`，内部最大宽度 940vp 居中；
- 单栏：`mobileChat` 控制列表 / 对话切换，对话页左上角返回；
- 弹层：设置 90% 高、最大 720vp；模型选择 84% 高、最大 560vp；
- 颜色全部走 `app.color.*`，`resources/dark/element/color.json` 自动跟随系统。

## 错误模型

| 场景 | 行为 |
|---|---|
| 无 API Key / 基址 | 打开设置并 toast，不创建消息 |
| 401 / 402 / 403 / 404 / 429 / 5xx | 中文前缀 + 上游 `error.message` |
| 网络失败 | `BusinessError.code` + message |
| SSE 内 `error` 事件 | 立即中断并保留已收内容 |
| 200 但空内容 | 显示“模型没有返回内容” |
| `finish_reason=length` | 追加“已达到最大输出长度”提示 |

## 可测试性

`core/` 四个文件不 import `@kit.*`，由 `scripts/test-core.mjs` 复制为 `.mts` 后用
Node 类型剥离执行。UI 与 HTTP 层需要 DevEco Studio 编译与真机验证。
