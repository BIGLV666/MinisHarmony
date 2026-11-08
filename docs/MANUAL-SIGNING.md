# Linux 手动签名与安装

DevEco Studio 的自动签名没有 Linux 版本，本机只有 OpenHarmony 公共 SDK。
下面这套流程用 SDK 自带的 `hap-sign-tool.jar` 和 `hdc` 完成，效果与
DevEco 的「手动签名」一致：密钥和 CSR 在本地生成，证书与 Profile 由
AppGallery Connect（AGC）签发，最后用 `hdc` 安装。

> 关键限制：本机 `build-profile.json5` 的 `default` 产品要求 HarmonyOS
> SDK 组件，当前 SDK 里只有 `default/openharmony`，直接构建 `default`
> 会报 `00303168 SDK component missing`。因此统一用 `product=ohos`
> 构建，再用 HarmonyOS 调试证书签名。

## 0. 平板准备

1. 设置 → 关于本机 → 软件版本，连点 7 次打开开发者模式。
2. 设置 → 系统 → 开发者选项 → 打开 **USB 调试**。
3. USB 连接电脑，平板上弹出「允许 USB 调试」时点允许（勾选始终允许）。

验证：

```bash
export HDC=/home/biglv/harmony-sdk/sdk/default/openharmony/toolchains/hdc
$HDC list targets
```

必须看到设备序列号。如果输出 `[Empty]`，先看本文末尾的排查一节。

## 1. 生成密钥与 CSR（一次性）

```bash
export SIGN_STORE_PASS='换成你的密钥库口令'
bash scripts/manual-sign.sh init
```

也可以把口令放进 `signing/.storepass`（脚本支持 `SIGN_STORE_PASS_FILE`），
避免口令出现在 shell 历史和命令行里：

```bash
bash scripts/manual-sign.sh init   # 会读取 SIGN_STORE_PASS_FILE=signing/.storepass
```

产物（`signing/` 已在 `.gitignore` 中，不会提交）：

- `signing/minisharmony.p12`：EC P-256 私钥 + 密钥库
- `signing/minisharmony.csr`：上传给 AGC 的证书请求

口令只从环境变量读取，脚本不会写盘。请自己记牢，丢了口令只能重新生成
密钥并重新申请证书。

## 2. 在 AppGallery Connect 申请调试证书与 Profile

前提：华为开发者账号，且已在 AGC 创建应用（包名必须是
`app.minis.client`，与 `AppScope/app.json5` 一致；包名不能含
`harmony` 等 AGC 保留字）。

1. **证书**：用户与访问 → 证书管理 → 新增证书 → 类型选「调试证书」，
   上传 `signing/minisharmony.csr`，下载得到的 `.cer`，放到
   `signing/minisharmony.cer`。
2. **设备**：设备管理 → 注册设备，UDID 用下面的命令读取，填进去：
   ```bash
   bash scripts/manual-sign.sh udid
   ```
3. **Profile**：证书、APP ID 和 Profile → Profile → 添加 → 类型「调试」，
   选择刚建的应用（APP ID）、调试证书和刚注册的设备，下载 `.p7b`，放到
   `signing/minisharmony.p7b`。

> 调试证书、Profile、设备 UDID、包名四者必须互相对应；换设备要在 AGC
> 重新注册并把 Profile 重新下载。

## 3. 构建、签名、安装

```bash
bash scripts/manual-sign.sh build
bash scripts/manual-sign.sh sign
bash scripts/manual-sign.sh install
```

产物：`signing/MinisHarmony-signed.hap`。

对应的底层命令（排查时可直接跑）：

```bash
# 构建
OHOS_BASE_SDK_HOME=/home/biglv/harmony-sdk/sdk \
  /home/biglv/harmony-sdk/hvigor-tools/bin/hvigorw assembleHap \
  --mode module -p product=ohos -p buildMode=debug --no-daemon

# 签名
java -jar /home/biglv/harmony-sdk/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  sign-app -mode localSign -keyAlias minisharmony \
  -keyPwd "$SIGN_STORE_PASS" -keystorePwd "$SIGN_STORE_PASS" \
  -keystoreFile signing/minisharmony.p12 \
  -appCertFile signing/minisharmony.cer \
  -profileFile signing/minisharmony.p7b \
  -inFile entry/build/ohos/outputs/default/entry-default-unsigned.hap \
  -outFile signing/MinisHarmony-signed.hap \
  -signAlg SHA256withECDSA -compatibleVersion 20 -signCode 1

# 安装
/home/biglv/harmony-sdk/sdk/default/openharmony/toolchains/hdc \
  install -r signing/MinisHarmony-signed.hap
```

## 4. 常用排查

| 现象 | 原因与处理 |
| --- | --- |
| `hdc list targets` 为空 | 平板 USB 模式只暴露了 MTP 接口，说明 USB 调试未打开或未授权。打开开发者选项里的 USB 调试，重新插拔并点「允许」。 |
| 安装报 `9568289` / profile 不匹配 | 包名、UDID、证书和 Profile 不是同一套；核对 AGC 里注册的设备与当前平板 UDID。 |
| 安装报签名校验失败 | 用了自签证书，或 `.cer`/`.p7b` 不匹配。必须是 AGC 针对该 CSR 签发的调试证书。 |
| 构建报 `00303168 SDK component missing` | 用了 `-p product=default`。本机没有 HarmonyOS SDK 组件，改 `-p product=ohos`。 |
| 安装成功但启动闪退 | 用 `hdc hilog` 看崩溃栈；OpenHarmony 构建在 HarmonyOS 上缺少 HMS 组件时会出现这种情况，需要改用 HarmonyOS SDK 重新构建。 |
| 设备列表出现多个 | `hdc -t <序列号> install ...` 指定目标。 |
