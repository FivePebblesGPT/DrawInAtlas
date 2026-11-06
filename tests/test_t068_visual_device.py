"""T-068 non-shipping Godot visual/RSS evidence and physical-device gates."""
from __future__ import annotations

import copy
import json
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_visual_device as device  # noqa: E402

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_visual_process_software.json"


class VisualDeviceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.record = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_pinned_software_evidence(self) -> None:
        device.validate(self.record)
        self.assertEqual(self.record["stress"]["checks"], 81)
        self.assertEqual(sum(len(row["cpu_dispatch"]["samples_ms"])
                             for row in self.record["stress"]["rows"]), 25)
        self.assertGreater(self.record["process_memory_kib"]["hwm_peak"], 0)
        self.assertTrue(device.software_renderer(self.record["stress"]["adapter"]))

    def test_timing_phase_and_statistics_fail_closed(self) -> None:
        for tamper in ("missing_sample", "median", "p95", "too_early", "missing_row", "checks", "engine"):
            with self.subTest(tamper=tamper):
                changed = copy.deepcopy(self.record)
                row = changed["stress"]["rows"][0]
                if tamper == "missing_sample":
                    row["cpu_dispatch"]["samples_ms"].pop()
                elif tamper == "median":
                    row["cpu_dispatch"]["median_ms"] += 5
                elif tamper == "p95":
                    row["event_to_frame_post_draw"]["p95_ms"] *= 0.5
                elif tamper == "too_early":
                    row["event_to_frame_post_draw"]["samples_ms"][0] = 0.01
                elif tamper == "missing_row":
                    changed["stress"]["rows"].pop()
                elif tamper == "checks":
                    changed["stress"]["checks"] -= 1
                else:
                    changed["stress"]["engine"]["status"] = "stable"
                with self.assertRaises(ValueError):
                    device.validate(changed)

    def test_process_memory_series_fail_closed(self) -> None:
        for tamper in ("missing", "false_peak", "negative", "hwm_rollback", "source"):
            with self.subTest(tamper=tamper):
                changed = copy.deepcopy(self.record)
                mem = changed["process_memory_kib"]
                if tamper == "missing":
                    mem["rss_samples"].pop()
                elif tamper == "false_peak":
                    mem["hwm_peak"] += 10000
                elif tamper == "negative":
                    mem["rss_samples"][0] = -1
                elif tamper == "hwm_rollback":
                    mem["hwm_samples"][-1] = mem["hwm_samples"][0] - 1
                else:
                    changed["sources"][next(iter(changed["sources"]))] = "0" * 64
                with self.assertRaises(ValueError):
                    device.validate(changed)

    def test_hardware_profile_is_not_inferred(self) -> None:
        with self.assertRaises(ValueError):
            device.validate_hardware(None, "llvmpipe", {})
        with self.assertRaises(ValueError):
            device.validate_hardware("llvmpipe", "Intel Iris Xe", {})
        with self.assertRaises(ValueError):
            device.validate_hardware("Mesa Intel Iris Xe", "Intel Iris Xe",
                                     {"LIBGL_ALWAYS_SOFTWARE": "1"})
        with self.assertRaises(ValueError):
            device.validate_hardware("Mesa Intel Iris Xe", "Intel Iris Xe",
                                     {"GALLIUM_DRIVER": "softpipe"})
        device.validate_hardware("Mesa Intel Iris Xe", "Intel Iris Xe", {})
        changed = copy.deepcopy(self.record)
        changed["profile"] = "hardware"
        with self.assertRaises(ValueError):
            device.validate(changed)
        changed["profile"] = "software"
        changed["stress"]["adapter"] = "Mesa Intel Iris Xe"
        with self.assertRaises(ValueError):
            device.validate(changed)

    def test_linux_status_parser(self) -> None:
        if sys.platform != "linux":
            self.skipTest("Linux /proc only")
        snapshot = device.status_memory(os.getpid())
        self.assertIsNotNone(snapshot)
        self.assertGreater(snapshot["VmRSS"], 0)
        self.assertGreaterEqual(snapshot["VmHWM"], snapshot["VmRSS"])
        self.assertIsNone(device.status_memory(99999999))

    @unittest.skipUnless(os.environ.get("T068_VISUAL_GODOT"),
                         "Opt-in real X11 Godot process: T068_VISUAL_GODOT=/path/to/godot")
    def test_live_software_compatibility(self) -> None:
        # Explicit X11/Xvfb launch is the caller's responsibility.
        actual = device.live(Path(os.environ["T068_VISUAL_GODOT"]), "software")
        self.assertEqual(actual["stress"]["checks"], 81)
        device.validate(actual)


if __name__ == "__main__":
    unittest.main()
