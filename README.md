# Minis Harmony

**纯血鸿蒙 6.0+ 平板优先的 AI 对话客户端。**
面向 OpenCode Go 订阅用户，原生 ArkTS / ArkUI 实现，无 Android 兼容层。

除了流式对话，它还实现了 OpenAI 工具调用循环：模型可以读取应用工作区、
搜索文本、写入文件、抓取网页，也可以把同一组工具转发到电脑上的兼容服务。
沙箱是**可插拔**的——本机与远程共用同一套工具定义，后续可以替换为 QEMU 后端。

这个项目参考了 [OpenMinis](https://github.com/OpenMinis/OpenMinis)（Android / iOS）与
[dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)（Flutter Android）的产品形态与
OpenCode Go 接入方式，但代码为面向 HarmonyOS 6.0（API 20）重新编写，不包含上述项目的源码。

---

## 为什么做这个

OpenCode Go 是 OpenAI 兼容的订阅服务，但服务端强制要求每个请求携带
`x-opencode-session`，并且该值必须是**每个对话稳定、首次请求就存在、重启后不变**的
会话 ID。很多通用 OpenAI 客户端不会发送它，结果就是 `400 Request is missing
x-opencode-session`，或者缓存永远不命中。

本项目把这个约束做进了数据模型，而不是做成一个可选请求头：

- 新建对话时立即生成 UUID，并先落库再发请求；
- 该 UUID 同时是本地会话主键，重启、换模型、重试都不会变；
- 只在 `opencode.ai`（含子域）发送，绝不把会话标识泄露给自定义中转；
- 默认基址为 `https://opencode.ai/zen/go/v1`，推理走
  `/zen/go/v1/chat/completions`，模型发现走 `/zen/go/v1/models`；
- 旧基址 `/inference/go/openai/v1` 仍可用，模型发现会自动换算到
  `/inference/go/v1/models`。

---

## 已实现

| | |
|---|---|
| **平板双栏** | ≥ 840vp 自动侧栏 + 对话区；窄屏切换为单栏并支持返回 |
| **OpenCode Go 预设** | 一键填入当前基址，自动注入 `x-opencode-session` |
| **OpenAI 兼容** | 任意兼容 `/chat/completions` 的服务，可自定义基址与模型 |
| **流式输出** | SSE 增量解析，思考过程（`reasoning_content` / `reasoning`）折叠展示 |
| **工具调用循环** | 解析流式 `tool_calls`，同一轮多个工具并行执行，默认最多 200 轮模型/工具往返（可调整），工具卡片可展开 |
| **本机工具** | 工作区内的 `list_dir` / `read_file` / `write_file` / `file_edit` / `search_text`，以及 `fetch_url` / `now`；设置里可逐工具关闭 |
| **持久记忆** | 可选的 `memory_write` / `memory_get`，写入本机每日记忆文件并注入后续对话；设置页可查看 / 编辑 / 清空 |
| **可插拔沙箱** | 本机工作区或远程 HTTP 工具服务，共用同一套工具定义与设置页；可逐工具关闭，写入可要求逐次确认 |
| **本地会话** | 会话、消息、模型、设置持久化在本机，重启可恢复；旧版纯文本消息自动迁移为 parts |
| **本地事件日志** | 可关闭（默认关闭）的结构化 JSONL：请求耗时、模型、轮次、工具状态、错误；脱敏、按天轮转、保留 14 天 |
| **Markdown** | 标题、列表、引用、分割线、行内样式、代码块复制 |
| **交互细节** | 停止生成、重新生成、失败重试、编辑消息并重发、回退到任意消息、置顶 / 归档 / 按日期分组会话、全文搜索（正文与工具结果）、可切换 Enter 发送或换行、斜杠命令 `/new` `/clear` `/compact` `/memory` `/thinking` `/help` |
| **上下文管理** | 可用 `/compact` 让模型摘要旧轮次；发送前超过字符预算时自动截断较早的工具结果 |
| **导出 / 导入** | 长按会话可导出 Markdown（含思考、工具参数与结果）或版本化 JSON（完整 parts，可作备份格式）；侧栏可导入 JSON 为新会话 |
| **后台生成** | 生成期间启动长时任务，切到其他应用仍保持流式连接；可在设置中关闭 |
| **用量显示** | 每条回复的输入/输出 token；顶栏显示最近一次请求的上下文大小 |
| **深色模式** | 跟随系统，使用 HarmonyOS 资源限定词 |

## 尚未实现（明确边界）

这不是 OpenMinis 的完整功能移植。当前阶段聚焦「平板上的高质量 Chat + 工具调用 +
OpenCode Go」，以下能力没有包含：

- 板载 Linux / Alpine 沙箱（`proot`、`ish`）、任意 shell 命令执行；
  QEMU 后端是后续阶段，接口上已为它保留 `ToolRuntime`；
- 浏览器自动化、Skills、MCP、定时任务；
- 语音、分享卡、对话回放、端到端加密分享链接；
- 多模态附件上传（图片 / PDF）、图片生成；
- 账号登录 / OAuth（当前只支持 API Key）。

路线图见 [docs/PORTING.md](docs/PORTING.md)。

---

## 快速开始

### 环境

- **DevEco Studio 6.0.0 或更新版本**
- **HarmonyOS SDK API 20**（HarmonyOS 6.0.0）
- 一台 HarmonyOS 6.0+ 平板，或 API 20 模拟器

工程里的版本声明：

```json5
"compatibleSdkVersion": "6.0.0(20)",
"targetSdkVersion": "6.0.0(20)",
"runtimeOS": "HarmonyOS"
```

如果你的 DevEco Studio 使用不同的 SDK 版本号，请在 `build-profile.json5` 中改成
SDK Manager 里实际安装的版本，然后 Sync。

### 运行

1. DevEco Studio → **Open** → 选择本目录；
2. 等待 hvigor Sync 完成；
3. `File → Project Structure → Signing Configs` 勾选自动签名（或配置自己的证书）；
4. 选择平板设备 / 模拟器，Run `entry`。

### 配置 OpenCode Go

1. 在 [OpenCode Console](https://opencode.ai/auth) 订阅 Go / Go Plus / Go Teams；
2. 复制 API Key；
3. 打开应用右上角 **⚙ 设置**；
4. 服务商选 **OpenCode Go**（基址会自动填为
   `https://opencode.ai/zen/go/v1`）；
5. 粘贴 API Key；
6. 模型可手填，或点 **获取** 拉取账号可用模型；
7. 保存后回到对话直接发消息。

> 不同区域和隐私设置会影响模型可用性。DeepSeek V4.1 Flash / V4 Pro 需要在
> Console 的 Privacy → Regions 选择 Global；Muse Spark Contributor 需要允许
> paid endpoints that train on request data。

---

## 会话头是怎么工作的

```text
新建对话
  └─ util.generateRandomUUID()  ──►  SessionMeta.id（立即持久化）
                                      │
发消息                                 │
  └─ AgentRuntime.start(…, id, …) ─────┤
       └─ ChatApi.startChatStream(…, id, …)
            └─ shouldAttachSessionHeader(baseUrl, id)
                 ├─ host == opencode.ai / *.opencode.ai ?
                 ├─ id 非空且不是 "__" 开头的草稿键 ?
                 └─ 是 ──► header["x-opencode-session"] = id
```

对应实现：

- `entry/src/main/ets/core/OpenCodeRules.ets` — 域名判定、草稿键拒绝、URL 拼接；
- `entry/src/main/ets/service/ChatApi.ets` — 每个请求读取同一会话 ID 并注入；
- `entry/src/main/ets/service/LocalStore.ets` — 会话 ID 与会话一起持久化。

安全边界：

- 使用**精确域名或点锚定子域**匹配，`not-opencode.ai`、`opencode.ai.example.com`
  不会命中；
- 自定义中转即使路径里带 `opencode.ai` 也不会收到会话头；
- `User-Agent` 如实标识 `MinisHarmony/1.0 (HarmonyOS tablet)`，不伪装成官方客户端。

---

## 工具与沙箱

设置 → **工具与沙箱** 有两个后端，模型看到的工具定义完全相同：

| 工具 | 作用 | 本机实现 |
|---|---|---|
| `list_dir` | 列目录 | 工作区内，最多 500 项 |
| `read_file` | 读文本 | 按行 `offset` / `limit`，单文件上限 1 MB，拒绝二进制 |
| `write_file` | 写文本 | 默认关闭，需显式允许；自动创建父目录 |
| `file_edit` | 精确替换 | `old_string` 必须唯一，或 `replace_all=true`；与写入共用开关 |
| `read_image` | 读图片 | 默认关闭；png/jpg/webp/gif/bmp，上限 5 MB，需模型支持视觉 |
| `search_text` | 搜索文本 | 最多 2000 个文件 / 512 KB，跳过依赖与二进制 |
| `memory_write` / `memory_get` | 持久记忆 | 需在设置中开启；写入 `filesDir/memory`，按天归档 |
| `subagent_task` | 子代理 | 仅本机模式；独立内存会话，最多 3 个并行、10 分钟超时 |
| `fetch_url` | 抓网页 | `http(s)`，30 秒读超时，结果截断 |
| `now` | 当前时间 | 设备本地时间 |

**本机模式**的工作区是应用私有目录 `context.filesDir/workspace`。模型只能使用
相对路径；绝对路径、`..` 和符号链接都会被拒绝。写入默认关闭，避免模型未经允许
覆盖文件。

**远程模式**把 `{name, arguments}` POST 到你填写的工具服务，期望返回
`{ok, content}`；可选 Bearer Token。这样平板可以保持轻量，把真实文件系统或
shell 留在电脑 / NAS 上。远程服务必须自己做根目录隔离与鉴权——应用只负责转发，
不会替远程端校验路径。写入同样受“允许写入工作区文件”开关控制：关闭时
`write_file` 不会出现在工具列表里。

仓库自带一个只依赖 Node 22 的参考实现：

```bash
# 在电脑上，工作区限定为 ~/minis-workspace，仅监听本机
node scripts/sandbox-server.mjs --root ~/minis-workspace --port 8787 --token 换成随机串

# 平板与电脑在同一 Tailscale / 局域网时（务必保留 Token）
node scripts/sandbox-server.mjs --root ~/minis-workspace --host 0.0.0.0 \
  --port 8787 --token 换成随机串
```

然后在设置里填 `http://电脑地址:8787/tool` 与同一个 Token。该实现同样拒绝绝对
路径、`..`、符号链接，只提供文件 / 搜索 / HTTP / 时间工具，不执行 shell。

`ToolRuntime` 是两个模式共同的接口；后续的 QEMU/Alpine 后端只需实现
`definitions()` 与 `execute()`，无需改动 AgentRuntime、ChatApi 或 UI。

---

## 轮次上限与事件日志

### 为什么默认是 200 轮

OpenMinis 的 Agent 循环使用 `MAX_AGENT_TURNS = 200`（`ChatViewModel.kt` 与
`HelperRunner.kt` 同值）。这个上限不是模型输出长度，而是**一次用户消息内
「模型请求 → 工具执行 → 再请求」的往返次数**。复杂任务（多文件阅读、搜索、
反复修正）需要几十到上百轮，12 轮会在正常任务中途截断。

本项目的对应实现：

- `AppSettings.maxAgentTurns`，默认 200，设置页可改为 1–1000；
- 达到上限时本轮结束，末尾写入可继续的提示，**不丢弃历史与工具结果**；
- 下次发送消息会带着完整上下文继续，等价于 OpenMinis 的 resumable 行为；
- 停止生成仍会立刻中断请求，并把未完成的工具标记为 error。

### 上下文预算与 `/compact`

设置 → **Agent 与日志** 里的「上下文预算」（默认 60000 字符）是**每次请求**的
估算上限。超过时，`fitHistoryToBudget()` 只对发送给模型的副本截断较早的工具结果，
本地消息、工具卡片和已保存记录都保持完整。这样长任务不会因为一次 `ls` 或
`read_file` 的输出而整轮失败。

`/compact` 是显式操作：保留最近 3 个用户轮次，把更早的部分交给当前模型生成摘要，
再用一条 `system` 消息替换。摘要请求复用同一个会话 ID（OpenCode 路由与缓存不变），
不发送工具，也不写入事件日志正文。

### 事件日志（埋点）

设置 → **Agent 与日志** 可以打开「记录本地事件日志」，默认关闭。日志写入
`filesDir/logs/events-YYYY-MM-DD.jsonl`，一行一个 JSON，只记录元数据：

```jsonc
{"ts":1762531200000,"event":"model_done","level":"info","session":"12345678",
 "model":"kimi-k3","step":3,"tool":"","ok":true,"durationMs":4210,
 "detail":"finish=stop chars=812 calls=2"}
```

覆盖事件：`agent_start` / `agent_finish` / `model_start` / `model_done` /
`model_error` / `tool_start` / `tool_done` / `turn_cap` / `cancelled`。

隐私与容量：

- **不记录**对话内容、系统提示词、工具参数、API Key 或沙箱 Token；
- 错误详情会经过 `redactSecrets()`（`sk-*`、`Bearer *`、`token=` 等）；
- 会话 ID 只保留前 8 位，用于把同一次运行的事件串起来；
- 按本地日期每天一个文件，保留 14 天，单日上限 8 MB；
- 设置页提供「查看事件日志」（最近 200 条，格式化为时间/事件/耗时）与「清空事件日志」；
  日志写失败不会影响对话。

日志是**纯本地**的，没有远端上报，也不包含任何自动遥测。

---

## 工程结构

```text
MinisHarmony/
├── AppScope/                         # 应用级 bundle 配置与图标
├── entry/
│   └── src/main/
│       ├── module.json5              # Stage 模型、tablet/2in1/phone、INTERNET
│       ├── ets/
│       │   ├── entryability/         # UIAbility
│       │   ├── pages/Index.ets       # 状态编排、会话、Agent 生命周期
│       │   ├── components/           # 侧栏、对话、气泡、工具卡片、Markdown、设置
│       │   ├── core/                 # 纯逻辑：类型、parts、工具协议、事件日志、路径规则、SSE、Markdown
│       │   └── service/              # HTTP 流、Agent 循环、本机/远程工具、持久化、日志落盘
│       └── resources/                # 颜色（含 dark）、字符串、图标
├── scripts/test-core.mjs             # Node 下的纯逻辑测试
├── scripts/sandbox-server.mjs        # 远程工具服务参考实现（Node 22）
├── docs/
│   ├── ARCHITECTURE.md
│   └── PORTING.md
├── build-profile.json5               # HarmonyOS 6.0.0(20)
└── oh-package.json5
```

---

## 测试

核心逻辑不依赖鸿蒙运行时，可直接用 Node 22 跑：

```bash
node --experimental-strip-types --experimental-transform-types scripts/test-core.mjs
```

覆盖：

- OpenCode 域名匹配（含 `not-opencode.ai` 等负例）；
- 基址规范化、chat / models URL，默认基址为 `/zen/go/v1`；
- 会话头注入条件（opencode 域 + 非草稿 ID）；
- SSE 分块、CRLF、多 data 行、尾部 flush；
- OpenAI 流式 chunk（content / reasoning / tool_calls / finish / DONE / error）；
- parts 消息模型：文本/思考分离、追加顺序、`messageKey`；
- 工具协议：`assistant.tool_calls` + `tool` 消息展开、中断调用补结果；
- 工作区路径规则：绝对路径、`..`、反斜杠与截断；
- Agent 轮次上限：默认 200、边界钳制、旧设置缺字段；
- 事件日志：密钥脱敏、单行化、JSONL、会话短标签、按天文件名；
- `file_edit`：唯一锚点、重复锚点拒绝、`replace_all`、空/相同/缺失锚点；
- token 用量：`choices: []` 的 usage 块、缺失时补算 total；
- 全文搜索：正文、工具参数与结果、长度上限；
- 持久记忆：条目格式、关键词排序、上下文拼装与截断；
- 会话排序：置顶优先、其余按更新时间；
- 消息回退：保留检查点、拒绝末条与不存在的 id；
- 上下文压缩：按用户轮次切分、摘要文本截断、预算内不改动历史；
- Markdown 导出：角色、思考、工具块与文件名清洗；
- JSON 导出 / 导入：版本化信封、parts 保留、流式标记归零、文件名校验、导入重写 ID 与未完成工具；
- 视觉输入：`read_image` 的 data URL 作为合成 user 消息紧跟工具结果；
- 侧栏分组：置顶与今天 / 昨天 / 最近 7 天 / 更早；
- 工具参数修复：围栏、截断闭合、尾逗号；
- 循环检测：只统计连续相同调用；
- Markdown 块级与行内解析。

当前结果：**44 项全部通过**。

另外做了静态与编译检查：

- `python3 scripts/check-brackets.py`：全部 `.ets` 文件括号配平；
- 使用 OpenHarmony 6.0.0.49 公共 SDK（API 20）与 hvigor 6.20 实际执行了
  `assembleHap`，产出 `entry-default-unsigned.hap`。这验证了 ArkTS 语法、
  ArkUI 声明、资源引用和完整打包链路。

```bash
# 使用仓库里单独声明的 OpenHarmony 编译产物（不改变默认的 HarmonyOS 目标）
OHOS_BASE_SDK_HOME=<sdk 根目录> \
  hvigorw assembleHap --mode module -p product=ohos -p buildMode=debug --no-daemon
```

> 说明：编译验证用的是公共 OpenHarmony SDK，不是华为 HarmonyOS SDK；产物**未签名**，
> 不能直接安装到平板。正式安装仍需 DevEco Studio + 华为 AGC 调试证书 + 设备 UDID
> 的签名配置。默认 product 仍声明 `runtimeOS: "HarmonyOS"`，面向 DevEco。
> 当前设备类型为 `tablet` / `2in1`（公共 SDK 不含 `phone` 的 syscap 定义）。

---

## 安全与隐私

- 对话与设置保存在应用私有 `preferences` 中，不会上传到本机以外，除非你主动请求
  你配置的服务端。
- API Key 与远程 Token 优先保存在 **Asset Store Kit**（`@kit.AssetStoreKit`），
  由系统加密并绑定锁屏；升级后旧的明文值会自动迁移并从 `preferences` 移除。
- 没有锁屏或 Asset Store 不可用时，应用会回退为 `preferences` 明文保存，功能不受
  影响，但安全性取决于设备本身。
- 建议只使用 `https://` 基址；自定义 `http://` 明文地址能否使用取决于系统网络策略。
- 本机工具只能访问 `filesDir/workspace`，拒绝绝对路径、`..` 和符号链接；写入默认关闭，并可要求每次写入前确认。
- `read_image` 默认关闭；开启后图片会以 base64 发送到你配置的服务商，仅在本机模式下可用。
- 事件日志默认关闭，只保存脱敏后的元数据，不含对话内容与密钥；可随时清空。
- 远程工具会把工具名与参数发送到你填写的服务，远程端必须自行限制工作目录并校验
  Token；不要把无鉴权的工具服务暴露到公网。
- 卸载应用会清除全部本地对话、工作区与密钥。

## 许可证

本项目以 [MIT](LICENSE) 发布。

OpenMinis 以 GPLv3 发布，dsh-Go 以 AGPL-3.0 发布。本项目只参考了它们的公开行为与
产品设计，没有复制其源代码；如果你要把本项目与上述代码合并，请自行评估许可证兼容性。
