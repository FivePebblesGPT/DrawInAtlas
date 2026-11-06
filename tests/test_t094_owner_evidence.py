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
from drawing_owner_evidence import blank_manifest, findings, validate  # noqa: E402


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
            "timings_ms": {phase: [10, 12, 13, 15, 19] for phase in (
                "down_to_preview_ms", "motion_to_preview_ms", "release_to_commit_ms")},
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
            candidate["results"][0]["timings_ms"]["down_to_preview_ms"] = [1, 2]
            self.assertTrue(validate(candidate, root)[0])
            candidate = copy.deepcopy(valid)
            candidate["results"][0]["zooms_percent"] = [50, 100]
            self.assertTrue(validate(candidate, root)[0])

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
