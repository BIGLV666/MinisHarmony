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
                 └─ 管道协议：start / write / read / signal / exit
                              │
                              ▼
                 Alpine userland: /bin/sh, busybox, python3, ...
```

关键设计：

- **入口**：`libishsandbox.so` 导出 `Main(NativeChildProcess_Args)`，由 ArkTS
  `childProcessManager.startNativeChildProcess('libishsandbox.so:Main', ...)` 启动。
- **通信**：不依赖 PTY（HarmonyOS 没有可用的 `/dev/ptmx` 保证）。用
  `ChildProcessArgs.fds` 传一对 socketpair/pipe，协议为长度前缀 JSON：
  `exec {command,timeout,cwd}` / `stdout` / `stderr` / `exit`；stdin 可选。
- **文件系统**：Alpine minirootfs 以 `rawfile/ish-rootfs.zip` 随 HAP 分发，
  首次启动用 `@ohos.zlib.decompressFile` 解到应用私有目录 `filesDir/ish-rootfs/`；
  不把 rootfs 放在 `/data/local/tmp`，避免 `debug_hap` 域访问
  `data_local_tmp` 的 SELinux 限制，应用也天然拥有 rootfs 的读写权限。
  workspace、memory、skills、attachments 后续映射进 guest 的 `/var/minis/*`。
- **隔离边界**：iSH 内核本身是边界：guest 只能看见 rootfs 和显式挂载的目录；
  网络默认共享宿主（与 OpenMinis 一致），后续可加开关。
- **生命周期**：每个应用进程一个沙箱内核，多条命令共享同一个 guest；命令级
  超时由宿主定时器 + guest `SIGKILL` 保证。
- **安全**：工具仍受 `toolsEnabled`、`allowWriteTools`、逐工具开关约束；
  guest 内不能访问应用私有目录以外的宿主路径（fakefs 只挂载显式目录）。
- **许可**：iSH 为 GPLv2，随应用分发时需要保留版权与源码获取方式；在
  `THIRD_PARTY_LICENSES` 中登记。

## 3. 里程碑

- [x] M1 交叉编译：用 OHOS NDK（aarch64-linux-ohos）构建
      `libish.a`、`libish_emu.a`、`libfakefs.a`，SQLite 用 amalgamation 交叉编译，
      VDSO 用 OHOS clang 构建；产物在 `entry/libs/arm64-v8a/libishsandbox.so`，
      可由 `scripts/build-ish-ohos.sh` 从 iSH 源码重建。
- [ ] M2 启动内核：原生子进程里 `ish_init` + 挂载 Alpine rootfs，
      跑通 `/bin/sh -c 'echo hi'`，结果经管道回到 ArkTS。
      （harness 已实现并链接进 `libishsandbox.so`，Alpine rootfs 已打进
      `rawfile/ish-rootfs.zip`；HAP 构建、签名、安装均成功。平板锁屏，
      `aa start` 被系统拒绝，运行时验证待解锁后进行。）
- [ ] M3 工具接入：本机模式新增 `shell_execute`，超时/输出上限/取消；
      工作区与记忆目录挂载。
- [ ] M4 稳定性：连续命令、并发、长输出、Python/Node 冒烟；
      应用退后台与子进程回收。
- [ ] M5 体验：设置页沙箱状态、首次解压进度、磁盘占用、重置 rootfs。

## 4. 移植风险

| 风险 | 验证方式 | 退路 |
| --- | --- | --- |
| Seccomp 过滤 iSH 需要的 syscall | M2 启动即暴露 | 在 guest 内核里绕开；必要时改用纯 fakefs |
| `mmap` 固定地址/大地址空间被拒 | M2 | 调整 iSH 内存布局参数 |
| pthread / futex / signal 行为差异 | M2/M4 | 打平台补丁（`platform/linux.c` 已有 Linux 宿主层） |
| SQLite 在应用沙箱的锁/WAL | M2 | 改 journal 模式或只读 rootfs + 可写 overlay |
| Alpine rootfs 体积（约 3–5 MB 压缩） | M1 | 裁剪 busybox + musl，按需安装包 |
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

# 启动 iSH 并跑冒烟命令（echo/uname/id/alpine-release）
$HDC shell aa start -a EntryAbility -b app.minis.client --ps sandboxIsh true
sleep 15
$HDC shell hilog -x -T MinisHarmony | grep ISH
```

也可以直接在平板上点：设置 → 工具与沙箱 → 启动 Linux 沙箱；输出面板
支持长按复制。
