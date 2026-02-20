# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LLVM 20 + Python 3.12 Docker 이미지 빌드 프로젝트. Debian Trixie 기반으로 LLVM은 apt.llvm.org에서, Python은 소스 빌드. 빌드 스크립트는 모두 Python (3.10+).

## Build Commands

```bash
# 전체 빌드 (runtime + slim)
python scripts/run_build.py

# runtime만 빌드 (slim 제외)
python scripts/run_build.py --no-slim

# 빌드 후 Docker Hub 푸시
python scripts/run_build.py --push

# 사설 레지스트리 푸시
python scripts/run_build.py --push --registry my.registry.local

# 단일 스테이지 빌드 (runtime)
python scripts/build_image.py --python-src deps/Python-3.12.11.tgz --tag llvm20.1-python3.12

# 단일 스테이지 빌드 (slim)
python scripts/build_image.py --python-src deps/Python-3.12.11.tgz --tag llvm20.1-python3.12 --slim

# 의존성 수동 다운로드
python scripts/download_deps.py
```

## Architecture

### Dockerfile Multi-Stage (`@ci/llvm20.1-python3.12.Dockerfile`)

3단계 멀티 스테이지 빌드:
- **builder**: LLVM dev 패키지 + Python 소스 빌드 (이후 스테이지에서 `/opt/python-3.12`만 복사)
- **runtime**: 전체 개발 도구 + LLVM full toolchain (clang-tools, clang-format, clang-tidy 포함)
- **slim**: `debian:trixie-slim` 기반, 최소 빌드 도구만 (clang/gcc/cmake/ninja/git)

### Build Scripts (`scripts/`)

- `run_build.py`: 오케스트레이터. `build.config` 읽기 → 의존성 자동 다운로드 → runtime/slim 순차 빌드 → 선택적 푸시. 로그는 `logs/docker-build-*.log`에 저장.
- `build_image.py`: 단일 타겟 빌드 래퍼. `--slim` 플래그로 타겟 전환, `--python-src`로 tarball 경로 지정.
- `download_deps.py`: `build.config`에서 tarball명 읽어 python.org에서 자동 다운로드.

### Configuration (`build.config`)

키=값 형식. `run_build.py`의 기본값으로 사용되며 CLI 인자로 오버라이드 가능. 주요 키: `DOCKER_USERNAME`, `IMAGE_NAME`, `PYTHON_TARBALL`, `SLIM`, `PUSH`, `REGISTRY`.

### CI Runner Image (`@ci/ubuntu-24.04-slim-llvm20/`)

Gitea Actions 용 별도 Dockerfile. Ubuntu 24.04 slim 기반, `use-compiler` 스크립트로 gcc/clang 전환 지원.

## Generated Artifacts (gitignored)

- `deps/` — Python 소스 tarball
- `logs/` — 빌드 로그
- Docker 이미지 태그: `masa4u/trixie-llvm20-python3.12`, `masa4u/trixie-llvm20-python3.12-slim`
