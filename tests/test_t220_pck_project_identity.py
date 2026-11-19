"""T-220: the exported pack must contain the Drawing project, not only ECFG magic."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from t217_pck_fixture import DEFAULT_FILES, make_pck, project_binary

from tools.benchmarks import t068_release_gate as gate


class PackedProjectIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.pack = Path(temporary.name) / "Drawing.pck"

    def inspect_project(self, content: bytes) -> dict[str, int | str]:
        self.pack.write_bytes(make_pck({**DEFAULT_FILES, "project.binary": content}))
        return gate.inspect_pck(self.pack)

    def test_drawing_identity_and_startup_remain_valid(self) -> None:
        self.assertEqual(self.inspect_project(project_binary())["file_count"], 4)

    def test_unrelated_project_name_and_scene_are_rejected(self) -> None:
        for changed_key, changed_value in (
            ("application/config/name", "Unrelated"),
            ("application/run/main_scene", "res://another.tscn"),
        ):
            entries = [
                ("application/config/name", "Drawing"),
                ("application/run/main_scene", "res://main.tscn"),
            ]
            entries = [(key, changed_value if key == changed_key else value) for key, value in entries]
            with (
                self.subTest(key=changed_key),
                self.assertRaisesRegex(gate.ReleaseError, "project|identity|startup"),
            ):
                self.inspect_project(project_binary(entries=entries))

    def test_spoofed_magic_only_and_missing_keys_are_rejected(self) -> None:
        for bad in (
            b"ECFG" + b"Drawing",
            project_binary(entries=[]),
            project_binary(entries=[("unrelated/key", "Drawing")]),
        ):
            with self.subTest(content=bad[:32]), self.assertRaises(gate.ReleaseError):
                self.inspect_project(bad)

    def test_ambiguous_duplicate_identity_or_scene_is_rejected(self) -> None:
        for key, different in (
            ("application/config/name", "Not Drawing"),
            ("application/run/main_scene", "res://other.tscn"),
        ):
            entries = [
                ("application/config/name", "Drawing"),
                ("application/run/main_scene", "res://main.tscn"),
                (key, different),
            ]
            with self.subTest(key=key), self.assertRaises(gate.ReleaseError):
                self.inspect_project(project_binary(entries=entries))

    def test_truncated_or_trailing_binary_settings_are_rejected(self) -> None:
        valid = project_binary()
        # Extra bytes, a truncated typed value, and a forged entry count.
        bad_count = bytearray(valid)
        struct.pack_into("<I", bad_count, 4, 100)
        for bad in (valid + b"unclaimed", valid[:-1], bytes(bad_count)):
            with self.subTest(length=len(bad)), self.assertRaises(gate.ReleaseError):
                self.inspect_project(bad)

    def test_wrong_value_type_and_noncanonical_string_are_rejected(self) -> None:
        valid = project_binary()
        key_end = 8 + 4 + len("application/config/name")
        value_size = struct.unpack_from("<I", valid, key_end)[0]
        self.assertEqual(value_size, 16)
        cases = []
        wrong_type = bytearray(valid)
        struct.pack_into("<I", wrong_type, key_end + 4, 2)  # Variant INT, not STRING
        cases.append(bytes(wrong_type))
        wrong_padding = bytearray(valid)
        wrong_padding[key_end + 4 + value_size - 1] = 65  # 'DrawingA' padding
        cases.append(bytes(wrong_padding))
        for bad in cases:
            with self.subTest(content=bad[:50]), self.assertRaises(gate.ReleaseError):
                self.inspect_project(bad)


if __name__ == "__main__":
    unittest.main()
