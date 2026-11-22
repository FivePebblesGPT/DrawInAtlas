# T-253 — dense Selection Delete input-to-frame repair (2026-11-22)

**Scope:** real-window 512×512 Selection Delete of three filled blocks, not the
T-221 eight-pixel sparse-clear fixture. The original owner screenshot
[`DrawingCurrent.png`](../assets/drawing-ux-2026-11-22/DrawingCurrent.png)
was used as the layout reference. Test colors/rectangles are representative,
not claimed as the owner's document bytes. No physical owner acceptance.

## Diagnosis and controlled fail-first witness

- Godot **4.8 beta 3**, Linux x86-64, Xvfb/X11, OpenGL compatibility,
  **Mesa llvmpipe 25.0.7**, 1280×795 window, 119% canvas zoom, 512×512
  image at (-256,-256). Three solid red rectangles plus one hidden-RGB
  pixel: **71,901 occupied pixels in four 256² storage tiles**; mask hole
  protects one selected red pixel. Exact source/texture sampling, seven
  Delete→frame→Undo→frame repetitions; Ctrl+D measured separately.
- Before fix, T-221 already limited traversal to occupied source pixels but
  performed **one GDScript `_stage()` and one global string-keyed history
  publication per occupied pixel**. A 71,900-pixel *headless* trace showed
  **528,175 µs staging + 583,698 µs commit = 1,112,225 µs** synchronous
  blocking. This explains why a previous eight-pixel p50=21.3ms graphical
  benchmark was not representative of the reported dense case.
- Fail-first **clean imported** native witness: copied the untouched
  `HEAD` versions of `edit_session.gd` and `document.gd` into the staged
  Drawing project while keeping the same tests and imported resources.
  **Delete input→first updated framebuffer** (7 trials):
  `[1127409, 1074059, 1039340, 999548, 1081270, 1030359, 1048773]` µs;
  **p50=1,048,773 µs; p95=1,127,409 µs**. The exact unchanged
  `T253_NATIVE_PASSED` assertion fails on the 500ms p95 ceiling, exit=1,
  rather than reporting green. No resource/script errors in this run.
- Same fixture after restoring the candidate, with optional
  `DRAWING_T253_PROFILE=1` enabled: input→frame
  `[142074, 135238, 145030, 152026, 178988, 139697, 139227]` µs;
  **p50=142,074 µs; p95=178,988 µs**. **~7.4× p50 / ~6.3× p95 faster.**
  Seven Ctrl+D input→frame trials do not mutate raster/history (the
  earlier unprofiled positive run had p50=7,794 µs, p95=8,276 µs).
- Compared against the 500ms software-X11 threshold intended to catch a
  **one-second frozen frame**, not a general display-frame/FPS guarantee.
  The X11 readback confirms actual changed viewport pixels but cannot
  measure physical scanout. No Windows/owner reference-hardware timings.

## Implementation

- `DrawingEditSession.clear_rect()` takes a **deferred per-tile RGBA8 path**
  only for a fresh session with a native tile ABI. It visits occupied source
  tiles, checks mask eligibility and the 1,048,576 occupied-pixel budget,
  creates one packed replacement buffer per changed tile, tracks tile-local
  preview offsets, and avoids per-pixel `"x,y"` allocation/history staging.
  Empty/pending unselected sources remain untouched. Mixed edit APIs
  materialize canonical pixel deltas before continuing; non-native callers
  retain the existing fallback path.
- `DrawingDocument._publish_dense_clear_tiles()` reuses checked
  `_publish_native_tile_edit(..., dry_run=true)` to freeze complete source
  identities, exact before/after bytes and dirty bounds **before** mutation.
  Rust accepts one failure-atomic `adopt_external_edit` with a whole-tile
  native history token. Only afterward are the prevalidated detached Godot
  tiles installed and the document/Atlas history revision advanced.
- Optional `DRAWING_T253_PROFILE=1` reports whole-command preflight,
  staging and commit+UI times. It is diagnostic-only and off by default.
  Seven native graphic profiles show remaining stage ~96–111ms, commit+UI
  ~26ms; their cost fits the measured input-to-frame period.

## Independent correctness and integration tests

| Test | Outcome | What it verifies |
| --- | --- | --- |
| `drawing/tests/t253_selection_delete_model.gd` | **22/22** | Native first adoption, 4,095 selected pixels, masked hidden RGB, signed tile, deferred preview and unchanged precommit revision, native whole-tile delta, Undo/Redo, standalone `.drawing` Save/Open, mixed-stage fallback in both orders, lock and over-budget atomic rejection |
| `drawing/tests/t253_selection_delete_native.gd` | **44/44**, 7 Delete+Undo and 7 Deselect real X11 input dispatches | Actual framebuffer before/after sampling and screenshots, owner-like 512² scene, exact tile pixels/history, no one-second stall |
| `tests/t253_atlas_dense_delete.gd` | **15/15** | Real Atlas campaign with 8,191 selected pixels, native-first edit, two whole-tile source images, single external chronological command, Undo/Redo, signed hidden RGB, campaign generation Save/Open |
| `drawing/tests/t221_selection_delete_regression.gd` | Passed | sparse mask, hidden RGB, signed anchors, lazy corrupt-source rejection, size budget and standalone persistence |
| `drawing/tests/selection_clipboard_smoke.gd` | Passed | neighboring selection/clipboard and Move model |
| `tests/t221_atlas_selection_delete.gd` | Passed | native Hokusai source+selection clear with Atlas global history and Save/Open |
| `tests/t148_atlas_native_tile_history.gd` | Passed | neighboring native Atlas history integration |

The new model is required in the existing T-088 fast-desktop CI step,
and the Atlas witness is required in its existing T-055 step; neither adds
or silently renumbers a required step ID. The on-demand T-088 X11 workflow
also runs the actual dense input/frame test, validates its strict pass
marker, and uploads source+cleared screenshots and logs. **Hosted CI was
not run for this local commit**. Source-only and snapshot tests do not
substitute for the owner's hardware review.

## Follow-up gates

T-253 is an **engineering completion** only. T-088 (Selection workflow),
T-250 (Drawing UX manual review), and T-059 (overall Drawing UX) remain
unapproved. The owner must verify that dense Selection Delete no longer
freezes on the actual machine, at the same original document/zoom and
with cold/warm repetitions. This narrower fix does not complete universal
T-148 native history ownership or change T-149's dependency.
