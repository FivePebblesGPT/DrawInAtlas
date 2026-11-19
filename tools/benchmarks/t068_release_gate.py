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


def _inspect_project_application(project: Path) -> None:
    """Require effective Drawing identity and launch scene in Godot's application section.

    A substring search accepts comment text, settings in unrelated sections,
    and a later conflicting assignment. Godot project files have sectioned
    key/value records, so examine only active [application] settings and reject
    duplicate or ambiguous declarations before packaging a standalone app.
    """
    try:
        contents = project.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ReleaseError("Cannot read standalone Drawing project settings") from exc
    in_application = False
    seen_application = False
    settings: dict[str, str] = {}
    for line in contents.splitlines():
        entry = line.strip()
        if not entry or entry.startswith(("#", ";")):
            continue
        if entry.startswith("[") and entry.endswith("]"):
            in_application = entry == "[application]"
            if in_application:
                if seen_application:
                    raise ReleaseError("Duplicate standalone Drawing application section")
                seen_application = True
            continue
        if not in_application:
            continue
        key, separator, value = entry.partition("=")
        key = key.strip()
        if separator and key in ("config/name", "run/main_scene"):
            if key in settings:
                raise ReleaseError(f"Duplicate standalone Drawing application setting: {key}")
            settings[key] = value.strip()
    if (not seen_application or settings.get("config/name") != '"Drawing"'
            or settings.get("run/main_scene") != '"res://main.tscn"'):
        raise ReleaseError("Wrong standalone Drawing project identity or startup scene")


def inspect_stage(stage: Path, *, require_native: bool = True) -> dict[str, Any]:
    """Verify the separate source project is a Drawing-only staged consumer."""
    if not stage.is_dir() or stage.is_symlink():
        raise ReleaseError("Missing independent Drawing staging directory")
    # Inspect *every* staged entry, not just regular files. Release staging
    # may contain generated Godot caches and nested Drawing scripts, but an
    # undeclared sibling directory or special node must never be silently
    # accepted by the native packager.
    allowed_directories = {"addons", "addons/drawing", "scripts", "tests", ".godot"}
    allowed_subtrees = ("addons/drawing/", "scripts/", "tests/", ".godot/")
    files: dict[str, Path] = {}
    for path in stage.rglob("*"):
        relative = path.relative_to(stage).as_posix()
        if path.is_symlink():
            raise ReleaseError("Staged project contains symbolic links")
        if path.is_dir():
            if relative not in allowed_directories and not relative.startswith(allowed_subtrees):
                raise ReleaseError(f"Unexpected stage directory: {relative}")
        elif path.is_file():
            files[relative] = path
        else:
            raise ReleaseError(f"Non-regular stage entry: {relative}")
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
    _inspect_project_application(files["project.godot"])
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


def inspect_distribution_entries(
    directory: Path, platform: str, *, allow_missing_native: bool = False,
) -> dict[str, Path]:
    """Require an exact regular-file export tree, including directory entries.

    An omitted native ELF is allowed only for the pre-package Linux projection.
    FIFOs, sockets and unexpected empty directories are not distributable files.
    """
    if platform not in BINARY or not directory.is_dir() or directory.is_symlink():
        raise ReleaseError("Missing or unsupported distribution")
    expected = {BINARY[platform], "Drawing.pck"}
    if platform == "linux":
        expected.add(NATIVE_LIBRARY.as_posix())
    if allow_missing_native and platform != "linux":
        raise ReleaseError("Only Linux may stage an unpackaged native export")
    required = expected - ({NATIVE_LIBRARY.as_posix()} if allow_missing_native else set())
    expected_directories = {
        parent.as_posix()
        for name in expected
        for parent in Path(name).parents
        if parent != Path(".")
    }
    actual: dict[str, Path] = {}
    for entry in directory.rglob("*"):
        name = entry.relative_to(directory).as_posix()
        if entry.is_symlink():
            raise ReleaseError("Distribution contains a symlink")
        if entry.is_dir():
            if name not in expected_directories:
                raise ReleaseError(f"Unexpected export directory: {name}")
        elif entry.is_file():
            if name not in expected:
                raise ReleaseError(f"Unexpected export file: {name}")
            actual[name] = entry
        else:
            raise ReleaseError(f"Non-regular export entry: {name}")
    if set(actual) != required:
        raise ReleaseError("Distribution contains missing or unexpected exported artifacts")
    return actual


def _inspect_packed_project_config(stream: Any, start: int, length: int) -> None:
    """Read the bounded ECFG setting table emitted by Godot 4.8 export.

    Each entry is a byte-length-prefixed UTF-8 setting name followed by a
    byte-length-prefixed Variant. Only the required String values are decoded;
    other Godot Variant types remain opaque, but all entry boundaries and the
    complete table must be accounted for.
    """
    if not 8 <= length <= 8 * 1024 * 1024:
        raise ReleaseError("Invalid packed project configuration length")
    stream.seek(start)
    config = stream.read(length)
    if len(config) != length or config[:4] != b"ECFG":
        raise ReleaseError("Missing packed Godot project configuration")
    count = struct.unpack_from("<I", config, 4)[0]
    if not 1 <= count <= 65_536 or count * 12 > len(config) - 8:
        raise ReleaseError("Invalid packed project configuration count")
    required = {
        "application/config/name": "Drawing",
        "application/run/main_scene": "res://main.tscn",
    }
    seen: set[str] = set()
    position = 8
    for _ in range(count):
        if position + 4 > len(config):
            raise ReleaseError("Truncated packed project setting name")
        key_size = struct.unpack_from("<I", config, position)[0]
        position += 4
        if not 0 < key_size <= 4096 or position + key_size + 4 > len(config):
            raise ReleaseError("Invalid packed project setting name")
        try:
            key = config[position : position + key_size].decode("utf-8")
        except UnicodeError as exc:
            raise ReleaseError("Invalid packed project setting UTF-8") from exc
        position += key_size
        if key in seen or "\x00" in key or not key:
            raise ReleaseError("Duplicate or invalid packed project setting")
        seen.add(key)
        value_size = struct.unpack_from("<I", config, position)[0]
        position += 4
        if value_size < 4 or value_size > len(config) - position:
            raise ReleaseError("Truncated packed project setting value")
        if key in required:
            value = config[position : position + value_size]
            if len(value) < 8 or struct.unpack_from("<I", value)[0] != 4:
                raise ReleaseError(f"Invalid packed project String setting: {key}")
            text_size = struct.unpack_from("<I", value, 4)[0]
            if text_size > len(value) - 8:
                raise ReleaseError(f"Invalid packed project String length: {key}")
            try:
                text_value = value[8 : 8 + text_size].decode("utf-8")
            except UnicodeError as exc:
                raise ReleaseError(f"Invalid packed project String UTF-8: {key}") from exc
            canonical = struct.pack("<II", 4, text_size) + text_value.encode("utf-8")
            canonical += b"\x00" * (-text_size % 4)
            if value != canonical or text_value != required[key]:
                raise ReleaseError(f"Wrong packed Drawing project identity or startup: {key}")
        position += value_size
    if position != len(config) or not required.keys() <= seen:
        raise ReleaseError("Invalid packed Drawing project settings or trailing bytes")


def inspect_pck(pack: Path, platform: str = "linux") -> dict[str, int | str]:
    """Verify the pinned Godot 4.8 PCK v4 index and native startup witnesses.

    A GDPC magic prefix alone does not prove that a PCK can load Drawing. This
    bounded index parser verifies every indexed payload but does not execute
    scripts or establish runtime correctness; isolated launch is separate.
    """
    if platform not in BINARY:
        raise ReleaseError("Unsupported PCK platform")
    required = {"project.binary"}
    choices = [("main.tscn", "main.tscn.remap")]
    if platform == "linux":
        required.add(NATIVE_MANIFEST.as_posix())
        choices.append(("tests/native_extension_ready.gd", "tests/native_extension_ready.gd.remap"))
    size = pack.stat().st_size
    if size < 116:
        raise ReleaseError("Truncated Godot PCK index")
    with pack.open("rb") as stream:
        header = stream.read(112)
        magic, version, major, minor, _patch, flags, file_base, directory = struct.unpack_from(
            "<4sIIIIIQQ", header
        )
        if magic != b"GDPC" or version != 4 or (major, minor) != (4, 8):
            raise ReleaseError("Expected Godot 4.8 PCK v4")
        if flags & ~2 or file_base < 112 or not file_base < directory <= size - 4:
            raise ReleaseError("Unsupported or invalid Godot PCK index layout")
        stream.seek(directory)
        count = struct.unpack("<I", stream.read(4))[0]
        if count == 0 or count > 100_000 or count * 40 > size - directory - 4:
            raise ReleaseError("Invalid Godot PCK directory count")
        records: dict[str, tuple[int, int, bytes]] = {}
        for _ in range(count):
            raw_length = stream.read(4)
            if len(raw_length) != 4:
                raise ReleaseError("Truncated Godot PCK resource name")
            name_length = struct.unpack("<I", raw_length)[0]
            if name_length == 0 or name_length > 4096 or name_length % 4:
                raise ReleaseError("Invalid Godot PCK resource name length")
            name_bytes = stream.read(name_length)
            metadata = stream.read(36)
            if len(name_bytes) != name_length or len(metadata) != 36:
                raise ReleaseError("Truncated Godot PCK directory entry")
            try:
                name = name_bytes.rstrip(b"\x00").decode("utf-8")
            except UnicodeError as exc:
                raise ReleaseError("Invalid UTF-8 in Godot PCK directory") from exc
            # Godot stores a UTF-8 name followed by *only* the zero padding
            # needed for 4-byte alignment. rstrip() alone accepts embedded
            # NUL aliases and surplus whole alignment blocks, which are not
            # canonical resource names and may be interpreted differently by
            # consumers of the packed directory.
            encoded = name.encode("utf-8")
            canonical = encoded + b"\x00" * (-len(encoded) % 4)
            if name_bytes != canonical:
                raise ReleaseError("Invalid Godot PCK resource name padding or NUL bytes")
            if (
                not name
                or name.startswith("/")
                or "\\" in name
                or any(ord(char) < 32 or ord(char) == 127 for char in name)
                or any(part in ("", ".", "..") for part in name.split("/"))
            ):
                raise ReleaseError("Unsafe Godot PCK resource name")
            if name in records:
                raise ReleaseError(f"Duplicate Godot PCK resource: {name}")
            offset, length = struct.unpack_from("<QQ", metadata)
            resource_flags = struct.unpack_from("<I", metadata, 32)[0]
            absolute_offset = offset + file_base if flags & 2 else offset
            if (
                resource_flags != 0
                or absolute_offset < file_base
                or absolute_offset > directory
                or length > directory - absolute_offset
            ):
                raise ReleaseError(f"Invalid Godot PCK resource bounds: {name}")
            records[name] = (absolute_offset, length, metadata[16:32])
        if stream.tell() != size:
            raise ReleaseError("Trailing or truncated Godot PCK directory")
        # Nonempty resource extents must be disjoint, even if two records have
        # identical checksums. Empty files are valid and consume no extent.
        spans = sorted(
            (start, start + length, name)
            for name, (start, length, _) in records.items()
            if length
        )
        for previous, current in zip(spans, spans[1:]):
            if current[0] < previous[1]:
                raise ReleaseError(f"overlapping PCK resource payloads: {previous[2]} and {current[2]}")
        if not required.issubset(records):
            raise ReleaseError("PCK missing required native Drawing project resources")
        selected: list[str] = sorted(required)
        for options in choices:
            found = [name for name in options if name in records]
            if not found:
                raise ReleaseError(f"PCK missing required Drawing resource: {options[0]}")
            selected.extend(found)
        # Godot release exports replace source scripts/scenes with remaps. A
        # present remap is insufficient if its compiled target is absent.
        for name in ("main.tscn.remap", "tests/native_extension_ready.gd.remap"):
            if name not in records:
                continue
            start, length, _ = records[name]
            if not 0 < length <= 64 * 1024:
                raise ReleaseError(f"Invalid packed remap: {name}")
            stream.seek(start)
            remap = configparser.ConfigParser(interpolation=None)
            try:
                remap.read_string(stream.read(length).decode("utf-8"))
            except (UnicodeError, configparser.Error) as exc:
                raise ReleaseError(f"Malformed packed remap: {name}") from exc
            target = remap.get("remap", "path", fallback="").strip('"')
            if not target.startswith("res://") or target[6:] not in records:
                raise ReleaseError(f"Packed remap target missing: {name}")
            selected.append(target[6:])
        project_start, project_length, _ = records["project.binary"]
        _inspect_packed_project_config(stream, project_start, project_length)

        for name in selected:
            if records[name][1] == 0:
                raise ReleaseError(f"Empty required packed resource: {name}")

        # Check all indexed bytes, not only the startup/ABI subset. Otherwise a
        # corrupt font, script, or other non-critical resource may still pass
        # export preflight even though its stored Godot MD5 no longer matches.
        for name, (start, length, checksum) in records.items():
            stream.seek(start)
            remaining = length
            digest_value = hashlib.md5()  # noqa: S324 - Godot PCK uses MD5 as a file-integrity field.
            while remaining:
                chunk = stream.read(min(1024 * 1024, remaining))
                if not chunk:
                    raise ReleaseError(f"Truncated packed resource: {name}")
                digest_value.update(chunk)
                remaining -= len(chunk)
            if digest_value.digest() != checksum:
                raise ReleaseError(f"Packed resource checksum mismatch: {name}")
        if platform == "linux":
            manifest_start, manifest_length, _ = records[NATIVE_MANIFEST.as_posix()]
            if manifest_length > 64 * 1024:
                raise ReleaseError("Oversized packed native manifest")
            stream.seek(manifest_start)
            manifest = configparser.ConfigParser(interpolation=None)
            try:
                manifest.read_string(stream.read(manifest_length).decode("utf-8"))
            except (UnicodeError, configparser.Error) as exc:
                raise ReleaseError("Malformed packed native manifest") from exc
            if manifest.get("configuration", "entry_symbol", fallback="").strip(
                '"'
            ) != "gdext_rust_init" or any(
                manifest.get("libraries", key, fallback="").strip('"') != NATIVE_RESOURCE
                for key in ("linux.release.x86_64", "linux.debug.x86_64")
            ):
                raise ReleaseError("Packed native manifest does not match required Rust ABI")
        return {
            "format_version": version,
            "file_count": count,
            "resources_verified": len(records),
            "startup_scene": next(name for name in choices[0] if name in records),
        }


def inspect_distribution(directory: Path, platform: str) -> dict[str, Any]:
    """Require separate, native x86_64 Godot executable and packed resources."""
    files = inspect_distribution_entries(directory, platform)
    exe = directory / BINARY[platform]
    pack = directory / "Drawing.pck"
    if not exe.is_file() or not pack.is_file() or exe.stat().st_size < 4096 or pack.stat().st_size < 64:
        raise ReleaseError("Missing or truncated executable or PCK")
    _inspect_binary(exe, platform)
    pack_info = inspect_pck(pack, platform=platform)
    native_info: dict[str, str | int] | None = None
    if platform == "linux":
        native = files[NATIVE_LIBRARY.as_posix()]
        if native.stat().st_size < 4096:
            raise ReleaseError("Missing or truncated required native library")
        _inspect_binary(native, "linux", shared=True)
        native_info = {
            "name": NATIVE_LIBRARY.as_posix(),
            "size": native.stat().st_size,
            "sha256": digest(native),
        }
    return {
        "platform": platform,
        "architecture": "x86_64",
        "binary": {"name": exe.name, "size": exe.stat().st_size, "sha256": digest(exe)},
        "pack": {"name": pack.name, "size": pack.stat().st_size, "sha256": digest(pack), "index": pack_info},
        "native_extension_shipped": platform == "linux",
        "native_library": native_info,
        "inspection": "structure_and_required_native"
        if platform == "linux"
        else "structure_only_no_windows_native",
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
