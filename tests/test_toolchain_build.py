"""Unit checks for source-locked toolchain and native staging contracts."""

from __future__ import annotations

import hashlib
import io
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.prepare_native_project import EXTENSION, prepare
from tools.toolchain import (
    LOCK_PATH,
    ROOT,
    UPLOAD_LIMIT_BYTES,
    ToolchainError,
    check_bundle_size,
    download,
    exec_command,
    normalize_rust_metadata,
    pins,
    resolve_bundle,
    safe_extract_zstd,
    select_tar_path,
    sha256_file,
    tool_command,
    tool_paths,
    verify_extracted,
    write_bundle_archive,
)


class ToolchainTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("zstd"), "zstd required for archive creation")
    def test_single_archive_has_internal_sums_and_rejects_repo_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            stage = directory / "stage"
            stage.mkdir()
            for name in ("bin", "rust", "vendor", "wheels"):
                (stage / name).mkdir()
            manifest = '{"files": {"bin/tool": "checksum-fixture"}}\n'
            (stage / "bundle-manifest.json").write_text(manifest)
            (stage / "bin/tool").write_bytes(b"tool-fixture")
            output = directory / "bundle.tar.zst"
            sidecar = directory / "bundle.tar.zst.sha256"
            sidecar.write_text("stale")
            write_bundle_archive(stage, output)
            self.assertTrue(output.is_file())
            self.assertFalse(sidecar.exists())
            unpacked = directory / "unpacked"
            unpacked.mkdir()
            safe_extract_zstd(output, unpacked)
            self.assertEqual((unpacked / "bundle-manifest.json").read_text(), manifest)
            self.assertEqual((unpacked / "bin/tool").read_bytes(), b"tool-fixture")
            (stage / "repo").mkdir()
            with self.assertRaisesRegex(ToolchainError, "no repo"):
                write_bundle_archive(stage, output)

    def test_godot_zero_exit_does_not_hide_script_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            godot = Path(temp) / "fake Godot"
            godot.write_text(
                '#!/bin/sh\nif [ "$1" = "--version" ]; then\n'
                f'  printf "{pins()["godot"]["version"]}.official\\n"\n'
                'else\n  printf "SCRIPT ERROR: injected error\\n" >&2\nfi\n'
            )
            godot.chmod(0o755)
            with patch.dict("os.environ", {"GODOT": str(godot)}):
                with self.assertRaisesRegex(ToolchainError, "even if its exit code was zero"):
                    exec_command("system", "", ["godot", "--headless", "--script", "fixture.gd"])

    def test_upload_size_limit_inclusive_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "bundle.tar.zst"
            with archive.open("wb") as stream:
                stream.truncate(UPLOAD_LIMIT_BYTES)
            self.assertEqual(check_bundle_size(archive), UPLOAD_LIMIT_BYTES)
            with archive.open("r+b") as stream:
                stream.truncate(UPLOAD_LIMIT_BYTES + 1)
            with self.assertRaisesRegex(ToolchainError, "upload limit is 500 MiB"):
                check_bundle_size(archive)

    def test_rust_component_registry_is_canonical(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            rust = Path(temp)
            registry = rust / "lib/rustlib/components"
            registry.parent.mkdir(parents=True)
            registry.write_text("rustc\ncargo\nclippy\n")
            normalize_rust_metadata(rust)
            self.assertEqual(registry.read_text(), "cargo\nclippy\nrustc\n")

    def test_pins_have_valid_sha256(self) -> None:
        lock = pins()
        self.assertEqual(lock["platform"], "x86_64-unknown-linux-gnu")
        for section in ("godot", "uv"):
            self.assertEqual(len(lock[section]["sha256"]), 64)
            int(lock[section]["sha256"], 16)
            self.assertTrue(lock[section]["url"].startswith("https://"))

    def test_pinned_local_archive_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source.zip"
            destination = Path(temp) / "download.zip"
            source.write_bytes(b"verified bytes")
            digest = hashlib.sha256(b"verified bytes").hexdigest()
            download("https://example.invalid/source.zip", digest, destination, str(source))
            self.assertEqual(destination.read_bytes(), b"verified bytes")
            source.write_bytes(b"changed bytes")
            with self.assertRaisesRegex(ToolchainError, "SHA-256"):
                download("https://example.invalid/source.zip", digest, destination, str(source))

    def test_python_wheels_are_universal_and_source_pinned(self) -> None:
        lock = pins()
        for name, version in lock["python_tools"].items():
            wheel = lock["wheels"][name]
            self.assertIn(f"{name}-{version}-py3-none-manylinux_2_17_x86_64", wheel["url"])
            self.assertEqual(len(wheel["sha256"]), 64)
            int(wheel["sha256"], 16)

    def test_archive_paths_reject_traversal(self) -> None:
        for path in ("../etc/passwd", "/tmp/payload", "a/../../etc/passwd"):
            with self.subTest(path=path), self.assertRaises(ToolchainError):
                select_tar_path(path)
        self.assertEqual(select_tar_path("./bin/godot"), Path("bin/godot"))

    @unittest.skipUnless(shutil.which("zstd"), "zstd required for bundle extraction")
    def test_streaming_extractor_rejects_links_traversal_and_corruption(self) -> None:
        for name, kind in (
            ("../escape", tarfile.REGTYPE),
            ("/escape", tarfile.REGTYPE),
            ("symlink", tarfile.SYMTYPE),
            ("hardlink", tarfile.LNKTYPE),
            ("fifo", tarfile.FIFOTYPE),
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp)
                raw = io.BytesIO()
                with tarfile.open(fileobj=raw, mode="w") as stream:
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    member.linkname = "/etc/passwd" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
                    stream.addfile(member)
                archive = directory / "bad.tar.zst"
                archive.write_bytes(subprocess.check_output(["zstd", "-q", "-c"], input=raw.getvalue()))
                output = directory / "unpack"
                output.mkdir()
                with self.assertRaises(ToolchainError):
                    safe_extract_zstd(archive, output)
                self.assertFalse((directory / "escape").exists())
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "corrupt.tar.zst"
            archive.write_bytes(b"not zstd")
            with self.assertRaises((ToolchainError, tarfile.TarError)):
                safe_extract_zstd(archive, Path(temp) / "unpack")

    def test_bad_or_empty_sidecar_rejected_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "bundle.tar.zst"
            archive.write_bytes(b"fixture")
            sidecar = archive.with_name(archive.name + ".sha256")
            for text in ("", "0" * 64):
                with self.subTest(text=text):
                    sidecar.write_text(text)
                    with self.assertRaisesRegex(ToolchainError, "sidecar mismatch"):
                        resolve_bundle(str(archive))

    def test_unsupported_platform_and_malformed_manifest_fail_clearly(self) -> None:
        with patch("tools.toolchain.sys.platform", "win32"):
            with self.assertRaisesRegex(ToolchainError, "Linux x86-64 only"):
                resolve_bundle("fixture.tar.zst")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "bundle-manifest.json").write_text("[]")
            with self.assertRaisesRegex(ToolchainError, "Malformed bundle manifest"):
                verify_extracted(root)

    def test_manifest_verifies_bytes_and_rejects_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = root / "bin/godot"
            payload.parent.mkdir()
            payload.write_bytes(b"godot-test")
            manifest = {
                "format": 1,
                "platform": pins()["platform"],
                "lock_sha256": sha256_file(LOCK_PATH),
                "cargo_lock_sha256": sha256_file(ROOT / "native/drawing_brush/Cargo.lock"),
                "files": {"bin/godot": hashlib.sha256(b"godot-test").hexdigest()},
            }
            (root / "bundle-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            (root / ".complete").write_text("extraction marker", encoding="utf-8")
            verify_extracted(root)
            for key, text in (
                ("lock_sha256", "toolchain.lock.toml"),
                ("cargo_lock_sha256", "Cargo.lock"),
                ("platform", "platform"),
            ):
                changed = {**manifest, key: "changed"}
                (root / "bundle-manifest.json").write_text(json.dumps(changed), encoding="utf-8")
                with self.assertRaisesRegex(ToolchainError, text):
                    verify_extracted(root)
            (root / "bundle-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            payload.write_bytes(b"corrupted")
            with self.assertRaises(ToolchainError):
                verify_extracted(root)

    def test_system_mode_does_not_require_bundle(self) -> None:
        env, root, legacy = tool_paths("system", "")
        self.assertIsNone(root)
        self.assertFalse(legacy)
        env["GODOT"] = "/custom/godot"
        self.assertEqual(tool_command(["godot", "--version"], env, root, legacy)[0], "/custom/godot")

    def test_bundle_missing_tools_never_falls_back_to_system(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "vendor").mkdir()
            with patch("tools.toolchain.resolve_bundle", return_value=(root, False)):
                with self.assertRaisesRegex(ToolchainError, "missing.*rust|Missing.*rust"):
                    tool_paths("bundle", str(root))

    def test_bundle_uses_private_writable_cache_and_explicit_rust(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for relative in (
                "bin/godot",
                "bin/uv",
                "rust/bin/cargo",
                "rust/bin/rustc",
                "rust/bin/rustfmt",
                "rust/bin/rustdoc",
            ):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("#!/bin/sh\nexit 0\n")
                path.chmod(0o755)
            (root / "vendor").mkdir()
            (root / "wheels").mkdir()
            with patch("tools.toolchain.resolve_bundle", return_value=(root, False)):
                with patch.dict(
                    "os.environ",
                    {
                        "RUSTC": "/bad/rustc",
                        "CARGO": "/bad/cargo",
                        "UV": "/bad/uv",
                        "RUSTC_WRAPPER": "/bad/wrapper",
                    },
                ):
                    env, _, _ = tool_paths("bundle", str(root))
            self.assertEqual(env["RUSTC"], str(root / "rust/bin/rustc"))
            self.assertEqual(env["CARGO"], str(root / "rust/bin/cargo"))
            self.assertEqual(env["UV"], str(root / "bin/uv"))
            self.assertNotIn("RUSTC_WRAPPER", env)
            self.assertFalse(Path(env["UV_CACHE_DIR"]).is_relative_to(root))
            self.assertEqual(env["UV_NO_INDEX"], "1")
            self.assertEqual(env["UV_FIND_LINKS"], str(root / "wheels"))

    def test_native_registration_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            native = root / "addons/drawing/native"
            (native / "bin").mkdir(parents=True)
            (native / "bin/libdrawing_brush.so").write_bytes(b"native-fixture")
            (native / "drawing_brush.gdextension").write_text(
                '[configuration]\nentry_symbol = "gdext_rust_init"\n[libraries]\nlinux.release.x86_64 = "res://addons/drawing/native/bin/libdrawing_brush.so"\n',
                encoding="utf-8",
            )
            self.assertEqual(prepare(root), prepare(root))
            self.assertEqual((root / ".godot/extension_list.cfg").read_text(), EXTENSION + "\n")

    def test_registration_fails_without_binary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Required Brush/Eraser extension"):
                prepare(root)


if __name__ == "__main__":
    unittest.main()
