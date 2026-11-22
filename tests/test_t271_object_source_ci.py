"""T-271: required-native Object discovery and Atlas source-identity CI contracts."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from tools.check_godot_model_log import verify_log  # noqa: E402
from tools.check_native_t093_log import verify as verify_t093  # noqa: E402
from tools.check_native_t120_log import verify as verify_t120  # noqa: E402

WORKFLOW = ROOT / ".github/workflows/godot-native-t093-object-sources.yml"
MAKEFILE = ROOT / "Makefile"


class T271ObjectSourceCIContracts(unittest.TestCase):
    def test_workflow_builds_and_imports_both_consumers_before_native_tests(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        for item in (
            "dtolnay/rust-toolchain@stable",
            "toolchain: 1.99.1",
            "make build TOOLCHAIN=system",
            "--path drawing",
            "--path .",
            "object_discovery_smoke.gd",
            "T093_MODEL: 56 checks; 0 failed",
            "object_discovery_native.gd",
            "t120_file_object_native.gd",
            "t271_atlas_object_sources_native.gd",
            "T271_ATLAS: 24 checks; 0 failed",
            "check_native_t093_log.py",
            "check_native_t120_log.py",
            "T271_ATLAS_PASSED",
            "tools/check_godot_model_log.py",
            "actions/upload-artifact@v4",
        ):
            with self.subTest(item=item):
                self.assertIn(item, source)
        self.assertLess(source.index("make build TOOLCHAIN=system"),
                        source.index("object_discovery_smoke.gd"))
        self.assertLess(source.index("object_discovery_smoke.gd"),
                        source.index("object_discovery_native.gd"))
        self.assertLess(source.index("t120_file_object_native.gd"),
                        source.index("t271_atlas_object_sources_native.gd"))
        self.assertIn("set -euo pipefail", source)
        self.assertIn("/tmp/t271-atlas.log", source)

    def test_make_target_stages_and_fails_closed(self) -> None:
        source = MAKEFILE.read_text(encoding="utf-8")
        target = "test-object-sources: import-drawing import-atlas"
        self.assertIn(target, source)
        block = source.split(target + "\n", 1)[1].split("\n# ", 1)[0]
        for item in (
            "set -euo pipefail",
            "object_discovery_smoke.gd",
            "object_discovery_native.gd",
            "t120_file_object_native.gd",
            "t271_atlas_object_sources_native.gd",
            "check_native_t093_log.py",
            "check_native_t120_log.py",
            "T093_MODEL: 56 checks; 0 failed",
            "T271_ATLAS: 24 checks; 0 failed",
            "T271_ATLAS_PASSED",
            "check_godot_model_log.py",
            'tee "$$log"',
            "timeout",
        ):
            with self.subTest(item=item):
                self.assertIn(item, block)
        self.assertEqual(block.count("set -euo pipefail"), 4)

    def test_standalone_and_atlas_log_oracles_reject_incomplete_evidence(self) -> None:
        t093 = "T093_NATIVE: 27 checks; 0 failed\nT093_NATIVE_PASSED"
        t120 = "T120_NATIVE: 20 checks; 0 failed\nT120_NATIVE_PASSED"
        atlas = "T271_ATLAS: 24 checks; 0 failed\nT271_ATLAS_PASSED"
        self.assertTrue(verify_t093(t093)[0])
        self.assertTrue(verify_t120(t120)[0])
        self.assertEqual(verify_log(atlas, "T271_ATLAS_PASSED")[0], [])
        for sample in (
            t093.replace("27 checks", "26 checks"),
            t093 + "\nT093_NATIVE_PASSED",
            "SCRIPT ERROR: native extension missing\n" + t093,
        ):
            with self.subTest(log=sample):
                self.assertFalse(verify_t093(sample)[0])
        for sample in (
            t120.replace("20 checks", "1 checks"),
            "ERROR: source mismatch\n" + t120,
        ):
            with self.subTest(log=sample):
                self.assertFalse(verify_t120(sample)[0])
        for sample in (
            atlas.replace("24 checks", "23 checks"),
            atlas.replace("0 failed", "1 failed"),
            atlas + "\nT271_ATLAS_PASSED",
            "SCRIPT ERROR: stale source\n" + atlas,
        ):
            with self.subTest(log=sample):
                # The generic log checker owns runtime/duplicate marker checks;
                # the recipe must enforce the separately pinned 24-check line.
                if "23 checks; 0 failed" in sample or "24 checks; 1 failed" in sample:
                    self.assertNotIn("T271_ATLAS: 24 checks; 0 failed", sample)
                else:
                    self.assertTrue(verify_log(sample, "T271_ATLAS_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
