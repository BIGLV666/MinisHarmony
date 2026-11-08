cmake_minimum_required(VERSION 3.5.0)
project(minis_sandbox_probe)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(sandboxprobe SHARED sandbox_probe.cpp)

# libishsandbox.so is not built here: it links the iSH kernel, Asbestos and
# SQLite and is produced by scripts/build-ish-ohos.sh, then committed under
# entry/libs/arm64-v8a/. See docs/SANDBOX.md.
