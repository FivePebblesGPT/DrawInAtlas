# T-107 — complete CI-log inventory and owner-finding evidence readiness

**Date:** 2026-11-12. **Status:** engineering checkpoint only; **T-107 remains In Progress**.
**Exact earlier local source commit:** `0ecfc1fa996b4c5fcfee04b8dfae793bc5b4043a` (T-106; replay itself was *pre-commit* exploratory).
**Last observed remote PR #17 head:** `79b8959e9eac01b3bb10a144a46407acc6901aed` (T-098), open and unmerged. The eight later local commits were not pushed.
**Pinned engine:** `4.8.beta3.official.c51ff06e8`, Linux x86-64, headless Dummy/software test environment. No physical GPU, Windows or owner input-to-photon result is claimed.

## Canonical machine-checkable evidence

- [`T-107-2026-11-12-readiness.json`](T-107-2026-11-12-readiness.json) has **46 named check IDs** with original shell script SHA-256, unmodified raw-log SHA-256/byte length, exit codes and outcomes; **23 numbered owner findings**, their canonical ticket mappings, physical action, expected behavior, existing engineering evidence and explicit Linux/Windows `NOT RUN` states; and **six** unapproved manual gates.
- [`T-107-2026-11-12-replay-capture/`](T-107-2026-11-12-replay-capture/) retains the actual 46 shell scripts, 46 raw logs, `report.json` and `summary.md` from T-106's corrected local replay. Its checked-in workflow scripts and all 46 raw-log digests are verified by `tools/verify_godot_ci_replay.py` through `tools/t107_evidence_audit.py`. All 46 recorded steps exited zero, and all recorded success outcomes are consistent. **Provenance remains `local-exploratory`, `candidate_commit=null`, `working_tree_clean=false`.** This archive does **not** prove the post-T-106/T-107 source passed remotely.
- [`T-107-2026-11-12-runtime/`](T-107-2026-11-12-runtime/) retains a separate fresh isolated Drawing build/import, 42-check standalone `.drawing` Save/Open, 89-check Atlas canonical composition, and 86-check Atlas campaign Save/Open, plus exact-marker verification outputs. The same replay archive's `ci_07_verify_t_053_standalone_linux_release_package.log` records a real Linux ELF/PCK export and release gate under the earlier source. Post-test known Godot teardown leak lines remain in raw logs.
- [`DRAWING_OWNER_ACCEPTANCE_MATRIX.md`](../DRAWING_OWNER_ACCEPTANCE_MATRIX.md) is the authoritative interactive owner runbook. The machine ledger rechecks its tickets against all 23 rows in [`DRAWING_USABILITY_REVIEW_2026-11-05.md`](../DRAWING_USABILITY_REVIEW_2026-11-05.md) and existence of mapped ticket files. Findings **01–21** require physical re-review, **22** was an owner-reported *positive* Save/Open flow needing regression coverage, and **23** is an expected monotonic internal revision with pending UI re-review. Neither the 42-check standalone regression nor any software screen callback grants owner acceptance.

## Reproduce the audit and negative controls

From the exact source checkout with standard Python 3 and no third-party Python dependencies:

```sh
python3 tools/t107_evidence_audit.py \
  --replay docs/evidence/T-107-2026-11-12-replay-capture \
  --remote-head 79b8959e9eac01b3bb10a144a46407acc6901aed \
  --local-head 0ecfc1fa996b4c5fcfee04b8dfae793bc5b4043a \
  --verify docs/evidence/T-107-2026-11-12-readiness.json
python3 -m unittest discover -s tests -p test_t107_evidence_audit.py -v
python3 -m unittest discover -s tests -p test_t094_owner_matrix.py -v
python3 tools/validate_ticket_store.py
```

**Observed exits:** audit **0** (46/46 captured logs and 23/23 actions), T-107 **8/8, exit 0**, T-094 matrix **4/4, exit 0**, ticket validation **109 valid, exit 0**. Negative controls changed a raw-log SHA, deleted a required raw log, dropped a step, corrupted an Atlas success marker, changed a manual gate and duplicated/removed a finding; the auditor rejected each. A matching remote/local SHA with no hosted artifact is still reported `NOT VERIFIED FOR CANDIDATE`.

Separate pinned Godot runtime commands (all completed with process exit **0**):

```sh
G=/path/to/Godot_v4.8-beta3_linux.x86_64 # 4.8.beta3.official.c51ff06e8
python3 tools/build_drawing_app.py --output /tmp/t107-isolated-drawing
"$G" --headless --editor --path /tmp/t107-isolated-drawing --import --quit
"$G" --headless --path /tmp/t107-isolated-drawing --script res://tests/standalone_smoke.gd
"$G" --headless --path . --script res://tests/drawing_composition_smoke.gd
"$G" --headless --path . --script res://tests/campaign_bundle_smoke.gd
```

Strict marker log-check exits **0** for `DRAWING_STANDALONE_PASSED`, `T055_COMPOSITION_PASSED`, `ATLAS_BUNDLE_PASSED`. The standalone and Atlas-composition raw logs retain **four named post-exit resource leaks each**; their process exits are not claimed leak-free. The CI release-export replay log remains a historical local export test; a newly exported **Windows** build and a fresh commit-attributed standalone/Atlas release have not been demonstrated in this ticket.

## Hosted versus local evidence boundary

The last observed PR head `79b8959e` is **older** than the T-106 local repairs. Its previously observed hosted run at an older PR revision was **43/46**, not an eligible success. T-106's 46/46 local exploratory replay has a recorded null candidate commit; it is not GitHub Actions provenance. A genuine hosted result must be associated with the exact updated PR SHA (or its verified synthetic merge SHA), include all **46 pre-continue-on-error outcomes**, pass the existing `tools/export_godot_ci_evidence.py --verify` identity/check validator, and retain/check source workflow and applicable raw logs. No hosted artifact for the updated candidate was available at this checkpoint. The audit has no API access, never invents hosted checks, and cannot certify CI merely because all local checks are green.

The owner must separately carry out the **23 matrix actions** on physical Linux and Windows, record screenshots/video and hashes, add input-phase timing for findings #01/#15 at 25/50/100%, then approve the appropriate gates explicitly. In particular the still-unapproved tickets **T-056, T-059, T-065, T-083, T-095 and T-096** are not changed by this artifact. Other incomplete engineering tickets also remain open; T-094 and T-106 stay In Progress.
