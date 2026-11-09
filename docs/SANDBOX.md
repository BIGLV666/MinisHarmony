# 本机 Linux 沙箱（内核）设计与实测

> 目标：在平板**本机**给 Agent 一个真正的 Linux 用户态（shell、Python、文件系统），
> 不依赖远程电脑。远程工具服务保留，但不是本文件的重点。
>
> 结论先行：HarmonyOS 禁止应用 exec 任何 ELF，PRoot 路线不可行；唯一可行的是
> **进程内内核模拟**，即把 OpenMinis iOS 使用的 iSH（ARM64 分支）移植到
> HarmonyOS 的原生子进程里。

## 1. 实机实测（2026-11-08，HarmonyOS 6 / HongMeng Kernel 1.12.0 / aarch64）

测试方式：应用内 `childProcessManager.startNativeChildProcess` 启动
`libsandboxprobe.so:Main`，在原生子进程中执行检查，结果写入应用私有目录后由
ArkTS 读取。代码见 `entry/src/main/cpp/sandbox_probe.cpp`，设置页
「工具与沙箱 → 运行内核自检」可复现；也可以用
`hdc shell aa start -a EntryAbility -b app.minis.client --ps sandboxProbe true`
触发，结果在 `hilog -T MinisHarmony`。

| 能力 | 结果 | 说明 |
| --- | --- | --- |
| 原生子进程 | 可用 | pid / uid 正常，SELinux 上下文 `debug_hap` |
| exec `/system/bin/sh` | **EACCES** | `access` 与 `posix_spawn` 都被拒绝 |
| exec 应用 libs 目录自带 ELF | **EACCES** | `/data/storage/el1/bundle/libs/arm64/...` 也不允许 |
| exec 复制到应用数据目录的 ELF | **EACCES** | 先复制成功，执行仍被拒绝 |
| ptrace（TRACEME + CONT） | 可用 | 系统调用跟踪路线在权限上可行 |
| `mmap(PROT_EXEC)` 匿名内存 | 可用 | threaded-code 解释器 / JIT 的前提成立 |
| mount namespace（unshare） | **超时/被杀** | 3 秒硬超时，不能依赖 |
| CapEff | `0` | 无任何 capability |
| Seccomp | `2`（filter） | 系统调用受过滤 |
| NoNewPrivs | `0` | — |

由此排除：

- **PRoot**：无论 proot 二进制放在哪，最终都要 exec rootfs 里的程序或 loader，
  实测全部 EACCES。
- **chroot / mount namespace / overlayfs**：无 capability，且 `unshare(CLONE_NEWNS)` 不返回。
- **调用系统 shell**：`/system/bin/sh` 对应用不可执行。

保留下来的两条路：

1. 进程内**内核模拟**（iSH / QEMU user 类）：自己加载 guest ELF、自己解释 guest
   指令和 syscall，不依赖宿主 exec。mmap(PROT_EXEC) 可用，Asbestos 的
   threaded-code 分派不需要运行时代码生成，最契合。
2. 远程 Linux 工具服务：已有 `RemoteToolRuntime` 协议，但用户明确要本机沙箱，
   只作为备选。

## 2. 选定方案：iSH ARM64 内核跑在原生子进程里

OpenMinis 在 iOS 上用的就是 `OpenMinis/ish-arm64` 分支：Asbestos 同架构
threaded-code 解释器 + iSH 内核（`KERNEL_ISH=1`）+ fakefs。它不 exec 宿主
程序，guest 的 `execve` 由 iSH 内核自己加载 ELF，因此不受 HarmonyOS exec
限制。本仓库参考克隆在 `/home/biglv/project/OpenMinis/deps/ish`。

目标形态：

```
ArkTS  ── tool call ──►  LocalToolRuntime（本机模式）
                              │
                              ▼
                 Native child process（libishsandbox.so:Main）
                 ├─ iSH 内核 + Asbestos（guest aarch64）
                 ├─ fakefs / realfs：Alpine minirootfs
                 ├─ /var/minis/workspace ← 应用 workspace/
                 ├─ /var/minis/memory    ← 应用 memory/
                 ├─ /var/minis/attachments ← 应用 attachments/（聊天图片等）
                 ├─ /var/minis/skills    ← 应用 skills/（导入的 SKILL.md）
                 └─ 管道协议：start / write / read / signal / exit
                              │
                              ▼
                 Alpine userland: /bin/sh, busybox, python3, ...
```

关键设计：

- **入口**：`libishsandbox.so` 导出 `Main(NativeChildProcess_Args)`，由 ArkTS
  `childProcessManager.startNativeChildProcess('libishsandbox.so:Main', ...)` 启动。
- **通信**：不依赖 PTY（HarmonyOS 没有可用的 `/dev/ptmx` 保证）。请求文件
  （`rootfs=` / `output=` / `commands=` / `workspace=` / `memory=` /
  `attachments=` / `skills=`，一行一个键）
  由 ArkTS 写一次；命令文件 `id=<n>\n<命令>` 每次原子替换（临时文件 + rename）。
  harness 把它包成 `{ … }; printf "\n[sandbox exit=%d id=<n>]\n" "$?"` 写进
  guest shell 的 stdin 管道，输出与标记都追加到 output 文件，应用按字符游标
  增量读取。标记由 shell 自己打印：guest PID 1 退出会带走整个原生进程。
- **文件系统**：Alpine minirootfs 以 `rawfile/ish-rootfs.zip` 随 HAP 分发，
  首次启动用 `@ohos.zlib.decompressFile` 解到应用私有目录 `filesDir/ish-rootfs/`；
  不把 rootfs 放在 `/data/local/tmp`，避免 `debug_hap` 域访问
  `data_local_tmp` 的 SELinux 限制，应用也天然拥有 rootfs 的读写权限。
  workspace、memory、attachments、skills 都已映射进 guest 的 `/var/minis/*`
  （skills 是导入的 `.md` 文件，脚本可以直接读取）。
- **预装 Python 3**：minirootfs 只有 busybox + apk，而 guest 没有网络，
  运行期无法 `apk add`。因此 `scripts/ish-rootfs-python.py` 在构建时按固定
  版本与 SHA-256 下载 Python 3.12.16 及 17 个依赖（musl、openssl、sqlite、
  readline 等，约 13.5 MB 压缩 / 39 MB 展开），直接解包进 rootfs 目录，
  再由 `create_fakefs.py` 重建 `meta.db`。zip 从 3.8 MB 增至 15 MB。
  `apk` 的已安装数据库不包含这些包（无网络时也不会用它），这是已知取舍。
  应用侧用 `filesDir/ish-rootfs/.minis-version` 标记 rootfs 版本，升级安装
  时旧 rootfs 会被重新解压，否则新 HAP 仍会跑旧文件系统。
- **隔离边界**：iSH 内核本身是边界：guest 只能看见 rootfs 和显式挂载的目录。
  当前 iSH 构建没有 slirp 网卡，guest 内没有外网；需要联网的数据由宿主
  `fetch_url` 获取，设置页文案不承诺沙箱内可联网。
- **生命周期**：每个应用进程一个常驻沙箱内核（`SandboxIsh` 单例），`/bin/sh`
  作为 PID 1 从 stdin 管道读命令，`cd`、环境变量在多次调用之间保留。
  应用侧命令队列串行执行；超时或用户点「停止」都无法在 guest 内中断，
  直接停掉整个 daemon（`SandboxIsh.cancel()`），在跑的调用立刻返回
  「命令已取消」，排队中的调用不受影响、下一条命令重新启动内核。
- **安全**：工具仍受 `toolsEnabled`、`allowWriteTools`、逐工具开关约束；
  guest 内不能访问应用私有目录以外的宿主路径（fakefs 只挂载显式目录）。
- **许可**：iSH 为 GPLv2，随应用分发时需要保留版权与源码获取方式；已在
  仓库根目录 `THIRD_PARTY_NOTICES.md` 登记 iSH、Alpine rootfs 与离线 Python
  包，并写明对应源码的获取/重建方式。

## 3. 里程碑

- [x] M1 交叉编译：用 OHOS NDK（aarch64-linux-ohos）构建
      `libish.a`、`libish_emu.a`、`libfakefs.a`，SQLite 用 amalgamation 交叉编译，
      VDSO 用 OHOS clang 构建；产物在 `entry/libs/arm64-v8a/libishsandbox.so`，
      可由 `scripts/build-ish-ohos.sh` 从 iSH 源码重建。
- [x] M2 启动内核：原生子进程里 `ish_init` + 挂载 Alpine rootfs，
      跑通 `/bin/sh -c 'echo hi'`，结果经管道回到 ArkTS。
      （2026-11-08 平板实机冒烟通过：`aa start ... --ps sandboxIsh true` 后，
      hilog 读到完整回传 —— `hello-from-ish`、`Linux localhost 4.20.69-ish
      SUPER AWESOME Nov  8 2026 18:47:42 aarch64 Linux`、`uid=0(root)
      gid=0(root)`、`3.21.3`，即内核启动、fakefs 挂载、`/bin/sh -c`
      执行与文件回传全部成功。首次失败的 900002 已修：`zlib.decompressFile`
      要求目标目录事先存在，解压前先 `mkdirSync(staging, true)`。
      结束标记：第一次冒烟只拿到输出、没有 `[sandbox exit=`，应用误报
      「未结束」。原因是 guest 的 PID 1 退出时 iSH 会把整个原生进程一起收掉，
      harness 主线程来不及补写标记。改为让 shell 自己在命令末尾
      `printf "[sandbox exit=%d]" "$?"`，不依赖进程收尾；第二次实机冒烟
      输出以 `[sandbox exit=0]` 结束，应用在约 20 秒内返回。guest 超时
      60 秒、应用侧轮询 150 秒作为兜底。）
- [x] M3 工具接入：本机模式新增 `shell_execute`，超时/输出上限/取消；
      工作区与记忆目录挂载。
      （2026-11-08 已实现：常驻 daemon 客户端、`ShellTool`、目录 realfs 挂载、
      输出上限 20000 字符、默认 900 秒 / 上限 3600 秒、超时停 daemon；
      主代理与子代理共用同一 handler，HAP 与核心单测通过。
      2026-11-09 平板实机：`--ps sandboxIsh true` 连续执行两条命令，第一条
      `cd /tmp; export MINIS_SMOKE=kept; ...`，第二条读到 `pwd=/tmp`、`smoke=kept`，
      三条命令总计 5.9 秒，证明内核只冷启动一次。会话中直接让模型调用
      `shell_execute` 执行 `uname -a; id; echo result=42`，工具卡片原样回传
      `Linux localhost 4.20.69-ish ... aarch64`、`uid=0(root)`、`[exit=0]`。）
- [x] M4 稳定性：连续命令、并发、长输出、Python/Node 冒烟；
      应用退后台与子进程回收。
      （2026-11-08 已把 Python 3.12.16 与依赖离线预装进 rootfs，构建可复现
      `scripts/ish-rootfs-python.py`；Node 未预装，按需再评估。
      2026-11-09 平板实机：`python3 -c "import ssl, sqlite3"` 输出 3.12 且
      `python_exit=0`；流式回答中点「停止」立刻中断；`seq 1 200000` 的输出
      被头尾截断（中间 `[... 380037 characters omitted ...]`，保留约 20048 字符），
      模型能据此判断输出不完整。
      2026-11-09 生命周期实测：启动后 `ps` 可见
      `app.minis.client:Native_libishsandbox0`；按 Home 切后台 20 秒后它仍常驻
      （下次命令免冷启动）；`aa force-stop app.minis.client` 后 3 秒再查 `ps`，
      相关进程 0 条，native child 随应用进程一起回收，没有孤儿内核。
      长输出：应用只在输出文件大小变化时重新读取，先只读末尾 256 KB 找
      结束标记（标记总是 shell 最后打印的行），命中后才整读一次；超过
      4 MB 放慢轮询。会话累计输出超过 24 MB 时在命令之间主动停一次
      daemon 轮转文件，超过 64 MB 硬停、只返回开头 64 KB。超时命令返回
      它已经打印的内容（超过 512 KB 时保留末尾），末尾的报错不会丢。
      返回给模型的文本经 `core/Terminal.ets` 清洗（去 ANSI/OSC、折叠
      `\r` 覆写、去控制字符、合并空行）后按 20000 字符头尾截断。并发
      请求在应用侧排队，共用同一个 guest shell。）
- [x] M5 体验：设置页沙箱状态、首次解压进度、磁盘占用、重置 rootfs。
      （2026-11-08 已加：设置页「沙箱状态」行显示已就绪/需重新解压/尚未解压、
      rootfs 占用与「内核常驻」状态；「重置」需两次点击确认，调用
      `SandboxIsh.reset` 停 daemon 后删除 rootfs，下次使用重新解压。
      `zlib.decompressFile` 没有进度回调，解压期间只显示一次性提示，没有百分比。
      2026-11-09 平板实机：设置页显示「已启动，内核常驻 · 占用 40.1 MB」；
      「运行内核自检」输出 pid、uid、内核版本与 `system_sh/spawn_system_sh/
      libs_exec/data_exec = 13 (Permission denied)`、`CapEff=0`、`Seccomp=2`；
      「启动 Linux 沙箱」在应用内输出 `hello-from-ish`、`uid=0(root)`、
      `3.21.3`、`[exit=0]`，并提供「复制输出」。）

## 4. 移植风险

| 风险 | 验证方式 | 退路 |
| --- | --- | --- |
| Seccomp 过滤 iSH 需要的 syscall | M2 启动即暴露 | 在 guest 内核里绕开；必要时改用纯 fakefs |
| `mmap` 固定地址/大地址空间被拒 | M2 | 调整 iSH 内存布局参数 |
| pthread / futex / signal 行为差异 | M2/M4 | 打平台补丁（`platform/linux.c` 已有 Linux 宿主层） |
| SQLite 在应用沙箱的锁/WAL | M2 | 改 journal 模式或只读 rootfs + 可写 overlay |
| Alpine rootfs 体积（含 Python 约 15 MB 压缩、39 MB 展开） | M1/M4 | 已离线预装 Python；如需减重可再拆出独立 zip，首次使用时解包 |
| GPLv2 合规 | 发布前 | 附源码与许可，提供获取方式 |

## 5. 构建与复现

### 5.1 重建沙箱库

```bash
# 只需要 meson、ninja、patch、curl、unzip、python3 和 OHOS NDK。
# 默认从 /home/biglv/project/OpenMinis/deps/ish 取源码。
scripts/build-ish-ohos.sh --clean

# 重新生成 Alpine fakefs 并更新 HAP 内置的 rawfile/ish-rootfs.zip
scripts/build-ish-ohos.sh --bundle-rootfs

# 调试时也可以把 rootfs 推到 /data/local/tmp（SELinux 可能拒绝应用访问）
scripts/build-ish-ohos.sh --rootfs --push
```

脚本做的事情：复制 iSH 源码 → 应用 `scripts/ish-ohos/*.patch` → 下载并交叉
编译 SQLite amalgamation → meson 交叉构建（`-Dkernel=ish -Dengine=asbestos
-Dguest_arch=arm64`）→ 把 meson 的 thin archive 重新打包成自包含的
`libish_all.a` → 链接 `entry/src/main/cpp/ish/sandbox_ish.cpp` 生成
`libishsandbox.so` → 校验导出了 `Main`。

可用环境变量覆盖路径：`ISH_SRC`、`OHOS_NDK`、`ISH_BUILD_DIR`、`OUT_LIB`、
`SQLITE_ZIP`、`ALPINE_TARBALL`、`MESON`、`NINJA`、`HDC`、`JOBS`。
默认 scratch 目录是 `build/ish-ohos/`（已被 git 忽略）。

`scripts/ish-ohos/` 里的五个补丁都是可移植性修补，不改变 iSH 语义：

| 补丁 | 作用 |
| --- | --- |
| `0001-vdso-target-ohos.patch` | VDSO 用 `aarch64-linux-ohos` 目标编译 |
| `0002-atomic-init.patch` | OHOS clang 不接受 `NULL` 初始化 `_Atomic` 函数指针 |
| `0003-fork-atomic-init.patch` | 同上，fork guard |
| `0004-fakefs-linux-portability.patch` | fakefs 的 macOS 时间字段与 `F_GETPATH` 换成 Linux/`/proc/self/fd` 实现 |
| `0005-gadget-branch-range.patch` | `tbnz` 的 ±32KB 范围够不到 `fiber_ret`，改为本地 `tbz` + `b` |

### 5.2 构建安装与触发

```bash
# 构建并安装（见 docs/MANUAL-SIGNING.md）
SIGN_STORE_PASS_FILE=signing/.storepass bash scripts/manual-sign.sh build
SIGN_STORE_PASS_FILE=signing/.storepass bash scripts/manual-sign.sh sign
SIGN_STORE_PASS_FILE=signing/.storepass bash scripts/manual-sign.sh install

# 触发自检并读结果
HDC=/home/biglv/harmony-sdk/sdk/default/openharmony/toolchains/hdc
$HDC shell hilog -r
$HDC shell aa start -a EntryAbility -b app.minis.client --ps sandboxProbe true
sleep 10
$HDC shell hilog -x -T MinisHarmony | grep PROBE

# 启动 iSH 并跑冒烟命令（内核/连续两条命令/Python 三组）
$HDC shell aa start -a EntryAbility -b app.minis.client --ps sandboxIsh true
sleep 15
$HDC shell hilog -x -T MinisHarmony | grep ISH
```

也可以一条命令完成构建、签名、安装、冒烟和断言：

```bash
scripts/verify-sandbox.sh --install   # 已安装时去掉 --install
```

脚本检查 `ISH1|hello-from-ish`、`ISH1|3.21.3`、`ISH2|pwd=/tmp`、
`ISH2|smoke=kept`、`ISH3|python 3.12` 与 `ISH END`，失败时打印应用回传的
原始日志；需要平板已连接（`hdc list targets` 非空）。

也可以直接在平板上点：设置 → 工具与沙箱 → 启动 Linux 沙箱；输出面板
支持长按复制。
