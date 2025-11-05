# syntax=docker/dockerfile:1.6

###############################################
# Builder stage: install LLVM from apt.llvm.org and build Python 3.12
###############################################
FROM debian:trixie AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Install build deps and LLVM in single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    build-essential \
    zlib1g-dev libffi-dev libssl-dev libbz2-dev libreadline-dev libsqlite3-dev uuid-dev \
  # Add LLVM repository and install
  && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc \
  && echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | tee /etc/apt/sources.list.d/llvm.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
      clang-20 clang++-20 lld-20 \
      clang-tools-20 clang-format-20 clang-tidy-20 \
      llvm-20 llvm-20-dev llvm-20-runtime \
      libclang-rt-20-dev libclang-rt-20-dev-dbgsym \
      llvm-20-tools \
      lldb-20 lldb-20-dbgsym \
      clangd-20 \
      valgrind \
  # Cleanup in same layer
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
            /var/cache/apt/* \
            /usr/share/doc/* \
            /usr/share/man/* \
            /tmp/* \
            /var/tmp/*

# Optional local tarball drop-in directory from build context
COPY deps/ /deps/

# Set default source URL for Python; override with local paths via --build-arg
ARG PYTHON_SRC_URL=""

# Fetch, build Python 3.12, and cleanup in single layer
RUN set -eux; \
  # Download Python source
  if echo "$PYTHON_SRC_URL" | grep -Eiq '^https?://'; then \
    curl -L "$PYTHON_SRC_URL" -o /tmp/python-src.tgz; \
  else \
    cp "$PYTHON_SRC_URL" /tmp/python-src.tgz; \
  fi; \
  # Extract and build
  mkdir -p /tmp/src && tar -xf /tmp/python-src.tgz -C /tmp/src; \
  PY_SRC_DIR=$(find /tmp/src -maxdepth 1 -type d -name 'Python-3.12*' -print -quit); \
  cd "$PY_SRC_DIR"; \
  ./configure --prefix=/opt/python-3.12 --enable-optimizations --with-lto --enable-shared; \
  make -j"$(nproc)"; \
  make install; \
  # Aggressive cleanup in same layer
  rm -rf /opt/python-3.12/lib/python3.12/test \
         /opt/python-3.12/lib/python3.12/*/test \
         /opt/python-3.12/lib/python3.12/__pycache__ \
         /opt/python-3.12/lib/python3.12/*/__pycache__ \
         /opt/python-3.12/share/doc; \
  find /opt/python-3.12 -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; \
  find /opt/python-3.12 -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete; \
  strip --strip-unneeded /opt/python-3.12/bin/python3.12 || true; \
  find /opt/python-3.12 -type f -name "*.so" -exec strip --strip-unneeded {} + || true; \
  # Remove build artifacts
  rm -rf /tmp/* /var/tmp/* /deps

###############################################
# Runtime stage: full-featured development environment
###############################################
FROM debian:trixie AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Install all runtime deps + dev tools + LLVM in single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget gnupg \
    libtinfo6 zlib1g libxml2 libedit2 \
    libstdc++6 libgcc-s1 \
    libffi8 libbz2-1.0 libreadline8 libsqlite3-0 xz-utils libssl3 \
    gcc g++ make cmake ninja-build \
    git curl p7zip-full zip unzip \
    pkg-config ccache patch file gdb \
    libc6-dev libstdc++-14-dev \
  # Add LLVM repository and install full toolchain
  && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc \
  && echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | tee /etc/apt/sources.list.d/llvm.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
      clang-20 clang++-20 lld-20 \
      clang-tools-20 clang-format-20 clang-tidy-20 \
      llvm-20 llvm-20-runtime \
  # Cleanup in same layer
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
            /var/cache/apt/* \
            /usr/share/doc/* \
            /usr/share/man/* \
            /usr/share/info/* \
            /tmp/* \
            /var/tmp/*

COPY --from=builder /opt/python-3.12 /opt/python-3.12

# Python cleanup, symlinks, and verification in single layer
RUN rm -rf /opt/python-3.12/lib/python3.12/test \
           /opt/python-3.12/lib/python3.12/*/test \
  && find /opt/python-3.12 -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/python-3.12 -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete \
  # Create symlinks
  && (test -f /opt/python-3.12/bin/python || ln -s /opt/python-3.12/bin/python3 /opt/python-3.12/bin/python) \
  && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 100 \
  && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 100 \
  # Quick verification
  && clang --version \
  && gcc --version \
  && /opt/python-3.12/bin/python3.12 --version \
  # Test compilation
  && echo 'int main() { return 0; }' > /tmp/test.c \
  && gcc /tmp/test.c -o /tmp/test_gcc \
  && clang /tmp/test.c -o /tmp/test_clang \
  && echo '#include <iostream>\nint main() { return 0; }' > /tmp/test.cpp \
  && g++ /tmp/test.cpp -o /tmp/test_gpp \
  && clang++ /tmp/test.cpp -o /tmp/test_clangpp \
  # Final cleanup
  && rm -rf /tmp/* /var/tmp/*

ENV PATH="/opt/python-3.12/bin:${PATH}" \
    CC=clang \
    CXX=clang++ \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH="/opt/python-3.12/lib:/usr/lib/llvm-20/lib:${LD_LIBRARY_PATH}"

WORKDIR /workspace

###############################################
# Slim runtime stage: smaller base with minimal deps
###############################################
FROM debian:trixie-slim AS slim

ARG DEBIAN_FRONTEND=noninteractive

# Install runtime deps + LLVM in single layer with aggressive cleanup
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget gnupg \
    libtinfo6 zlib1g libxml2 libedit2 \
    libstdc++6 libgcc-s1 \
    libffi8 libbz2-1.0 libreadline8 libsqlite3-0 xz-utils libssl3 \
    gcc g++ make cmake ninja-build git \
    p7zip-full zip unzip pkg-config \
  # Add LLVM repository and install
  && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc \
  && echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | tee /etc/apt/sources.list.d/llvm.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
      clang-20 clang++-20 lld-20 llvm-20-runtime \
  # Aggressive cleanup in same layer
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
            /var/cache/apt/* \
            /usr/share/doc/* \
            /usr/share/man/* \
            /usr/share/info/* \
            /usr/share/locale/* \
            /var/log/* \
            /tmp/* \
            /var/tmp/*

COPY --from=builder /opt/python-3.12 /opt/python-3.12

# Python cleanup, symlinks, and verification in single layer
RUN rm -rf /opt/python-3.12/lib/python3.12/ensurepip \
           /opt/python-3.12/lib/python3.12/test \
           /opt/python-3.12/lib/python3.12/*/test \
           /opt/python-3.12/share/doc \
  && find /opt/python-3.12 -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/python-3.12 -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete \
  # Create symlinks
  && (test -f /opt/python-3.12/bin/python || ln -s /opt/python-3.12/bin/python3 /opt/python-3.12/bin/python) \
  && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 100 \
  && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 100 \
  # Quick verification
  && clang --version \
  && gcc --version \
  && /opt/python-3.12/bin/python3.12 --version \
  # Test compilation
  && echo 'int main() { return 0; }' > /tmp/test.c \
  && gcc /tmp/test.c -o /tmp/test_gcc \
  && clang /tmp/test.c -o /tmp/test_clang \
  && echo '#include <iostream>\nint main() { return 0; }' > /tmp/test.cpp \
  && g++ /tmp/test.cpp -o /tmp/test_gpp \
  && clang++ /tmp/test.cpp -o /tmp/test_clangpp \
  # Final cleanup
  && rm -rf /tmp/* /var/tmp/*

ENV PATH="/opt/python-3.12/bin:${PATH}" \
    CC=clang \
    CXX=clang++ \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH="/opt/python-3.12/lib:/usr/lib/llvm-20/lib:${LD_LIBRARY_PATH}"

WORKDIR /workspace
