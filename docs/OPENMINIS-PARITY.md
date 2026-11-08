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
| - [ ] | 多选导出 | 选中多个会话导出 zip | 见「分享 / 导出」 | P2 |
| - [ ] | 消息时间戳 | 相对时间 | 已有 `formatRelative` | — |
| - [x] | token 用量显示 | 每条回复的输入/输出 token | 解析流式 `usage` 并持久化到消息 | P0 |
| - [x] | 上下文压力提示 | 接近窗口上限变色 | 顶栏显示 `上下文 12.3k`（最近一次 prompt+completion） | P0 |
| - [x] | 失败重试 | 一键重发上一条 | 错误回复显示「重试」，复用重新生成 | P1 |
| - [x] | 斜杠命令 | `/clear` `/compact` `/memory` `/thinking` | `/new` `/clear` `/compact` `/memory` `/thinking` `/help`；记忆开关为全局而非每会话，思考用请求级 `reasoning_effort`（无模型元数据） | P1 |
| - [ ] | 消息内图片预览 | 附件缩略图、点开大图 | 依赖附件功能 | P2 |
| - [ ] | 表格 / LaTeX / 语法高亮 | Markdown 完整渲染 | 当前仅基础 Markdown | P2 |
| - [ ] | 消息内链接点击 | 内置浏览器打开 | `Want` 拉起系统浏览器 | P2 |

## 2. Agent 运行时

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 流式 tool_calls | 分片累加 `index/id/name/arguments` | `AgentRuntime.accumulate` | — |
| - [x] | 工具结果回填 | assistant.tool_calls + tool 消息 | `ToolProtocol.toApiMessages` | — |
| - [x] | 轮次上限可配置 | `MAX_AGENT_TURNS = 200` | 默认 200，1–1000，可续跑 | — |
| - [x] | 中断工具补结果 | 避免悬空 tool_call | `interruptToolCalls` + `INTERRUPTED_RESULT` | — |
| - [x] | 本地事件日志 | 结构化日志、脱敏 | `EventLog` + `AppLogger` | — |
| - [~] | 子代理 `subagent_task` | 最多 3 个并行、steer/cancel/resume、10 分钟 | 独立 `AgentRuntime` + 内存子会话、并行上限 3、10 分钟超时、嵌套 2 层；无 steer/resume，子会话不落库 | P1 |
| - [x] | 工具并行执行 | 同一轮多个 tool_calls 并发 | `Promise.all` 并发执行，结果回到各自 part | P1 |
| - [x] | 上下文压缩（compact） | `/compact` 摘要旧消息 | 保留最近 3 个用户轮次，旧轮次由模型摘要替换 | P1 |
| - [x] | 工具循环检测 | 重复调用同一工具时警告 | 连续相同 `name+args` 达 3 次时在工具结果前追加警告 | P2 |
| - [ ] | tool call 配对修复 | 补齐缺失的 tool 结果 | 已有 synth result，可加强 | P2 |
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
| - [ ] | 列目录 | 通过 shell `ls` | 已有 `list_dir` | — |
| - [x] | 搜索文本 | 通过 shell `grep` | `search_text` | — |
| - [x] | HTTP 抓取 | 浏览器引擎 `fetch` | `fetch_url` | — |
| - [x] | 当前时间 | 通过 shell `date` | `now` | — |
| - [x] | 读图片 / 视觉 | `read_image` 注入视觉上下文 | `read_image` 读取工作区图片，工具消息后追加合成 user 图片消息；本机模式、默认关闭 | P1 |
| - [ ] | 浏览器自动化 | `browser_use` 22 动作 | ArkWeb 子集（导航/点击/取值/JS） | P2 |
| - [x] | 持久记忆 | `memory_write` / `memory_get` | `filesDir/memory`，每日文件 + GLOBAL.md，关键词检索 | P1 |
| - [~] | 子代理 | `subagent_task` | 本机模式已实现，见 2. 子代理；远程模式不暴露 | P1 |
| - [ ] | 图像生成 | `minis-model-use` 调用 `/images/generations` | 可选，取决于订阅模型 | P3 |
| - [ ] | 工具开关 UI | 逐工具启用/禁用 | 目前只有总开关与写入开关 | P2 |
| - [ ] | 工具权限确认 | 危险操作弹出确认 | 写入默认关闭，可加逐次确认 | P2 |

## 4. Provider 与模型

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | OpenAI 兼容 | 自定义 base URL | 已支持 | — |
| - [x] | OpenCode Go 会话头 | `x-opencode-session` 域门控 | 已支持，含负例测试 | — |
| - [x] | 拉取模型列表 | `/models` | 「获取」按钮 | — |
| - [ ] | Anthropic 原生协议 | Messages API + 流式 | 新增 provider 分支 | P2 |
| - [ ] | Gemini 原生协议 | `generateContent` | 新增 provider 分支 | P2 |
| - [ ] | OAuth 登录 | Anthropic / Copilot / Codex | 设备码或浏览器回跳 | P2 |
| - [ ] | 模型组 | fallback / 负载均衡 | 按顺序重试 | P3 |
| - [ ] | thinking level | 逐模型推理档位 | 请求体 `reasoning_effort` 等 | P2 |
| - [ ] | fast mode | 优先级队列 | 取决于上游支持 | P3 |
| - [ ] | 逐模型参数覆盖 | temperature/top_p/headers/extra_body | `AppSettings` 增加 per-model 表 | P2 |
| - [ ] | 模型能力元数据 | models.dev 目录、上下文长度 | 内置少量 + 拉取 | P2 |

## 5. 记忆 / 技能 / 人格

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 长期记忆 | `GLOBAL.md` + 每日 `YYYY-MM-DD.md` | `filesDir/memory/`，每轮注入最近 3 天 + GLOBAL | P1 |
| - [x] | 记忆检索 | `memory_get` 模糊搜索 | 关键词打分，返回带日期的片段 | P1 |
| - [x] | 记忆开关 | 每会话可关闭 | `AppSettings.memoryEnabled`，默认关闭 | P1 |
| - [x] | 记忆查看 / 编辑 UI | 记忆页 | 设置内嵌文件选择 + 编辑器，可保存 GLOBAL.md 与任意 YYYY-MM-DD.md | P2 |
| - [ ] | Skills | `SKILL.md` + frontmatter，按会话启用 | 导入本地目录，注入 top-N 描述 | P2 |
| - [ ] | Skills 斜杠命令 | 技能注册为 `/命令` | 与斜杠命令合并 | P2 |
| - [ ] | Soul / 人格 | `SOUL.md` 身份层 | 系统提示词扩展 + 预设 | P2 |
| - [ ] | 提示词预设库 | ——（OpenMinis 也没有） | 不做 | - |

## 6. MCP / 浏览器 / 工作区

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [ ] | MCP HTTP / SSE | JSON-RPC、工具发现 | `fetch` 实现 JSON-RPC 客户端 | P2 |
| - [ ] | MCP stdio | 启动本地进程 | 鸿蒙不能 spawn，做不了 | - |
| - [ ] | MCP OAuth | PKCE | 可复用浏览器/Web 组件 | P3 |
| - [ ] | 内置浏览器 | 多标签、历史、下载、Cookie | ArkWeb + 动作脚本 | P2 |
| - [ ] | 工作区文件浏览 | `minis://workspace` 文件页 | 新增文件列表页 + 预览 | P2 |
| - [ ] | 附件命名空间 | `minis://attachments` | 应用私有目录 | P2 |
| - [ ] | 深链 | `minis://` 打开会话/文件 | `Want` + `uris` 配置 | P3 |
| - [ ] | 从其他应用分享进来 | Share Extension / ShareReceiver | `Want` + `ohos.want.action.sendData` | P2 |

## 7. 设备能力（Native offloads）

OpenMinis 把设备能力包装成沙箱内 CLI。鸿蒙侧对应 Kit，按需接入 v1。

| | 能力 | OpenMinis | 鸿蒙方案 | 优先级 |
|---|---|---|---|---|
| - [ ] | 剪贴板 | `android-clipboard` / `apple-clipboard` | `pasteboard` | P2 |
| - [ ] | 通知 | `notification` | `notificationManager` | P2 |
| - [ ] | 日历 | `calendar` | `CalendarKit` | P3 |
| - [ ] | 通讯录 | `contacts` | `ContactsKit` | P3 |
| - [ ] | 照片 / 相机 | `photos` | `PhotoPicker` / `CameraKit` | P2 |
| - [ ] | 定位 | `location` | `LocationKit` | P3 |
| - [ ] | 天气 | `weather` | 第三方 API | P3 |
| - [ ] | 语音识别 | `speech` / ASR | `CoreSpeechKit` | P2 |
| - [ ] | 朗读 TTS | `speak` | `CoreSpeechKit` | P2 |
| - [ ] | 无障碍自动化 | Android AccessibilityService | 无对等能力 | - |
| - [ ] | Shizuku 特权 | Android 专用 | 不适用 | - |
| - [ ] | HealthKit / HomeKit / NFC | iOS 专用 | 不适用 | - |

## 8. 后台任务 / 定时任务

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 切后台继续生成 | 前台服务 / 后台模式 | 已实现，见 2. 后台继续生成 | P1 |
| - [ ] | 生成状态通知 | 通知栏显示进度 | `notificationManager` + 进度模板 | P2 |
| - [ ] | 定时任务 | AlarmManager / Shortcuts | `agent-powered reminder` 或后台代理提醒 | P3 |
| - [ ] | 任务运行历史 | 列表 + 结果 | 依赖定时任务 | P3 |

## 9. 分享 / 导入导出 / 同步

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [ ] | 导出会话 JSON | 单会话 zip（含附件） | 写文件 + 系统分享 | P2 |
| - [x] | 导出 Markdown | 对话转 Markdown | 纯函数生成，经系统文档选择器保存（含思考与工具结果） | P2 |
| - [ ] | 多会话导出 | 多选打包 | 依赖导出 | P3 |
| - [ ] | 单轮截图分享 | 渲染一张图 | `componentSnapshot` | P3 |
| - [ ] | 系统分享 | 文件/链接/文本 | `ShareKit` | P2 |
| - [ ] | 备份 / 恢复 | 本地归档、加密 | 导出 zip + 恢复 | P2 |
| - [ ] | 远程备份 | rclone（SMB/WebDAV/S3/SFTP） | WebDAV 起步 | P3 |
| - [ ] | 多端同步 | iCloud（iOS） | 自建 WebDAV，端到端加密 | P3 |
| - [ ] | 分享链接 / 回放卡 | ——（OpenMinis 也没有） | 不做 | - |

## 10. 设置 / 外观 / 本地化

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 深色模式 | 跟随系统 | 资源限定词 | — |
| - [x] | 工具与沙箱设置 | 工具开关、沙箱后端 | `SettingsSheet` | — |
| - [x] | 事件日志开关 | 日志查看器 | 开关 + 清空 | — |
| - [ ] | 主题色 / 字号 | 主题、字体缩放 | `AppStorage` + 主题表 | P2 |
| - [ ] | 多语言 | 18 种 | `resources/base/element/string.json` 扩展 | P2 |
| - [ ] | 首次引导 | 配置 provider / 沙箱 | 三步引导页 | P2 |
| - [ ] | 每会话参数 | 模型、思考档位、系统提示词 | `SessionMeta` 扩展 | P2 |
| - [ ] | 应用图标切换 | 备用图标 | 鸿蒙不支持动态图标 | - |
| - [ ] | 快捷指令 / 小组件 | iOS Widget / Shortcuts | 服务卡片 | P3 |
| - [ ] | 回车键行为 | Enter 发送或换行 | 设置项 | P2 |
| - [ ] | 常亮 / 自动聚焦 | 小选项集合 | `window` API | P3 |
| - [x] | 日志查看器 UI | 应用内查看 | 设置页内嵌最近 200 条，格式化为时间/事件/耗时/详情，可收起 | P2 |

## 11. 安全 / 隐私 / 诊断

| | 功能 | OpenMinis 行为 | MinisHarmony 方案 | 优先级 |
|---|---|---|---|---|
| - [x] | 日志脱敏 | 环境变量、Key 脱敏 | `redactSecrets` | — |
| - [x] | 工作区路径 jail | 沙箱根目录 | `normalizeRelativePath` + symlink 检查 | — |
| - [x] | 写入需显式开启 | 工具权限 | `allowWriteTools` | — |
| - [x] | 密钥安全存储 | Keychain / EncryptedPrefs | `Asset Store Kit`；不可用时回退 preferences 并保留明文兼容 | P1 |
| - [ ] | 应用锁 | Face ID / 生物识别 | `userIAM.userAuth` | P2 |
| - [ ] | 加密备份 | `BackupCrypto` | AES-GCM + 口令派生 | P3 |
| - [ ] | 崩溃 / 诊断导出 | 诊断包 | `hiAppEvent` + 日志打包 | P3 |
| - [ ] | 请求检查器 | LLM 请求日志 | 日志增加 request id（不含正文） | P2 |

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
