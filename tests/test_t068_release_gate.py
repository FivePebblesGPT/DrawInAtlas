"""T-068: portable Drawing release inspection cannot be passed by editor-only files."""
from __future__ import annotations

from pathlib import Path
import stat
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
sys.path.insert(0, str(ROOT / "tools"))
import t068_release_gate as release  # noqa: E402
from build_drawing_app import stage  # noqa: E402


def write_binary(directory: Path, platform: str) -> Path:
    result = directory / release.BINARY[platform]
    data = bytearray(4096)
    if platform == "linux":
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", data, 18, 62)
    else:
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 256)
        data[256:260] = b"PE\0\0"
        data[260:262] = b"\x64\x86"
    result.write_bytes(data)
    result.chmod(result.stat().st_mode | stat.S_IXUSR)
    (directory / "Drawing.pck").write_bytes(b"GDPC" + bytes(128))
    return result


class PortableReleaseGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.stage = stage(self.base / "project")
        self.linux = self.base / "linux"
        self.linux.mkdir()
        self.windows = self.base / "windows"
        self.windows.mkdir()
        write_binary(self.linux, "linux")
        write_binary(self.windows, "windows")

    def test_standalone_staging_and_static_artifact_fingerprints(self) -> None:
        report = release.inspect_release(self.stage, self.linux, self.windows)
        self.assertEqual(report["schema"], "t068-portable-export-v1")
        self.assertEqual(report["linux"]["architecture"], "x86_64")
        self.assertEqual(report["windows"]["architecture"], "x86_64")
        self.assertNotIn("runtime", report["windows"])
        self.assertTrue(report["stage"]["file_count"] > 20)
        self.assertEqual(report["linux"]["pack"]["sha256"],
                         release.digest(self.linux / "Drawing.pck"))

    def test_nonportable_or_corrupt_artifacts_fail_closed(self) -> None:
        exe = self.linux / "Drawing.x86_64"
        payload = bytearray(exe.read_bytes())
        with self.subTest("wrong_architecture"):
            broken = bytearray(payload)
            struct.pack_into("<H", broken, 18, 183)  # ARM64
            exe.write_bytes(broken)
            with self.assertRaises(release.ReleaseError):
                release.inspect_distribution(self.linux, "linux")
        exe.write_bytes(payload)
        exe.chmod(0o755)
        with self.subTest("invalid_pck"):
            (self.linux / "Drawing.pck").write_bytes(b"PCK?" + bytes(128))
            with self.assertRaises(release.ReleaseError):
                release.inspect_distribution(self.linux, "linux")
        (self.linux / "Drawing.pck").write_bytes(b"GDPC" + bytes(128))
        with self.subTest("native_library"):
            (self.linux / "experimental.so").write_bytes(b"native")
            with self.assertRaises(release.ReleaseError):
                release.inspect_distribution(self.linux, "linux")
        (self.linux / "experimental.so").unlink()
        with self.subTest("atlas_source_leak"):
            extra = self.stage / "campaign"
            extra.mkdir()
            (extra / "atlas.gd").write_text("extends Node\n")
            with self.assertRaises(release.ReleaseError):
                release.inspect_stage(self.stage)
            (extra / "atlas.gd").unlink()
            extra.rmdir()
        with self.subTest("windows_wrong_machine"):
            win = self.windows / "Drawing.exe"
            broken = bytearray(win.read_bytes())
            broken[260:262] = b"\x4c\x01"  # i386
            win.write_bytes(broken)
            with self.assertRaises(release.ReleaseError):
                release.inspect_distribution(self.windows, "windows")
        with self.subTest("missing_artifact"):
            (self.linux / "Drawing.pck").unlink()
            with self.assertRaises(release.ReleaseError):
                release.inspect_release(self.stage, self.linux, self.windows)

    def test_stage_rejects_native_extensions_and_bad_identity(self) -> None:
        illegal = self.stage / "addons/drawing/scalar.gdextension"
        illegal.write_text("[configuration]\n", encoding="utf-8")
        with self.assertRaises(release.ReleaseError):
            release.inspect_stage(self.stage)
        illegal.unlink()
        project = self.stage / "project.godot"
        project.write_text('config/name="Atlas"\n', encoding="utf-8")
        with self.assertRaises(release.ReleaseError):
            release.inspect_stage(self.stage)

    def test_isolated_launch_accepts_only_named_post_exit_rids(self) -> None:
        version = "Godot Engine v4.8.beta2.official.cafc17a19"
        leak = "ERROR: 9 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit."
        self.assertEqual(release.check_launch_log(version + "\n" + leak, 0), 1)
        self.assertEqual(release.check_launch_log(version, 0), 0)
        for log, code in ((version + "\nERROR: Native renderer crashed", 0),
                          (version + "\nSCRIPT ERROR: bad source", 0),
                          (version + "\nParse Error: invalid code", 0),
                          (leak, 0), (version + "\n" + leak, 2)):
            with self.subTest(log=log, code=code):
                with self.assertRaises(release.ReleaseError):
                    release.check_launch_log(log, code)

    def test_linux_runtime_isolated_and_must_identify_godot(self) -> None:
        class Completed:
            def __init__(self, code: int, text: str):
                self.returncode = code
                self.stdout = text
                self.stderr = ""

        def checked(command: list[str], **kwargs: object) -> Completed:
            self.assertEqual(command[1:], ["--headless", "--quit-after", "5"])
            self.assertNotEqual(kwargs["cwd"], self.stage)
            exported = Path(command[0])
            self.assertNotEqual(exported.parent, self.linux)
            self.assertTrue((exported.parent / "Drawing.pck").is_file())
            self.assertFalse((exported.parent / "project").exists())
            env = kwargs["env"]
            assert isinstance(env, dict)
            self.assertNotIn("GODOT_PROJECT_PATH", env)
            self.assertNotEqual(env["HOME"], str(Path.home()))
            return Completed(0, "Godot Engine v4.8.beta2\n")

        with patch.object(release.subprocess, "run", side_effect=checked):
            success = release.inspect_release(self.stage, self.linux, None, launch=True)
            self.assertEqual(success["linux"]["runtime"]["status"], "passed")
            self.assertEqual(success["windows"]["status"], "not_tested")
        for code, log in ((1, "Godot Engine"), (0, "SCRIPT ERROR: problem"),
                          (0, "nothing ran")):
            with self.subTest(code=code, log=log):
                with patch.object(release.subprocess, "run", return_value=Completed(code, log)):
                    with self.assertRaises(release.ReleaseError):
                        release.launch_linux(self.linux)


if __name__ == "__main__":
    unittest.main()
