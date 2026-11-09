# 第三方组件与许可证

本项目自身以 [MIT](LICENSE) 发布。随 HAP 分发的二进制与数据文件包含下列第三方
组件；各组件的版权归其作者所有，使用与再分发须遵守对应许可证。

## 1. iSH（GPL-2.0）

本机 Linux 沙箱使用 iSH 的 ARM64 分支（Asbestos threaded-code 解释器 + iSH 内核
+ fakefs），编译进 `entry/libs/arm64-v8a/libishsandbox.so`。

- 上游：<https://github.com/ish-app/ish>
- 本项目取用的分支：OpenMinis 维护的 `ish-arm64`（同架构 port）
- 针对 HarmonyOS 的本地补丁：`scripts/ish-ohos/*.patch`，作用见
  [docs/SANDBOX.md](docs/SANDBOX.md) 5.1
- 重建方式：`scripts/build-ish-ohos.sh`（从 `ISH_SRC` 指定的 iSH 检出编译，
  默认 `/home/biglv/project/OpenMinis/deps/ish`）

iSH 以 GPL-2.0 分发。按 GPLv2 第 3 条，分发包含 iSH 二进制的 HAP 时须同时提供
对应源代码：上游源码、OpenMinis 的 ARM64 分支与本仓库的补丁合在一起即构成
`libishsandbox.so` 的完整对应源码。若从应用商店等渠道分发，应通过同一渠道或
书面承诺提供该源码包。

## 2. Alpine Linux minirootfs（3.21.3）

沙箱 rootfs 来自 Alpine Linux 官方 minirootfs（aarch64），随 HAP 以
`resources/rawfile/ish-rootfs.zip` 分发。其中主要的包与许可证：

| 包 | 许可证 |
| --- | --- |
| busybox（含 `/bin/sh`、常用 applet） | GPL-2.0 |
| musl libc | MIT |
| apk-tools | GPL-2.0 |
| alpine-baselayout | GPL-2.0 |

## 3. 离线预装的 Python 3 运行时

`scripts/ish-rootfs-python.py` 固定版本与 SHA-256 拉取 Alpine 3.21 `main/aarch64`
的 Python 3.12.16 及 17 个依赖并解包进 rootfs：

| 包 | 许可证 |
| --- | --- |
| python3 3.12.16 | PSF-2.0 |
| musl 1.2.5 | MIT |
| libcrypto3 / libssl3（OpenSSL 3.3.7） | Apache-2.0 |
| sqlite-libs 3.48.0 | Public Domain |
| readline 8.2.13 | GPL-3.0-or-later |
| libncursesw / libpanelw / ncurses-terminfo-base 6.5 | MIT-style（X11） |
| zlib 1.4 | Zlib |
| libbz2 1.0.8 | bzip2-1.0.6 |
| xz-libs 5.8.4 | 0BSD / Public Domain |
| gdbm 1.24 | GPL-3.0-or-later |
| libffi 3.4.7 | MIT |
| libexpat 2.10.0 | MIT |
| mpdecimal 4.0.0 | BSD-2-Clause |
| libgcc / libstdc++ 14.2.0 | GPL-3.0-or-later WITH GCC-exception-3.1 |

各包完整许可证文本随上游 `.apk` 提供；如需逐包文本，可用同一脚本的
`--apk-dir` 参数从 <https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64>
重新下载后解包查看。

## 4. 平台库

`libishsandbox.so` 与 ArkTS 侧代码在运行时链接 HarmonyOS / OpenHarmony 系统库
（`libc++`、`libhilog`、`libace_napi` 等），这些库随系统提供，本项目不分发。

## 5. 参考实现

OpenMinis（GPLv3）与 dsh-Go（AGPL-3.0）仅用于参考公开行为与产品设计，本仓库
没有复制它们的源代码；如需合并请自行评估许可证兼容性。
