# syntax=docker/dockerfile:1.6

###############################################
# Builder stage: install LLVM from apt.llvm.org and build Python 3.12
###############################################
FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Build deps for Python and LLVM repository setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    build-essential \
    zlib1g-dev libffi-dev libssl-dev libbz2-dev libreadline-dev libsqlite3-dev uuid-dev \
  && rm -rf /var/lib/apt/lists/*

# Install LLVM 20 from apt.llvm.org
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-20 main" | tee /etc/apt/sources.list.d/llvm.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      clang-20 \
      clang++-20 \
      lld-20 \
      clang-tools-20 \
      clang-format-20 \
      clang-tidy-20 \
      llvm-20 \
      llvm-20-dev \
      llvm-20-runtime && \
    rm -rf /var/lib/apt/lists/*

# Create symlinks in /opt/llvm-20.1/bin for compatibility
RUN mkdir -p /opt/llvm-20.1/bin /opt/llvm-20.1/lib && \
    ln -s /usr/bin/clang-20 /opt/llvm-20.1/bin/clang && \
    ln -s /usr/bin/clang++-20 /opt/llvm-20.1/bin/clang++ && \
    ln -s /usr/bin/lld-20 /opt/llvm-20.1/bin/lld && \
    ln -s /usr/bin/ld.lld-20 /opt/llvm-20.1/bin/ld.lld && \
    ln -s /usr/bin/lld-link-20 /opt/llvm-20.1/bin/lld-link && \
    ln -s /usr/bin/llvm-ar-20 /opt/llvm-20.1/bin/llvm-ar && \
    ln -s /usr/bin/llvm-ranlib-20 /opt/llvm-20.1/bin/llvm-ranlib && \
    ln -s /usr/bin/llvm-objdump-20 /opt/llvm-20.1/bin/llvm-objdump && \
    ln -s /usr/bin/llvm-objcopy-20 /opt/llvm-20.1/bin/llvm-objcopy && \
    ln -s /usr/bin/llvm-strip-20 /opt/llvm-20.1/bin/llvm-strip && \
    ln -s /usr/bin/llvm-as-20 /opt/llvm-20.1/bin/llvm-as && \
    ln -s /usr/bin/llvm-dis-20 /opt/llvm-20.1/bin/llvm-dis && \
    ln -s /usr/bin/llvm-nm-20 /opt/llvm-20.1/bin/llvm-nm && \
    ln -s /usr/bin/clang-format-20 /opt/llvm-20.1/bin/clang-format && \
    ln -s /usr/bin/clang-tidy-20 /opt/llvm-20.1/bin/clang-tidy && \
    ln -s /usr/lib/llvm-20/lib/* /opt/llvm-20.1/lib/ || true

# Optional local tarball drop-in directory from build context
COPY deps/ /deps/

# Set default source URL for Python; override with local paths via --build-arg
ARG PYTHON_SRC_URL=""

WORKDIR /tmp/build

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
    gcc g++ make cmake ninja-build \
    git curl p7zip-full zip unzip \
    pkg-config ccache patch file gdb \
    libc6-dev libstdc++-14-dev \
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
RUN /opt/llvm-20.1/bin/clang --version && \
    /opt/llvm-20.1/bin/clang++ --version && \
    gcc --version && \
    g++ --version && \
    /opt/python-3.12/bin/python3.12 --version

# Test compilation with both compilers
RUN echo 'int main() { return 0; }' > /tmp/test.c && \
    gcc /tmp/test.c -o /tmp/test_gcc && \
    clang /tmp/test.c -o /tmp/test_clang && \
    echo '#include <iostream>\nint main() { std::cout << "test"; return 0; }' > /tmp/test.cpp && \
    g++ /tmp/test.cpp -o /tmp/test_gpp && \
    clang++ /tmp/test.cpp -o /tmp/test_clangpp && \
    rm -f /tmp/test*

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
    git curl p7zip-full zip unzip \
    pkg-config ccache patch file gdb \
    libc6-dev libstdc++-12-dev \
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

RUN /opt/llvm-20.1/bin/clang --version && \
    /opt/llvm-20.1/bin/clang++ --version && \
    gcc --version && \
    g++ --version && \
    /opt/python-3.12/bin/python3.12 --version

# Test compilation with both compilers
RUN echo 'int main() { return 0; }' > /tmp/test.c && \
    gcc /tmp/test.c -o /tmp/test_gcc && \
    clang /tmp/test.c -o /tmp/test_clang && \
    echo '#include <iostream>\nint main() { std::cout << "test"; return 0; }' > /tmp/test.cpp && \
    g++ /tmp/test.cpp -o /tmp/test_gpp && \
    clang++ /tmp/test.cpp -o /tmp/test_clangpp && \
    rm -f /tmp/test*
