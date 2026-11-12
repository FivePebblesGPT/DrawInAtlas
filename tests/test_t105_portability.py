"""T-105 fail-closed portable-export evidence and Windows strict-FP guards."""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/benchmarks"))

from build_drawing_app import stage  # noqa: E402
import t105_release_residency as release  # noqa: E402
import t105_windows_msvc as msvc  # noqa: E402


def fixture() -> dict:
    """Create an intentionally incomplete, internally consistent Linux report."""
    source_sha = {str(p.relative_to(ROOT)): release.digest(p)
                  for p in (release.SOURCE, release.RELEASE_GATE)}
    rows = [
        {"returncode": 0, "sample_count": 10,
         "elapsed_ms": 2000.0 + i, "cpu_user_ms": 900.0 + i,
         "cpu_system_ms": 150.0 + i, "rss_peak_kib": 95000 + i,
         "hwm_peak_kib": 98000 + i,
         "recognized_godot_shutdown_leaks": 4}
        for i in range(3)
    ]
    keys = ("elapsed_ms", "cpu_user_ms", "cpu_system_ms", "rss_peak_kib", "hwm_peak_kib")
    return {"schema": 1, "ticket": "T-105", "platform": "linux-x86_64",
            "source_sha256": source_sha, "stage": {"file_count": 37, "font_license_sha256": "c" * 64},
            "release": {"platform": "linux", "native_extension_shipped": False,
                        "inspection": "structure_only",
                        "binary": {"name": "Drawing.x86_64", "size": 4096,
                                   "sha256": "a" * 64},
                        "pack": {"name": "Drawing.pck", "size": 96,
                                 "sha256": "b" * 64}},
            "engine": "4.8.beta3.official.c51ff06e8", "frames": 120,
            "runs": rows,
            "summary": {key: {"p50": release.nearest([float(row[key]) for row in rows], 0.5),
                              "p95": release.nearest([float(row[key]) for row in rows], 0.95),
                              "max": max(float(row[key]) for row in rows)}
                        for key in keys},
            "windows": {"status": "not_tested"},
            "vram": {"status": "not_measured"}, "complete": False,
            "limitations": list(release.LIMITATIONS)}


class T105EvidenceTests(unittest.TestCase):
    def test_valid_linux_report_is_explicitly_incomplete(self) -> None:
        record = fixture()
        release.validate(record)
        self.assertFalse(record["complete"])
        self.assertEqual(record["windows"]["status"], "not_tested")
        self.assertEqual(record["vram"]["status"], "not_measured")

    def test_reject_forged_windows_gpu_or_completion(self) -> None:
        for key, value in (("complete", True), ("windows", {"status": "passed"}),
                           ("vram", {"status": "measured"}),
                           ("platform", "windows-x86_64")):
            with self.subTest(key=key):
                record = fixture()
                record[key] = value
                with self.assertRaises(ValueError):
                    release.validate(record)

    def test_reject_missing_runs_or_changed_cpu_memory_statistics(self) -> None:
        changes = (
            lambda r: r["runs"].pop(),
            lambda r: r["runs"][0].update(returncode=1),
            lambda r: r["runs"][0].update(sample_count=0),
            lambda r: r["runs"][0].update(rss_peak_kib=999999),
            lambda r: r["runs"][1].update(hwm_peak_kib=1),
            lambda r: r["summary"]["elapsed_ms"].update(p95=0),
            lambda r: r["summary"]["hwm_peak_kib"].update(p50=123),
            lambda r: r["release"]["binary"].update(sha256="0" * 31),
            lambda r: r["release"].update(native_extension_shipped=True),
            lambda r: r["stage"].pop("font_license_sha256"),
            lambda r: r["release"]["binary"].update(name="fake.x86_64"),
            lambda r: r["source_sha256"].update({"bad": "123"}),
            lambda r: r["runs"][0].update(fabricated_gpu_vram_mib=12),
        )
        for mutate in changes:
            record = fixture()
            mutate(record)
            with self.assertRaises(ValueError):
                release.validate(record)

    def test_nearest_rank_rejects_invalid_samples(self) -> None:
        self.assertEqual(release.nearest([9, 3, 5], 0.5), 5)
        self.assertEqual(release.nearest([9, 3, 5], 0.95), 9)
        for values in ([], [-1, 1], [1, float("nan")]):
            with self.subTest(values=values), self.assertRaises(ValueError):
                release.nearest(values, 0.95)

    def test_on_demand_workflow_preserves_both_platforms_and_fast_inventory(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-native-t105-portability.yml").read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("runs-on: ubuntu-24.04", workflow)
        self.assertIn("runs-on: windows-2022", workflow)
        self.assertIn("include-templates: true", workflow)
        self.assertIn("t105_windows_msvc.py", workflow)
        self.assertIn("t105_windows_release.py", workflow)
        self.assertIn("--without-native", workflow)
        self.assertEqual(workflow.count("if: always()"), 2)
        import re
        required = (ROOT / ".github/workflows/godot-check.yml").read_text()
        self.assertEqual(len(re.findall(r"^\s*id: ci_[^\s]+", required, re.M)), 46)

    def test_portable_stage_excludes_native_even_when_built(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "without-native"
            result = stage(target, without_native=True)
            self.assertEqual(result, target)
            self.assertFalse((target / "addons/drawing/native").exists())
            self.assertTrue((target / "addons/drawing/fonts/OFL-1.1.txt").exists())
            self.assertEqual((target / "project.godot").is_file(), True)

    def test_windows_adapter_refuses_unpinned_cpp_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "unexpected.cpp"
            source.write_text(msvc.SCALAR_SOURCE.read_text() + "\n// changed\n")
            with self.assertRaisesRegex(ValueError, "pinned cross-OS"):
                msvc.portable_source(source)

    def test_windows_quad_shim_exports_pinned_symbol_without_modifying_source(self) -> None:
        body = msvc.portable_source(msvc.QUAD_SOURCE)
        self.assertIn('extern "C" __declspec(dllexport) int32_t t068_quad_scope_mask(', body)
        self.assertNotIn('__declspec(dllexport)', msvc.QUAD_SOURCE.read_text())

    def test_msvc_runner_rejects_linux_host(self) -> None:
        if sys.platform == "win32":
            self.skipTest("requires non-Windows negative control")
        with self.assertRaisesRegex(RuntimeError, "Real Windows x64"):
            msvc.run()
        self.assertEqual(msvc.percentiles([20.0, 10.0, 30.0]),
                         {"p50": 20.0, "p95": 30.0, "max": 30.0})

    def test_msvc_fast_math_macro_and_gcc_fast_math_both_fail_before_compilation(self) -> None:
        compiler = shutil.which("g++")
        if compiler is None:
            self.skipTest("g++ unavailable for source guard negative control")
        for source in (msvc.SCALAR_SOURCE, msvc.QUAD_SOURCE):
            with tempfile.TemporaryDirectory() as temporary:
                raw = subprocess.run([compiler, "-std=c++17", "-D_M_FP_FAST=1",
                                      "-c", str(source), "-o", str(Path(temporary) / "red.o")],
                                     text=True, capture_output=True, timeout=45, check=False)
                self.assertEqual(raw.returncode, 0, raw.stderr)
            for bad_flags in (("-D_M_FP_FAST=1",), ("-Ofast",)):
                with self.subTest(source=source.name, bad_flags=bad_flags):
                    with tempfile.TemporaryDirectory() as temp:
                        adapted = Path(temp) / "portable.cpp"
                        adapted.write_text(msvc.portable_source(source), encoding="utf-8")
                        self.assertIn("_M_FP_FAST", adapted.read_text(encoding="utf-8"))
                        result = subprocess.run(
                            [compiler, "-std=c++17", *bad_flags, "-c", str(adapted),
                             "-o", str(Path(temp) / "unsafe.o")],
                            text=True, capture_output=True, timeout=45, check=False)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("requires strict floating-point semantics", result.stderr)
                        self.assertFalse((Path(temp) / "unsafe.o").exists())


if __name__ == "__main__":
    unittest.main()
