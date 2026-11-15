"""T-136: bounded preview/committed sparse draw union and CI contracts."""

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PreviewSparseUnionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_workflow = (ROOT / ".github/workflows/godot-native-t086-viewport.yml").read_text()
        cls.model = (ROOT / "drawing/tests/t136_preview_sparse_union_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t136_preview_sparse_union_native.gd").read_text()

    def test_fails_closed_and_keeps_bounded_exact_index(self) -> None:
        helper = self.canvas.split("func _sparse_visible_draw_rows(", 1)[1].split("\nfunc ", 1)[0]
        for term in (
            "preview_stamps: Dictionary = {}",
            "preview_complete: bool = false",
            "has_preview and not preview_complete",
            "_occupancy_unknown",
            "MAX_OCCUPANCY_ENTRIES",
            "window.get_area() <= 2 * maxi(",
            "keys = _occupied_display_tiles.duplicate()",
            "for key: String in preview_stamps:",
            "int(preview_stamps[key]) <= 0",
            "keys[key] = true",
            "keys.size() > MAX_OCCUPANCY_ENTRIES",
            "x_text.is_valid_int()",
            "y_text.is_valid_int()",
            '"%d,%d" % [tile.x, tile.y] != key',
            "window.has_point(tile)",
            "ys.sort()",
        ):
            with self.subTest(term=term):
                self.assertIn(term, helper)
        draw = self.canvas.split("func _draw() -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("preview_session != null, indexed_stamps, use_preview_index", draw)
        self.assertIn('metrics["tiles_examined"]', draw)
        self.assertIn('metrics["sparse_draw"]', draw)

    def test_models_and_native_witness_verify_real_parity(self) -> None:
        for phrase in (
            "overlapping committed/preview tile included exactly once",
            "new preview generation cannot reuse stale rows",
            "incomplete preview index always falls back",
            "unknown committed occupancy always falls back",
            "malformed preview key cannot authorize culling",
            "invalid zero preview generation fails closed",
        ):
            with self.subTest(model=phrase):
                self.assertIn(phrase, self.model)
        for phrase in (
            "draft blue pixel visible in actual framebuffer",
            "committed and preview-only tiles both visited without scanning empty viewport",
            "new draft generation updates framebuffer without stale sparse result",
            "unknown committed occupancy forces exact legacy preview traversal",
            "cancellation removes blue preview, never committed red",
            "Undo exact pixels and retained committed red",
            "Redo blue source pixel appears in framebuffer",
            "retained GPU display tiles stay under the 144-entry cap",
        ):
            with self.subTest(native=phrase):
                self.assertIn(phrase, self.native)

    def test_strict_required_ci_and_on_demand_native(self) -> None:
        required = self.workflow.split("id: ci_t086_viewport_cache_model", 1)[1].split(
            "- name: Verify T-087", 1
        )[0]
        for text in (
            "res://tests/t136_preview_sparse_union_model.gd",
            "T136_UNION_PASSED checks=18 failures=0",
            "--marker T136_UNION_PASSED",
            "test_t136_preview_sparse_union.py",
        ):
            self.assertIn(text, required)
        for text in (
            "res://tests/t136_preview_sparse_union_native.gd",
            "T136_NATIVE_PASSED checks=26 failures=0",
            "--marker T136_NATIVE_PASSED",
            "/tmp/t136-preview-sparse-native.log",
        ):
            self.assertIn(text, self.native_workflow)
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.workflow, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for marker, count in (("T136_UNION_PASSED", 18), ("T136_NATIVE_PASSED", 26)):
            good = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(good, marker)[0])
            for bad in (good + good, good.replace("failures=0", "failures=1"),
                        good + "SCRIPT ERROR: dropped preview\n"):
                self.assertTrue(verify_log(bad, marker)[0])


if __name__ == "__main__":
    unittest.main()
