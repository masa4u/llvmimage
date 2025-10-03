# syntax=docker/dockerfile:1.6

###############################################
# Builder stage: install LLVM from apt.llvm.org and build Python 3.12
###############################################
FROM debian:trixie AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Build deps for Python and LLVM repository setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    build-essential \
    zlib1g-dev libffi-dev libssl-dev libbz2-dev libreadline-dev libsqlite3-dev uuid-dev \
  && rm -rf /var/lib/apt/lists/*

# Install LLVM 20 from apt.llvm.org (Trixie repository)
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | tee /etc/apt/sources.list.d/llvm.list && \
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
FROM debian:trixie AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Runtime-only libs to execute clang/llvm and Python, plus gcc/g++ for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget gnupg \
    libtinfo6 zlib1g libxml2 libedit2 \
    libstdc++6 libgcc-s1 \
    libffi8 libbz2-1.0 libreadline8 libsqlite3-0 xz-utils libssl3 \
    gcc g++ make cmake ninja-build \
    git curl p7zip-full zip unzip \
    pkg-config ccache patch file gdb \
    libc6-dev libstdc++-14-dev \
  && rm -rf /var/lib/apt/lists/*

# Install LLVM 20 from apt.llvm.org (Trixie repository)
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | tee /etc/apt/sources.list.d/llvm.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      clang-20 \
      clang++-20 \
      lld-20 \
      clang-tools-20 \
      clang-format-20 \
      clang-tidy-20 \
      llvm-20 \
      llvm-20-runtime && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/python-3.12 /opt/python-3.12

# Create python symlink if it doesn't exist
RUN test -f /opt/python-3.12/bin/python || ln -s /opt/python-3.12/bin/python3 /opt/python-3.12/bin/python

# Create versioned symlinks for clang/clang++ to unversioned names
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 100

ENV PATH="/opt/python-3.12/bin:${PATH}" \
    CC=clang \
    CXX=clang++ \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH="/opt/python-3.12/lib:/usr/lib/llvm-20/lib:${LD_LIBRARY_PATH}"

WORKDIR /workspace

# Quick verification (kept lightweight)
RUN clang --version && \
    clang++ --version && \
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
FROM debian:trixie-slim AS slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget gnupg \
    libtinfo6 zlib1g libxml2 libedit2 \
    libstdc++6 libgcc-s1 \
    libffi8 libbz2-1.0 libreadline8 libsqlite3-0 xz-utils libssl3 \
    gcc g++ make cmake ninja-build \
    git curl p7zip-full zip unzip \
    pkg-config ccache patch file gdb \
    libc6-dev libstdc++-14-dev \
  && rm -rf /var/lib/apt/lists/*

# Install LLVM 20 from apt.llvm.org (Trixie repository)
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | tee /etc/apt/sources.list.d/llvm.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      clang-20 \
      clang++-20 \
      lld-20 \
      clang-tools-20 \
      clang-format-20 \
      clang-tidy-20 \
      llvm-20 \
      llvm-20-runtime && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/python-3.12 /opt/python-3.12

# Further prune Python ensurepip to shrink size
RUN rm -rf /opt/python-3.12/lib/python3.12/ensurepip || true

# Create python symlink if it doesn't exist
RUN test -f /opt/python-3.12/bin/python || ln -s /opt/python-3.12/bin/python3 /opt/python-3.12/bin/python

# Create versioned symlinks for clang/clang++ to unversioned names
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 100

ENV PATH="/opt/python-3.12/bin:${PATH}" \
    CC=clang \
    CXX=clang++ \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH="/opt/python-3.12/lib:/usr/lib/llvm-20/lib:${LD_LIBRARY_PATH}"

WORKDIR /workspace

RUN clang --version && \
    clang++ --version && \
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
