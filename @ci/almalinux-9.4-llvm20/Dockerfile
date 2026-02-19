FROM almalinux:9.4

ENV PATH="/usr/lib64/ccache:${PATH}"

# 1) EPEL + CRB 활성화
RUN set -eux; \
    dnf install -y epel-release; \
    dnf config-manager --set-enabled crb

# 2) Python 3.12 (AppStream) + 빌드 도구 + 유틸
RUN set -eux; \
    dnf install -y \
      python3.12 python3.12-devel python3.12-pip \
      gcc gcc-c++ make cmake ninja-build pkgconfig ccache \
      patch file gdb \
      git curl wget tar xz p7zip p7zip-plugins zip unzip; \
    alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1; \
    dnf clean all; \
    rm -rf /var/cache/dnf

# 3) LLVM 20 사전 빌드 바이너리 설치
#    NOTE: glibc 호환 문제 발생 시 LLVM 소스 빌드로 전환 필요
ARG LLVM_VERSION=20.1.6
RUN set -eux; \
    cd /tmp; \
    wget "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"; \
    tar xf "LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"; \
    cp -a LLVM-${LLVM_VERSION}-Linux-X64/* /usr/local/; \
    rm -rf /tmp/LLVM-*; \
    ldconfig; \
    # 버전 접미사 심링크 생성 (clang → clang-20 등)
    for bin in clang clang++ clang-format clang-tidy lldb lld; do \
      [ -f "/usr/local/bin/$bin" ] && [ ! -e "/usr/local/bin/${bin}-20" ] \
        && ln -s "$bin" "/usr/local/bin/${bin}-20" || true; \
    done; \
    # alternatives: gcc(80) / clang(100, 기본)
    alternatives --install /usr/bin/cc cc /usr/bin/gcc 80 \
      --slave /usr/bin/c++ c++ /usr/bin/g++; \
    alternatives --install /usr/bin/cc cc /usr/local/bin/clang-20 100 \
      --slave /usr/bin/c++ c++ /usr/local/bin/clang++-20; \
    # ccache 심링크
    mkdir -p /usr/lib64/ccache; \
    ln -sf /usr/bin/ccache /usr/lib64/ccache/clang; \
    ln -sf /usr/bin/ccache /usr/lib64/ccache/clang++; \
    ln -sf /usr/bin/ccache /usr/lib64/ccache/gcc; \
    ln -sf /usr/bin/ccache /usr/lib64/ccache/g++

WORKDIR /workspace

# 4) 컴파일러 전환 스크립트 (gcc / clang)
RUN set -eux; \
    printf '%s\n' '#!/usr/bin/env bash' \
                  'set -euo pipefail' \
                  'if [[ $# -ne 1 ]]; then echo "usage: use-compiler <gcc|clang>"; exit 2; fi' \
                  'case "$1" in' \
                  '  gcc)   alternatives --set cc /usr/bin/gcc ;;' \
                  '  clang) alternatives --set cc /usr/local/bin/clang-20 ;;' \
                  '  *)     echo "unsupported: $1 (use: gcc | clang)"; exit 2 ;;' \
                  'esac' \
                  'echo "cc  -> $(readlink -f "$(command -v cc)")"' \
                  'echo "c++ -> $(readlink -f "$(command -v c++)")"' \
      > /usr/local/bin/use-compiler; \
    chmod +x /usr/local/bin/use-compiler

# 5) C/C++ 빌드 테스트 (clang + gcc 모두 검증)
RUN set -eux; \
    printf '%s\n' '#include <stdio.h>' \
                  'int main(){printf("Hello C (%s)\\n", __VERSION__);}' > test.c; \
    printf '%s\n' '#include <iostream>' \
                  'int main(){std::cout<<"Hello C++"<<std::endl;}' > test.cpp; \
    # clang 테스트 (기본)
    cc test.c -o testc && ./testc; \
    c++ test.cpp -o testcpp && ./testcpp; \
    # gcc 테스트
    use-compiler gcc; \
    cc test.c -o testc && ./testc; \
    c++ test.cpp -o testcpp && ./testcpp; \
    # clang으로 복원
    use-compiler clang; \
    rm -f test.c testc test.cpp testcpp

# 6) 버전 확인
RUN set -eux; \
    python3 --version; \
    cc --version; \
    c++ --version; \
    cmake --version; \
    ninja --version; \
    git --version; \
    clang-format-20 --version
