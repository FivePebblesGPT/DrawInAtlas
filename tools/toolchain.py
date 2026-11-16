#!/usr/bin/env python3
"""Portable Linux toolchain acquisition, inspection and command execution.

Make owns build ordering. This helper only selects/verifies tools, creates
the offline toolchain archive, and runs a command inside the selected toolchain.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "toolchain.lock.toml"
BUILD = ROOT / ".build"
MANIFEST = "bundle-manifest.json"


class ToolchainError(RuntimeError):
    """An actionable toolchain or artifact validation error."""


def sha256_file(path: Path) -> str:
    """Return the SHA-256 of a file without buffering it in memory."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pins() -> dict:
    with LOCK_PATH.open("rb") as stream:
        return tomllib.load(stream)


def check_platform() -> None:
    if sys.platform != "linux" or platform.machine() not in ("x86_64", "amd64"):
        raise ToolchainError("Bundle mode currently supports Linux x86-64 only; use TOOLCHAIN=system elsewhere")


def run(argv: list[str], *, env: dict[str, str] | None = None, cwd: Path | None = None) -> None:
    subprocess.run(argv, check=True, env=env, cwd=cwd)


def download(url: str, expected_sha: str, destination: Path) -> None:
    if not url.startswith("https://") or len(expected_sha) != 64:
        raise ToolchainError("Toolchain downloads require HTTPS and a pinned SHA-256 digest")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and sha256_file(destination) == expected_sha:
        return
    temp = destination.with_suffix(destination.suffix + ".part")
    try:
        with urllib.request.urlopen(url, timeout=120) as source, temp.open("wb") as output:
            shutil.copyfileobj(source, output)
        actual = sha256_file(temp)
        if actual != expected_sha:
            raise ToolchainError(f"SHA-256 mismatch for {url}: {actual} != {expected_sha}")
        os.replace(temp, destination)
    finally:
        temp.unlink(missing_ok=True)


def select_tar_path(name: str) -> Path:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ToolchainError(f"Unsafe archive member: {name}")
    return Path(*[part for part in path.parts if part not in (".", "")])


def safe_extract_zstd(archive: Path, destination: Path) -> None:
    """Extract regular files and directories; forbid links and traversal."""
    zstd = shutil.which("zstd")
    if zstd is None:
        raise ToolchainError("zstd is required to read .tar.zst bundles")
    process = subprocess.Popen([zstd, "-dc", str(archive)], stdout=subprocess.PIPE)
    assert process.stdout is not None
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as stream:
            for member in stream:
                rel = select_tar_path(member.name)
                path = destination / rel
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    path.parent.mkdir(parents=True, exist_ok=True)
                    contents = stream.extractfile(member)
                    if contents is None:
                        raise ToolchainError(f"Could not extract {member.name}")
                    with contents, path.open("wb") as output:
                        shutil.copyfileobj(contents, output)
                    path.chmod(member.mode & 0o777)
                else:
                    raise ToolchainError(f"Bundle contains unsupported link/special member: {member.name}")
        if process.wait() != 0:
            raise ToolchainError(f"zstd decompression failed: {archive}")
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.kill()
            process.wait()


def find_bundle_root(directory: Path) -> Path:
    if (directory / MANIFEST).is_file() or (directory / "setup-rust-env.sh").is_file():
        return directory
    for child in directory.iterdir():
        if child.is_dir() and ((child / MANIFEST).is_file() or (child / "setup-rust-env.sh").is_file()):
            return child
    raise ToolchainError(f"No recognized bundle layout under {directory}")


def verify_extracted(directory: Path, *, legacy: bool = False) -> None:
    manifest_path = directory / MANIFEST
    if not manifest_path.is_file():
        if legacy and (directory / "setup-rust-env.sh").is_file():
            if not (directory / "rust-hokusai" / "vendor").is_dir():
                raise ToolchainError("Legacy bundle is missing the vendored Cargo registry")
            return
        raise ToolchainError("Missing bundle-manifest.json; cannot verify unpacked toolchain")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or manifest.get("platform") != pins()["platform"]:
        raise ToolchainError("Unsupported bundle manifest/platform")
    if manifest.get("lock_sha256") != sha256_file(LOCK_PATH):
        raise ToolchainError("Bundle was built against a different toolchain.lock.toml")
    if manifest.get("cargo_lock_sha256") != sha256_file(ROOT / "native/drawing_brush/Cargo.lock"):
        raise ToolchainError("Bundle was built against a different Cargo.lock; regenerate it")
    expected = manifest.get("files")
    if not isinstance(expected, dict) or not expected:
        raise ToolchainError("Malformed/empty bundle file manifest")
    actual_paths: set[str] = set()
    for path in directory.rglob("*"):
        if path.is_symlink():
            raise ToolchainError(f"Bundle contains a symlink: {path}")
        if not path.is_file() or path == manifest_path or path.name == ".complete":
            continue
        relative = path.relative_to(directory).as_posix()
        actual_paths.add(relative)
        if sha256_file(path) != expected.get(relative):
            raise ToolchainError(f"Missing, unexpected or corrupted bundle file: {relative}")
    if actual_paths != set(expected):
        raise ToolchainError(f"Bundle manifest file list differs: {sorted(set(expected) - actual_paths)[:5]}")


def resolve_bundle(value: str) -> tuple[Path, bool]:
    check_platform()
    if not value:
        raise ToolchainError("TOOLCHAIN=bundle requires BUNDLE=/path/to/archive.tar.zst or extracted directory")
    path = Path(value).expanduser().resolve()
    if path.is_dir():
        root = find_bundle_root(path)
        verify_extracted(root, legacy=True)
        return root, not (root / MANIFEST).exists()
    if not path.is_file():
        raise ToolchainError(f"Bundle does not exist: {path}")
    digest = sha256_file(path)
    legacy = pins()["legacy_bundle"]
    is_legacy = path.name == legacy["filename"]
    if is_legacy and digest != legacy["sha256"]:
        raise ToolchainError("Legacy bundle SHA-256 does not match the committed lockfile")
    sidecar = path.with_name(path.name + ".sha256")
    if sidecar.is_file() and sidecar.read_text(encoding="utf-8").split()[0] != digest:
        raise ToolchainError("Bundle archive SHA-256 sidecar mismatch")
    destination = BUILD / "toolchains" / digest
    if not (destination / ".complete").is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        temp = Path(tempfile.mkdtemp(prefix="unpack-", dir=destination.parent))
        try:
            safe_extract_zstd(path, temp)
            root = find_bundle_root(temp)
            verify_extracted(root, legacy=is_legacy)
            (temp / ".complete").write_text(digest, encoding="ascii")
            if destination.exists():
                shutil.rmtree(destination)
            os.replace(temp, destination)
        finally:
            if temp.exists():
                shutil.rmtree(temp)
    root = find_bundle_root(destination)
    verify_extracted(root, legacy=is_legacy)
    return root, is_legacy


def tool_paths(mode: str, bundle: str) -> tuple[dict[str, str], Path | None, bool]:
    if mode not in ("auto", "system", "bundle"):
        raise ToolchainError(f"Unknown toolchain mode: {mode}")
    use_bundle = mode == "bundle" or (mode == "auto" and bool(bundle))
    env = os.environ.copy()
    if not use_bundle:
        if env.get("RUST_BIN"):
            env["PATH"] = env["RUST_BIN"] + os.pathsep + env["PATH"]
        return env, None, False
    root, legacy = resolve_bundle(bundle)
    env["CARGO_NET_OFFLINE"] = "true"
    if (root / "rust/bin/cargo").is_file():
        env["CARGO"] = str(root / "rust/bin/cargo")
    env["UV_OFFLINE"] = "1"
    env["UV_PYTHON_DOWNLOADS"] = "never"
    env["CARGO_TARGET_DIR"] = str(BUILD / "target")
    env["CARGO_BUILD_TARGET"] = pins()["platform"]
    vendor = root / "vendor" if (root / "vendor").is_dir() else root / "rust-hokusai/vendor"
    if not vendor.is_dir():
        raise ToolchainError("Bundle lacks Cargo vendor directory")
    env["CARGO_VENDOR_DIR"] = str(vendor)
    if (root / "uv-cache").is_dir():
        env["UV_CACHE_DIR"] = str(root / "uv-cache")
    env["PATH"] = os.pathsep.join([str(root / "rust/bin"), str(root / "bin"), env["PATH"]])
    return env, root, legacy


def find_godot(root: Path) -> Path:
    preferred = root / "bin/godot"
    if preferred.is_file():
        return preferred
    candidates = (
        list(root.glob("Godot_v4.8*linux.x86_64"))
        + list(root.glob("*/Godot_v4.8*linux.x86_64"))
        + list(root.glob("*/*/Godot_v4.8*linux.x86_64"))
    )
    if len(candidates) == 1:
        return candidates[0]
    raise ToolchainError("Godot beta3 executable missing or ambiguous inside bundle")


def tool_command(command: list[str], env: dict[str, str], root: Path | None, legacy: bool) -> list[str]:
    if not command:
        raise ToolchainError("No command supplied after --")
    command = list(command)
    aliases = {"godot": "GODOT", "cargo": "CARGO", "uv": "UV"}
    tool = command[0]
    if root is None and tool in aliases:
        command[0] = env.get(aliases[tool], tool)
    if root is not None:
        if tool == "godot":
            command[0] = str(find_godot(root))
        elif tool == "cargo" and (root / "rust/bin/cargo").is_file():
            command[0] = str(root / "rust/bin/cargo")
        elif tool == "uv" and (root / "bin/uv").is_file():
            command[0] = str(root / "bin/uv")
        if legacy and (root / "setup-rust-env.sh").is_file():
            return ["bash", "-c", 'set -e; source "$1"; shift; exec "$@"', "bundle-env",
                    str(root / "setup-rust-env.sh"), *command]
    return command


def exec_command(mode: str, bundle: str, command: list[str]) -> int:
    env, root, legacy = tool_paths(mode, bundle)
    argv = tool_command(command, env, root, legacy)
    return subprocess.call(argv, env=env, cwd=ROOT)


def doctor(mode: str, bundle: str) -> int:
    env, root, legacy = tool_paths(mode, bundle)
    print(f"mode={'bundle' if root else 'system'} platform={sys.platform}/{platform.machine()}")
    print(f"python={sys.executable} version={platform.python_version()}")
    print(f"bundle={root if root else '(none)'}")
    failures = 0
    for key, args, want in (
        ("Godot", ["godot", "--version"], pins()["godot"]["version"]),
        ("Rust", ["rustc", "--version"], pins()["rust"]["version"]),
        ("Cargo", ["cargo", "--version"], None),
        ("uv", ["uv", "--version"], pins()["uv"]["version"]),
    ):
        try:
            cmd = tool_command(args, env, root, legacy)
            output = subprocess.check_output(cmd, env=env, cwd=ROOT, stderr=subprocess.STDOUT, text=True).strip()
            print(f"{key}: {output}")
            if want and want.lower() not in output.lower():
                print(f"  EXPECTED {want}")
                failures += 1
        except (FileNotFoundError, subprocess.CalledProcessError, ToolchainError) as exc:
            print(f"{key}: UNAVAILABLE ({exc})")
            failures += 1
    if root is not None:
        print(f"Cargo vendor: {env['CARGO_VENDOR_DIR']}")
    for rel in ("addons/drawing/native/bin/libdrawing_brush.so",
                "drawing/addons/drawing/native/bin/libdrawing_brush.so"):
        print(f"{rel}: {'present' if (ROOT / rel).is_file() else 'missing'}")
    return 1 if failures else 0


def extract_godot(archive: Path, destination: Path, expected_name: str) -> None:
    with zipfile.ZipFile(archive) as zipped:
        matches = [x for x in zipped.infolist() if PurePosixPath(x.filename).name == expected_name]
        if len(matches) != 1 or matches[0].is_dir():
            raise ToolchainError("Pinned Godot archive does not contain the expected executable")
        with zipped.open(matches[0]) as source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)
    destination.chmod(0o755)


def extract_uv(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:gz") as t:
        matches = [m for m in t if PurePosixPath(m.name).name == "uv" and m.isfile()]
        if len(matches) != 1:
            raise ToolchainError("Pinned uv archive does not contain exactly one uv binary")
        content = t.extractfile(matches[0])
        if content is None:
            raise ToolchainError("Cannot read pinned uv archive")
        with content, destination.open("wb") as output:
            shutil.copyfileobj(content, output)
    destination.chmod(0o755)


def bundle(output: Path, python: str) -> None:
    check_platform()
    lock = pins()
    if shutil.which("rustup") is None:
        raise ToolchainError("Generating bundles requires rustup on the ONLINE builder")
    if shutil.which("tar") is None or shutil.which("zstd") is None:
        raise ToolchainError("Generating bundles requires GNU tar and zstd")
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    download_cache = BUILD / "downloads"
    godot_zip = download_cache / "godot-4.8-beta3.zip"
    uv_tgz = download_cache / "uv-linux-x86_64.tar.gz"
    download(lock["godot"]["url"], lock["godot"]["sha256"], godot_zip)
    download(lock["uv"]["url"], lock["uv"]["sha256"], uv_tgz)

    rust = lock["rust"]["version"]
    rustup_cmd = ["rustup", "toolchain", "install", rust, "--profile", "minimal"]
    for component in lock["rust"]["components"]:
        rustup_cmd.extend(["--component", component])
    run(rustup_cmd)
    rustc = Path(subprocess.check_output(
        ["rustup", "which", "--toolchain", rust, "rustc"], text=True).strip()).resolve()
    rust_dir = rustc.parent.parent
    with tempfile.TemporaryDirectory(prefix="toolchain-build-", dir=output.parent) as tmp:
        stage = Path(tmp) / "stage"
        (stage / "bin").mkdir(parents=True)
        shutil.copytree(rust_dir, stage / "rust")
        extract_godot(godot_zip, stage / "bin/godot", lock["godot"]["executable"])
        extract_uv(uv_tgz, stage / "bin/uv")
        rust_env = os.environ.copy()
        rust_env["CARGO_NET_OFFLINE"] = "false"
        rust_env["PATH"] = str(rust_dir / "bin") + os.pathsep + rust_env["PATH"]
        run(["cargo", "vendor", "--locked", "--versioned-dirs", str(stage / "vendor")],
            env=rust_env, cwd=ROOT / "native/drawing_brush")

        # Populate the portable uv cache for the requested Python minor.
        # The sandbox still uses its system interpreter; no Python distribution is shipped.
        uv_env = os.environ.copy()
        uv_env["UV_CACHE_DIR"] = str(stage / "uv-cache")
        uv_env["UV_PYTHON_DOWNLOADS"] = "never"
        for name in ("ruff", "ty"):
            run([str(stage / "bin/uv"), "run", "--no-project", "--no-managed-python",
                 "--python", python, "--with", f"{name}=={lock['python_tools'][name]}",
                 "--", name, "--version"], env=uv_env, cwd=ROOT)
        version_env = rust_env.copy()
        for executable, version in (
            ([str(stage / "rust/bin/rustc"), "--version"], lock["rust"]["version"]),
            ([str(stage / "bin/godot"), "--version"], lock["godot"]["version"]),
            ([str(stage / "bin/uv"), "--version"], lock["uv"]["version"]),
        ):
            value = subprocess.check_output(executable, env=version_env, text=True).strip()
            if version.lower() not in value.lower():
                raise ToolchainError(f"Expected {version}, got {value}")

        files = {
            p.relative_to(stage).as_posix(): sha256_file(p)
            for p in sorted(stage.rglob("*")) if p.is_file()
        }
        manifest = {
            "format": 1,
            "platform": lock["platform"],
            "python_builder_minor": f"{sys.version_info.major}.{sys.version_info.minor}",
            "lock_sha256": sha256_file(LOCK_PATH),
            "cargo_lock_sha256": sha256_file(ROOT / "native/drawing_brush/Cargo.lock"),
            "files": files,
        }
        (stage / MANIFEST).write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n",
                                     encoding="utf-8")
        temporary_archive = output.with_name(output.name + ".part")
        try:
            run(["tar", "--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--hard-dereference",
                 "--numeric-owner", "--dereference", "-I", "zstd -19 -T1", "-cf",
                 str(temporary_archive), "-C", str(stage), "."])
            os.replace(temporary_archive, output)
        finally:
            temporary_archive.unlink(missing_ok=True)
    digest = sha256_file(output)
    output.with_name(output.name + ".sha256").write_text(
        f"{digest}  {output.name}\n", encoding="ascii")
    print(f"Bundle generated: {output}\nSHA-256: {digest}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    for action in ("exec", "doctor"):
        entry = commands.add_parser(action)
        entry.add_argument("--mode", default="auto", choices=("auto", "system", "bundle"))
        entry.add_argument("--bundle", default="")
        if action == "exec":
            entry.add_argument("command", nargs=argparse.REMAINDER)
    create = commands.add_parser("bundle")
    create.add_argument("--output", required=True, type=Path)
    create.add_argument("--python", default=sys.executable)
    verify = commands.add_parser("verify")
    verify.add_argument("--bundle", required=True)
    pin = commands.add_parser("pin")
    pin.add_argument("name", choices=("ruff", "ty"))

    args = parser.parse_args()
    try:
        if args.action == "exec":
            command = args.command[1:] if args.command[:1] == ["--"] else args.command
            return exec_command(args.mode, args.bundle, command)
        if args.action == "doctor":
            return doctor(args.mode, args.bundle)
        if args.action == "bundle":
            bundle(args.output, args.python)
            return 0
        if args.action == "verify":
            root, legacy = resolve_bundle(args.bundle)
            verify_extracted(root, legacy=legacy)
            print(f"Verified bundle: {root}")
            return 0
        if args.action == "pin":
            print(pins()["python_tools"][args.name])
            return 0
    except (ToolchainError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"toolchain: {exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
