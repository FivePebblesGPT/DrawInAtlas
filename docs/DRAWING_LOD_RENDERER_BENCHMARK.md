# T-057 — Atlas renderer / derived display LOD feasibility decision

**Measured 2026-11-03:** Debian 13 Linux x86_64, virtual Intel Xeon Platinum 8573C, Godot **4.8.beta2 official `cafc17a19`**, Mesa 25.0.7 llvmpipe (OpenGL Compatibility), Xvfb 1280×900. This is a **software-GL benchmark**, not a representative hardware-GPU frame rate or a Windows validation. No new renderer dependency was adopted. The measured prototype does **not** modify the production renderer.

## Reproduce

From the repository root with the pinned engine on PATH:

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/t057_lod_headless.gd -- --output /tmp/t057-headless.json
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t057_lod_native.gd -- --output /tmp/t057-native.json
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/drawing_raster_upload_benchmark.gd -- --output /tmp/t057-upload.json
```

Raw results: [headless stride/cache/fidelity](benchmarks/T057_2026-11-03_headless.json), [native pan/zoom/memory](benchmarks/T057_2026-11-03_native.json), [full-tile upload](benchmarks/T057_2026-11-03_upload.json). The tests emit explicit `*_PASSED` markers and nonzero exit codes on failures. All results are from one sandbox; run the scripts on real Windows/Linux GPUs before relying on their absolute timings.

## Decision

**Retain Godot's rendering backend.** Incrementally prototype a **bounded, revision-aware display-tile cache** and only later a lazy derived-LOD pyramid, independent of canonical source tiles and independent of authored D0/D1/D2 detail switching. Do **not** adopt libvips or MapLibre Native for interactive display on current evidence. Native/GDExtension editing performance is separately owned by T-068, not by this study. No production cache was deployed by T-057; any integration should receive a distinct implementation ticket with real framebuffer/fidelity tests.

The present Atlas pipeline composites bounded source regions with `AtlasDrawingComposition.render_region()`; that adapter already has an image result cache with a 96-frame limit. However, `AtlasCanvas._draw_canonical_composition()` allocates **new `ImageTexture` objects on each redraw**, and drops rendering entirely if the visible source extent exceeds a 4,096-pixel axis / 2,097,152-pixel budget. A production display cache would need to retain actual texture resources, handle revision/LOD invalidation and display-driver memory pressure, not just cache CPU images. The source tile stride (256–2048), display update tile (64/128/256) and authored D-level must remain **three independent dimensions**.

## Controlled Godot comparison — CPU source frames

`tests/t057_lod_headless.gd` creates exactly the same visible 80×80 patterned RGBA8 content in two sparse Drawing raster layers at all four document storage strides. Seed rectangles deliberately cross signed tile boundaries at 64-bit world anchors beyond ±2⁵³. Sixteen repeated viewport pans cover a 128×96 display window using 64×64 display blocks; each run does the same pixel hashing, source layer compositing and camera path. Exact viewport-cache entries are keyed by **document revision and signed integer tile coordinates**. There were 88 requested blocks, 80 hits and 8 cold misses in each candidate run. All 16 frame signatures match the uncached reference; a subsequent one-pixel published edit invalidates the revision key, and the refreshed view again matches uncached bytes. The candidate caches at most 8 × 16 KiB for the pan sequence (196,608 B counted after the edit's new-revision misses).

| Canonical tile stride | Uncached CPU median / p95 | Exact-cache CPU median / p95 | Reused / cold tile samples |
| ---: | ---: | ---: | ---: |
| 256 | 34.258 / 42.277 ms | 0.105 / 30.864 ms | 80 / 8 |
| 512 | 32.330 / 42.205 ms | 0.112 / 26.082 ms | 80 / 8 |
| 1024 | 39.538 / 62.445 ms | 0.104 / 31.216 ms | 80 / 8 |
| 2048 | 35.052 / 58.658 ms | 0.154 / 45.085 ms | 80 / 8 |

**Interpretation:** repeated, unchanged view regions are amenable to caching; **the 0.1-ms hit path is not a production end-to-end speedup**. The test bypasses GPU resource creation and render-thread queueing, uses warmed repeated tiles, and still has visible cold-miss p95 spikes. It does not time multi-gigapixel authored maps, cache eviction, user pointer events, text/vector-heavy scenes, or a real texture-streaming scheduler. Rendered work stays bounded by the viewport rather than entire sparse-world extent; CPU timings here are not monotonically related to canonical storage stride. See T-067 for storage size/codec tests and T-068 for edits/compositor CPU tests.

### Downsampled display LOD fidelity

A 128×128 composited RGBA8 view was reduced to 64×64 and expanded to 128×128. Against exact source, nearest-neighbor had mean **28.015 / 255 per RGBA channel**, including mean alpha error **24.420 / 255**; bilinear had mean **25.720**, with alpha error **28.242**. Both changed visible bytes (same values at all strides, since source pixels are held constant). These intentionally high-frequency patterns show that a derived pyramid is **lossy**, even when canonical pixels and hidden RGB are preserved in the DrawingDocument. Choose filter, premultiplication/alpha treatment and threshold based on actual zoom/shape/text content, test transparency halos, and retain exact data for saves/edits. Downsampling must never create or substitute a different *authored* D-level.

## Native Atlas pan/zoom and GPU update evidence

`tests/t057_lod_native.gd` drives a real Atlas canvas composed through the canonical Drawing engine. A mouse event paints one visible D0 stroke and increments the document revision. It verifies that an unpainted D1 document is fully transparent and switching back does not retarget D0. Twenty-one native `RenderingServer.frame_post_draw` pan frames alternate zoom factors 4×/6×/8×. On Xvfb/Mesa they took **14.822 ms median, 24.558 ms p95, 26.568 ms maximum** from camera change to the submission signal. This is **not** hardware event-to-photons latency; renderer setup, compositor, scheduling and software frame timing are mixed.

Sampled peak Godot static-memory monitor: **97,972,970 bytes (~93.4 MiB)**; renderer-reported video-memory peak **11,479,179 bytes (~10.9 MiB)**, of which renderer-reported texture usage peaked at **5,053,187 bytes**. These are sampling/engine counters under llvmpipe, **not physical GPU VRAM** or a process peak RSS guarantee. Actual GPU VRAM peaks on Windows/Linux hardware remain unverified.

The standalone existing upload microbenchmark `tests/drawing_raster_upload_benchmark.gd` times a full `ImageTexture.update()` with the same sized RGBA8 image under software GL. The Godot API replaces the entire texture, even when only a small region was edited; it does not provide subrectangle uploading through that method. This machine measured full-texture update medians of **0.027 / 0.032 / 0.080 / 0.318 ms** at 128 / 256 / 512 / 1024 display tile sides, respectively (RGBA8 upload sizes 64 KiB / 256 KiB / 1 MiB / 4 MiB); the respective p95 values were **0.136 / 0.070 / 0.238 / 0.347 ms**. These are function-call microbenchmarks, not frame-presentation costs. The raw T-057 upload JSON retains complete observations. Display-tile sizing is therefore a separate tradeoff: smaller tiles reduce bytes per dirty change but increase texture/draw-call count; source stride must not be chosen to optimize a full-texture upload accidentally.

### Large signed coordinate precision

The `DrawingDocument`+`DrawingRenderer` read path correctly handles positive and negative **int64 tile anchors beyond 2⁵³** without float conversion; all exact-cache parity and seam checks passed. The **Atlas `Vector2` camera does not guarantee the same precision**. Native camera-relative tests at ±1,048,576 world units preserved an 8×/−4× local translation, but `Vector2(2²⁴, -2²⁴)` and `Vector2(2²⁴+1, -2²⁴-1)` compare equal on this default single-precision build. At very large world coordinates, current `AtlasCanvas` camera mapping cannot pan/edit in one-unit increments. This is a documented precision limit, **not** a passed huge-world navigation claim. A future renderer implementation must introduce a high-precision integer anchor plus bounded floating local offset (or an equivalent floating-origin scheme) and test camera mapping, hit-testing and save/reload together.

## Candidate and licensing evaluation (no third-party speedups claimed)

- **Godot bounded exact display cache / derived tile pyramid:** directly benchmarked prototype, no additional runtime license/binary. Prefer this first; retain canonical source revisions and avoid CPU/GPU cache disagreement. Add LRU/dirty-region invalidation and real texture retention as an explicit next step.
- **libvips:** [demand-driven tiled image processing](https://github.com/libvips/libvips) and [DeepZoom pyramid generation](https://www.libvips.org/API/current/making-image-pyramids.html) are suitable for **offline/batch pyramid generation** from bounded, already-rendered artwork. Licensed **LGPL-2.1-or-later** (dynamic/static distribution obligations differ). It is not an in-app GPU presenter, cannot select authored D-levels, and a mutable signed sparse world would need an export, invalidation scheduler, FFI and deployable pinned binaries. No libvips executable or linked build was benchmarked here, so there is no evidence it accelerates live Atlas edits.
- **MapLibre Native:** [BSD-2-Clause](https://github.com/maplibre/maplibre-native), built to render styled geographic vector/raster map tiles. Atlas here uses editable Godot-native artwork, not MapLibre-style geographic tile sources; substituting it would duplicate camera, inputs, selection, authored-detail and render integration. **Reject for this workload** without a prototype, not a claim about its general speed.
- **Narrow native GPU or C++ backend:** neither a compiled Godot graphics extension nor a cross-platform hardware comparison exists. T-068 evaluates bounded CPU editing and texture upload separately. Adopting a renderer is unjustified until it wins reproducibly on the actual visible/edit path and passes standalone Drawing and Windows/Linux exports.

## Test and decision boundaries

Godot headless checks: **249/249** when exporting JSON (**248/248** without `--output`), native checks **36/36**, 4/4 upload cases, and existing related LOD/composition contracts rerun as recorded in T-057. These are targeted engineering measurements, not owner UX approval of Drawing. This ticket's deliverable is an evidence-backed **retain-Godot decision**; it changes no source files, pixel format, persistent save schema or runtime dependencies. Deploying a cache, precision fix, GPU-specific backend or independently testing Windows are implementation/release-stage work, not untested features masquerading as completed research.
