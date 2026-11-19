"""The standalone Linux release must ship exactly its required Rust extension."""

from __future__ import annotations

import errno
import os
import stat
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import package_linux_export as package
from tools.benchmarks import t068_release_gate as gate
from tools.build_drawing_app import stage


def elf(kind: int = 3, machine: int = 62) -> bytes:
    data = bytearray(4096)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 16, kind)
    struct.pack_into("<H", data, 18, machine)
    return bytes(data)


class LinuxNativeExportTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.stage = stage(self.root / "project", without_native=True)
        self.manifest = self.stage / "addons/drawing/native/drawing_brush.gdextension"
        self.native = self.stage / "addons/drawing/native/bin/libdrawing_brush.so"
        self.native.parent.mkdir(parents=True)
        self.native.write_bytes(elf())
        self.manifest.write_text(
            '[configuration]\nentry_symbol = "gdext_rust_init"\n'
            '[libraries]\nlinux.debug.x86_64 = "res://addons/drawing/native/bin/libdrawing_brush.so"\n'
            'linux.release.x86_64 = "res://addons/drawing/native/bin/libdrawing_brush.so"\n',
            encoding="utf-8",
        )
        self.output = self.root / "release"
        self.output.mkdir()
        executable = self.output / "Drawing.x86_64"
        executable.write_bytes(elf(kind=2))
        executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
        (self.output / "Drawing.pck").write_bytes(b"GDPC" + bytes(128))

    def test_package_release_keeps_native_bytes_and_launch_isolation(self) -> None:
        self.assertTrue(gate.inspect_stage(self.stage)["native_required"])
        package.package(self.stage, self.output)
        report = gate.inspect_distribution(self.output, "linux")
        self.assertTrue(report["native_extension_shipped"])
        self.assertEqual(report["native_library"]["sha256"], gate.digest(self.native))

        class Completed:
            returncode = 0
            stderr = ""

            def __init__(self, stdout: str):
                self.stdout = stdout

        def run(command: list[str], **kwargs: object) -> Completed:
            executable = Path(command[0])
            self.assertNotEqual(executable.parent, self.output)
            self.assertTrue((executable.parent / "Drawing.pck").is_file())
            self.assertEqual((executable.parent / gate.NATIVE_LIBRARY).read_bytes(), elf())
            self.assertNotEqual(kwargs["cwd"], self.stage)
            env = kwargs["env"]
            assert isinstance(env, dict)
            self.assertNotEqual(env["HOME"], str(Path.home()))
            self.assertEqual(command[1:3], ["--path", str(executable.parent)])
            if "--script" in command:
                self.assertEqual(command[-1], "res://tests/native_extension_ready.gd")
                return Completed("Godot Engine v4.8.beta3\nNATIVE_EXTENSION_READY\n")
            self.assertEqual(command[3:], ["--headless", "--quit-after", "5"])
            return Completed("Godot Engine v4.8.beta3\n")

        with patch.object(gate.subprocess, "run", side_effect=run) as mocked:
            result = gate.launch_linux(self.output)
        self.assertEqual(mocked.call_count, 2)
        self.assertTrue(result["native_abi_verified"])

    def test_missing_mismatched_and_extra_native_files_fail_closed(self) -> None:
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_distribution(self.output, "linux")
        self.native.write_bytes(elf(machine=183))
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_stage(self.stage)
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)
        self.native.write_bytes(elf())
        package.package(self.stage, self.output)
        shipped = self.output / gate.NATIVE_LIBRARY
        shipped.write_bytes(b"corrupted")
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_distribution(self.output, "linux")
        shipped.write_bytes(elf())
        (self.output / "unexpected.so").write_bytes(elf())
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_distribution(self.output, "linux")
        (self.output / "unexpected.so").unlink()
        (self.output / "addons/drawing/native/bin/libshadow.so").write_bytes(elf())
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_distribution(self.output, "linux")

    def test_rejected_export_does_not_leave_partially_installed_library(self) -> None:
        """Invalid ELF/PCK and unexpected files must fail without any publication."""
        native = self.output / gate.NATIVE_LIBRARY
        for tamper in ("extra", "pack", "elf"):
            executable = self.output / "Drawing.x86_64"
            pack = self.output / "Drawing.pck"
            if tamper == "extra":
                (self.output / "unexpected.so").write_bytes(elf())
            elif tamper == "pack":
                pack.write_bytes(b"BAD!" + bytes(128))
            else:
                executable.write_bytes(bytes(4096))
            before = {
                item.relative_to(self.output).as_posix(): item.read_bytes()
                for item in self.output.rglob("*") if item.is_file()
            }
            with self.subTest(tamper=tamper):
                with self.assertRaises(package.PackageError):
                    package.package(self.stage, self.output)
                after = {
                    item.relative_to(self.output).as_posix(): item.read_bytes()
                    for item in self.output.rglob("*") if item.is_file()
                }
                self.assertEqual(after, before)
                self.assertFalse(native.exists())
                self.assertFalse(native.parent.exists())
                self.assertFalse(any(self.output.glob(".native-preflight-*")))
            (self.output / "unexpected.so").unlink(missing_ok=True)
            pack.write_bytes(b"GDPC" + bytes(128))
            executable.write_bytes(elf(kind=2))

    def test_preflight_cross_filesystem_native_fallback(self) -> None:
        """The native source can be on another filesystem than the export."""
        real_link = os.link

        def emulate_cross_device(source: Path, destination: Path) -> None:
            if source == self.native:
                raise OSError(errno.EXDEV, "cross-device link")
            real_link(source, destination)

        with patch.object(package.os, "link", side_effect=emulate_cross_device):
            shipped = package.package(self.stage, self.output)
        self.assertEqual(shipped.read_bytes(), self.native.read_bytes())
        self.assertEqual(
            gate.inspect_distribution(self.output, "linux")["native_library"]["sha256"],
            gate.digest(self.native),
        )
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

    def test_late_distribution_rejection_rolls_back_new_native(self) -> None:
        native = self.output / gate.NATIVE_LIBRARY
        inspect = package.inspect_distribution
        inspections = 0

        def reject_after_install(distribution: Path, platform: str) -> dict[str, object]:
            nonlocal inspections
            inspections += 1
            if inspections == 2:
                raise gate.ReleaseError("late failure")
            return inspect(distribution, platform)

        with patch.object(package, "inspect_distribution", side_effect=reject_after_install):
            with self.assertRaisesRegex(package.PackageError, "late failure"):
                package.package(self.stage, self.output)
        self.assertEqual(inspections, 2)
        self.assertFalse(native.exists())
        self.assertFalse(native.parent.exists())

    def test_exported_native_symlink_rejected_even_when_target_matches(self) -> None:
        package.package(self.stage, self.output)
        shipped = self.output / gate.NATIVE_LIBRARY
        shipped.unlink()
        shipped.symlink_to(self.native)
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_distribution(self.output, "linux")
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)

    def test_symlinks_and_unregistered_stage_rejected(self) -> None:
        self.manifest.unlink()
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_stage(self.stage)
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)
        self.manifest.symlink_to(self.root / "elsewhere")
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_stage(self.stage)
        self.manifest.unlink()
        # A bad manifest cannot silently authorize a different library.
        self.manifest.write_text(
            '[configuration]\nentry_symbol = "wrong"\n[libraries]\nlinux.release.x86_64 = "res://other.so"\n',
            encoding="utf-8",
        )
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_stage(self.stage)
        self.native.unlink()
        self.native.symlink_to(self.root / "somewhere")
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)

    def test_exported_launch_rejects_unregistered_abi_even_when_main_loads(self) -> None:
        package.package(self.stage, self.output)

        class Completed:
            returncode = 0
            stderr = ""
            stdout = "Godot Engine v4.8.beta3\n"

        with patch.object(gate.subprocess, "run", return_value=Completed()):
            with self.assertRaises(gate.ReleaseError):
                gate.launch_linux(self.output)


if __name__ == "__main__":
    unittest.main()
