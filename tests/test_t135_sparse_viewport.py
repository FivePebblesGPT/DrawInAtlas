"""Wide sparse viewport traversal: bounded exact source and CI contracts."""

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class SparseViewportContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_ci = (ROOT / ".github/workflows/godot-native-t086-viewport.yml").read_text()
        cls.model = (ROOT / "drawing/tests/t135_sparse_draw_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t135_sparse_draw_native.gd").read_text()

    @staticmethod
    def method(source: str, name: str) -> str:
        return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]

    def test_fails_closed_without_exact_committed_occupancy(self) -> None:
        helper = self.method(self.canvas, "_sparse_visible_draw_rows")
        for term in (
            "has_preview or _occupancy_unknown",
            "MAX_OCCUPANCY_ENTRIES",
            "_occupied_display_tiles",
            "window.has_point(tile)",
            "x_text.is_valid_int()",
            "y_text.is_valid_int()",
            '"%d,%d" % [tile.x, tile.y] != key',
            '"indexed": false',
            '"indexed": true',
            "ys.sort()",
        ):
            with self.subTest(term=term):
                self.assertIn(term, helper)
        draw = self.method(self.canvas, "_draw")
        self.assertLess(draw.index("_sync_display_cache()"),
                        draw.index("_sparse_visible_draw_rows"))
        self.assertIn("preview_session != null", draw)
        self.assertIn("for y: int in draw_ys:", draw)
        self.assertIn("for x: int in draw_xs:", draw)
        self.assertIn('metrics["tiles_examined"]', draw)
        self.assertIn('metrics["empty_skipped"]', draw)
        self.assertIn('metrics["tiles_visible"] = visible_tiles.get_area()', draw)
        self.assertIn("_occupied_display_tiles.has(key)", draw)

    def test_models_cover_signed_order_invalid_fallback_and_native_state(self) -> None:
        for phrase in (
            "only five signed occupied display tiles intersect window",
            "exclusive positive Y edge is omitted",
            "columns remain sorted in the original left-to-right draw order",
            "any detached preview keeps the conservative full draw",
            "unknown or incomplete occupancy cannot cull content",
            "malformed index fails closed to full scan",
            "nonnumeric tile coordinates also fail closed",
            "noncanonical duplicate-prone coordinates cannot authorize",
            "fully empty sparse documents do not traverse the full viewport",
        ):
            with self.subTest(model=phrase):
                self.assertIn(phrase, self.model)
        for phrase in (
            "signed red and positive blue compositing visible in native framebuffer",
            "indexed draw actually visits only the bounded occupied tile set",
            "seven repeat-frame CPU timing samples recorded",
            "unknown occupancy safely bypasses sparse enumeration",
            "dirty source revision revalidates sparse display",
            "Redo pixel remains visible after sparse viewport reuse",
            "hidden top layer cannot leave stale cached texture",
        ):
            with self.subTest(native=phrase):
                self.assertIn(phrase, self.native)

    def test_strict_required_ci_and_on_demand_native(self) -> None:
        required = self.workflow.split("id: ci_t086_viewport_cache_model", 1)[1].split(
            "- name: Verify T-087", 1
        )[0]
        for text in (
            "res://tests/t135_sparse_draw_model.gd",
            "--marker T135_SPARSE_PASSED",
            "T135_SPARSE_PASSED checks=16 failures=0",
            "test_t135_sparse_viewport.py",
        ):
            self.assertIn(text, required)
        for text in (
            "res://tests/t135_sparse_draw_native.gd",
            "T135_NATIVE_PASSED checks=23 failures=0",
            "--marker T135_NATIVE_PASSED",
            "/tmp/t135-sparse-native.log",
        ):
            self.assertIn(text, self.native_ci)
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.workflow, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for marker, count in (("T135_SPARSE_PASSED", 16), ("T135_NATIVE_PASSED", 23)):
            valid = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(valid, marker)[0])
            for altered in (
                valid.replace(f"checks={count}", f"checks={count-1}"),
                valid.replace("failures=0", "failures=1"),
                valid + "SCRIPT ERROR: unexpected\n",
                valid + valid,
            ):
                # Count mismatches require the separate exact CI grep; all
                # genuinely broken markers/errors must be rejected here.
                if "failures=1" in altered or "SCRIPT ERROR:" in altered or altered == valid + valid:
                    self.assertTrue(verify_log(altered, marker)[0])


if __name__ == "__main__":
    unittest.main()
