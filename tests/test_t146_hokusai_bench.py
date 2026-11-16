"""Offline strict T-146 benchmark report tests; no Godot/X11 required."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from run_t146_hokusai_bench import p, summary, verify_run_log  # noqa: E402


def candidate_source(zero: int = 0) -> str:
    return (f"T146_SOURCE label=stroke-0 sha256={'a' * 64} covered={262144-zero} zero={zero} "
            f"alpha_1_63=0 alpha_64_127=0 alpha_128_191={262144-zero} "
            "alpha_192_254=0 alpha_255=0 red=262144 nonred=0 first_hole=(-1, -1) "
            f"fills_512={str(zero == 0).lower()}")


def candidate_log() -> str:
    return "\n".join([
        f"T146_IDENTITY backend=Hokusai preset=hard width=96 preset_sha256={'a'*64} "
        f"native_sha256={'b'*64} repo_sha={'c'*40}",
        "T146_HOKUSAI_RUN index=0 backend=Hokusai source_pixels=262144 width_px=96 "
        "input_events=100 total_to_postdraw_ms=2800 release_to_commit_ms=2700 "
        "stage_cpu_ms=740 commit_cpu_ms=1400 compose_cpu_ms=200 texture_cpu_ms=5 "
        "max_drain_ms=35 max_frame_draw_ms=20",
        candidate_source(),
        candidate_source().replace("stroke-0", "redo-0"),
        "T146_FILL_STATUS index=0 full_coverage=true holes=0",
        *["T146_FRAMEBUFFER index=0 point=(0.5, 0.5) rgba=(1, 0, 0, 1) source_rgba=ff0000ff"] * 5,
        "T146_FIRST_VISIBLE index=0 down_us=1000 first_submit_us=1500 first_postdraw_us=2000 "
        "postdraw_matches=1 frame_samples=2",
        "T146_NATIVE_PHASE index=0 native_ffi_calls=30 tile_ffi_calls=45 "
        "tile_bytes_exported=1048576 tile_pixel_stream_calls=0 stage_cpu_ms=740",
        "T146_CANCEL_RETRY revision=2 base_revision=1 events=1",
        "T146_MASK_HIDDEN_RGB native=Hokusai rgba=00332211 revision=5",
    ])


class T146ReporterTests(unittest.TestCase):
    def test_candidate_exact_complete_run(self) -> None:
        parsed = verify_run_log(candidate_log(), "Hokusai", 1)
        self.assertEqual(parsed[0]["source_coverage"], 262144)
        self.assertEqual(parsed[0]["first_postdraw_ms"], 1.0)
        self.assertEqual(parsed[0]["native_ffi_calls"], 30)
        self.assertEqual(parsed[0]["tile_bytes_exported"], 1048576)

    def test_zero_alpha_cannot_pass_full_coverage(self) -> None:
        text = candidate_log().replace(candidate_source(), candidate_source(10))
        with self.assertRaisesRegex(ValueError, "full-coverage"):
            verify_run_log(text, "Hokusai", 1)

    def test_mismatched_redo_is_rejected(self) -> None:
        text = candidate_log().replace("T146_SOURCE label=redo-0 sha256=" + "a" * 64,
                                       "T146_SOURCE label=redo-0 sha256=" + "b" * 64)
        with self.assertRaisesRegex(ValueError, "Undo/Redo"):
            verify_run_log(text, "Hokusai", 1)

    def test_missing_framebuffer_witness_is_rejected(self) -> None:
        text = candidate_log().replace("T146_FRAMEBUFFER ", "T146_NOT_FRAMEBUFFER ")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            verify_run_log(text, "Hokusai", 1)

    def test_nonfinite_latency_is_rejected(self) -> None:
        text = candidate_log().replace("stage_cpu_ms=740", "stage_cpu_ms=nan")
        with self.assertRaisesRegex(ValueError, "missing/nonfinite"):
            verify_run_log(text, "Hokusai", 1)

    def test_mismatched_histogram_rejected(self) -> None:
        text = candidate_log().replace("alpha_128_191=262144", "alpha_128_191=999")
        with self.assertRaisesRegex(ValueError, "histogram"):
            verify_run_log(text, "Hokusai", 1)

    def test_silent_native_fallback_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "backend"):
            verify_run_log(candidate_log().replace("backend=Hokusai", "backend=Legacy"),
                           "Hokusai", 1)

    def test_missing_last_pointer_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "input_events"):
            verify_run_log(candidate_log().replace("input_events=100", "input_events=99"),
                           "Hokusai", 1)

    def test_partial_success_count_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "expected 2"):
            verify_run_log(candidate_log(), "Hokusai", 2)

    def test_no_backend_comparison_is_accepted(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown backend"):
            verify_run_log(candidate_log(), "Legacy", 1)

    def test_nearest_rank_and_sample_counts(self) -> None:
        self.assertEqual(p([4.0, 1.0, 3.0, 2.0], .95), 4)
        self.assertEqual(p([4.0, 1.0, 3.0, 2.0], .50), 2)
        stats = summary([{"total_to_postdraw_ms": "2"}, {"total_to_postdraw_ms": "5"}])
        self.assertEqual(stats["total_to_postdraw_ms"]["n"], 2)
        self.assertEqual(stats["total_to_postdraw_ms"]["p95"], 5)


if __name__ == "__main__":
    unittest.main()
