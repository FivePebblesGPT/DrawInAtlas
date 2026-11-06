"""T-068 concurrency witness contracts (isolated native C++, not Godot UX)."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "benchmarks"))
from t068_native_thread_jitter import (  # noqa: E402
    compile_benchmark, parse_tsv, run,
)


class NativeJitterTests(unittest.TestCase):
    @staticmethod
    def fixture() -> str:
        return ("case\tmode\tworkers\ttrials\tcandidates\tchanged\tmedian_ms\tp95_ms\tmax_ms\tchecked_calls\n" +
                "\n".join(f"{case}\t{mode}\t1\t3\t400\t125\t0.10\t0.20\t0.25\t3"
                          for case in ("overlapping_source_over", "masked_erase", "exact_replace")
                          for mode in ("sparse", "full")))

    def test_parser_requires_full_set_and_valid_counts(self) -> None:
        valid = parse_tsv(self.fixture(), 128, 3, (1,))
        self.assertEqual(len(valid["rows"]), 6)
        self.assertEqual(valid["schema"], "t068-native-thread-jitter-v1")
        for mutation in ("bad header", self.fixture().splitlines()[0] + "\n",
                         self.fixture() + "\n" + self.fixture().splitlines()[1],
                         self.fixture().replace("\t0.20\t", "\t0.05\t"),
                         self.fixture().replace("\t125\t", "\t500\t"),
                         self.fixture().replace("\t3\t400\t", "\t4\t400\t")):
            with self.subTest(mutation=mutation[:40]), self.assertRaises(ValueError):
                parse_tsv(mutation, 128, 3, (1,))

    @unittest.skipUnless(shutil.which("g++") is not None, "C++ compiler required")
    def test_native_threads_match_all_modes_with_distinct_buffers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            executable = compile_benchmark(Path(directory))
            evidence = run(executable, 128, 4, (1, 2, 4))
            self.assertEqual(len(evidence["rows"]), 18)
            self.assertTrue(all(row["checked_calls"] == row["workers"] * 4
                                for row in evidence["rows"]))
            self.assertTrue(all(row["p95_ms"] >= row["median_ms"]
                                for row in evidence["rows"]))
            for bad_region in (0, 64, 150, 2048):
                with self.assertRaises(ValueError):
                    run(executable, bad_region, 4, (1,))
            for bad_workers in ((), (0,), (1, 1), (17,)):
                with self.assertRaises(ValueError):
                    run(executable, 128, 4, bad_workers)


if __name__ == "__main__":
    unittest.main()
