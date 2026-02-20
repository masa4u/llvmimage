# ============================================================
# Stage 1: llvm-prep — LLVM 다운로드 및 불필요 파일 공격적 제거
# ============================================================
FROM almalinux:9.4 AS llvm-prep

ARG LLVM_VERSION=20.1.6

RUN set -eux; \
    dnf install -y tar xz wget findutils binutils; \
    dnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum

# LLVM 다운로드 → /opt/llvm 에 압축 해제
RUN set -eux; \
    cd /tmp; \
    wget "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"; \
    tar xf "LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"; \
    mv "LLVM-${LLVM_VERSION}-Linux-X64" /opt/llvm; \
    rm "LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"

# LLVM 공격적 정리 — 개발 헤더·cmake·문서·불필요 바이너리 제거
RUN set -eux; \
    # 1) 개발 헤더 전체 삭제 (clang 사용에는 불필요)
    rm -rf /opt/llvm/include; \
    \
    # 2) 최상위 static 라이브러리 전체 삭제
    rm -f /opt/llvm/lib/*.a; \
    \
    # 3) cmake 설정 파일 삭제
    rm -rf /opt/llvm/lib/cmake; \
    \
    # 4) share/ · libexec/ 전체 삭제
    rm -rf /opt/llvm/share /opt/llvm/libexec; \
    \
    # 5) 불필요 공유 라이브러리 삭제 (컴파일에 필요한 libclang-cpp.so만 유지)
    #    liblldb — lldb 제거됨, libclang — C API (IDE용), libLTO — lld 자체 LTO 지원
    #    libmlir_* — MLIR 런타임, LLVMPolly — 폴리헤드럴 옵티마이저, liblldbIntelFeatures
    rm -f /opt/llvm/lib/liblldb*; \
    rm -f /opt/llvm/lib/libclang.so*; \
    rm -f /opt/llvm/lib/libLTO*; \
    rm -f /opt/llvm/lib/LLVMPolly*; \
    rm -f /opt/llvm/lib/libmlir_*; \
    rm -f /opt/llvm/lib/liblldbIntelFeatures*; \
    rm -f /opt/llvm/lib/libRemarks*; \
    rm -rf /opt/llvm/lib/objects-RELEASE; \
    rm -rf /opt/llvm/lib/libscanbuild /opt/llvm/lib/libear; \
    rm -rf /opt/llvm/lib/x86_64-unknown-linux-gnu; \
    \
    # 6) lib/clang/*/lib/ 안의 sanitizer 런타임 삭제, builtins·profile만 유지
    find /opt/llvm/lib/clang -path '*/lib/linux/*.a' \
         ! -name '*builtins*' ! -name '*profile*' \
         -delete; \
    \
    # 7) 불필요 바이너리 삭제 (화이트리스트 방식)
    #    유지: 컴파일러, 코드품질, 링커, binutils, 커버리지, 지원 도구
    find /opt/llvm/bin -maxdepth 1 \( -type f -o -type l \) | while read -r f; do \
      base=$(basename "$f"); \
      case "$base" in \
        clang|clang++|clang-20|clang-cpp| \
        clang-format|clang-tidy| \
        lld|ld.lld| \
        llvm-ar|llvm-nm|llvm-ranlib|llvm-objdump|llvm-objcopy|llvm-strip|llvm-size|llvm-readelf| \
        llvm-cov|llvm-profdata| \
        llvm-symbolizer|llvm-config) \
          : ;; \
        *) rm -f "$f" ;; \
      esac; \
    done; \
    \
    # 8) 남은 바이너리·공유 라이브러리 strip (디버그 심볼 제거)
    find /opt/llvm/bin -maxdepth 1 -type f -exec sh -c \
      'file "$1" | grep -qE "ELF.*executable|ELF.*shared" && strip --strip-unneeded "$1" 2>/dev/null || true' \
      _ {} \; ; \
    find /opt/llvm/lib -maxdepth 1 -name '*.so*' -type f -exec sh -c \
      'file "$1" | grep -q "ELF.*shared" && strip --strip-unneeded "$1" 2>/dev/null || true' \
      _ {} \;

# ============================================================
# Stage 2: 최종 이미지
# ============================================================
FROM almalinux:9.4

ENV PATH="/opt/llvm/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/llvm/lib"

# 1) EPEL + CRB 활성화 + 패키지 설치
RUN set -eux; \
    dnf install -y epel-release; \
    dnf config-manager --set-enabled crb; \
    dnf install -y --allowerasing --setopt=install_weak_deps=False \
      python3.12 python3.12-pip \
      gcc gcc-c++ make cmake ninja-build pkgconfig \
      patch file gdb valgrind \
      git curl tar xz zip unzip \
      sudo zsh vim; \
    alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1; \
    # 정리: dnf 캐시 + docs/man/locale
    dnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum \
           /usr/share/doc/* /usr/share/man/* \
           /usr/share/info/* /usr/share/locale/* \
           /var/log/dnf* /var/log/yum* /tmp/*; \
    # Python 불필요 파일 정리
    find /usr/lib64/python3.12 -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; \
    find /usr/lib64/python3.12 -type d -name test -exec rm -rf {} + 2>/dev/null || true; \
    find /usr/lib64/python3.12 -type d -name tests -exec rm -rf {} + 2>/dev/null || true; \
    rm -rf /usr/lib64/python3.12/idlelib \
           /usr/lib64/python3.12/tkinter \
           /usr/lib64/python3.12/turtle*.py \
           /usr/lib64/python3.12/turtledemo; \
    # 시스템 바이너리 strip
    strip --strip-unneeded /usr/bin/gcc /usr/bin/g++ /usr/libexec/gcc/x86_64-redhat-linux/11/cc1 /usr/libexec/gcc/x86_64-redhat-linux/11/cc1plus 2>/dev/null || true; \
    find /usr/lib/gcc /usr/lib64 -name '*.so' -exec strip --strip-unneeded {} + 2>/dev/null || true

# 2) Stage 1에서 정리된 LLVM 복사
COPY --from=llvm-prep /opt/llvm /opt/llvm

RUN set -eux; \
    # 공유 라이브러리 경로 등록
    echo "/opt/llvm/lib" > /etc/ld.so.conf.d/llvm.conf; \
    ldconfig; \
    # 버전 접미사 심링크 생성 (clang-20 → clang 등)
    for bin in clang clang++ clang-format clang-tidy lld; do \
      [ -f "/opt/llvm/bin/$bin" ] && [ ! -e "/opt/llvm/bin/${bin}-20" ] \
        && ln -s "$bin" "/opt/llvm/bin/${bin}-20" || true; \
    done; \
    # alternatives: gcc(80) / clang(100, 기본)
    # gcc-c++ 패키지가 /usr/bin/c++을 실제 파일로 설치하므로 심링크로 교체
    rm -f /usr/bin/c++; \
    alternatives --install /usr/bin/cc cc /usr/bin/gcc 80 \
      --slave /usr/bin/c++ c++ /usr/bin/g++; \
    alternatives --install /usr/bin/cc cc /opt/llvm/bin/clang-20 100 \
      --slave /usr/bin/c++ c++ /opt/llvm/bin/clang++-20

WORKDIR /workspace

# 3) 컴파일러 전환 스크립트 (gcc / clang)
RUN set -eux; \
    printf '%s\n' '#!/usr/bin/env bash' \
                  'set -euo pipefail' \
                  'if [[ $# -ne 1 ]]; then echo "usage: use-compiler <gcc|clang>"; exit 2; fi' \
                  'case "$1" in' \
                  '  gcc)   alternatives --set cc /usr/bin/gcc ;;' \
                  '  clang) alternatives --set cc /opt/llvm/bin/clang-20 ;;' \
                  '  *)     echo "unsupported: $1 (use: gcc | clang)"; exit 2 ;;' \
                  'esac' \
                  'echo "cc  -> $(readlink -f "$(command -v cc)")"' \
                  'echo "c++ -> $(readlink -f "$(command -v c++)")"' \
      > /usr/local/bin/use-compiler; \
    chmod +x /usr/local/bin/use-compiler

# 4) C/C++ 빌드 테스트 (clang + gcc 모두 검증)
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

# 5) 버전 확인 (컴파일러 + coverage/leak 도구)
RUN set -eux; \
    python3 --version; \
    cc --version; \
    c++ --version; \
    cmake --version; \
    ninja --version; \
    git --version; \
    clang-format-20 --version; \
    valgrind --version; \
    llvm-cov --version; \
    llvm-profdata --version

# 6) WSL 설정 + dev 유저 생성 (sudo, zsh 기본 셸)
RUN set -eux; \
    # wsl.conf — WSL1에서 기본 유저를 dev로 설정
    printf '[user]\ndefault=dev\n' > /etc/wsl.conf; \
    # dev 유저 생성 + sudo 권한 + zsh 기본 셸
    useradd -m -s /bin/zsh dev; \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev; \
    chmod 440 /etc/sudoers.d/dev
