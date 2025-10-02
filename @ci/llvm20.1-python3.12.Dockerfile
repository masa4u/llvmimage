# syntax=docker/dockerfile:1.6

###############################################
# Builder stage: compile LLVM 20.1 and Python 3.12
###############################################
FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Build deps (kept minimal; final image won’t include these)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils \
    build-essential cmake ninja-build pkg-config \
    python3 \
    zlib1g-dev libtinfo-dev libxml2-dev libedit-dev \
    libffi-dev libssl-dev libbz2-dev libreadline-dev libsqlite3-dev uuid-dev \
  && rm -rf /var/lib/apt/lists/*

# Optional local tarball drop-in directory from build context
COPY deps/ /deps/

# Set default source URLs; override with local paths via --build-arg
ARG LLVM_SRC_URL=""
ARG PYTHON_SRC_URL=""

WORKDIR /tmp/build

# Fetch + build LLVM (projects: clang, lld; targets: X86, AArch64)
RUN set -eux; \
  if echo "$LLVM_SRC_URL" | grep -Eiq '^https?://'; then \
    curl -L "$LLVM_SRC_URL" -o llvm-src.tar.xz; \
  else \
    cp "$LLVM_SRC_URL" llvm-src.tar.xz; \
  fi; \
  mkdir -p /tmp/src && tar -xf llvm-src.tar.xz -C /tmp/src; \
  LLVM_SRC_DIR=$(find /tmp/src -maxdepth 1 -type d -name 'llvm-project-*' -print -quit); \
  mkdir -p /tmp/build/llvm && cd /tmp/build/llvm; \
  cmake -G Ninja -S "$LLVM_SRC_DIR/llvm" -B . \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS='clang;lld' \
    -DLLVM_TARGETS_TO_BUILD='X86;AArch64' \
    -DLLVM_ENABLE_TERMINFO=ON \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCMAKE_INSTALL_PREFIX=/opt/llvm-20.1; \
  ninja -j"$(nproc)"; \
  ninja install; \
  # prune non-essential LLVM tools to reduce size (keep core toolchain only)
  bash -lc 'set -e; cd /opt/llvm-20.1/bin; \
    keep="clang clang++ ld.lld lld-link llvm-ar llvm-ranlib llvm-objdump llvm-objcopy llvm-strip llvm-as llvm-dis llvm-nm"; \
    for f in *; do \
      case " $keep " in \
        *" $f "*) : ;; \
        *) rm -f "$f" || true ;; \
      esac; \
    done'; \
  # strip and remove static libs to reduce size
  find /opt/llvm-20.1 -type f -name "*.a" -delete || true; \
  find /opt/llvm-20.1 -type f -perm -111 -exec strip --strip-unneeded {} + || true; \
  find /opt/llvm-20.1 -type f -name "*.so*" -exec strip --strip-unneeded {} + || true; \
  rm -rf /tmp/build/llvm /tmp/src llvm-src.tar.xz

# Fetch + build Python 3.12
RUN set -eux; \
  if echo "$PYTHON_SRC_URL" | grep -Eiq '^https?://'; then \
    curl -L "$PYTHON_SRC_URL" -o python-src.tgz; \
  else \
    cp "$PYTHON_SRC_URL" python-src.tgz; \
  fi; \
  mkdir -p /tmp/src && tar -xf python-src.tgz -C /tmp/src; \
  PY_SRC_DIR=$(find /tmp/src -maxdepth 1 -type d -name 'Python-3.12*' -print -quit); \
  cd "$PY_SRC_DIR"; \
  ./configure --prefix=/opt/python-3.12 --enable-optimizations --with-lto --enable-shared; \
  make -j"$(nproc)"; \
  make install; \
  # trim tests and caches
  rm -rf /opt/python-3.12/lib/python3.12/test \
         /opt/python-3.12/lib/python3.12/*/test \
         /opt/python-3.12/lib/python3.12/__pycache__ \
         /opt/python-3.12/lib/python3.12/*/__pycache__; \
  strip --strip-unneeded /opt/python-3.12/bin/python3.12 || true; \
  find /opt/python-3.12 -type f -name "*.so" -exec strip --strip-unneeded {} + || true; \
  rm -rf /tmp/src python-src.tgz

###############################################
# Runtime stage: minimal tools only
###############################################
FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Runtime-only libs to execute clang/llvm and Python, plus gcc/g++ for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libtinfo6 zlib1g libxml2 libedit2 \
    libstdc++6 libgcc-s1 \
    libffi8 libbz2-1.0 libreadline8 libsqlite3-0 xz-utils openssl \
    gcc g++ make \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/llvm-20.1 /opt/llvm-20.1
COPY --from=builder /opt/python-3.12 /opt/python-3.12

# Create python symlink if it doesn't exist
RUN test -f /opt/python-3.12/bin/python || ln -s /opt/python-3.12/bin/python3 /opt/python-3.12/bin/python

ENV PATH="/opt/llvm-20.1/bin:/opt/python-3.12/bin:${PATH}" \
    CC=clang \
    CXX=clang++ \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH="/opt/python-3.12/lib:/opt/llvm-20.1/lib:${LD_LIBRARY_PATH}"

WORKDIR /workspace

# Quick verification (kept lightweight)
RUN /opt/llvm-20.1/bin/clang --version && /opt/python-3.12/bin/python3.12 --version

###############################################
# Slim runtime stage: smaller base with minimal deps
###############################################
FROM debian:12-slim AS slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libtinfo6 zlib1g libxml2 libedit2 \
    libstdc++6 libgcc-s1 \
    libffi8 libbz2-1.0 libreadline8 libsqlite3-0 xz-utils libssl3 \
    gcc g++ make cmake ninja-build \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/llvm-20.1 /opt/llvm-20.1
COPY --from=builder /opt/python-3.12 /opt/python-3.12

# Further prune headers and CMake metadata to shrink size
RUN rm -rf /opt/llvm-20.1/include /opt/llvm-20.1/lib/cmake || true \
    && rm -rf /opt/python-3.12/lib/python3.12/ensurepip || true

# Create python symlink if it doesn't exist
RUN test -f /opt/python-3.12/bin/python || ln -s /opt/python-3.12/bin/python3 /opt/python-3.12/bin/python

ENV PATH="/opt/llvm-20.1/bin:/opt/python-3.12/bin:${PATH}" \
    CC=clang \
    CXX=clang++ \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH="/opt/python-3.12/lib:/opt/llvm-20.1/lib:${LD_LIBRARY_PATH}"

WORKDIR /workspace

RUN /opt/llvm-20.1/bin/clang --version && /opt/python-3.12/bin/python3.12 --version
