"""Contracts for bounded cold population of complete detached drawing previews."""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PreviewColdPopulationContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_ci = (ROOT / ".github/workflows/godot-native-t086-viewport.yml").read_text()
        cls.model = (ROOT / "drawing/tests/t137_preview_cold_population_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t137_preview_cold_population_native.gd").read_text()

    def test_source_only_throttles_complete_retainable_preview(self) -> None:
        planner = self.canvas.split("func _cold_population_targets(", 1)[1].split("\nfunc ", 1)[0]
        draw = self.canvas.split("func _draw() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for term in (
            "preview: DrawingEditSession = null",
            "preview_stamps: Dictionary = {}",
            "sparse: Dictionary = {}",
            "if _occupancy_unknown:",
            "preview != active_preview",
            'not bool(sparse.get("indexed", false))',
            'int(sparse.get("count", MAX_DISPLAY_TILES + 1)) > MAX_DISPLAY_TILES',
            'for y: int in sparse.get("ys", []):',
            'var stamp: int = int(preview_stamps.get(key, 0))',
            'entry.get("preview_owner") != owner',
            'entry.get("preview_stamp", 0)',
            "MAX_COLD_TILES_PER_DRAW",
            "_occupied_display_tiles.size() * 2 < window.get_area()",
        ):
            with self.subTest(source_guard=term):
                self.assertIn(term, planner)
        self.assertLess(draw.index("_preview_index_for_draw(preview_session, visible_tiles)"),
                        draw.index("_cold_population_targets(visible_tiles, cache_focus,"))
        self.assertLess(draw.index("_sparse_visible_draw_rows(visible_tiles,"),
                        draw.index("_cold_population_targets(visible_tiles, cache_focus,"))
        self.assertIn("preview_session, indexed_stamps, sparse", draw)
        self.assertIn('metrics["cold_budgeted"]', draw)

    def test_real_regressions_cover_fallback_and_settlement(self) -> None:
        for term in (
            "closest preview-only tile receives cold priority",
            "unchanged draft texture is a cache hit",
            "different preview owner requires refresh",
            "changed draft generation requires refresh",
            "incomplete preview index must use conservative traversal",
            "over-144 tile preview retains full traversal",
        ):
            self.assertIn(term, self.model)
        for term in (
            "real detached preview provides complete index",
            "first native frame composites at most four cold tiles",
            "other cold tiles are explicitly deferred to later frames",
            "bounded cold preview settles in subsequent draw frames",
            "preview-only blue pixel appears in final framebuffer",
            "committed red pixel appears in final framebuffer",
            "preview cancellation removes only detached pixels",
            "Undo removes blue without changing committed red",
            "Redo completes bounded cold display repopulation",
            "Redo restores exact canonical source and visible framebuffer pixel",
        ):
            self.assertIn(term, self.native)

    def test_native_redo_requires_settlement_and_source_frame_parity(self) -> None:
        # The Redo comparison must not pass on a stale cold display tile.
        redo = self.native.split('check(doc.redo().ok, "Redo source transaction")', 1)[1]
        self.assertLess(redo.index('var redo_settled: bool = false'),
                        redo.index('check(redo_settled, "Redo completes bounded cold display repopulation")'))
        self.assertLess(redo.index('check(redo_settled,'),
                        redo.index('"Redo restores exact canonical source and visible framebuffer pixel"'))
        final_pixel = redo.split('check(redo_settled,', 1)[1].split('"Redo restores exact canonical', 1)[0]
        self.assertIn('doc.read_pixel(layer, 0, 260)', final_pixel)
        self.assertIn('pixel(canvas, Vector2(0.5, 260.5))', final_pixel)
        self.assertIn('cold_tiles_deferred', redo)

    def test_existing_ci_inventory_and_fail_closed_logs(self) -> None:
        required = self.workflow.split("id: ci_t086_viewport_cache_model", 1)[1].split(
            "- name: Verify T-087", 1
        )[0]
        for text in (
            "res://tests/t137_preview_cold_population_model.gd",
            "T137_COLD_PASSED checks=15 failures=0",
            "--marker T137_COLD_PASSED",
            "test_t137_preview_cold_population.py",
        ):
            self.assertIn(text, required)
        for text in (
            "res://tests/t137_preview_cold_population_native.gd",
            "T137_NATIVE_PASSED checks=19 failures=0",
            "--marker T137_NATIVE_PASSED",
            "/tmp/t137-preview-cold-native.log",
        ):
            self.assertIn(text, self.native_ci)
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.workflow, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for marker, count in (("T137_COLD_PASSED", 15), ("T137_NATIVE_PASSED", 19)):
            good = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(good, marker)[0])
            for bad in (good + good, good.replace("failures=0", "failures=1"),
                        good + "SCRIPT ERROR: incomplete preview\n"):
                self.assertTrue(verify_log(bad, marker)[0])


if __name__ == "__main__":
    unittest.main()
