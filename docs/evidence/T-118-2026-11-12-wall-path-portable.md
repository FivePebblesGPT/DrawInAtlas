# T-118 — Atlas Wall Path smoke regression repair

**Date:** 2026-11-12
**Baseline Git HEAD:** `b9fec9c30858ddb5cf9ed295e4679f06c11172ae` (T-117)
**Original `tests/wall_paths_smoke.gd` Git blob:** `d2223542caf67deffd42d2b47c2e46b84bcfd8a8`
**Candidate `tests/wall_paths_smoke.gd` Git blob:** `efae22ff94e85aaa136a4f54a6ec95baaaaab261`
**Godot:** `4.8.beta3.official.c51ff06e8`
**Host:** Linux headless, graphical Xvfb/Mesa `gl_compatibility`, Dummy audio. These are software checks, not physical device or owner acceptance.

## Red and green controls

The **unchanged** T-117 Wall suite exits **1** after `78` checks and **four**
`WALL PATH FAILED` lines:

1. `explicit restyle action changes style only`: the test had cleared the selected handle (`_wall_selected_index == -1`) before invoking the *selection-dependent* command.
2. `style redo`: the first failed restyle never generated a history command.
3. `native save round-trip retains path edits`: the test asked the retired `load_campaign("campaign.scn")` loader to reopen an Editor `_on_save()` that writes a **portable generation**.
4. `changed cell rejects vertex drag without modifying the wall or history`: the selected-cell edit mask was disabled, so changing only cell focus was correctly permitted.

The corrected **test only** explicitly clicks the existing wall to select it,
requires that selection, then verifies Restyle and one-step Undo/Redo.
It turns the cell scope on before the stale-drag test, preserving the separate
positive test that an unmasked gesture is allowed to survive cell-focus
changes. It loads the saved generation with `load_portable_result()`, requires
`OK`, a nonempty generation ID, complete `to_dict()` equality for the
campaign including editable paths, the portable root and absence of a legacy
single-file head, then verifies that Undo does not alter the loaded snapshot
and Redo restores the exact live campaign.

The corrected suite exits **0** and prints
`ATLAS_WALL_PATHS_PASSED checks=82 failures=0`. The independent strict
`check_godot_model_log.py` verifier exits **0**. No runtime GDScript,
serializer, UI contract, or review status changed.

## Reproduction

From the repository root, with the pinned engine available:

```sh
G=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$G" --headless --audio-driver Dummy --path . \
  --script res://tests/wall_paths_smoke.gd > wall-portable.log 2>&1
python3 tools/check_godot_model_log.py wall-portable.log \
  --marker ATLAS_WALL_PATHS_PASSED

# Neighboring source authorization:
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$G" --headless --audio-driver Dummy --path . \
  --script res://tests/t117_wall_registered_target_smoke.gd > wall-owner.log 2>&1
python3 tools/check_godot_model_log.py wall-owner.log --marker T117_WALL_PASSED

# Real graphical test:
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 135s \
  xvfb-run -a "$G" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path . \
  --script res://tests/wall_paths_visual.gd > wall-visual.log 2>&1
python3 tools/check_godot_model_log.py wall-visual.log \
  --marker ATLAS_WALL_PATHS_VISUAL_PASSED

python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
python3 -m unittest discover -s tests -p test_t094_godot_model_log.py
python3 -m unittest discover -s tests -p test_t094_ci_replay.py
```

The original log was captured **before** editing the test on T-117. That
red process exited 1 and must not be counted as a passing run. The green
runs below had confirmed process exit 0 **and** strict verifier exit 0.
A combined neighboring-test batch hit its overall execution watchdog while
checking Polygon; that incomplete process is **not** counted as green.

## Raw-log evidence

The following files are committed verbatim in
`docs/evidence/T-118-2026-11-12-logs/` (SHA-256 over raw file bytes).

| Log | Outcome | Process / verifier exits | SHA-256 |
| --- | --- | --- | --- |
| `wall-legacy-red.log` | T-117 test, **4/78 failed** | 1 / rejection expected | `0ffb0beddd351876257976cbb892a4fcac56395776075cccef741cbc7a8cd257` |
| `wall-portable-green.log` | Wall smoke **82/82** | 0 / 0 | `4bc787f0d6c203f8bb8a294c67039b9c4f3eba2204c189b1fbb43ce5e4a15f58` |
| `wall-owner.log` | T-117 **91/91** | 0 / 0 | `e39bc356f61706e43cefc93c3b55898f92038afbed13b808a81f8c254dcb339a` |
| `wall-visual.log` | Xvfb Wall **20/20** | 0 / 0 | `f68a16389683a11d2f0b960882b5dbb5b952488cea814c4e5e70610dc6b8efeb` |
| `atlas-composition.log` | Atlas composition **89/89** | 0 / 0 | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |
| `line-portable.log` | Line portable Save/Open **128/128** | 0 / 0 | `298289bd4fb0b6b6a4f357ff052b649a604fe4f10390282b7103212c622b6346` |
| `bucket-owner.log` | Bucket identity **29/29** | 0 / 0 | `0641679554209786c98dbc34b2f75bb263ea6285f40ce0a1072756602d3dd114` |

The Atlas composition log includes **four named Godot resource-leak errors
after** its success marker. The strict checker identifies but does not erase
or claim a clean teardown for these recognized diagnostics.

## CI and acceptance boundary

Only the existing required T-055 composition CI step is extended to execute
the repaired Wall smoke under a separate 120-second watchdog with a raw `tee`
log and the exact `ATLAS_WALL_PATHS_PASSED` marker verifier. The required
workflow still exposes **46 unique check IDs**, and the 118-ticket store
validator, 425-script explicit-type check, 24 strict model-log policy
contracts and 14 replay contracts pass locally. No GitHub-hosted run,
physical rendering latency, or owner decision on T-026's Wall Path controls,
mask and editable-path persistence is asserted.
