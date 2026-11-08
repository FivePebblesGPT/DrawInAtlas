# T-095 — cached native fixed-point export (2026-11-09)

**Ticket:** T-095 (`In Progress`, `manual_review: true`). **Branch:**
`sprint/2026-11-07`, building on the locally committed but unpushed T-095
checkpoints after remote `dc2af79`. This is **one** optional Hokusai 0.3.0
GDExtension improvement, not a user-hardware acceptance or a default Brush
change. The owner rejected the prior 60px responsiveness; that verdict stands.

## Identified work and implementation

Hokusai's `TrackedSurface` marks 64×64 native tiles dirty. Previously
`DrawingNativeBrush.preset_segments()` converted all 4,096 fixed-point pixels
in every dirty tile from premultiplied linear channels to straight sRGB8,
then compared the RGBA8 output against the previous export. Even a tiny dab
inside an already populated tile paid the conversion cost for unaffected
pixels, despite the GDScript adapter accepting only changed RGBA8 triples.

The per-stroke `ExportedTile` now retains both 4×u16 native raw channels and
canonical u32 quantized RGBA8 per pixel. A cheap raw equality check skips the
nonlinear conversion for unchanged native pixels. **Only an RGBA8 difference**
updates the exported stream: if native fix15 channels change without crossing
an RGBA8 bucket, no GDScript pixel, preview generation, or Undo state changes.
Conversion arithmetic, output ordering, signed coords, transparent erasure,
`TrackedSurface` dirty ordering and document history remain unchanged. There
is a **32 KiB additional native raw-cache cost per visited 64×64 tile** over
the prior 16 KiB RGBA8 output cache; memory profiling of extremely long
strokes has not been done. The cache is scoped to an active native stroke.

A distinct safety correction validates **all** native input positions and
finite pressure before executing any Hokusai stroke state mutation. Previously
a valid first point followed by NaN could mutate the native surface while
returning an empty delta array, contaminating the following batch. Invalid
inputs now leave both brush and export state unchanged. The existing ABI
still returns an empty array rather than an explicit error object on invalid
inputs; host-level error signaling is a separate compatibility decision.

## Independent correctness and reproduction

- Two native Rust unit tests passed with Cargo 1.99.1 and vendored, locked
  Hokusai 0.3.0/godot-rust 0.5.5. A 32-frame full 4,096-pixel tile reference
  recomputes the original quantized output for every pixel and checks the
  cache's exact delta stream; additional tests cover transparent hidden RGB,
  alpha erasure/reappearance, unchanged frames and native fix15 differences
  within the same 8-bit bucket. `cargo clippy --all-targets -- -D warnings`
  passed offline.
- A **pre-change native binary** emitted batch-delimited SHA-256 streams from
  a deterministic 12×8-point path across signed 64px tile boundaries, with
  pressure 0.7 and 1.0, for all four bundled upstream `.myb` fixtures. The
  optimized Linux library matches all four complete stream hashes and their
  pixel triple counts exactly. The test is
  `drawing/tests/t095_native_export_cache.gd` (**81/81** assertions). It also
  checks for no native state pollution after a valid-then-NaN path or NaN
  pressure. The four full hashes are embedded in the test as frozen old-engine
  golden witnesses; the four pixel counts are 26175, 24032, 20510, 25224.
- `hokusai_bulk_delta_smoke.gd` **126/126**, independent sparse preview
  **133/133**, native preset integration **30/30**, post-release navigation
  **48/48**, hard-brush coverage **32/32**, native live stroke **125/125**,
  signed-boundary native **17/17**, native viewport cache **153/153** after
  fresh font import, native fallback **6/6**, and other selected blend,
  selection and preview-index model tests pass locally.
- An initial `viewport_cache_native.gd` run after standalone staging failed
  two text-font assertions: `build_drawing_app.py --in-place` had removed
  generated `.ttf.import` sidecars. A fresh **Godot editor import** regenerated
  those and the unchanged test passed 153/153. Existing pixel-boundary Godot
  post-exit RID leak warnings remain present; these are not called clean
  shutdown. No hosted CI was executed.

Build/test locally (the supplied archive is **not** committed):

```bash
bash tools/build_native_brush.sh /path/to/extracted/tooling
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --path drawing \
  --script res://tests/t095_native_export_cache.gd
# Then run the graphical brush_latency_native.gd witness with xvfb-run.
```

The fixed-native-output test cannot run on the public on-demand CI job unless
a pinned, platform-compatible native binary is explicitly built from the
supplied vendored toolchain first. It is not silently skipped or reported as
a hosted-CI pass.

## Paired software-only measurements (not device UX)

Same container, Godot `4.8.beta2.official.cafc17a19`, Mesa 25.0.7 llvmpipe,
Xvfb 1280×900×24, 512×512 Drawing image at 786% zoom, 60px Hokusai Brush,
five 120-motion strokes with real Godot pointer press/motion/release and
four motions per frame. The control is the prior tracked Rust source built
**with the same toolchain**; the optimized library was restored and built
immediately after, with no other source changes. All five strokes completed
`T095_NATIVE_PASSED`. `native_us` includes Hokusai rasterization, raw
comparison, conversion and ABI transfer, not GDScript staging or physical
frame delivery.

| Metric | Original Rust exporter | Cached exporter |
|---|---:|---:|
| Native `preset_segments` CPU per-stroke p50 | 28.522 ms | 21.127 ms |
| Native `preset_segments` CPU per-stroke p95 | 35.184 ms | 25.035 ms |
| Full pointer-stroke staging p50 | 222.935 ms | 212.064 ms |
| Full pointer-stroke staging p95 | 237.346 ms | 253.152 ms |
| Release→commit p95 | 80.022 ms | 85.269 ms |
| Dirty exported pigment triples (five strokes) | 114892–117711 | same |

Thus the **native export stage** improved ~26% at p50 and ~29% at p95 in
this paired run. The full brush staging p95 was *worse*, and the reported
release p95 was slightly worse; five strokes under software rendering cannot
support a meaningful full-gesture responsiveness claim. An earlier same
session comparison had full staging p95 223.430→208.396 ms, demonstrating
run-to-run variability. A final same-machine Legacy control staged at
170.117 ms p95, still faster than the cached Hokusai path; renderer CPU,
texture upload, real GPU presentation, sustained custom brushes, and
physical input-to-photon latency remain unresolved.

**Disposition:** Keep Legacy default and Hokusai opt-in. Preserve T-095
`In Progress` and `manual_review: true`; no owner approval has been given.
T-096 remains independently in Manual Review, and PR #16 must not be merged
or treated as hardware accepted.
