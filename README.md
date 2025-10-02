# Dockerized LLVM20.1/Python3.12 Toolchain

이 저장소는 LLVM 20.1.x와 Python 3.12를 포함한 Docker 이미지를 생성하기 위한 스크립트를 제공합니다. 모든 빌드 로직은 Python으로 통합되어 Windows/WSL/Linux 어디서든 동일한 절차로 사용할 수 있습니다.

## 구성 요소
- `@ci/llvm20.1-python3.12.Dockerfile`: 실제 빌드에 사용하는 멀티 스테이지 Dockerfile
- `ci/build_image.py`: Docker 이미지 한 스테이지를 빌드하는 경량 Python 스크립트
- `scripts/run_build.py`: 런타임/slim 이미지 빌드 및(선택 시) 레지스트리 푸시를 자동화하는 오케스트레이션 스크립트
- `scripts/download_deps.py`: LLVM/Python 소스 tarball을 자동 다운로드하는 유틸리티
- `build.config`: tarball 파일명, 기본 태그 등 공통 설정을 정의
- `deps/`: LLVM/Python 소스 tarball을 저장하는 디렉터리 (빌드 시 자동 복사)
- `.github/workflows/docker-build.yml`: GitHub Actions CI/CD 워크플로우

## 선행 조건
- Docker CLI (Docker Desktop 등) 가동 중
- Python 3.10 이상이 PATH에 존재 (`python`, `python3`, 혹은 `py` 명령으로 호출 가능)
- (선택) `deps/` 디렉터리에 다음 파일 준비 (없으면 자동 다운로드)
  - `llvm-project-20.1.8.src.tar.xz`
  - `Python-3.12.9.tgz`

## 빠른 시작
```bash
# 런타임 + 슬림 이미지 빌드, 로그/리포트 포함
python scripts/run_build.py

# slim 이미지를 제외하고 빌드
python scripts/run_build.py --no-slim

# 빌드 후 사설 레지스트리로 푸시
python scripts/run_build.py --push --registry my.registry.local/team
```

실행 후 `logs/docker-build-YYYYMMDD-HHmmss.log` 파일이 생성되고, 생성된 태그와 푸시 대상이 콘솔과 로그에 기록됩니다.

**참고**: `scripts/run_build.py` 실행 시 LLVM/Python tarball이 없으면 자동으로 다운로드됩니다. 수동 다운로드는 `python scripts/download_deps.py`를 실행하세요.

## 단일 스테이지 빌드
특정 타깃만 빌드하려면 `ci/build_image.py`를 직접 사용할 수 있습니다.

```bash
# 기본(runtime) 이미지 빌드
python ci/build_image.py \
  --llvm-src deps/llvm-project-20.1.8.src.tar.xz \
  --python-src deps/Python-3.12.9.tgz \
  --tag llvm20.1-python3.12

# 슬림 이미지 빌드
python ci/build_image.py \
  --llvm-src deps/llvm-project-20.1.8.src.tar.xz \
  --python-src deps/Python-3.12.9.tgz \
  --tag llvm20.1-python3.12 --slim
```

`--slim` 옵션을 사용하면 `runtime` 스테이지 대신 `slim` 스테이지가 빌드되며, 기본 태그(`llvm20.1-python3.12`)를 그대로 사용할 경우 자동으로 `-slim` 접미사가 붙습니다.

## 설정 커스터마이징
`build.config`에 정의된 값은 `scripts/run_build.py` 실행 시 기본값으로 사용됩니다. 키=값 형식을 유지하면서 필요에 맞게 수정하세요.

```ini
LLVM_TARBALL=llvm-project-20.1.8.src.tar.xz
PYTHON_TARBALL=Python-3.12.9.tgz
ARTIFACTS_DIR=deps
BASE_TAG=llvm20.1-python3.12
REGISTRY=
PUSH=false
SLIM=true
```

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
