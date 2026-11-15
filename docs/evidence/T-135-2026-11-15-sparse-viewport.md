# T-135 — bounded committed sparse viewport traversal

Date: 2026-11-15 · branch `sprint/2026-11-14` · pinned Godot
`4.8.beta3.official.c51ff06e8` · Linux x86-64 · Mesa 25.0.7 llvmpipe
in Xvfb OpenGL Compatibility · software CPU/render submission only.

## Reproduction and exact negative control

The T-134 `addons/drawing/canvas.gd` draws the visible source rectangle with
nested row/column loops. It skips unoccupied tiles *inside* the loop, but
still formats a string key and queries the occupancy dictionary for **all
120,701** visible display cells in the two-tile synthetic test. Cached draws
therefore performed no raster work yet consumed over 100ms on this runner.

Baseline commit `4eae8bb43e223d22dbe58a10f40e335b2d881ee3`. Its exact
Canvas source SHA-256 and the candidate Canvas SHA-256 are recorded in the
[measurement manifest](T-135-2026-11-15-sparse-viewport-results.json).
A separate detached Git worktree was checked out at this commit. The pinned
Lato font files were copied from the same supplied toolchain snapshot because
Git LFS smudging was unavailable; a real Godot import then ran successfully.
The only nonbaseline file in its standalone test stage was the identical
new `t135_sparse_draw_native.gd` witness. The baseline produced **4/23
assertion failures**, including absence of indexed traversal, lack of a
bounded visited-cell count, and failure of its conservative-path telemetry.
Source/framebuffer parity assertions still passed. Exit 1 is expected.

## Change and correctness boundary

`DrawingCanvas._sparse_visible_draw_rows()` uses the *existing* complete
occupancy index after `_sync_display_cache()` to select and sort only visible
occupied display cells. Integer and canonical tile-key validation rejects
malformed or alias-prone entries and uses the original full scan instead.
Detached Brush/Move previews, incomplete/unknown occupancy, and relatively
dense views **always** use the original full traversal. Full-window
`tiles_visible` versus actually visited `tiles_examined` and `sparse_draw`
telemetry are distinct. The same image composition, cache, cold-budget, dirty
invalidation, texture submission and overlays are retained. The document and
storage formats, alpha math, cache limit and Undo semantics are unchanged.

The **16/16 headless** oracle tests signed row/column ordering, inclusive and
exclusive view edges, empty indexed views, the fallback on dense/preview,
unknown, malformed, nonnumeric or noncanonical hints. The **23/23 native X11**
witness tests actual red/blue signed/framebuffer pixels, 1% zoom, two source
tiles visited among 120,701 visible cells, seven warm draw phases, 144-tile
retention cap, one-pixel revision/Undo/Redo, unknown occupancy and visibility
change invalidation. It uses a 512×384 canvas in an 820×610 Xvfb window;
this 1% programmatic zoom is deliberately outside the normal wheel's 25%
minimum, to isolate empty-cell traversal overhead. It is not a typical
end-user workload.

## Exact commands and artifacts

```sh
python3 tools/build_drawing_app.py --in-place
# Re-import after rebuilding to ensure the canonical Lato font is usable:
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t135_sparse_draw_model.gd
xvfb-run -a godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t135_sparse_draw_native.gd
python3 tools/check_godot_model_log.py /path/to/model.log \
  --marker T135_SPARSE_PASSED
python3 tools/check_godot_model_log.py /path/to/native.log \
  --marker T135_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t135_sparse_viewport.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

The three native candidate runs and three baseline control runs all use the
same test, engine, framebuffer size, zoom, source pixels and 7-frame sample
series. Each run's complete stdout/stderr, SHA-256, ordered seven samples,
p50 and p95 is retained in the [raw log directory](t135-sparse-viewport-logs/)
and the [JSON manifest](T-135-2026-11-15-sparse-viewport-results.json).
These are per-Canvas-`_draw()` CPU times, **not** wall-frame cadence or
physical input-to-photon timing.

| Seven-sample run p50 (ms) | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Unmodified T-134 baseline | 104.884 | 107.058 | 107.656 |
| T-135 indexed candidate | 0.088 | 0.070 | 0.078 |

Candidate 7-sample p95 values were **0.143, 0.076, 0.207 ms**, and baseline
p95 values were **116.514, 121.046, 200.112 ms**. The strong gain is
specific to an intentionally very wide *mostly empty* viewport. Trial
outliers and CPU scheduling may differ elsewhere. This is not proof of dense
viewport, cold-composite or normal 25% zoom performance on owner hardware.

The 16-check headless and 23-check native candidate tests return exit 0.
Python source/CI contracts pass 3/3. An existing **153-check T-086 native
software framebuffer** witness passes after fresh font import; an earlier
unreimported run failed two glyph-resource assertions solely because its
font loader could not read an unimported resource. No application change was
made for that environment issue. Eleven neighboring headless viewport,
preview, sparse-renderer and cold scheduling suites pass. The independent
native-absent standalone consumer was built/imported and passes its Drawing
smoke test with a strict log check. The existing 46 required CI check IDs
remain unchanged. The on-demand native workflow now checks T-135 and retains
its full log; a *hosted* run has not been observed.

Known renderer/RID resource-leak diagnostics after successful Godot tests
remain in raw logs. They are not suppressed, nor treated as unrelated runtime
errors. No physical Windows/Linux hardware, owner approval, real GPU scanout,
input-to-photon latency, or T-086/T-095 closure is claimed.
