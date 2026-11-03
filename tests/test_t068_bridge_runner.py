"""T-068: isolated GDExtension runner contracts; no Godot/native UI in push CI."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/benchmarks/t068_bridge/run_bridge.py"
SPEC = importlib.util.spec_from_file_location("t068_bridge_runner", SOURCE)
assert SPEC is not None and SPEC.loader is not None
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class IsolatedBridgeRunnerContracts(unittest.TestCase):
    def test_references_only_test_assets_and_existing_checked_kernel(self) -> None:
        self.assertEqual(bridge.ROOT, ROOT)
        self.assertTrue((bridge.BRIDGE / "t068_bridge.cpp").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_bridge_smoke.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_revision_adapter.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_revision_smoke.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_document_adapter.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_document_smoke.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_document_batch_adapter.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_document_batch_smoke.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_document_sparse_adapter.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_document_sparse_smoke.gd").is_file())
        self.assertTrue((ROOT / "tools/benchmarks/t068_raster_kernel.cpp").is_file())
        self.assertFalse(list(ROOT.rglob("*.gdextension")),
                         "The experimental native extension must not load at app startup")

    def test_correctness_marker_and_multiple_runs(self) -> None:
        expected = "T068_BRIDGE_PASSED: 443 checks\n"
        self.assertEqual(bridge.PASS_RE.search(expected).group(1), "443")
        self.assertIsNone(bridge.PASS_RE.search("T068_BRIDGE_FAILED: 1/443"))
        self.assertEqual(bridge.REVISION_RE.search(
            "T068_REVISION_PASSED: 370 checks\n").group(1), "370")
        self.assertIsNone(bridge.REVISION_RE.search("T068_REVISION_FAILED: 1/370"))
        self.assertEqual(bridge.DOCUMENT_RE.search(
            "T068_DOCUMENT_PASSED: 219 checks\n").group(1), "219")
        self.assertIsNone(bridge.DOCUMENT_RE.search("T068_DOCUMENT_FAILED: 1/219"))
        self.assertEqual(bridge.BATCH_RE.search("T068_BATCH_PASSED: 128 checks\n").group(1), "128")
        self.assertIsNone(bridge.BATCH_RE.search("T068_BATCH_FAILED: 1/128"))
        self.assertEqual(bridge.SPARSE_RE.search(
            "T068_SPARSE_PASSED: 173 checks\n").group(1), "173")
        self.assertIsNone(bridge.SPARSE_RE.search("T068_SPARSE_FAILED: 1/173"))
        self.assertIsNotNone(bridge.SPARSE_TIMING_RE.search(
            'T068_SPARSE_TIMING: {"32":{"full_median_us":100}}\n'))
        self.assertIsNotNone(bridge.TIMING_RE.search(
            'T068_BRIDGE_TIMING: {"32":{"median_us":8}}\n'))

    def test_nonzero_exit_and_godot_errors_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wd = Path(tmp)
            self.assertIn("ready", bridge.checked_run(
                [sys.executable, "-c", "print('ready')"], cwd=wd, timeout=10))
            with self.assertRaises(RuntimeError):
                bridge.checked_run([sys.executable, "-c", "raise SystemExit(3)"],
                                   cwd=wd, timeout=10)
            for diagnostic in ("SCRIPT ERROR: parse failed", "ERROR: invalid extension",
                               "T068_BRIDGE_FAIL: mismatched bytes",
                               "T068_REVISION_FAIL: stale write accepted",
                               "T068_REVISION_FAILED: 1/370",
                               "T068_DOCUMENT_FAIL: stale revision accepted",
                               "T068_DOCUMENT_FAILED: 1/219",
                               "T068_BATCH_FAIL: partial publication",
                               "T068_BATCH_FAILED: 1/128",
                               "T068_SPARSE_FAIL: malicious delta",
                               "T068_SPARSE_FAILED: 1/173"):
                with self.subTest(diagnostic=diagnostic), self.assertRaises(RuntimeError):
                    bridge.checked_run([sys.executable, "-c",
                                        f"print({diagnostic!r})"], cwd=wd, timeout=10)

    def test_generated_header_and_compiler_called_without_mutating_main_project(self) -> None:
        original = SOURCE.read_text(encoding="utf-8")
        self.assertIn("--dump-gdextension-interface", original)
        self.assertIn("with tempfile.TemporaryDirectory", original)
        self.assertIn("str(ROOT / \"tools/benchmarks/t068_raster_kernel.cpp\")", original)
        self.assertIn('"--script", "res://test.gd"', original)
        self.assertNotIn('ROOT / "project.godot").write_text(', original)
        self.assertIn('drawing.mkdir(parents=True)', original)
        self.assertIn('shutil.copyfile(ROOT / "addons" / "drawing"', original)
        self.assertNotIn('shutil.copytree(ROOT / "addons"', original)

    def test_canonical_script_dependency_subset_is_explicit(self) -> None:
        expected = {"document", "edit_session", "signed_tiles", "layer_node",
                    "raster_tile", "result", "delta", "dirty_region", "selection",
                    "history_context", "text_element", "text_raster"}
        self.assertEqual(set(bridge.CANONICAL_SCRIPTS), expected)
        for stem in expected:
            self.assertTrue((ROOT / "addons" / "drawing" / (stem + ".gd")).is_file())
        self.assertNotIn("workspace", expected)

    def test_real_document_adapter_requires_transactional_publication(self) -> None:
        adapter = (bridge.BRIDGE / "t068_document_adapter.gd").read_text(encoding="utf-8")
        witness = (bridge.BRIDGE / "t068_document_smoke.gd").read_text(encoding="utf-8")
        for required in ("request_chunk_at", "begin_edit", "apply_region", "edit.commit()",
                         "expected_revision", "STALE_REVISION", "COORD_RANGE"):
            self.assertIn(required, adapter)
        for required in ("doc.undo()", "doc.redo()", "register_lazy_chunk",
                         "T068_DOCUMENT_PASSED", "DrawingEditSession._blend"):
            self.assertIn(required, witness)
        self.assertNotIn(".texture.update(", adapter)
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn('"document_checks": int(document_match.group(1))', source)
        self.assertIn('"res://document_test.gd"', source)

    def test_multi_tile_adapter_stays_atomic_and_opt_in(self) -> None:
        adapter = (bridge.BRIDGE / "t068_document_batch_adapter.gd").read_text(encoding="utf-8")
        witness = (bridge.BRIDGE / "t068_document_batch_smoke.gd").read_text(encoding="utf-8")
        runner = SOURCE.read_text(encoding="utf-8")
        for required in ("MAX_TILES", "MAX_PIXELS", "DUPLICATE_TILE",
                         "request_chunk_at", "edit.apply_region", "edit.commit()",
                         "edit.cancel()", "STALE_REVISION", "dirty_tiles"):
            self.assertIn(required, adapter)
        for required in ("doc.undo()", "doc.redo()", "MISSING_TILE",
                         "CORRUPT_TILE", "BATCH_LIMIT", "T068_BATCH_PASSED"):
            self.assertIn(required, witness)
        self.assertIn('"res://batch_test.gd"', runner)
        self.assertIn('"batch_checks": int(batch_match.group(1))', runner)
        self.assertNotIn("addons/drawing/workspace", adapter)
        self.assertNotIn("ImageTexture", adapter)

    def test_sparse_native_delta_wire_is_checked_before_document_publication(self) -> None:
        cpp = (bridge.BRIDGE / "t068_bridge.cpp").read_text(encoding="utf-8")
        adapter = (bridge.BRIDGE / "t068_document_sparse_adapter.gd").read_text(encoding="utf-8")
        witness = (bridge.BRIDGE / "t068_document_sparse_smoke.gd").read_text(encoding="utf-8")
        for marker in ("draw_batch_deltas_checked", "apply_sparse_checked",
                       "process_sparse", "put32", "ptrcall_sparse", "call_sparse"):
            self.assertIn(marker, cpp)
        for marker in ("NATIVE_DELTA", "source.decode_u32", "expected.has(index)",
                       "seen.has(index)", "count != expected.size()", "DrawingEditSession._blend",
                       "request_chunk_at", "edit._stage(", "edit.cancel()", "edit.commit()"):
            self.assertIn(marker, adapter)
        for marker in ("ForgedBridge", "CountingBridge", "forged zero-count response",
                       "omitted second-tile deltas", "CORRUPT_TILE", "MISSING_TILE",
                       "T068_SPARSE_PASSED", "T068_SPARSE_TIMING", "hidden RGB"):
            self.assertIn(marker, witness)
        self.assertNotIn("ImageTexture", adapter)
        self.assertNotIn("workspace.gd", adapter)
        self.assertFalse(list(ROOT.rglob("*.gdextension")))

    def test_sparse_runner_is_on_demand_with_fail_closed_evidence(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text(
            encoding="utf-8")
        for required in ('"res://sparse_test.gd"', '"sparse_benchmark": sparse_benchmark',
                         '"sparse_checks": int(sparse_match.group(1))',
                         "SPARSE_TIMING_RE.search", "Missing or insufficient sparse checks"):
            self.assertIn(required, source)
        self.assertIn("workflow_dispatch", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertNotIn("push:", workflow)
        self.assertIn("run_bridge.py", workflow)

    def test_revision_checks_require_native_renderer_and_isolation(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn('shutil.which("xvfb-run")', source)
        self.assertIn('"--audio-driver", "Dummy"', source)
        self.assertIn('"res://revision_test.gd"', source)
        self.assertIn('"revision_checks": int(revision_match.group(1))', source)
        self.assertIn("T068_REVISION_PASSED", source)
        self.assertNotIn('ROOT / "scripts"', source)
        adapter = (bridge.BRIDGE / "t068_revision_adapter.gd").read_text(encoding="utf-8")
        self.assertIn('expected_revision != revision or original != _pixels', adapter)
        self.assertIn('texture.update(_image())', adapter)
        self.assertIn('"dirty_rect": Rect2i(', adapter)



if __name__ == "__main__":
    unittest.main()
