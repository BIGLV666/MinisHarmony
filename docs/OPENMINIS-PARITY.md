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
| - [x] | 表格 / LaTeX / 语法高亮 | Markdown 完整渲染 | GFM 表格已支持（表头、对齐分隔行、缺列补空）；代码块按语言着色（JS/TS/ETS/Python/Shell/JSON/Kotlin/Go/Rust 的关键字、字符串、注释、数字、函数调用，未知语言纯文本）；`$$` 独立公式块用内置 KaTeX（`katex.min.js` + `mhchem.min.js` + 字体，约 888 KB）在 ArkWeb 中真实排版，支持矩阵、多行环境、化学式与 `\tag`，按测量高度自适应、超宽横向滚动，深色配色与字号跟随设置，渲染失败退回 Unicode；行内 `$...$` 复用同一个 KaTeX 页面，但按 OpenMinis Android 的「离屏 WebView 池 + 文本内占位图」方案实现：根组件 `InlineMathHost` 在聊天界面背后常驻一个透明 ArkWeb，`service/InlineMathCache` 串行渲染并按「LaTeX + 字号 + 深浅色」缓存 `PixelMap`（上限 256 条，淘汰只丢引用避免正在显示的图被释放）；`MarkdownView` 先显示 `core/Latex.ets` 的 Unicode 近似，位图返回后用 `ImageSpan`（基线对齐、按 `px2vp` 还原尺寸）原地替换，正文、标题、列表、引用和表格单元格都覆盖，渲染失败或超时则保留近似文本；独立成行的 `![alt](url)` 渲染为图片（http(s)、`minis://workspace`、`minis://browser`、`minis://attachments`、工作区相对路径），行内图片仍保留为文本 | P2 |
| - [x] | 消息内链接点击 | 内置浏览器打开 | Markdown 链接与裸 URL 可点击，默认在 `BrowserPage` 内置浏览器打开（可一键转系统浏览器）；仅允许 http/https，mailto/tel 仍交系统处理 | P2 |

## 2. Agent 运行时

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 流式 tool_calls | 分片累加 `index/id/name/arguments` | `AgentRuntime.accumulate` | — |
| - [x] | 工具结果回填 | assistant.tool_calls + tool 消息 | `ToolProtocol.toApiMessages` | — |
| - [x] | 轮次上限可配置 | `MAX_AGENT_TURNS = 200` | 默认 200，1–1000，可续跑 | — |
| - [x] | 中断工具补结果 | 避免悬空 tool_call | `interruptToolCalls` + `INTERRUPTED_RESULT` | — |
| - [x] | 本地事件日志 | 结构化日志、脱敏 | `EventLog` + `AppLogger` | — |
| - [x] | 子代理 `subagent_task` | 最多 3 个并行、steer/cancel/resume、10 分钟 | 独立 `AgentRuntime`、全局并行上限 3 + 排队；默认后台执行，立即返回 job_id，结果以「[后台任务结束 …]」消息送回并自动续跑父对话，`wait=true` 阻塞；`status`/`steer`/`cancel`/`resume` 均支持 job_id 前缀，steer 在子代理下一次请求前读取、不打断工具调用，turn 结束时若有待读纠正会续跑；`max_minutes` 1–60（默认 10），嵌套 2 层（嵌套强制阻塞）；结束时子会话落库为「子代理 · 标签」；崩溃遗留任务标记 `interrupted`，resume 从原始任务说明重启（无子转写可续）；`progress_report` 支持 none/frequent(15s 有变化才发)/moderate(60s)，以「[后台任务进度 …]」消息送回父对话，`wait=true` 时忽略，父对话流式时新报告替换未读旧报告；`core/SubAgentRoster.ets` 提供内置 `helper` + 最多 10 个命名子代理（名字 40、说明 200、附加提示 4000 字符上限），名册进入系统提示，`subagent_task.agent` 按名字选择，子会话标题为「子代理 · 名字 · 标签」，设置页可增删改 | P1 |
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
| - [x] | Shell 命令 | `shell_execute {command, timeout}`，默认 900 秒、上限 3600 秒 | 本机 `shell_execute`：iSH 常驻 shell（`cd`、环境变量跨调用保留），工作区与记忆目录 realfs 挂载，应用侧串行队列；完成检测只扫输出末尾 256 KB，命中后整读一次；会话输出过 24 MB 在命令间轮转 daemon；超时/用户停止停 daemon 并立即返回已打印内容（末尾 512 KB）；输出经 `core/Terminal.ets` 去 ANSI/OSC、折叠 `\r`、头尾截断到 20000 字符；运行中每 700 ms 把清洗后的末尾 4000 字符推到工具卡片「实时输出」（折叠状态也显示最后 4 行，对齐 OpenMinis 的 live sheet），停止时标注输出不完整；受「允许写入工作区文件」、逐工具开关与逐次确认约束；主代理与子代理共用；远程模式由远端执行。**实机 2026-11-09 验证：三条命令连跑 5.9 秒，`pwd` 与 `MINIS_SMOKE=kept` 跨调用保留；会话内模型调用 `uname -a; id` 返回 `4.20.69-ish aarch64`、`uid=0(root)`、`[exit=0]`；20 万行输出按头尾截断并标注省略；流式期间「停止」立即生效** | P0 |
| - [x] | 读图片 / 视觉 | `read_image` 注入视觉上下文 | `read_image` 读取工作区图片，工具消息后追加合成 user 图片消息；本机模式、默认关闭 | P1 |
| - [x] | 浏览器自动化 | `browser_use` 22 动作 | 22 个动作全部实现：open/navigate、click、type、text/get_text、html、eval/execute_js、scroll、get_page_info、find_elements、hover、get_readable、get_backbone、get_cookies、set_cookies、set_user_agent、set_viewport、scroll_and_collect、wait_for_dom_stable、screenshot、fetch，以及 new_tab/close_tab/list_tabs（另有 back/forward/reload/wait/title/url）。多标签由最多 4 个独立 `HiddenTab` 组成，每个有自己的 `WebviewController` 与历史，`tab_id` 选择目标页，活动页 `zIndex` 置顶；关闭活动页自动切到首个剩余页，拒绝关闭最后一页。所有隐藏视图全屏透明且不拦截触摸；`screenshot` 经 `webPageSnapshot` 存 PNG 到工作区 `.minis-browser/` 并返回 `minis://browser/` 链接（与 OpenMinis 一致），工具卡片直接显示缩略图；`fetch` 下载同样落在 `.minis-browser/` 并返回 `minis://browser/` 链接；`open/navigate` 接受 `minis://workspace`、`minis://browser` 与 `minis://attachments`，映射为 `file://` 加载本地 HTML（相对 JS/CSS/图片可用）；App 启动时注册 `minis` 自定义 scheme，每个隐藏标签页在 `onControllerAttached` 安装 `WebSchemeHandler`，HTML 内绝对 `minis://` 子资源由 handler 读文件返回（带 MIME 与 CORS 头，单文件上限 64 MB）；`get_cookies` 只返回名称与长度并把值写入 env 文件；页面加载最多等 20 秒，返回内容截断；远程沙箱模式不暴露 | P2 |
| - [x] | 持久记忆 | `memory_write` / `memory_get` | `filesDir/memory`，每日文件 + GLOBAL.md，关键词检索 | P1 |
| - [x] | 子代理 | `subagent_task` | 本机模式完整实现（后台投递、status/steer/cancel/resume、排队、超时、崩溃恢复），见 2. 子代理；远程沙箱模式仍不暴露子代理 | P1 |
| - [x] | 图像生成 | `minis-model-use` 调用 `/images/generations` | 工具 `generate_image {prompt, size?, model?}`：POST OpenAI 兼容 `/images/generations`（`response_format=b64_json`），支持 1024x1024 / 1024x1792 / 1792x1024，模型省略时用当前对话模型；返回 b64 或 http(s) 图片地址（自动下载），按魔数识别 png/jpg/webp/gif 后存入附件目录，上限 10 MB；工具卡片直接显示缩略图并可全屏查看，下一轮请求把图片作为视觉输入带回模型；设置页「允许生成图片」默认关闭，Anthropic / Gemini 原生预设明确拒绝，远程沙箱与子代理按本机设置继承/不转发 | P3 |
| - [x] | 工具开关 UI | 逐工具启用/禁用 | 设置页「逐工具开关」9 项（含 `shell_execute`）；`AppSettings.disabledTools`，本机/远程/子代理共用；执行时同样拒绝 | P2 |
| - [x] | 工具权限确认 | 危险操作弹出确认 | 设置项「写入前逐次确认」；`write_file` / `file_edit` / `shell_execute` 执行前弹窗，允许/拒绝，停止生成会按拒绝结算 | P2 |

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
| - [x] | OAuth 登录（Codex） | ChatGPT 账号 | `core/OAuth.ets` 新增 Codex 的 PKCE 配置（授权页 `auth.openai.com/oauth/authorize`、回调 `localhost:1455/auth/callback`、JSON 换码 / 表单刷新）与 `id_token` 声明解析（`chatgpt_account_id`、`chatgpt_plan_type`）；`service/OAuth.ets` 用系统浏览器登录、粘贴回调完成、Asset Store 存于 `MinisHarmony.oauth.codex`、到期前刷新单飞；`core/ResponsesProtocol.ets` 实现 Responses API 线格式：`instructions` 顶层、`message`/`function_call`/`function_call_output` 输入项、扁平工具定义、`prompt_cache_key`、SSE 解码（文本/推理/工具参数增量/`completed` 用量/`incomplete`/`failed`），工具 id 记为 `call_id|item_id`；`ChatApi` 的 Codex 分支用 `codex_cli_rs` 指纹头 + `chatgpt-account-id` 走 `backend-api/codex/responses`，`/compact` 与模型发现（`/codex/models`，过滤 hidden，失败回退内置列表）同步；设置页新增「ChatGPT Codex」预设与登录卡片（掩码、订阅、退出、回调粘贴）；发送前置检查允许已登录用户 | P2 |
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
| - [x] | MCP HTTP / SSE | JSON-RPC、工具发现 | `core/McpProtocol.ets` + `service/McpClient.ets`：Streamable HTTP 的 `initialize` / `tools/list` / `tools/call`，响应兼容纯 JSON 与 SSE；工具以 `mcp_服务_工具` 暴露，聊天时与本机工具合并；设置页增删服务、手动刷新；无 stdio；static OAuth 另见下条 | P2 |
| - [ ] | MCP stdio | 启动本地进程 | 鸿蒙不能 spawn，做不了 | - |
| - [x] | MCP OAuth | PKCE | 对齐 OpenMinis 的 static 模式：`core/McpOAuth.ets` 纯逻辑（client id / 授权与令牌端点 / scopes / redirect / RFC 8707 resource 规范化、授权 URL 带 `response_type`、`code_challenge(S256)`、`state`、`access_type=offline`、`prompt=consent`、可选 `resource`/`scope`，换码与刷新表单只在有 client secret / resource 时追加）；`service/McpOAuth.ets` 用系统浏览器打开授权页、粘贴完整回调（鸿蒙无回环监听）、表单换码与到期前单飞刷新；client secret 与令牌按服务 id 存 Asset Store（`MinisHarmony.mcp.oauth.token.<id>` / `...secret.<id>`），配置只保留非密钥字段与 `clientSecretSet`；`McpClient` 自动附加 `Authorization: Bearer`（手填请求头优先），`McpRegistry.refresh` 先并行取令牌再发现工具；设置页 OAuth 开关与字段、保存后的「OAuth」登录面板（掩码状态、开始/完成/退出登录），删除服务时清除令牌与 secret；备份含非密钥 OAuth 配置但不含 secret | P3 |
| - [~] | 内置浏览器 | 多标签、工具栏、历史/下载/设置 | OpenMinis Android 的聊天内浏览器不是单页预览：有标签栏、历史面板（搜索/清空）、下载面板（进度、角标、清空、打开文件）和浏览器设置（UA 预设/自定义、视口宽高、Cookie 按域过滤与清空）。本实现已对齐工具栏、后退/前进、可编辑地址栏与 4 标签页池（`HiddenBrowser` + `BrowserHost`），聊天内 `BrowserPage` 新增 🕘 历史（搜索/清空/点击重开，旧记录同 URL 合并）、⬇ 下载（Web 下载委派写入 `filesDir/browser-downloads`，列出名称/大小/时间，点击用 `file://` 打开，可清空）、⚙ 设置（默认/移动/桌面/自定义 UA、宽视口开关、当前站与全部 Cookie 清除）；`browser_use` 的 `download` 仍写工作区 `.minis-browser/`。剩余：下载进度条与工具栏角标、按域过滤 Cookie 的列表、视口宽高数值设置 | P2 |
| - [x] | 工作区文件浏览 | `minis://workspace` 文件页 | 设置 →「工作区文件 → 浏览」：目录浏览、上一级、文本预览（256 KB）、跳过符号链接；只读 | P2 |
| - [~] | 工作区资源链接 | `[name](minis://workspace/path)` | 回复中的 `minis://workspace/...` 链接可点击，直接打开只读预览并定位到该文件；解析时解码一次百分号转义，拒绝绝对路径、`..` 与控制字符。附件链接按类型处理：图片进全屏查看器，md/txt/json/csv 等文本类打开只读文本预览（等宽、可复制、256 KB 截断），二进制类型给出不可预览原因。`.html`/`.htm` 在工作区面板内用 ArkWeb 直接渲染（`file://` + 逐段 `encodeURIComponent`，相对 CSS/JS/图片可加载，`fileAccess`/`javaScriptAccess`/`domStorageAccess` 打开，400vp 高），与 OpenMinis 文件预览的 HTML 渲染一致；二进制文件仍只给不可预览原因，没有 OpenMinis 的导出/外部打开按钮。`shell_execute` 说明里教模型用这种链接；`minis://browser/<file>` 同样可点击 | P2 |
| - [x] | 附件命名空间 | `minis://attachments` | `filesDir/attachments/`，消息 part 存 `attachment:<文件名>`；无对外 URI scheme | P2 |
| - [x] | 深链 | `minis://` 打开会话/文件 | `module.json5` 注册 `minis` scheme（viewData + browsable）；支持 `minis://session|sessions|chat|s/<id>`、`minis://session/<id>/<资源路径>`、`minis://open?session=<id>&path=<路径>`（launcher 回跳）、`minis://open?path=...`、`minis://new`、`minis://action/new_chat`、`minis://action/camera_chat`（新建会话并打开系统相机；`voice_chat` 因缺 CoreSpeechKit 仍不支持）、`minis://task/<id>`、`minis://settings[/<子页>]`、`minis://views/alarm`；资源路径按 `browser/`、`workspace/`、`attachments/` 作用域打开预览，裸路径按工作区处理；`settings/scheduled*` 与 `views/alarm` 直接打开定时任务面板；冷启动排队到 bootstrap 后执行，未知/不支持的链接提示 | P3 |
| - [x] | 从其他应用分享进来 | Share Extension / ShareReceiver | `EntryAbility` 注册 `ohos.want.action.sendData` / `text/plain`；`onCreate` 与 `onNewWant` 解析文本参数（兼容多个历史键名）或读取首个文本文件（≤512 KB）；经 `AppStorage` 填入输入框、不自动发送；另有 `ability.params.stream` 中的图片 URI（`want.uri` 也接受），在 UI 初始化 `AttachmentStore` 后复制到附件目录（最多 4 张，走同一格式/大小校验），加入待发送附件列表并提示视觉能力；`module.json5` 的 sendData skill 增加 `file` + `image/*` | P2 |

## 7. 设备能力（Native offloads）

OpenMinis 把设备能力包装成沙箱内 CLI。鸿蒙侧对应 Kit，按需接入 v1。

| | 能力 | OpenMinis | 鸿蒙方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 剪贴板 | `android-clipboard` / `apple-clipboard` | `clipboard_read` / `clipboard_write`，默认关闭、设置页单独开关；`pasteboard` 纯文本读写；远程沙箱不转发 | P2 |
| - [x] | 通知 | `notification` | 后台生成时 `notificationManager` 发布「正在生成」，完成替换为「回复已完成」，点按回到应用 | P2 |
| - [x] | 日历 | `calendar` | `service/DeviceTools.ets`：`calendar` 工具支持 list（时间段内最多 50 条，默认今天起 7 天）与 create（标题/起止/地点/备注，写入默认日历）；`CalendarKit.getCalendarManager` + `READ_CALENDAR`/`WRITE_CALENDAR`，首次调用请求系统授权；默认关闭，设置页单独开关；远程沙箱不暴露 | P3 |
| - [~] | 通讯录 | `contacts` | `contacts` 工具支持 search/list：按姓名、电话、邮箱不敏感匹配，最多 20 条，只读不写；`ContactsKit.queryContacts` + `READ_CONTACTS` 首次授权；默认关闭，远程沙箱不暴露。**当前签名已移除 READ_CONTACTS**：该权限是 system_basic 受限 ACL 权限，调试 Profile 需在 AGC 单独申请，获批前工具对模型隐藏、设置页显示「暂不可用」 | P3 |
| - [x] | 照片 / 相机 | `photos` | 系统相册 `PhotoViewPicker` 多选（最多 4 张、10 MB），复制到应用私有目录；输入框「拍照」调用 `cameraPicker.pick` 打开系统相机（后置、仅照片），结果 URI 走同一条 `AttachmentStore.saveFromUri` 流程，格式/大小不支持时提示，视觉能力缺失时提醒 | P2 |
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
| - [ ] | 系统分享 | 文件/链接/文本 | **暂不可做**：本机安装的 HarmonyOS 6.0.0 API 20 SDK 不含 `ShareKit`（`@hms.core.*` 目录缺失），`ACTION_SEND_DATA` 自 API 9 起已废弃，`ShareExtensionAbility` 只能接收。当前替代：截图分享 + 文档选择器导出 | P2 |
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
| - [x] | 多语言 | 18 种 | 18 种语言（简中、繁中、英、日、韩、德、法、西、葡巴、俄、泰、印尼、马来、土、波、罗、克、菲）：源码中文原文即键，`t()` 按「当前语言 → 英文 → 中文」回退；启动时从 `resources/rawfile/i18n/*.json` 同步加载，简中零开销；设置页语言区即时切换并持久化，`i18nVersion` 驱动整棵页面子树重建（无需重启）；17 份词条各 1,224 条，`scripts/i18n-merge.mjs` 校验键集、`scripts/i18n-audit.mjs` 审计；持久化标记保持中文，`i18nVariants()` 跨语言识别旧消息 | P2 |
| - [x] | 首次引导 | 配置 provider / 沙箱 | 首次启动且无 Key 时显示三步引导（欢迎 → 填 Key → 完成），可跳过；`onboardingDone` 持久化，不再打扰 | P2 |
| - [x] | 每会话参数 | 模型、思考档位、系统提示词 | 长按会话「会话参数」：模型 ID、五档思考（含跟随全局）、追加系统提示词；`effectiveSettings()` 在发送/压缩/子代理时合并 | P2 |
| - [ ] | 应用图标切换 | 备用图标 | 鸿蒙不支持动态图标 | - |
| - [~] | 快捷指令 / 小组件 | iOS Widget / Shortcuts | 2×2 服务卡片：`FormExtensionAbility` 读取主应用发布的快照（当前会话标题 + 最近一条助手回复摘要 + 运行中标记），点按卡片回到应用；主应用在持久化、切换会话与启动后发布，内容不变不重复刷新，并立即 `updateForm` 已登记卡片；卡片随深浅色主题取资源颜色。**实机 2026-11-09 验证：数据链路全部正常，但系统渲染服务画不出任何内容，卡片空白。** 已确认：`onAddForm` 在卡片扩展进程执行并返回合法 `FormBindingData`（`title=hi`、正文 121 字符）；`ets/widgets.abc` 含模块记录 `app.minis.client/entry/ets/widget/pages/WidgetCard`（`initialRender`/`rerender`）；桌面日志 `Add form success ... type: 1, uiSyntax: 2`；`com.ohos.formrenderservice` 打印 `FormRenderer: InitUIContent ... formData.size = N` 后既无页面加载、无异常，也不再有第二次渲染。把卡片页面简化到 `Column` + `Text('HELLO CARD')`（不引任何资源/词条）依旧空白，且选择器预览与桌面同时空白；同机其它应用（平板管家、Petal One、日历、备忘录）卡片正常。已排除布局/资源/i18n、`useNormalizedOHMUrl`（关掉后 abc 记录名不变，仍空白）、改用 `runtimeOS: HarmonyOS` 构建（SDK 组件缺失无法构建）。推断为 OpenHarmony SDK 编译出的 `widgets.abc` 不被本机 HarmonyOS 表单渲染服务接受（或页面模块解析方式不同），暂无绕过方案。桌面长按快捷指令未做：本机 API 20 的 `module.json5` 校验不接受 `shortcuts` 字段；深链参数 `minis_deep_link` 已接通，待 SDK 支持即可补配置 | P3 |
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
| - [x] | 板载 Linux 沙箱 | 鸿蒙禁止 app exec 任何 ELF，但原生子进程可用；改为在子进程内嵌 iSH ARM64 内核 + Asbestos 解释执行 guest，rootfs 用 fakefs。2026-11-08 平板实机冒烟通过：kernel boot → fakefs 挂载 → `/bin/sh -c` 执行 → 输出回传（`hello-from-ish` / `uname -a` 显示 iSH 4.20.69 aarch64 / `uid=0` / Alpine 3.21.3），并以 `[sandbox exit=0]` 上报退出码。现为常驻 daemon：内核只启动一次，`/bin/sh` 作为 PID 1 从 stdin 管道读命令，`cd`/环境变量跨调用保留；`shell_execute` 已接入主代理与子代理，工作区、记忆、聊天附件与技能目录经 realfs 挂到 `/var/minis/*`；rootfs 离线预装 Python 3.12.16、Node.js 22.23.4、npm 10.9.1 与 git 2.47.3（含 libcurl）及依赖，并从 ca-certificates 的 PEM 生成 CA bundle（构建脚本固定版本与 SHA-256）。guest 的 socket 调用由 iSH 转发给宿主，因此可以直接联网；构建时写入 `/etc/resolv.conf` 与 `/etc/hosts`，`curl`/`pip`/`npm`/`git` 可用。新增常驻解释器工具 `python_execute`（平板实测热请求 14–28 ms，变量与导入跨调用保留，超时自动重启）。2026-11-09 平板实机验证两条连续命令（`pwd=/tmp`、`MINIS_SMOKE=kept`）、`python3 -c` 与 `shell_execute` 会话调用，M3–M5 全部完成；见 [`SANDBOX.md`](SANDBOX.md) |
| - [-] | Android AccessibilityService | 鸿蒙无对等自动化 API |
| - [-] | Shizuku | Android 专用 |
| - [-] | iCloud 同步 / Live Activity / Dynamic Island | iOS 专用，鸿蒙用服务卡片 / 通知替代 |
| - [-] | MCP stdio | 需要 spawn 子进程 |
| - [-] | 应用图标动态切换 | 鸿蒙不支持 |

---

## 13. 源码对照补充（2026-11-10）

上一轮按 iOS 行为做对齐时漏记了 Android 侧的一批用户可见能力；以下为逐文件对照
OpenMinis 源码后新增的缺口，状态均为未做，按影响排序。浏览器行已据
`ui/browser/BrowserHistorySheet.kt`、`BrowserDownloadsSheet.kt`、
`BrowserSettingsSheet.kt` 改正为 `[~]`。

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 生成中排队发送 | 代理运行时仍可发送：消息进入队列，在工具边界或停止后作为用户消息注入，输入框上滑提示 Release to queue | 已实现：生成中输入框保留「↑ 排队」按钮，消息与图片进入本地 FIFO（`core/PromptQueue.ets`）并调用 `AgentRuntime.injectUserMessage()` 在工具边界插入为真实用户消息；`onInputsDrained` 回传已注入条数同步扣减 UI 队列；停止/异常结束后未注入条目经 `flushQueuedPrompts()` 自动续发；输入框上方显示「排队中 N / 清空」；切换会话时丢弃不属于当前会话的条目 | P0 |
| - [x] | 自定义会话分组 | 新建/重命名/解散文件夹，移动会话、分组内新建、折叠分组；现有实现只有按日期分组 | 已实现：`SessionMeta.folderId` + `AppSettings.sessionFolders`（`core/SessionFolder.ets` 纯函数：新建/重命名/删除/折叠/分组）；侧栏在无搜索词时按文件夹分组，标题行显示折叠箭头、会话数、`＋`（分组内新建），末尾「未分组」，空文件夹也保留；「管理分组」弹窗支持新建、重命名、删除；会话长按菜单新增「移动到分组」，删除分组时保留会话并回到未分组；分组随设置进整库/加密备份与 WebDAV，会话导出保留 `folderId`（普通导入仍落未分组） | P1 |
| - [~] | 浏览器历史 / 下载 / 设置 | 历史搜索与清空；下载列表打开/清空/角标；UA 预设与自定义、视口、Cookie 按域过滤与清空 | 已实现大部分：`core/BrowserHistory.ets`（历史解析/去重/搜索、下载解析/按路径更新、大小格式化）+ `service/BrowserStore.ets`（preferences 持久化）；`BrowserPage` 三个面板——🕘 历史（标题/域名/相对时间、搜索、清空、点击重开）、⬇ 下载（`WebDownloadDelegate` 写入应用私有 `browser-downloads`，同名自动加时间戳，列出名称/大小/时间，成功项用 `file://` 打开，可清空）、⚙ 设置（默认/移动/桌面/自定义 UA、宽视口开关、当前网站与全部 Cookie 清除）。下载用 `onDownloadUpdated`/`getPercentComplete()` 维护进行中列表，面板顶部显示进度条、工具栏 ⬇ 显示进行中数量；Cookie 用 `core/BrowserHistory.cookieOrigins()` 从当前页与历史提取 origin（最多 20），逐站查询条数并单独清除。未做：视口宽高数值（ArkWeb 未暴露） | P2 |
| - [x] | 自动生成会话标题 | 首轮后按首条用户+助手内容让模型起标题，长会话补末尾；失败回退截断首句；侧栏可重新生成 | 已实现：`core/SessionTitle.ets`（`cleanTitle` 去引号/前缀/句号并截到 20 字、`titleTranscript` 取首轮用户+助手，超过 8 条消息再补最近一条助手、`hasAnswer` 跳过失败轮）；`ChatApi.generateSessionTitle` 复用摘要的非流式通道（OpenAI 兼容/Anthropic/Gemini/Codex，指令 ≤20 字，`max_tokens` 200）；一轮结束后 `Index.maybeAutoTitle` 仅在标题仍是派生首句时异步请求，成功写 `SessionMeta.title` 并持久化，失败静默保留 `titleFrom()`；会话操作菜单新增「重新生成标题」（手动失败会提示），编辑首条用户消息会重置并在下一轮重新生成 | P2 |
| - [~] | @ 文件提及 | 输入框键入 `@` 弹出会话工作区文件列表，方向键选择并插入路径 | 已实现：`core/Mention.ets` 识别草稿末尾的 `@query`（要求 `@` 在开头或空白之后，邮件地址不触发），`service/WorkspaceFiles.listWorkspaceFiles()` 递归列出工作区文件（最多 4 层、跳过隐藏目录与 `node_modules`/`oh_modules`/`.hvigor`/`build`/`.minis-browser`、上限 300 个）；`ChatView` 在输入框上方显示最多 5 条匹配（文件名 + 相对路径，不区分大小写），点按插入 `@path `，回车选中当前项；工具栏新增 `@` 按钮。剩余：方向键上下切换高亮（ArkUI TextArea 未暴露光标位置，目前只按尾部 token 识别，光标在中间时无法触发） | P2 |
| - [~] | 视频/音频附件与内联播放 | 相册可多选视频，消息与文件预览内联播放并显示缩略图 | 已实现：输入栏新增「视频」「音频」按钮，分别用 `PhotoViewPicker`（`VIDEO_TYPE`，最多 4 个）与 `AudioViewPicker`（最多 4 个）选取；`AttachmentStore` 支持 mp4/webm/mov/m4v/mkv 与 mp3/m4a/wav/ogg/aac/flac，视频上限 100 MB、音频 20 MB，媒体永不转 data URL；消息里写入 `[视频]/[音频] 文件名` 文本提示 + `PART_FILE` 媒体 part（协议层忽略、不影响上下文），用户气泡用 `Video` 控件内联播放（视频 240×150、音频 240×54，手动播放、显示控件），输入栏用 ▶/♪ 占位块预览。剩余：视频封面缩略图（当前不截帧）、音频播放器外观改用自定义 AVPlayer 控件 | P2 |
| - [~] | 用量统计与存储管理 | 按模型/供应商聚合输入输出 token（实测/估算）；按类别/会话查看占用并清理单会话生成文件 | 已实现：`core/UsageStats.ets` 纯函数（解析、按「日期+模型+预设」合并、累计、按模型排序、按日倒序，保留最新 400 行）+ `service/UsageStore.ets`（preferences `minis_usage_store`，只存 token 计数，不存提示词）；`Index` 在每轮结束记录最后一条带 `totalTokens` 的助手消息，按消息 id 去重，模型取 `activeModelId()`；设置页「用量统计与存储」显示累计输入/输出/请求数、按模型前 5、最近 7 天，可二次确认清空。存储占用由 `service/StorageUsage.ets` 递归统计附件、工作区、浏览器下载（文件数+字节），二次确认后清空对应目录（保留目录本身，单个失败不中断）。剩余：按供应商聚合、按会话查看占用与只清理单会话生成文件 | P2 |
| - [~] | 会话级 MCP 开关 + 记忆面板 | 单会话覆盖 MCP 服务启停；聊天内查看本轮注入的记忆与读写日志，逐条编辑/保存/撤销 | 已实现：`SessionMeta.mcpDisabled` 保存本会话关闭的服务 id，`core/McpOverrides.ets` 提供归一化/判断/切换纯函数；`LocalStore` 读写归一化，fork 与导出保留；`McpRuntime` 在 `definitions()` 中过滤该服务全部工具，并在 `execute()` 拒绝直接调用。会话参数弹窗新增「MCP 服务」列表，全局启用的服务可逐项开关，全局关闭的显示「全局已关闭」且开关不可用。聊天页标题栏「记忆」打开面板：显示当前会注入的系统提示、所有可编辑记忆文件（GLOBAL.md 与每日文件，逐文件 TextArea + 保存/撤销到打开面板时的原文），以及 `MemoryStore` 最近 50 条读写日志（代理写入、检索、手动保存）。剩余：全局关闭的服务尚不能在单会话强制启用（发现阶段只拉全局启用项）；记忆按文件而非按行编辑；日志为本次启动的内存记录 | P2 |
| - [~] | 模型快速测试 | 从模型选择器对条目跑文本/图像生成自检并内联显示结果 | 已实现：`core/ModelTest.ets` 定义 `ModelTestOutcome` 与 `modelTestLine`（失败显示错误、空回复提示、成功显示耗时 + 首段 80 字并压平换行）；复用 `ChatApi.requestModelText`（非流式、32 token）与 `OAuthService.decorate`，`Index.testModel(id)` 克隆设置后仅替换 modelId。模型选择器每行新增「测试」按钮，测试中显示「测试中…」，结果就地显示在行内；自定义 ID 输入后也有独立测试按钮。多个模型可并行测试、按 id 分别记录状态。剩余：图像生成自检（OpenMinis 会按模型能力发一张图） | P3 |
| - [~] | 配置变更审计与回滚 | 记录用户/代理经 `config` 工具改动的键值、状态与时间，可一键还原旧值 | 已实现：`core/ConfigAudit.ets` 提供 `diffConfig`（按键比较编码后的快照）、`mergeConfigAudit`（新在前、上限 200）、`parseConfigAudit`（丢弃坏行）与 `auditValueLabel`；`service/ConfigAuditStore.ets` 的 `configSnapshot` 覆盖 44 个设置键，经 preferences `minis_config_audit` 持久化。设置保存与模型切换前比较旧/新设置，逐键记录时间与旧新值；设置页「配置变更记录」显示最近 30 条，标量/字符串/字符串数组标量可「还原」为旧值（还原本身也记一条反向记录），可二次确认清空。安全：API Key、沙箱令牌与 WebDAV 密码只存「已设置/未设置」，MCP/模型覆盖/分组/子代理等结构化设置只存条目数，二者不可还原。剩余：代理仍无 `config` 写入工具，暂无 agent 来源记录 | P3 |
| - [x] | 启动/外观/输入细项 | 启动进入上次会话、自动展开思考、回复后自动聚焦、自动分组与标题开关、消息/输入框/全局分别缩放；长粘贴转附件占位；用户消息「压缩到此为止」可撤销、工具卡片「从此处重跑」/单独停止 | 已实现：`UiStateStore`（preferences `minis_ui_state`）记录最后打开的会话，启动时优先恢复，会话不存在则回退最新；新设置 `autoExpandThinking`（结算后仍展开思考）、`autoFocusInput`（`streaming` 由 true 变 false 时 `focusControl.requestFocus`）、`autoTitleEnabled`（关闭后 `maybeAutoTitle` 直接返回）、`messageFontScale` 与 `inputFontScale`（分别经 AppStorage 驱动 MarkdownView/用户气泡与输入框，`fontScale` 继续管界面）；设置页三组字号与三个开关，旧数据缺字段时消息/输入框字号回退到原 `fontScale`。用户消息「压缩到此为止」的撤销横幅此前已实现（`compactUndo`/`canUndoCompact`）。长粘贴：输入框单次插入超过 15000 字时，`core/Paste.ets` 用公共前后缀还原插入段，`Index.attachHugePaste()` 把它写入 `<workspace>/pasted/Pasted_<时间>.txt` 并作为 `text/plain` 附件加入待发送列表；气泡只显示 📄 文件名，模型收到「[粘贴文本] pasted/…（可用 read_file 读取）」标记 + 文件 part，不再把正文塞进草稿或气泡。工具关闭或远程沙箱时保留原文在输入框（模型无法读取工作区文件）。自动归入分组：标题请求把已有分组名一并交给模型，`core/SessionTitle.parseTitleSuggestion` 解析 `{"title","folder"}`，`matchFolder` 只接受与提供列表大小写不敏感的完全相同名称（`null`/空串/未知名称一律视为不分组），`Index.applyTitleFolder` 只在会话尚无 `folderId` 时写入，从不新建分组；`SessionTitle.titleInstruction` 无分组或开关关闭时退回原来的纯标题提示。设置页新增「自动归入分组」开关（默认开），`AppSettings.autoGroupingEnabled` 已接入克隆、归一化、备份与配置审计。工具卡片：运行中的卡片标题右侧显示红色停止块，点击调用与输入框相同的整轮停止（与 OpenMinis 一致，工具层没有单调用取消 API）；展开已结算的卡片显示「从此处重跑」，`core/Types.rerunCutFromTool()` 按块边界保留目标工具调用之前的文本/工具块，删除该调用、其后块与之后所有消息，再 `runAgent` 让模型重新决策；目标前没有任何实质内容时直接丢弃整条助手轮次；流式生成中拒绝重跑。 | P3 |
| - [~] | 会话列表状态角标 | 卡片角标显示后台暂停/被中断/同步中，进入会话后清除 | 已实现：`SessionMeta.statusBadge` 只接受 `background`/`interrupted`/`syncing`，`normalizeSessionBadge` 做白名单，`LocalStore` 读盘时归一化并丢弃被杀死进程留下的 `syncing`。`SidebarView` 在会话标题旁显示角标：中断用危险色、同步用主题色、后台用次要色，`ForEach` key 纳入角标以便状态变化立即重绘。写入点：`Index.stopStream()` 标「已中断」；`syncBackup()` 开始时给全部会话标「同步中」，`finally` 只清除仍为同步中的项；`bootstrap` 为仍有未回应后台结果（最后一条是 `[后台任务]` 用户消息）的会话标「后台」。进入会话、开始新一轮生成、启动时恢复当前会话都会清除角标；角标随会话持久化，但 `syncing` 不跨进程。剩余：后台暂停/运行中的实时进度仍由系统通知承担，角标不反映后台任务的逐秒状态 | P3 |

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
| 2026-11-08 | 设置页沙箱状态与重置 | 工具与沙箱页新增「沙箱状态」：显示已就绪 / 需要重新解压（带旧版本号）/ 尚未解压，rootfs 实际占用（递归统计），以及内核是否常驻；「重置」两次点击确认，停 daemon 后删除 `filesDir/ish-rootfs`，下次使用重新解压；首次使用时提示在解压约 15 MB。`zlib.decompressFile` 无进度回调，暂不显示百分比。HAP 构建通过，实机视觉待验 |
| 2026-11-08 | 沙箱预装 Python 3 | minirootfs 没有 Python，guest 无网络也无法 `apk add`。新增 `scripts/ish-rootfs-python.py`：固定 Alpine 3.21 aarch64 的 python3 3.12.16 与 17 个依赖（musl/openssl/sqlite/readline/ncurses 等，18 个包、13.5 MB，全部带 SHA-256），构建时解包进 rootfs 目录并由 `create_fakefs.py` 重建 `meta.db`（521 → 1380 个文件，zip 3.8 MB → 15 MB）；`--no-python` 可跳过。应用侧加 `filesDir/ish-rootfs/.minis-version`，升级安装时重新解压。构建脚本复现验证：从旧 zip 重新生成 1380 文件、树与 meta.db 完全一致；HAP 21.7 MB，111 项单测通过。`python3 -c` 实机冒烟待平板 |
| 2026-11-08 | 常驻沙箱与 `shell_execute` | 一次性模式每条命令都要冷启动内核（实机约 20 秒）。改为常驻 daemon：`/bin/sh` 作 PID 1 从 stdin 管道读脚本流，应用用「临时文件 + rename」原子提交 `id=<n>\n<命令>`，shell 自己打印 `[sandbox exit=%d id=<n>]`；`SandboxIsh` 变为单例客户端（串行队列、增量游标、90 秒启动窗口、超时停 daemon 并重启）。`shell_execute` 进 ToolCatalog，`ShellTool` 默认 900 秒 / 上限 3600 秒 / 输出 20000 字符，主代理与子代理共用同一 handler；workspace 与 memory 经 realfs 挂到 `/var/minis/*`。111 项单测与 HAP 构建通过；平板未连接，实机二连命令冒烟待做 |
| 2026-11-08 | 沙箱客户端加固 | 可选挂载目录缺失不再被当成致命启动失败（原生侧改 `[sandbox warn]`，应用侧先建 workspace/memory）；命令超过 harness 的 16 KB 缓冲时前置报错而不是等到超时；完成检测先只扫末尾 256 KB，命中后才整读，避免大输出下每 120 ms 全量读的二次方开销；会话输出过 24 MB 在命令间停一次 daemon 轮转文件；超时命令返回已打印内容（超过 512 KB 保留末尾）；用户点停止时 `SandboxIsh.cancel()` 停掉在跑命令并立即返回「命令已取消」，排队命令不受影响。116 项单测、HAP 通过 |
| 2026-11-08 | shell 权限门禁 | `shell_execute` 可写任意挂载目录，之前却不受「允许写入工作区文件」约束、没有逐工具开关、也不走逐次确认。现在在 `definitions()`/`execute()` 里按写工具处理（关闭时不暴露、直接调用被拒），`confirmWriteTools` 对 shell 同样弹窗，设置页逐工具列表加入「Linux 沙箱」并更新说明文案。111 项单测、HAP 通过 |
| 2026-11-08 | 终端输出清洗 | 新增 `core/Terminal.ets`（对齐 OpenMinis TerminalSanitizer）：按真实终端语义折叠 `\r` 覆写（含 `ESC[K` 擦除）、去 ANSI/OSC 序列与控制字符、合并空行；截断改为保留头尾并标注省略字符数，构建日志尾部的报错不再被砍掉；清洗前先预截 400k 字符限制中间分配。`ShellTool` 使用它。5 项新测试，116 项通过 |
| 2026-11-08 | 沙箱协议抽取 | `core/SandboxProtocol.ets` 承接与 `sandbox_ish.cpp` 共用的帧格式：结束标记解析（id 匹配、未闭合、负退出码）、`id=<n>\n<命令>` 负载、16 KB 上限（按 UTF-8 字节计，中文命令不再低估）、请求文件；`SandboxIsh` 改为调用。3 项新测试，119 项通过 |
| 2026-11-08 | 附件目录挂载进沙箱 | OpenMinis 的 shell 能直接处理 `/var/minis/attachments` 里的聊天图片；`sandbox_ish.cpp` 新增 `attachments=` 请求键与 realfs 挂载，`SandboxIsh`/`ShellTool`/设置页冒烟参数传 `filesDir/attachments`，`shell_execute` 说明同步更新。可选挂载缺失只警告，不影响启动。119 项单测、HAP 通过 |
| 2026-11-08 | shell 实时输出 | 对齐 OpenMinis 的 ToolLiveSheet：`ToolRuntime`/`ShellHandler` 增加可选 `onProgress`，`SandboxIsh` 轮询时每 700 ms 回传新增输出，`ShellTool` 清洗并只保留末尾 4000 字符，`AgentRuntime.runTool` 写入 `resultText` 后 `emit()`；工具卡片在折叠状态也显示「实时输出」最后 4 行，流式期间可见；停止生成时保留已有输出并标注「已停止，以上为不完整输出」。119 项单测、HAP 构建通过，实机待验 |
| 2026-11-08 | 技能目录挂载进沙箱 | `sandbox_ish.cpp` 新增 `skills=` 请求键，把 `filesDir/skills` 挂到 `/var/minis/skills`，脚本可直接读导入的 SKILL.md；`SandboxProtocol.sandboxRequestPayload` 改为 7 行、`SandboxOptions` 新增 `skills`，`ShellTool`/设置页冒烟/启动冒烟都传入；`shell_execute` 说明与 `SANDBOX.md` 同步。原生库重建（3.3 MB），119 项单测、HAP 构建通过 |
| 2026-11-08 | 子代理进度报告与角色名册 | `core/SubagentJob.ets` 新增 `parseProgressLevel`/`progressInterval`/`progressSignature`/`progressMessage`（none/frequent 15s/moderate 60s，有变化才发，正文保留末尾 800 字符）；`SubagentRunner` 每秒表定时读当前工具、已完成轮数与最后一条助手文本，经 `deliver` 以「[后台任务进度 …]」送回父对话，`wait=true` 时关闭，结束时清定时器；`AgentRuntime.injectInput` 支持按前缀替换未读报告，`Index.deliverSubagentResult` 在父对话空闲且上一条是未回答的进度消息时原地替换；`core/SubAgentRoster.ets` 定义内置 `helper` 与最多 10 个命名子代理（名字规范化、说明/附加提示夹取、去重、防御式解析），名册拼进系统提示，`subagent_task.agent` 选择角色，子会话标题与后台消息带角色名，resume 保留角色；`AppSettings.subAgents` 接入本地存储与备份；设置页新增名册列表与内联编辑器。137 项单测、HAP 构建通过 |
| 2026-11-08 | 桌面服务卡片 | `core/WidgetData.ets`（快照 JSON、空白折叠与截断、损坏输入回退）；`service/WidgetBridge.ets` 把当前会话标题、最近助手回复摘要（120 字符）与「生成中」标记写入 preferences，去重后 `formProvider.updateForm` 所有已登记卡片；`EntryFormAbility` 在 onAddForm/onUpdateForm 读取快照并登记/注销 form id；`widget/pages/WidgetCard.ets` 为 2×2 卡片（应用图标、标题、摘要、状态、点按回应用），`form_config.json` 每 30 分钟兜底刷新；主应用在 `persistNow`、切换会话与启动后发布。深链 `want.parameters.minis_deep_link` 已识别；本机 SDK 的 module schema 不接受 `shortcuts`，桌面快捷指令暂缺。1 项新测试、143 项通过、HAP 构建成功（`debug_widget` 产物已生成）；实机加卡待平板连接 |
| 2026-11-08 | MCP static OAuth | `core/McpOAuth.ets` 纯逻辑：`canonicalResourceUri`（去 fragment、去尾斜杠、校验 scheme/host）、`buildMcpAuthorizeUrl`（保留端点自带 query；PKCE S256 + state + offline/consent，可选 resource/scope）、`mcpTokenExchangeBody`/`mcpRefreshBody`（client secret 与 resource 仅非空时加入）、配置规范化与默认回调 `http://localhost:54546/callback`；`service/McpOAuth.ets` 用 CryptoArchitectureKit 生成 verifier/state、系统浏览器授权、粘贴回调换码、到期前 5 分钟单飞刷新；client secret 与令牌按服务 id 存 Asset Store，`McpServerConfig.oauth` 只存非密钥字段；`McpClient` 自动加 Bearer（手填 Authorization 优先），`McpRegistry.refresh` 并行取令牌；设置页新增 OAuth 开关/字段与登录面板（掩码、开始/完成/退出），删除服务时 purge；备份保留非密钥 OAuth 配置并强制 `clientSecretSet=false`。5 项新测试、142 项通过、HAP 构建成功；实机授权需可达的 OAuth 服务端，平板未连接 |
| 2026-11-08 | 多语言 | 18 种语言全部落地。`core/I18n.ets` 以中文原文为键，`t()` 按当前语言 → 英文 → 中文回退，显式空翻译有效；`service/I18n.ets` 启动读系统语言或已存选择，从 rawfile 同步加载英文与目标语言，切换时持久化并写 `i18nVersion` 触发重建；设置页新增语言区（18 种自称、即时切换）。69 个 .ets 文件、1,221 条中文文案完成包裹；模块级常量改为函数或在渲染时翻译，避免词条未加载时求值；持久化标记保持中文并用 `i18nVariants()` 识别旧消息。`scripts/i18n-merge.mjs` 生成 17 份词条（各 1,221 条，键集精确校验），`scripts/i18n-audit.mjs` 审计缺失/多余/空值。日期改为按语言选择数字顺序的 `shortMonthDay()`，避免直接拼接「月/日」翻译。145 项单测、HAP 构建通过（17 份词条已打包）；切换语言的实机观感待平板连接 |
| 2026-11-08 | ChatGPT Codex OAuth 与 Responses API | `core/ResponsesProtocol.ets`（约 500 行）纯逻辑：`/responses` 与 `/models` 地址推导、`call_id|item_id` 组合、system→`instructions`、消息转 typed input 项、扁平工具、自定义 id 的合成 `fc_syn_` 项、`prompt_cache_key`、SSE 解码按 item id 维护工具索引并只补发缺失的参数后缀；`service/OAuth.ets` 补齐 `hasCodexToken`/`codexMaskedToken`/`codexPlan`/`codexAccountId`/`beginCodexLogin`/`completeCodexLogin`（JSON 换码）/`refreshCodex`（表单刷新）与 `decorate` 注入；`ChatApi` 新增 Codex 请求头、Responses 流式与摘要、`/codex/models` 发现及 401/403 失效提示；`Types`/`LocalStore` 支持 `codex` 预设与 `oauthAccountId`；设置页新增预设卡、登录卡片（浏览器授权、回调粘贴、掩码、订阅、退出）、模型发现与发送前置检查。131 项单测、HAP 构建通过；实机需连网并登录后验证，平板当前未连接 |
| 2026-11-09 | 沙箱 M3/M4/M5 实机验证 | 平板连上后逐项验收：`--ps sandboxIsh true` 连跑三条命令仅 5.9 秒，第二条读到第一条的 `pwd=/tmp`、`MINIS_SMOKE=kept`；`python3 -c "import ssl, sqlite3"` 返回 3.12 与退出码 0；会话里让模型调用 `shell_execute` 执行 `uname -a; id`，工具卡片回传 `4.20.69-ish aarch64`、`uid=0(root)`、`[exit=0]`；`seq 1 200000` 的输出被头尾截断并标注中间省略 380037 字符；流式期间点「停止」能立即中断。设置页显示「已启动，内核常驻 · 占用 40.1 MB」，内核自检、应用内冒烟与「复制输出」均正常 |
| 2026-11-09 | 语言切换免重启 | 实机发现 ArkUI 局部更新不会重算 `t()` 文案：声明 `@StorageProp('i18nVersion')` 但 build 不引用它，页面文字不刷新；改用 `appRecovery.restartApp()` 能杀进程却不保证重启。现由 `Index` 用 `@Watch` 监听 `i18nVersion`，切换后把 `i18nEpoch` 加一，`build()` 两个完全相同但分属不同分支的 `if` 随奇偶切换，整棵页面子树销毁重建；重建时 `ChatView` 的 `autoFocusComposer` 传 false，不再弹出键盘。补齐语言区 3 条文案后 17 份词条各 1,224 条；实机 en→zh→en 往返，设置页、侧栏与聊天界面全部即时刷新，进程不重启，选择持久化 |
| 2026-11-09 | 日期按语言格式化 | 直接拼接「月/日」的翻译在 de/es/fil/hr/id/ms/th 下会得到「11Monat8Tage」，新增 `service/Format.ets` 的 `shortMonthDay()`：简中/繁中/日「M月D日」、韩「M월 D일」、英/菲「M/D」、德「D.M.」、克「D. M.」、其余「D/M」，相对时间不再翻译片段 |
| 2026-11-09 | 服务卡片实机排查 | 桌面加卡后在平板逐层定位空白卡片：确认 FormExtensionAbility 在独立进程执行且 `onAddForm` 返回合法绑定数据（`title=hi`、正文 121 字符），`ets/widgets.abc` 含 `WidgetCard` 的 `initialRender`/`rerender` 模块记录，桌面日志 `Add form success ... uiSyntax: 2`，`com.ohos.formrenderservice` 打印 `InitUIContent ... formData.size` 后不再加载页面；简化到 `Column`+`Text` 的最小卡片、排除资源与词条后仍空白，同机其它应用卡片正常。排查过程中确认卡片页面走专用 ArkTS 编译链（API 白名单会拒绝 `hilog`），并给 `onAddForm` 的 `I18nService.init` 加了防御性 try/catch。结论：疑似 OpenHarmony SDK 产出的 `widgets.abc` 与 HarmonyOS 表单渲染服务不兼容，暂列已知问题、卡片行改标 `[~]` |
| 2026-11-09 | 沙箱网络、Node 与常驻 Python | 补齐 OpenMinis 沙箱的联网与运行时：iSH 没有 slirp，但 `fs/sock.c` 把 guest 的 AF_INET/AF_LOCAL 调用直接转发到宿主 socket，App 已声明 `INTERNET`，因此 guest 与 App 共用网络；构建时写入 `resolv.conf`（223.5.5.5 / 1.1.1.1）和 `hosts`，启动时创建 `/dev/shm`（01777）。新增 `scripts/ish-rootfs-node.py`：固定 nodejs 22.23.4-r0、npm 10.9.1-r0（community）及 10 个依赖的 SHA-256，解包后从 ca-certificates 的 118 张 PEM 拼出 `/etc/ssl/certs/ca-certificates.crt`；同时把 iSH fork 的 `wasm-polyfill.js` / `fetch-polyfill.js` 放进 `/lib`（fork 只在文件存在时注入 `--require`），rootfs 从 1380 个文件增至 4499 个，zip 15 MB → 38 MB，`node` 为 aarch64 musl ELF（47 MB），iSH fork 在 exec 时自动注入 `--jitless --no-lazy`。新增 `python_execute` 工具与 `service/PythonService.ets`：guest 内常驻 `python3 -u -S -E` 服务（`rawfile/minis_py_srv.py`），请求走 `req.txt` 原子替换 + `out.txt` 完成标记，25 ms 轮询且仅在文件大小变化时读取，id 由 `seq.txt` 持久化递增；出错时才导入 `traceback`，空闲逐秒预导入常用模块；超时 `kill -9` 服务进程，`SandboxIsh.daemonGeneration()` 变化时立即返回；`SandboxIsh.beginHelper()/endHelper()` 让用户点「停止」时也能直接停掉 daemon 与解释器，而不是等工具超时。工具作为写工具受 `allowWriteTools`、逐工具开关与逐次确认约束，主代理与子代理共用；147 项单测通过。`ROOTFS_VERSION` 2→3，升级安装自动重新解压 |
| 2026-11-09 | 沙箱构建脚本只在需要时要求交叉工具链 | `--bundle-rootfs` 之前无论如何都会先编原生库，没有 meson/NDK 的机器无法只重建 rootfs。新增 `--rootfs-only`（跳过原生构建，直接从 `ISH_SRC/benchmark/create_fakefs.py` 重建 meta.db），并把 clang/meson/ninja/patch 的检查移到 `DO_NATIVE=1` 分支；`--rootfs-only` 只需 curl、zip、python3、sha256sum，实测在无 meson 环境生成 4499 条目、38 MB 的 `rawfile/ish-rootfs.zip` |
| 2026-11-09 | 沙箱离线预装 git | 沙箱是 Alpine，包管理器为 `/sbin/apk`（没有 apt）；原来的 rootfs 未装 git。新增 `scripts/ish-rootfs-git.py`：固定 `git 2.47.3-r0`、`libcurl 8.14.1-r3`、`pcre2`、`libidn2`、`libpsl`、`libunistring`、`ca-certificates-bundle` 的 SHA-256 并解包进 rootfs，跳过 ca-certificates-bundle 里指向 `/etc/ssl/certs` 的绝对软链（`etc/ssl1.1`）。`git-remote-https` 的 NEEDED 依赖全部就位，https 远端可走同一套宿主 socket 与 CA bundle。rootfs 4499 → 4707 个文件，zip 38 → 43 MB；冒烟 ISH4 增加 `git --version`，断言 `git_exit=0`；构建脚本加 `--no-git`。`ROOTFS_VERSION` 3→4 |
| 2026-11-10 | 沙箱补齐常用命令 | 系统提示承诺的 bash/curl/jq/pip/ssh/rsync 之前其实没装（curl、pip 只是描述里有），新增 `scripts/ish-rootfs-tools.py`：固定 bash 5.2.37、curl 8.14.1、jq 1.7.1 + oniguruma、py3-pip 24.3.1 + setuptools/packaging/parsing、openssh-client 9.9_p2（ssh/scp/sftp/keygen）、rsync 3.5.2（含 acl/lz4/popt/xxhash）、unzip 6.0 的 SHA-256；`/usr/bin/unzip` 原先是指向 busybox 的绝对软链，解包前先删掉。全部复用已有 libcurl/openssl/readline/libidn2/zstd。rootfs 4707 → 5747 个文件，zip 43 → 49 MB，展开约 144 MB；`pip install` 可用（无 `EXTERNALLY-MANAGED`）。冒烟新增 ISH6，逐个运行并断言 `tools_exit=0`；构建脚本加 `--no-tools`。`ROOTFS_VERSION` 4→5 |
| 2026-11-10 | 工作区资源链接 | OpenMinis 让模型用 `[文件名](minis://workspace/路径)` 引用生成的文件；之前本实现只接受 http/https，这类链接会落到「不支持的链接类型」。新增 `core/MinisResource.ets`（解析 workspace/attachments 作用域、百分号解码一次、复用 `normalizeRelativePath` 拒绝绝对路径与 `..`），`MarkdownView` → `MessageBubble` → `ChatView` → `Index` 增加 `onOpenMinis` 回调；点击 workspace 链接直接打开 `WorkspaceSheet` 并定位到文件所在的目录与预览，关闭时清空初始路径。附件链接暂提示查看消息内图片。`shell_execute` 描述告诉模型可以这样链接文件。148 项单测通过、构建通过 |
| 2026-11-09 | 沙箱预热与自检降噪 | 针对「shell 命令感觉慢」定位：daemon 常驻时单条命令只有轮询与清洗开销，慢的是每个应用进程的第一次调用要等内核启动，以及超时/停止后 daemon 被杀导致的再次冷启动。新增 `SandboxIsh.warm()` 与 `warmSoon()`：首屏就绪 2 秒后后台预热，命令超时、用户停止、输出轮转后 300–800 ms 自动重启；rootfs 未解压时不预热（不偷偷解包），预热进行中来的命令会等待同一次启动，避免双内核。另修自检探针：`unshare` 被 seccomp 以 SIGSYS 杀掉会让系统记录 native crash，默认直接报告已知结论，只有 `--ps sandboxProbeDeep true` 才实测。构建通过、145 项单测通过；实机计时待平板重连 |
| 2026-11-10 | 浏览器动作补齐 | `service/BrowserTool.ets` 从 12 个动作扩到 19 个 OpenMinis 动作：新增 navigate/get_text/execute_js 别名、scroll（可选容器选择器）、get_page_info（URL/标题/视口/滚动/页面尺寸/链接数）、find_elements（前 50 个元素的文本/坐标/链接）、hover（mouseover/mouseenter/mousemove）、get_readable（克隆 DOM 后去脚本/样式/导航/页脚再取正文）、get_backbone（按深度输出 DOM 骨架）、get_cookies/set_cookies（`fetchCookieSync`/`configCookieSync`，set 先合并已有 Cookie）、set_user_agent（default/mobile/desktop/自定义）、set_viewport（隐藏视图尺寸随 `@State` 调整）、scroll_and_collect（按 `item_selector` 或整页文本去重收集，最多 20 屏）、wait_for_dom_stable（每 250 ms 对比 DOM 签名，连续两次相同即稳定）、screenshot（`webPageSnapshot` + ImagePacker，保存到 `workspace/.minis-browser/shot-<ts>.png`，返回 Markdown 链接）、fetch（App 侧 `http.createHttp` 下载原始字节，带当前页面 Cookie，按 Content-Disposition/URL/类型命名，存到 `.minis-browser/` 并返回 `minis://workspace` 链接）。`new_tab`/`close_tab`/`list_tabs` 明确返回不支持。`HiddenBrowser` 由 1×1 改为全屏透明（`opacity(0)` + `hitTestBehavior(None)`），并注册工作区路径与视口回调；`ToolCatalog` 新增 direction/amount/item_selector/scroll_count/cookies/user_agent/max_depth/timeout/viewport_width/viewport_height。新增 1 项 schema 测试，149 项通过、HAP 构建签名成功；截图、Cookie 与动态页实机验证待平板连接 |
| 2026-11-10 | Markdown 图片与附件预览 | `core/Markdown.ets` 新增 `Image` 块：独立成行的 `![alt](url)`（可带 title）解析为图片块并保留 alt，行内图片仍按文本处理；`MarkdownView` 解析来源：http(s)/`data:image` 直接加载，`minis://workspace` 映射到 `filesDir/workspace`，`minis://attachments` 经 `AttachmentStore.absolutePath`，裸相对路径按工作区文件处理（复用 `normalizeRelativePath` 防越界），宽度 100%、最高 360、`ImageFit.Contain`。`Index` 新增全屏图片预览 `bindContentCover`：点击图片类 `minis://` 链接（含浏览器截图）打开大图，工作区非图片仍进文件预览；附件非图片提示不可预览。新增 1 项解析测试，150 项通过、HAP 构建签名成功；真机图片加载与双 cover 交互待平板连接 |
| 2026-11-10 | Cookie 读取脱敏与视口重置 | 对齐 OpenMinis 的 Cookie 冒烟约定：`get_cookies` 不再把原始值写进工具结果，只返回名称与长度，匹配项写入 `.minis-browser/env_cookies_<ts>.sh`（`export MINIS_COOKIE_<NAME>='值'`，单引号转义），shell 里 `source` 后使用；新增 `keyword` 与 `fuzzy`（默认包含匹配）过滤。`set_viewport` 新增 `reset=true` 恢复整屏视口；`wait_for_dom_stable` 默认等待 10000 ms、轮询 500 ms，与参考实现一致。150 项测试通过、HAP 构建签名成功；Cookie 文件与 `source` 流程待平板验证 |
| 2026-11-10 | 本地 HTML 预览 | `browser_use` 的 open/navigate 之前会把 `minis://...` 拼成 `https://minis://...`。现在先按 `parseMinisResource` 识别 workspace/attachments，交给 `BrowserHost.resolveResource` 映射为逐段百分号编码的 `file://` URL；隐藏 Web 打开 `fileAccess(true)`，并注册 attachments 根目录。这样模型可以导航到工作区里的 HTML 小应用，页面内相对 JS/CSS/图片由 file:// 正常加载。未调用 `customizeSchemes`，HTML 内绝对 `minis://` 子资源仍会失败（相对路径可绕过）；`fetch` 仍只走 http(s)。构建签名成功，150 项测试通过；实机本地页面与相对资源待平板验证 |
| 2026-11-10 | 源码对照补充与浏览器行更正 | 逐文件对照 iOS/Android 源码，新增第 13 节 12 项清单外缺口（排队发送、会话分组、浏览器历史/下载/设置、自动标题、@ 文件提及、视频附件、用量/存储、会话级 MCP/记忆面板、模型快测、配置审计、外观细项、会话角标）。更正第 6 节内置浏览器：此前「参考实现只有单页、没有多标签/历史/下载/Cookie」的结论只适用 iOS，Android 的 `ui/browser/BrowserSheet.kt` 有标签栏，`BrowserHistorySheet`/`BrowserDownloadsSheet`/`BrowserSettingsSheet` 分别提供历史、下载与 UA/视口/Cookie 设置；状态改为 `[~]`，本实现已有 4 标签池但缺这三块。旧完成记录保留不改，以此条为准 | `core/DeepLink` 增加 `minis://action/camera_chat`（返回 `kind=camera`），`voice_chat` 明确返回 null；`Index.applyDeepLink` 对 camera 先 `createChat()` 再 `takePhoto()`，对应 OpenMinis 桌面长按「新对话（相机）」；新增 2 条断言（camera 解析、voice 拒绝），150 项测试通过，构建签名成功；相机弹窗行为待平板验证 | `WorkspaceSheet` 对 `.html`/`.htm` 不再显示源码：新增 `previewHtml`/`previewPath` 状态与独立 `WebviewController`，`reveal` 与 `openFile` 识别扩展名后切换分支，预览区用 `Web(file://<workspace>/<逐段编码路径>)` 渲染 400vp 高页面，开启 `fileAccess`/`javaScriptAccess`/`domStorageAccess`/`onlineImageAccess` 与混合内容，相对资源可加载；关闭预览或换文件时清空状态并换新控制器。与 OpenMinis `FilePreviewScreen` 的 `HtmlPreview` 对齐；`minis://workspace/page.html`、`minis://browser/page.html` 深链与聊天链接因此都能看到渲染结果。构建成功待签名，平板验证见 N23 | 复刻 OpenMinis Android 的离屏 WebView 池：新增 `components/InlineMathHost.ets`（根组件透明 ArkWeb，加载 `katex-render.html`，用 `runJavaScript('renderMath(..., false, …)')` 排版后经 `webPageSnapshot` 截成 `PixelMap`，4 秒测量超时、8 秒就绪超时）与 `service/InlineMathCache.ets`（按 LaTeX/字号/深浅色缓存，串行队列，重复公式去重，上限 256 条，淘汰只丢引用）。`MdInline` 新增可选 `math` 字段保留原始 LaTeX，`MarkdownView` 在正文、标题、列表、引用、表格单元格中把 Unicode 近似 `Span` 原位替换为 `ImageSpan`（基线对齐、`px2vp` 尺寸），图片未就绪或失败时保持近似文本；`plainMath`（离屏快照卡）仍跳过 Web。`test-core` 增加 `math` 字段断言，150 项通过；构建成功留 HAP 待签名；透明 Web 的渲染与截图像素透明度需按 N22 在平板确认 | `core/DeepLink` 按 OpenMinis 路由表扩展：`sessions` 别名、`session/<id>/<资源路径>`、`open?session&path`（含只有 path 的 launcher 形式）、`action/new_chat`、`settings[/子页]`、`views/alarm`；查询参数与路径百分号解码一次，空 id 与未知 host 仍返回 null。`Index` 新增 `openLinkedResource`：去掉前导 `/` 后按 `browser`/`workspace`/`attachments` 作用域调用 `openMinisResource`，裸路径当工作区文件；`settings/scheduled*` 与 `views/alarm` 打开定时任务面板，其余 settings 打开设置；`minis://file` 在参考实现中并不存在，文档中删除该说法。新增 10 组断言，150 项测试通过、HAP 构建签名成功；`hdc shell aa start` 各路由待平板验证 |
| 2026-11-10 | 浏览器资源作用域与工具缩略图 | 新增 `minis://browser/<file>`（映射 `workspace/.minis-browser/`），对齐 OpenMinis 截图/下载链接；`screenshot` 与 `fetch` 的 Markdown 链接和 `imageUri` 改为该作用域，`open/navigate` 也可打开浏览器产物。另行修复工具卡片缩略图：`read_image` 与截图之前把工作区相对路径写进 `imageUri`，而 `MessageBubble` 一律按附件名解析，真机会指向不存在的文件；现在工具结果用 `minis://workspace|browser` URI，`AttachmentStore.imagePath` 按作用域解析，附件/生成图仍用 `attachment:`，并对旧会话里带 `/` 的裸相对路径做工作区存在性回退。`MarkdownView` 与工作区链接点击同步支持 `browser`。150 项测试通过、HAP 构建签名成功；截图缩略图、`minis://browser` 链接与旧会话图片待平板验证 |
| 2026-11-10 | 分享图片进来 | `ShareReceiver` 之前只处理文本，图片分享被忽略。`core/SharePayload` 新增 `imageUrisFromShare`：合并 `want.uri` 与 `ability.params.stream`、按 MIME/扩展名识别 png/jpg/jpeg/webp/gif/bmp、去重并截到 4 张；`ShareReceiver` 把原始 URI 以 JSON 放进 `AppStorage.pendingShareImages`，`Index` 在 `AttachmentStore.init` 之后逐张 `saveFromUri`，加入待发送附件并给出视觉能力提示。`module.json5` 的 `sendData` skill 增加 `scheme=file, type=image/*`；文本分享路径不变。新增 3 组断言，150 项测试通过、HAP 构建签名成功；真实图库分享面板与 URI 权限待平板验证 |
| 2026-11-10 | 相机拍照 | 输入框在「图片」旁新增「拍照」，用 `@kit.CameraKit` 的 `cameraPicker.pick` 启动系统相机（`PickerMediaType.PHOTO`、后置），无需相机权限；`resultCode=0` 时把 `resultUri` 交给 `AttachmentStore.saveFromUri`，与相册选择共用 10 MB/格式校验、待发送附件列表和视觉能力提示；取消或失败不产生附件。新增 3 条文案并同步 17 份词条，`i18n-audit` 1227/1227 全通过。150 项测试、HAP 构建签名成功；系统相机 UI 与拍摄结果待平板验证 |
| 2026-11-10 | 附件文本预览 | `minis://attachments/...` 链接之前除了图片只提示「无法预览」。`Index` 新增只读文本预览覆盖层：非图片附件交给 `previewWorkspaceFile`（attachments 根目录 + 相对路径，沿用越界校验与 256 KB 限制），标题为文件名，正文等宽、可复制、可滚动，二进制显示具体原因；图片仍走全屏查看器。150 项测试通过、HAP 构建签名成功；附件文本/二进制与关闭交互待平板验证 |
| 2026-11-10 | 本地 HTML 绝对子资源 | 之前 `file://` 页面里的 `<script src="minis://workspace/...">` 因未注册 scheme 无法加载。现在 `EntryAbility.onCreate` 在首个 Web 组件之前调用 `WebviewController.customizeSchemes` 注册 `minis`（CORS/fetch/standard/local 全开）；`HiddenTab` 在 `onControllerAttached` 给每个 controller 安装 `WebSchemeHandler`，`workspace`/`attachments` 请求经 `parseMinisResource` 校验后读文件，按扩展名给出 MIME（HTML/JS/CSS/图片/字体/音视频/wasm 等）与 `Access-Control-Allow-Origin: *`，64 MB 上限，越界与不存在返回 `ERR_FILE_NOT_FOUND`。主文档仍走 `file://`，相对资源行为不变。150 项测试通过、HAP 构建签名成功；自定义 scheme 子资源在真机的实际加载与 CORS 行为待平板验证 |
| 2026-11-10 | 浏览器多标签 | 补齐 `browser_use` 最后 3 个动作：`new_tab`（经 UI 回调挂载新 `HiddenTab`，3 秒内等 controller attach，最多 4 个）、`close_tab`（拒绝关闭最后一个或未知 id，关闭活动页自动切到首个剩余页）、`list_tabs`（按 id 排序列出 URL，当前页标 `*`）。`BrowserHostRegistry` 从单 controller 改为 `Map<tabId, WebviewController>`，加载等待、URL 记录、attach/detach 全部按标签页隔离；`tab_id` 在动作分发前切换目标页。UI 侧 `HiddenBrowser` 拆为 `HiddenTab` + `ForEach(tabIds)`，新增 active id 回调，活动页 `zIndex(1)` 置顶以避免透明层被合成器遮挡。`ToolCatalog` 增加 `tab_id` 说明，schema 测试同步。150 项测试通过、HAP 构建签名成功；多标签并发、截图目标页与关闭后状态待平板验证 |
| 2026-11-10 | 生成中排队发送 | 对齐 OpenMinis 的运行中排队：新增 `core/PromptQueue.ets`（FIFO 入队/按注入数扣减，均返回新数组）与 `AgentRuntime.injectUserMessage()`——生成中收到的消息连同图片 part 进入 `pendingInputs`，在下一次模型请求边界作为真实用户消息写入历史；`AgentCallbacks.onInputsDrained(count)` 回传本次注入条数，`Index` 据此同步扣减 UI 队列，避免停止后重复发送。生成中输入框显示「↑ 排队」按钮，点按不再被「请先停止当前生成」拒绝；待发送列表上方显示「排队中 N」与「清空」。停止、出错或工具循环结束后 `flushQueuedPrompts()` 自动续发队首；切换会话时丢弃属于旧会话的条目并提示「已取消」。`sendQueuedPrompt` 复用 API Key/地址校验、自动压缩、会话创建与标题逻辑；附件经 `queuedParts()` 走同一 `image_url` 通路。新增 2 项队列单测，152 项通过、HAP 构建签名成功；真实生成中注入时机与停止后续发待平板验证 |
| 2026-11-10 | 自定义会话分组 | 新增 `core/SessionFolder.ets`：`SessionFolder` 与 `normalizeSessionFolders` 放在 `Types` 供 `AppSettings.sessionFolders` 引用，纯函数负责 `addFolder` / `renameFolder` / `removeFolder` / `setFolderCollapsed` / `newFolderId` / `groupByFolder` / `countFolderSessions`，全部返回新数组。`SessionMeta` 增可选 `folderId`，`LocalStore` 读写时归一化，`SessionExport` 导出保留、普通导入清空、备份恢复保留。侧栏无搜索词且存在分组时改为文件夹视图：标题行可折叠、显示会话数、`＋` 即时在分组内新建；「未分组」置底且仅非空时出现；空分组仍显示。新增「管理分组」弹窗（新建/重命名/删除）与会话菜单「移动到分组」；删除分组把成员退回未分组。新增 8 条中文文案并补齐 17 份词条，`i18n-audit` 1235/1235；新增 3 项单测，155 项通过、HAP 构建签名成功；侧栏折叠、新建与移动的实机交互待平板验证 |
| 2026-11-10 | 浏览器历史 / 下载 / 设置 | 新增 `core/BrowserHistory.ets`：`parseHistory`/`recordHistory`（只收 http(s)、同 URL 去重、新标题覆盖旧标题、上限 200）、`filterHistory`（标题与 URL 不区分大小写）、`parseDownloads`/`upsertDownload`（按目标路径去重、上限 100）、`formatBytes`；`service/BrowserStore.ets` 用 preferences 持久化历史、下载、UA 预设/自定义值与宽视口。`BrowserPage` 工具栏新增 🕘/⬇/⚙：历史面板可搜索、清空、点击重开；下载面板通过 `setDownloadDelegate` 把 Web 下载写进 `filesDir/browser-downloads`（文件名清洗、重名加时间戳），完成后记录名称/大小/时间，成功项以 `file://` 打开，可清空；设置面板提供默认/移动/桌面/自定义 UA（`onControllerAttached` 应用并刷新）、宽视口开关、当前站与全部 Cookie 清除。`fileAccess` 改为开启以支持本地下载预览。新增 11 条文案并补齐 17 份词条（1246/1246），新增 5 项单测（160 项通过），HAP 构建签名成功；真实下载、UA 生效与 Cookie 清除待平板验证，下载进度/角标、Cookie 按域列表、视口宽高仍缺 |
| 2026-11-10 | 自动生成会话标题 | 新增 `core/SessionTitle.ets`：`cleanTitle` 去掉模型返回的引号、「标题：」/`Title:` 前缀与句末标点，按 20 字截断并加省略号；`titleTranscript` 取首条用户消息与首条助手消息（各 600 字），超过 8 条消息时再补最近一条助手消息（300 字）；`hasAnswer` 要求已有非失败的用户/助手文本。`ChatApi` 把四种协议的非流式摘要抽成 `requestModelText(settings, sessionId, transcript, instruction, maxTokens)`，新增 `generateSessionTitle()`（标题指令、`max_tokens` 200、OpenAI 兼容/Anthropic/Gemini/Codex 全走原通道，OpenCode 会话头保持不变）。`Index` 在每轮 settle 后调用 `maybeAutoTitle()`：仅当标题仍等于 `titleFrom(首条用户消息)` 或「新对话」时请求一次，成功写 `SessionMeta.title`、`refreshSessions()` 并 `persistSoon()`，失败静默保留派生标题；`titleJobs` 记录已请求的会话，编辑首条消息时重置。会话操作菜单新增「重新生成标题」，手动请求会提示「正在生成标题…」、失败原因与「已更新标题」。新增 10 条文案并补齐 17 份词条（1256/1256），新增 3 项单测（163 项通过），HAP 构建签名成功；真实模型标题质量、四协议通道与离线回退待平板验证 |
| 2026-11-10 | @ 文件提及 | 新增 `core/Mention.ets`：`activeMention` 只把草稿末尾的 `@query` 当作提及（`@` 必须在开头或空白后、query 不含空白、长度上限 120），`replaceMention` 原位替换为 `@path `，`filterMentionFiles` 跳过目录并按相对路径不区分大小写匹配、可限条数。`service/WorkspaceFiles.listWorkspaceFiles()` 递归遍历工作区（深度 4、跳过隐藏目录与依赖/构建目录、上限 300，返回文件完整相对路径）。`ChatView` 新增 `workspaceRoot` 属性与提及面板：输入 `@` 后显示最多 5 条文件名/相对路径，点按插入，回车选中当前高亮（首条），工具栏加 `@` 按钮；插入后草稿尾部带空格，菜单自动关闭。新增 3 项单测（166 项通过），HAP 构建签名成功；方向键切换与光标在草稿中间时的提及待后续（TextArea 未暴露光标位置），真机键盘行为待平板验证 |
| 2026-11-10 | 视频/音频附件与内联播放 | `Types` 新增 `filePart()`（`PART_FILE` + uri + mime），协议层不发送媒体 part，只发送随附的 `[视频]/[音频] 文件名` 文本。`AttachmentStore.mimeFor` 增加 mp4/webm/mov/m4v/mkv 与 mp3/m4a/wav/ogg/aac/flac，新增按类型的大小上限（视频 100 MB、音频 20 MB、图片 10 MB），`dataUrl()` 拒绝音视频以免把大文件塞进请求。`Index` 新增 `pickVideos()`（`PhotoViewPicker` + `VIDEO_TYPE`）与 `pickAudio()`（`AudioViewPicker`），共用 `attachPicked()` 生成附件项；发送时视频/音频生成文本提示 + 文件 part，图片仍走 `imagePart`。`ChatView` 工具栏新增「视频」「音频」按钮，附件预览对媒体显示 ▶/♪ 占位块；`MessageBubble` 用户气泡用 `Video` 控件内联播放（视频 240×150、音频 240×54，`controls(true)`、不自动播放）。新增 6 条文案并补齐 17 份词条（1262/1262），新增 1 项单测（167 项通过），HAP 构建签名成功；真实视频/音频选择、播放与大小上限待平板验证 |
| 2026-11-10 | 用量统计与存储管理 | 新增 `core/UsageStats.ets`：`dayKey` 按本地时区生成 `YYYY-MM-DD`；`parseUsage` 丢弃非数组/坏 JSON/缺日期或模型的条目并把计数归一为非负整数；`recordUsage` 按「日期+模型+预设」合并并累加请求数，超过 `USAGE_RECORD_LIMIT=400` 时按日期保留最新行；`usageTotal`/`usageByModel`/`usageByDay` 分别给总量、按模型（总 token 降序）与按日（倒序、可限条数）聚合。`service/UsageStore.ets` 用 preferences `minis_usage_store` 只存这组计数，不落提示词；`Index.recordUsage()` 在每轮结束找最后一条 `totalTokens > 0` 的助手消息，按消息 id 去重（上限 300），以 `activeModelId()` 记一次请求。新增 `service/StorageUsage.ets`：`directoryUsage` 递归统计文件数/字节（深度 8、忽略消失项），`clearDirectory` 删除目录内容但保留目录本身、单个文件失败不中断。设置页新增「用量统计与存储」：累计输入/输出/请求数、按模型前 5、最近 7 天、二次确认清空统计；附件/工作区/浏览器下载三行占用与二次确认清理按钮。新增 23 条文案并补齐 17 份词条（1285/1285），新增 6 项单测（172 项通过），HAP 构建签名成功；真实累计、跨日归并、清理后的占用刷新与权限行为待平板验证 |
| 2026-11-10 | 会话级 MCP 开关与记忆面板 | 新增 `core/McpOverrides.ets`：`normalizeMcpDisabled` 去空白/空串/重复，`isMcpDisabled` 判断，`setMcpDisabled` 返回新数组（关闭时移到末尾，打开时移除）。`SessionMeta` 增 `mcpDisabled?: string[]`；`LocalStore` 归一化读写，`Index.forkSession` 复制，`SessionExport` 导出与备份恢复保留、普通导入清空。`McpRuntime` 构造增加 `disabledServers`：`definitions()` 跳过这些服务发现的全部工具，`execute()` 对直接调用返回「该 MCP 服务已在本会话关闭。」。会话参数弹窗新增 MCP 列表，逐服务 Toggle，全局关闭项禁用并标注。`MemoryStore` 增加最近 50 条读写日志（代理写入、检索、手动保存）与 `logs()`。聊天标题栏/更多菜单新增「记忆」，面板展示当前注入文本、所有可编辑记忆文件（TextArea + 保存/撤销回打开时原文）与近期日志。新增 18 条文案并补齐 17 份词条（1303/1303），新增 1 项单测（173 项通过），HAP 构建签名成功；真实 MCP 工具过滤、跨设备导出与记忆面板交互待平板验证 |
| 2026-11-10 | 浏览器下载进度与按域 Cookie | `core/BrowserHistory` 新增 `webOrigin`（提取 `scheme://host[:port]`，拒绝非 http(s)）与 `cookieOrigins`（当前页优先、历史去重、可限条数）。`BrowserPage` 的下载委托增加 `onDownloadUpdated`：按 guid 维护 `ActiveDownload`（名称、`getPercentComplete()`，未知为 -1 显示 …），下载面板顶部显示进度条，工具栏 ⬇ 带进行中数量（>9 显示 9+），完成/失败即移除。设置页 Cookie 区新增按站列表：打开面板时取当前页与历史的 origin（最多 20），逐个 `fetchCookieSync` 计数，可单站清除；保留全部清除。视口仍只有宽视口开关，数值宽高因 ArkWeb 未暴露 API 未做。新增 2 条文案并补齐 17 份词条（1305/1305），新增 1 项单测（174 项通过），HAP 构建签名成功；真实下载进度、角标与逐站 Cookie 清除待平板验证 |
| 2026-11-10 | 模型快速测试 | 新增 `core/ModelTest.ets`：`ModelTestOutcome { ok, text, message, elapsedMs }` 与 `modelTestLine`——失败优先显示服务端错误，成功但空正文提示「模型没有返回内容」，否则输出「耗时 ms · 首段回复」，换行/制表压成空格并截断到 80 字。`ChatApi.requestModelText` 改为导出以便复用非流式请求；`Index.testModel(id)` 克隆当前设置、仅替换 `modelId`、经 `OAuthService.decorate` 补 OAuth 头后发一条 `maxTokens=32` 的「这是一次连通性测试，请只回复 OK。」。`ModelPicker` 每行新增「测试」按钮，测试中显示「测试中…」，返回后就地在模型行下显示结果；自定义模型 ID 输入后有独立测试入口。可同时测试多个模型，状态按 id 分开保存，单个结果不会覆盖另一个。新增 6 条文案并补齐 17 份词条（1311/1311），新增 1 项单测（175 项通过），HAP 构建签名成功；真实模型连通性、不同供应商的鉴权分支与行内布局待平板验证 |
| 2026-11-10 | 配置变更审计与回滚 | 新增 `core/ConfigAudit.ets`：`ConfigPair`/`ConfigAuditEntry`、`CONFIG_AUDIT_LIMIT=200`、密钥键名单、结构化键名单与可还原键名单；`diffConfig` 按 key 比较编码值并生成带时间戳的条目，`mergeConfigAudit` 新条目前置并按上限截断，`parseConfigAudit` 丢弃缺 key/时间或类型不对的行；`auditValueLabel` 把密钥显示为「已设置/未设置」、字符串数组显示为「N 项」、空串显示「（空）」并压平截断到 48 字。`service/ConfigAuditStore.ets` 的 `configSnapshot` 覆盖 44 个设置键（密钥只存 set 标记，MCP/模型覆盖/分组/子代理只存条目数），用 preferences `minis_config_audit` 持久化。`Index.applySettings` 与 `pickModel` 在写入前记录差异；设置页新增「配置变更记录」：最近 30 条显示键、旧值 → 新值、时间，可还原的条目带「还原」（写回旧值并自然产生一条反向记录），结构化/密钥行标「仅记录」，支持二次确认清空。还原仅支持标量、字符串与字符串数组，并校验枚举与数字。新增 17 条文案并补齐 17 份词条（1328/1328），新增 4 项单测（179 项通过），HAP 构建签名成功；真实设置保存、批量改动、还原后界面刷新与重启后记录保留待平板验证 |
| 2026-11-10 | 启动恢复、思考展开、自动聚焦与三处字号 | 新增 `service/UiStateStore.ets`（preferences `minis_ui_state`，键 `lastSessionId`）：`selectSession`/`createChat`/fork 时记住当前会话，`bootstrap` 优先打开该会话，已删除或为空则回退到最新会话。`AppSettings` 新增 `autoExpandThinking`、`autoFocusInput`、`autoTitleEnabled`、`messageFontScale`、`inputFontScale`：默认分别为关、开、开、1、1；`cloneSettings` 与 `LocalStore.normalizeSettings` 在旧数据缺字号时回退到 `fontScale`，`Backup` 同步读写，`ConfigAudit` 把五项列入可还原键与快照。`applyAppearance` 写入 AppStorage；`MessageBubble` 在 `autoExpandThinking` 时让结算后的思考保持展开（用户手动切换仍优先）；`ChatView` 监听 `streaming` 由 true 变 false，在 120ms 后把焦点还给 `composerInput`；`maybeAutoTitle` 受 `autoTitleEnabled` 控制。字号拆为界面/消息/输入框三组：`MarkdownView` 与用户气泡读 `messageFontScale`，输入框读 `inputFontScale`，侧栏与设置继续用 `fontScale`。设置页新增三组字号选择与三个开关，并更新说明。新增 10 条文案并补齐 17 份词条（1338/1338），新增 5 条断言（179 项通过），HAP 构建签名成功；重启恢复、结算后键盘弹出、旧数据迁移与三处字号实机观感待平板验证 |
| 2026-11-10 | 会话列表状态角标 | `SessionMeta` 新增可选 `statusBadge`，`core/Types` 的 `normalizeSessionBadge` 只接受 `background`/`interrupted`/`syncing`；`LocalStore.normalizeSessionMeta` 读盘时校验并清掉崩溃遗留的 `syncing`。`SidebarView` 在标题旁渲染角标（已中断=危险色、同步中=主题色、后台=次要色），并把角标加入 `ForEach` key，避免复用旧行不刷新。`Index` 在用户停止时标「已中断」，WebDAV 同步全程标「同步中」并在 `finally` 清除，启动时为仍有未处理后台结果的会话标「后台」；`selectSession`、`runAgent` 开始与启动恢复当前会话时清除。新增 2 条文案并补齐 17 份词条（1340/1340），新增 5 条 `normalizeSessionBadge` 断言（179 项通过），HAP 构建签名成功；角标在真机的显示、切换会话清除与同步瞬时状态待平板验证 |
| 2026-11-10 | 长粘贴转工作区附件 | 新增 `core/Paste.ets`：`PASTE_FILE_THRESHOLD=15000`、`hugePasteInsertion()` 用公共前后缀从 TextArea 的新旧值还原插入段（支持开头/中间/末尾与替换）、`pasteFileName()` 生成毫秒级本地文件名、`pasteRelativePath()`/`isPastedAttachment()` 只认 `minis://workspace/pasted/` 下的 text/plain。`ChatView` 在 onChange 检测到单次插入超过阈值时回调宿主，成功后先让 TextArea 接受输入、下一 tick 恢复去掉长文的草稿；附件列表对粘贴文件显示 📄 文件名。`Index.attachHugePaste()` 同步写入工作区并加入待发送附件；发送时（含排队注入 `queuedParts`）改为「[粘贴文本] 相对路径（可用 read_file 读取）」文本 + 文件 part，不再把正文塞进气泡。工具关闭或远程沙箱时返回 false，原文保留在输入框，避免模型读不到文件。新增 2 条文案并补齐 17 份词条（1342/1342），新增 2 项测试（181 项通过），HAP 构建签名成功；真机长按粘贴、草稿恢复与 read_file 读取待平板验证 |
| 2026-11-10 | 自动归入分组 | `core/SessionTitle.ets` 新增 `TitleSuggestion { title, folder }`、`matchFolder()` 与 `parseTitleSuggestion()`：在回复里找第一个 `{` 到最后一个 `}` 解析 `{"title","folder"}`，`title` 缺失/非字符串或清洗后为空时回退纯文本路径；`folder` 为 `null`、空串或不在提供列表内时一律返回空串，只有与提供名称大小写不敏感完全一致才保留。`ChatApi.titleInstruction(folders)` 在提供分组时改用五句 JSON 提示并附「已有分组：A、B」列表，未提供时保持原纯标题提示；`generateSessionTitle(..., folders = [])` 透传。`Index.offeredFolderNames()` 仅在 `autoGroupingEnabled` 且会话尚无 `folderId` 时收集 `sessionFolders` 名称（trim、大小写不敏感去重）；`requestTitle()` 解析后先写标题再 `applyTitleFolder()`，按 id 写回分组，绝不新建分组。`AppSettings` 新增 `autoGroupingEnabled`（默认 `true`），接入 `cloneSettings`、`LocalStore.normalizeSettings`、`Backup` 与 `ConfigAudit` 可还原键/快照；设置页新增开关与说明。新增 7 条文案并补齐 17 份词条（1349/1349），新增 1 项测试（182 项通过），HAP 构建签名成功；真实模型返回的 JSON 解析、分组自动归入与开关关闭行为待平板验证 |
| 2026-11-10 | 工具卡片「从此处重跑」与停止 | `core/Types.ets` 新增 `toolPartKey()`（id 为空时用 `名称:参数`）与 `rerunCutFromTool()`：在指定助手消息里按 key 找到工具调用，保留其之前的文本/工具块，删除该调用、同消息之后的块与所有后续消息；目标前没有任何实质内容时丢弃整条助手轮次；找不到调用或裁完没有历史可发时返回 `null`。`MessageBubble` 运行中的卡片标题右侧新增红色停止块（点击走 `onStop`，与输入框停止一致；OpenMinis 同样没有单工具取消 API），展开的已结算卡片新增「从此处重跑」。`ChatView` 透传 `onStop`/`onRerunTool`；`Index.rerunFromTool()` 在非流式时裁剪会话、同步 `messageCount`/`updatedAt`、刷新列表后 `runAgent` 续跑，流式时提示先停止，裁剪失败提示「无法从此处重跑」。新增 3 条文案并补齐 17 份词条（1352/1352），新增 1 项测试（183 项通过），HAP 构建签名成功；真机停止块触控、块边界裁剪后的续跑与分组/标题联动待平板验证 |
