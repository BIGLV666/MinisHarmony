#!/usr/bin/env python3
"""Add Python 3 to an Alpine fakefs rootfs tree.

OpenMinis' sandbox ships a full Linux userland with Python; Alpine's
minirootfs only carries busybox and apk. Nothing in the guest can download
packages (iSH has no network here), so the pinned package set is fetched at
build time and unpacked straight into the rootfs directory. The build script
regenerates meta.db afterwards with the iSH helper, which is how fakefs
learns about the new paths.

Usage:
    python3 -I scripts/ish-rootfs-python.py \
        --data build/ish-ohos/rootfs/data \
        --cache build/ish-ohos/cache/python-apks

Run this before create_fakefs.py. It is idempotent: unpacking again simply
overwrites the same files.
"""

import argparse
import hashlib
import os
import subprocess
import sys
import tarfile

REPO = "https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64"

# python3 3.12.16-r0 and its transitive dependencies, pinned by hash so a
# mirror change cannot silently alter the shipped rootfs.
PACKAGES = [
    ("gdbm-1.24-r0.apk",
     "51da8e712c448965e5f2f652e9889dc0928ced665d4a4d11207e16adef680f9b"),
    ("libbz2-1.0.8-r6.apk",
     "49945b5c46f2be9201c900df45ca173e1065adb45366c6ad51709381123daa5f"),
    ("libcrypto3-3.3.7-r2.apk",
     "2303cca13dc8bba5798744a68abd07530abb35ab339d9cc4640fc53276049af0"),
    ("libexpat-2.10.0-r0.apk",
     "2352b71e3e94d18a97ca28de2e2f36fcf2cb259344377cf8f65ac24406051302"),
    ("libffi-3.4.7-r0.apk",
     "814579137f32e94e54370f2e5d93d992c4148515b426c168e87102d4d6f6ddc6"),
    ("libgcc-14.2.0-r4.apk",
     "7cfdc00f102d3b98fe563b31e7a59a7b7ab61850c1751915f34e419e83ef2653"),
    ("libncursesw-6.5_p20241006-r3.apk",
     "c1a5a3a552ad4d44c94454555f38de71b151dc2d608ea2246d92b3bd845b7f3a"),
    ("libpanelw-6.5_p20241006-r3.apk",
     "11e2911f6fa4f3885e2fb7488847d58c4c8e166922b5fe259811a04f21802089"),
    ("libssl3-3.3.7-r2.apk",
     "d494a0a211dd78a8055c24885fc06375eabb79c82ae797f7f694cefbf3653b79"),
    ("libstdc++-14.2.0-r4.apk",
     "93dded5af4e42ca59a2e981ffc5acc59c5d7110cec4adaeb15b84dc224526b63"),
    ("mpdecimal-4.0.0-r0.apk",
     "e14866cce8ab46653d2c2ffd679357abfa100fe5259f520509117be19d56cab9"),
    ("musl-1.2.5-r12.apk",
     "f37e73d41880bbc653b771c7d8962c8739bff773503f5155c14fab1bd7c4d52f"),
    ("ncurses-terminfo-base-6.5_p20241006-r3.apk",
     "a86fb76ba2ac494ed3a550a5c42d032c486d942966bceae38f6ce95eaa384550"),
    ("python3-3.12.16-r0.apk",
     "778f9105e454ebc60c3078a3ae59acfdd263615a6948090cb75b06ea088a7add"),
    ("readline-8.2.13-r0.apk",
     "7dad49f83ecbcfa00c5c7df044a5566b928ac1995651cfff219e1df1c2b93871"),
    ("sqlite-libs-3.48.0-r4.apk",
     "0e4e80c156f65307d0b35c4caf5771fae2a8c3d7f5ffb642a72d13e9c6d3cd14"),
    ("xz-libs-5.8.4-r0.apk",
     "d110bed012e0902491ea8ca186a28fd1fdef026405434e10aee0c6f87bbcca4d"),
    ("zlib-1.4-r0.apk",
     "05b5663e2559dcd4b0914b946e358f34830c6897ed73404cdfa958ea3b0d0b46"),
]

SKIP_PREFIX = (".PKGINFO", ".SIGN", ".pre-", ".post-", ".trigger")


def digest(path):
    sha = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()


def fetch(cache, name, expected):
    path = os.path.join(cache, name)
    if os.path.exists(path) and digest(path) == expected:
        return path
    os.makedirs(cache, exist_ok=True)
    url = REPO + "/" + name
    print("downloading", url)
    tmp = path + ".part"
    subprocess.run(["curl", "-fsSL", "-o", tmp, url], check=True)
    actual = digest(tmp)
    if actual != expected:
        os.remove(tmp)
        raise SystemExit("checksum mismatch for %s: %s" % (name, actual))
    os.replace(tmp, path)
    return path


def member_filter(member):
    name = member.name.lstrip("./")
    if not name or name.startswith(SKIP_PREFIX):
        return None
    member.name = name
    # Package control files carry the setuid bits; guest code only needs the
    # ordinary permission bits, and fakefs records them from this tree.
    member.mode &= 0o777
    member.uid = 0
    member.gid = 0
    return member


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True,
                        help="rootfs data directory (the fakefs tree)")
    parser.add_argument("--cache", required=True,
                        help="directory holding the pinned .apk files")
    args = parser.parse_args()

    os.makedirs(args.data, exist_ok=True)
    for name, expected in PACKAGES:
        path = fetch(args.cache, name, expected)
        with tarfile.open(path, "r:gz") as archive:
            members = [m for m in (member_filter(m)
                                   for m in archive.getmembers()) if m]
            archive.extractall(args.data, members=members, filter="tar")
    python = os.path.join(args.data, "usr", "bin", "python3.12")
    if not os.path.exists(python):
        raise SystemExit("python3.12 missing after extraction")
    print("python3 installed into", args.data)


if __name__ == "__main__":
    main()
