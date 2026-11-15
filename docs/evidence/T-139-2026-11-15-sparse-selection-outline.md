# T-139 — sparse explicit pixel-mask outline traversal

Date: 2026-11-15. Source baseline: `7573db31af75d9684ba9067dc005022b9d93896b` (T-138).
Godot **4.8.beta3.official.c51ff06e8**, Linux Xvfb/Mesa llvmpipe
software renderer; not a physical desktop, touch device, or input-to-photon
measurement.

## Defect, bounded fix and exact scope

The Canvas's irregular selection display traced 64px contour tiles in
row-major order across the entire visible **bounding rectangle**, even when
`DrawingSelection._pixel_mask` authorized just a few pixels. The 4096-tile
cache and four-new-tiles-per-frame cap could be consumed by entirely empty
regions while an actual positive/signed selected island at the far side
never appeared. The positive, operation-free explicit mask now derives
bounded candidate tiles directly from its `true` pixel entries within the
selection's base rectangle and the current screen footprint. False/outside
pixels create no contour work. Candidate ordering is deterministic; the
underlying exact `contour_segments()` and source selection are unchanged.

Inverted masks, compound boolean operations, or more than 4096 distinct
occupied contour tiles retain conservative row-major traversal, with the
fallback work list capped at 4096 tiles per draw. The cache and four-per-frame
budget remain; this does not claim full outline coverage for enormous
compound selections, merely no further regression for their previous mode.

## Red and green evidence

The native witness uses a 1920×1080 software window, 1680×960 Canvas at
**25% zoom**, with a positive explicit mask spanning roughly 8000×5200
source pixels and two separated **16×16** true islands at signed (-2800,
-1400) and (2900, 1500). The islands yield two distinct 64px contour
cells; the small but nontrivial rectangles are intentionally wide enough
to be visible in the native framebuffer at quarter zoom.

The unchanged T-138 `canvas.gd` was temporarily staged *only* into the
standalone test package, leaving the canonical source untouched. On the
same 7-check native script, it exits nonzero, failing **6/7** checks:
far/island cache coverage, actual framebuffer change, and bounded re-entry.
The corrected Canvas passes **7/7** with framebuffer-pixel differences for
both distant islands (28 changed pixels in each local sampling region), no
canonical source revision/content mutation, and repeatable re-entry.
The headless model passes **14/14**: signed and far-right islands, false and
out-of-bounds points, viewport clipping, deterministic order, inverted and
compound fallback, >4096-tile index overflow, empty footprint, and
unchanged selection truth.

Reproduce after importing the pinned standalone app:

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t139_sparse_selection_outline_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t139_sparse_selection_outline_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T139_OUTLINE_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T139_NATIVE_PASSED
```

The raw [logs](t139-sparse-outline-logs/) and [SHA-256 manifest](T-139-2026-11-15-sparse-selection-outline-logs.json)
record the baseline and focused/neighboring runs. The ordinary T-088
selection model **131/131**, sparse paste **56/56**, sparse capture **54/54**,
and X11 pointer/clipboard **51/51** all pass. The existing T-096
large-selection oracle passes **13,847/13,847**, and its native pointer,
Move and outline witness passes **34/34**. A freshly staged **native-absent**
standalone Drawing consumer imports and passes **42/42**. Its four known
post-exit RID diagnostics remain visible and are accepted only by the strict
post-success checker. Selection/camera metadata updates continue using the
canonical setters; no saved files are mutated.

## Limits

No comparable physical Windows/Linux hardware, pen/stylus, dense-mask
benchmark, owner-facing UX acceptance or hosted green GitHub workflow was
obtained. The native framebuffer numbers are software-rendered correctness
checks, not a p50/p95 performance measurement. T-088 remains In Progress,
T-096 remains Manual Review, and no manual gates were self-approved.
