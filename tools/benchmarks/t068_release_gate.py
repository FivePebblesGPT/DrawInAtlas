#!/usr/bin/env python3
"""T-068: fail-closed inspection and isolated launch of *exported* Drawing builds.

This checks a real distribution, not a Godot editor project. A Windows PE can be
inspected on Linux, but can only be run/approved on a Windows host separately.
The required Rust Hokusai extension must be present in isolated Linux exports.
Windows inspection is structural only until a Windows-native build is supplied.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path
from typing import Any


class ReleaseError(ValueError):
    """A release artifact or isolated launch failed its contract."""


BINARY = {"linux": "Drawing.x86_64", "windows": "Drawing.exe"}
REQUIRED_FONT_LICENSE = "addons/drawing/fonts/OFL-1.1.txt"
BAD_LOG = re.compile(r"(?:^|\n)(?:SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:)")
# Standard Godot 4.8-beta2 headless shutdown may emit these named leaks even
# after a clean, zero-exit isolated launch. Preserve counts, never exempt
# general runtime errors, missing Godot identification, or nonzero exit codes.
KNOWN_SHUTDOWN = re.compile(r"ERROR: \d+ RID allocations of type '[^'\n]+' were leaked at exit\.")
FORBIDDEN_EXTENSIONS = {".so", ".dll", ".dylib", ".gdextension"}
NATIVE_MANIFEST = Path("addons/drawing/native/drawing_brush.gdextension")
NATIVE_LIBRARY = Path("addons/drawing/native/bin/libdrawing_brush.so")
NATIVE_RESOURCE = "res://" + NATIVE_LIBRARY.as_posix()



def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def inspect_stage(stage: Path, *, require_native: bool = True) -> dict[str, Any]:
    """Verify the separate source project is a Drawing-only staged consumer."""
    if not stage.is_dir() or stage.is_symlink():
        raise ReleaseError("Missing independent Drawing staging directory")
    files = {p.relative_to(stage).as_posix(): p for p in stage.rglob("*") if p.is_file()}
    if any(p.is_symlink() for p in stage.rglob("*")):
        raise ReleaseError("Staged project contains symbolic links")
    required_files = ["project.godot", "main.tscn", "export_presets.cfg", REQUIRED_FONT_LICENSE]
    if require_native:
        required_files.extend((NATIVE_MANIFEST.as_posix(), NATIVE_LIBRARY.as_posix()))
    for required in required_files:
        if required not in files or not files[required].is_file():
            raise ReleaseError(f"Missing Drawing staging input: {required}")
    allowed_native = {NATIVE_MANIFEST.as_posix(), NATIVE_LIBRARY.as_posix()}
    if any(p.suffix.lower() in FORBIDDEN_EXTENSIONS and k not in allowed_native
           for k, p in files.items()):
        raise ReleaseError("Stage includes an unexpected native extension or library")
    if require_native:
        manifest = configparser.ConfigParser(interpolation=None)
        try:
            manifest.read_string(files[NATIVE_MANIFEST.as_posix()].read_text(encoding="utf-8"))
        except (configparser.Error, UnicodeError) as exc:
            raise ReleaseError("Malformed GDExtension manifest") from exc
        if (manifest.get("configuration", "entry_symbol", fallback="").strip('"') != "gdext_rust_init" or
                any(manifest.get("libraries", key, fallback="").strip('"') != NATIVE_RESOURCE
                    for key in ("linux.release.x86_64", "linux.debug.x86_64"))):
            raise ReleaseError("GDExtension ABI/library mapping does not match required Rust export")
        _inspect_binary(files[NATIVE_LIBRARY.as_posix()], "linux", shared=True)
    allowed_root = {"project.godot", "main.tscn", "export_presets.cfg"}
    allowed_prefixes = ("scripts/", "tests/", "addons/drawing/", ".godot/")
    if any(k not in allowed_root and not k.startswith(allowed_prefixes) for k in files):
        raise ReleaseError("Unexpected non-Drawing content in standalone project")
    if not any(k.startswith("addons/drawing/") and k.endswith(".gd") for k in files):
        raise ReleaseError("Missing canonical Drawing GDScript sources")
    if 'config/name="Drawing"' not in files["project.godot"].read_text(encoding="utf-8"):
        raise ReleaseError("Wrong project identity")
    return {"file_count": len(files), "font_license_sha256": digest(files[REQUIRED_FONT_LICENSE]),
            "native_required": require_native,
            "native_library_sha256": digest(files[NATIVE_LIBRARY.as_posix()]) if require_native else None}


def _inspect_binary(path: Path, platform: str, *, shared: bool = False) -> None:
    with path.open("rb") as src:
        header = src.read(4096)
        if platform == "linux":
            if (len(header) < 64 or header[:4] != b"\x7fELF" or header[4:6] != b"\x02\x01"
                    or struct.unpack_from("<H", header, 18)[0] != 62
                    or struct.unpack_from("<H", header, 16)[0] not in ((3,) if shared else (2, 3))):
                raise ReleaseError("Expected x86_64 little-endian ELF executable")
            if not shared and not os.access(path, os.X_OK):
                raise ReleaseError("Linux export is not executable")
        elif platform == "windows":
            if len(header) < 64 or header[:2] != b"MZ":
                raise ReleaseError("Expected Windows PE executable")
            offset = struct.unpack_from("<I", header, 0x3C)[0]
            src.seek(offset)
            if src.read(4) != b"PE\0\0" or src.read(2) != b"\x64\x86":
                raise ReleaseError("Expected Windows x86_64 PE executable")
        else:
            raise ReleaseError("Unsupported export platform")


def inspect_distribution(directory: Path, platform: str) -> dict[str, Any]:
    """Require separate, native x86_64 Godot executable and packed resources."""
    if platform not in BINARY or not directory.is_dir() or directory.is_symlink():
        raise ReleaseError("Missing or unsupported distribution")
    if any(p.is_symlink() for p in directory.rglob("*")):
        raise ReleaseError("Distribution contains a symlink")
    files = {p.relative_to(directory).as_posix(): p for p in directory.rglob("*") if p.is_file()}
    expected = {BINARY[platform], "Drawing.pck"}
    if platform == "linux":
        expected.add(NATIVE_LIBRARY.as_posix())
    if set(files) != expected:
        raise ReleaseError("Distribution contains missing or unexpected exported artifacts")
    exe = directory / BINARY[platform]
    pack = directory / "Drawing.pck"
    if not exe.is_file() or not pack.is_file() or exe.stat().st_size < 4096 or pack.stat().st_size < 64:
        raise ReleaseError("Missing or truncated executable or PCK")
    _inspect_binary(exe, platform)
    with pack.open("rb") as stream:
        if stream.read(4) != b"GDPC":
            raise ReleaseError("Invalid Godot PCK header")
    native_info: dict[str, str | int] | None = None
    if platform == "linux":
        native = files[NATIVE_LIBRARY.as_posix()]
        if native.stat().st_size < 4096:
            raise ReleaseError("Missing or truncated required native library")
        _inspect_binary(native, "linux", shared=True)
        native_info = {"name": NATIVE_LIBRARY.as_posix(), "size": native.stat().st_size,
                       "sha256": digest(native)}
    return {
        "platform": platform,
        "architecture": "x86_64",
        "binary": {"name": exe.name, "size": exe.stat().st_size, "sha256": digest(exe)},
        "pack": {"name": pack.name, "size": pack.stat().st_size, "sha256": digest(pack)},
        "native_extension_shipped": platform == "linux",
        "native_library": native_info,
        "inspection": "structure_and_required_native" if platform == "linux" else "structure_only_no_windows_native",
    }


def check_launch_log(log: str, returncode: int) -> int:
    """Require clean startup; count only precisely recognized exit diagnostics."""
    if returncode != 0 or "Godot Engine" not in log:
        raise ReleaseError(f"Isolated Linux export failed ({returncode}): {log[-2000:]}")
    shutdown_leaks = 0
    for line in log.splitlines():
        if BAD_LOG.match(line):
            if KNOWN_SHUTDOWN.fullmatch(line):
                shutdown_leaks += 1
            else:
                raise ReleaseError(f"Isolated Linux export runtime error: {line}")
    return shutdown_leaks


def launch_linux(directory: Path, *, timeout: int = 45) -> dict[str, Any]:
    """Verify exported-native ABI then boot from a copied, isolated distribution."""
    inspect_distribution(directory, "linux")
    with tempfile.TemporaryDirectory(prefix="t068-export-runtime-") as temporary:
        base = Path(temporary)
        for item in ("home", "data", "cache", "config", "work", "distribution"):
            (base / item).mkdir()
        # Copy only exported artifacts. Neither the original stage/project nor
        # adjacent editor resources can be loaded via a fallback path.
        for filename in (BINARY["linux"], "Drawing.pck", NATIVE_LIBRARY.as_posix()):
            destination = base / "distribution" / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(directory / filename, destination)
        executable = base / "distribution" / BINARY["linux"]
        environment = {**os.environ, "HOME": str(base / "home"),
                       "XDG_DATA_HOME": str(base / "data"),
                       "XDG_CONFIG_HOME": str(base / "config"),
                       "XDG_CACHE_HOME": str(base / "cache"),
                       "GODOT_SILENCE_ROOT_WARNING": "1"}
        environment.pop("GODOT_PROJECT_PATH", None)
        leaks = 0
        for arguments in (("--path", str(base / "distribution"), "--headless", "--script",
                           "res://tests/native_extension_ready.gd"),
                          ("--path", str(base / "distribution"), "--headless", "--quit-after", "5")):
            try:
                result = subprocess.run(
                    [str(executable), *arguments], cwd=base / "work", env=environment,
                    text=True, capture_output=True, timeout=timeout, check=False,
                )
            except (subprocess.TimeoutExpired, OSError) as exc:
                raise ReleaseError(f"Isolated Linux export failed to launch: {exc}") from exc
            log = result.stdout + "\n" + result.stderr
            leaks += check_launch_log(log, result.returncode)
            if "--script" in arguments and "NATIVE_EXTENSION_READY" not in log.splitlines():
                raise ReleaseError("Exported GDExtension classes or ABI were not verified")
        return {"status": "passed", "isolated_working_directory": True,
                "isolated_user_profile": True, "source_project_loaded": False,
                "native_abi_verified": True, "post_exit_leak_diagnostics": leaks}


def inspect_release(stage: Path, linux: Path | None, windows: Path | None,
                    *, launch: bool = False) -> dict[str, Any]:
    if launch and linux is None:
        raise ReleaseError("Cannot run a Linux smoke without a Linux export")
    # The Windows-only path is a historical structural diagnostic; the package
    # has no Windows-native manifest yet. Never treat it as a verified build.
    report: dict[str, Any] = {"schema": "t068-required-native-export-v2",
                              "stage": inspect_stage(stage, require_native=linux is not None),
                              "linux": {"status": "not_tested"},
                              "windows": {"status": "not_tested"},
                              "limitations": ["Windows runtime and physical GPU verification are separate",
                                              "No measured input-to-visible latency or VRAM",
                                              "Windows package is not native-certified by Linux-only manifest"]}
    for platform, directory in (("linux", linux), ("windows", windows)):
        if directory is not None:
            report[platform] = inspect_distribution(directory, platform)
    if launch:
        assert linux is not None
        report["linux"]["runtime"] = launch_linux(linux)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--linux", type=Path)
    parser.add_argument("--windows", type=Path)
    parser.add_argument("--launch-linux", action="store_true")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.linux is None and arguments.windows is None:
        parser.error("Provide at least one exported distribution")
    try:
        result = inspect_release(arguments.stage, arguments.linux, arguments.windows,
                                 launch=arguments.launch_linux)
    except ReleaseError as exc:
        parser.exit(1, f"T-068 release gate failed: {exc}\n")
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if arguments.output is not None:
        arguments.output.write_text(output, encoding="utf-8")
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
