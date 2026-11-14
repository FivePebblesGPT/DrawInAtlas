# T-114 — Polygon campaign/registry authorization

**Date:** 2026-11-12. **Starting commit:** local T-113
`8002adccdf366a7bee37e2d5071e84f70aa8603d` (original Canvas blob
`333f152138e8dd20a01c4250cccddb50e352e53b`). **Remote PR #17 HEAD
rechecked:** `79b8959e9eac01b3bb10a144a46407acc6901aed`, open/unmerged.
**Candidate Canvas blob:** `55075f9a84a5d3bef083d4bbb426db26e42363f6`.
**Engine:** pinned `4.8.beta3.official.c51ff06e8`, Linux x86-64;
Xvfb/Mesa llvmpipe for native graphical check; no physical device or
hosted CI result claimed.

## Failure and red control

The Polygon first-vertex snapshot already fixed its map, floor, raster layer,
selected-cell scope, and current presentation/lock eligibility. Unlike a
registered document transaction, however, `_polygon_context_matches()` only
compared the `Canvas.map`/`Canvas.floor` Resource pointers against those
snapshots. If the campaign replaced/removed the registered map, or a map
replaced/removed its registered floor while Canvas still held the original
Resources, a polygon could be closed and send `stroke_requested` to the
editor. A different campaign Resource retaining those same map/floor objects
was also admitted. These are not merely ID collisions: the map/floor
replacements are serialized-byte-equal to the originals.

`tests/t114_polygon_registered_target_smoke.gd` creates a new real Atlas
Editor and Board for each of five failures: same-ID same-byte registered map
replacement, map removal, same-ID same-byte registered floor replacement,
floor removal and campaign-owner replacement. It records the emitted stroke
and rejection signal counts, full floor dictionary and Undo cursor, and
requires rejection with no publication, followed by a separate valid
registered Polygon and exact raster Undo/Redo. A registered **unrelated** map
change is explicitly allowed during that valid gesture.

**Red:** substituting the *exact unmodified T-113 Canvas blob* while keeping
the new test yields exit code **1**, **14 failures / 43 checks**. A stale
closure can emit strokes and, for some replacements, mutate source/history.
The raw failed oracle is retained and must never be read as a pass.

**Green:** capturing the campaign Resource alongside map/floor/layer and
checking `campaign.get_map(map.id) == map` and
`map.floor_by_id(floor.id) == floor` on every context check yields exit code
**0**, **43/43** assertions; strict `T114_POLYGON_PASSED` log verification
passes. Source is `scripts/interface/canvas.gd`; the captured campaign
reference is cleared with the rest of the Polygon draft on commit/cancel.
The existing layer, detail, selection and geometry checks are unchanged.

## Reproduction and scope

From the repository root with the pinned Linux beta3 engine and initialized
project imports:

```bash
GODOT=/path/to/Godot_v4.8-beta3_linux.x86_64
export GODOT_SILENCE_ROOT_WARNING=1
# Red: temporarily replace ONLY scripts/interface/canvas.gd with its
# 'git show 8002adcc:scripts/interface/canvas.gd' bytes, preserving a backup.
timeout --signal=TERM --kill-after=5s 120s "$GODOT" --headless --path . \
  --script res://tests/t114_polygon_registered_target_smoke.gd \
  > t114_old_source_red.log 2>&1       # expected exit 1
# Restore the T-114 candidate before running any other test.
timeout --signal=TERM --kill-after=5s 120s "$GODOT" --headless --path . \
  --script res://tests/t114_polygon_registered_target_smoke.gd \
  > t114_polygon_registered_target_smoke.log 2>&1   # exit 0
python3 tools/check_godot_model_log.py \
  t114_polygon_registered_target_smoke.log --marker T114_POLYGON_PASSED

# Nearby headless source/history oracles (each exits 0):
for name in polygon_smoke t111_line_release_authorization_smoke \
  t113_bucket_resource_identity_smoke drawing_composition_smoke \
  raster_objects_smoke; do
  timeout --signal=TERM --kill-after=5s 120s "$GODOT" --headless --path . \
    --script "res://tests/$name.gd" > "$name.log" 2>&1
done
# Real GUI input, software renderer only (exit 0):
timeout --signal=TERM --kill-after=5s 120s xvfb-run -a "$GODOT" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path . --script res://tests/polygon_visual.gd \
  > polygon_visual.log 2>&1
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p test_t094_godot_model_log.py -q
python3 -m unittest discover -s tests -p test_godot_ci_fail_late.py -q
```

**Nearby results:** Polygon portable Save/Open **70/70**, T-111 Line
authorization **49/49**, T-113 Bucket authorization **29/29**, Atlas
composition **89/89** (4 named post-exit Godot leak diagnostics retained),
Xvfb Polygon **17/17**, and the historical raster-objects suite **52/52**
all exited 0. The five first named logs plus T-114 are accepted by the
T-094 exact-marker policy; the 52-check raster-objects suite uses the old
`(52 checks)` grammar and is **not strictly verifiable**, despite exiting 0.
Explicit typing **423 project scripts / 33 skill documents**, ticket-store
**114 tickets**, strict log-policy **24 tests**, CI fail-late **8 tests** and
workflow YAML/46 unique check IDs passed.

## Archived raw evidence and SHA-256

All files below are in `docs/evidence/raw/T-114/`; `.log` paths are forcibly
tracked despite the repository-wide `.gitignore` rule.

| File | Exit | Expected result | SHA-256 |
| --- | ---: | --- | --- |
| `t114_old_source_red.log` | 1 | 14/43 expected failures | `d5c5f92473c00ef3c7fc8386b4fda31ea31c252bebf1cee47dc1a0461b720815` |
| `t114_polygon_registered_target_smoke.log` | 0 | 43/43, strict | `829ed7f656815389561d20103b898f0f990134cf10ff56a7a44cc6fa09a0a7e7` |
| `polygon_smoke.log` | 0 | 70/70, strict | `c0dcf8edf9000de5db4318d412e7e19c1c0fa43b3e4610b077941dabc433e282` |
| `t111_line_release_authorization_smoke.log` | 0 | 49/49, strict | `9fe0c8a2405e654de5618e48303a58f3a739f1363b10fd77a52669b2c087c43e` |
| `t113_bucket_resource_identity_smoke.log` | 0 | 29/29, strict | `0641679554209786c98dbc34b2f75bb263ea6285f40ce0a1072756602d3dd114` |
| `drawing_composition_smoke.log` | 0 | 89/89, strict, 4 known leaks | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |
| `polygon_visual.log` | 0 | 17/17, Xvfb | `12b316990582bd359fa61f1958bf9df1f3737db7537657b781f6ae781c6b3438` |
| `raster_objects_smoke.log` | 0 | 52/52, historical marker | `00b8872e799345cbc5502ac08406871119a6f21920363bc9e4fe6907f2d3cac3` |

**Review gates:** T-114 has no manual gate and directly depends only on Done
T-028. T-025's independent user-facing Polygon behavior approval remains
unsettled; no parent or other ticket's owner-review status was changed.
Required CI inventory remains 46; the new oracle is added inside the
existing Atlas composition step. Hosted CI has not been run on this local
candidate, and physical-pointer timing/acceptance is not claimed.
