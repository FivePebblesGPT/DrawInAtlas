# T-116 — Atlas editable Text portable Save/Open regression

**Date:** 2026-11-12
**Baseline commit:** `8b23ab5997dc2f50dde4dd2f4d5be6f038607960` (T-115)
**Baseline `tests/text_smoke.gd` Git blob:** `2b67cb03769a8a9c15bfa4336eec61214019bb52`
**Candidate `tests/text_smoke.gd` Git blob:** `96d4580776c7cc3ef999ea2c57c416708dc7e625`
**Pinned engine:** `4.8.beta3.official.c51ff06e8`
**Environment:** Linux headless + graphical Xvfb/Mesa llvmpipe, Dummy audio; no physical input-to-photon or owner acceptance.

## Failure and correction

The existing `tests/text_smoke.gd` invoked the Editor's current `_on_save()`
portable writer and then called `AtlasCampaignStore.load_campaign()` on the
retired `campaign.scn` head. On the exact T-115 checkout the real process
exited **1**, recording `ATLAS_TEXT_PASSED checks=69 failures=2` and the two
`TEXT FAILED` lines for obsolete native reload and editable-content checks.
A printed PASS token alongside nonzero failures is never treated as a pass.

The correction changes **only the test**. It now calls the Editor Save and
`load_portable_result()` at both D0 and D1, requiring a nonempty generation
ID, `OK` status, exact campaign/Objects-layer dictionaries, an existing
portable root with no retired head, retained content/metadata, and Text
reopening in the editor. After saving the second generation, Undo and Redo
must change the live campaign without changing the loaded published snapshot.
The corrected test exits **0** with `ATLAS_TEXT_PASSED checks=73 failures=0`;
`tools/check_godot_model_log.py --marker ATLAS_TEXT_PASSED` exits **0**.

## Reproduction and process outcome

Run from the repository root with fonts hydrated and the original Godot
import cache available. The first command against T-115 is the *red* control;
run it before replacing `tests/text_smoke.gd` with the T-116 candidate.

```bash
G=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$G" --headless --audio-driver Dummy --path . \
  --script res://tests/text_smoke.gd > text.log 2>&1
# Record the exact process exit. The red T-115 control returns 1.
python3 tools/check_godot_model_log.py text.log --marker ATLAS_TEXT_PASSED

# Green: separately run tests/t115_text_modal_registered_target_smoke.gd,
# drawing_composition_smoke.gd, campaign_bundle_editor_smoke.gd,
# line_smoke.gd and polygon_smoke.gd with matching exact markers.
# On graphical Linux:
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 140s \
  xvfb-run -a "$G" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path . \
  --script res://tests/text_visual.gd > text-visual.log 2>&1
python3 tools/check_godot_model_log.py text-visual.log \
  --marker ATLAS_TEXT_VISUAL_PASSED

python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
python3 -m unittest discover -s tests -p 'test_t094_godot_model_log.py'
python3 -m unittest discover -s tests -p 'test_t094_ci_replay.py'
```

### Retained raw logs

All paths below are relative to `docs/evidence/T-116-2026-11-12-logs/`.
Their SHA-256 digests were computed over the exact committed log bytes.
The negative control exits nonzero by design; every green process **and its
strict log verifier** exited 0. The T-055 composition test emitted four
recognized post-exit Godot leak diagnostics, retained verbatim in its raw log;
this is not a claim of clean teardown.

| File | Assertions / outcome | Process exit | SHA-256 |
| --- | --- | ---: | --- |
| `text-legacy-red.log` | 69 checks, 2 failures (old test) | 1 | `8fb9e6af17f95a489c808d5727dc216bbc78f1e107b2d9d2662a8248cccbe4a7` |
| `text-portable-green.log` | 73/73 Text portable Save/Open | 0 | `e825aa6218eafbd56bdc0081e752a4bbc019601d29fcc7c9256e323662e6da33` |
| `t115-ownership.log` | 42/42 Text modal ownership | 0 | `cb993192d909712cb2bbc3500c5b25601ce7b18753fc7943a1de0b45f7d5977e` |
| `text-visual-xvfb.log` | 22/22 graphical Text | 0 | `3df1fa52a716d7009bf787f1d9af34923f550facc114f71c3995607b391840b2` |
| `composition.log` | 89/89 Atlas composition; four retained recognized leaks | 0 | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |
| `portable-editor.log` | 23/23 portable Editor Save/Load | 0 | `572fb6d280fe102cb84c1f8f29124db09da2899be38efcbb986b7fcca6adef3d` |
| `line-neighbor.log` | 128/128 Line portable Save/Open | 0 | `298289bd4fb0b6b6a4f357ff052b649a604fe4f10390282b7103212c622b6346` |
| `polygon-neighbor.log` | 70/70 Polygon portable Save/Open | 0 | `c0dcf8edf9000de5db4318d412e7e19c1c0fa43b3e4610b077941dabc433e282` |

## CI / review boundary

The new test invocation runs after the T-115 ownership oracle in the
existing required T-055 Atlas composition step, with its own bounded timeout,
raw `tee` log and fail-closed success-marker verifier. The **46 required CI
step IDs** are unchanged. Local workflow tests, explicit type checks and
Kanban validator pass. Hosted GitHub CI was **not** run for this commit;
the parent T-027 font/control/readability owner approval is still unresolved.
