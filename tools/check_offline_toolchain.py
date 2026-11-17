#!/usr/bin/env python3
"""Copy only source and bundle to a cold, network-isolated Linux consumer.

Requires bubblewrap on the validation host, not on ordinary bundle consumers.
The output must be a new directory outside the checkout. Logs and the consumer
are retained for inspection; no existing build, Cargo, uv or Godot cache is copied.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(bundle: Path, output: Path) -> int:
    output = output.resolve()
    bundle = bundle.resolve()
    if output.exists() or output == ROOT or ROOT in output.parents:
        raise ValueError("Output must be a new directory outside the checkout")
    if shutil.which("bwrap") is None:
        raise ValueError("Network-isolated validation requires bubblewrap (bwrap)")
    if not bundle.is_file():
        raise ValueError(f"Missing generated bundle: {bundle}")
    output.mkdir(parents=True)
    source = output / "source with spaces"
    source.mkdir()
    files = (
        subprocess.check_output(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
        )
        .decode()
        .split("\0")
    )
    for relative in filter(None, files):
        path = Path(relative)
        # Editor-local configuration is not part of the transferable source.
        if path.parts[0] in {".vscode", ".idea"}:
            continue
        target = source / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, target)
    shutil.copy2(bundle, output / "bundle with spaces.tar.zst")
    for pattern in ("**/*.so", "**/.godot", "**/target"):
        if list(source.glob(pattern)):
            raise ValueError(f"Consumer was not cold: {pattern}")
    home = output / "home"
    home.mkdir()
    # Hide the original checkout, user caches and tool installations. Only
    # distribution runtime prerequisites (Python, C linker/libc, Make, zstd) remain.
    sandbox = [
        "bwrap",
        "--unshare-net",
        "--die-with-parent",
        "--ro-bind",
        "/",
        "/",
        "--tmpfs",
        "/home",
        "--tmpfs",
        "/root",
        "--tmpfs",
        "/tmp",
        "--bind",
        str(output),
        "/mnt",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--chdir",
        "/mnt/source with spaces",
        "--clearenv",
    ]
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": "/mnt/home",
        "LANG": "C.UTF-8",
        "CARGO": "/unavailable-system-cargo",
        "UV": "/unavailable-system-uv",
        "GODOT": "/unavailable-system-godot",
        "RUSTC": "/unavailable-system-rustc",
        "RUSTC_WRAPPER": "/unavailable-wrapper",
        "UV_PYTHON_DOWNLOADS": "never",
    }
    for key, value in env.items():
        sandbox.extend(["--setenv", key, value])
    commands = [
        [
            "python3",
            "-c",
            "import socket; s=socket.socket(); result=s.connect_ex(('1.1.1.1',443)); "
            "print('network connect errno:', result); assert result == 101",
        ],
        ["make", "doctor"],
        ["make", "bundle-verify"],
        ["make", "bundle-check"],
        ["make", "lint"],
        ["make", "lint"],
        ["make", "bundle-verify"],
    ]
    results = []
    for index, command in enumerate(commands):
        if command[0] == "make":
            command += ["TOOLCHAIN=bundle", "BUNDLE=/mnt/bundle with spaces.tar.zst"]
        log_path = output / f"{index:02d}-{command[1]}.log"
        print(f"Running {command!r}; log={log_path}", flush=True)
        with log_path.open("w", encoding="utf-8") as log:
            log.write(f"COMMAND: {command!r}\n")
            log.flush()
            result = subprocess.run(
                [*sandbox, "--", *command], stdout=log, stderr=subprocess.STDOUT, timeout=1800
            )
            log.write(f"\nEXIT CODE: {result.returncode}\n")
        results.append({"command": command, "exit_code": result.returncode, "log": log_path.name})
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
        if result.returncode:
            return result.returncode
    print(f"COLD_OFFLINE_TOOLCHAIN_PASSED: {output}", flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        return validate(args.bundle, args.output)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"offline validation: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
