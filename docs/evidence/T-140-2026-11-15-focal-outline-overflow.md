# T-140 — focal-first bounded irregular selection outlines

Date: 2026-11-15. **Negative-control source:**
`bd2b6ba3dfa79d84dc3e28aa68a03f10162ce71a` (T-139).
Godot **4.8.beta3.official.c51ff06e8**, Linux Xvfb/Mesa llvmpipe,
1920×1080 window with a 1680×960 Drawing Canvas at **25% zoom**.
These are software-renderer correctness checks, **not physical input-to-photon
measurements**.

## Problem and independent controls

T-139's positive explicit mask index accurately handles up to 4096 occupied
64px outline tiles. With >4096 visible occupied tiles, or with compound or
inverted expressions, the fallback previously filled its 4096 candidate
budget in top-left row-major order. At a wide normal 25% zoom, a real
selected **16×16 pixel** island near the viewport center could remain absent.
A saturated cached contour plan also had no focal-change invalidation if
the clipped selection tile window remained unchanged during a camera pan.

The new fallback visits bounded square-ring perimeters outward from the camera
focus, clamps outside camera coordinates to the visible tile footprint, and
clips every ring to the visible window. Candidate creation and retained
contours stay under the existing **4096-entry** budget, with at most **four
new contours per frame**. When a capped candidate plan has a new focal tile
but unchanged viewport tile window, it invalidates the prior saturated cache.
The existing below-cap exact positive-mask indexing and
`DrawingSelection.contour_segments()`/`allows()` remain unchanged.

**Unchanged T-139 control:** The same new headless oracle exits nonzero with
**8/17 failed** assertions (focal coverage, camera clamping, skinny footprint,
compound/inverted focus). The native X11 oracle exits nonzero with **5/9
failed**, including missing actual center-framebuffer change and a simulated
saturated cache stranded after an in-window pan. The temporary baseline
`canvas.gd` was staged only into the generated `drawing/addons/drawing`
consumer and restored by the canonical builder afterward; the source checkout
was never modified by the negative controls.

**Candidate:** Headless **17/17** and native X11 **9/9**, strict-process-exit
and log checks passed. The native framebuffer changed **28 pixels** near the
center selection island when the mask was cleared. Panning 128 source pixels
inside a selection wholly within the viewport retained the same contour tile
window, and replaced a deliberately saturated 4096-entry cache with just
**four current-frame contour tiles**, including the new focus. The 16×16
island is selected under a real explicit pixel mask containing >4096 distinct
occupied tiles. No raster layer, revision, or Undo history was mutated.

## Reproduction

Build/import the pinned canonical standalone package before source or native
checks; running without Godot's SVG icon import emits real loader errors and
is **not** counted as passing:

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t140_focal_mask_overflow_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t140_focal_mask_overflow_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T140_OUTLINE_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T140_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t140_focal_selection_outline.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

## Neighboring evidence

| Scope | Result |
| --- | --- |
| T-139 sparse outline model / native | **14/14** / **7/7** |
| T-088 selection/clipboard headless / native | **131/131** / **51/51** |
| T-088 sparse Paste / sparse Capture | **56/56** / **54/54** |
| T-096 large selection/Move headless / native | **13,847/13,847** / **34/34** |
| Clean native-absent standalone Drawing consumer | **42/42** |
| Python source/CI contracts, T-139 + T-140 | **6/6** |
| Explicit typing | **454 GDScript files, 33 skill documents** |
| Canonical dependency/manual-gate validator | **140 tickets valid** |
| Fast required CI step inventory | **46 unique IDs (unchanged)** |

[Raw before/after and neighboring logs](t140-outline-logs/) and
[SHA-256 manifest](T-140-2026-11-15-focal-outline-overflow-logs.json)
retain actual diagnostic lines. The independent consumer's recognized
post-success RID/texture leak diagnostics are preserved and categorized by
the strict model-log checker, not suppressed.

## Boundaries

Over-budget contours still prioritize only 4096 tiles and may omit remote
peripheral outlines; this ticket changes *which tiles get traced first*, not
mask truth, contour geometry, total image dimensions, or selection policy.
It does not benchmark dense selection throughput or confirm the physical
owner's selection/Move UX. The parent T-088 stays In Progress; T-096 remains
Manual Review. Hosted GitHub CI was not run on this unpushed source, and
physical Windows/Linux approval is not inferred.
