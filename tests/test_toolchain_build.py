"""Unit checks for source-locked toolchain and native staging contracts."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.prepare_native_project import EXTENSION, prepare
from tools.toolchain import (
    LOCK_PATH,
    ROOT,
    ToolchainError,
    pins,
    select_tar_path,
    sha256_file,
    tool_command,
    tool_paths,
    verify_extracted,
)


class ToolchainTests(unittest.TestCase):
    def test_pins_have_valid_sha256(self) -> None:
        lock = pins()
        self.assertEqual(lock["platform"], "x86_64-unknown-linux-gnu")
        for section in ("godot", "uv"):
            self.assertEqual(len(lock[section]["sha256"]), 64)
            int(lock[section]["sha256"], 16)
            self.assertTrue(lock[section]["url"].startswith("https://"))

    def test_archive_paths_reject_traversal(self) -> None:
        for path in ("../etc/passwd", "/tmp/payload", "a/../../etc/passwd"):
            with self.subTest(path=path), self.assertRaises(ToolchainError):
                select_tar_path(path)
        self.assertEqual(select_tar_path("./bin/godot"), Path("bin/godot"))

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
            payload.write_bytes(b"corrupted")
            with self.assertRaises(ToolchainError):
                verify_extracted(root)

    def test_system_mode_does_not_require_bundle(self) -> None:
        env, root, legacy = tool_paths("system", "")
        self.assertIsNone(root)
        self.assertFalse(legacy)
        env["GODOT"] = "/custom/godot"
        self.assertEqual(tool_command(["godot", "--version"], env, root, legacy)[0],
                         "/custom/godot")

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
