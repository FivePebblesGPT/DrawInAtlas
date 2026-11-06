"""Offline, fail-closed T-068 Linux software visual-contention evidence contracts."""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_visual_contention as contention  # noqa: E402

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_visual_contention_software.json"


class ContentionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_pinned_evidence(self) -> None:
        contention.validate(self.evidence)
        self.assertEqual([x["name"] for x in self.evidence["phases"]], list(contention.PHASES))
        self.assertEqual(sum(len(x["visual"]["stress"]["rows"]) for x in self.evidence["phases"]), 10)

    def test_tampering_is_rejected(self) -> None:
        for mutation in ("source", "phase", "missing", "label", "ticks", "difference",
                         "sample", "sample_stat", "rss", "gpu", "limitations"):
            with self.subTest(mutation=mutation):
                forged = copy.deepcopy(self.evidence)
                first = forged["phases"][0]["visual"]
                if mutation == "source":
                    forged["sources"][next(iter(forged["sources"]))] = "0" * 64
                elif mutation == "phase":
                    forged["phases"].reverse()
                elif mutation == "missing":
                    forged["phases"].pop()
                elif mutation == "label":
                    forged["phases"][1]["name"] = "idle"
                elif mutation == "ticks":
                    forged["worker_ticks"]["after"] = forged["worker_ticks"]["before"]
                elif mutation == "difference":
                    key = next(iter(forged["frame_median_delta_ms"]))
                    forged["frame_median_delta_ms"][key] += 0.01
                elif mutation == "sample":
                    first["stress"]["rows"][0]["cpu_dispatch"]["samples_ms"].pop()
                elif mutation == "sample_stat":
                    first["stress"]["rows"][0]["event_to_frame_post_draw"]["p95_ms"] += 10
                elif mutation == "rss":
                    first["process_memory_kib"]["hwm_peak"] += 1
                elif mutation == "gpu":
                    first["profile"] = "hardware"
                else:
                    forged["limitations"].pop()
                with self.assertRaises(ValueError):
                    contention.validate(forged)

    @unittest.skipUnless(os.environ.get("T068_VISUAL_GODOT"), "Opt-in X11 Godot jitter run")
    def test_live(self) -> None:
        record = contention.live(Path(os.environ["T068_VISUAL_GODOT"]))
        contention.validate(record)


if __name__ == "__main__":
    unittest.main()
