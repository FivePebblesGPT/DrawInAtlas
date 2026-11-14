"""T-107 regression: complete local evidence cannot impersonate hosted or owner approval."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from t107_evidence_audit import (  # noqa: E402
    AuditError, _read_rows, audit, copy_replay, manual_gates, owner_actions,
    replay_inventory, runtime_inventory,
)

EXTERNAL = ROOT / "docs/evidence/T-107-2026-11-12-replay-capture"
REMOTE = "7" * 40
CANDIDATE = "8" * 40


class OwnerActionTests(unittest.TestCase):
    def test_every_finding_is_mapped_to_concrete_action_and_not_run(self) -> None:
        rows = owner_actions()
        self.assertEqual([x["finding"] for x in rows], list(range(1, 24)))
        for entry in rows:
            self.assertTrue(entry["tickets"])
            self.assertTrue(entry["physical_action"])
            self.assertTrue(entry["engineering_observation"])
            self.assertEqual(entry["physical_linux"], "NOT RUN")
            self.assertEqual(entry["physical_windows"], "NOT RUN")
            self.assertEqual(entry["owner_acceptance"], "NOT GRANTED")
        self.assertEqual(rows[21]["finding_state"], "OWNER PASS / REGRESSION")
        self.assertEqual(rows[22]["finding_state"], "MODEL EXPECTED / UI PENDING")
        self.assertEqual({x["ticket"] for x in manual_gates()},
                         {"T-056", "T-059", "T-065", "T-083", "T-095", "T-096"})

    def test_duplicate_and_missing_owner_findings_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "synthetic.md"
            original = (ROOT / "docs/DRAWING_OWNER_ACCEPTANCE_MATRIX.md").read_text()
            for mutated in (original + "\n" + next(x for x in original.splitlines()
                                                    if x.startswith("| 01 |")),
                            original.replace("| 01 |", "| XX |", 1)):
                path.write_text(mutated, encoding="utf-8")
                with self.assertRaises(AuditError):
                    _read_rows(path)

    def test_standalone_and_atlas_raw_logs_have_strict_exact_markers(self) -> None:
        result = runtime_inventory()
        self.assertEqual(len(result["checks"]), 9)
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp)
            for source in (ROOT / "docs/evidence/T-107-2026-11-12-runtime").glob("*.log"):
                (dest / source.name).write_bytes(source.read_bytes())
            broken = dest / "atlas-composition.log"
            broken.write_bytes(broken.read_bytes().replace(b"T055_COMPOSITION_PASSED",
                                                           b"T055_COMPOSITION_FAILED"))
            with self.assertRaises(AuditError):
                runtime_inventory(dest)

    def test_bad_manual_gate_cannot_be_silently_accepted(self) -> None:
        with patch("t107_evidence_audit.MANUAL_GATES", ("T-097",)):
            with self.assertRaises(AuditError):
                manual_gates()


class CapturedReplayTests(unittest.TestCase):
    def test_integrity_of_real_46_step_replay_with_truthful_provenance(self) -> None:
        report = audit(EXTERNAL, remote_head=REMOTE, local_head=CANDIDATE)
        self.assertEqual(report["required_fast_ci"]["checks_passed"], 46)
        self.assertEqual(report["required_fast_ci"]["kind"], "local-exploratory")
        self.assertTrue(report["required_fast_ci"]["not_github_hosted"])
        self.assertEqual(report["hosted_ci"]["status"], "NOT VERIFIED FOR CANDIDATE")
        self.assertEqual(len(report["owner_findings"]), 23)

    def test_candidate_equal_to_remote_does_not_fabricate_hosted_success(self) -> None:
        result = audit(EXTERNAL, remote_head=REMOTE, local_head=REMOTE)
        self.assertEqual(result["hosted_ci"]["status"], "NOT VERIFIED FOR CANDIDATE")
        with self.assertRaises(AuditError):
            audit(EXTERNAL, remote_head="not-a-hash", local_head=CANDIDATE)

    def test_missing_log_wrong_hash_and_dropped_step_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "replay"
            copy_replay(EXTERNAL, target)
            logs = list(sorted((target / "logs").glob("*.log")))
            self.assertEqual(len(logs), 46)
            victim = logs[0]
            original = victim.read_bytes()
            victim.write_bytes(original + b"\nforged post-success line\n")
            with self.assertRaisesRegex(AuditError, "SHA-256 mismatch"):
                replay_inventory(target)
            victim.write_bytes(original)
            victim.unlink()
            with self.assertRaisesRegex(AuditError, "Missing"):
                replay_inventory(target)
            victim.write_bytes(original)
            report_path = target / "report.json"
            source = json.loads(report_path.read_text())
            source["checks"] = source["checks"][:-1]
            report_path.write_text(json.dumps(source))
            with self.assertRaises(AuditError):
                replay_inventory(target)

    def test_copied_capture_is_self_contained_and_auditable(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / "replay"
            copy_replay(EXTERNAL, dest)
            self.assertEqual(replay_inventory(dest)["checks_total"], 46)
            with self.assertRaises(AuditError):
                copy_replay(EXTERNAL, dest)


if __name__ == "__main__":
    unittest.main()
