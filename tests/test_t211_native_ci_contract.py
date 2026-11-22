"""Keep required/native CI on the supported Hokusai and tile transaction ABI."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAST = ROOT / ".github/workflows/godot-check.yml"
NATIVE = ROOT / ".github/workflows/godot-native-t095-brush.yml"
REMOVED_FIXTURES = (
    "hokusai_bulk_delta_smoke",
    "t095_tile_shift_smoke",
    "t095_tile_commit_smoke",
)


class RequiredNativeCIContracts(unittest.TestCase):
    def test_retired_scripted_bridge_tests_are_not_runnable_ci(self) -> None:
        workflow = FAST.read_text() + NATIVE.read_text()
        for name in REMOVED_FIXTURES:
            self.assertNotIn(f"res://tests/{name}.gd", workflow)
            self.assertFalse((ROOT / f"drawing/tests/{name}.gd").exists())
        self.assertNotIn("t147_scripted_session_bridge.gd", workflow)
        self.assertFalse((ROOT / "drawing/tests/t147_scripted_session_bridge.gd").exists())

    def test_required_fast_step_checks_actual_native_pigment_rollback(self) -> None:
        workflow = FAST.read_text()
        self.assertIn("id: ci_t085_live_stroke_preview", workflow)
        self.assertIn("make test TOOLCHAIN=system", workflow)
        self.assertIn("res://tests/t095_native_pigment_atomic.gd", workflow)
        self.assertIn("--marker T095_NATIVE_PIGMENT_ATOMIC_PASSED", workflow)
        self.assertIn("T095_NATIVE_PIGMENT_ATOMIC_RESULT checks=57 failures=0", workflow)
        self.assertIn("test_t211_native_ci_contract.py", workflow)

    def test_required_fast_step_checks_signed_native_boundaries(self) -> None:
        workflow = FAST.read_text()
        for name, marker, count in (
            ("t158_signed_lazy_tile_bounds", "T158_TILE_BOUNDS_PASSED", 24),
            ("t159_signed_replay_publication_bounds", "T159_SIGNED_REPLAY_PASSED", 39),
        ):
            self.assertIn(f"res://tests/{name}.gd", workflow)
            self.assertIn(f"--marker {marker}", workflow)
            self.assertIn(f"{marker} checks={count} failures=0", workflow)

    def test_required_fast_step_bootstraps_first_tile_local_edit(self) -> None:
        workflow = FAST.read_text()
        name = "t232_tile_native_bootstrap"
        marker = "T232_TILE_BOOTSTRAP_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=34 failures=0", workflow)

    def test_required_fast_step_bootstraps_first_pixel_map_edit(self) -> None:
        workflow = FAST.read_text()
        name = "t233_pixel_native_bootstrap"
        marker = "T233_PIXEL_BOOTSTRAP_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=37 failures=0", workflow)

    def test_required_fast_step_preflights_native_brush_publication(self) -> None:
        workflow = FAST.read_text()
        name = "t234_native_publication_preflight"
        marker = "T234_NATIVE_PUBLICATION_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=32 failures=0", workflow)

    def test_required_fast_step_preflights_tile_local_patch_inputs(self) -> None:
        workflow = FAST.read_text()
        name = "t235_tile_patch_preflight"
        marker = "T235_TILE_PREFLIGHT_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=34 failures=0", workflow)

    def test_required_fast_step_preflights_pixel_map_inputs(self) -> None:
        workflow = FAST.read_text()
        name = "t236_pixel_map_preflight"
        marker = "T236_PIXEL_PREFLIGHT_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=35 failures=0", workflow)

    def test_required_fast_step_preflights_detached_tile_history(self) -> None:
        workflow = FAST.read_text()
        name = "t237_detached_tile_replay_preflight"
        marker = "T237_HISTORY_PREFLIGHT_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=40 failures=0", workflow)

    def test_required_fast_step_rechecks_brush_source_bytes_after_lazy_callbacks(self) -> None:
        workflow = FAST.read_text()
        name = "t238_brush_source_reentrancy"
        marker = "T238_BRUSH_SOURCE_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=18 failures=0", workflow)

    def test_required_fast_step_rejects_retained_out_of_order_history(self) -> None:
        workflow = FAST.read_text()
        name = "t239_native_history_order"
        marker = "T239_HISTORY_ORDER_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=36 failures=0", workflow)

    def test_required_fast_step_preflights_native_ffi_payloads(self) -> None:
        workflow = FAST.read_text()
        name = "t240_native_ffi_payload_preflight"
        marker = "T240_FFI_PREFLIGHT_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=32 failures=0", workflow)

    def test_required_fast_step_fences_host_owned_history_handoff(self) -> None:
        workflow = FAST.read_text()
        name = "t241_host_history_owner_fence"
        marker = "T241_HOST_OWNER_PASSED"
        source_path = ROOT / f"drawing/tests/{name}.gd"
        self.assertTrue(source_path.is_file())
        self.assertIn(marker, source_path.read_text())
        self.assertIn(f"res://tests/{name}.gd", workflow)
        self.assertIn(f"--marker {marker}", workflow)
        self.assertIn(f"{marker} checks=29 failures=0", workflow)

    def test_required_fast_step_protects_external_history_property(self) -> None:
        workflow = FAST.read_text()
        for project, name, marker, count in (
            ("drawing", "t242_history_mode_readonly", "T242_HISTORY_MODE_PASSED", 25),
            (".", "t242_atlas_history_mode_readonly", "T242_ATLAS_MODE_PASSED", 18),
        ):
            path = ROOT / ("drawing/tests" if project == "drawing" else "tests") / f"{name}.gd"
            self.assertTrue(path.is_file())
            self.assertIn(marker, path.read_text())
            self.assertIn(f"--path {project} --script res://tests/{name}.gd", workflow)
            self.assertIn(f"--marker {marker}", workflow)
            self.assertIn(f"{marker} checks={count} failures=0", workflow)

    def test_optional_native_ci_retains_tile_publication_and_rollback(self) -> None:
        workflow = NATIVE.read_text()
        self.assertIn("res://tests/t095_native_pigment_atomic.gd", workflow)
        self.assertIn("--marker T095_NATIVE_PIGMENT_ATOMIC_PASSED", workflow)
        self.assertIn("res://tests/t148_document_tile_publication.gd", workflow)
        self.assertIn("--marker T148_DOCUMENT_TILES_PASSED", workflow)
        self.assertIn("T148_DOCUMENT_TILES_RESULT checks=56 failures=0", workflow)
        for name in ("t158_signed_lazy_tile_bounds", "t159_signed_replay_publication_bounds"):
            self.assertIn(f"{name}:", workflow)

    def test_ci_script_paths_and_success_markers_exist(self) -> None:
        for name, marker in (
            ("t095_native_pigment_atomic", "T095_NATIVE_PIGMENT_ATOMIC_PASSED"),
            ("t148_document_tile_publication", "T148_DOCUMENT_TILES_PASSED"),
            ("t158_signed_lazy_tile_bounds", "T158_TILE_BOUNDS_PASSED"),
            ("t159_signed_replay_publication_bounds", "T159_SIGNED_REPLAY_PASSED"),
        ):
            source_path = ROOT / f"drawing/tests/{name}.gd"
            self.assertTrue(source_path.is_file(), f"missing {source_path}")
            self.assertIn(marker, source_path.read_text())
        # The old test bridge must have no remaining consumers in runnable tests.
        for source_path in (ROOT / "drawing/tests").glob("*.gd"):
            self.assertNotIn("t147_scripted_session_bridge.gd", source_path.read_text(), source_path.name)


if __name__ == "__main__":
    unittest.main()
