#!/usr/bin/env bash
# Runs the on-device Linux sandbox smoke and checks what reached hilog.
#
#   scripts/verify-sandbox.sh             # app must already be installed
#   scripts/verify-sandbox.sh --install   # build, sign and install first
#
# The app's ISH smoke runs five commands through the persistent daemon:
#   ISH1  kernel boot, fakefs, /bin/sh          (hello-from-ish, uname, id)
#   ISH2  same shell: cd and exported variable   (pwd=/tmp, smoke=kept)
#   ISH3  preinstalled Python with C extensions  (python 3.12, ssl, sqlite3)
#   ISH4  preinstalled Node.js, npm and git      (node/npm/git_exit=0)
#   ISH5  guest network via host sockets         (DNS + TCP, net_exit=0)
# ISH2 only passes if the shell survived between calls; ISH END carries the
# total wall time.
#
# Exit codes: 0 all checks passed, 1 a check failed, 2 no device / setup.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${OHOS_BASE_SDK_HOME:-/home/biglv/harmony-sdk/sdk}"
HDC="${HDC:-$SDK/default/openharmony/toolchains/hdc}"
BUNDLE="${BUNDLE:-app.minis.client}"
TAG="${TAG:-MinisHarmony}"
TIMEOUT="${TIMEOUT:-300}"
LOG="$(mktemp)"

cleanup() {
  rm -f "$LOG"
}
trap cleanup EXIT

if [ ! -x "$HDC" ]; then
  echo "找不到 hdc: $HDC（可用 HDC=/path/to/hdc 覆盖）" >&2
  exit 2
fi

targets="$("$HDC" list targets 2>/dev/null | tr -d '\r')"
if [ -z "$targets" ] || printf '%s' "$targets" | grep -q '^\[Empty\]$'; then
  echo "没有已连接的设备。先用 USB 连接平板并确认 hdc list targets 非空。" >&2
  exit 2
fi

if [ "${1:-}" = "--install" ]; then
  if [ ! -f "$ROOT/signing/.storepass" ]; then
    echo "缺少 signing/.storepass；先按 docs/MANUAL-SIGNING.md 准备签名材料。" >&2
    exit 2
  fi
  export SIGN_STORE_PASS_FILE="$ROOT/signing/.storepass"
  bash "$ROOT/scripts/manual-sign.sh" build || exit 2
  bash "$ROOT/scripts/manual-sign.sh" sign || exit 2
  bash "$ROOT/scripts/manual-sign.sh" install || exit 2
fi

echo "清理 hilog 并启动沙箱冒烟…"
"$HDC" shell hilog -r >/dev/null 2>&1
"$HDC" shell aa start -a EntryAbility -b "$BUNDLE" --ps sandboxIsh true

started="$(date +%s)"
while true; do
  "$HDC" shell hilog -x -T "$TAG" 2>/dev/null | tr -d '\r' >"$LOG"
  if grep -q 'ISH END' "$LOG"; then
    break
  fi
  now="$(date +%s)"
  if [ $((now - started)) -ge "$TIMEOUT" ]; then
    echo "等待 $TIMEOUT 秒仍未看到 ISH END。已收到的日志：" >&2
    grep 'ISH' "$LOG" >&2 || true
    exit 1
  fi
  sleep 3
done

elapsed=$(( $(date +%s) - started ))
grep 'ISH' "$LOG"

fail=0
check() {
  if grep -qF "$1" "$LOG"; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    fail=$((fail + 1))
  fi
}

echo
echo "检查项："
check 'ISH1|hello-from-ish'
check 'ISH1|uid=0(root)'
check 'ISH1|3.21.3'
check 'ISH2|pwd=/tmp'
check 'ISH2|smoke=kept'
check 'ISH3|python 3.12'
check 'ISH3|python_exit=0'
check 'ISH4|node_exit=0'
check 'ISH4|npm_exit=0'
check 'ISH4|git_exit=0'
check 'ISH5|net_exit=0'
check 'ISH END'

total="$(grep -o 'total=[0-9]*ms' "$LOG" | tail -1)"
echo
echo "冒烟总耗时约 ${elapsed}s（应用内计时 ${total:-未知}）。"
if [ "$fail" -eq 0 ]; then
  echo "全部通过：内核启动、命令间 shell 状态保留、Python 可用。"
  exit 0
fi
echo "$fail 项未通过。上面的 ISH 日志是应用回传的原始输出。" >&2
exit 1
