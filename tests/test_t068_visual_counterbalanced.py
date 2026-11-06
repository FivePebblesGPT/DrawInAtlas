"""Fail-closed replay of T-068 ABBA synthetic-frame load comparisons."""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_visual_counterbalanced as counterbalanced  # noqa: E402

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_visual_counterbalanced_software.json"


class CounterbalancedContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_record(self) -> None:
        counterbalanced.validate(self.evidence)
        self.assertEqual([p["name"] for p in self.evidence["phases"]],
                         list(counterbalanced.PHASES))
        self.assertEqual(sum(len(p["visual"]["stress"]["rows"]) for p in self.evidence["phases"]), 20)
        self.assertEqual(sum(p["visual"]["stress"]["checks"] for p in self.evidence["phases"]), 324)

    def test_tampered_records(self) -> None:
        for mutation in ("source", "phase_order", "phase_count", "worker", "idle_worker",
                         "contrast", "contrast_missing", "raw_sample", "median", "pixel",
                         "memory", "renderer", "profile", "limitations"):
            with self.subTest(mutation=mutation):
                forged = copy.deepcopy(self.evidence)
                first = forged["phases"][0]["visual"]
                if mutation == "source":
                    forged["sources"][next(iter(forged["sources"]))] = "0" * 64
                elif mutation == "phase_order":
                    forged["phases"].reverse()
                elif mutation == "phase_count":
                    forged["phases"].pop()
                elif mutation == "worker":
                    forged["phases"][1]["worker_ticks"]["after"] = forged["phases"][1]["worker_ticks"]["before"]
                elif mutation == "idle_worker":
                    forged["phases"][0]["worker_ticks"] = {"before": 1, "after": 2}
                elif mutation == "contrast":
                    forged["contrasts_ms"]["dab_4px"]["average_ms"] += 1
                elif mutation == "contrast_missing":
                    forged["contrasts_ms"].pop("dab_4px")
                elif mutation == "raw_sample":
                    first["stress"]["rows"][0]["event_to_frame_post_draw"]["samples_ms"].pop()
                elif mutation == "median":
                    first["stress"]["rows"][0]["cpu_dispatch"]["median_ms"] += 1
                elif mutation == "pixel":
                    first["stress"]["checks"] -= 1
                elif mutation == "memory":
                    first["process_memory_kib"]["hwm_peak"] -= 1
                elif mutation == "renderer":
                    forged["phases"][2]["visual"]["stress"]["adapter"] = "different"
                elif mutation == "profile":
                    first["profile"] = "hardware"
                else:
                    forged["limitations"].pop()
                with self.assertRaises(ValueError):
                    counterbalanced.validate(forged)

    @unittest.skipUnless(os.environ.get("T068_VISUAL_COUNTERBALANCED_GODOT"), "Opt-in X11 ABBA run")
    def test_live(self) -> None:
        record = counterbalanced.live(Path(os.environ["T068_VISUAL_COUNTERBALANCED_GODOT"]))
        counterbalanced.validate(record)


if __name__ == "__main__":
    unittest.main()
