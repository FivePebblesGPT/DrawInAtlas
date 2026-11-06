"""T-068 source-pinned Linux process-memory and native parity evidence."""
from __future__ import annotations

import copy
import json
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))

from t068_native_memory import EVIDENCE, SIDES, validate


class NativeMemoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.record = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_source_pinned_evidence(self) -> None:
        validate(self.record)
        self.assertEqual({r["side"] for run in self.record["runs"] for r in run}, set(SIDES))
        self.assertEqual(sum(len(run) for run in self.record["runs"]), 12)

    def test_reject_mutated_source_or_oracle(self) -> None:
        for change in ("source", "pixel", "selection", "case"):
            with self.subTest(change=change):
                record = copy.deepcopy(self.record)
                row = record["runs"][0][0]
                if change == "source":
                    record["sources"][next(iter(record["sources"]))] = "0" * 64
                elif change == "pixel":
                    row["pixels_sha256"] = "0" * 64
                elif change == "selection":
                    row["selection_sha256"] = "0" * 64
                else:
                    row["case"] = "unrelated"
                with self.assertRaises(ValueError):
                    validate(record)

    def test_reject_missing_duplicate_and_reordered_workers(self) -> None:
        for change in ("remove", "duplicate", "swap", "run"):
            with self.subTest(change=change):
                record = copy.deepcopy(self.record)
                if change == "remove":
                    record["runs"][0].pop()
                elif change == "duplicate":
                    record["runs"][0][-1] = record["runs"][0][0]
                elif change == "swap":
                    record["runs"][0][0], record["runs"][0][1] = record["runs"][0][1], record["runs"][0][0]
                else:
                    record["runs"].pop()
                with self.assertRaises(ValueError):
                    validate(record)

    def test_reject_invalid_memory_metrics(self) -> None:
        for field, value in (
            ("rss_before_prep_kib", -1), ("rss_before_call_kib", True),
            ("rss_after_call_kib", 2_000_001), ("hwm_before_call_kib", 0),
            ("hwm_after_call_kib", 0), ("hwm_native_growth_kib", 1_000_000),
            ("native_status", -1),
        ):
            with self.subTest(field=field):
                record = copy.deepcopy(self.record)
                record["runs"][0][0][field] = value
                with self.assertRaises(ValueError):
                    validate(record)

    @unittest.skipUnless(os.getenv("T068_BLEND2D_ARCHIVE") and os.getenv("T068_BLEND2D_SOURCE") and
                         os.getenv("T068_BLEND2D_BUILD"), "Optional live Blend2D library required")
    def test_live_fresh_processes(self) -> None:
        from t068_native_memory import live
        result = live(Path(os.environ["T068_BLEND2D_ARCHIVE"]),
                      Path(os.environ["T068_BLEND2D_SOURCE"]), Path(os.environ["T068_BLEND2D_BUILD"]))
        validate(result)


if __name__ == "__main__":
    unittest.main()
