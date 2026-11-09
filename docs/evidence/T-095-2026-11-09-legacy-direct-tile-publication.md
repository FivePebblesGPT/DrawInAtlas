# T-095 — Legacy Brush direct tile-publication checkpoint

**Date:** 2026-11-09
**Status:** Engineering checkpoint only; T-095 In Progress, manual review required.
**Base:** `dc2af79fad5926ce1cddbfc6a05a70afb2a05f4b` (open PR #16, `sprint/2026-11-07`)
**Previous local HEAD:** `61cf597` (unpublished cumulative stack)
**Environment:** Debian Trixie, glibc 2.41, Linux x86_64, Godot
`4.8.beta2.official.cafc17a19`, Xvfb 1280×900, OpenGL compatibility/Mesa.
These are local software-renderer timings, not physical input-to-photon measurements.

## Change and isolation

`DrawingEditSession._stage()` already creates the exact detached
`_preview_tiles` patch and verified `_source_tiles` pointers for each newly
covered pixel. Its existing `_after` string-keyed map is still needed for
rollback/mixed edits, but publishing that map through `DrawingDocument._publish_edit()`
re-splits and reassigns every coordinate. Brush-only sessions now use the
existing `_publish_tile_edit()` instead. Both paths converge on
`_install_prepared_edit()`, which publishes all tiles/dirty regions and one
history entry atomically. The original publisher remains selected as soon
as ordinary `_stage()` or other mixed editing is used. Hokusai keeps its
independently tested native tile-only path. All existing Brush geometry and
RGBA8 source-over semantics remain unchanged.

A separate attempted convex-oblique-scanline implementation passed 500
original-Geometry2D pixel assertions but **regressed** the actual-pointer
staging p95 (127.095→140.514ms in the first comparison). It was reverted and
is **not included** in the submitted source.

## Reproduction

Stage canonical addon code with `python3 tools/build_drawing_app.py --in-place`,
import with pinned Godot 4.8b2, and run:

```bash
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --path drawing \
  --script res://tests/t095_legacy_tile_commit_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' \
  godot --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/brush_latency_native.gd
```

The timing witness delivers five actual mouse-down/120-motion/mouse-up
60px Brush strokes at 7.86× zoom (about 786%) on a new 512×512 image. The
same Godot build, workstation and workload were used for the previous and
optimized versions, with a reversed-order confirmation. Per-stroke data
are retained in the `T095_NATIVE_RUN` lines in local test logs. No
500ms diagnostic ceiling was required to determine this result.

| Software metric (p95) | Original pixel publisher | Direct tile publisher | Comparison |
|---|---:|---:|---|
| Pair A release→commit | 66.306ms | 49.133ms | 25.9% lower |
| Pair A commit CPU | 65.883ms | 48.705ms | 26.1% lower |
| Pair A stage CPU | 127.095ms | 121.522ms | mixed variance |
| Pair B release→commit | 62.757ms | 53.489ms | 14.8% lower |
| Pair B commit CPU | 62.338ms | 53.090ms | 14.8% lower |
| Pair B stage CPU | 118.575ms | 126.792ms | mixed variance |

Five strokes are too few for robust hardware p95 or throughput claims; this
isolates a CPU commit-phase gain, not overall brush catch-up or future
textured-brush viability. Staging and compositor still need profiling on
the owner's physical GPU/driver. In neither configuration does the synthetic
software run supersede the owner's rejection.

## Correctness tests

- **507/507** independent old-vs-new tile commit oracle: Brush/Eraser,
  overlapping batches, four storage strides including irregular 30px,
  ±2³¹ signed anchors, selection holes, clipping and hidden RGB source,
  exact before/after RGBA8 dictionaries, dirty-region maps, detached preview,
  Undo/Redo, stale revision, late invalid offset and replaced source-object
  fail-closed handling. Mixed `fill_rect()` returns to the canonical publisher.
- Existing **32/32** hard-brush source, **86/86** Geometry2D, **4,193/4,193**
  signed source, **126/126** native delta, **56/56** native tile commit,
  **133/133** sparse preview, **422/422** signed tile shift,
  **30/30** native preset, **48/48** post-release navigation,
  **125/125** live-stroke native, **17/17** signed boundary,
  **153/153** viewport cache, and neighboring headless tests passed locally.
- Fresh standalone import **without the native manifest/library** passes
  **507/507** new-oracle and **6/6** Legacy fallback checks. This is a
  first-import test, not an already-imported hot-unplug demonstration.
- The oracle log passes `tools/check_godot_model_log.py` with the exact success
  marker. The on-demand workflow includes the oracle with strict logging.
- An original-publisher negative control exits nonzero: **four assertions
  fail** for invalid tile-local offset rejection and same-byte source-object
  replacement; the optimized publisher passes the complete **507/507** oracle.
  The original publisher was never designed to validate externally tampered
  detached tile patches, so this is a differential guard, not evidence of a
  pre-existing user-facing crash.
- The signed-boundary run still emits known Godot renderer resource-leak
  shutdown diagnostics, so clean engine teardown is not claimed.

## Gates left open

No hosted CI result, owner-device physical input-to-photon measurement,
Windows/macOS export verification, custom stamp support, or explicit owner
approval exists for this checkpoint. T-095 stays **In Progress** with
`manual_review: true`. T-096's independent Manual Review gate is untouched,
and PR #16 must not be merged based on these results.
