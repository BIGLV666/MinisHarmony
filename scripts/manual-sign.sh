#!/usr/bin/env bash
# Manual HarmonyOS signing on Linux, without DevEco Studio.
#
#   export SIGN_STORE_PASS='<keystore password>'
#   bash scripts/manual-sign.sh init     # key + CSR (one time)
#   bash scripts/manual-sign.sh udid     # device UDID for AppGallery Connect
#   bash scripts/manual-sign.sh build    # unsigned HAP
#   bash scripts/manual-sign.sh sign     # signing/MinisHarmony-signed.hap
#   bash scripts/manual-sign.sh install  # hdc install -r
#
# AppGallery Connect still has to issue the debug certificate (.cer) and the
# provisioning profile (.p7b); nothing here can replace that step. The
# password is read from the environment and never written to disk.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${OHOS_BASE_SDK_HOME:-/home/biglv/harmony-sdk/sdk}"
TOOL="$SDK/default/openharmony/toolchains/lib/hap-sign-tool.jar"
HDC="$SDK/default/openharmony/toolchains/hdc"
HVIGORW="${HVIGORW:-/home/biglv/harmony-sdk/hvigor-tools/bin/hvigorw}"

SIGN_DIR="$ROOT/signing"
ALIAS="${SIGN_ALIAS:-minisharmony}"
STORE="$SIGN_DIR/$ALIAS.p12"
CSR="$SIGN_DIR/$ALIAS.csr"
CER="$SIGN_DIR/$ALIAS.cer"
PROFILE="$SIGN_DIR/$ALIAS.p7b"
HAP="$ROOT/entry/build/ohos/outputs/default/entry-default-unsigned.hap"
OUT="$SIGN_DIR/MinisHarmony-signed.hap"
API=20

# Optionally read the password from a gitignored file instead of the
# environment, so it never appears in a shell history or command line.
if [ -z "${SIGN_STORE_PASS:-}" ] && [ -n "${SIGN_STORE_PASS_FILE:-}" ] &&
  [ -f "$SIGN_STORE_PASS_FILE" ]; then
  SIGN_STORE_PASS="$(<"$SIGN_STORE_PASS_FILE")"
  export SIGN_STORE_PASS
fi

usage() {
  echo "用法: bash scripts/manual-sign.sh <init|udid|build|sign|install>"
  echo "  init     生成 $ALIAS.p12 密钥库与 $ALIAS.csr 证书请求"
  echo "  udid     读取已连接平板的 UDID（需要在 AGC 注册设备）"
  echo "  build    构建未签名 HAP（product=ohos）"
  echo "  sign     用 signing/ 下的 .p12/.cer/.p7b 签名"
  echo "  install  通过 hdc 安装已签名 HAP"
}

need_pass() {
  if [ -z "${SIGN_STORE_PASS:-}" ]; then
    echo "错误: 请先 export SIGN_STORE_PASS=<密钥库口令>" >&2
    exit 1
  fi
}

cmd_init() {
  need_pass
  mkdir -p "$SIGN_DIR"
  if [ -f "$STORE" ]; then
    echo "已存在 $STORE，跳过密钥生成。"
  else
    java -jar "$TOOL" generate-keypair \
      -keyAlias "$ALIAS" \
      -keyPwd "$SIGN_STORE_PASS" \
      -keyAlg ECC \
      -keySize NIST-P-256 \
      -keystoreFile "$STORE" \
      -keystorePwd "$SIGN_STORE_PASS"
  fi
  java -jar "$TOOL" generate-csr \
    -keyAlias "$ALIAS" \
    -keyPwd "$SIGN_STORE_PASS" \
    -subject "C=CN,O=MinisHarmony,OU=Dev,CN=MinisHarmony" \
    -signAlg SHA256withECDSA \
    -keystoreFile "$STORE" \
    -keystorePwd "$SIGN_STORE_PASS" \
    -outFile "$CSR"
  echo "证书请求: $CSR"
  echo "下一步: 在 AppGallery Connect 用它申请调试证书，并下载 .cer 与 .p7b 到 $SIGN_DIR"
}

cmd_udid() {
  "$HDC" shell bm get --udid
}

cmd_build() {
  OHOS_BASE_SDK_HOME="$SDK" "$HVIGORW" assembleHap --mode module \
    -p product=ohos -p buildMode=debug --no-daemon
}

cmd_sign() {
  need_pass
  if [ ! -f "$STORE" ] || [ ! -f "$CER" ] || [ ! -f "$PROFILE" ]; then
    echo "缺少签名材料，需要: $STORE  $CER  $PROFILE" >&2
    echo "先运行 init，再从 AppGallery Connect 下载 .cer 与 .p7b。" >&2
    exit 1
  fi
  if [ ! -f "$HAP" ]; then
    echo "缺少未签名 HAP: $HAP（先运行 build）" >&2
    exit 1
  fi
  mkdir -p "$SIGN_DIR"
  java -jar "$TOOL" sign-app \
    -mode localSign \
    -keyAlias "$ALIAS" \
    -keyPwd "$SIGN_STORE_PASS" \
    -appCertFile "$CER" \
    -profileFile "$PROFILE" \
    -inFile "$HAP" \
    -signAlg SHA256withECDSA \
    -keystoreFile "$STORE" \
    -keystorePwd "$SIGN_STORE_PASS" \
    -outFile "$OUT" \
    -compatibleVersion "$API" \
    -signCode 1
  echo "已签名: $OUT"
}

cmd_install() {
  if [ ! -f "$OUT" ]; then
    echo "缺少已签名 HAP: $OUT（先运行 sign）" >&2
    exit 1
  fi
  "$HDC" install -r "$OUT"
}

case "${1:-}" in
  init) cmd_init ;;
  udid) cmd_udid ;;
  build) cmd_build ;;
  sign) cmd_sign ;;
  install) cmd_install ;;
  *) usage; exit 1 ;;
esac
