"""T-219: reject ambiguous resource names in native Drawing PCK indexes."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from t217_pck_fixture import DEFAULT_FILES, make_pck

from tools.benchmarks import t068_release_gate as gate


class CanonicalPckNamesTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.pack = Path(temporary.name) / "Drawing.pck"

    def inspect_extra(self, name: str) -> dict[str, int | str]:
        contents = {**DEFAULT_FILES, name: b"optional payload"}
        self.pack.write_bytes(make_pck(contents))
        return gate.inspect_pck(self.pack)

    def test_valid_utf8_optional_resource_remains_supported(self) -> None:
        result = self.inspect_extra("assets/équipe overview.png")
        self.assertEqual(result["resources_verified"], len(DEFAULT_FILES) + 1)

    def test_embedded_nul_in_index_name_is_rejected(self) -> None:
        with self.assertRaisesRegex(gate.ReleaseError, "resource name|padding"):
            self.inspect_extra("assets/brush\x00alias.png")

    def test_four_extra_nul_padding_bytes_are_rejected(self) -> None:
        with self.assertRaisesRegex(gate.ReleaseError, "resource name|padding"):
            self.inspect_extra("assets/brush.png\x00\x00\x00\x00")

    def test_newline_and_carriage_return_names_are_rejected(self) -> None:
        for char in ("\n", "\r"):
            with self.subTest(char=repr(char)):
                with self.assertRaisesRegex(gate.ReleaseError, "resource name"):
                    self.inspect_extra(f"assets/brush{char}alias.png")

    def test_other_control_and_delete_names_are_rejected(self) -> None:
        for char in ("\x1f", "\x7f"):
            with self.subTest(char=repr(char)):
                with self.assertRaisesRegex(gate.ReleaseError, "resource name"):
                    self.inspect_extra(f"assets/brush{char}alias.png")


if __name__ == "__main__":
    unittest.main()
