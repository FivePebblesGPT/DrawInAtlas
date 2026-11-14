# T-115 — registered-source authorization for Atlas Text Apply

**Date:** 2026-11-12
**Baseline Git commit:** `d83136f2f995ac48cd3e3346f205ae3d46c8ae3b` (T-114)
**Baseline `scripts/interface/editor.gd` Git blob:** `d41bf6a822047b8e7308cf129ad0208bc01af7e2`
**Candidate `scripts/interface/editor.gd` Git blob:** `4f6ef4e6ccc5dd2da18dd5f8df0bf1ca546247d5`
**Engine:** `4.8.beta3.official.c51ff06e8` (pinned supplied binary)
**Host:** Linux, Godot headless + Xvfb/Mesa llvmpipe graphical test, Dummy audio

## Defect and change

The Text modal already held exact map/floor/Objects-layer pointers and a
frozen selected-cell edit mask. These pointers did **not** prove that their
original map and floor were still owned by the campaign's live registry at
Apply time. Replacing a map, replacing a floor, or assigning a different
campaign owner while keeping Canvas's original map/floor pointers could
publish text or create a history entry on a detached source. The new guard
captures the campaign owner at opening and requires Editor, Canvas and the
registered map/floor edges to still match before any publication. Rejection
keeps the user's draft visible and never writes the original source or history.
The campaign reference is cleared when the modal closes.

## Negative control and candidate

The new standalone Godot oracle `tests/t115_text_modal_registered_target_smoke.gd`
uses a real `main.tscn` Editor and an actual Text modal. Each case starts with
fresh campaign state and verifies original source dictionaries and the Undo
cursor/command. It includes same-ID byte-identical map/floor replacement,
removed registry entries, Canvas campaign replacement, Editor campaign
replacement, draft/error retention and captured-reference cleanup. A
positive control adds an unrelated map, commits one text object, then compares
full source dictionary bytes across Undo and Redo.

| Source | Command exit | Assertions | Strict result |
| --- | ---: | ---: | --- |
| Original T-114 Editor (`git show d83136f:scripts/interface/editor.gd`) | 1 | 8 failed of 42 | Expected red (no success marker) |
| Candidate Editor | 0 | 42/42 passed | `T115_TEXT_PASSED`, accepted |

The negative control temporarily substituted only the exact original Editor
source into this same checkout, then restored the candidate before continuing.
No test assertions or new script were removed from the control. Cases where
the prior history transaction already rejected a removed registry entry still
pass on the old code; the eight failures are precisely the unguarded
replacement/ownership cases. The committed candidate did not change storage,
text rendering, selection modes or the native plugin interface.

### Reproduction

From repository root (after Godot import and font hydration):

```sh
G=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 timeout 140s "$G" --headless --audio-driver Dummy \
  --path . --script res://tests/t115_text_modal_registered_target_smoke.gd \
  > /tmp/t115-text.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t115-text.log --marker T115_TEXT_PASSED

GODOT_SILENCE_ROOT_WARNING=1 timeout 130s xvfb-run -a "$G" \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path . --script res://tests/text_visual.gd > /tmp/t115-text-visual.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t115-text-visual.log \
  --marker ATLAS_TEXT_VISUAL_PASSED

python3 tests/check_explicit_types.py
python3 -m unittest discover -s tests -p 'test_t094_godot_model_log.py'
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py'
python3 tools/validate_ticket_store.py
```

The required `ci_14_verify_t_055_atlas_canonical_drawing_composition_and_input`
step runs the new oracle with its own 120-second watchdog and raw log using
the existing T-094 strict checker. The CI inventory remains 46 check IDs.

## Neighboring tests (Godot process exit and strict log outcome)

| Suite | Exit / strict log | Result |
| --- | --- | --- |
| T-115 source oracle | 0 / 0 | 42/42 |
| Graphical Text `text_visual.gd` | 0 / 0 | 22/22 |
| T-111 Line release | 0 / 0 | 49/49 |
| T-113 Bucket release | 0 / 0 | 29/29 |
| T-114 Polygon ownership | 0 / 0 | 43/43 |
| Atlas composition | 0 / 0 | 89/89 (known Godot shutdown leaks retained) |
| Line portable Save/Open | 0 / 0 | 128/128 |
| Polygon portable Save/Open | 0 / 0 | 70/70 |
| Explicit GDScript types | 0 | 424 scripts, 33 skill documents |
| T-094 log-policy Python contracts | 0 | 24 passed |
| CI-order Python contract | 0 | 1 passed |
| Ticket-store validator | 0 | 115 tickets valid |

**Known unrelated red:** `tests/text_smoke.gd` exits **1** with two
Save/Open failures (`native campaign save and reload`, `native save preserves
editable content`) on both exact T-114 and candidate Editor sources. Its old
native `.scn` campaign path is not the application's portable generation
format. Both retained logs have identical SHA-256. This is **not** claimed
passing and is not fixed as part of this one authorization ticket.

## SHA-256 of retained raw logs

All listed files are committed in `docs/evidence/T-115-2026-11-12-logs/`.
The failed control and the known failing legacy suite are retained rather
than normalized or hidden.

| Raw log | SHA-256 |
| --- | --- |
| `t115-old-source-red.log` | `2768bdadcd17fad1c3aeb45d018d01e364795d0e82d29821f4de8c72d8e69c70` |
| `t115-candidate-green.log` | `cb993192d909712cb2bbc3500c5b25601ce7b18753fc7943a1de0b45f7d5977e` |
| `text-visual-xvfb.log` | `3df1fa52a716d7009bf787f1d9af34923f550facc114f71c3995607b391840b2` |
| `text-smoke-old-source-red.log` | `8fb9e6af17f95a489c808d5727dc216bbc78f1e107b2d9d2662a8248cccbe4a7` |
| `text-smoke-candidate-red.log` | `8fb9e6af17f95a489c808d5727dc216bbc78f1e107b2d9d2662a8248cccbe4a7` |
| `t111-line-neighbor.log` | `9fe0c8a2405e654de5618e48303a58f3a739f1363b10fd77a52669b2c087c43e` |
| `t113-bucket-neighbor.log` | `0641679554209786c98dbc34b2f75bb263ea6285f40ce0a1072756602d3dd114` |
| `t114-polygon-neighbor.log` | `829ed7f656815389561d20103b898f0f990134cf10ff56a7a44cc6fa09a0a7e7` |
| `t055-composition-neighbor.log` | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |
| `line-neighbor.log` | `298289bd4fb0b6b6a4f357ff052b649a604fe4f10390282b7103212c622b6346` |
| `polygon-neighbor.log` | `c0dcf8edf9000de5db4318d412e7e19c1c0fa43b3e4610b077941dabc433e282` |

**Limitations:** These are Godot-simulated editor state changes and
software-rendered Xvfb input, not physical Windows/Linux owner acceptance,
correctness of the entire Text UX or successful hosted GitHub Actions. T-027
and other manual-review gates remain unchanged. No product policy was
approved or inferred from this checkpoint.
