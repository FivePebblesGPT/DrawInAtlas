# T-068 — Drawing edit-to-visible CPU rasterization and compositing study

**Measured 2026-11-02 on a Linux x86_64 sandbox, Godot 4.8.beta2, G++ 14.2, Mesa llvmpipe 25.0.7.** Engineering evidence only. No native backend has been selected, linked into Godot, exported to Windows, or shipped. T-068 remains **In Progress** because the full gate requires actual third-party CPU raster runs, input-event-to-present profiling, native extension boundary, and multi-thread/Windows memory-jitter evidence. This is not an owner-review gate.

## Reproduction

From the repository root, with `godot`, `g++` and Python 3 installed:

```sh
python3 -m unittest discover -s tests -p 'test_t068_kernel.py' -v
godot --headless --path . --script res://tests/drawing_raster_backend_benchmark.gd -- --output /tmp/t068-godot.json
python3 tools/benchmarks/t068_native.py --build-dir /tmp/t068-native --godot-vectors /tmp/t068-godot.json --output /tmp/t068-native.json
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --display-driver x11 --audio-driver Dummy --rendering-method gl_compatibility --path . --script res://tests/drawing_latency_visual.gd -- --output /tmp/t068-frame.json
xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/drawing_raster_upload_benchmark.gd -- --output /tmp/t068-upload.json
```

[Godot source measurements, workload timings, 128 exact blend vectors and signed-world native fixture](benchmarks/T068_2026-11-02_godot.json) · [C++ bounded batch and FFI microbenchmarks](benchmarks/T068_2026-11-02_native.json) · [software-GL upload observations](benchmarks/T068_2026-11-02_upload.json)

A clean source import of both Atlas and staged Drawing and the existing regression suites are required before merging the renderer improvement. `tests/drawing_raster_backend_benchmark.gd` contains the **unaltered legacy per-pixel compositor** exclusively as an independent byte oracle; the application no longer calls it. The production `DrawingRenderer` now processes signed, horizontally contiguous tile runs with one lazy-chunk lookup per run. Its failure propagation remains intact, and it does **not** convert large camera anchors into 32-bit `Vector2i` or floating-point world addresses.

## Directly comparable native-Godot CPU measurements (A vs B)

**Two visible raster layers**, 96×96 RGBA8 viewport, five alternating in-tile/boundary positions, exact same document and pixels. `median/p95` measured with `Time.get_ticks_usec()`. These include Godot's source lookups and CPU composition but not GPU upload, event dispatch, or draw presentation.

| Saved document stride | A: original renderer median / p95 | B: tile-run renderer median / p95 | Median speedup |
|---:|---:|---:|---:|
| 512 | 95.692 / 99.060 ms | 6.096 / 6.317 ms | 15.7× |
| 1024 | 96.077 / 96.695 ms | 5.989 / 6.101 ms | 16.0× |
| 2048 | 94.966 / 96.127 ms | 5.995 / 6.239 ms | 15.8× |

**Result:** retain and deploy B for raster-only CPU viewport compositing. The full Godot experiment passed **691 assertions in the latest rerun**, including byte-identical source-over composition (even around negative tile seams beyond 2⁵³), correct local painting, erasure, masks, source revision conflict, cancellation, local undo/redo, and a 24-pixel signed-origin parity fixture. The renderer remains read-only. Transparent *source* RGB does not overwrite the visible destination; untouched stored straight-RGBA8 source bytes remain exact. Text is still delegated to the existing text rasterizer with the same layer order.

A 512-stride **GDScript complete edit+commit+undo+redo** median: short swept 4px brush 1.625 ms; 64px round brush 115.117 ms; fast 216px stroke 39.432 ms; self-cross 1.205 ms; erase 1.945 ms; masked stroke 4.809 ms. This is **not** a pure raster inner-loop timer or end-to-end input-to-present. Brush coverages/delta sizes are recorded in the JSON. They are primarily sensitive to candidate scans and per-pixel dictionaries, not sparse storage stride (the same test at 1024/2048 shows similar timings). Large brushes and fills remain optimization targets.

## Isolated native C++ candidate C (not yet GDExtension)

`tools/benchmarks/t068_raster_kernel.cpp` builds as a local shared library; Python `ctypes` calls it in a separate process. Its **bounded batch** receives view-relative pixel coordinates, an optional byte mask, RGBA8 source, operation and delta capacity; it publishes into detached output only after all validation. Overlapping samples blend once. Tests cover 3,000 seeded alpha cases, hidden RGB, exact changed-pixel rounding, erase, direct copy, mask, insufficient capacity and invalid coordinates. `draw_source_over` matched **128 Godot-rendered RGBA8 blend vectors**, and the batch exactly reproduced a real 24-pixel Godot gesture in a signed-world document. These are **correctness comparisons**, not claims that Python's FFI approximates Godot's GDExtension marshaling.

| C++ dirty edit region | 4px dab / 128 precovered pixels | 64px round / 3,228 pixels | 4px long sweep | Rectangle fill |
|---:|---:|---:|---:|---:|
| 128×128 (64 KiB) | 0.0076 ms | 0.0894 ms | 0.0144 ms | 0.2461 ms |
| 256×256 (256 KiB) | 0.0166 ms | 0.0980 ms | 0.0367 ms | 1.3547 ms |
| 512×512 (1 MiB) | 0.0528 ms | 0.1352 ms | 0.1011 ms | 6.3410 ms |

Medians over seven hot kernel calls; all outputs identical to canonical straight RGBA8 for supported operations. The C++ kernel is **scalar**, not an implemented SIMD acceleration path. Candidates were precovered in Python; geometry scanning, source-change validation, native↔Godot conversion, undo publication, GPU upload and real UI are *not included*. The benchmark's no-op Python `ctypes` dispatch median/p95 was **1.332/1.423 µs**, which must **not** be called a Godot extension crossing. Changed-pixel deltas use a 12-byte `index/before/after` struct (uncompressed), e.g. 1,536 bytes for 128 changed pixels; the entire 128/256/512 backing region is copied regardless of changed area. This establishes an upper-bound copy problem rather than a ready-to-ship backend. Native code is an optional unlinked prototype, not a fork of Drawing.

**Recorded process high-water marks** (`/usr/bin/time -f %M`): 158,484 KiB for the full Godot benchmark process and 128,648 KiB for the Python+native benchmark. These are **per-process** peak RSS values including engine/Python/runtime overhead, not isolated tile allocations or comparable engine-native benchmarks. The 512×512 RGBA8 buffer is 1 MiB, 256×256 is 256 KiB, and 128×128 is 64 KiB. `var_to_bytes([before,after])` is used as a consistent **undo wire-size proxy**, not a heap estimate; 64px round strokes reached ~347 KiB per gesture in this session. No GPU VRAM profiler was available.

## Texture publication is a separate, full-update bottleneck

The [Godot ImageTexture API](https://docs.godotengine.org/en/stable/classes/class_imagetexture.html) defines `update()` as **replacing the texture's complete data**, not uploading an arbitrary subrectangle. An independent 128/256/512/1024 test under software OpenGL 4.5 (Mesa llvmpipe) produced these upload-only medians: **0.014 / 0.017 / 0.044 / 0.168 ms**, with complete RGBA8 upload sizes 0.0625 / 0.25 / 1 / 4 MiB. `RenderingServer.force_draw()` medians were around 2 ms, but this is a driver/queue probe, **not an input-to-visible frame timestamp**. Independent 128/256 edit-display tiles can reduce full-upload work relative to 512/1024 storage tiles. Do not conflate compressed storage stride, dirty edit regions, or display-upload geometry.

## Operation-by-operation candidate screening

| Operation | A/B Godot | C++ prototype | Blend2D D | Skia CPU E | Decision today |
|---|---|---|---|---|---|
| Existing once-covered hard brush, exact straight-RGBA8 | Reference behavior, measured | Masked per-pixel batch verified; native path geometry not implemented | Premultiplied format conversion / rounding parity **not established**; no runnable dependency | Same unresolved exact-byte bridge | Keep GDScript; prototype narrow native batch further for large gestures |
| Erase, bounded fill, touched-region COW, compact undo | Functional and regression-tested; large fill slow | Exact replace/erase/mask and compact deltas verified, but region copied fully | Not a complete undo/document store | Not a complete undo/document store | Optimize bounded native buffers and touched-region COW first |
| Visible multi-layer CPU composite | B is measured ~16× A | No compiled compositing integration | CPU compositor feasible; output parity unknown | CPU compositor feasible; output parity unknown | **Ship B**, no external renderer |
| Vector paths, Béziers, antialias, complex blend | Separate existing tool contracts | Unsupported by simple hard-pixel prototype | Candidate when quality/workload requirements justify it | Candidate if paths/text/filters warrant heavier dependency | Defer new engine; performance **not measured** |
| Natural brush dynamics, pressure/tilt | Not this hard-brush benchmark | Unsupported | Limited natural-media brush semantics | No libmypaint equivalence assumed | Evaluate **libmypaint** separately only if feature scope demands |

External dependencies were **not fetched, built or timed**: no Blend2D, Skia or libmypaint development packages were available on this machine, and source download failed due DNS/network access. Thus **there is no honest D/E p95 speedup, binary-size, conversion-cost, exact output parity, or release compatibility result**. Capability/licensing screening is not an execution benchmark. Blend2D [zlib licensing / AsmJit requirement and release pin hashes](https://blend2d.com/download.html), candidate version **0.21.2**, source SHA **`def0d1238c3e5d0983bb848e5676049d829e435b`**; Skia [BSD 3-Clause](https://github.com/google/skia/blob/main/LICENSE) with GN and extensive optional build dependencies; libmypaint [ISC and json-c](https://github.com/mypaint/libmypaint/blob/master/README.md). No external code or binaries were copied into the monorepo. Windows builds and all third-party versions would require actual validated dependency locking before acceptance.


## Regression and legacy compatibility evidence

- Final Godot import/explicit-type validation passed; T-055 composition **89** checks, T-061 world mapping **125**, Drawing history **101**, T-060 Object Assets **95**, Object Editor **45**, editable Drawing text **60**, T-066 bundle persistence **84** and editor Save/Load **23**, artwork **171**, and legacy storage **77** all passed.
- The independent Drawing build imported from a clean staged directory and passed its **38-check** standalone witness; Linux `Drawing.x86_64` and `.pck` exported successfully. The Godot benchmark passed **691 checks in the latest rerun** with JSON output; C++ kernel Python unit tests passed **6** and cross-runtime parity passed.
- The old `tests/text_smoke.gd` reports **two failures** because it still asserts that the editor saves via `AtlasCampaignStore.load_campaign()` from a legacy single `.scn` path. The identical failures were reproduced by running the unmodified **`9c64138`** baseline code in a separately imported checkout. This is a **pre-existing compatibility debt**, not a new regression, and is not silently corrected under this research ticket.
- This delivery's CPU renderer change is **not** T-067's production stride change or T-057's derived LOD. No new backend is enabled, and no existing persistent formats were changed.

## Remaining mandatory T-068 acceptance work

1. Build/run pinned Blend2D CPU and Skia CPU comparators on eligible path/shape and compositing workloads; document exact premultiplied↔straight-byte conversions and unchanged hidden-RGB preservation. libmypaint only if natural brush support enters Essential scope.
2. Prototype a **versioned optional GDExtension** (no Atlas references), pass bounded region batches and measure real marshal+conversion overhead, source revision conflicts, output dirty rectangles and main-thread publication. Explicitly measure SIMD vs scalar only once compiled; the existing C++ prototype does not implement SIMD.
3. Measure real pointer-event → CPU stage → main-thread texture update → displayed-frame latency median/p95, plus RAM/VRAM peaks and multi-thread jitter on Windows and Linux (including non-software GPUs). Test large brush, shape/flood, transformed four-corner masks, multiple layers and rapid cancel/undo under controlled loads.
4. Prove the native module optionality and independent standalone Drawing release on both desktop targets. Do **not** select or ship a native library until verified repeatable wins outweigh the additional binary, license and update burden.

**Interim recommendation:** keep the canonical tile-run renderer improvement; keep Godot as the reliable edit backend. Prefer tuning candidate window traversal, packed visited masks, dirty-region copy-on-write and concise deltas before introducing a native extension. Preserve exact canonical RGBA8/hidden RGB and the one-hit-per-gesture brush contract. The T-067 512px *future storage default* decision is independent and is not implemented here.

## Second T-068 checkpoint: sparse-native deltas and real framebuffer events

**Still In Progress; no native dependency adopted.** The initial isolated native
candidate now has a *versioned, unintegrated C ABI* (`draw_kernel_abi_version() == 1`)
and a separate `draw_batch_deltas` call. It returns the same ordered, exact
straight-RGBA8 `{pixel index, before, after}` values as `draw_batch`, **without
allocating or copying the full region-sized output**. A one-bit-per-pixel coverage
map replaces the prior byte-per-pixel visited array. The legacy full-output API
is preserved for parity and only copies after validating all candidates/capacity.

[Native delta-only microbenchmarks (15 cases)](benchmarks/T068_2026-11-02_native_delta.json)
were measured using the same precovered coordinates, G++ `-O3`, 11 hot iterations with alternating call order after four warmups,
and a Python `ctypes` caller (not Godot). Representative medians in milliseconds:

| Dirty region and coverage | Full region output | Delta-only native | Changed pixels | Full-output copy avoided |
|---|---:|---:|---:|---:|
| 128×128, short hard brush | 0.0063 | 0.0050 | 128 | 64 KiB |
| 256×256, short hard brush | 0.0099 | 0.0050 | 128 | 256 KiB |
| 512×512, short hard brush | 0.0279 | 0.0058 | 128 | 1 MiB |
| 512×512, large fill | 6.1873 | 6.0571 | 230,400 | 1 MiB |

The speedup is for **candidate enumeration only**: applying deltas to immutable
source tiles, validating a DrawingDocument revision, Godot↔native marshalling,
GPU upload, and an actual global-history commit are **not included**. A large
fill is not materially faster; changed-pixel processing dominates. The C++
prototype has no SIMD implementation, no GDExtension binding and no runtime
connection to Drawing or Atlas. An unchanged 2048×2048 RGBA8 source is 16 MiB:
the native delta call allocates a 512 KiB visited bitset plus up to the caller's
changed-pixel deltas, rather than also copying a second 16 MiB output buffer.
Memory figures are algorithmic allocation bounds, **not measured peak RSS**.

The expanded native unit suite passed **10 tests**, including all three edit
operations with masks and overlapping points, zero-alpha hidden-RGB behavior,
byte parity between APIs, 2048×2048 two-pixel edits, stale-data rejection
in the Python materializer, and sentinel-verified atomicity for capacity and
coordinate errors. Existing 128 Godot blend vectors and a 24-pixel signed-world
stroke continue to match byte-for-byte. This verifies the *prototype* only.

### Input-event to submitted-frame witness (not photons)

The new `tests/drawing_latency_visual.gd` creates a real Atlas canvas backed by
the canonical Drawing composition, injects 21 distinct left-click gestures
through `Window.push_input()` on X11, verifies committed revision increments
and the painted pixels in `root.get_texture().get_image()` following
`RenderingServer.frame_post_draw`, and times CPU dispatch separately. This is a
more representative **software framebuffer** measurement than an isolated
CPU compositor; it still does **not** measure mouse hardware, input-driver
queueing, scan-out, or a human-visible frame on a physical display.

[Raw software-frame event evidence](benchmarks/T068_2026-11-02_frame.json)
(Godot 4.8 beta 2, Xvfb/Mesa llvmpipe, 21 samples, 68 checks):

| Stage | Median | p95 |
|---|---:|---:|
| Synthetic event dispatch through CPU paint commit | 0.445 ms | 0.597 ms |
| Synthetic event → `RenderingServer.frame_post_draw` | 10.358 ms | 12.960 ms |

The test deliberately uses single-dab, opaque brush gestures, and therefore
**does not establish p95 for 64–256px strokes, long paths, flood fills, GPU
upload scheduling, multi-thread jitter or Windows/non-software GPUs**. It does
prove that actual editor input, DrawingDocument revision and a verifiable
native framebuffer are connected. CI runs this witness under software X11,
while the pre-existing Godot and C++ correctness suites still guard pixel parity.

**Remaining closure obligations are unchanged:** execute pinned Blend2D and
Skia CPU comparators, run an actual optional GDExtension and native-boundary
measurements, test real physical input-to-display and peak RAM/VRAM/jitter on
Windows/Linux hardware, and prove two-platform optional exports. Those cannot
be represented as completed by the above prototype. Runtime fallback remains
pure Godot and no new binary or external license is shipped.

## 2026-11-03 follow-up: stationary hard dab and nontrivial native gestures

`DrawingEditSession._paint_segment()` now skips `Geometry2D.get_closest_point_to_segment()` for a **stationary** hard-brush dab (`start == finish`), using the same center/closed-circle comparison and unchanged once-per-pixel staging. Swept nonstationary segments keep their existing geometry and all commit/cancel/undo paths are unchanged. This is a small, dependency-free CPU optimization, **not** a replacement raster kernel or altered brush policy.

- `tests/drawing_dab_geometry_smoke.gd` supplies an **independent original `Geometry2D` oracle**, not the new fast branch. On Godot 4.8.beta2 it passes **125 checks**, including exact pixels over multiple widths and fractional/negative points at tile seams beyond 2^53 signed anchors, history undo/redo and hidden RGB on transparent no-op paint.
- The normal headless `drawing_raster_backend_benchmark.gd` passed **693/693** after the change. A before/after headless comparison on this sandbox found **identical** 128 blend vectors, signed parity fixture, changed-pixel maxima and undo wire sizes for all 18 operation/stride cases. On the three 64px round-dab cases, edit+commit+undo+redo medians were **211.206 → 201.767 ms** (512), **208.288 → 199.490 ms** (1024), and **211.647 → 211.511 ms** (2048). Individual runs can be affected by scheduling and background load; this is a *single* before/after pass, not a randomized A/B study. No reliable large speedup is claimed.
- The new **non-push native X11/Mesa** `tests/drawing_latency_stress_visual.gd` witnesses actual Control pointer input to a canonical Drawing revision and a changed `root.get_texture()` pixel. Its **25 synthetic gestures and 81/81 checks** passed on each of two runs. The test explicitly verifies sample D0 uses **1 canonical pixel per world unit**, so widths are accurately labeled 4/32/64px, plus a 4px long path and a 4px crossing path. Each row has only five observations; measured p95 is the **maximum**, not a stable latency estimator.

| Synthetic native gesture | Run A CPU dispatch median / p95 | Run A input → `frame_post_draw` median / p95 | Run B CPU dispatch median / p95 | Run B input → `frame_post_draw` median / p95 |
|---|---:|---:|---:|---:|
| 4px stationary dab | 2.655 / 4.887 ms | 29.597 / 49.078 ms | 1.193 / 1.732 ms | 20.018 / 31.172 ms |
| 32px stationary dab | 30.111 / 204.851 ms | 58.226 / 451.334 ms | 40.323 / 143.219 ms | 76.653 / 171.599 ms |
| 64px stationary dab | 116.110 / 220.834 ms | 161.146 / 263.005 ms | 151.746 / 190.818 ms | 176.075 / 212.372 ms |
| 4px long swept stroke | 9.553 / 16.889 ms | 44.020 / 54.690 ms | 8.499 / 10.689 ms | 38.355 / 52.760 ms |
| 4px self-crossing stroke | 7.137 / 169.542 ms | 65.573 / 437.637 ms | 8.315 / 13.095 ms | 29.981 / 37.973 ms |

[Raw native stress run A](benchmarks/T068_2026-11-03_stress.json) · [Raw native stress run B](benchmarks/T068_2026-11-03_stress_repeat.json) · [Original vs optimized mixed workload data](benchmarks/T068_2026-11-03_dab_comparison.json).

These are **synthetic input dispatch and software framebuffer submission**, not hardware input latency, real frame scan-out, a representative graphics card, Windows, or multithread jitter. A 64px frame outlier should motivate *separately instrumented* raster/undo/cache/upload profiling, not a premature adoption of Blend2D, Skia, or a custom GDExtension. The earlier 21 single-dab/native result remains a distinct workload. No third-party executable comparison or optional cross-platform binary was added. **T-068 remains In Progress.**


## 2026-11-03 follow-up: source-tile cache during a detached gesture

The pure-Godot `DrawingEditSession` now resolves each source tile at most once
per session. `_stage()` previously constructed a `DrawingResult` and resolved
its source tile **per covered candidate pixel**, even when thousands of
candidates belonged to one tile. The session now holds a dictionary keyed by
canonical signed tile keys with nullable `DrawingRasterTile` values; successful
absent tiles are cached as `null`, while missing/corrupt lazy-source failures
are **never cached**. The cache is discarded on `commit()` (including rejected
commits) and `cancel()`. Document publication still verifies its revision and
re-reads original values before atomically replacing only touched sparse tiles.
No storage schema, brush geometry, canvas renderer, platform dependency or
native prototype ABI changed.

New CI-required `tests/drawing_edit_tile_cache_smoke.gd` passes **31/31**:
reads across four signed tile seams, duplicate dab coverage, exact RGBA8
(including hidden RGB), undo/redo, empty-tile caching, missing/corrupt lazy
chunk error and repair, mid-gesture partial failure/retry, concurrent writer
rejection, and precise >2^53 anchors. Existing original-geometry witness
passes **125/125**, and two unmodified 512/1024/2048 mixed benchmark runs
pass **693/693 each** both before and after this change. The 128 blend
vectors, native parity fixture, 18 changed-pixel maxima and undo wire sizes
match exactly on each before/after pair. Source files:

- [Godot baseline A](benchmarks/T068_2026-11-03_tile_cache_baseline.json)
  and [cached B](benchmarks/T068_2026-11-03_tile_cache_cached.json)
- [Godot baseline A repeat](benchmarks/T068_2026-11-03_tile_cache_baseline_repeat.json)
  and [cached B repeat](benchmarks/T068_2026-11-03_tile_cache_cached_repeat.json)
- [Native software-frame baseline](benchmarks/T068_2026-11-03_tile_cache_native_baseline.json)
  and [cached](benchmarks/T068_2026-11-03_tile_cache_native_cached.json)

### Measured effect and constraints

Two **non-randomized** mixed Godot baseline/cached pairs measured a single
5-sample median per operation and stride, including commit, undo and redo:

| Workload | 512 base → cached (ms), runs 1 / 2 | 1024 base → cached | 2048 base → cached |
|---|---|---|---|
| 64px dab | 260.732 → 184.416 / 316.833 → 338.228 | 227.670 → 203.334 / 434.734 → 238.021 | 293.677 → 219.989 / 206.255 → 190.271 |
| Long 4px stroke | 84.125 → 60.591 / 74.839 → 76.593 | 70.265 → 59.475 / 101.243 → 83.791 | 75.557 → 55.387 / 66.297 → 90.848 |

Results are mixed: the 512-stride dab and long stroke in repeat 2, and the
2048 long stroke in repeat 2, **regressed**. The optimization removes
redundant tile lookups, but these pairs do not isolate stage time from undo,
GC, process startup or scheduling; no stable speedup distribution is claimed.

The existing **native Control-pointer to `frame_post_draw`** stress test also
passed 81/81 baseline and 81/81 cached on fresh Xvfb/Mesa llvmpipe runs
(Godot 4.8.beta2, dummy audio, 5 synthetic gestures/case):

| Native case | CPU dispatch baseline → cached median | Input → software `frame_post_draw` baseline → cached median |
|---|---:|---:|
| 4px dab | 1.453 → 0.989 ms | 19.109 → 16.552 ms |
| 32px dab | 33.430 → 21.934 ms | 53.561 → 47.719 ms |
| 64px dab | 117.367 → 83.709 ms | 140.281 → 109.453 ms |
| 4px long | 12.092 → 8.401 ms | 41.099 → 32.761 ms |
| 4px crossing | 7.534 → 8.578 ms | 33.313 → 52.407 ms |

The crossing-path median **regressed**, and the cached 32px and crossing
p95 contain large outliers. Five samples do not characterize production
latency. X11/Mesa software frame submission is not physical display time.
There is still no Windows or hardware-GPU validation, third-party Blend2D/
Skia comparison, integrated optional GDExtension, VRAM/RSS measurement or
multi-thread-jitter study. This is a safe, isolated optimization and **T-068
remains In Progress** pending its original research acceptance.

## 2026-11-03: commit-time tile resolution benchmark (T-068)

Once the detached edit session has staged pixels, `DrawingDocument._publish_edit`
validates every source original before installing any changed tile. It now
resolves an immutable source tile **once per touched tile** for that single
checked publication, rather than constructing a `read_pixel()` result for
every changed pixel. An unresolved lazy tile still aborts the entire commit;
null source tiles are valid and create detached tiles only on publication.
This does not alter RGBA8 semantics, history, or the exposed read API.

The pinned Godot 4.8 beta 2 headless microbenchmark runs three new-document
samples per cell, timing only `_publish_edit` for 4,096 or 16,384 new pixels.
Its output is **not** an end-to-end gesture/frame benchmark.

| Source stride | 64×64 baseline → cached median | 128×128 baseline → cached median |
| --- | ---: | ---: |
| 512 | 59.225 → 16.441 ms | 224.672 → 83.902 ms |
| 1024 | 53.453 → 19.705 ms | 216.894 → 76.303 ms |
| 2048 | 51.222 → 16.830 ms | 210.705 → 69.773 ms |

Raw per-sample files: [baseline](benchmarks/T068_2026-11-03_publication_baseline.json)
and [cached](benchmarks/T068_2026-11-03_publication_cached.json). All six cases
pass source-pixel and delta-count checks. A separate 30-assertion CI witness
checks signed-tile resolution counts, transparent hidden RGB, stale originals,
lazy loading/retry, reentrant provider revision changes, no partial commits,
and undo/redo. Existing raster,
history, composition and mapping regressions also pass. These synthetic
three-sample medians may be noisy; no hardware speedup or backend adoption
is implied. A post-change X11/Mesa native framebuffer witness also passed 81/81
checks, with its [raw result](benchmarks/T068_2026-11-03_publication_native.json).
Because no fresh native baseline was run for this change, the numbers are
**not** claimed as a native speedup. Windows and actual presentation latency
remain unmeasured.


## 2026-11-03: horizontal/vertical swept brush geometry (T-068)

`DrawingEditSession._paint_segment` now uses a bounded squared-distance test
for exact axis-aligned, nonstationary swept hard brushes. Horizontal/vertical
paths stay in the original **row-major** candidate traversal; any angled sweep
continues to call the existing Godot `Geometry2D` oracle. The existing
stationary-dab path is unchanged. Mask gating, source-pixel blending, once-per-
gesture coverage, detached previews, cancellation, undo/redo, signed anchors
and transaction publication are also unchanged. No native dependency is added.

The fast-CI `tests/drawing_axis_sweep_smoke.gd` passes **239/239** checks
on Godot 4.8 beta 2: independent original-`Geometry2D` touched-pixel and
straight-RGBA8 comparison, fractional/reversed endpoints, radii 1–15,
64-bit signed anchors beyond 2^53, selection masks, retries and Undo/Redo.
An additional 320 seeded randomized axis segments compare over 20,000
candidate pixel classifications with `Geometry2D`, with no mismatches.

Seven samples per test case on fresh blank documents, measuring only
`paint_path` **plus** `commit` (no UI, frame, disk, or GPU) produced:

| Synthetic sweep (16 px, 256 tile) | Original median/p95 ms | Shortcut median/p95 ms | Exact changed pixels |
|---|---:|---:|---:|
| Horizontal | 33.803 / 37.963 | 33.041 / 36.521 | 3,604 |
| Vertical | 32.442 / 34.253 | 34.126 / 35.606 | 3,604 |
| Oblique control (unchanged path) | 31.407 / 33.308 | 31.964 / 37.551 | 3,432 |

Raw samples and execution notes: [`benchmarks/T068_2026-11-03_axis_sweep_ab.json`](benchmarks/T068_2026-11-03_axis_sweep_ab.json). The comparison is *not* randomized or
interleaved and has no confidence interval. The vertical median regressed;
the optimization therefore **does not establish a reliable end-to-end speedup**.
The per-pixel stage/history overhead still dominates this small scenario.
This work is a correctness-guarded, dependency-free baseline rather than a
reason to select or exclude a native backend. T-068 remains **In Progress**;
third-party library comparisons, optional Godot native binary integration,
Windows/Linux hardware measurements, RSS/VRAM and jitter evidence remain open.


A separate **post-change-only** targeted Xvfb/Mesa software-framebuffer
stress run passed **80/80** checks across 25 synthetic gestures, with dummy
audio and no resource errors. The 4px-long-path CPU dispatch median was
3.931 ms and `frame_post_draw` median was 20.317 ms (five samples); there is
**no matched baseline**, so neither is attributable to the axis shortcut.
[Raw stress data](benchmarks/T068_2026-11-03_axis_sweep_native.json).


## 2026-11-03: verified lazy tile reads for bounded flood fill

T-068 now reads flood-fill source pixels through the edit session's existing
verified immutable per-tile cache, instead of separately calling resident-only
`has_stored_pixel()` and `DrawingDocument.read_pixel()` at each visited point.
This fixes a correctness hole for unmaterialized, hash-verified source tiles
and avoids repeated tile-result allocation. A zero canonical RGBA8 value is
still unfillable blank space; nonzero transparent hidden RGB is an authored
stored pixel. Lazy resolution failure aborts the gesture without publication.
The 30-check [fill witness](../tests/drawing_fill_tile_cache_smoke.gd)
includes a failed/corrupt provider and retry, undo/redo, mask, and signed
coordinates beyond 2^53.

**Reproduction (same Godot 4.8 beta 2):**

```sh
godot --headless --path . --script res://tests/drawing_fill_tile_cache_smoke.gd
godot --headless --path . --script res://tests/drawing_fill_tile_benchmark.gd
```

[Raw ordered before/after observations](benchmarks/T068_2026-11-03_fill_cache_before_after.json)
include each of five samples for three matched areas and two runs per variant.
The baseline was the previous `ae3de9a` commit, with the same benchmark script;
only the fill-source read path changed. Medians of the two run medians:

| Filled pixels | Before (ms) | Cached (ms) | Observed change |
|---:|---:|---:|---:|
| 32 × 32 | 17.686 | 14.526 | −17.9% |
| 64 × 64 | 73.714 | 50.586 | −31.4% |
| 96 × 96 | 167.943 | 123.499 | −26.5% |

These numbers include **CPU fill staging and synchronous publication** on
small synthetic documents, but not seed allocation, user input, texture
upload, rendering or photon/present latency. Sequential before/after runs,
just ten observations per variant per size and heterogeneous system load mean
no statistically supported stable gain. No native backend was enabled.


## 2026-11-03: queue each flood-fill candidate only once

The four-connected `DrawingEditSession.flood_fill()` now marks a candidate as
soon as it enters the queue. Previously a position could be queued repeatedly
by several already accepted neighboring pixels; the duplicate entries were
later skipped, consuming temporary queue space. The queue is now unique, and
its `head` counts the unique candidates examined by the explicit `limit`.
The four-neighbor order, source-tile verification, immutable original colors,
selection tests, detached staging, rollback, and commit/Undo contract are
unchanged. The fill still refuses unallocated clear source pixels and does not
change its native/backend dependencies.

The independent 56-check finite-grid oracle and exact-budget rollback/retry
witness is `tests/drawing_fill_frontier_smoke.gd` (fast-CI-gated). It exercises
masked/unmasked connected regions, wall colors, holes, negative coordinates,
transparent hidden RGB, and Undo/Redo. Existing lazy-source fill and gesture
regressions are separately retained; no synthetic benchmark is a replacement.

Two ordered baseline and changed five-sample **CPU-only** benchmark runs of
`drawing_fill_tile_benchmark.gd` (same Godot beta2 and test script) yielded:

| Filled pixels | Baseline run 1 / 2 medians (ms) | Unique-frontier run 1 / 2 (ms) |
|---:|---:|---:|
| 32 × 32 | 12.766 / 13.601 | 13.225 / 19.539 |
| 64 × 64 | 53.491 / 57.204 | 56.587 / 55.861 |
| 96 × 96 | 140.005 / 142.046 | 134.218 / 130.686 |

[Full samples](benchmarks/T068_2026-11-03_unique_frontier.json). The larger
region appears somewhat faster while 32² regresses badly in the second run;
this is **not evidence of stable speedup**. Scheduling, short sample windows,
GC, and workload shape are uncontrolled. No physical event-to-display latency,
peak RSS/VRAM, thread jitter or native/backend comparison is implied.
T-068 remains In Progress pending its original acceptance obligations.


Final regression checkpoint for this change: **14/14** headless suites,
**1,803/1,803** assertions, with editor-imported bundled fonts; explicit
GDScript types, ticket validator (83), CI contracts (6) and workflow YAML
passed. The optional native Xvfb/Mesa brush/framebuffer witness passed
**81/81**, with [raw results](benchmarks/T068_2026-11-03_frontier_native.json).
This native test does **not** exercise Bucket, so it is only a general
post-change display regression check. No native fill-latency comparison was made.


## 2026-11-03: reuse previously verified flood-fill source bytes

The fill path previously read the canonical original RGBA8 for comparison,
then called the normal `_stage()` path, which re-created a source tile address
and retrieved the same pixel again. A private `verified_source` parameter now
reuses the already authenticated value for that fill match only. Other tools
keep the normal source read, and the original delta and revision checks still
run. No new native dependency, storage layout, blending rule or GPU feature
was introduced.

New regression: [29-check verified-stage smoke](../tests/drawing_fill_verified_stage_smoke.gd)
with a same-session edit/fill/edit and a rejected limited fill, immutable
before-values, hidden RGB, signed 64-bit tile crossings, repeated fills,
selection, Undo/Redo and concurrent revision rejection. The 15-suite
headless check aggregate passed **1,832/1,832**; the targeted unrelated brush
framebuffer stress passed **81/81** on X11/Mesa.

Three ordered baseline/changed pairs of the same `drawing_fill_tile_benchmark.gd`
(5 independent fill+commit timings per size per process; 3 separate processes
per version) produced the following median of the three run medians:

| Source rectangle | Before | With verified-source staging | Relative |
| --- | ---: | ---: | ---: |
| 32×32 | 11.922 ms | 11.048 ms | −7.3% |
| 64×64 | 50.868 ms | 44.961 ms | −11.6% |
| 96×96 | 121.659 ms | 115.892 ms | −4.7% |

[Raw trials, including each process's five timings](benchmarks/T068_2026-11-03_verified_stage_ab.json)
· [Targeted native brush diagnostic](benchmarks/T068_2026-11-03_verified_stage_native.json).
This is only a small, nonrandomized CPU study in a software sandbox; the
96×96 changed result regressed against baseline in one pair. It does not
establish statistical significance, measured peak memory, real Bucket
pointer-to-frame latency, or physical Windows/Linux/GPU performance.
T-068 remains **In Progress** pending the original backend comparisons,
optional extension boundary, physical metrics and operation-by-operation
recommendation.


## 2026-11-03: native software frame timing and sampled allocation counters for canonical fill

A new **test-only** native GUI adapter delivers a synthetic Control mouse
release to `DrawingEditSession.flood_fill()` and publishes through
`DrawingCanvas`. This makes the previously missing *fill transaction → software
frame submission* path observable, while intentionally avoiding any claim that
production Atlas or standalone Bucket tool wiring was tested. The same
64/96/32-side RGBA8 rectangles are seeded on fresh 128-stride documents; five
trials per size per process, two independent X11/Mesa llvmpipe processes.
An exact changed-pixel count, source value, revision and *visible framebuffer*
probe are assertions, not inferred from timestamps. A budget-rejected click
is also required not to change canonical content or the framebuffer.

| Pixels | Run 1 CPU / post-draw (ms) | Run 2 CPU / post-draw (ms) |
|---|---:|---:|
| 32² | 12.903 / 35.126 | 14.754 / 36.934 |
| 64² | 57.530 / 85.673 | 56.060 / 84.385 |
| 96² | 134.877 / 168.214 | 141.533 / 176.683 |

These are each **medians of only five trials**. Per-trial values and
five-sample p95s (effectively the maximum), sampled Godot static memory,
renderer-reported VRAM and texture counters are recorded in
[raw JSON](benchmarks/T068_2026-11-03_bucket_frame_native.json).
Typical sampled values were approximately 97 MB Godot static memory,
12.9 MB renderer-reported video memory and 6.4 MB texture allocation;
these values include the process, canvas and software renderer. They are
*not* peak physical process RSS/VRAM, per-fill allocations, or cross-platform
jitter measurements. The software frame-post-draw signal is not GPU scanout
or actual visible-to-human latency, and synthetic input is not OS pointer
hardware interaction. No before/after backend comparison was performed.

Reproduce locally after Godot 4.8 beta2 main-project import:

```sh
xvfb-run -a -s '-screen 0 1280x900x24' godot --audio-driver Dummy \
  --rendering-driver opengl3 --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_fill_frame_native.gd -- \
  --output /tmp/t068-fill-frame.json --screenshot /tmp/t068-fill-frame.png
```

An on-demand `.github/workflows/godot-native-t068-fill.yml` performs this
outside fast push CI and uploads the evidence. T-068 remains In Progress:
third-party kernel comparisons, optional native boundary, Windows/Linux
physical-device, actual memory high-water, jitter and operation decision
remain open.


## 2026-11-03: reproducible Linux process-memory sampler and 21-trial software-frame distribution

The follow-up `tools/benchmarks/t068_fill_process_profile.py` starts separate
`xvfb-run`/Godot 4.8 beta 2 processes, identifies **Godot** by its real
`/proc/PID/exe` rather than trusting the wrapper command line, and samples
`VmRSS`, `VmHWM` and `VmSwap`. The 10 ms sampling interval is requested, not
hard-real-time, and VmHWM includes the process lifetime (Godot startup plus
renderer). A readiness marker supports a separately reported **sampled**
post-initialization RSS change; neither figure is an allocation trace.

| Fill pixels | Run A dispatch median / p95 | Run A `frame_post_draw` median / p95 | Run B dispatch median / p95 | Run B frame median / p95 |
| --- | ---: | ---: | ---: | ---: |
| 32² | 13.671 / 19.462 ms | 34.158 / 44.510 ms | 13.549 / 16.639 ms | 34.614 / 40.051 ms |
| 64² | 53.826 / 67.755 ms | 79.671 / 98.488 ms | 56.037 / 78.486 ms | 83.642 / 109.090 ms |
| 96² | 134.427 / 158.094 ms | 168.487 / 196.921 ms | 129.480 / 152.565 ms | 164.342 / 190.817 ms |

Each row is based on **21 successful, seeded, fixed-size fill gestures per
fresh process**, with visible pixel checks after a software-rendered frame.
There are 385 passing checks in each process (770 aggregate). No trials are
pooled to imply independent machines or statistical confidence; p95 is the
20th ordered sample out of 21. Whole-process kernel VmHWM was **251,288 KiB**
and **251,420 KiB**; peak sampled post-ready RSS increases were **8,988 KiB**
and **8,284 KiB**. The process includes Godot, textures, renderer caching,
new documents and test overhead. It does **not** isolate per-fill memory or
physical VRAM. The test adapter sends synthetic Godot GUI events into the
canonical fill session, not the production Bucket UI; the rendering signal
is not physical scanout or Windows/Linux device validation.

[Complete raw process/trial evidence](benchmarks/T068_2026-11-03_fill_linux_rss.json)
was generated with:

```sh
python3 tools/benchmarks/t068_fill_process_profile.py \
  --godot /path/to/Godot_v4.8-beta2_linux.x86_64 \
  --output-dir /tmp/t068-fill-profile --runs 2 --trials 21 --sample-ms 10
```

The host runner requires Linux `/proc`, Xvfb, software OpenGL and an imported
Godot project; the GitHub workflow exposes it *on demand*. No raster library
was adopted, and T-068's external backend, optional GDExtension, physical
Windows/Linux, GPU and operation-level decision obligations remain open.
