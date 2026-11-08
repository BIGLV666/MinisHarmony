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
| - [x] | 上下文压缩（compact） | `/compact` 摘要旧消息 | 保留最近 3 个用户轮次，旧轮次由模型摘要替换 | P1 |
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
| - [x] | 读图片 / 视觉 | `read_image` 注入视觉上下文 | `read_image` 读取工作区图片，工具消息后追加合成 user 图片消息；本机模式、默认关闭 | P1 |
| - [x] | 浏览器自动化 | `browser_use` 22 动作 | ArkWeb 子集：隐藏 Web 视图常驻，`browser_use` 支持 open / click / type / text / html / eval / back / forward / reload / wait / title / url；页面加载最多等 20 秒，返回内容截断；远程沙箱模式不暴露 | P2 |
| - [x] | 持久记忆 | `memory_write` / `memory_get` | `filesDir/memory`，每日文件 + GLOBAL.md，关键词检索 | P1 |
| - [x] | 子代理 | `subagent_task` | 本机模式完整实现（后台投递、status/steer/cancel/resume、排队、超时、崩溃恢复），见 2. 子代理；远程沙箱模式仍不暴露子代理 | P1 |
| - [ ] | 图像生成 | `minis-model-use` 调用 `/images/generations` | 可选，取决于订阅模型 | P3 |
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
| - [ ] | OAuth 登录 | Anthropic / Copilot / Codex | 设备码或浏览器回跳 | P2 |
| - [ ] | 模型组 | fallback / 负载均衡 | 按顺序重试 | P3 |
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
| - [ ] | 日历 | `calendar` | `CalendarKit` | P3 |
| - [ ] | 通讯录 | `contacts` | `ContactsKit` | P3 |
| - [x] | 照片 / 相机 | `photos` | 系统相册 `PhotoViewPicker` 多选（最多 4 张、10 MB），复制到应用私有目录；相机拍摄未接 | P2 |
| - [ ] | 定位 | `location` | `LocationKit` | P3 |
| - [ ] | 天气 | `weather` | 第三方 API | P3 |
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
| - [ ] | 定时任务 | AlarmManager / Shortcuts | `agent-powered reminder` 或后台代理提醒 | P3 |
| - [ ] | 任务运行历史 | 列表 + 结果 | 依赖定时任务 | P3 |

## 9. 分享 / 导入导出 / 同步

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 导出会话 JSON | 单会话 zip（含附件） | 带 `app/version/exportedAt` 信封的 JSON，保留全部 part 与工具结果；系统文档选择器保存（无附件，故不打包 zip） | P2 |
| - [x] | 导出 Markdown | 对话转 Markdown | 纯函数生成，经系统文档选择器保存（含思考与工具结果） | P2 |
| - [x] | 多会话导出 | 多选打包 | 侧栏多选 → 单个 JSON bundle；导入端同时接受 bundle 与单会话文件 | P3 |
| - [ ] | 单轮截图分享 | 渲染一张图 | `componentSnapshot` | P3 |
| - [ ] | 系统分享 | 文件/链接/文本 | `ShareKit` | P2 |
| - [~] | 备份 / 恢复 | 本地归档、加密 | 整库备份可导出为单个 JSON（全部会话 + 设置快照，API Key / 沙箱 Token / MCP 与模型请求头全部剔除），导入时合并会话并恢复非密钥设置、保留当前密钥；加密包仍未做 | P2 |
| - [ ] | 远程备份 | rclone（SMB/WebDAV/S3/SFTP） | WebDAV 起步 | P3 |
| - [ ] | 多端同步 | iCloud（iOS） | 自建 WebDAV，端到端加密 | P3 |
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
| - [x] | 日志查看器 UI | 应用内查看 | 设置页内嵌最近 200 条，格式化为时间/事件/耗时/详情，可收起 | P2 |

## 11. 安全 / 隐私 / 诊断

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 日志脱敏 | 环境变量、Key 脱敏 | `redactSecrets` | — |
| - [x] | 工作区路径 jail | 沙箱根目录 | `normalizeRelativePath` + symlink 检查 | — |
| - [x] | 写入需显式开启 | 工具权限 | `allowWriteTools` | — |
| - [x] | 密钥安全存储 | Keychain / EncryptedPrefs | `Asset Store Kit`；不可用时回退 preferences 并保留明文兼容 | P1 |
| - [x] | 应用锁 | Face ID / 生物识别 | 设置「启动时验证系统锁屏」；启动调用 `userAuth`（PIN/人脸/指纹，ATL3），无可用认证时放行 | P2 |
| - [ ] | 加密备份 | `BackupCrypto` | AES-GCM + 口令派生 | P3 |
| - [ ] | 崩溃 / 诊断导出 | 诊断包 | `hiAppEvent` + 日志打包 | P3 |
| - [x] | 请求检查器 | LLM 请求日志 | 每次模型请求生成 8 位 `req`，写入 `model_start/done/error` 与同轮工具事件；日志查看器显示 `req=`，不含正文 | P2 |

## 12. 平台特性（不可移植 / 需替代）

| | 功能 | 说明 |
|---|---|---|
| - [-] | 板载 Linux 沙箱 | PRoot/iSH 依赖 exec；鸿蒙普通 HAP 不可行，QEMU 另行评估 |
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
