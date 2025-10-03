# Dockerized LLVM20/Python3.12 Toolchain

이 저장소는 LLVM 20 (apt.llvm.org)와 Python 3.12를 포함한 Docker 이미지를 생성하기 위한 스크립트를 제공합니다. Debian Trixie (testing) 기반으로 LLVM은 apt.llvm.org 저장소에서 설치되며, Python은 소스에서 빌드됩니다. 모든 빌드 로직은 Python으로 통합되어 Windows/WSL/Linux 어디서든 동일한 절차로 사용할 수 있습니다.

## 구성 요소
- `@ci/llvm20.1-python3.12.Dockerfile`: 실제 빌드에 사용하는 멀티 스테이지 Dockerfile
- `scripts/build_image.py`: Docker 이미지 한 스테이지를 빌드하는 경량 Python 스크립트
- `scripts/run_build.py`: 런타임/slim 이미지 빌드 및(선택 시) 레지스트리 푸시를 자동화하는 오케스트레이션 스크립트
- `scripts/download_deps.py`: Python 소스 tarball을 자동 다운로드하는 유틸리티
- `build.config`: tarball 파일명, 기본 태그 등 공통 설정을 정의
- `deps/`: Python 소스 tarball을 저장하는 디렉터리 (빌드 시 자동 복사)
- `.github/workflows/docker-build.yml`: GitHub Actions CI/CD 워크플로우

## 선행 조건
- Docker CLI (Docker Desktop 등) 가동 중
- Python 3.10 이상이 PATH에 존재 (`python`, `python3`, 혹은 `py` 명령으로 호출 가능)
- (선택) `deps/` 디렉터리에 다음 파일 준비 (없으면 자동 다운로드)
  - `Python-3.12.11.tgz`

**참고**: LLVM 20은 빌드 시 apt.llvm.org 저장소에서 자동으로 설치됩니다 (Debian Trixie 호환).

## 빠른 시작
```bash
# 런타임 + 슬림 이미지 빌드, 로그/리포트 포함
python scripts/run_build.py

# slim 이미지를 제외하고 빌드
python scripts/run_build.py --no-slim

# 빌드 후 Docker Hub에 푸시 (build.config의 DOCKER_USERNAME 사용)
python scripts/run_build.py --push

# 빌드 후 사설 레지스트리로 푸시
python scripts/run_build.py --push --registry my.registry.local
```

실행 후 `logs/docker-build-YYYYMMDD-HHmmss.log` 파일이 생성되고, 생성된 태그와 푸시 대상이 콘솔과 로그에 기록됩니다.

**참고**: `scripts/run_build.py` 실행 시 Python tarball이 없으면 자동으로 다운로드됩니다. 수동 다운로드는 `python scripts/download_deps.py`를 실행하세요.

## 단일 스테이지 빌드
특정 타깃만 빌드하려면 `scripts/build_image.py`를 직접 사용할 수 있습니다.

```bash
# 기본(runtime) 이미지 빌드
python scripts/build_image.py \
  --python-src deps/Python-3.12.11.tgz \
  --tag llvm20.1-python3.12

# 슬림 이미지 빌드
python scripts/build_image.py \
  --python-src deps/Python-3.12.11.tgz \
  --tag llvm20.1-python3.12 --slim
```

`--slim` 옵션을 사용하면 `runtime` 스테이지 대신 `slim` 스테이지가 빌드되며, 기본 태그(`llvm20.1-python3.12`)를 그대로 사용할 경우 자동으로 `-slim` 접미사가 붙습니다.

## 설정 커스터마이징
`build.config`에 정의된 값은 `scripts/run_build.py` 실행 시 기본값으로 사용됩니다. 키=값 형식을 유지하면서 필요에 맞게 수정하세요.

```ini
DOCKER_USERNAME=masa4u
IMAGE_NAME=trixie-llvm20-python3.12
PYTHON_TARBALL=Python-3.12.11.tgz
ARTIFACTS_DIR=deps
REGISTRY=
PUSH=false
SLIM=true
```

생성되는 Docker 이미지 태그:
- **Runtime**: `masa4u/trixie-llvm20-python3.12`
- **Slim**: `masa4u/trixie-llvm20-python3.12-slim`

## 이미지 크기 최적화

이 프로젝트는 Debian slim 이미지 생성을 위한 일반적인 방법론을 적용하여 이미지 크기를 최소화합니다:

### 적용된 최적화 기법

1. **레이어 통합**
   - 여러 RUN 명령을 하나로 통합하여 레이어 수 최소화
   - 패키지 설치와 cleanup을 동일 레이어에서 수행

2. **동일 레이어 내 정리**
   - `apt-get clean`, `/var/lib/apt/lists/*` 삭제를 설치 명령과 동일 RUN에서 실행
   - Python 빌드 후 임시 파일 삭제를 동일 레이어에서 수행

3. **불필요한 파일 제거**
   - 문서: `/usr/share/doc`, `/usr/share/man`, `/usr/share/info`, `/usr/share/locale`
   - 캐시: `/var/cache/apt`, `/tmp`, `/var/tmp`
   - Python: `__pycache__`, `*.pyc`, `*.pyo`, test 디렉토리

4. **Slim 단계 패키지 최소화**
   - LLVM: clang-20, clang++-20, lld-20, llvm-20-runtime만 설치 (tools/format/tidy 제외)
   - 필수 빌드 도구: gcc, g++, make, cmake, ninja-build, git, p7zip-full, zip, unzip, pkg-config
   - 개발 헤더 제거: libc6-dev, libstdc++-14-dev 등
   - 추가 도구 제거: curl, gdb, ccache, patch, file 등

5. **바이너리 최적화**
   - `strip --strip-unneeded`로 Python 바이너리 및 .so 파일 크기 축소

### 스테이지별 특징

- **Builder**: LLVM dev 패키지 포함, Python 소스 빌드 환경
- **Runtime**: 전체 개발 도구 및 LLVM toolchain (clang-tools, clang-format, clang-tidy 포함)
- **Slim**: 필수 빌드 도구 (gcc/g++/clang/clang++/cmake/ninja/git/7zip/zip/pkg-config) + 최소 런타임

## 문제 해결
- `docker 명령을 찾을 수 없습니다` 메시지가 나오면 Docker Desktop이 실행 중인지, CLI가 PATH에 있는지 확인합니다.
- tarball 관련 오류가 발생하면 `deps/`에 파일이 존재하는지, 파일명이 설정과 일치하는지 확인합니다.
- Python 인터프리터를 찾지 못하는 경우 `python --version`이 정상 출력되는지 점검하고, 환경 변수 `PYTHON`을 설정할 수도 있습니다.

필요 시 추가 자동화(스케줄링, 알림 등)를 `scripts/run_build.py`를 기반으로 구성할 수 있습니다.



## Export Docker image
  - WSL: docker image save llvm20.1-python3.12-slim -o llvm20.1-python3.12-slim.tar
  - Windows PowerShell (WSL path already built): wsl.exe --cd /mnt/c/code/dockerimages docker image save llvm20.1-python3.12-slim -o /mnt/c/code/dockerimages/llvm20.1-python3.12-slim.tar

## Podman Import
  - Standard load: podman load -i llvm20.1-python3.12-slim.tar
  - Alternate prefix form: podman load < llvm20.1-python3.12-slim.tar
  - Load with custom tag: podman load --input llvm20.1-python3.12-slim.tar --quiet | podman tag docker.io/library/llvm20.1-python3.12-slim my-registry/llvm20.1-python3.12-slim
