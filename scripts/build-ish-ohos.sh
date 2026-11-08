#!/usr/bin/env bash
#
# Build the on-device Linux sandbox library (libishsandbox.so) for
# HarmonyOS arm64 from an iSH source checkout.
#
# The library contains the iSH kernel, the Asbestos interpreter, fakefs and
# the HarmonyOS host harness (entry/src/main/cpp/ish/sandbox_ish.cpp). ArkTS
# starts it with childProcessManager.startNativeChildProcess(
# 'libishsandbox.so:Main', ...). See docs/SANDBOX.md for why the guest has to
# be interpreted instead of executed.
#
# Requirements:
#   - HarmonyOS SDK with the OHOS native toolchain (clang/lld/llvm-ar)
#   - meson + ninja (a virtualenv is fine; set MESON and NINJA)
#   - patch, curl, unzip, sha256sum, python3
#
# Usage:
#   scripts/build-ish-ohos.sh                 # build the library
#   scripts/build-ish-ohos.sh --rootfs        # also prepare the Alpine fakefs
#   scripts/build-ish-ohos.sh --rootfs --push # ... and push it to the tablet
#   scripts/build-ish-ohos.sh --clean         # remove the build directory first
#
# Environment overrides:
#   ISH_SRC        iSH checkout (default /home/biglv/project/OpenMinis/deps/ish)
#   OHOS_NDK       HarmonyOS native SDK dir
#   ISH_BUILD_DIR  scratch/build directory (default build/ish-ohos)
#   OUT_LIB        output path (default entry/libs/arm64-v8a/libishsandbox.so)
#   SQLITE_ZIP     reuse an already downloaded sqlite amalgamation zip
#   ALPINE_TARBALL reuse an already downloaded Alpine minirootfs
#   HDC            hdc binary (default: found on PATH)
#   MESON / NINJA  explicit binaries
#   JOBS           parallel build jobs (default: nproc)
#
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ISH_SRC=${ISH_SRC:-/home/biglv/project/OpenMinis/deps/ish}
OHOS_NDK=${OHOS_NDK:-/home/biglv/harmony-sdk/sdk/default/openharmony/native}
BUILD_DIR=${ISH_BUILD_DIR:-$ROOT/build/ish-ohos}
OUT_LIB=${OUT_LIB:-$ROOT/entry/libs/arm64-v8a/libishsandbox.so}
HDC=${HDC:-hdc}
MESON=${MESON:-meson}
NINJA=${NINJA:-ninja}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

SQLITE_VERSION=3450000
SQLITE_DIR_NAME=sqlite-amalgamation-$SQLITE_VERSION
SQLITE_URL=${SQLITE_URL:-https://www.sqlite.org/2024/sqlite-amalgamation-$SQLITE_VERSION.zip}
SQLITE_SHA256=${SQLITE_SHA256:-bde30d13ebdf84926ddd5e8b6df145be03a577a48fd075a087a5dd815bcdf740}

ALPINE_VERSION=3.21.3
ALPINE_NAME=alpine-minirootfs-$ALPINE_VERSION-aarch64
ALPINE_URL=${ALPINE_URL:-https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/$ALPINE_NAME.tar.gz}
ALPINE_SHA256=${ALPINE_SHA256:-ead8a4b37867bd19e7417dd078748e2312c0aea364403d96758d63ea8ff261ea}
DEVICE_ROOTFS=${DEVICE_ROOTFS:-/data/local/tmp/minis-ish-rootfs}

DO_ROOTFS=0
DO_PUSH=0
DO_CLEAN=0

usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --rootfs) DO_ROOTFS=1 ;;
        --push) DO_ROOTFS=1; DO_PUSH=1 ;;
        --clean) DO_CLEAN=1 ;;
        -h|--help) usage 0 ;;
        *) echo "unknown argument: $1" >&2; usage 1 ;;
    esac
    shift
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Put explicitly configured meson/ninja next to the rest of the tools on PATH
# so `meson setup` can find ninja as its backend.
if [ -n "${MESON##*/}" ] && [ -x "$MESON" ]; then
    PATH=$(dirname "$MESON"):$PATH
fi
if [ -n "${NINJA##*/}" ] && [ -x "$NINJA" ]; then
    PATH=$(dirname "$NINJA"):$PATH
fi
export PATH

NDK_BIN=$OHOS_NDK/llvm/bin
# The VDSO custom target looks up a bare `clang` on PATH. Pointing it at the
# OHOS clang is what makes the VDSO use the ohos triple from patch 0001.
PATH=$NDK_BIN:$PATH
export PATH

CC=$NDK_BIN/aarch64-unknown-linux-ohos-clang
CXX=$NDK_BIN/aarch64-unknown-linux-ohos-clang++
AR=$NDK_BIN/llvm-ar
NM=$NDK_BIN/llvm-nm

log "Checking tools"
[ -d "$ISH_SRC" ] || die "iSH source not found: $ISH_SRC (set ISH_SRC)"
[ -x "$CC" ] || die "OHOS clang not found: $CC (set OHOS_NDK)"
[ -x "$CXX" ] || die "OHOS clang++ not found: $CXX"
[ -x "$AR" ] || die "llvm-ar not found: $AR"
command -v "$MESON" >/dev/null || die "meson not found (set MESON)"
command -v "$NINJA" >/dev/null || die "ninja not found (set NINJA)"
command -v patch >/dev/null || die "patch not found"
command -v curl >/dev/null || die "curl not found"
command -v unzip >/dev/null || die "unzip not found"
command -v sha256sum >/dev/null || die "sha256sum not found"
command -v python3 >/dev/null || die "python3 not found"
if [ "$DO_PUSH" = 1 ]; then
    command -v "$HDC" >/dev/null || die "hdc not found (set HDC)"
fi

if [ "$DO_CLEAN" = 1 ]; then
    log "Removing $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

SRC=$BUILD_DIR/src
DEPS=$BUILD_DIR/deps
BUILD=$BUILD_DIR/build
CACHE=$BUILD_DIR/cache
mkdir -p "$DEPS" "$CACHE"

log "Staging iSH source"
rm -rf "$SRC"
mkdir -p "$SRC"
cp -a "$ISH_SRC/." "$SRC/"
rm -rf "$SRC/.git"

log "Applying HarmonyOS patches"
shopt -s nullglob
patches=("$ROOT"/scripts/ish-ohos/*.patch)
[ ${#patches[@]} -gt 0 ] || die "no patches in $ROOT/scripts/ish-ohos"
for p in "${patches[@]}"; do
    printf '  %s\n' "$(basename "$p")"
    patch -p1 -d "$SRC" --batch --forward --silent < "$p" \
        || die "failed to apply $(basename "$p")"
done
shopt -u nullglob

log "Preparing SQLite amalgamation $SQLITE_VERSION"
SQLITE_ZIP=${SQLITE_ZIP:-$CACHE/$SQLITE_DIR_NAME.zip}
if [ ! -f "$SQLITE_ZIP" ]; then
    curl -fL --retry 3 -o "$SQLITE_ZIP.part" "$SQLITE_URL"
    mv "$SQLITE_ZIP.part" "$SQLITE_ZIP"
fi
echo "$SQLITE_SHA256  $SQLITE_ZIP" | sha256sum -c - >/dev/null \
    || die "SQLite archive checksum mismatch: $SQLITE_ZIP"
rm -rf "$DEPS/$SQLITE_DIR_NAME"
unzip -q -o "$SQLITE_ZIP" -d "$DEPS"
[ -f "$DEPS/$SQLITE_DIR_NAME/sqlite3.c" ] || die "sqlite3.c missing after unzip"

log "Compiling libsqlite3.a"
"$CC" -O2 -fPIC -D_GNU_SOURCE \
    -c "$DEPS/$SQLITE_DIR_NAME/sqlite3.c" \
    -o "$DEPS/sqlite3.o"
"$AR" rcs "$DEPS/libsqlite3.a" "$DEPS/sqlite3.o"

log "Configuring iSH ($("$MESON" --version), $("$NINJA" --version))"
cat > "$BUILD_DIR/ohos-cross.ini" <<EOF
[binaries]
c = '$CC'
ar = '$AR'
ranlib = '$NDK_BIN/llvm-ranlib'
strip = '$NDK_BIN/llvm-strip'
ld = '$NDK_BIN/ld.lld'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['-O2', '-fPIC', '-D_GNU_SOURCE', '-I$DEPS/$SQLITE_DIR_NAME']
c_link_args = ['-fuse-ld=lld', '-L$DEPS']
EOF

rm -rf "$BUILD"
"$MESON" setup "$BUILD" "$SRC" \
    --cross-file "$BUILD_DIR/ohos-cross.ini" \
    -Dkernel=ish -Dengine=asbestos -Dguest_arch=arm64

log "Building iSH"
"$NINJA" -C "$BUILD" -j "$JOBS"

log "Creating self-contained libish_all.a"
# meson/llvm-ar produce thin archives that reference the build tree, which is
# useless once the .so is packaged into the HAP. Combine the objects instead.
LIBISH_ALL=$BUILD_DIR/libish_all.a
rm -f "$LIBISH_ALL"
find "$BUILD" -name '*.o' -print0 | xargs -0 "$AR" rcs "$LIBISH_ALL"
count=$(find "$BUILD" -name '*.o' | wc -l)
[ "$count" -gt 0 ] || die "no object files in $BUILD"
printf '  %s objects\n' "$count"

log "Linking $OUT_LIB"
mkdir -p "$(dirname "$OUT_LIB")"
"$CXX" -shared -fPIC -O2 -std=c++17 \
    -o "$OUT_LIB" \
    "$ROOT/entry/src/main/cpp/ish/sandbox_ish.cpp" \
    "$LIBISH_ALL" \
    "$DEPS/libsqlite3.a" \
    -lm -ldl -lpthread -lrt

main_symbol=$("$NM" -D --defined-only "$OUT_LIB" | grep -w Main || true)
[ -n "$main_symbol" ] || die "Main is not exported from $OUT_LIB"
printf '  %s (%s bytes)\n' "$OUT_LIB" "$(stat -c %s "$OUT_LIB")"

prepare_rootfs() {
    log "Preparing Alpine $ALPINE_VERSION fakefs rootfs"
    local tarball=${ALPINE_TARBALL:-$CACHE/$ALPINE_NAME.tar.gz}
    if [ ! -f "$tarball" ]; then
        curl -fL --retry 3 -o "$tarball.part" "$ALPINE_URL"
        mv "$tarball.part" "$tarball"
    fi
    echo "$ALPINE_SHA256  $tarball" | sha256sum -c - >/dev/null \
        || die "Alpine archive checksum mismatch: $tarball"

    local root=$BUILD_DIR/rootfs
    rm -rf "$root"
    mkdir -p "$root/data"
    tar -xzf "$tarball" -C "$root/data"

    # fakefs reads guest modes from the real tree, so import before relaxing
    # the host permissions.
    python3 -I "$SRC/benchmark/create_fakefs.py" "$root/data" "$root"
    [ -f "$root/meta.db" ] || die "create_fakefs.py did not produce meta.db"

    # The tablet extracts the archive as the app's uid; make everything
    # writable so the guest root user can modify its own filesystem.
    chmod -R a+rwX "$root/data"
    tar -czf "$BUILD_DIR/rootfs.tar.gz" -C "$root" data meta.db
    printf '  %s\n' "$BUILD_DIR/rootfs.tar.gz"
}

push_rootfs() {
    log "Pushing rootfs to $DEVICE_ROOTFS"
    local remote_tar=/data/local/tmp/minis-ish-rootfs.tar.gz
    "$HDC" file send "$BUILD_DIR/rootfs.tar.gz" "$remote_tar"
    "$HDC" shell mkdir -p "$DEVICE_ROOTFS"
    # toybox tar on device: extract over the old tree, then relax modes.
    "$HDC" shell tar -xzf "$remote_tar" -C "$DEVICE_ROOTFS"
    "$HDC" shell chmod -R a+rwX "$DEVICE_ROOTFS"
    "$HDC" shell rm -f "$remote_tar"
    "$HDC" shell ls -l "$DEVICE_ROOTFS/meta.db"
}

if [ "$DO_ROOTFS" = 1 ]; then
    prepare_rootfs
    if [ "$DO_PUSH" = 1 ]; then
        push_rootfs
    fi
fi

log "Done"
