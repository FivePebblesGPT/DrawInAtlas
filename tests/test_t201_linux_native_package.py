"""The standalone Linux release must ship exactly its required Rust extension."""

from __future__ import annotations

import errno
import os
import socket
import stat
import struct
import tempfile
import unittest
from pathlib import Path
from typing import BinaryIO
from unittest.mock import patch

from t217_pck_fixture import DEFAULT_FILES, make_pck, project_binary

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
        (self.output / "Drawing.pck").write_bytes(make_pck())

    def test_package_release_keeps_native_bytes_and_launch_isolation(self) -> None:
        self.assertTrue(gate.inspect_stage(self.stage)["native_required"])
        package.package(self.stage, self.output)
        shipped = self.output / gate.NATIVE_LIBRARY
        self.assertEqual(stat.S_IMODE(shipped.stat().st_mode), stat.S_IMODE(self.native.stat().st_mode))
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
            self.assertEqual(command[1:4], ["--headless", "--quit-after", "5"])
            if "--verify-native-extension" in command:
                self.assertEqual(command[4:], ["--", "--verify-native-extension"])
                return Completed("Godot Engine v4.8.beta4\nNATIVE_EXTENSION_READY\n")
            self.assertEqual(command[4:], [])
            return Completed("Godot Engine v4.8.beta4\n")

        with patch.object(gate.subprocess, "run", side_effect=run) as mocked:
            result = gate.launch_linux(self.output)
        self.assertEqual(mocked.call_count, 2)
        self.assertTrue(result["native_abi_verified"])

    def test_engine_copy_is_normalized_only_if_it_matches_the_stage(self) -> None:
        root_copy = self.output / gate.NATIVE_LIBRARY.name
        wrong = self.native.read_bytes() + b"extra"
        root_copy.write_bytes(wrong)
        with self.assertRaisesRegex(package.PackageError, "Engine-copied native library differs"):
            package.package(self.stage, self.output)
        self.assertEqual(root_copy.read_bytes(), wrong)
        self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())

        root_copy.write_bytes(self.native.read_bytes())
        destination = package.package(self.stage, self.output)
        self.assertEqual(destination, self.output / gate.NATIVE_LIBRARY)
        self.assertFalse(root_copy.exists())
        self.assertEqual(destination.read_bytes(), self.native.read_bytes())

    def test_repeated_godot_export_normalizes_identical_engine_copy(self) -> None:
        """A second beta4 export must not invalidate an already packaged release."""
        shipped = package.package(self.stage, self.output)
        original_bytes = shipped.read_bytes()
        root_copy = self.output / gate.NATIVE_LIBRARY.name
        root_copy.write_bytes(original_bytes)
        with self.assertRaisesRegex(gate.ReleaseError, "Unexpected export file"):
            gate.inspect_distribution(self.output, "linux")

        self.assertEqual(package.package(self.stage, self.output), shipped)
        self.assertFalse(root_copy.exists())
        self.assertEqual(shipped.read_bytes(), original_bytes)
        self.assertEqual(
            gate.inspect_distribution(self.output, "linux")["native_library"]["sha256"],
            gate.digest(self.native),
        )
        self.assertFalse(any(self.output.parent.glob(".native-reexport-*")))

    def test_repeated_export_rejects_changed_engine_copy_without_mutation(self) -> None:
        shipped = package.package(self.stage, self.output)
        root_copy = self.output / gate.NATIVE_LIBRARY.name
        root_copy.write_bytes(self.native.read_bytes() + b"unexpected")
        before = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*") if p.is_file()}
        with self.assertRaisesRegex(package.PackageError, "Engine-copied native library differs"):
            package.package(self.stage, self.output)
        after = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(shipped.read_bytes(), self.native.read_bytes())

    def test_repeated_export_rejects_corrupt_pck_and_extra_entries_unchanged(self) -> None:
        package.package(self.stage, self.output)
        root_copy = self.output / gate.NATIVE_LIBRARY.name
        root_copy.write_bytes(self.native.read_bytes())
        original_pack = (self.output / "Drawing.pck").read_bytes()
        for kind in ("pack", "extra", "symlink"):
            unexpected = self.output / "foreign.txt"
            if kind == "pack":
                (self.output / "Drawing.pck").write_bytes(b"broken export")
            elif kind == "extra":
                unexpected.write_bytes(b"foreign artifact")
            else:
                root_copy.unlink()
                root_copy.symlink_to(self.native)
            before = {
                path.relative_to(self.output): (path.is_symlink(), path.read_bytes())
                for path in self.output.rglob("*") if path.is_file() or path.is_symlink()
            }
            with self.subTest(kind=kind):
                with self.assertRaises(package.PackageError):
                    package.package(self.stage, self.output)
                self.assertEqual(before, {
                    path.relative_to(self.output): (path.is_symlink(), path.read_bytes())
                    for path in self.output.rglob("*") if path.is_file() or path.is_symlink()
                })
                self.assertFalse(any(self.output.parent.glob(".native-reexport-*")))
            (self.output / "Drawing.pck").write_bytes(original_pack)
            unexpected.unlink(missing_ok=True)
            if kind == "symlink":
                root_copy.unlink()
                root_copy.write_bytes(self.native.read_bytes())

    def test_repeated_export_restores_engine_copy_on_late_failure(self) -> None:
        package.package(self.stage, self.output)
        root_copy = self.output / gate.NATIVE_LIBRARY.name
        root_copy.write_bytes(self.native.read_bytes())
        original = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*") if p.is_file()}
        real_inspect = package.inspect_distribution
        calls = 0

        def fail_after_normalization(path: Path, platform: str) -> dict[str, object]:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise gate.ReleaseError("injected late distribution failure")
            return real_inspect(path, platform)

        with patch.object(package, "inspect_distribution", side_effect=fail_after_normalization):
            with self.assertRaisesRegex(package.PackageError, "injected late distribution failure"):
                package.package(self.stage, self.output)
        self.assertEqual(calls, 2)
        after = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*") if p.is_file()}
        self.assertEqual(original, after)
        self.assertFalse(any(self.output.parent.glob(".native-reexport-*")))

    def test_unrelated_pack_is_rejected_before_native_publication(self) -> None:
        pack = self.output / "Drawing.pck"
        pack.write_bytes(make_pck({"unrelated.txt": b"not Drawing"}))
        before = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        with self.assertRaisesRegex(package.PackageError, "PCK missing required"):
            package.package(self.stage, self.output)
        after = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)
        self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

    def test_noncanonical_resource_name_rejects_without_native_publication(self) -> None:
        """Invalid PCK names must fail during preflight, not after .so installation."""
        pack = self.output / "Drawing.pck"
        pack.write_bytes(
            make_pck(
                {
                    "project.binary": project_binary(),
                    "main.tscn": b"[gd_scene format=3]\n",
                    "addons/drawing/native/drawing_brush.gdextension": self.manifest.read_bytes(),
                    "tests/native_extension_ready.gd": b"extends SceneTree\n",
                    "assets/brush\x00alias.png": b"ambiguous path",
                }
            )
        )
        before = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        with self.assertRaisesRegex(package.PackageError, "resource name"):
            package.package(self.stage, self.output)
        after = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)
        self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

    def test_noncritical_resource_corruption_rejects_without_native_publication(self) -> None:
        """A bad packed asset cannot install a valid native ELF or mutate the export."""
        asset = b"unrelated packed source, still required intact"
        pack = self.output / "Drawing.pck"
        content = bytearray(
            make_pck(
                {
                    "project.binary": project_binary(),
                    "main.tscn": b"[gd_scene format=3]\n",
                    "addons/drawing/native/drawing_brush.gdextension": self.manifest.read_bytes(),
                    "tests/native_extension_ready.gd": b"extends SceneTree\n",
                    "assets/corrupted.bin": asset,
                }
            )
        )
        content[content.index(asset) + 3] ^= 1
        pack.write_bytes(content)
        before = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        with self.assertRaisesRegex(package.PackageError, "checksum mismatch"):
            package.package(self.stage, self.output)
        after = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)
        self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

    def test_wrong_packed_project_rejects_before_native_publication(self) -> None:
        """The staged Drawing project cannot authorize an unrelated exported ECFG."""
        pack = self.output / "Drawing.pck"
        pack.write_bytes(
            make_pck(
                {
                    **DEFAULT_FILES,
                    "project.binary": project_binary(**{"application/config/name": "Unrelated"}),
                }
            )
        )
        before = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        with self.assertRaisesRegex(package.PackageError, "project identity"):
            package.package(self.stage, self.output)
        after = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)
        self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

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
                for item in self.output.rglob("*")
                if item.is_file()
            }
            with self.subTest(tamper=tamper):
                with self.assertRaises(package.PackageError):
                    package.package(self.stage, self.output)
                after = {
                    item.relative_to(self.output).as_posix(): item.read_bytes()
                    for item in self.output.rglob("*")
                    if item.is_file()
                }
                self.assertEqual(after, before)
                self.assertFalse(native.exists())
                self.assertFalse(native.parent.exists())
                self.assertFalse(any(self.output.glob(".native-preflight-*")))
            (self.output / "unexpected.so").unlink(missing_ok=True)
            pack.write_bytes(make_pck())
            executable.write_bytes(elf(kind=2))

    def test_staged_project_inside_export_root_is_rejected_without_publication(self) -> None:
        """Regression for CI exporting ELF/PCK beside its staged project."""
        nested_project = self.output / "project"
        nested_project.mkdir()
        try:
            with self.assertRaisesRegex(
                package.PackageError, "Unexpected export directory: project"
            ):
                package.package(self.stage, self.output)
            self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())
        finally:
            nested_project.rmdir()
        # Only ELF/PCK remain; the same strict validator must now accept the
        # clean distribution, without making an exception for a project dir.
        package.package(self.stage, self.output)
        self.assertTrue(gate.inspect_distribution(self.output, "linux")["native_extension_shipped"])

    def test_rejected_special_entries_leave_export_unchanged(self) -> None:
        """A complete native projection must not authorize extra filesystem nodes."""
        native = self.output / gate.NATIVE_LIBRARY
        for kind in ("extra_directory", "fifo"):
            if kind == "extra_directory":
                unexpected = self.output / "unrelated"
                unexpected.mkdir()
            else:
                if not hasattr(os, "mkfifo"):
                    continue
                unexpected = self.output / "not-a-file.pipe"
                os.mkfifo(unexpected)
            try:
                with self.subTest(kind=kind):
                    with self.assertRaises(package.PackageError):
                        package.package(self.stage, self.output)
                    self.assertFalse(native.exists())
                    self.assertFalse(native.parent.exists())
                    self.assertFalse(any(self.output.glob(".native-preflight-*")))
                    self.assertTrue(unexpected.exists())
            finally:
                if unexpected.is_dir():
                    unexpected.rmdir()
                else:
                    unexpected.unlink()

    def test_rejected_package_preserves_foreign_temporary_file(self) -> None:
        """Cleanup cannot unlink a temp-looking file owned by another process."""
        native = self.output / gate.NATIVE_LIBRARY
        native.parent.mkdir(parents=True)
        foreign = native.with_name(native.name + ".tmp")
        payload = b"foreign export diagnostic; not created by the packager"
        foreign.write_bytes(payload)
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)
        self.assertEqual(foreign.read_bytes(), payload)
        self.assertFalse(native.exists())

    def test_rejected_package_preserves_foreign_temporary_symlink(self) -> None:
        """An unexpected symlink must be refused without being removed."""
        native = self.output / gate.NATIVE_LIBRARY
        native.parent.mkdir(parents=True)
        foreign = native.with_name(native.name + ".tmp")
        target = self.root / "external-sentinel"
        target.write_bytes(b"do not touch")
        foreign.symlink_to(target)
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)
        self.assertTrue(foreign.is_symlink())
        self.assertEqual(foreign.readlink(), target)
        self.assertEqual(target.read_bytes(), b"do not touch")
        self.assertFalse(native.exists())

    def test_rejected_package_preserves_foreign_temporary_directory(self) -> None:
        """Unexpected directories must not hide the original validation error."""
        native = self.output / gate.NATIVE_LIBRARY
        native.parent.mkdir(parents=True)
        foreign = native.with_name(native.name + ".tmp")
        foreign.mkdir()
        with self.assertRaisesRegex(package.PackageError, "Invalid pre-package export layout"):
            package.package(self.stage, self.output)
        self.assertTrue(foreign.is_dir())
        self.assertFalse(native.exists())

    def test_interrupted_copy_removes_only_owned_temporary(self) -> None:
        """A failed native copy leaves no partial library or staging files."""
        native = self.output / gate.NATIVE_LIBRARY

        def partial_copy(input_stream: BinaryIO, output_stream: BinaryIO) -> None:
            del input_stream
            output_stream.write(b"partial native bytes")
            raise OSError(errno.EIO, "interrupted native copy")

        with patch.object(package.shutil, "copyfileobj", side_effect=partial_copy):
            with self.assertRaisesRegex(package.PackageError, "interrupted native copy"):
                package.package(self.stage, self.output)
        self.assertFalse(native.exists())
        self.assertFalse(native.parent.exists())
        self.assertFalse(any(self.output.rglob("*.tmp")))
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

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

    def test_stage_identity_cannot_be_spoofed_by_comments_or_other_sections(self) -> None:
        """Only effective [application] settings authorize standalone packaging."""
        project = self.stage / "project.godot"
        original = project.read_text(encoding="utf-8")
        before = {
            path.relative_to(self.output).as_posix(): path.read_bytes()
            for path in self.output.rglob("*")
            if path.is_file()
        }
        cases = {
            "commented_identity": original.replace(
                'config/name="Drawing"', 'config/name="Atlas"\n; config/name="Drawing"'
            ),
            "other_section_identity": original.replace('config/name="Drawing"', 'config/name="Atlas"')
            + '\n[diagnostics]\nconfig/name="Drawing"\n',
            "duplicate_identity": original.replace(
                'config/name="Drawing"', 'config/name="Drawing"\nconfig/name="Atlas"'
            ),
            "duplicate_application": original + '\n[application]\nconfig/name="Drawing"\n',
            "wrong_startup_scene": original.replace(
                'run/main_scene="res://main.tscn"', 'run/main_scene="res://tests/native_extension_ready.gd"'
            ),
            "commented_startup_scene": original.replace(
                'run/main_scene="res://main.tscn"',
                'run/main_scene="res://tests/native_extension_ready.gd"\n# run/main_scene="res://main.tscn"',
            ),
        }
        for label, content in cases.items():
            with self.subTest(label=label):
                project.write_text(content, encoding="utf-8")
                with self.assertRaisesRegex(gate.ReleaseError, "project|application|identity|startup"):
                    gate.inspect_stage(self.stage)
                with self.assertRaises(package.PackageError):
                    package.package(self.stage, self.output)
                self.assertEqual(
                    before,
                    {
                        path.relative_to(self.output).as_posix(): path.read_bytes()
                        for path in self.output.rglob("*")
                        if path.is_file()
                    },
                )
                self.assertFalse(any(self.output.glob(".native-preflight-*")))
        project.write_text(original, encoding="utf-8")
        self.assertTrue(gate.inspect_stage(self.stage)["native_required"])
        package.package(self.stage, self.output)

    def test_stage_rejects_undeclared_directories(self) -> None:
        """No source-stage entry can escape the Drawing allowlisted hierarchy."""
        for relative in ("unrelated", "addons/other"):
            extra = self.stage / relative
            extra.mkdir(parents=True)
            try:
                with self.subTest(relative=relative):
                    with self.assertRaisesRegex(gate.ReleaseError, "Unexpected stage directory"):
                        gate.inspect_stage(self.stage)
            finally:
                extra.rmdir()

    def test_stage_rejects_special_files_even_in_allowed_subtrees(self) -> None:
        """is_file-only inventory silently ignored FIFOs and Unix sockets."""
        if not hasattr(os, "mkfifo"):
            self.skipTest("Requires POSIX FIFO nodes")
        for relative in ("tests/native.pipe", ".godot/imported/native.pipe"):
            special = self.stage / relative
            special.parent.mkdir(parents=True, exist_ok=True)
            os.mkfifo(special)
            try:
                with self.subTest(relative=relative):
                    with self.assertRaisesRegex(gate.ReleaseError, "Non-regular stage entry"):
                        gate.inspect_stage(self.stage)
            finally:
                special.unlink()

    def test_stage_rejects_unix_sockets_in_allowed_subtrees(self) -> None:
        """Unix sockets are not staged resources, even under cache directories."""
        if not hasattr(socket, "AF_UNIX"):
            self.skipTest("Requires Unix-domain sockets")
        path = self.stage / ".godot/stale.sock"
        path.parent.mkdir(parents=True, exist_ok=True)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.bind(str(path))
            with self.assertRaisesRegex(gate.ReleaseError, "Non-regular stage entry"):
                gate.inspect_stage(self.stage)

    def test_package_rejected_stage_preserves_export(self) -> None:
        """Pre-packaging rejection must not publish the native library."""
        extra = self.stage / "unrelated"
        extra.mkdir()
        before = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*") if p.is_file()}
        with self.assertRaises(package.PackageError):
            package.package(self.stage, self.output)
        after = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*") if p.is_file()}
        self.assertEqual(after, before)
        self.assertFalse((self.output / gate.NATIVE_LIBRARY).exists())
        self.assertFalse(any(self.output.glob(".native-preflight-*")))

    def test_stage_permits_generated_godot_and_drawing_subdirectories(self) -> None:
        """Allowed empty source and Godot cache folders remain supported."""
        (self.stage / ".godot/imported").mkdir(parents=True, exist_ok=True)
        (self.stage / "scripts/nested").mkdir(parents=True, exist_ok=True)
        self.assertTrue(gate.inspect_stage(self.stage)["native_required"])
        package.package(self.stage, self.output)
        self.assertTrue(gate.inspect_distribution(self.output, "linux")["native_extension_shipped"])

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
