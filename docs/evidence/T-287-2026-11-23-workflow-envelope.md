# T-287 — Local replay workflow/job envelope fidelity

**Date:** 2026-11-23. **Baseline:** `ab37bb52` (15 local commits after
remote main `bbae76c3`). **Scope:** local replay's full-workflow source
contract; no native raster, Godot UI or release-package implementation change.

## Fail-first

`python3 -m unittest -v tests.test_t287_ci_workflow_envelope` before the
guard returned **3 tests, 14 failing negative subtests**. The old parser
silently accepted alternate runners; job `env`, `defaults`, `if`,
`timeout-minutes`, `container` or matrix; root `env`, `defaults`, `permissions`
or `concurrency`; modified triggers/event branches; duplicate runner; and an
unrelated second job. All mutations preserve the original check scripts,
illustrating why an unchanged 46-command inventory alone was insufficient.

[Raw pre-fix log](T-287-2026-11-23-workflow-envelope/fail-first.log).

## Corrected contract

`extract_checks` now validates a deliberately narrow workflow envelope
before parsing check steps: nonempty name, push+pull-request triggers,
`jobs.smoke-and-desktop.runs-on: ubuntu-latest`, and one `steps` sequence.
All noncomment metadata with indentation less than six spaces is considered,
not just canonical 0/2/4-space lines. Any additional or changed field is
rejected. A renamed friendly workflow label, comments and synthetic
step-only test snippets remain allowed.

`python3 -m unittest -v tests.test_t287_ci_workflow_envelope` returns
**3/3 pass**. [Raw log](T-287-2026-11-23-workflow-envelope/guard.log).

## Neighboring and static validation

Run with process-local Git LFS filter overrides because this container lacks
`git-lfs`; no tracked LFS content changed:

```bash
GIT_CONFIG_COUNT=3 \
GIT_CONFIG_KEY_0=filter.lfs.process GIT_CONFIG_VALUE_0='' \
GIT_CONFIG_KEY_1=filter.lfs.smudge GIT_CONFIG_VALUE_1='' \
GIT_CONFIG_KEY_2=filter.lfs.required GIT_CONFIG_VALUE_2=false \
python3 -m unittest -v \
  tests.test_godot_ci_fail_late tests.test_godot_ci_order \
  tests.test_t094_owner_matrix tests.test_t094_owner_evidence \
  tests.test_t094_ci_replay tests.test_t286_ci_replay_metadata \
  tests.test_t287_ci_workflow_envelope
```

**50/50 passed**, including all existing replay verifier, fail-late and owner
matrix source contracts; existing workflow still supplies 46 CI checks.
[Neighbor log](T-287-2026-11-23-workflow-envelope/neighbors.log).

`ruff check tools/replay_godot_ci.py tests/test_t287_ci_workflow_envelope.py`,
`ty check tools/replay_godot_ci.py`, `python3 tests/check_explicit_types.py`,
`python3 tools/validate_ticket_store.py` and Python bytecode compile all pass.

## Validation boundary

This is local source fidelity, not a replay of GitHub's setup/checkout/artifact
steps or their environment effects, and not provenance for a hosted beta4 run.
It adds no UX evidence and never sets `manual_review_approved`. Full CI,
portable releases and owner decisions remain separate pending gates.
