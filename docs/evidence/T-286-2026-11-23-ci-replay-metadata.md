# T-286 — Local fast-CI replay step metadata integrity

**Date:** 2026-11-23. **Baseline:** `0b84ff73` (14 local commits after remote
main `bbae76c3`). **Scope:** `tools/replay_godot_ci.py` parser and new
`tests/test_t286_ci_replay_metadata.py`; no production Drawing/Atlas code.

## Fail-first

Command: `python3 -m unittest -v tests.test_t286_ci_replay_metadata`.
Before the guard, the test reported **4 tests / 8 subtest failures**. The
parser silently accepted `working-directory`, `timeout-minutes`, `env`,
`defaults`, duplicate `if` / `continue-on-error`, `strategy` and YAML
merge/complex-key constructs. Other existing guards caught the injected
alternate `shell`, duplicate `run` and duplicate check ID. The original
46-step workflow parsed successfully.

Full retained log: [fail-first](T-286-2026-11-23-ci-replay-metadata/fail-first.log).

## Fixed guard

The parser enumerates exact eight-space step metadata lines, rejects unknown
or repeated keys, and checks their exact supported values before extracting
Bash. The allowlist is `id`, `if: ${{ !cancelled() }}`,
`continue-on-error: true`, optional `shell: bash`, and one `run`. Blank lines
and YAML comments remain supported; unchanged CI workflow still parses all
46 checks. This protects **local audit fidelity**, not presentation/UI.

Command with Git LFS filter overrides to avoid the *missing executable* in
this isolated runtime (no LFS files changed):

```bash
GIT_CONFIG_COUNT=3 \
GIT_CONFIG_KEY_0=filter.lfs.process GIT_CONFIG_VALUE_0='' \
GIT_CONFIG_KEY_1=filter.lfs.smudge GIT_CONFIG_VALUE_1='' \
GIT_CONFIG_KEY_2=filter.lfs.required GIT_CONFIG_VALUE_2=false \
python3 -m unittest -v \
  tests.test_godot_ci_fail_late tests.test_godot_ci_order \
  tests.test_t094_owner_matrix tests.test_t094_owner_evidence \
  tests.test_t094_ci_replay tests.test_t286_ci_replay_metadata
```

Result: **47/47 tests pass**, including 4 new metadata tests and 43 adjacent
contracts. `python3 -m compileall -q tools/replay_godot_ci.py
tests/test_t286_ci_replay_metadata.py` succeeds. Ticket validation after
adding T-286: 286 canonical tickets and review gates valid.

Full retained log: [all 47 contracts](T-286-2026-11-23-ci-replay-metadata/neighbors.log).

## Remaining gates

The fast-desktop hosted workflow, native raster benchmarks, official package
release, and T-250 owner UX approval are **not** proven by this contract
repair. T-094 and T-106 remain In Progress. This exercise did not modify or
approve manual-review frontmatter.
