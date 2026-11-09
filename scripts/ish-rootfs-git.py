#!/usr/bin/env python3
"""Add git to an Alpine fakefs rootfs tree.

The sandbox is Alpine, so the package manager is apk (not apt); the guest
cannot rely on a mirror being reachable at runtime. This script unpacks a
pinned git 2.47.3 and the dependencies the Python/Node sets do not already
provide, including libcurl so https remotes work.

Usage:
    python3 -I scripts/ish-rootfs-git.py \
        --data build/ish-ohos/rootfs/data \
        --cache build/ish-ohos/cache/git-apks

Run this before create_fakefs.py. It is idempotent.
"""

import argparse
import hashlib
import os
import subprocess
import tarfile

MAIN = "https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64"

# git 2.47.3-r0 and the part of its closure missing from the Python/Node sets.
# musl, libexpat, zlib, openssl, nghttp2, brotli, c-ares and zstd are already
# unpacked by the other scripts.
PACKAGES = [
    ("git-2.47.3-r0.apk",
     "6449c9bd31b7e47221a54f68f6fddb4122351f65b9a1b371b737872ef5a1b68b"),
    ("libcurl-8.14.1-r3.apk",
     "a1f8514eb8d591730e871fe7356ec3266409a7f4a3f5745152e7f2b9dea8aea9"),
    # libcurl links against libidn2 and libpsl for international domains and
    # the Public Suffix List; both pull libunistring.
    ("libidn2-2.3.7-r0.apk",
     "189be98c9ce9ec5bd6709ea489bd236f5a6c971bf70e074f9a3ea24585f9d5ec"),
    ("libpsl-0.21.5-r3.apk",
     "2e9d33bc57bc4db4ba78993ce3e684b1fcef182d86812792885751b47cb9ccd4"),
    ("libunistring-1.2-r0.apk",
     "6c80d48d4458f4344fa34a28283a5c6147404fb24398b861e981aa5dd9df79da"),
    ("pcre2-10.43-r1.apk",
     "525f1b4c7560ef6561b0a43e6a160bcda368254c58595fa43eff672b01031be1"),
    # git depends on the official generated bundle packaged separately from
    # the ca-certificates update script. It ships /etc/ssl/cert.pem and
    # /etc/ssl/certs/ca-certificates.crt directly.
    ("ca-certificates-bundle-20261020-r0.apk",
     "2e421ec229ec0956a5617dd3c9a1dc0129a0cb3e15ebbf452f9379cf6f622450"),
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
    url = MAIN + "/" + name
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
    # ca-certificates-bundle carries ssl1.1 compatibility links pointing at
    # absolute paths (/etc/ssl/certs). Nothing needs them, and tarfile refuses
    # to extract a symlink that resolves outside the destination tree.
    if name.startswith("etc/ssl1.1"):
        return None
    member.name = name
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

    git = os.path.join(args.data, "usr", "bin", "git")
    remote = os.path.join(args.data, "usr", "libexec", "git-core",
                          "git-remote-https")
    if not os.path.exists(git):
        raise SystemExit("git missing after extraction")
    if not os.path.exists(remote):
        raise SystemExit("git-remote-https missing after extraction")
    print("git installed into", args.data)


if __name__ == "__main__":
    main()
