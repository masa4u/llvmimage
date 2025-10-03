FROM gitea/runner-images:ubuntu-24.04-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/ccache:${PATH}"

# 1) 기본 툴 + universe 활성화
# 1) 기본 툴 + universe 활성화 (add-apt-repository 대신 정식 deb 라인 추가)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends wget gnupg ca-certificates lsb-release; \
    . /etc/os-release; \
    echo "deb http://archive.ubuntu.com/ubuntu ${VERSION_CODENAME} main universe" \
      > /etc/apt/sources.list.d/universe.list; \
    echo "deb http://archive.ubuntu.com/ubuntu ${VERSION_CODENAME}-updates main universe" \
      >> /etc/apt/sources.list.d/universe.list; \
    echo "deb http://security.ubuntu.com/ubuntu ${VERSION_CODENAME}-security main universe" \
      >> /etc/apt/sources.list.d/universe.list; \
    apt-get update


# 2) Python 3.12 + 빌드툴 + 유틸
RUN set -eux; \
    apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3.12-dev \
      gcc g++ make cmake ninja-build pkg-config ccache patch file gdb \
      git curl p7zip-full zip unzip; \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# 3) apt.llvm.org keyring + repo + LLVM/Clang 20
RUN set -eux; \
    mkdir -p /usr/share/keyrings; \
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor > /usr/share/keyrings/llvm-snapshot.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/llvm-snapshot.gpg] http://apt.llvm.org/noble/ llvm-toolchain-noble-20 main" > /etc/apt/sources.list.d/llvm20.list; \
    echo "deb-src [signed-by=/usr/share/keyrings/llvm-snapshot.gpg] http://apt.llvm.org/noble/ llvm-toolchain-noble-20 main" >> /etc/apt/sources.list.d/llvm20.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      clang-20 lld-20 lldb-20 clang-format-20 llvm-20-tools; \
    update-alternatives --install /usr/bin/cc cc /usr/bin/gcc 80 --slave /usr/bin/c++ c++ /usr/bin/g++; \
    update-alternatives --install /usr/bin/cc cc /usr/bin/clang-20 100 --slave /usr/bin/c++ c++ /usr/bin/clang++-20; \
    ln -sf /usr/bin/ccache /usr/lib/ccache/clang; \
    ln -sf /usr/bin/ccache /usr/lib/ccache/clang++; \
    ln -sf /usr/bin/ccache /usr/lib/ccache/gcc; \
    ln -sf /usr/bin/ccache /usr/lib/ccache/g++; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# 4) 컴파일러 전환 스크립트
RUN set -eux; \
    printf '%s\n' '#!/usr/bin/env bash' \
                  'set -euo pipefail' \
                  'if [[ $# -ne 1 ]]; then echo "usage: use-compiler <gcc|clang>"; exit 2; fi' \
                  'case "$1" in' \
                  '  gcc)   update-alternatives --set cc /usr/bin/gcc ;;' \
                  '  clang) update-alternatives --set cc /usr/bin/clang-20 ;;' \
                  '  *)     echo "unsupported: $1 (use: gcc | clang)"; exit 2 ;;' \
                  'esac' \
                  'echo "cc  -> $(readlink -f "$(command -v cc)")"' \
                  'echo "c++ -> $(readlink -f "$(command -v c++)")"' \
      > /usr/local/bin/use-compiler; \
    chmod +x /usr/local/bin/use-compiler

# 5) 간단 C/C++ 빌드 테스트
RUN set -eux; \
    echo '#include <stdio.h>\nint main(){printf("Hello C (%s)\\n", __VERSION__);}' > test.c; \
    cc test.c -o testc; ./testc; \
    echo '#include <iostream>\nint main(){std::cout<<"Hello C++"<<std::endl;}' > test.cpp; \
    c++ test.cpp -o testcpp; ./testcpp

# 6) 버전 확인
RUN set -eux; \
    python3 --version; \
    cc --version; \
    c++ --version; \
    cmake --version; \
    ninja --version; \
    git --version; \
    clang-format-20 --version; \
    lldb-20 --version

