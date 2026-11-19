"""T-218: every packed resource must be intact and non-overlapping."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from t217_pck_fixture import DEFAULT_FILES, make_pck

from tools.benchmarks import t068_release_gate as gate


class CompletePckPayloadIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.pack = Path(temporary.name) / "Drawing.pck"

    def inspect(self, data: bytes) -> dict[str, int | str]:
        self.pack.write_bytes(data)
        return gate.inspect_pck(self.pack)

    @staticmethod
    def offset_field(data: bytes | bytearray, resource: str) -> int:
        """Find a v4 index entry's resource-offset field in a fixture PCK."""
        index = struct.unpack_from("<Q", data, 32)[0]
        count = struct.unpack_from("<I", data, index)[0]
        cursor = index + 4
        for _ in range(count):
            length = struct.unpack_from("<I", data, cursor)[0]
            name = data[cursor + 4 : cursor + 4 + length].rstrip(b"\0").decode()
            offset_field = cursor + 4 + length
            if name == resource:
                return offset_field
            cursor = offset_field + 36
        raise AssertionError(f"Missing test fixture resource: {resource}")

    def test_valid_pack_verifies_every_indexed_resource(self) -> None:
        files = {**DEFAULT_FILES, "assets/optional.bin": b"noncritical asset", "assets/empty.bin": b""}
        result = self.inspect(make_pck(files))
        self.assertEqual(result["file_count"], len(files))
        self.assertEqual(result["resources_verified"], len(files))

    def test_optional_payload_byte_corruption_is_rejected(self) -> None:
        content = b"unique noncritical payload marker"
        data = bytearray(make_pck({**DEFAULT_FILES, "assets/optional.bin": content}))
        start = data.index(content)
        data[start + 5] ^= 0x10
        with self.assertRaisesRegex(gate.ReleaseError, "checksum mismatch"):
            self.inspect(bytes(data))

    def test_optional_index_checksum_corruption_is_rejected(self) -> None:
        data = bytearray(make_pck({**DEFAULT_FILES, "assets/optional.bin": b"unchanged payload"}))
        checksum_field = self.offset_field(data, "assets/optional.bin") + 16
        data[checksum_field] ^= 0x01
        with self.assertRaisesRegex(gate.ReleaseError, "checksum mismatch"):
            self.inspect(bytes(data))

    def test_two_distinct_resources_may_not_overlap_even_with_matching_checksums(self) -> None:
        # Identical payloads have identical MD5. Overlap must fail on structure,
        # not only a checksum mismatch.
        files = {**DEFAULT_FILES, "assets/a.bin": b"shared payload", "assets/b.bin": b"shared payload"}
        data = bytearray(make_pck(files))
        first = self.offset_field(data, "assets/a.bin")
        second = self.offset_field(data, "assets/b.bin")
        struct.pack_into("<Q", data, second, struct.unpack_from("<Q", data, first)[0])
        with self.assertRaisesRegex(gate.ReleaseError, "overlap"):
            self.inspect(bytes(data))

    def test_empty_optional_resource_does_not_count_as_overlap(self) -> None:
        files = {**DEFAULT_FILES, "assets/empty.bin": b"", "assets/next.bin": b"data"}
        self.assertEqual(self.inspect(make_pck(files))["resources_verified"], len(files))


if __name__ == "__main__":
    unittest.main()
