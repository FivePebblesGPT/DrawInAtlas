# T-095 — Brush result allocation/ownership checkpoint

**Date:** 2026-11-09
**Ticket:** T-095, `In Progress`, `manual_review: true`
**Source:** `addons/drawing/edit_session.gd`, session-private successful pixel staging.
**Environment:** Godot `4.8.beta2.official.cafc17a19`, Linux Xvfb 1280×900×24, Mesa 25.0.7 llvmpipe/OpenGL 4.5. Neither a physical input-to-photon nor owner-display timing.

## Reason for change and invariant

Every successful Legacy Brush pixel formerly created a `DrawingResult` even
though the internal rasterizer only checked `result.ok`. Now just the internal
Brush/NativeHard paths pass `internal_brush=true` and receive a shared
success-only instance owned by their `DrawingEditSession`. `RGBA`, tile-source,
revision and other failures still return **new** failure results. Unrelated
`_stage()` callers keep newly allocated success objects: they may inspect or
mutate their result without corrupting future operations. The external
`paint_path()` return remains a fresh result. The sentinel is never stored in
document history or exposed by a normal editor API. Source pixels, blend,
coverage and candidate selection are unchanged.

## Pointer-driven paired software controls

The existing `drawing/tests/brush_latency_native.gd` generates five real
Godot mouse-down/motion/up gestures with 120 motions each, four per frame,
60px Legacy Brush at 786% zoom on a new 512×512 image. No fill API was used.
The previous committed source was restored **only** to the standalone staged
`edit_session.gd` for the second baseline; canonical addon source was then
restored. Two old→new pairs were run with the same Godot binary and renderer:

| Control | Previous stage p50 / p95 | New stage p50 / p95 | Previous release p95 | New release p95 |
| --- | --- | --- | --- | --- |
| A | 132.443 / **138.769 ms** | 121.368 / **123.404 ms** | 62.105 ms | 64.150 ms |
| B | 147.034 / **150.340 ms** | 118.952 / **128.852 ms** | 63.673 ms | 62.059 ms |

The observed staging p95 decrease was **11.1%** (A) and **14.3%** (B).
Compositor p95 moved 12.032→12.099ms (A), 13.029→12.419ms (B); these
numbers do not justify a compositor claim. Release-to-commit moves in
opposite directions and remains near 62–64ms. Five strokes cannot
establish significance or a physical responsiveness gain; there is no owner
acceptance or official hosted CI result.

Local raw logs (outside Git): `t095-turn12-baseline.log`,
`t095-turn12-optimized.log`, `t095-turn12-baseline2.log`,
`t095-turn12-optimized2.log`.

## Regression and failure-boundary evidence

- New independent result-ownership oracle: **30/30**, including ordinary
  caller mutation isolation, shared internal selection and covered-pixel
  successes, invalid RGBA failure/retry, signed source pixels, detached
  preview and canonical Undo/Redo, and actual 60px oblique painting.
- Existing headless coverage **32/32**, oblique Geometry2D **86/86**,
  signed tile/source oracle **4,193/4,193**, native tile math **422/422**,
  native Hokusai delta **126/126**, direct tile publication **56/56**,
  queue compaction **31/31**, latency-window **22/22**, sparse-preview
  **133/133**, and blend/selection/viewport-index/live-stroke smoke passes.
- Xvfb native integration **30/30**, released-stroke navigation **48/48**,
  native live-stroke and signed pixel-boundary regression passed; viewport
  cache **153/153** after a clean standalone font-resource reimport.
- A clean standalone build with the `.gdextension` and `.so` removed **before
  first import** passes the new **30/30** oracle and 6/6 Legacy fallback.
  Existing project caches are not a substitute for a clean fallback test.
- `python3 tools/validate_ticket_store.py` validates all 96 frontmatter
  records and manual-review gates. The new test's log passes
  `tools/check_godot_model_log.py --marker T095_BRUSH_RESULT_PASSED`.

The on-demand T-095 workflow now invokes the oracle and retains its log.
This checkpoint does not close T-095. Real-device catch-up latency,
custom/textured-brush headroom, hosted CI, OS export behavior and explicit
owner re-acceptance are still needed. Preserve T-096's separate review.
