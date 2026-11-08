# OpenMinis 功能对齐清单

本文件记录 OpenMinis（Android Kotlin/Compose + iOS SwiftUI）除 Linux 沙箱以外的全部功能，
以及 MinisHarmony 的复刻状态。**每完成一项，把 `- [ ]` 改成 `- [x]`，并在文件末尾的
「完成记录」里追加一行。**

- 参考仓库：`/home/biglv/project/OpenMinis`（本地完整克隆）
- 参考规模：Android 581 个 Kotlin 文件 / 230,158 行；iOS 622 个 Swift 文件
- 本项目：`entry/src/main/ets` 下的 ArkTS 单平台实现
- 状态图例：`[x]` 已复刻 · `[~]` 部分复刻（行内注明差异）· `[ ]` 未做 · `[-]` 不适用
- 优先级：**P0** 日常手感 · **P1** 核心竞争力 · **P2** 锦上添花 · **P3** 平台相关

> 约定：`[~]` 也算未完成项，继续做时把它推进到 `[x]`。

界面/交互层的实机反馈（右侧溢出、思考等级入口、思考链展开、日志复制等）
单独记录在 [`UI-FEEDBACK.md`](UI-FEEDBACK.md)。2026-11-08 已完成第一轮 UI 修复；
内核沙箱仍是最高优先级，但 UI 项不再一律让路。

---

## 1. 会话与消息交互

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 流式对话 | SSE 增量、思考块折叠 | `ChatApi` + `SseParser` + `MessageBubble` | — |
| - [x] | 停止生成 | 中断请求，保留已收内容 | `AgentRuntime.cancel()` | — |
| - [x] | 会话列表 / 新建 / 删除 | 分组、置顶、归档、多选 | 新建 / 切换 / 长按菜单（置顶 / 归档 / 复制 / 删除） | — |
| - [x] | 复制消息 | 复制文本 / 工具输出 | 气泡与工具卡片均可复制 | — |
| - [x] | 重新生成 | 重跑最后一条 assistant | 删除末尾 assistant 后用相同历史续跑 | P0 |
| - [x] | 编辑用户消息并重发 | 就地编辑，截断其后历史 | 编辑弹层 + 截断到该条 user 消息 | P0 |
| - [x] | 消息回退（rewind） | 回到任意消息节点继续 | 气泡「回到这里」+ 确认弹层，保留该条并删除其后消息 | P1 |
| - [x] | 会话 fork / 复制 | 复制整段会话为新会话 | 深拷贝 `StoredSession` + 新 UUID，长按菜单 | P1 |
| - [x] | 会话置顶 / 归档 / 分组 | 侧栏分组与置顶 | 置顶、归档（含「显示已归档」开关）、按 置顶/今天/昨天/最近 7 天/更早 分组 | P1 |
| - [x] | 全文搜索 | 搜消息正文、工具结果 | 侧栏搜索覆盖标题、模型、正文、工具参数与结果 | P0 |
| - [x] | 多选导出 | 选中多个会话导出 zip | 侧栏「选择会话」多选，导出为单个 `sessions` JSON bundle；不打包 zip（无附件） | P2 |
| - [x] | 消息时间戳 | 相对时间 | 用户与助手气泡底部显示 `formatRelative`；会话列表同样显示相对更新时间 | — |
| - [x] | token 用量显示 | 每条回复的输入/输出 token | 解析流式 `usage` 并持久化到消息 | P0 |
| - [x] | 上下文压力提示 | 接近窗口上限变色 | 顶栏显示 `上下文 12.3k`（最近一次 prompt+completion） | P0 |
| - [x] | 失败重试 | 一键重发上一条 | 错误回复显示「重试」，复用重新生成 | P1 |
| - [x] | 斜杠命令 | `/clear` `/compact` `/memory` `/thinking` | `/new` `/clear` `/compact` `/memory` `/thinking` `/help`；记忆开关为全局而非每会话，思考用请求级 `reasoning_effort`（无模型元数据） | P1 |
| - [x] | 消息内图片预览 | 附件缩略图、点开大图 | 用户气泡显示缩略图，点按全屏 `bindContentCover` 查看；图片副本存应用私有目录 | P2 |
| - [~] | 表格 / LaTeX / 语法高亮 | Markdown 完整渲染 | GFM 表格已支持（表头、对齐分隔行、缺列补空）；代码块按语言着色（JS/TS/ETS/Python/Shell/JSON/Kotlin/Go/Rust 的关键字、字符串、注释、数字、函数调用，未知语言纯文本）；`$$` 独立公式块用内置 KaTeX（`katex.min.js` + `mhchem.min.js` + 字体，约 888 KB）在 ArkWeb 中真实排版，支持矩阵、多行环境、化学式与 `\tag`，按测量高度自适应、超宽横向滚动，深色配色与字号跟随设置，渲染失败退回 Unicode；行内 `$...$` 仍是 `core/Latex.ets` 的 Unicode 近似（`\frac`、`\sqrt`、希腊字母、运算符、上下标、`\text`），不启动 Web 以保证长列表性能 | P2 |
| - [x] | 消息内链接点击 | 内置浏览器打开 | Markdown 链接与裸 URL 可点击，默认在 `BrowserPage` 内置浏览器打开（可一键转系统浏览器）；仅允许 http/https，mailto/tel 仍交系统处理 | P2 |

## 2. Agent 运行时

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 流式 tool_calls | 分片累加 `index/id/name/arguments` | `AgentRuntime.accumulate` | — |
| - [x] | 工具结果回填 | assistant.tool_calls + tool 消息 | `ToolProtocol.toApiMessages` | — |
| - [x] | 轮次上限可配置 | `MAX_AGENT_TURNS = 200` | 默认 200，1–1000，可续跑 | — |
| - [x] | 中断工具补结果 | 避免悬空 tool_call | `interruptToolCalls` + `INTERRUPTED_RESULT` | — |
| - [x] | 本地事件日志 | 结构化日志、脱敏 | `EventLog` + `AppLogger` | — |
| - [x] | 子代理 `subagent_task` | 最多 3 个并行、steer/cancel/resume、10 分钟 | 独立 `AgentRuntime`、全局并行上限 3 + 排队；默认后台执行，立即返回 job_id，结果以「[后台任务结束 …]」消息送回并自动续跑父对话，`wait=true` 阻塞；`status`/`steer`/`cancel`/`resume` 均支持 job_id 前缀，steer 在子代理下一次请求前读取、不打断工具调用，turn 结束时若有待读纠正会续跑；`max_minutes` 1–60（默认 10），嵌套 2 层（嵌套强制阻塞）；结束时子会话落库为「子代理 · 标签」；崩溃遗留任务标记 `interrupted`，resume 从原始任务说明重启（无子转写可续）；未做 `progress_report` 与按对话的角色名册 | P1 |
| - [x] | 工具并行执行 | 同一轮多个 tool_calls 并发 | `Promise.all` 并发执行，结果回到各自 part | P1 |
| - [x] | 上下文压缩（compact） | `/compact` 摘要旧消息 | 保留最近 3 个用户轮次，旧轮次由模型摘要替换；新增自动压缩开关与阈值（默认 80%，50–95），发送前按最近 `prompt+completion` 判断；成功显示可撤销提示，摘要为独立「对话摘要」节点，失败保留原历史；轮次边界对齐用户消息，工具调用/结果不被拆开 | P1 |
| - [x] | 工具循环检测 | 重复调用同一工具时警告 | 连续相同 `name+args` 达 3 次时在工具结果前追加警告 | P2 |
| - [x] | tool call 配对修复 | 补齐缺失的 tool 结果 | 中断结果 + 重复 id 去重 + 空工具名跳过 | P2 |
| - [x] | JSON 参数修复 | 截断/尾逗号自动修复 | 代码围栏 / 截断闭合 / 尾逗号三类修复，失败保留原文 | P2 |
| - [x] | 后台继续生成 | 前台服务 / 后台模式 | 生成期间启动 `dataTransfer` 长时任务，结束/停止即释放；失败静默回退 | P1 |
| - [x] | 达到上下文上限自动截断 | 按 token 预算裁剪旧工具结果 | 发送前按字符预算截断较早的工具结果，不改动已存记录 | P1 |

## 3. 工具面

OpenMinis 的内置工具（逐字）：`shell_execute`、`file_read`、`file_write`、`file_edit`、
`read_image`、`browser_use`、`memory_write`、`memory_get`、`subagent_task`。

| | 工具 | OpenMinis 行为 | MinisHarmony 状态 | 优先级 |
|---|---|---|---|---|
| - [x] | 读文件 | `file_read` offset/limit | `read_file` | — |
| - [x] | 写文件 | `file_write` 覆盖 | `write_file`（默认关闭） | — |
| - [x] | 精确编辑 | `file_edit` 字符串替换 | `file_edit`：唯一锚点 / `replace_all`，纯逻辑可测 | P0 |
| - [x] | 列目录 | 通过 shell `ls` | `list_dir`：目录优先排序、大小与修改时间、路径 jail、跳过符号链接 | — |
| - [x] | 搜索文本 | 通过 shell `grep` | `search_text` | — |
| - [x] | HTTP 抓取 | 浏览器引擎 `fetch` | `fetch_url` | — |
| - [x] | 当前时间 | 通过 shell `date` | `now` | — |
| - [~] | Shell 命令 | `shell_execute {command, timeout}`，默认 900 秒、上限 3600 秒 | 本机 `shell_execute`：iSH 常驻 shell（`cd`、环境变量跨调用保留），工作区与记忆目录 realfs 挂载，应用侧串行队列、增量读取、20000 字符上限，超时停 daemon 并在下一条命令重启内核；主代理与子代理共用；远程模式由远端执行。**待平板实机二连命令冒烟** | P0 |
| - [x] | 读图片 / 视觉 | `read_image` 注入视觉上下文 | `read_image` 读取工作区图片，工具消息后追加合成 user 图片消息；本机模式、默认关闭 | P1 |
| - [x] | 浏览器自动化 | `browser_use` 22 动作 | ArkWeb 子集：隐藏 Web 视图常驻，`browser_use` 支持 open / click / type / text / html / eval / back / forward / reload / wait / title / url；页面加载最多等 20 秒，返回内容截断；远程沙箱模式不暴露 | P2 |
| - [x] | 持久记忆 | `memory_write` / `memory_get` | `filesDir/memory`，每日文件 + GLOBAL.md，关键词检索 | P1 |
| - [x] | 子代理 | `subagent_task` | 本机模式完整实现（后台投递、status/steer/cancel/resume、排队、超时、崩溃恢复），见 2. 子代理；远程沙箱模式仍不暴露子代理 | P1 |
| - [x] | 图像生成 | `minis-model-use` 调用 `/images/generations` | 工具 `generate_image {prompt, size?, model?}`：POST OpenAI 兼容 `/images/generations`（`response_format=b64_json`），支持 1024x1024 / 1024x1792 / 1792x1024，模型省略时用当前对话模型；返回 b64 或 http(s) 图片地址（自动下载），按魔数识别 png/jpg/webp/gif 后存入附件目录，上限 10 MB；工具卡片直接显示缩略图并可全屏查看，下一轮请求把图片作为视觉输入带回模型；设置页「允许生成图片」默认关闭，Anthropic / Gemini 原生预设明确拒绝，远程沙箱与子代理按本机设置继承/不转发 | P3 |
| - [x] | 工具开关 UI | 逐工具启用/禁用 | 设置页「逐工具开关」；`AppSettings.disabledTools`，本机/远程/子代理共用；执行时同样拒绝 | P2 |
| - [x] | 工具权限确认 | 危险操作弹出确认 | 设置项「写入前逐次确认」；`write_file` / `file_edit` 执行前弹窗，允许/拒绝，停止生成会按拒绝结算 | P2 |

## 4. Provider 与模型

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | OpenAI 兼容 | 自定义 base URL | 已支持 | — |
| - [x] | OpenCode Go 会话头 | `x-opencode-session` 域门控 | 已支持，含负例测试 | — |
| - [x] | 拉取模型列表 | `/models` | 「获取」按钮 | — |
| - [x] | Anthropic 原生协议 | Messages API + 流式 | `ProviderPreset` 增加 `anthropic`：`x-api-key` + `anthropic-version`；system 提到顶层，工具转为 `tool_use` / `tool_result` 块，图片转 base64 block；SSE 解析 `content_block_*` / `message_delta` / `message_stop`，工具参数按 `input_json_delta` 累加；`/compact` 与模型发现也走原生端点 | P2 |
| - [x] | Gemini 原生协议 | `generateContent` | `ProviderPreset` 增加 `gemini`：模型 ID 拼进 URL，`x-goog-api-key` 鉴权；system 放 `systemInstruction`，工具转 `functionCall` / `functionResponse`，图片转 `inlineData`；SSE 解析 `candidates[].content.parts`、`usageMetadata` 与 `finishReason`，模型发现与 `/compact` 也走原生端点 | P2 |
| - [x] | OAuth 登录（Claude） | Claude Pro/Max 账号 | PKCE（S256，64 字节 verifier）+ 浏览器授权：系统浏览器打开 `claude.ai/oauth/authorize`，回调停在 `localhost:54545`（鸿蒙不做本地回环服务），用户在设置页粘贴完整回调地址、`code#state` 或授权码；`service/OAuth.ets` 负责加密存储（Asset Store 独立别名）、到期前 5 分钟单飞刷新、刷新失败保留旧令牌；请求改用 `Authorization: Bearer` + `anthropic-beta` 与 Claude CLI 指纹头，API Key 模式不变；令牌只以掩码显示，运行时字段 `oauthToken` 不写 preferences、不进备份 | P2 |
| - [x] | OAuth 登录（Copilot） | GitHub 设备码 | RFC 8628 设备码流程：`github.com/login/device/code` 取设备码并用系统浏览器打开验证页，用户点「我已授权，继续」后按 `interval` 轮询 `access_token`（`authorization_pending` 继续、`slow_down` 加 5 秒、拒绝/过期给出原因）；GitHub 长期令牌存 Asset Store 的 `MinisHarmony.oauth.copilot`，每次请求前用 `copilot_internal/v2/token` 换短时会话令牌（单飞、提前 60 秒刷新、过期秒转毫秒）；请求头伪装 VS Code Copilot Chat（`Editor-Version`、`Editor-Plugin-Version`、`Copilot-Integration-Id`、按最后一条消息角色设置 `X-Initiator`、`X-Request-Id`、图片时加 `Copilot-Vision-Request`），`/chat/completions` 用 Bearer 会话令牌；设置页 Copilot 预设下新增登录卡片、设备码显示/复制、掩码状态与退出 | P2 |
| - [ ] | OAuth 登录（Codex） | ChatGPT 账号 | PKCE + 浏览器授权，响应需 Responses API | P2 |
| - [x] | 模型组 | fallback / 负载均衡 | 设置页「备用模型」逗号/换行分隔；每轮请求先走主模型，失败且本轮尚未产生任何文本/推理/工具调用时按顺序切换备用模型（去重、跳过空项），已重试的模型本轮不再重复；切换写事件日志（`model=` 与 `fallback ->`）；产生输出后再失败不重试，避免重复内容。负载均衡未做（参考实现也以顺序重试为主） | P3 |
| - [x] | thinking level | 逐模型推理档位 | 设置页四档（off/low/medium/high）+ `/thinking` 循环；请求体 `reasoning_effort`。全局设置，不做逐模型元数据 | P2 |
| - [ ] | fast mode | 优先级队列 | 取决于上游支持 | P3 |
| - [x] | 逐模型参数覆盖 | temperature/top_p/headers/extra_body | `AppSettings.modelOverrides` 按模型 ID 精确匹配；设置页可增删改；温度/top_p/最大输出覆盖请求字段，请求头 JSON 合并，extra_body 顶层字段覆盖基础请求体；非法 JSON 在保存时拒绝、请求时忽略 | P2 |
| - [x] | 模型能力元数据 | models.dev 目录、上下文长度 | `core/ModelCaps.ets` 按家族前缀内置上下文/输出/视觉/推理估计；顶栏显示 `已用 / 窗口 (百分比)`，模型列表显示能力标签，`max_tokens` 按上限夹取；离线可用，不做远端拉取 | P2 |

## 5. 记忆 / 技能 / 人格

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 长期记忆 | `GLOBAL.md` + 每日 `YYYY-MM-DD.md` | `filesDir/memory/`，每轮注入最近 3 天 + GLOBAL | P1 |
| - [x] | 记忆检索 | `memory_get` 模糊搜索 | 关键词打分，返回带日期的片段 | P1 |
| - [x] | 记忆开关 | 每会话可关闭 | `AppSettings.memoryEnabled`，默认关闭 | P1 |
| - [x] | 记忆查看 / 编辑 UI | 记忆页 | 设置内嵌文件选择 + 编辑器，可保存 GLOBAL.md 与任意 YYYY-MM-DD.md | P2 |
| - [x] | Skills | `SKILL.md` + frontmatter，按会话启用 | 设置页导入单个 `.md`、开关启用；系统提示只放名称/简介，模型用 `read_skill` 取正文；全局开关而非按会话 | P2 |
| - [x] | Skills 斜杠命令 | 技能注册为 `/命令` | 已启用技能自动成为 `/技能id`；正文注入本轮系统提示，命令后的文字作为用户输入；`/help` 列出 | P2 |
| - [x] | Soul / 人格 | `SOUL.md` 身份层 | 内置 5 种人格（通用/严谨工程师/简洁/耐心讲解/创意写作），作为系统提示前缀；无外部 `SOUL.md` 导入 | P2 |
| - [ ] | 提示词预设库 | ——（OpenMinis 也没有） | 不做 | - |

## 6. MCP / 浏览器 / 工作区

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | MCP HTTP / SSE | JSON-RPC、工具发现 | `core/McpProtocol.ets` + `service/McpClient.ets`：Streamable HTTP 的 `initialize` / `tools/list` / `tools/call`，响应兼容纯 JSON 与 SSE；工具以 `mcp_服务_工具` 暴露，聊天时与本机工具合并；设置页增删服务、手动刷新；无 stdio 与 OAuth | P2 |
| - [ ] | MCP stdio | 启动本地进程 | 鸿蒙不能 spawn，做不了 | - |
| - [ ] | MCP OAuth | PKCE | 可复用浏览器/Web 组件 | P3 |
| - [x] | 内置浏览器 | 单页预览、工具栏 | OpenMinis 的聊天内浏览器是单页 WebView 预览（标题 + 主机、关闭、刷新/停止、外部打开、全屏），本身没有多标签、历史列表、下载与 Cookie 管理；本实现用 ArkWeb 全屏覆盖层对齐，并额外提供后退/前进与可编辑地址栏 | P2 |
| - [x] | 工作区文件浏览 | `minis://workspace` 文件页 | 设置 →「工作区文件 → 浏览」：目录浏览、上一级、文本预览（256 KB）、跳过符号链接；只读 | P2 |
| - [x] | 附件命名空间 | `minis://attachments` | `filesDir/attachments/`，消息 part 存 `attachment:<文件名>`；无对外 URI scheme | P2 |
| - [x] | 深链 | `minis://` 打开会话/文件 | `module.json5` 注册 `minis` scheme（viewData + browsable）；支持 `minis://session/<id>`、`/chat/<id>`、`/s/<id>`、`minis://new`；冷启动排队到 bootstrap 后执行，未知会话提示；`minis://file/...` 未接 | P3 |
| - [x] | 从其他应用分享进来 | Share Extension / ShareReceiver | `EntryAbility` 注册 `ohos.want.action.sendData` / `text/plain`；`onCreate` 与 `onNewWant` 解析文本参数（兼容多个历史键名）或读取首个文本文件（≤512 KB）；经 `AppStorage` 填入输入框、不自动发送；图片分享未接 | P2 |

## 7. 设备能力（Native offloads）

OpenMinis 把设备能力包装成沙箱内 CLI。鸿蒙侧对应 Kit，按需接入 v1。

| | 能力 | OpenMinis | 鸿蒙方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 剪贴板 | `android-clipboard` / `apple-clipboard` | `clipboard_read` / `clipboard_write`，默认关闭、设置页单独开关；`pasteboard` 纯文本读写；远程沙箱不转发 | P2 |
| - [x] | 通知 | `notification` | 后台生成时 `notificationManager` 发布「正在生成」，完成替换为「回复已完成」，点按回到应用 | P2 |
| - [x] | 日历 | `calendar` | `service/DeviceTools.ets`：`calendar` 工具支持 list（时间段内最多 50 条，默认今天起 7 天）与 create（标题/起止/地点/备注，写入默认日历）；`CalendarKit.getCalendarManager` + `READ_CALENDAR`/`WRITE_CALENDAR`，首次调用请求系统授权；默认关闭，设置页单独开关；远程沙箱不暴露 | P3 |
| - [~] | 通讯录 | `contacts` | `contacts` 工具支持 search/list：按姓名、电话、邮箱不敏感匹配，最多 20 条，只读不写；`ContactsKit.queryContacts` + `READ_CONTACTS` 首次授权；默认关闭，远程沙箱不暴露。**当前签名已移除 READ_CONTACTS**：该权限是 system_basic 受限 ACL 权限，调试 Profile 需在 AGC 单独申请，获批前工具对模型隐藏、设置页显示「暂不可用」 | P3 |
| - [x] | 照片 / 相机 | `photos` | 系统相册 `PhotoViewPicker` 多选（最多 4 张、10 MB），复制到应用私有目录；相机拍摄未接 | P2 |
| - [x] | 定位 | `location` | `location` 工具用 `LocationKit.getCurrentLocation` 取一次坐标（FIRST_FIX、10 秒超时），返回经纬度与精度；`APPROXIMATELY_LOCATION` 首次授权；默认关闭，远程沙箱不暴露 | P3 |
| - [x] | 天气 | `weather` | `weather` 工具走 Open-Meteo（无需密钥）：`current` 当前温湿度/体感/风速/降水，`forecast` 1–7 天（天气、最高最低、降水概率）；指定 `city` 时用 Open-Meteo 地理编码，否则用设备定位；WMO 天气码译为中文；`Weather` 相关纯函数在 `core/Device.ets`，97 项测试通过 | P3 |
| - [ ] | 语音识别 | `speech` / ASR | 当前公共 OpenHarmony SDK 不含 `CoreSpeechKit`，接入需华为 HarmonyOS SDK 与真机验证 | P2 |
| - [ ] | 朗读 TTS | `speak` | 同上：`CoreSpeechKit` 不在公共 SDK 中，暂无法编译接入 | P2 |
| - [ ] | 无障碍自动化 | Android AccessibilityService | 无对等能力 | - |
| - [ ] | Shizuku 特权 | Android 专用 | 不适用 | - |
| - [ ] | HealthKit / HomeKit / NFC | iOS 专用 | 不适用 | - |

## 8. 后台任务 / 定时任务

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 切后台继续生成 | 前台服务 / 后台模式 | 已实现，见 2. 后台继续生成 | P1 |
| - [x] | 生成状态通知 | 通知栏显示进度 | `service/Notify.ets`：离开前台且仍在生成时发布常驻通知，完成/停止后替换为完成提醒；回前台自动清除 | P2 |
| - [x] | 定时任务 | AlarmManager / Shortcuts | `core/ScheduledTask.ets` + `service/ReminderScheduler.ets` + `components/ScheduledTasksSheet.ets`：用 `reminderAgentManager` 发布一次性日历提醒（`PUBLISH_AGENT_REMINDER`），通知带 `minis://task/<id>` wantAgent；点击后只把提示词填回输入框，不自动发请求、不偷偷花 token。支持快捷时间/日期/时间选择、删除、手动填入，任务持久化在 preferences | P3 |
| - [x] | 任务运行历史 | 列表 + 结果 | `TaskRun` 记录在 `task_runs`（最多 50 条）：仅当任务预填的提示词原样发送时归属该任务，完成后写入成功/失败/取消与回答摘要；任务为一次性，运行后自动从列表移除。历史可在定时任务面板展开、清空 | P3 |

## 9. 分享 / 导入导出 / 同步

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 导出会话 JSON | 单会话 zip（含附件） | 带 `app/version/exportedAt` 信封的 JSON，保留全部 part 与工具结果；系统文档选择器保存（无附件，故不打包 zip） | P2 |
| - [x] | 导出 Markdown | 对话转 Markdown | 纯函数生成，经系统文档选择器保存（含思考与工具结果） | P2 |
| - [x] | 多会话导出 | 多选打包 | 侧栏多选 → 单个 JSON bundle；导入端同时接受 bundle 与单会话文件 | P3 |
| - [x] | 单轮截图分享 | 渲染一张图 | 助手回复底部「截图」：离屏 `componentSnapshot.createFromBuilder` 渲染 720vp 卡片（会话名、用户问题、Markdown 正文、工具调用摘要、绝对时间与 token），`image.createImagePacker` 编码 PNG 后经系统文档选择器保存；离屏容器不能承载 ArkWeb，显示公式退化为 Unicode 近似；不依赖滚动位置，长回复可完整导出；正文超 12000 字截断、工具行超 12 行折叠，避免贴图过大 | P3 |
| - [ ] | 系统分享 | 文件/链接/文本 | `ShareKit` | P2 |
| - [x] | 备份 / 恢复 | 本地归档、加密 | 整库备份可导出为单个 JSON（全部会话 + 设置快照，API Key / 沙箱 Token / MCP 与模型请求头全部剔除），导入时合并会话并恢复非密钥设置、保留当前密钥；侧栏新增「加密备份（密码保护）」：PBKDF2-HMAC-SHA256（12 万次、16 字节盐）派生密钥，AES-256-GCM（12 字节 IV、16 字节认证标签）加密，密码仅用于派生、不落盘不写日志；导入端自动识别加密包并弹窗要密码，错密码与篡改统一报「密码错误或文件已损坏」，明文上限 16 MB | P2 |
| - [x] | 远程备份 | rclone（SMB/WebDAV/S3/SFTP） | WebDAV 起步：设置页填地址/账号/密码（密码进 Asset Store，与 API Key 同等对待）；上传把整库用该密码经 PBKDF2-HMAC-SHA256 + AES-256-GCM 加密后 PUT 到「minis-backup-日期-enc.json」并覆盖「minis-backup-latest-enc.json」；恢复 GET latest → 解密 → 合并会话并恢复非密钥设置；鸿蒙 `http` 不支持 PROPFIND，因此不列目录、以固定 `latest` 为恢复入口；明文与密码本身永不上传 | P3 |
| - [x] | 多端同步 | iCloud（iOS） | WebDAV 端到端加密同步：`core/SyncMerge.ets` 按会话 id 合并，`updatedAt` 新者胜、同刻偏好有消息的一侧、仅本地存在的一侧永远保留（删除不自动传播）；远端恢复改为保 id 解析并合并，不再重复导入；设置页新增「自动同步」开关与「立即同步（合并远端）」，每轮对话结束/启动/保存设置后 15 秒防抖执行「下载→解密→合并→只推 latest」，单飞锁避免并发；`webDavLastSyncAt` 记录并在设置页显示；自动同步失败静默，手动同步才提示错误 | P3 |
| - [ ] | 分享链接 / 回放卡 | ——（OpenMinis 也没有） | 不做 | - |

## 10. 设置 / 外观 / 本地化

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 深色模式 | 跟随系统 | 资源限定词 | — |
| - [x] | 工具与沙箱设置 | 工具开关、沙箱后端 | `SettingsSheet` | — |
| - [x] | 事件日志开关 | 日志查看器 | 开关 + 清空 | — |
| - [x] | 主题色 / 字号 | 主题、字体缩放 | 设置「主题色」（六种预设，`#RRGGBB`）+「正文字号」（小/标准/大/特大）；经 `AppStorage` 作用于主界面、消息正文/代码/表格与输入框 | P2 |
| - [ ] | 多语言 | 18 种 | `resources/base/element/string.json` 扩展 | P2 |
| - [x] | 首次引导 | 配置 provider / 沙箱 | 首次启动且无 Key 时显示三步引导（欢迎 → 填 Key → 完成），可跳过；`onboardingDone` 持久化，不再打扰 | P2 |
| - [x] | 每会话参数 | 模型、思考档位、系统提示词 | 长按会话「会话参数」：模型 ID、五档思考（含跟随全局）、追加系统提示词；`effectiveSettings()` 在发送/压缩/子代理时合并 | P2 |
| - [ ] | 应用图标切换 | 备用图标 | 鸿蒙不支持动态图标 | - |
| - [ ] | 快捷指令 / 小组件 | iOS Widget / Shortcuts | 服务卡片 | P3 |
| - [x] | 回车键行为 | Enter 发送或换行 | 设置项「Enter 键发送」；输入框切换 `EnterKeyType.Send` / `NEW_LINE`，`onSubmit` 仅在可发送时触发 | P2 |
| - [x] | 常亮 / 自动聚焦 | 小选项集合 | 生成期间 `setWindowKeepScreenOn(true)`，结束/停止恢复；进入对话后自动聚焦输入框（350 ms 后布局完成再请求焦点） | P3 |
| - [x] | 日志查看器 UI | 应用内查看 | 设置页内嵌最近 300 条，格式化为时间/事件/耗时/详情；级别（info/warn/error）与事件类型筛选、关键词/时间搜索、行内长按/按钮复制、复制可见、240/520vp 高度切换；崩溃记录可在应用内查看格式化堆栈并复制 | P2 |

## 11. 安全 / 隐私 / 诊断

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 日志脱敏 | 环境变量、Key 脱敏 | `redactSecrets` | — |
| - [x] | 工作区路径 jail | 沙箱根目录 | `normalizeRelativePath` + symlink 检查 | — |
| - [x] | 写入需显式开启 | 工具权限 | `allowWriteTools` | — |
| - [x] | 密钥安全存储 | Keychain / EncryptedPrefs | `Asset Store Kit`；不可用时回退 preferences 并保留明文兼容 | P1 |
| - [x] | 应用锁 | Face ID / 生物识别 | 设置「启动时验证系统锁屏」；启动调用 `userAuth`（PIN/人脸/指纹，ATL3），无可用认证时放行 | P2 |
| - [x] | 加密备份 | `BackupCrypto` | AES-GCM + 口令派生 | P3 |
| - [x] | 崩溃 / 诊断导出 | 诊断包 | 设置「导出诊断包」：单个 JSON 含设备型号 / 系统版本 / SDK API / 版本号 / 语言、非密钥设置摘要（不含 baseUrl、systemPrompt）、会话与消息数量、`hiAppEvent` 收集的最近 40 条崩溃/冻结记录、最近 300 条事件日志；崩溃参数与日志详情再次过 `redactSecrets` 并截断，明确不含提示词、消息正文、API Key、沙箱 Token；`service/CrashLog.ets` 常驻 watcher，记录落 `filesDir/diagnostics/crashes.jsonl` 并保留 40 条；经系统文档选择器保存 | P3 |
| - [x] | 请求检查器 | LLM 请求日志 | 每次模型请求生成 8 位 `req`，写入 `model_start/done/error` 与同轮工具事件；日志查看器显示 `req=`，不含正文 | P2 |

## 12. 平台特性（不可移植 / 需替代）

| | 功能 | 说明 |
|---|---|---|
| - [~] | 板载 Linux 沙箱 | 鸿蒙禁止 app exec 任何 ELF，但原生子进程可用；改为在子进程内嵌 iSH ARM64 内核 + Asbestos 解释执行 guest，rootfs 用 fakefs。2026-11-08 平板实机冒烟通过：kernel boot → fakefs 挂载 → `/bin/sh -c` 执行 → 输出回传（`hello-from-ish` / `uname -a` 显示 iSH 4.20.69 aarch64 / `uid=0` / Alpine 3.21.3），并以 `[sandbox exit=0]` 上报退出码。现为常驻 daemon：内核只启动一次，`/bin/sh` 作为 PID 1 从 stdin 管道读命令，`cd`/环境变量跨调用保留；`shell_execute` 已接入主代理与子代理，工作区与记忆目录经 realfs 挂到 `/var/minis/*`；rootfs 离线预装 Python 3.12.16 及依赖（构建脚本固定版本与校验和）。**待平板实机验证两条连续命令与 `python3 -c`**；见 [`SANDBOX.md`](SANDBOX.md) |
| - [-] | Android AccessibilityService | 鸿蒙无对等自动化 API |
| - [-] | Shizuku | Android 专用 |
| - [-] | iCloud 同步 / Live Activity / Dynamic Island | iOS 专用，鸿蒙用服务卡片 / 通知替代 |
| - [-] | MCP stdio | 需要 spawn 子进程 |
| - [-] | 应用图标动态切换 | 鸿蒙不支持 |

---

## 完成记录

| 日期 | 完成项 | 备注 |
|---|---|---|
| 2026-11-08 | 建立本清单 | 依据本地 OpenMinis 完整仓库逐项核对 |
| 2026-11-08 | `file_edit` | 唯一锚点 / `replace_all`；本机与远程参考服务同步；5 项新测试 |
| 2026-11-08 | token 用量 + 上下文压力 | 解析 `stream_options.include_usage`，消息页脚与顶栏显示；持久化 |
| 2026-11-08 | 重新生成 / 编辑重发 | 截断到目标 user 消息，复用 `AgentRuntime.regenerate()` |
| 2026-11-08 | 全文搜索 | 标题 + 模型 + 正文 + 工具参数/结果；流式期间不重建索引 |
| 2026-11-08 | 会话 fork | 长按菜单「复制为新会话」，深拷贝消息 |
| 2026-11-08 | 斜杠命令（部分） | `/new` `/clear` `/help`；`/compact` 仍缺失 |
| 2026-11-08 | 并行工具调用 | `Promise.all`，结果回到各自 part |
| 2026-11-08 | 持久记忆 | `memory_write` / `memory_get`、系统提示注入、开关、清空；32 项测试通过 |
| 2026-11-08 | 消息回退 / 失败重试 | 任意历史消息「回到这里」；错误回复显示「重试」 |
| 2026-11-08 | 会话置顶 / 归档 | `pinned` / `archived` 持久化；置顶优先排序，归档默认隐藏且仍可搜索；34 项测试通过 |
| 2026-11-08 | 修复 | `refreshSessions()` 自调用导致启动时无限递归；改为构建 meta 列表 |
| 2026-11-08 | 上下文压缩 / 自动裁剪 | `/compact` 用模型摘要旧轮次并保留最近 3 轮；请求前按 `contextBudgetChars` 裁剪旧工具结果；37 项测试通过 |
| 2026-11-08 | 子代理 `subagent_task` | 独立内存会话 + 相同工具；最多 3 并行、10 分钟超时、嵌套 2 层；远程模式不暴露 |
| 2026-11-08 | 密钥安全存储 | API Key / 沙箱 Token 迁入 Asset Store Kit；旧 preferences 明文自动迁移；不可用时回退 |
| 2026-11-08 | 导出 Markdown | 长按会话「导出为 Markdown」，系统文档选择器选择位置；38 项测试通过 |
| 2026-11-08 | 后台继续生成 | `KEEP_BACKGROUND_RUNNING` + `backgroundModes: dataTransfer`；生成开始/结束成对启停长时任务，失败静默回退 |
| 2026-11-08 | `read_image` 视觉输入 | 工作区图片经 `imageDataUrl()` 转 data URL，`role:"tool"` 后紧跟合成 user 图片消息；5 MB 上限、编码缓存、默认关闭；39 项测试通过 |
| 2026-11-08 | `/memory` `/thinking` | 记忆开关即时生效并落盘；思考在 off/medium 间切换，开启时请求携带 `reasoning_effort` |
| 2026-11-08 | 侧栏日期分组 | 置顶 / 今天 / 昨天 / 最近 7 天 / 更早；纯函数 `groupSessionMetas`，40 项测试通过 |
| 2026-11-08 | 工具循环检测 / JSON 修复 | 连续 3 次相同调用追加警告；围栏、截断闭合、尾逗号三类修复；42 项测试通过 |
| 2026-11-08 | 日志查看器 | `AppLogger.recent(200)` + `formatEventLine()`，设置页内嵌展示；损坏行原样保留 |
| 2026-11-08 | 记忆查看 / 编辑 | 文件选择 + TextArea 编辑 + 保存；仅允许 GLOBAL.md 与 `YYYY-MM-DD.md`，缓存即时失效 |
| 2026-11-08 | 回车键行为 | 设置项「Enter 键发送」；开启后 `enterKeyType=Send` 且 `onSubmit` 发送，关闭保持换行；输入提示随设置切换 |
| 2026-11-08 | 导出会话 JSON | `SessionExport` 版本化信封 + 完整 parts；长按菜单「导出为 JSON」，选择器保存；43 项测试通过 |
| 2026-11-08 | 导入会话 JSON | 侧栏「导入会话 JSON」；校验 app/version、重建 parts、新 ID、标题后缀、未完成工具转 error；8 MB 上限；44 项测试通过 |
| 2026-11-08 | 逐工具开关 | `disabledTools` 持久化 + 设置页 8 个工具开关；本机/远程 runtime 过滤定义并拒绝直接调用，子代理继承 |
| 2026-11-08 | 写入前确认 | `AgentRuntime.runTool()` 在写工具前 await 回调；UI 弹窗含参数预览，拒绝写成工具错误；停止生成会结算为拒绝 |
| 2026-11-08 | 请求检查器 | 每次请求生成 8 位 req，写入同轮模型与工具事件；查看器显示；`turn_cap` 等非请求事件为空 |
| 2026-11-08 | 工作区文件浏览 | 设置内入口；`WorkspaceFiles` 列表/预览，共用路径规则，跳过符号链接；排序与大小格式化纯函数可测；45 项测试通过 |
| 2026-11-08 | 首次引导 | 无 Key 的首次启动显示三步引导，Key 写入 Asset Store，跳过即 `onboardingDone=true`；已有配置不触发 |
| 2026-11-08 | 思考档位 UI | 设置页四档选择，`/thinking` 改为 off→low→medium→high 循环；`cycleThinkingLevel` 纯函数可测 |
| 2026-11-08 | 应用锁 | 启动锁；`service/AppLock.ets` 调用系统认证，取消后显示锁定页可重试；设备无认证时 fail-open |
| 2026-11-08 | 生成状态通知 | `service/Notify.ets`：后台生成常驻通知 + 完成提醒，`wantAgent` 点按回应用；前台不打扰，通知关闭时静默跳过 |
| 2026-11-08 | 消息内链接 | Markdown 链接与裸 URL 均可点击；尾部标点保留；`isOpenableUrl()` 只放行安全协议；46 项测试通过 |
| 2026-11-08 | 每会话参数 | `SessionMeta` 增模型/思考/追加提示词覆盖；会话操作弹窗编辑；发送、`/compact`、子代理均用合并后的设置；导出/导入与 fork 保留；47 项测试通过 |
| 2026-11-08 | Markdown 表格 | 识别表头 + 对齐分隔行，渲染为等宽列表格，缺列补空；LaTeX 与代码高亮仍未做；48 项测试通过 |
| 2026-11-08 | 主题色 / 字号 | 六种强调色 + 四档阅读字号；`AppStorage` 广播，消息正文/代码/表格/输入框即时生效；颜色与缩放函数可测 |
| 2026-11-08 | Soul / 人格 | `core/Soul.ets` 内置五种人格；设置页选择；请求时拼在人设→系统提示→记忆之前；未知 id 回退通用 |
| 2026-11-08 | Skills | 导入 SKILL.md（frontmatter name/description）、开关、删除；目录存应用私有 `skills/`；系统提示注入简介，`read_skill` 按 id 读正文；49 项测试通过 |
| 2026-11-08 | 生成时保持常亮 | `service/ScreenWake.ets` 在开始生成时 `setWindowKeepScreenOn(true)`，完成或停止恢复；失败静默 |
| 2026-11-08 | tool call 配对加固 | 全历史重复 `tool_call_id` 追加 `_2`/`_3` 后缀并同步结果；空工具名的调用不再发送；中断调用仍回填合成结果；51 项测试通过 |
| 2026-11-08 | Skills 斜杠命令 | 已启用技能按 id 注册为 `/命令`，大小写不敏感；正文作为本轮系统提示注入、不显示在气泡；命令后文字作为用户输入；`/help` 动态列出；52 项测试通过 |
| 2026-11-08 | 模型能力元数据 | `core/ModelCaps.ets` 家族前缀估计上下文/最大输出/视觉/推理；顶栏显示窗口占比、模型列表显示标签；请求 `max_tokens` 夹取到模型上限；未知模型回退 128k/8k；53 项测试通过 |
| 2026-11-08 | 剪贴板工具 | `clipboard_read` / `clipboard_write` 经 `pasteboard` 读写纯文本；默认关闭，设置页「允许访问剪贴板」；读取截断到 24k 字符、写入上限 100k；子代理继承，远程模式不暴露 |
| 2026-11-08 | 多会话导出 | 侧栏「选择会话」多选，导出为 `sessions` 数组的 JSON bundle；导入端统一解析单会话与 bundle，逐会话分配新 ID，坏条目跳过；54 项测试通过 |
| 2026-11-08 | 图片附件 / 预览 | 输入栏🖼从系统相册多选（4 张、10 MB），副本存 `filesDir/attachments`；用户气泡缩略图可全屏查看；请求时转 data URL 走多模态 `image_url`；编辑重发保留图片；55 项测试通过 |
| 2026-11-08 | 逐模型参数覆盖 | `core/ModelOverride.ets` + 设置页「逐模型参数」：按模型 ID 精确匹配，覆盖 temperature / top_p / max_tokens，合并额外请求头与 extra_body；未知模型或全局参数不受影响；坏 JSON 保存时拒绝；57 项测试通过 |
| 2026-11-08 | 浏览器自动化 `browser_use` | `service/BrowserTool.ets` + `components/HiddenBrowser.ets`：App 就绪后常驻 1×1 隐藏 ArkWeb（JS/DOM storage 开、文件访问关），工具动作 open/click/type/text/html/eval/back/forward/reload/wait/title/url；选择器与输入文本 JSON 编码后注入，页面加载等 `onPageEnd` 最多 20 秒，结果按 `max_chars` 截断；远程沙箱与子代理不暴露；70 项测试通过、构建通过 |
| 2026-11-08 | 子代理会话落库 | `SubagentRunner` 结束时通过 `onFinish` 把子会话交给页面，`Index.adoptSubagentSession` 合并进 `store` 并触发保存，侧栏标题「子代理 · 标签」，可打开查看或继续对话；失败/超时也保留已有记录；嵌套子代理同样上报；运行中 steer 仍未做；70 项测试通过、构建通过 |
| 2026-11-08 | 内置浏览器 | `components/BrowserPage.ets`：聊天内 http(s) 链接改为全屏 ArkWeb 覆盖层打开，工具栏含地址栏、后退/前进/刷新/系统浏览器/关闭，页面加载进度条与标题；`MarkdownView` 新增可选 `onOpenLink` 回调，未注入时仍走系统浏览器，mailto/tel 继续交系统；暂未做多标签、历史列表、下载、Cookie 管理；70 项测试通过、构建通过 |
| 2026-11-08 | Gemini 原生协议 | `core/GeminiProtocol.ets`：user/model 角色，助手工具调用转 `functionCall`、结果并入紧随其后的 user `functionResponse`（含错误标记），图片转 `inlineData` base64，system 放 `systemInstruction`；设置页第 4 个预设（默认 `https://generativelanguage.googleapis.com/v1beta`）；`streamGenerateContent?alt=sse` 解析文本、`thought` 推理、函数调用（参数对象转 JSON 字符串）、`usageMetadata` 与安全检查拦截；模型发现过滤 `generateContent` 能力；`/compact` 走 `:generateContent`；70 项测试通过 |
| 2026-11-08 | Anthropic 原生协议 | `core/AnthropicProtocol.ets`：历史转 Messages，assistant 工具调用转 `tool_use`、结果并入紧随其后的 user `tool_result`（重复 ID 自动加后缀），图片转 base64 block，system 提到顶层；设置页新增 Anthropic 预设（默认 `https://api.anthropic.com/v1`）；SSE 解码 `message_start` / `content_block_start|delta|stop` / `message_delta` / `message_stop`，累加 input/output tokens；`/compact` 与模型发现同样走 `x-api-key` 原生端点；SSE 传输层抽出 `runStream` 供两种协议共用；67 项测试通过 |
| 2026-11-08 | 深链 | `core/DeepLink.ets` 解析 `minis://session|chat|s/<id>` 与 `minis://new`；EntryAbility 冷/热启动都路由，深链优先于分享；Index 冷启动时等 bootstrap 完成再跳转；63 项测试通过 |
| 2026-11-08 | 输入框自动聚焦 | `ChatView` 首次布局后 350 ms 调用 `focusControl.requestFocus('composerInput')`，失败静默；与生成期间常亮一起补齐该项 |
| 2026-11-08 | 接收应用分享 | `core/SharePayload.ets` 兼容 `ability.params.content` 等键与 `ability.params.stream` 文件列表；`EntryAbility` 冷/热启动都接收，读文本文件上限 512 KB；内容只填入输入框，不自动发送；62 项测试通过 |
| 2026-11-08 | 代码语法高亮 | `core/CodeHighlight.ets` 轻量分词：C 系/JS/Python/Shell/JSON/Go/Rust 关键字、字符串、注释、数字与函数调用；未知语言或超 20k 字符退纯文本；浅/深色各一组配色；61 项测试通过 |
| 2026-11-08 | 整库备份 / 恢复 | 侧栏「备份整库」导出 `minis-backup-日期.json`：全部会话 + 设置快照，密钥类字段（API Key、沙箱 Token、MCP/模型请求头）写盘前清空；「导入」同时识别备份与普通会话包，恢复设置时保留本机密钥；无加密；60 项测试通过 |
| 2026-11-08 | MCP HTTP 工具 | 设置页「MCP 工具」可增删服务（URL + 请求头 JSON + 启用开关）；启动与保存设置时后台发现，手动刷新强制重查；`initialize` → `notifications/initialized` → `tools/list`，调用走 `tools/call`；响应支持 JSON 与 SSE；工具名 `mcp_服务_工具`，JSON Schema 原样透传；无 stdio / OAuth；59 项测试通过 |
| 2026-11-08 | LaTeX 公式 | `core/Latex.ets` 轻量转换：`\frac/\dfrac/\tfrac`、`\sqrt[n]`、希腊字母、关系/集合/箭头运算符、`\sin` 等函数名、`^`/`_` 上下标（Unicode 上下标字符，不支持时退 `^(...)`/`_(...)`）、`\text`/`\mathrm`/`\operatorname`、`\left`/`\right`、`\begin|\end` 环境断行；未知命令丢弃。Markdown 识别单行与围栏式 `$$` 块（等宽居中卡片）以及行内 `$...$`；行内规则排除 `$5` 货币、`$$`、空行与未闭合。矩阵/多行环境只断行，非真实排版；73 项测试通过 |
| 2026-11-08 | 子代理 steer / status / cancel / resume | `subagent_task` 改为单个工具 + `action`：delegate 默认后台执行并立即返回 job_id，结束时把「[后台任务结束 …]」作为用户消息送回父对话并自动续跑；`wait=true`/嵌套子代理同步阻塞。全局最多 3 个并行，其余排队，空位自动泵出；`max_minutes` 1–60。`status` 报告状态/当前工具/耗时/模型/结果；`steer` 由 `AgentRuntime.injectInput` 在下一请求前插入，若 turn 刚好结束则续跑而不是丢弃；`cancel` 保留部分结果；活动任务写入 preferences，重启后标记 `interrupted` 并可由 `resume` 按原始说明重跑。父对话停止时同步取消其阻塞子代理，后台任务继续投递；非当前会话的结果在打开时自动续跑。`core/SubagentJob.ets` 状态机/前缀匹配/报告/后台消息 78 项测试通过 |
| 2026-11-08 | 内置浏览器对齐 | 按 OpenMinis 实际范围校正清单：参考实现只有单页 WebView 预览，没有多标签/历史/下载/Cookie 管理。补齐工具栏差异：加载中显示停止按钮（`controller.stop()`），标题下方显示去 `www.` 与端口的主机名；地址栏与 `browser_use` 共用 `core/WebUrl.ets` 的补协议与主机解析；79 项测试通过 |
| 2026-11-08 | KaTeX 公式排版 | 从参考实现复制内置 `katex/` 资源（`katex.min.js`、`katex.min.css`、`mhchem.min.js`、字体、`katex-render.html`，约 888 KB）到 `rawfile`；`components/MathBlockView.ets` 用独立 ArkWeb 加载并 `javaScriptProxy` 回传测量宽高，`$$` 块按高度自适应，超宽横向滚动，深色与字号跟随设置，`throwOnError` 失败退回 Unicode 文本；`MdBlock.raw` 保留原始 LaTeX；`nestedScroll` 让公式内竖滑交给聊天列表；79 项测试通过、构建通过 |
| 2026-11-08 | 加密备份 | `core/BackupCrypto.ets` 定义并严格校验加密信封（app/version/kind、cipher、kdf、迭代次数区间、base64、payload 长度）；`service/BackupCrypto.ets` 用 PBKDF2-HMAC-SHA256（12 万次、16 字节随机盐、32 字节密钥）+ AES-256-GCM（12 字节随机 IV），按官方约定 `update()` 取密文、`doFinal(null)` 取 16 字节 tag，payload 存「密文‖tag」，解密时 `update()` + `doFinal(null)` 验签；侧栏「加密备份（密码保护）」与导入自动识别，密码只存在组件状态、不落盘不写日志；错误统一提示，明文导入上限放宽到 16 MB；80 项测试通过、构建通过 |
| 2026-11-08 | 模型组 fallback | `AppSettings.fallbackModels` + `parseModelList`/`modelChain` 纯函数（分割、去空白、去重、保持顺序）；设置页「备用模型」输入；`AgentRuntime` 每轮建立主模型 + 备用链，请求失败且本步无任何输出时 `step--` 后异步重试下一个模型，切换写入事件日志（`fallback -> <id>`），已有输出则照旧报错终止；`activeModelId()` 用于请求、事件日志与用量记录；81 项测试通过、构建通过 |
| 2026-11-08 | 图像生成 | `core/ImageGen.ets` 纯函数：端点拼接（复用 `normalizeBaseUrl`）、请求体、尺寸白名单、响应解析（b64/url/错误）、魔数识别图片格式；`service/ImageGen.ets` 走 `http` POST `/images/generations`，URL 结果二次下载，写入附件目录；新增 `generate_image` 工具与 `ImageGenHandler` 边界、设置开关 `imageGenEnabled`（默认关）；`MessageBubble` 工具卡片显示图片缩略图并复用全屏预览；远程沙箱不暴露；82 项测试通过、构建通过 |
| 2026-11-08 | 单轮截图分享 | `components/ShareCardView.ets` 全局 `@Builder` 卡片（问题条 + Markdown 正文 + 工具摘要 + 时间/token 页脚）；`service/Screenshot.ets` 用 `UIContext.getComponentSnapshot().createFromBuilder` 离屏渲染（不受滚动位置裁剪）、`image.createImagePacker` 转 PNG、`DocumentViewPicker` 保存；`MarkdownView.plainMath` 让离屏卡片用 Unicode 公式；`core/ShareCard.ets` 负责文件名与 12000 字/12 工具的边界；`ChatView` 找到上一条用户消息一并入图；83 项测试通过、构建通过 |
| 2026-11-08 | 崩溃 / 诊断导出 | `core/Diagnostics.ets` 定义诊断文档（环境、非密钥设置摘要、计数、崩溃、事件）与文件名，`crashLine` 对系统上报参数再次脱敏并截断到 2000 字；`service/CrashLog.ets` 用 `hiAppEvent.addWatcher` 订阅 `APP_CRASH`/`APP_FREEZE`，落 `crashes.jsonl` 保留 40 条；`service/Diagnostics.ets` 汇总 `deviceInfo`、`bundleManager`、`i18n`、`AppLogger.recent(300)` 并经文档选择器导出；设置页「导出诊断包」；84 项测试通过、构建通过 |
| 2026-11-08 | 定时任务 / 运行历史 | `core/ScheduledTask.ets` 纯逻辑（提示词清洗与 4000 字上限、标题/通知文案派生、1 分钟–1 年时间校验、排序、今天/明天/日期显示、任务与运行记录的防御式解析、运行历史 50 条上限）；`service/ReminderScheduler.ets` 用 `reminderAgentManager` 发布一次性日历提醒（新增 `PUBLISH_AGENT_REMINDER` 权限），wantAgent 指向 `minis://task/<id>`；`core/DeepLink.ets` 支持该深链；`components/ScheduledTasksSheet.ets` 提供提示词、快捷时间（1 小时后/今晚 20:00/明早 09:00）、DatePicker/TimePicker、删除/填入与可展开历史；顶栏 ⏰ 打开；Index 预填后仅在提示词原样发送时归属任务，完成/失败/取消写入 `TaskRun` 并移除一次性任务；任务与历史存 preferences；92 项测试通过、构建通过 |
| 2026-11-08 | 设备数据工具（日历/通讯录/定位/天气） | `core/Device.ets` 纯逻辑：时间参数解析（YYYY-MM-DD HH:mm、ISO、时间戳、当天 HH:mm）、WMO 天气码中文映射、Open-Meteo URL 构造与防御式 JSON 解析、事件/联系人格式化；`service/DeviceTools.ets` 实现 `calendar`（list/create，默认日历，50 条上限）、`contacts`（姓名/电话/邮箱搜索，只读，20 条上限）、`location`（FIRST_FIX，10 秒超时）、`weather`（Open-Meteo 当前/预报 1–7 天，城市名或设备定位），每个能力首次调用才请求系统权限；`DeviceToolsHandler` 让 `LocalToolRuntime` 仅在开关打开时暴露工具，远程沙箱隐藏；`module.json5` 增加 READ/WRITE_CALENDAR、READ_CONTACTS、APPROXIMATELY_LOCATION 与授权理由；设置页新增四个默认关闭的开关；97 项测试通过、构建通过 |
| 2026-11-08 | GitHub Copilot 登录 | `core/OAuth.ets` 新增设备码解析、轮询结果分类（success/pending/slow_down/denied/expired/fatal）、间隔递增与会话令牌解析（`expires_at` 秒转毫秒）；`service/OAuth.ets` 用设备码流程登录 GitHub，长期令牌存 `MinisHarmony.oauth.copilot`，按需换 Copilot 短时会话令牌（单飞、提前 60 秒、失败不清除登录态）；`ChatApi` 的 Copilot 请求头（VS Code 指纹、`X-Initiator`、`X-Request-Id`、视觉标记）与 `/chat/completions` Bearer 认证；`ProviderPreset` 增加 `copilot`（本地存储、备份解析、设置页预设卡与默认 `https://api.githubcopilot.com` + `gpt-4o`）；设置页登录卡片（设备码显示、我已授权、退出、掩码）；发送前置检查允许 Copilot 登录用户；107 项测试通过、构建通过 |
| 2026-11-08 | Claude OAuth 登录 | `core/OAuth.ets` 纯逻辑：base64url、PKCE verifier/challenge、三家 provider 配置与授权 URL、回调解析（完整地址 / `code#state` / 裸 code / error）、令牌 JSON 与过期判定（到期前 5 分钟）、掩码、JWT 声明、RFC 8628 设备码与 Copilot 会话令牌解析；`service/OAuth.ets` 用 CryptoArchitectureKit 生成 64 字节随机 verifier 与 SHA-256 challenge，系统浏览器打开授权页，粘贴回调后 POST 换令牌；令牌存 Asset Store 的 `MinisHarmony.oauth.claude`，内存缓存供同步读取，刷新单飞并在失败时保留旧令牌；`ChatApi` 的 Anthropic 流式、摘要与模型发现统一走 `anthropicAuthHeaders`（OAuth 时 Bearer + 7 个 beta + CLI 指纹头）；设置页 Anthropic 预设下新增登录卡片、回调粘贴框、掩码状态与退出；`oauthToken` 为运行时字段，保存设置与备份时强制清空；107 项测试通过、构建通过 |
| 2026-11-08 | 自动多端同步 | `core/SyncMerge.ets` 以会话为单位合并：同一 id 取 `updatedAt` 较新者，时间相同且一侧为空时取有消息者；远端独有的会话新增，本地独有的会话保留（不做自动删除传播）；输出复用 `sortSessionMetas` 排序。`core/SessionExport.ets` 新增 `parseBackupSessions`，恢复时保留原 id/title/updatedAt，避免「恢复即复制」。`service/WebDav.ets` 的 `uploadEncryptedBackup` 增加 `includeDated=false`，自动同步只覆盖 `latest`，不会每轮生成日期快照。`AppSettings` 新增 `webDavAutoSync`/`webDavLastSyncAt` 并在 LocalStore、备份恢复中归一化。Index 在启动、每轮结束与保存设置后 15 秒防抖同步（`syncRunning` 单飞锁，流式生成时跳过）：下载 latest → 解密 → 保 id 解析 → 合并 → 上传 → 记录时间；自动失败静默，手动「立即同步（合并远端）」才提示；设置页显示上次同步时间与自动同步开关；100 项测试通过、构建通过 |
| 2026-11-08 | 远程备份 WebDAV | `core/WebDav.ets` 负责地址规范化、文件 URL 与「日期快照 + latest」目标；`service/WebDav.ets` 用 Basic 认证 PUT 加密信封、GET latest 供恢复；`AppSettings` 新增 `webDavUrl/webDavUser/webDavPassword`，密码走 `SecureStore` 新增别名并在保存设置时从 preferences 剔除；`redactedSettings` 清空 WebDAV 密码、备份恢复保留当前密码；设置页新增「远程备份（WebDAV）」区块（地址/账号/密码 + 上传/恢复），草稿凭据直接用于当次操作；86 项测试通过、构建通过 |
| 2026-11-08 | Linux 手动签名与首次安装 | 无 DevEco 自动签名，新增 `scripts/manual-sign.sh`（init/udid/build/sign/install）与 `docs/MANUAL-SIGNING.md`：SDK 自带 `hap-sign-tool.jar` 生成 EC P-256 密钥与 CSR，AGC 签发调试证书和 Profile，`hdc` 安装。包名因 AGC 保留字 `harmony` 改为 `app.minis.client`。首次安装报 `9568289 READ_CONTACTS`：该权限是 system_basic 受限 ACL，Profile 的 `allowed-acls` 为空无法授予；暂时从 `module.json5` 移除该权限，`DeviceTools.enabled('contacts')` 固定返回 false、设置页显示「暂不可用」，等 AGC ACL 审批通过后恢复。签名与安装成功 |
| 2026-11-08 | 流式 `usage:null` 闪退修复 | OpenCode 的部分流式 chunk 带 `"usage":null`，`parseOpenAiData` 直接读 `usage.prompt_tokens` 触发 JsError 导致应用闪退；对 `usage`、`error`、`choices`、`delta`、`tool_calls`、`function` 全部做 null 防御，并新增回归测试；108 项测试通过、重新签名安装 |
| 2026-11-08 | 流式字符串字段 `null` 闪退修复 | 修完 usage 后仍有 `Cannot read property length of null`（`ChatApi.consumeEvent` 读 `delta.reasoning.length`）：JSON 的 `null` 能通过 `!== undefined` 检查，被赋给字符串字段。三套协议解析器统一改成按 `typeof === 'string'/'number'` 取值（OpenAI 的 `content/reasoning_content/reasoning/finish_reason/error.message/tool_calls`，Anthropic 的 `text/thinking/partial_json/id/name/stop_reason`，Gemini 的 `text/functionCall.name/finishReason/error.message`），并在 `consumeEvent` 再做一层运行时兜底；新增 5 组 null 字段回归；109 项测试通过、重新签名安装 |
| 2026-11-08 | 板载 Linux 沙箱（iSH 内核） | 实机探针确认：原生子进程可用，但 app 无法 exec 任何 ELF；ptrace 与 `mmap(PROT_EXEC)` 可用。改为在 `childProcessManager.startNativeChildProcess` 内嵌 iSH ARM64 内核 + Asbestos 解释器 + fakefs，guest `/bin/sh` 由内核加载执行。用 OHOS NDK 交叉编译 `libish.a`/`libish_emu.a`/`libfakefs.a` + SQLite amalgamation + 真实 VDSO，打 5 个 Linux/OHOS 可移植性补丁；harness（`entry/src/main/cpp/ish/sandbox_ish.cpp`）挂 rootfs、建设备节点、挂 `/proc`、`/dev/pts`，以文件为 stdio 跑 `/bin/sh -c` 并回写退出码；`scripts/build-ish-ohos.sh` 可从源码一键重建；Alpine 3.21.3 fakefs 以 `rawfile/ish-rootfs.zip`（保留符号链接，3.8 MB）随 HAP 分发，首次运行解压到应用私有目录，避开 `/data/local/tmp` 的 SELinux 限制。运行时冒烟被平板锁屏阻塞，待解锁后验证 |
| 2026-11-08 | UI 反馈第一轮：布局与思考 | P0 右侧溢出改为「头像 + layoutWeight 列 + 端对齐」，百分比 `maxWidth` 获得确定父宽，`ListItem` 显式 100%，代码块长 token `WordBreak.BREAK_ALL`；顶栏新增思考等级菜单（写入 `SessionMeta.thinkingOverride`，`/thinking` 同源，Anthropic/Gemini/不支持 reasoning 的模型隐藏）；思考链流式自动展开、结束收起为「思考了 N 秒 · 摘要」，手动开合按消息 id 记忆，260vp 内滚动并加左侧细线 |
| 2026-11-08 | UI 反馈第一轮：压缩、日志与去装饰 | 自动压缩 + 撤销条 + 独立摘要节点 + 失败保留；日志查看器支持筛选/搜索/复制/高度切换与崩溃堆栈；移除 📌/🖼/🔒/⚠️/⏰/⚙ 和营销副标题、常驻提示；助手操作行可换行。111 项纯函数测试通过、HAP 构建成功；平板实机回归待解锁 |
| 2026-11-08 | 板载沙箱 M2 实机冒烟 | rootfs 在 `filesDir` 首次解压报 `BusinessError 900002`，因为 `zlib.decompressFile` 要求目标目录已存在；解压前 `mkdirSync(staging, true)` 后重新构建、签名、安装。`aa start -a EntryAbility -b app.minis.client --ps sandboxIsh true` 触发冒烟，hilog 捕获到完整回传：`hello-from-ish`、`Linux localhost 4.20.69-ish SUPER AWESOME ... aarch64 Linux`、`uid=0(root) gid=0(root)`、`3.21.3`，证明原生子进程、iSH 内核、fakefs、`/bin/sh -c` 路径全部可用。遗留：结束标记未在 45 秒轮询窗口内出现，guest 超时改为 60 秒、应用轮询改为 150 秒，待下一次实机确认退出码 |
| 2026-11-08 | 板载沙箱结束标记 | 实机复跑确认：把等待放宽到 150 秒后仍无 `[sandbox exit=`，且原生子进程已消失（无崩溃记录），说明 guest PID 1 退出时 iSH 会连带结束整个原生进程，harness 主线程来不及写标记。改为在 ArkTS 层把命令包成 `<command>; __minis_status=$?; printf "\n[sandbox exit=%d]\n" "$__minis_status"`，由 shell 自己上报退出码；重装后冒烟输出以 `[sandbox exit=0]` 结束，约 20 秒返回。M2 完成 |
| 2026-11-08 | 气泡溢出实机回归 | 重装后用 `snapshot_display` 抓取同一段 `hi` 长对话：助手白卡通栏到聊天列右缘，思考条 / `list_dir` 工具条 /「展开」「完成」全部在卡内，无右侧裁切（证据 `docs/assets/ui-layout-fixed-2026-11-08.jpeg`）。竖屏与分屏待验 |
| 2026-11-08 | 沙箱预装 Python 3 | minirootfs 没有 Python，guest 无网络也无法 `apk add`。新增 `scripts/ish-rootfs-python.py`：固定 Alpine 3.21 aarch64 的 python3 3.12.16 与 17 个依赖（musl/openssl/sqlite/readline/ncurses 等，18 个包、13.5 MB，全部带 SHA-256），构建时解包进 rootfs 目录并由 `create_fakefs.py` 重建 `meta.db`（521 → 1380 个文件，zip 3.8 MB → 15 MB）；`--no-python` 可跳过。应用侧加 `filesDir/ish-rootfs/.minis-version`，升级安装时重新解压。构建脚本复现验证：从旧 zip 重新生成 1380 文件、树与 meta.db 完全一致；HAP 21.7 MB，111 项单测通过。`python3 -c` 实机冒烟待平板 |
| 2026-11-08 | 常驻沙箱与 `shell_execute` | 一次性模式每条命令都要冷启动内核（实机约 20 秒）。改为常驻 daemon：`/bin/sh` 作 PID 1 从 stdin 管道读脚本流，应用用「临时文件 + rename」原子提交 `id=<n>\n<命令>`，shell 自己打印 `[sandbox exit=%d id=<n>]`；`SandboxIsh` 变为单例客户端（串行队列、增量游标、90 秒启动窗口、超时停 daemon 并重启）。`shell_execute` 进 ToolCatalog，`ShellTool` 默认 900 秒 / 上限 3600 秒 / 输出 20000 字符，主代理与子代理共用同一 handler；workspace 与 memory 经 realfs 挂到 `/var/minis/*`。111 项单测与 HAP 构建通过；平板未连接，实机二连命令冒烟待做 |
