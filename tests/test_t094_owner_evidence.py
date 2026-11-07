"""T-094 physical evidence schema: no synthetic or partial result becomes approval."""

from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from drawing_owner_evidence import (  # noqa: E402
    blank_manifest, check_cohort, findings, percentile_ms, timing_summary, validate,
)


class OwnerPhysicalEvidenceTests(unittest.TestCase):
    def test_templates_remain_not_run_and_match_every_current_finding(self) -> None:
        for os_name in ("Linux", "Windows"):
            with self.subTest(os=os_name):
                manifest = blank_manifest(os_name)
                problems, passed, failed = validate(manifest, Path("/tmp"))
                self.assertEqual(problems, [])
                self.assertEqual((passed, failed), (0, 0))
                self.assertEqual({r["finding"] for r in manifest["results"]}, set(range(1, 24)))
                self.assertEqual({r["tickets"] for r in manifest["results"]}, set(findings().values()))
                self.assertTrue(all(r["status"] == "NOT RUN" for r in manifest["results"]))

    @staticmethod
    def _observed_report(directory: Path) -> dict:
        manifest = blank_manifest("Linux")
        manifest["environment"].update({
            "physical_display": True,
            "commit": "a" * 40,
            "godot_version": "4.8.beta2.official.cafc17a19",
            "gpu": "hardware test card",
            "renderer": "Vulkan 1.3",
            "pointer": "USB optical mouse",
            "display_refresh_hz": 60,
            "window_px": "1280x720",
            "ui_scale": 1.5,
            "timestamp": "2026-11-06T07:00:00+01:00",
        })
        artifact = directory / "frame.png"
        artifact.write_bytes(b"test binary pixels; not actual owner evidence")
        entry = manifest["results"][0]
        entry.update({
            "status": "PASS",
            "observed": "The first uncommitted brush pixels were visually present.",
            "artifacts": [{"path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}],
            "zooms_percent": [25, 50, 100],
            "timings_ms": {
                str(zoom): {phase: [10, 12, 13, 15, 19] for phase in (
                    "down_to_preview_ms", "motion_to_preview_ms", "release_to_commit_ms")}
                for zoom in (25, 50, 100)
            },
        })
        return manifest

    def test_valid_annotated_row_is_not_equivalent_to_complete_owner_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self._observed_report(root)
            self.assertEqual(validate(manifest, root), ([], 1, 0))
            path = root / "results.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            cli = [sys.executable, "tools/drawing_owner_evidence.py", "verify", str(path)]
            normal = subprocess.run(cli, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(normal.returncode, 0, normal.stderr)
            self.assertIn("NOT RUN 22/23", normal.stdout)
            strict = subprocess.run(cli + ["--require-complete"], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(strict.returncode, 1)
            self.assertIn("Physical evidence incomplete", strict.stderr)

    def test_rejects_file_integrity_and_path_escape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = self._observed_report(root)
            for path, digest in (("frame.png", "0" * 64), ("../outside.png", "0" * 64),
                                 ("missing.png", "0" * 64), ("/tmp/outside.png", "0" * 64)):
                with self.subTest(path=path):
                    manifest = copy.deepcopy(valid)
                    manifest["results"][0]["artifacts"] = [{"path": path, "sha256": digest}]
                    self.assertTrue(validate(manifest, root)[0])
            (root / "symlink.png").symlink_to(root / "frame.png")
            linked = copy.deepcopy(valid)
            linked["results"][0]["artifacts"][0]["path"] = "symlink.png"
            self.assertTrue(validate(linked, root)[0])

    def test_rejects_unsupported_hardware_missing_metadata_and_broken_timings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = self._observed_report(root)
            for path, value in (("gpu", "llvmpipe"), ("physical_display", False),
                                ("commit", "bad"), ("timestamp", "2026-11-06"),
                                ("renderer", "SwiftShader"), ("display_refresh_hz", 0)):
                with self.subTest(path=path):
                    candidate = copy.deepcopy(valid)
                    candidate["environment"][path] = value
                    self.assertTrue(validate(candidate, root)[0])
            candidate = copy.deepcopy(valid)
            candidate["results"][0]["timings_ms"]["25"]["down_to_preview_ms"] = [1, 2]
            self.assertTrue(validate(candidate, root)[0])
            candidate = copy.deepcopy(valid)
            candidate["results"][0]["zooms_percent"] = [50, 100]
            self.assertTrue(validate(candidate, root)[0])

    def test_timed_pass_requires_unpooled_samples_at_every_recorded_zoom(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = self._observed_report(root)
            self.assertEqual(validate(valid, root), ([], 1, 0))
            for mutation in (
                # This formerly returned a green report despite only 15 pooled samples.
                lambda row: row.update(timings_ms={phase: [1, 2, 3, 4, 5] for phase in (
                    "down_to_preview_ms", "motion_to_preview_ms", "release_to_commit_ms")}),
                lambda row: row["timings_ms"].pop("25"),
                lambda row: row["timings_ms"].update({"200": row["timings_ms"]["25"]}),
                lambda row: row["timings_ms"]["50"].pop("motion_to_preview_ms"),
                lambda row: row["timings_ms"]["100"]["release_to_commit_ms"].append(float("nan")),
                lambda row: row["timings_ms"]["100"]["release_to_commit_ms"].append(10**1000),
                lambda row: row["timings_ms"]["25"]["down_to_preview_ms"].append(True),
                lambda row: row.update(zooms_percent=[25, 50, 50, 100]),
                lambda row: row.update(zooms_percent=[25, 50, {"value": 100}]),
                lambda row: row.update(zooms_percent="25,50,100"),
            ):
                with self.subTest(mutation=mutation):
                    candidate = copy.deepcopy(valid)
                    mutation(candidate["results"][0])
                    problems, passed, failed = validate(candidate, root)
                    self.assertTrue(problems)
                    self.assertEqual((passed, failed), (1, 0), "Reported PASS is not accepted without a clean validator verdict")

    def test_summary_uses_independent_r7_percentiles_and_stable_zoom_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self._observed_report(root)
            samples = [100, 2, 3, 1, 4]  # Deliberately unordered with one outlier.
            report["results"][0]["zooms_percent"] = [100, 25, 50]
            report["results"][0]["timings_ms"]["25"]["down_to_preview_ms"] = samples
            self.assertEqual(validate(report, root), ([], 1, 0))
            self.assertEqual(percentile_ms(samples, 50), 3.0)
            self.assertAlmostEqual(percentile_ms(samples, 95), 80.8)
            lines = timing_summary(report)
            self.assertEqual(len(lines), 9)
            self.assertEqual(lines[0],
                             "Linux #01 25% down_to_preview_ms: n=5 p50=3.000 ms p95=80.800 ms")
            self.assertTrue(lines[3].startswith("Linux #01 50%"))
            self.assertTrue(lines[6].startswith("Linux #01 100%"))
            self.assertEqual(timing_summary(blank_manifest("Linux")), [])

    def test_cli_summary_requires_valid_evidence_and_does_not_forge_results(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = [sys.executable, "tools/drawing_owner_evidence.py", "verify", "--timing-summary"]
            report = self._observed_report(root)
            path = root / "linux.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            success = subprocess.run(cli + [str(path)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(success.returncode, 0, success.stderr)
            self.assertEqual(success.stdout.count(" p50="), 9)
            self.assertIn("Linux #01 25% down_to_preview_ms:", success.stdout)
            self.assertIn("owner approval is never inferred", success.stdout)
            self.assertNotIn("Windows #", success.stdout)
            # FAIL and NOT RUN rows are real outcomes, not inferred timing PASSes.
            report["results"][0]["status"] = "FAIL"
            path.write_text(json.dumps(report), encoding="utf-8")
            failed_observation = subprocess.run(cli + [str(path)], cwd=ROOT,
                                                capture_output=True, text=True)
            self.assertEqual(failed_observation.returncode, 0, failed_observation.stderr)
            self.assertIn("No validated PASS timing observations", failed_observation.stdout)
            self.assertNotIn(" p50=", failed_observation.stdout)
            # An invalid PASS cannot print an apparently trustworthy statistic.
            report["results"][0]["status"] = "PASS"
            report["results"][0]["timings_ms"]["25"]["motion_to_preview_ms"] = [5]
            path.write_text(json.dumps(report), encoding="utf-8")
            invalid = subprocess.run(cli + [str(path)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(invalid.returncode, 2)
            self.assertIn("five finite nonnegative", invalid.stderr)
            self.assertNotIn(" p50=", invalid.stdout)
            # Untested templates print an explicit absence, not made-up timings.
            path.write_text(json.dumps(blank_manifest("Linux")), encoding="utf-8")
            unrun = subprocess.run(cli + [str(path)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(unrun.returncode, 0, unrun.stderr)
            self.assertIn("No validated PASS timing observations", unrun.stdout)

    def test_timing_summary_reports_both_findings_and_both_operating_systems(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = []
            for os_name in ("Linux", "Windows"):
                os_dir = root / os_name
                os_dir.mkdir()
                report = self._observed_report(os_dir)
                report["environment"]["os"] = os_name
                source = report["results"][0]
                fifteenth = report["results"][14]
                fifteenth.update({key: copy.deepcopy(value) for key, value in source.items()
                                  if key not in ("finding", "tickets")})
                path = os_dir / "manifest.json"
                path.write_text(json.dumps(report), encoding="utf-8")
                paths.append(str(path))
            command = [sys.executable, "tools/drawing_owner_evidence.py", "verify",
                       "--timing-summary", "--expected-commit", "a" * 40, *paths]
            valid = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(valid.returncode, 0, valid.stderr)
            self.assertEqual(valid.stdout.count(" p50="), 36)
            self.assertIn("Windows #15 100% release_to_commit_ms:", valid.stdout)
            self.assertIn("Linux #01 25% down_to_preview_ms:", valid.stdout)
            # Complete-status rejection happens *before* performance statistics.
            incomplete = subprocess.run(command[:4] + ["--require-complete"] + command[4:],
                                        cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(incomplete.returncode, 1)
            self.assertIn("Physical evidence incomplete", incomplete.stderr)
            self.assertNotIn(" p50=", incomplete.stdout)

    def test_mixed_revision_summary_fails_before_printing_statistics(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = []
            for os_name in ("Linux", "Windows"):
                os_dir = root / os_name
                os_dir.mkdir()
                report = self._observed_report(os_dir)
                report["environment"]["os"] = os_name
                report["environment"]["commit"] = "a" * 40 if os_name == "Linux" else "b" * 40
                path = os_dir / "manifest.json"
                path.write_text(json.dumps(report), encoding="utf-8")
                paths.append(str(path))
            command = [sys.executable, "tools/drawing_owner_evidence.py", "verify",
                       "--timing-summary", *paths]
            invalid = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(invalid.returncode, 2)
            self.assertIn("Mixed Git commit", invalid.stderr)
            self.assertNotIn(" p50=", invalid.stdout)

    def test_untested_rows_cannot_carry_stale_zoom_claims(self) -> None:
        report = blank_manifest("Linux")
        report["results"][0]["zooms_percent"] = [25, 50, 100]
        problems, _, _ = validate(report, Path("/tmp"))
        self.assertTrue(any("NOT RUN cannot contain" in p for p in problems))

    def test_both_timed_findings_require_independent_zoom_timings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self._observed_report(root)
            first = report["results"][0]
            fifteenth = report["results"][14]
            fifteenth.update({key: copy.deepcopy(value) for key, value in first.items()
                              if key not in ("finding", "tickets")})
            self.assertEqual(validate(report, root), ([], 2, 0))
            fifteenth["timings_ms"].pop("100")
            self.assertTrue(any("#15:" in p for p in validate(report, root)[0]))

    def test_never_silently_drops_rows_or_changes_the_runbook_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = self._observed_report(root)
            for mutation in (lambda r: r.pop(),
                             lambda r: r.append(copy.deepcopy(r[0])),
                             lambda r: r[1].update({"tickets": "T-000"})):
                with self.subTest(mutation=mutation):
                    candidate = copy.deepcopy(valid)
                    mutation(candidate["results"])
                    self.assertTrue(validate(candidate, root)[0])

    def test_physical_cohort_must_represent_one_revision_and_godot_build(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            linux = self._observed_report(root)
            windows = copy.deepcopy(linux)
            windows["environment"]["os"] = "Windows"
            manifests = {"Linux": linux, "Windows": windows}
            self.assertEqual(check_cohort(manifests), [])
            self.assertEqual(check_cohort(manifests, expected_commit="a" * 40), [])
            self.assertTrue(check_cohort(manifests, expected_commit="b" * 40))
            self.assertTrue(check_cohort(manifests, expected_commit="not-a-full-sha"))

            windows["environment"]["commit"] = "b" * 40
            self.assertTrue(any("Mixed Git commit" in item for item in check_cohort(manifests)))
            windows["environment"]["commit"] = "a" * 40
            windows["environment"]["godot_version"] = "4.8.beta2.official.other-build"
            self.assertTrue(any("Mixed Godot build" in item for item in check_cohort(manifests)))

    def test_partial_cohort_accepts_unrun_os_without_faking_comparability(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            linux = self._observed_report(root)
            manifests = {"Linux": linux, "Windows": blank_manifest("Windows")}
            self.assertEqual(check_cohort(manifests, expected_commit="a" * 40), [])
            self.assertTrue(check_cohort(manifests, expected_commit="b" * 40))
            self.assertEqual(check_cohort({"Windows": blank_manifest("Windows")}), [])

    def test_complete_cli_rejects_mixed_commits_and_revisions_other_than_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = [sys.executable, "tools/drawing_owner_evidence.py", "verify"]
            paths = []
            for os_name in ("Linux", "Windows"):
                os_dir = root / os_name
                os_dir.mkdir()
                report = self._observed_report(os_dir)
                report["environment"]["os"] = os_name
                # Synthetic data intentionally tests *schema* only, not the
                # authenticity of actual hardware or owner approval.
                reference = copy.deepcopy(report["results"][0])
                for entry in report["results"]:
                    entry.update({key: copy.deepcopy(value) for key, value in reference.items()
                                  if key not in ("finding", "tickets")})
                self.assertEqual(validate(report, os_dir), ([], 23, 0))
                path = os_dir / "results.json"
                path.write_text(json.dumps(report), encoding="utf-8")
                paths.append(path)

            command = cli + [str(p) for p in paths] + ["--require-complete"]
            accepted = subprocess.run(command + ["--expected-commit", "a" * 40], cwd=ROOT,
                                      capture_output=True, text=True)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertIn("owner approval is never inferred", accepted.stdout)

            for expected in ("b" * 40, "short-sha"):
                with self.subTest(expected=expected):
                    denied = subprocess.run(command + ["--expected-commit", expected],
                                            cwd=ROOT, capture_output=True, text=True)
                    self.assertEqual(denied.returncode, 2)
                    self.assertIn("cohort rejected", denied.stderr)

            windows = json.loads(paths[1].read_text(encoding="utf-8"))
            windows["environment"]["commit"] = "b" * 40
            paths[1].write_text(json.dumps(windows), encoding="utf-8")
            denied = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(denied.returncode, 2)
            self.assertIn("Mixed Git commit", denied.stderr)
            self.assertNotIn("PASS 23/23", denied.stdout, "Do not print a passing summary before cohort checks")
            windows["environment"]["commit"] = "a" * 40
            windows["environment"]["godot_version"] = "4.8.beta2.official.different"
            paths[1].write_text(json.dumps(windows), encoding="utf-8")
            denied = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(denied.returncode, 2)
            self.assertIn("Mixed Godot build", denied.stderr)

    def test_init_never_overwrites_and_incomplete_two_os_is_not_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = [sys.executable, "tools/drawing_owner_evidence.py"]
            paths = []
            for os_name in ("Linux", "Windows"):
                path = root / f"{os_name}.json"
                create = subprocess.run(cli + ["init", "--os", os_name, "--output", str(path)],
                                        cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(create.returncode, 0, create.stderr)
                paths.append(str(path))
                second = subprocess.run(cli + ["init", "--os", os_name, "--output", str(path)],
                                        cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(second.returncode, 2)
            verify = subprocess.run(cli + ["verify", *paths], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(verify.returncode, 0)
            incomplete = subprocess.run(cli + ["verify", *paths, "--require-complete"],
                                        cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(incomplete.returncode, 1)


if __name__ == "__main__":
    unittest.main()
