# T-095 — Deferred Legacy Brush storage-tile staging

**Date:** 2026-11-09
**Status:** engineering checkpoint; T-095 `In Progress`, `manual_review: true`
**Remote base:** `dc2af79fad5926ce1cddbfc6a05a70afb2a05f4b` (open PR #16)
**Parent local checkpoint:** `9926dd5` (16 earlier commits, not pushed)
**Environment:** Linux x86_64, Debian Trixie/glibc 2.41, pinned Godot
`4.8.beta2.official.cafc17a19`, Xvfb 1280×900×24, Mesa llvmpipe OpenGL
compatibility. Local software-rendered CPU/frame callback metrics only.

## Change and ownership

The existing Brush-only direct tile publisher avoided reparsing canonical
pixel keys **at commit**, but the live `_stage()` path still constructed and
updated `_before`/`_after` string-keyed entries for every successful pixel.
The default swept Brush and Eraser now retain only detached tile-local pixel
patches while capturing. Each batch journals its original patch/coverage
state, so an error after painting earlier pixels can roll back **only** the
failed batch, retaining prior accepted batches. The session counts changed
pixels without allocating global keys. The validated shared tile publisher
still constructs the exact original history on mouse-up.

A mixed `fill_rect()` or public `_stage()` materializes those global maps and
uses the original canonical-key publisher; subsequent Brush work remains on
that fallback for the session. Hokusai retains its separate native staging
logic. A preverified source value still records the canonical source **tile
identity** before publication, preventing an unnoticed same-revision source
replacement. Signed tile arithmetic and straight-alpha RGBA8 are unchanged.

## Tests and reproducibility

Stage the canonical shared addon into standalone Drawing and import Godot:

```sh
python3 tools/build_drawing_app.py --in-place
Godot_v4.8-beta2_linux.x86_64 --headless --editor --path drawing --import --quit
Godot_v4.8-beta2_linux.x86_64 --headless --path drawing \
  --script res://tests/t095_brush_deferred_staging_smoke.gd
Godot_v4.8-beta2_linux.x86_64 --headless --path drawing \
  --script res://tests/t095_legacy_tile_commit_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' \
  Godot_v4.8-beta2_linux.x86_64 --display-driver x11 \
  --rendering-method gl_compatibility --path drawing \
  --script res://tests/brush_latency_native.gd
```

The independent reference session sets `_brush_tile_publish=false` to use
the **previous canonical-key implementation**, rather than sharing the new
deferred branch. The new oracle passes **492/492** checks, across four
storage strides (16, 30, 64, 256), signed >32-bit origins, Brush/Eraser,
three overlapping 60px batches, selection holes, hidden RGB, mixed Fill and
subsequent Brush, preview/commit bytes, exact history and Undo/Redo. It injects
a deliberately missing lazy source chunk partway through a subsequent batch,
checks that the earlier accepted preview is unchanged, removes the fixture,
and successfully retries. Preverified source tile identity is checked against
same-byte source replacement. The updated existing direct-publish oracle
passes **519/519** with additional deferred-state assertions. Hard-brush
coverage, Geometry2D, signed-stage, Hokusai, native preview, navigation and
viewport tests passed locally; the viewport-cache test required regenerating
Godot's imported Lato fonts (initial run failed two font assertions).

A fresh standalone project with the GDExtension manifest and binary removed
**before first import** passes **492/492** and Legacy fallback **6/6**.
This does not establish hot-unplug support in an already imported project.
The on-demand workflow verifies logs strictly; hosted CI was not executed.
The signed-boundary witness still emits the pre-existing Godot shutdown
resource-leak diagnostics; clean engine teardown is not claimed.

## Controlled performance witness

Actual `InputEventMouseButton` down/up and **120** delivered
`InputEventMouseMotion` events per stroke (five strokes, first cold and four
warm), 60px Brush, 7.86× zoom, approximately 512×512 document. Four motions
are delivered per rendered frame. No direct fill was substituted.

| Metric (p95) | Original live string keys | Deferred tile-local | Relative change |
| --- | ---: | ---: | ---: |
| Pair A stage CPU | 125.782 ms | 103.677 ms | 17.6% less |
| Pair A release→commit | 53.721 ms | 46.110 ms | 14.2% less |
| Pair B, reversed order stage CPU | 123.056 ms | 103.476 ms | 15.9% less |
| Pair B release→commit | 56.174 ms | 44.901 ms | 20.1% less |
| Later optimized confirmation stage CPU | — | 109.536 ms | local variance |
| Later optimized confirmation release→commit | — | 45.170 ms | local variance |

Raw `T095_NATIVE_SUMMARY`/per-stroke `T095_NATIVE_RUN` lines were captured
in local `t095-turn16-*.log` benchmark files. The controls were run on the
same machine/build with the immediately preceding committed
`edit_session.gd` temporarily installed only in the **ignored staged**
standalone tree; the canonical optimized source was restored for final tests.
Each five-stroke p95 is the maximum of five values. The benchmark primarily
observes staged CPU work and software-renderer callbacks, **not physical
input-to-photon**. It is too small to claim a stable machine-independent p95
or proof of sufficient future custom-brush headroom.

## Unresolved acceptance gates

The owner's 2026-11-08 negative 60px usability review remains controlling.
No owner hardware input-to-photon measurements, physical GPU/driver evaluation,
hosted CI completion, Windows/macOS export qualification, custom texture
brush implementation, or explicit re-acceptance exist. T-095 remains **In
Progress**, `manual_review: true`. T-096 remains independently in Manual
Review; do not merge PR #16 on this checkpoint alone.
