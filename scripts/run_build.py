#!/usr/bin/env python3
"""Cross-platform Docker 이미지 빌드 오케스트레이터."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional


def read_config(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}

    entries: Dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        entries[key.strip().upper()] = value.strip()
    return entries


def bool_from(value: Optional[str], default: bool) -> bool:
    if value is None:
        return default
    lowered = value.strip().lower()
    if lowered in {"1", "true", "yes", "y"}:
        return True
    if lowered in {"0", "false", "no", "n"}:
        return False
    return default


def run_command(command: Iterable[str], log_file, *, env: Optional[Dict[str, str]] = None) -> None:
    process = subprocess.Popen(
        list(command),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )

    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="")
        log_file.write(line)
    exit_code = process.wait()
    if exit_code != 0:
        raise subprocess.CalledProcessError(exit_code, list(command))


def ensure_docker_available() -> None:
    if shutil.which("docker") is None:
        raise RuntimeError("docker 명령을 찾을 수 없습니다. Docker Desktop 또는 CLI를 확인하세요.")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Docker 빌드 자동화 스크립트")
    parser.add_argument("--config", default="build.config", help="설정 파일 경로")
    parser.add_argument("--artifacts", help="소스 tarball 이 위치한 디렉터리")
    parser.add_argument("--python-tarball", help="Python tarball 파일명 또는 경로")
    parser.add_argument("--tag", help="기본 Docker 태그")
    parser.add_argument("--registry", help="푸시할 대상 레지스트리")
    parser.add_argument("--log-dir", help="로그 저장 디렉터리")
    parser.add_argument("--slim", dest="slim", action="store_true", help="슬림 이미지도 빌드")
    parser.add_argument("--no-slim", dest="slim", action="store_false", help="슬림 이미지 빌드 생략")
    parser.add_argument("--push", dest="push", action="store_true", help="빌드 후 푸시")
    parser.add_argument("--no-push", dest="push", action="store_false", help="푸시 생략")
    parser.add_argument(
        "--report",
        default="",
        help="JSON 리포트 파일 경로 (기본: logs 하위 자동 생성)",
    )
    parser.set_defaults(slim=None, push=None)

    args = parser.parse_args(argv)

    config_path = Path(args.config).resolve()
    config = read_config(config_path)

    def resolve(key: str, cli_value: Optional[str], default: str) -> str:
        if cli_value:
            return cli_value
        if key in config:
            return config[key]
        return default

    def resolve_bool(key: str, cli_value: Optional[bool], default: bool) -> bool:
        if cli_value is not None:
            return cli_value
        if key in config:
            return bool_from(config[key], default)
        return default

    repo_root = Path(__file__).resolve().parent.parent

    artifacts_dir = resolve("ARTIFACTS_DIR", args.artifacts, "deps")
    artifacts_path = Path(artifacts_dir)
    if not artifacts_path.is_absolute():
        artifacts_path = (repo_root / artifacts_path).resolve()

    python_spec = resolve("PYTHON_TARBALL", args.python_tarball, "Python-3.12.11.tgz")

    # Build tag from DOCKER_USERNAME and IMAGE_NAME
    docker_username = resolve("DOCKER_USERNAME", None, "")
    image_name = resolve("IMAGE_NAME", None, "trixie-llvm20-python3.12")

    if args.tag:
        base_tag = args.tag
    elif docker_username:
        base_tag = f"{docker_username}/{image_name}"
    else:
        base_tag = image_name

    registry = resolve("REGISTRY", args.registry, "")
    log_dir_value = resolve("LOG_DIR", args.log_dir, "logs")

    slim_enabled = resolve_bool("SLIM", args.slim, True)
    push_enabled = resolve_bool("PUSH", args.push, False)

    deps_dir = (repo_root / "deps").resolve()
    deps_dir.mkdir(parents=True, exist_ok=True)

    # Auto-download dependencies if not present
    download_script = repo_root / "scripts" / "download_deps.py"
    if download_script.exists():
        print("의존성 파일 확인 중...")
        try:
            subprocess.run([sys.executable, str(download_script)], check=True)
        except subprocess.CalledProcessError:
            print("의존성 다운로드 실패", file=sys.stderr)
            return 1

    def resolve_tarball(spec: str) -> Path:
        candidate = Path(spec)
        if not candidate.is_absolute():
            candidate = (artifacts_path / candidate).resolve()
        return candidate

    python_src = resolve_tarball(python_spec)

    if not python_src.exists():
        raise FileNotFoundError(f"Python tarball 을 찾을 수 없습니다: {python_src}")

    python_dest = deps_dir / python_src.name

    if python_src.resolve() != python_dest.resolve():
        shutil.copy2(python_src, python_dest)

    log_dir = Path(log_dir_value)
    if not log_dir.is_absolute():
        log_dir = (repo_root / log_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_path = log_dir / f"docker-build-{timestamp}.log"

    report_path: Optional[Path] = None
    if args.report:
        rp = Path(args.report)
        report_path = rp if rp.is_absolute() else (repo_root / rp).resolve()

    ensure_docker_available()

    dockerfile_path = repo_root / "@ci" / "llvm20.1-python3.12.Dockerfile"
    if not dockerfile_path.exists():
        raise FileNotFoundError(f"Dockerfile 이 없습니다: {dockerfile_path}")

    build_results = []

    with log_path.open("w", encoding="utf-8") as log_file:
        def build_image(target: str, tag: str) -> None:
            args_list = [
                "docker",
                "build",
                "-f",
                str(dockerfile_path),
                "--build-arg",
                f"PYTHON_SRC_URL=/deps/{python_dest.name}",
                "--target",
                target,
                "-t",
                tag,
                str(repo_root),
            ]
            log_file.write(f"\n# docker build ({target}) -> {tag}\n")
            log_file.flush()
            run_command(args_list, log_file)

        try:
            build_image("runtime", base_tag)
            build_results.append({"tag": base_tag, "target": "runtime"})

            if slim_enabled:
                slim_tag = base_tag
                if not base_tag.endswith("-slim"):
                    slim_tag = f"{base_tag}-slim"
                build_image("slim", slim_tag)
                build_results.append({"tag": slim_tag, "target": "slim"})
        except subprocess.CalledProcessError as exc:
            log_file.write(f"빌드 실패: {exc}\n")
            print(f"빌드 실패 (로그: {log_path})", file=sys.stderr)
            return 1

        pushed_tags: List[str] = []
        if push_enabled:
            for result in build_results:
                local_tag = result["tag"]
                remote_tag = local_tag
                if registry:
                    registry_clean = registry.rstrip("/")
                    remote_tag = f"{registry_clean}/{local_tag}"
                    log_file.write(f"\n# docker tag {local_tag} {remote_tag}\n")
                    log_file.flush()
                    try:
                        run_command(["docker", "tag", local_tag, remote_tag], log_file)
                    except subprocess.CalledProcessError as exc:
                        log_file.write(f"태그 작업 실패: {exc}\n")
                        print(f"태그 작업 실패 (로그: {log_path})", file=sys.stderr)
                        return 1

                log_file.write(f"\n# docker push {remote_tag}\n")
                log_file.flush()
                try:
                    run_command(["docker", "push", remote_tag], log_file)
                    pushed_tags.append(remote_tag)
                except subprocess.CalledProcessError as exc:
                    log_file.write(f"푸시 실패: {exc}\n")
                    print(f"푸시 실패 (로그: {log_path})", file=sys.stderr)
                    return 1

    report_data = {
        "log": str(log_path),
        "builds": build_results,
        "pushed": pushed_tags if push_enabled else [],
        "config": {
            "config_path": str(config_path),
            "artifacts_dir": str(artifacts_path),
            "base_tag": base_tag,
            "registry": registry,
            "slim": slim_enabled,
            "push": push_enabled,
        },
        "timestamp": timestamp,
    }

    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report_data, indent=2, ensure_ascii=False), encoding="utf-8")

    print("--- 요약 ---")
    print(f"생성된 태그: {', '.join(item['tag'] for item in build_results)}")
    if push_enabled:
        if pushed_tags:
            print(f"푸시 완료: {', '.join(pushed_tags)}")
        else:
            print("푸시가 설정되었지만 진행되지 않았습니다.")
    print(f"로그 파일 위치: {log_path}")
    if report_path:
        print(f"리포트 파일: {report_path}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"오류: {exc}", file=sys.stderr)
        sys.exit(1)
