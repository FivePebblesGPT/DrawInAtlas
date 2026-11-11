# T-095 — avoid rebuilding unchanged Canvas preview indexes (2026-11-11)

**Branch:** `sprint/2026-11-11`; **ticket:** T-095 (`In Progress`, `manual_review: true`). **Pinned local engine:** Godot `4.8.beta3.official.c51ff06e8`, Linux headless and Xvfb/Mesa llvmpipe. The owner-device 60px lag remains an unaccepted manual gate.

## Reproduction and implementation

`DrawingCanvas._draw()` previously called `DrawingEditSession.preview_stamps_for_display_tiles()` on **every** Canvas redraw while an edit session existed. The bounded projection loops through changed storage tile generations, parses their string keys and computes display-tile intersections. Repeated cursor/overlay redraws with no change to the detached preview rebuild identical indexes even when display raster textures are cached.

The Canvas now retains **one** private bounded index. It reuses it only with the identical edit-session object, preview `_preview_epoch`, document revision, and visible 128px display tile rectangle, and only for a live session. Paint/rollback generations, a changed viewport, source revision, or replacement session trigger recomputation. An idle/no-document draw discards the index and its retained session. No change to `DrawingEditSession`'s API, source pixels, renderer geometry, texture-dirty decisions, editing authorization, input samples, or history. `last_frame_metrics.preview_index_cache_hit` is 1 only on a reuse; the previous instrumentation fields remain intact. Existing index-budget overflow returns the same `indexed: false` exact per-area fallback.

## Independent regression and control

`drawing/tests/t095_preview_index_reuse_smoke.gd` runs under SceneTree; **529/529** assertions pass. It checks every display tile against `preview_stamp_for_area()` for signed windows and real Brush edits. It exercises unchanged cursor redraws, changing the window and returning to it, subsequent genuine Brush mutations, a cancelled session, a fresh session at the same revision, external commits invalidating a stale session, actual Canvas draw-frame metrics, and 40,000-entry overflow fallback with signed-int64 corruption protection. This last case uses a valid 2,048px Drawing storage stride and 170 synthetic storage tile stamps; the stress fixture adds no physical paint pixels.

A temporary **staged Drawing-copy only** mutation disabled the `_preview_index_for_draw()` reuse branch. Before the three overflow assertions were added, the same oracle failed **5/526** checks (including actual Canvas cursor draw); it returned exit code 1. Re-staging canonical `addons/drawing/canvas.gd` restored the **529/529** pass and exit 0. The temporary mutation was never committed.

An optional synthetic 240-storage-key, fixed-window benchmark repeated full index construction and cached lookup 80 times. Two local observations of full rebuild CPU time were approximately **58.6–61.5 ms** per 80 calls; cached lookups were **0.040–0.045 ms**. The index output and accumulated generations were byte/equality-equivalent. This is a narrow deterministic GDScript CPU workload, **not** a whole-frame speedup or physical input-to-photon timing. No CI timing budget was imposed.

## Local surrounding checks

The following ran under pinned beta3, with successful process exits and no script/engine errors in their accepted logs:

- New 529-check preview-index reuse model + actual Canvas redraw, strict `T095_PREVIEW_REUSE_PASSED`.
- T-086 existing preview index **2,146/2,146** (`T086_PREVIEW_INDEX_PASSED`) and viewport model **27/27** (`T086_MODEL_PASSED`), strict logs.
- T-095 no-op draw **24/24**, sparse-preview **133/133**, 60px source oracle **32/32**, tile-reference cache **626/626**, mixed-edit rollback **504/504**, strict logs.
- Xvfb viewport-cache native **153/153**, process exit 0 with exact `T086_NATIVE_PASSED` after regenerating missing `.ttf.import` metadata via standalone `--headless --editor --import --quit`. The *first* attempt exited 1 with two unrelated missing-font assertions; it is not counted as a pass.
- Xvfb released-stroke navigation **48/48**, and real 60px/786% five-stroke mouse-event witness success (stage p95 **182.480 ms**, release-to-commit p95 **58.045 ms**). These remain software-display measurements.

The first local viewport-model strict checker was mistakenly invoked with `T086_VIEWPORT_CACHE_PASSED` instead of its actual `T086_MODEL_PASSED` marker. It was rerun using the correct exact marker and passed; the earlier checker failure is not counted as a pass. No hosted GitHub Actions run, physical GPU/OS comparison, or owner approval has been conducted. The on-demand workflow registers only this new regression and its fail-closed raw log; T-094 and the required fast-CI matrix are unchanged. T-096 remains independently in Manual Review.

## Reproduction

```sh
python3 tools/build_drawing_app.py --in-place
# First import the pinned Godot editor project so font metadata exists.
godot --headless --editor --path drawing --import --quit
set -o pipefail
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_preview_index_reuse_smoke.gd \
  2>&1 | tee /tmp/t095-preview-index-reuse.log
python3 tools/check_godot_model_log.py /tmp/t095-preview-index-reuse.log \
  --marker T095_PREVIEW_REUSE_PASSED
```

**Outstanding:** Owner physically reproduces the original ~3-second 60px Brush stroke at 786% zoom on a reference device; collect actual pointer-to-photon latency plus stage/compose/upload/release p50/p95 and explicit owner decision. The optimization above cannot close T-095 on its own.

### Further compatibility confirmation

The real native integration test exited 0 (**30/30**), present-native fallback exited 0 (**7/7**), NativeHard source-read rollback exited 0 (**113/113**, strict marker), and Hokusai pigment rollback exited 0 (**57/57**, strict marker). A new **external empty-directory standalone** built from canonical source with `addons/drawing/native` removed before the editor import passed clean editor import (exit 0), this preview reuse regression **529/529** (strict marker), and native-absent fallback **7/7** (`native=false`, exit 0). This import did not use the existing in-place generated font metadata; the fonts imported within that standalone project. No LFS data is needed by this change.
