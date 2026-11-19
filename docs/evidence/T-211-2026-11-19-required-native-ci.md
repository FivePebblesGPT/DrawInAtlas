# T-211 — Replace un-runnable T-095 CI stub with required-native test contracts

**Date:** 2026-11-19. **Scope:** CI/workflow scripts, retired test files, and
one strict success-marker addition to an existing test. No native/GDScript
production paint, tile, history or performance change.

## Fail-first reproduction

From the current PR #21 source on the pinned bundled Godot
`4.8.beta3.official.c51ff06e8`, with the real `DrawingNativeBrush` and
`DrawingNativeTiles` already staged:

| Historical CI consumer | Process exit | Failure |
| --- | ---: | --- |
| `hokusai_bulk_delta_smoke.gd` | **1** | Missing `t147_scripted_session_bridge.gd` preload at line 2 |
| `t095_tile_shift_smoke.gd` | **1** | Same missing bridge preload |
| `t095_tile_commit_smoke.gd` | **1** | Same missing bridge preload |

These scripts depend on the scripted fake native-producer interface deleted by
T-153. Their earlier **126/422/56 historical assertion counts are not
current native results** and are not transferred to the new tests. The five
new Python contracts initially fail 5/5 against the unmodified workflows and
script inventory (`contract-fail-first.log`). The real native pigment test
already passes 57/57 before changes, providing a direct actual-Rust replacement.

## Changes and coverage mapping

| Active CI path | Former test | Native-backed replacement and checked contracts |
| --- | --- | --- |
| Fast-desktop existing T-085 required step | scripted bulk-delta oracle (un-runnable) | `t095_native_pigment_atomic`: real Rust pigment rollback and exact same-object retry after rejected chunk source, signed origin, mask hole, preview, Undo/Redo; **57/57** |
| Same required step | no corresponding signed source check | T-158: native signed lazy tile bounds; **24/24** |
| Same required step | no corresponding native signed replay check | T-159: signed history replay and publication; **39/39** |
| Optional native workflow | scripted bulk/shift tests (both un-runnable) | Already separately runs actual Hokusai pigment + T-158/T-159 and T-148 full native tile contract; no duplicate stub runs |
| Optional native workflow | scripted tile commit (un-runnable) | `t148_document_tile_publication`: packed source, hidden-RGB, tile identity, publication/rollback and lock guard; **56/56** |

The existing `T148_DOCUMENT_TILES_RESULT checks=56 failures=0` line is retained
for current consumers; successful execution also emits
`T148_DOCUMENT_TILES_PASSED checks=56 failures=0` for the unmodified strict
`check_godot_model_log.py`. The original test's assertions and failure
exit conditions were not loosened. Its pre-marker output was rejected by the
strict checker (**exit 1**, `Expected exactly one ... marker, got 0`); two
final real-Godot runs have strict exit 0.

No new required CI job/step ID was added; the existing fail-late shell step,
per-process timeouts, strict named log checkers and exact assertion-count
checks stay in force. `test_t211_native_ci_contract.py` is called from the
same step and guards deleted preloads, replacement script presence, markers,
counts and optional native workflow coverage. The three un-runnable tests and
their `.uid` files were removed. Historical docs/evidence remain available
through Git history, not a revived Legacy bridge.

## Confirmed local validation

Commands and outputs are retained in
[`T-211-2026-11-19-required-native-ci-raw/`](T-211-2026-11-19-required-native-ci-raw/).
The accompanying `exits.tsv`, `source-sha256.txt`, `raw-sha256.txt` and
`commands.txt` identify outcomes and inputs.

| Check | Exit / result |
| --- | --- |
| New T-211 Python source contracts before/after | 1 (**5 fail-first**), then 0 (**5/5**) |
| Native Hokusai pigment smoke ×2 | 0 ×2, strict 0 ×2, **57/57 each** |
| Native signed lazy source bounds ×2 | 0 ×2, strict 0 ×2, **24/24 each** |
| Native signed replay bounds ×2 | 0 ×2, strict 0 ×2, **39/39 each** |
| Native tile publication after strict marker ×2 | 0 ×2, strict 0 ×2, **56/56 each** |
| Strict marker negative control on pre-marker tile-publication output | 1 (rejected) |
| `make python-test` | 0, **56 tests** |
| Existing CI fail-late / order contracts | 0, **9 tests** |
| Native Rust (bundled offline, `--test`) | 0, **35 tests** |
| Explicit GDScript typing audit | 0, **518 scripts**, 33 skills |
| Ruff changed Python source, ty defined target | 0 / 0 |
| YAML parsing of both edited workflows | Parsed, unchanged 1-job structure |
| `tools/validate_ticket_store.py` | **211 tickets valid**, manual gates preserved |
| `git diff --check` | 0 |

**Environment and limitations:** Linux software/headless Godot 4.8 beta3 with
the supplied offline Rust native extension, no physical mouse/GPU review, no
Windows or official release-template export and **no new GitHub-hosted run**.
CI includes other historical Legacy-era tests not covered here; none is silently
called green. T-106's required post-T-150 native inventory, T-180's hosted
portability/export, T-095's physical owner acceptance, and the T-148/T-149/T-150
architecture remain open. The T-211 ticket completes only this isolated
scripted-bridge CI failure and verified native-check replacement.
