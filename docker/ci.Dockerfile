# 本地模拟 CI 环境: Ubuntu 24.04 + clang-18 (和 GitHub 的 ubuntu-24.04 runner 一致)
# scripts/scan-local.sh 会自动构建这个镜像
FROM ubuntu:24.04@sha256:24737cef17f4e22b1977df7d9a05e77c4e28b7da5b8911f8d8ccda136bf3573c
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      clang-18 libclang-rt-18-dev llvm-18 cmake ninja-build git ca-certificates python3 \
      libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*
# llvm-symbolizer 在 /usr/lib/llvm-18/bin：sanitizer 报错时靠它把地址翻译成 文件:行号
ENV CXX=clang++-18 CMAKE_GENERATOR=Ninja PATH=/usr/lib/llvm-18/bin:$PATH
