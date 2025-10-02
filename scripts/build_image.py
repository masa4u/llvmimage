#!/usr/bin/env python3
"""Docker 이미지 빌드를 위한 Python 헬퍼 스크립트."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def ensure_docker() -> None:
    if shutil.which("docker") is None:
        raise RuntimeError("docker 명령을 찾을 수 없습니다. Docker Desktop 또는 CLI 설치를 확인하세요.")


def copy_if_needed(source: Path, destination_dir: Path) -> Path:
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / source.name
    if not source.exists():
        raise FileNotFoundError(f"소스 파일을 찾을 수 없습니다: {source}")
    if source.resolve() != destination.resolve():
        shutil.copy2(source, destination)
    return destination


def build_image(
    *,
    dockerfile: Path,
    repository_root: Path,
    llvm_src: str | None,
    python_src: str | None,
    tag: str,
    target: str,
) -> None:
    command = [
        "docker",
        "build",
        "-f",
        str(dockerfile),
        "--target",
        target,
        "-t",
        tag,
    ]

    deps_dir = repository_root / "deps"
    deps_dir.mkdir(parents=True, exist_ok=True)

    if llvm_src:
        llvm_path = copy_if_needed(Path(llvm_src), deps_dir)
        command.extend(["--build-arg", f"LLVM_SRC_URL=/deps/{llvm_path.name}"])

    if python_src:
        python_path = copy_if_needed(Path(python_src), deps_dir)
        command.extend(["--build-arg", f"PYTHON_SRC_URL=/deps/{python_path.name}"])

    command.append(str(repository_root))

    subprocess.run(command, check=True)


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="CI Docker 이미지 빌드 스크립트")
    parser.add_argument("--llvm-src", dest="llvm_src", default="", help="LLVM 소스 tarball 경로")
    parser.add_argument("--python-src", dest="python_src", default="", help="Python 소스 tarball 경로")
    parser.add_argument("--tag", dest="tag", default="llvm20.1-python3.12", help="생성할 이미지 태그")
    parser.add_argument("--slim", dest="slim", action="store_true", help="slim 타겟 빌드")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_arguments(argv)

    repo_root = Path(__file__).resolve().parent.parent
    dockerfile = repo_root / "@ci" / "llvm20.1-python3.12.Dockerfile"
    if not dockerfile.exists():
        raise FileNotFoundError(f"Dockerfile 을 찾을 수 없습니다: {dockerfile}")

    ensure_docker()

    target = "slim" if args.slim else "runtime"
    tag = args.tag
    if args.slim and tag == "llvm20.1-python3.12":
        tag = f"{tag}-slim"

    try:
        build_image(
            dockerfile=dockerfile,
            repository_root=repo_root,
            llvm_src=args.llvm_src or None,
            python_src=args.python_src or None,
            tag=tag,
            target=target,
        )
    except subprocess.CalledProcessError as exc:
        print(f"docker build 실패: {exc}", file=sys.stderr)
        return exc.returncode
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print(f"Built image: {tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
