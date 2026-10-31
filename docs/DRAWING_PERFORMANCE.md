# Drawing performance and pointer sampling

The 2026-10-31 report described progressively falling frame rates while drawing,
including inside one hex, and missing mouse motion between frames.

## Cause and runtime changes

- Input accumulation merged OS mouse events once per rendered frame. Freehand
  press now disables `Input.use_accumulated_input`; release, cancellation, focus
  loss, tool changes and canvas teardown restore the previous setting.
- The input callback records samples; preview work runs once per process frame.
  Stroke samples remain in document coordinates and one gesture still produces
  one undo command.
- Raster preview previously rescanned the whole gesture bounds against every
  segment and cloned its source on every sample. `AtlasRasterBrush` now supports
  incremental sessions: scan new segments, remember covered pixels, and blend
  each pixel once against the original source into a detached snapshot. The
  whole-gesture candidate-pixel limit and transformed full-pixel mask checks
  still apply. The static `paint()` entry point uses the same coverage logic.
- The subsequent owner clarification retired freehand Ink authoring. Brushes
  and all ordinary shapes now target raster; walls, text and placed image props
  target Objects. Completed layer draw commands are retained while only the
  draft/cursor changes. See [[RASTER_OBJECTS_WORKFLOW]].
- Long or holed semantic/legacy object paths use coverage masks, clipped to their
  visible bounds and rebuilt after pan/zoom/resize. This avoids expensive path
  unions and the old fallback's repeated alpha blending at self-overlaps.
  Masks are derived viewer data; semantic geometry and metadata stay in the
  document. Unused masks and raster-preview texture generations are discarded.
- Persistent and preview textures have separate caches. Releasing a texture
  invalidates its retained raster draw commands; otherwise cancellation on focus
  loss leaves stale RIDs and can corrupt the displayed transparency.

Godot reference: the installed 4.7 `Input` documentation explicitly recommends
disabling accumulation for freehand drawing. The implementation and native
checks were run with Godot **4.8-beta2**.

## Verification

```sh
xvfb-run -a godot --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_performance_visual.gd
godot --headless --path . --script res://tests/brush_smoke.gd
godot --headless --path . --script res://tests/fill_scope_smoke.gd
```

The native test sends 32 distinct pointer positions between process frames,
continues to 2,049 samples inside one cell, and compares early/late preview CPU
cost. It checks retained samples, input-setting restoration, translucent
preview/commit agreement, holes, camera changes and layer opacity. Its timing
metric excludes display pacing; it is **not** an FPS measurement.

On this machine with Xvfb/Mesa llvmpipe, the initial 1 px/unit implementation
measured around 0.25 ms per ink batch and 1.4 ms per raster batch. With the
owner-requested 4 px/unit painting density (16× the pixel area), current raster
updates remain around 12 ms per 32-sample batch at both ends of the gesture.
Initial whole-path probes had grown from 0.16 to 17 ms for ink outline
generation and 17 to 82 ms for raster painting between 64 and 1,024 samples.
These are local diagnostic measurements, not hardware-independent budgets.

The headless brush suite additionally compares incremental raster sessions
byte-for-byte against whole-path coverage, including self-overlap, paint/erase,
signed chunks, partial images, affine transforms and cell masks. Existing
brush, pen-turn, eraser, continuous-canvas, selection and semantic-shape native
checks cover the surrounding editing and rendering behavior.
