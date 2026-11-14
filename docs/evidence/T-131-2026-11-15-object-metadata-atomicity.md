# T-131 — Object Editor metadata authorization and failed Save As rollback

Date: 2026-11-15. Branch: `sprint/2026-11-14`. The negative-control source is
the **exact T-130 Git tree** `a81d6e48929a0f2020db8d864159d40ac3f147b3`;
the recorded remote baseline is `61c6f689974a848f8a7cc4040c98be418518b156`.
Pinned engine: **Godot 4.8.beta3.official.c51ff06e8**, Linux x86-64,
from supplied bundle 8. No owner GPU, tablet or physical pointer-to-photon
measurement was available.

## Reproduction and bounded fix

On an independent Object Editor tab, release a large Brush gesture while it
is still draining and capture a second bounded gesture. The existing Rename
handler changed `DrawingObjectEditorSession.name` despite the unpublished
source transaction. The named Save As handler set `session.variant_name`
*before* calling `_publish_object(true)`, where the T-125 pending-stroke guard
would reject publication. The variant target also survived a rejected or
malformed publisher response. This was a private draft metadata inconsistency,
not a demonstrated lost pixel or published asset.

The workspace now refuses actual rename changes during pending paint, allows
an equivalent name, authorizes Save As before staging its variant target,
and restores the prior target if publication fails. `_publish_object` returns
an explicit success boolean to the named Save As handler; existing callers
still use it for the same publication side effects. Success continues to
publish the chosen variant name and clear `variant_name` normally.

The test `drawing/tests/t131_object_pending_metadata_smoke.gd` was executed
with its new test code on a clean replay checkout at the exact T-130 tree,
then against the candidate canonical workspace staged into Drawing. Its test
callbacks simulate rejection, malformed-success snapshots and a valid
successful publisher; both queued strokes must commit as separate document
revisions, with visible canonical RGBA8 pixels.

```sh
G=/mnt/data/work/bundle8/Godot_v4.8-beta3_linux.x86_64
python3 tools/build_drawing_app.py --in-place
"$G" --headless --audio-driver Dummy --editor --path drawing --import --quit
"$G" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t131_object_pending_metadata_smoke.gd > t131.log 2>&1
python3 tools/check_godot_model_log.py t131.log --marker T131_OBJECT_META_PASSED
```

- **Negative control:** exit 1, `T131_OBJECT_META_FAILED checks=21 failures=5`.
  SHA-256 of raw log: `2e0287127889f5c890835657868f9e6325a2eec8878713e598fccfbf37b8b047`.
- **Candidate:** exit 0, `T131_OBJECT_META_PASSED checks=21 failures=0`.
  SHA-256 of raw log: `aed30467b34022a7e1dda9aefe3801ad68dfd001345f909b2a9d2ce4401e6a05`.
  Strict log verification passed; four known Godot post-success RID resource
  leak diagnostics remain visible and separately classified.

## Adjacent verification

| Completed check | Result |
| --- | --- |
| T-131 Object metadata, headless | 21/21, exit 0, strict log |
| T-130 source-context guard | 34/34, exit 0, strict log |
| T-129 content mutations | 35/35, exit 0, strict log |
| T-128 History row guard | 37/37, exit 0, strict log |
| T-127 Undo/Redo guard | 40/40, exit 0, strict log |
| T-126 document switching | 34/34, exit 0, strict log |
| T-125 persistence protection | 29/29, exit 0, strict log |
| T-124 queued Brush | 69/69, exit 0, strict log |
| Object Editor UI, Drawing-only | 26/26, exit 0, strict log |
| Atlas/Object Editor source and publisher | 45/45, exit 0, strict log, after root import |
| Standalone Drawing smoke | PASS, exit 0, strict log |
| T-120 File/Object native X11 | PASS, exit 0, dedicated native checker |
| T-124 queued Brush native X11 | 19/19, exit 0, strict log |
| Independent native-absent Drawing consumer | staged/imported; standalone smoke PASS, exit 0 |
| T-131 Python source/CI contracts | 3/3 passed |

All X11 runs used `xvfb-run` with Godot X11/gl_compatibility on a software
renderer. The first Atlas Object Editor attempt before resource import could
not parse registered project classes and was not counted; the retry after
`--editor --path . --import --quit` passed 45 checks with a clean exit.

## CI and review boundaries

The new Godot oracle and three Python contracts run inside the existing
`ci_t085_live_stroke_preview` check. CI still enforces process exit, strict
forbidden-marker scanning, an exact 21-assertion success line, and duplicate
marker rejection. The existing **46 required check IDs** are unchanged.
Neither a fresh hosted CI pass nor hardware review is claimed. The T-095
large-Brush performance problem remains In Progress and owner-gated; the
T-106/T-107 hosted and other hands-on acceptance requirements remain open.
