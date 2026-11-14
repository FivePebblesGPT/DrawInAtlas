# T-122 — historical fast-CI replay isolation, 2026-11-15

## Source and pre-change failure

- Starting sprint branch: `sprint/2026-11-14`, HEAD
  `61c6f689974a848f8a7cc4040c98be418518b156`.
- Actual GitHub Actions fast-desktop run
  [43639949024](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/43639949024),
  SHA `61c6f689`, **failed 45/46**. The one failed check ID was
  `ci_21_verify_t_073_approved_inventory_versus_proposed_workspace_ux`.
- `test_t107_retained_raw_ci_evidence_and_all_23_owner_actions` raised
  `AuditError`, listing a changed workflow digest, exploratory (unattested)
  provenance, and four scripts whose historical bytes differed from current
  T-093, nested Objects, Atlas composition and Asset Browser CI commands.
  Exploratory provenance was previously an explicitly permitted condition;
  pairing it with current-source drift incorrectly turned the historical
  capture into a failure. The source drift itself was not a test regression.
- An independent original-auditor negative control (loaded from the starting
  commit without changing the candidate file) reproduced those same errors.

## Recovery and invariant

The original 46 archived `scripts/*.sh` files were reinserted into the starting
commit's workflow step bodies without changing step names, check IDs or YAML
structure. The reconstructed UTF-8 `workflow.yml` hashes to **exactly**
`835f044bf57224999dea386959bbc14b4f60e3d5b4a4bf798db8ff2da79a411f`,
which equals `report.json.workflow_sha256`. Repeating that reconstruction using
earlier branch/PR workflow revisions yielded the same exact hash. This
establishes that the captured source is byte-for-byte the historical workflow,
not merely a guessed command inventory.

`replay_inventory` now audits against this pinned retained source, rather than
treating all later edits to the live workflow as mutations of historical
replay data. It still validates SHA-256 and literal bytes of all 46 archived
scripts and logs, complete ordered successful outcomes, exact summary and
beta3 version, explicit **unattested** classification, and the *current*
required-check ID inventory. `copy_replay` retains the workflow too. No source
script, log, report, owner-finding entry, current workflow step, or status has
been weakened or rewritten.

## Verification

Run from the source root with Python 3:

```sh
python3 tools/t107_evidence_audit.py \
  --replay docs/evidence/T-107-2026-11-12-replay-capture \
  --remote-head 79b8959e9eac01b3bb10a144a46407acc6901aed \
  --local-head 0ecfc1fa996b4c5fcfee04b8dfae793bc5b4043a \
  --verify docs/evidence/T-107-2026-11-12-readiness.json
python3 -m unittest discover -s tests -p test_t107_evidence_audit.py -v
python3 -m unittest discover -s tests -p test_t094_owner_matrix.py -v
python3 -m unittest discover -s tests -p test_t094_ci_replay.py -v
python3 -m unittest discover -s tests -p test_godot_ci_fail_late.py -v
python3 -m unittest discover -s tests -p test_godot_ci_order.py -v
python3 tools/validate_ticket_store.py
```

Initial local results before the final commit: audit **exit 0** with the
existing unchanged 46-check/23-action ledger; T-107 **10/10**, T-094 owner
matrix **4/4**, T-094 replay **14/14**, CI fail-late **8/8**, CI ordering
**1/1**, hosted evidence **9/9**, owner evidence **16/16** (**62** focused and adjacent unit tests total). The new regression cases include missing/tampered workflow bytes,
modified script contents, and an unrelated new current-workflow comment.
Existing negative controls reject missing or forged logs, changed report
records, duplicate/missing owner rows and false owner approvals. There are no
Godot runtime edits in this ticket; these are Python CI/audit contracts.

## Outstanding gates

This is **not** a newly executed full 46/46 Godot suite, a hosted green run,
physical Linux/Windows acceptance, or a replacement for T-106/T-107's open
requirements. The prior hosted failure remains a real recorded failure until
an independently verified hosted run of the updated commit passes. T-106,
T-107 and all owner-review gates retain their existing states.
