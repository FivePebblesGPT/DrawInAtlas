"""T-217: exported PCKs must contain the actual native Drawing startup resources."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from t217_pck_fixture import DEFAULT_FILES, make_pck

from tools.benchmarks import t068_release_gate as gate


class RequiredNativePckTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.pack = Path(directory.name) / "Drawing.pck"

    def inspect(self, content: bytes) -> dict[str, int | str]:
        self.pack.write_bytes(content)
        return gate.inspect_pck(self.pack)

    def test_valid_minimal_pack_has_native_and_startup_resources(self) -> None:
        result = self.inspect(make_pck())
        self.assertEqual(result["format_version"], 4)
        self.assertEqual(result["file_count"], 4)

    def test_magic_only_and_unrelated_pack_are_rejected(self) -> None:
        for content in (b"GDPC" + bytes(128), make_pck({"unrelated.txt": b"data"})):
            with self.subTest(length=len(content)), self.assertRaises(gate.ReleaseError):
                self.inspect(content)

    def test_missing_required_resource_is_rejected(self) -> None:
        for name in DEFAULT_FILES:
            with self.subTest(resource=name):
                files = dict(DEFAULT_FILES)
                files.pop(name)
                with self.assertRaises(gate.ReleaseError):
                    self.inspect(make_pck(files))

    def test_malformed_or_out_of_range_pack_index_is_rejected(self) -> None:
        valid = make_pck()
        cases: list[bytes] = []
        for position, replacement in (
            (4, 999),  # unsupported pack layout
            (8, 3),  # wrong major engine
            (20, 3),  # encrypted directory
            (32, len(valid) + 1),
        ):
            bad = bytearray(valid)
            if position == 32:
                struct.pack_into("<Q", bad, position, replacement)
            else:
                struct.pack_into("<I", bad, position, replacement)
            cases.append(bytes(bad))
        cases.append(valid[:-7])
        for content in cases:
            with self.subTest(case=len(content), header=content[:40]), self.assertRaises(gate.ReleaseError):
                self.inspect(content)

    def test_required_payload_checksum_mismatch_is_rejected(self) -> None:
        bad = bytearray(make_pck())
        bad[112] ^= 0x20
        with self.assertRaises(gate.ReleaseError):
            self.inspect(bytes(bad))

    def test_remapped_startup_requires_packed_target(self) -> None:
        files = dict(DEFAULT_FILES)
        files.pop("main.tscn")
        files["main.tscn.remap"] = b'[remap]\npath="res://.godot/exported/main.scn"\n'
        with self.assertRaisesRegex(gate.ReleaseError, "remap target missing"):
            self.inspect(make_pck(files))
        files[".godot/exported/main.scn"] = b"compiled scene"
        self.assertEqual(self.inspect(make_pck(files))["startup_scene"], "main.tscn.remap")

    def test_windows_structural_pack_need_not_claim_linux_native_abi(self) -> None:
        files = {key: data for key, data in DEFAULT_FILES.items() if key in ("project.binary", "main.tscn")}
        self.pack.write_bytes(make_pck(files))
        self.assertEqual(gate.inspect_pck(self.pack, platform="windows")["file_count"], 2)
        with self.assertRaises(gate.ReleaseError):
            gate.inspect_pck(self.pack, platform="linux")

    def test_packed_native_manifest_mapping_is_checked(self) -> None:
        files = dict(DEFAULT_FILES)
        files["addons/drawing/native/drawing_brush.gdextension"] = files[
            "addons/drawing/native/drawing_brush.gdextension"
        ].replace(b"gdext_rust_init", b"wrong_entry")
        with self.assertRaisesRegex(gate.ReleaseError, "packed native manifest|Packed native manifest"):
            self.inspect(make_pck(files))

    def test_non_project_configuration_is_rejected(self) -> None:
        files = dict(DEFAULT_FILES)
        files["project.binary"] = b"wrong project"
        with self.assertRaisesRegex(gate.ReleaseError, "project configuration"):
            self.inspect(make_pck(files))

    def test_duplicate_pack_index_resource_is_rejected(self) -> None:
        # Two index records with the same resource name must not be ambiguous.
        valid = bytearray(make_pck())
        index = struct.unpack_from("<Q", valid, 32)[0]
        name_length = struct.unpack_from("<I", valid, index + 4)[0]
        entry_length = 4 + name_length + 8 + 8 + 16 + 4
        entry = valid[index + 4 : index + 4 + entry_length]
        struct.pack_into("<I", valid, index, 5)
        valid.extend(entry)
        with self.assertRaises(gate.ReleaseError):
            self.inspect(bytes(valid))


if __name__ == "__main__":
    unittest.main()
