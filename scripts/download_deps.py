#!/usr/bin/env python3
"""Download LLVM and Python source tarballs if not present."""

import os
import sys
import urllib.request
from pathlib import Path


def load_config(config_file="build.config"):
    """Load configuration from build.config file."""
    config = {}
    config_path = Path(__file__).parent.parent / config_file

    if not config_path.exists():
        print(f"Warning: {config_file} not found, using defaults")
        return config

    with open(config_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip()

    return config


def download_file(url, dest_path):
    """Download a file with progress indication."""
    print(f"Downloading {url} ...")
    print(f"  -> {dest_path}")

    try:
        with urllib.request.urlopen(url) as response:
            total_size = int(response.headers.get('content-length', 0))
            block_size = 8192
            downloaded = 0

            with open(dest_path, 'wb') as f:
                while True:
                    chunk = response.read(block_size)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)

                    if total_size > 0:
                        percent = (downloaded / total_size) * 100
                        print(f"\r  Progress: {percent:.1f}% ({downloaded}/{total_size} bytes)",
                              end='', flush=True)

            print()  # New line after progress
            print(f"✓ Downloaded successfully")
            return True

    except Exception as e:
        print(f"\n✗ Download failed: {e}")
        if dest_path.exists():
            dest_path.unlink()
        return False


def main():
    """Main entry point."""
    config = load_config()

    # Get configuration values
    llvm_tarball = config.get("LLVM_TARBALL", "llvm-project-20.1.8.src.tar.xz")
    python_tarball = config.get("PYTHON_TARBALL", "Python-3.12.9.tgz")
    artifacts_dir = config.get("ARTIFACTS_DIR", "deps")

    # Parse versions from tarball names
    llvm_version = llvm_tarball.replace("llvm-project-", "").replace(".src.tar.xz", "")
    python_version = python_tarball.replace("Python-", "").replace(".tgz", "")

    # Setup paths
    repo_root = Path(__file__).parent.parent
    deps_dir = repo_root / artifacts_dir
    deps_dir.mkdir(exist_ok=True)

    llvm_path = deps_dir / llvm_tarball
    python_path = deps_dir / python_tarball

    # Download URLs
    llvm_url = f"https://github.com/llvm/llvm-project/releases/download/llvmorg-{llvm_version}/{llvm_tarball}"
    python_url = f"https://www.python.org/ftp/python/{python_version}/{python_tarball}"

    # Check and download LLVM
    if llvm_path.exists():
        print(f"✓ LLVM tarball exists: {llvm_path}")
    else:
        print(f"✗ LLVM tarball not found: {llvm_path}")
        if not download_file(llvm_url, llvm_path):
            print("Failed to download LLVM tarball")
            sys.exit(1)

    # Check and download Python
    if python_path.exists():
        print(f"✓ Python tarball exists: {python_path}")
    else:
        print(f"✗ Python tarball not found: {python_path}")
        if not download_file(python_url, python_path):
            print("Failed to download Python tarball")
            sys.exit(1)

    print("\n✓ All dependencies ready")
    return 0


if __name__ == "__main__":
    sys.exit(main())
