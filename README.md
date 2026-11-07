# Minis Harmony

**纯血鸿蒙 6.0+ 平板优先的 AI 对话客户端。**
面向 OpenCode Go 订阅用户，原生 ArkTS / ArkUI 实现，无 Android 兼容层。

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
- 模型发现走 OpenCode 的 `/inference/go/v1/models`，推理走
  `/inference/go/openai/v1/chat/completions`。

---

## 已实现

| | |
|---|---|
| **平板双栏** | ≥ 840vp 自动侧栏 + 对话区；窄屏切换为单栏并支持返回 |
| **OpenCode Go 预设** | 一键填入当前基址，自动注入 `x-opencode-session` |
| **OpenAI 兼容** | 任意兼容 `/chat/completions` 的服务，可自定义基址与模型 |
| **流式输出** | SSE 增量解析，思考过程（`reasoning_content` / `reasoning`）折叠展示 |
| **本地会话** | 会话、消息、模型、设置持久化在本机，重启可恢复 |
| **Markdown** | 标题、列表、引用、分割线、行内样式、代码块复制 |
| **交互细节** | 停止生成、切换模型、搜索对话、长按删除、API Key 显示切换、拉取模型列表 |
| **深色模式** | 跟随系统，使用 HarmonyOS 资源限定词 |

## 尚未实现（明确边界）

这不是 OpenMinis 的完整功能移植。第一阶段聚焦「平板上的高质量 Chat + OpenCode Go」，
以下能力没有包含：

- 板载 Linux / Alpine 沙箱（`proot`、`ish`）、shell 工具；
- 浏览器自动化、Skills、持久记忆、MCP、工具调用循环；
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
   `https://opencode.ai/inference/go/openai/v1`）；
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
  └─ startChatStream(settings, id, …) ─┤
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

## 工程结构

```text
MinisHarmony/
├── AppScope/                         # 应用级 bundle 配置与图标
├── entry/
│   └── src/main/
│       ├── module.json5              # Stage 模型、tablet/2in1/phone、INTERNET
│       ├── ets/
│       │   ├── entryability/         # UIAbility
│       │   ├── pages/Index.ets       # 状态编排、会话、流式生命周期
│       │   ├── components/           # 侧栏、对话、气泡、Markdown、设置、模型选择
│       │   ├── core/                 # 纯逻辑：类型、SSE、URL 规则、Markdown
│       │   └── service/              # HTTP 流、OpenCode 头、preferences 持久化
│       └── resources/                # 颜色（含 dark）、字符串、图标
├── scripts/test-core.mjs             # Node 下的纯逻辑测试
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
- 基址规范化、chat / models URL；
- 会话头注入条件（opencode 域 + 非草稿 ID）；
- SSE 分块、CRLF、多 data 行、尾部 flush；
- OpenAI 流式 chunk（content / reasoning / finish / DONE / error）；
- Markdown 块级与行内解析。

当前结果：**11 项全部通过**。

另外做了两项静态检查：

- `python3 scripts/check-brackets.py`：全部 ArkTS 文件括号配平；
- `tree-sitter-arkts`：全部 15 个 `.ets` 文件解析 0 错误（ArkUI 声明式语法）；
- `ohos-typescript`：`core/` 与 `service/` 的 8 个非 UI 文件语法诊断 0 条。

> 说明：本机没有 DevEco Studio / HarmonyOS SDK，因此**没有执行 hvigor 编译、单元测试或
> 真机运行**。上述检查只覆盖语法与纯逻辑，不覆盖 ArkUI API 签名、资源引用和签名配置。
> 工程按 API 20 的 Stage 模型编写，首次在 DevEco 中打开时如遇 API 名称差异，请在
> DevEco 的 API 提示下调整。

---

## 安全与隐私

- 对话、设置、API Key 只保存在应用私有 `preferences` 中，不会上传到本机以外，
  除非你主动请求你配置的服务端。
- API Key 目前以明文保存在应用沙箱内。对安全要求更高时，可改用
  **Asset Store Kit**（`@kit.AssetStoreKit`）保存密钥，见路线图。
- 建议只使用 `https://` 基址；自定义 `http://` 明文地址能否使用取决于系统网络策略。
- 卸载应用会清除全部本地对话与密钥。

## 许可证

本项目以 [MIT](LICENSE) 发布。

OpenMinis 以 GPLv3 发布，dsh-Go 以 AGPL-3.0 发布。本项目只参考了它们的公开行为与
产品设计，没有复制其源代码；如果你要把本项目与上述代码合并，请自行评估许可证兼容性。
