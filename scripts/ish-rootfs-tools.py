#!/usr/bin/env python3
"""Add the everyday command-line tools to an Alpine fakefs rootfs.

OpenMinis tells the model it can rely on bash, curl, jq, pip, ssh and rsync
(installing them with `apk add` when a mirror is reachable). This project
preinstalls a pinned set instead so the sandbox works offline; the libraries
the Python, Node and git sets already unpacked (openssl, libcurl, readline,
zlib, libidn2, zstd) are reused rather than duplicated.

Usage:
    python3 -I scripts/ish-rootfs-tools.py \
        --data build/ish-ohos/rootfs/data \
        --cache build/ish-ohos/cache/tool-apks

Run this before create_fakefs.py. It is idempotent.
"""

import argparse
import hashlib
import os
import subprocess
import tarfile

MAIN = "https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64"
COMMUNITY = "https://dl-cdn.alpinelinux.org/alpine/v3.21/community/aarch64"

# bash brings an interactive-friendly shell; curl/jq/unzip are the tools the
# system prompt promises; py3-pip + setuptools make `pip install` work against
# PyPI; openssh-client covers git-over-ssh and scp; rsync copies into and out
# of the mounted /var/minis directories. libreadline, libcurl, libcrypto,
# libz, libidn2 and zstd are already present from the other package sets.
PACKAGES = [
    ("main", "bash-5.2.37-r0.apk",
     "876b5e7c50bd13bd7537038c16d5598cfad249aba1cca1086a1f7e3e48b0440f"),
    ("main", "curl-8.14.1-r3.apk",
     "a0d31bc75826fc6b37261acf29417669d54be908430bad672069d140a97b23c5"),
    ("main", "jq-1.7.1-r0.apk",
     "6623022405bd08a0db224e349f8aa5e227cf0ed3fd2318ab2020d87e6aec9734"),
    ("main", "oniguruma-6.9.9-r0.apk",
     "70ee737bf0b3dd2c33bb83b2c0dea0158d24ada18234d18947e003593233cde2"),
    ("community", "py3-pip-24.3.1-r0.apk",
     "038d5fec30f3c39dbfa9657111a5d9b80f4c659ad85d36df7a0882e2dbb7431b"),
    ("main", "py3-setuptools-70.3.0-r0.apk",
     "17a4fdd0c0d2c7e8df459e71690076d8afe3d82b5d42cb8f6ddaaeb079ee534d"),
    ("main", "py3-packaging-24.2-r0.apk",
     "bfb9b256b03ec2bd97a702d7e5f04f3ac11849e42b03f33d096dd234f6de206c"),
    ("main", "py3-parsing-3.1.4-r0.apk",
     "e0cb14deac8e79207789e128160fe2fab5d3a3308697612f0bec55de194caf38"),
    ("main", "openssh-client-default-9.9_p2-r1.apk",
     "2c9dc996383767a021a08cff4164a10ebdc1d67a820159eea2ddfbc053df05d9"),
    ("main", "openssh-client-common-9.9_p2-r1.apk",
     "158bcb3a0b8253f5ffba7afb2f2d24059cf4721cfd70428bb18c9149cbe8259a"),
    ("main", "openssh-keygen-9.9_p2-r1.apk",
     "44ad22e392c8cb15821224078c18a50500eafe672d5f04315b5fbb540a6057f5"),
    ("main", "libedit-20240808.3.1-r0.apk",
     "a3782c6baa2b944d2b62d38c899f7b8f2d104adad34e99efe6aa75f9523cf2f7"),
    ("main", "rsync-3.5.2-r1.apk",
     "a8b82b90fdff2869618f011cc8141976a07d0f664cd216ff354e3cf47f8eaffe"),
    ("main", "acl-libs-2.3.2-r1.apk",
     "b0d03f1eed5d5c083a5a11b780a4f89ccdfc5619ebbd822c8c1f09df179b7802"),
    ("main", "lz4-libs-1.10.0-r0.apk",
     "92e8508c0d3c4115b8039ef333fa0ad0dcd271976ac82554fb3eab1e4b8a4a8e"),
    ("main", "popt-1.19-r4.apk",
     "39e2f9105f75b18ffa089fb758b02e049212211c105b3910e4e9b4918bf3558a"),
    ("main", "libxxhash-0.8.2-r2.apk",
     "c4a3ccb2c54fa9f8ae83cd7457984b9fd47b8237560f2930693df16bc2adc877"),
    ("main", "unzip-6.0-r15.apk",
     "b75c03bc8808172fd825d7f1e94daf4a40492d6d1838308db7e2f9e050da89e9"),
]

REPOS = {"main": MAIN, "community": COMMUNITY}
SKIP_PREFIX = (".PKGINFO", ".SIGN", ".pre-", ".post-", ".trigger")


def digest(path):
    sha = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()


def fetch(cache, repo, name, expected):
    path = os.path.join(cache, name)
    if os.path.exists(path) and digest(path) == expected:
        return path
    os.makedirs(cache, exist_ok=True)
    url = REPOS[repo] + "/" + name
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
    for repo, name, expected in PACKAGES:
        path = fetch(args.cache, repo, name, expected)
        with tarfile.open(path, "r:gz") as archive:
            members = [m for m in (member_filter(m)
                                   for m in archive.getmembers()) if m]
            for member in members:
                # The minirootfs links /usr/bin/unzip at busybox; the real
                # package must replace that absolute symlink with a file, and
                # tarfile refuses to write through it.
                target = os.path.join(args.data, member.name)
                if member.isfile() and os.path.islink(target):
                    os.unlink(target)
            archive.extractall(args.data, members=members, filter="tar")

    for rel in ("bin/bash", "usr/bin/curl", "usr/bin/jq", "usr/bin/pip3",
                "usr/bin/ssh", "usr/bin/scp", "usr/bin/rsync", "usr/bin/unzip",
                "usr/lib/python3.12/site-packages/pip/__init__.py"):
        if not os.path.exists(os.path.join(args.data, rel)):
            raise SystemExit("%s missing after extraction" % rel)
    print("common tools installed into", args.data)


if __name__ == "__main__":
    main()
