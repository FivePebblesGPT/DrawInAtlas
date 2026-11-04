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
| Existing once-covered hard brush, exact straight-RGBA8 | Reference behavior, measured | Masked per-pixel batch verified; native path geometry not implemented | Pinned premultiplied comparison has parity losses (see later checkpoint) | Direct Skia RGBA8 shows rare rounding/transparent-replace mismatches; no brush/mask parity (see later checkpoint) | Keep GDScript; prototype narrow native batch further for large gestures |
| Erase, bounded fill, touched-region COW, compact undo | Functional and regression-tested; large fill slow | Exact replace/erase/mask and compact deltas verified, but region copied fully | Not a complete undo/document store | Not a complete undo/document store | Optimize bounded native buffers and touched-region COW first |
| Visible multi-layer CPU composite | B is measured ~16× A | No compiled compositing integration | CPU rectangle rendered, but straight RGBA8 parity not general | Direct CPU rectangles screened; canonical general compositing not proven | **Ship B**, no external renderer |
| Vector paths, Béziers, antialias, complex blend | Separate existing tool contracts | Unsupported by simple hard-pixel prototype | Candidate when quality/workload requirements justify it | Skia CPU path/AA capability screened; no canonical geometry parity yet | Defer new engine; app-level performance **not measured** |
| Natural brush dynamics, pressure/tilt | Not this hard-brush benchmark | Unsupported | Limited natural-media brush semantics | No libmypaint equivalence assumed | Evaluate **libmypaint** separately only if feature scope demands |

At the **initial 2026-11-02 checkpoint only**, external dependencies were **not fetched, built or timed**: no Blend2D, Skia or libmypaint development packages were available on this machine, and source download failed due DNS/network access. Thus **there is no honest D/E p95 speedup, binary-size, conversion-cost, exact output parity, or release compatibility result**. Capability/licensing screening is not an execution benchmark. Blend2D [zlib licensing / AsmJit requirement and release pin hashes](https://blend2d.com/download.html), candidate version **0.21.2**, source SHA **`def0d1238c3e5d0983bb848e5676049d829e435b`**; Skia [BSD 3-Clause](https://github.com/google/skia/blob/main/LICENSE) with GN and extensive optional build dependencies; libmypaint [ISC and json-c](https://github.com/mypaint/libmypaint/blob/master/README.md). No external code or binaries were copied into the monorepo. Windows builds and all third-party versions would require actual validated dependency locking before acceptance.


## Regression and legacy compatibility evidence

- Final Godot import/explicit-type validation passed; T-055 composition **89** checks, T-061 world mapping **125**, Drawing history **101**, T-060 Object Assets **95**, Object Editor **45**, editable Drawing text **60**, T-066 bundle persistence **84** and editor Save/Load **23**, artwork **171**, and legacy storage **77** all passed.
- The independent Drawing build imported from a clean staged directory and passed its **38-check** standalone witness; Linux `Drawing.x86_64` and `.pck` exported successfully. The Godot benchmark passed **691 checks in the latest rerun** with JSON output; C++ kernel Python unit tests passed **6** and cross-runtime parity passed.
- The old `tests/text_smoke.gd` reports **two failures** because it still asserts that the editor saves via `AtlasCampaignStore.load_campaign()` from a legacy single `.scn` path. The identical failures were reproduced by running the unmodified **`9c64138`** baseline code in a separately imported checkout. This is a **pre-existing compatibility debt**, not a new regression, and is not silently corrected under this research ticket.
- This delivery's CPU renderer change is **not** T-067's production stride change or T-057's derived LOD. No new backend is enabled, and no existing persistent formats were changed.

## Remaining mandatory T-068 acceptance work

1. Extend the pinned Blend2D rectangle and Skia CPU rectangle/path screens with an independently verified canonical shape/brush/mask workload and matched *native C++* conversion/marshal benchmarks; their current source/format differences and hidden-RGB losses are recorded below. Evaluate libmypaint only if natural brush support enters Essential scope.
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


## 2026-11-03: independent C++ threads, kernel jitter and exact edit parity

The [two-run evidence](benchmarks/T068_2026-11-03_native_thread_jitter.json)
measures **only** the isolated C++ kernel. The new
`tools/benchmarks/t068_thread_jitter.cpp` uses `std::thread` (not Python
threads) to dispatch one, two, or four simultaneously running callers with
**private immutable RGBA8 copies, separate output and delta arrays**, and a
start barrier. It compares source-over with repeated coordinates, masked
erase and exact replacement with nonzero RGB at alpha zero. Each native
worker's output/source/deltas must match a serial oracle before results are
accepted. Full-buffer-copy and sparse-delta APIs are timed separately.

Representative *median of two run medians* (ms) at 256² pixels, 101 calls
per worker and three warmups:

| Kernel case | Mode | 1 worker | 2 workers | 4 workers |
|---|---|---:|---:|---:|
| Masked erase | Sparse deltas | 0.1048 | 0.1045 | 0.1451 |
| Masked erase | Full region | 0.1199 | 0.1216 | 0.1641 |
| Exact replace | Sparse deltas | 0.0915 | 0.1250 | 0.1586 |
| Exact replace | Full region | 0.1063 | 0.1097 | 0.1769 |

**Caveats:** These figures are microbenchmarks on a shared Linux host, not
confirmed scalable throughput, integrated drawing latency or physical-device
performance. The p95 tails fluctuate materially between runs and may include
OS scheduling and CPU contention. No shared mutable source is deliberately
allowed in the benchmark. The compiled kernel has **not** been adopted as a
Godot GDExtension, no renderer or save format changed, and no new native
runtime dependency is shipped. These results narrow T-068's concurrency
unknowns but cannot close the ticket or determine a backend by themselves.


## 2026-11-03: bounded C ABI prototype safety gate (not integrated)

The benchmark-only scalar kernel still exports its existing `draw_batch` and
`draw_batch_deltas` functions at ABI version 1. New opt-in
`draw_batch_checked` and `draw_batch_deltas_checked` functions also take
**declared byte capacities** for source, points, mask, deltas and optional full
output. They validate sizes before accessing buffers, reject writable range
aliasing and return new error codes `-5` (short/invalid) and `-6` (overlap),
while preserving legacy source-over, clear and replacement bytes. Checked
calls catch internal C++ exceptions at their C boundary (`-4`).

`tests/test_t068_checked_abi.py` passes six contract tests: 160 randomized
source/mask/operation cases compared byte-for-byte to both original entry
points; exact-capacity canaries; short, null, overflow and overlapping buffers;
zero-alpha/empty batches; and failure-atomic invalid coordinates and capacity.
Only the test harness calls these functions. There is **no evidence** that
native integration, Godot buffer marshaling or overall edit-to-visible latency
is faster. In particular, supplied capacities cannot authenticate foreign
pointers, so the wrapper does not make arbitrary C calls memory-safe. The
remaining library-comparison, GDExtension, physical-hardware and operation-
selection obligations stay open under T-068.


## T-068 isolated Godot GDExtension ABI timing (2026-11-03)

A Linux-only, manually invoked temporary GDExtension project now measures the
real Godot `PackedByteArray` → C++ checked batch → `PackedByteArray` boundary,
without modifying Atlas or standalone Drawing. Two Godot 4.8 beta 2 runs pass
**443 exactness/boundary checks each**. Each call allocates detached native
source/output storage, and the result is copied back to Godot. Four harness
contracts are part of fast CI; the Godot binary bridge runs only on demand.

| Region | Run 1 median / p95 | Run 2 median / p95 | Samples per run |
|---|---:|---:|---:|
| 32×32 RGBA8 | 8 / 15 μs | 9 / 14 μs | 31 |
| 64×64 RGBA8 | 13 / 36 μs | 13 / 14 μs | 31 |
| 128×128 RGBA8 | 16 / 60 μs | 16 / 17 μs | 31 |

[Raw JSON](benchmarks/T068_2026-11-03_gdextension_bridge.json) reports the
engine-generated header digest and timings. These values are small **API-call
microbenchmarks**, not a comparison against a Godot in-app edit or physical
pointer-to-visible presentation. The engine editor scan of this experimental
module can abort; only explicit runtime loading in a throwaway project has
passed. No source-revision or main-thread dirty-region publication, renderer
integration, Windows binary, external-library competitor, or adoption decision
has been established. **T-068 remains In Progress.**


### T-068 revision-aware opt-in publication boundary (2026-11-03)

An isolated GDScript adapter now exercises the checked native GDExtension output
through a detached RGBA8 edit, a revalidated expected source revision **and**
byte snapshot, single-step atomic install, dirty-pixel bounding rectangle and
whole-`ImageTexture.update()` call on the main thread. A publication race
changes the source between native computation and install; the computed result
is discarded without overwriting the concurrent source. Masked hidden-RGB,
no-op, invalid-input and stale-revision cases are explicit.

Two Godot 4.8b2 runs pass **370/370 publication checks** and **443/443 native
pixel/argument checks** each. The GL readback is performed under Xvfb/Mesa,
not Godot's headless dummy driver. [Raw evidence](benchmarks/T068_2026-11-03_gdextension_revision.json)
contains check counts and bridge timings. This test does **not** measure
native `DrawingDocument` publication costs or input-to-photon latency, and the
reported dirty rectangle does **not** mean Godot supports partial
`ImageTexture.update()`. The production renderer, file format and editor
startup are unchanged; the third-party backend and hardware comparisons remain
outstanding.


### Real canonical DrawingDocument transaction witness (2026-11-03)

The optional native bridge now has a **second, independent publication path**
for experimental verification: one checked C++ tile result is fed to the real
`DrawingDocument` through `DrawingEditSession.apply_region()` and its usual
atomic `commit()`. The temporary Godot project includes only 12 source scripts
from the generic Drawing package. No native library or extension descriptor
is installed in the real editor. This is not optimized: a whole tile crosses
the GDExtension boundary and is scanned/staged through GDScript, and a maximum
1,024² tile is allowed by the existing edit-region budget.

[Two-run raw evidence](benchmarks/T068_2026-11-03_gdextension_document.json)
records **443 native bridge**, **370 texture readback** and **219 canonical
Document** checks per run. The latter verify source pixels/hidden RGB, 48
independent randomized blend/erase/replacement oracles, revisions, real
history and dirty regions, mask eligibility, stale concurrent commits, signed
coordinates, lazy SHA-verified bytes, and lock failure atomicity. Reported
microsecond bridge timings exclude the whole-tile Drawing commit and must
**not** be used to claim an edit-to-visible improvement. No real editor
startup, production Bucket tool, GPU subrectangle upload, Windows build or
physical-hardware comparison was exercised. T-068 remains **In Progress**.


## T-068: isolated atomic multi-tile native-to-document boundary (2026-11-03)

The optional bridge prototype now accepts a bounded batch of independently
computed checked C++ raster tiles and publishes them through **one** real
`DrawingEditSession` history event. Its preflight rejects duplicate/unsafe
tile targets and invalid results before any stage; `commit()` revalidates
source revisions and bytes before installing all tiles. The deliberate
1,048,576-pixel aggregate full-tile staging limit and view-relative range
restriction avoid unbounded allocations. Per-tile dirty rectangles are
reported using integer local coordinates (not floating-point world
coordinates), including at signed-world origins beyond 2^53.

Two standalone Godot 4.8 beta 2 runs of
`tools/benchmarks/t068_bridge/run_bridge.py --runs 2` each pass the new
**128-check** multi-tile witness alongside the established 443/370/219
checks for native parity, texture readback and single-tile publication.
[Raw results](benchmarks/T068_2026-11-03_gdextension_multitile.json) retain
independent check counts. No comparative multi-tile runtime measurements
were taken, so this test **cannot** justify a backend speedup. It does not
load in production Drawing/Atlas or remove the documented external CPU
comparators, Windows builds, physical-hardware and final selection gates.


## Experimental sparse-delta C++ to Godot publication (2026-11-04)

The optional T-068 GDExtension test bridge now returns changed-pixel records
instead of cloning an entire RGBA8 tile over the return boundary. Wire bytes
are **4 + 12 × changed pixels** (u32 count, then u32 index/before/after) versus
**4 × tile stride²** returned by the earlier full-tile path; both paths still
send the **entire original tile into native code**. For a one-pixel change,
that is 16 bytes returned versus 4,096 / 16,384 / 65,536 bytes for 32/64/128
pixel tiles, respectively. The GDScript adapter performs independent before/
after and mask validation before calling the canonical `DrawingEditSession`;
its transient native metadata, point-set dictionaries, lazy-source reads and
canonical Undo deltas have not been measured as isolated allocation costs.

The manual-only `tools/benchmarks/t068_bridge/run_bridge.py` runs five
alternating full/sparse single-pixel edit-and-commit samples per tile size,
plus seeded multi-tile pixel/history parity and native error-atomicity tests.
Raw per-run latency data is in
[`T068_2026-11-04_gdextension_sparse.json`](benchmarks/T068_2026-11-04_gdextension_sparse.json).
These synthetic sequential samples compare prototype integration strategies,
**not native raster versus production GDScript tools**; CPU dispatch,
full source copy, frame upload, real input and Windows/Linux hardware remain
unmeasured. The default backend remains pure Godot, and T-068 is In Progress.

The two five-sample medians below are **isolated prototype edit+commit timings**,
not a controlled production benchmark; loop ordering alternates across samples.

| Tile | Full-output run 1 / run 2 | Sparse-delta run 1 / run 2 | Return bytes, full → sparse |
|---:|---:|---:|---:|
| 32² | 3,293 / 3,134 μs | 60 / 57 μs | 4,096 → 16 |
| 64² | 13,137 / 12,252 μs | 74 / 68 μs | 16,384 → 16 |
| 128² | 50,695 / 51,177 μs | 111 / 109 μs | 65,536 → 16 |

The strong microbenchmark difference primarily reflects the previous
`apply_region()` path scanning **all tile pixels**, whereas the sparse path
stages just the one changed pixel. It does **not** measure brush coverage
computation, file I/O, GPU upload, pointer dispatch, memory peaks or the
performance of the production raster engine. The 16-byte record format
omits Python/Godot container allocation overhead and the full source buffer
still passed *into* native code. Retain pure-Godot as the shipped fallback.


## 2026-11-04: complete sparse-output validation boundary

The opt-in native bridge previously checked every delta record independently,
but could accept a forged native zero-change header even when an eligible
requested pixel would change. It now **recomputes the complete canonical set**
from the verified source bytes, unique eligible point coordinates and exact
blend/erase/replace operation; counts, indices, before/after values and
uniqueness must all match. A partial or empty forged return never reaches a
`DrawingDocument` publication, including in a multi-tile gesture. True no-op
or mask-excluded operations still succeed. The targeted witness adds four
regression assertions, reaching 173 per isolated native run.

This deliberately spends O(requested unique points) GDScript CPU work in the
sparse path and can reduce its apparent speed benefit. Retain raw paired
staging timings in [the new diagnostic evidence](benchmarks/T068_2026-11-04_sparse_completeness.json)
but **do not** infer native backend performance, actual pointer-to-display
latency, or relative optimization gains from small synthetic samples. The
shipping Drawing path remains Godot-only; T-068 is still In Progress.


## 2026-11-04: optional Cairo image-surface CPU parity screen

The isolated `tools/benchmarks/t068_cairo_cpu.py` compares **Cairo 1.18.4
(runtime-reported)** with the existing checked scalar C++ batch and an
independent canonical straight-RGBA8 Python oracle. It uses `ctypes` against
the Linux system `libcairo.so.2`, not a bundled dependency. Every C++ result
is asserted byte-for-byte equal to the oracle. Cairo is rendered into
native-endian premultiplied `CAIRO_FORMAT_ARGB32`, then converted back to
canonical straight RGBA8 without silently repairing changed or unchanged
pixels. Its half-tile rectangular operation is intended only to screen
source-over, replace, clear and exact-color compatibility; it does not mimic
brush/path geometry, masks, document storage, history or GPU uploads.

[Raw two-run measurements](benchmarks/T068_2026-11-04_cairo_cpu.json)
contain 9 samples/run, 6 operations and 3 square sizes (36 scenario
observations). Both runs had **12 of 18 non-parity cases**, exclusively with
partially/fully transparent source tiles. For a 64² image, the two runs
reproduce these mismatch counts:

| Case | Painted disagreement pixels | Unpainted disagreement pixels | Hidden transparent RGB loss (all locations) |
|---|---:|---:|---:|
| Opaque replace | 0 | 0 | 0 |
| Opaque source-over | 0 | 0 | 0 |
| Transparent source-over | 654 | 2,025 | 704 |
| Translucent source-over | 970 | 2,025 | 704 |
| Translucent replace | 1,024 | 2,025 | 704 |
| Clear | 0 | 2,025 | 544 |

The clear operation correctly sets painted pixels to canonical zero, but
**unpainted** transparent/semistransparent source pixels are damaged just by
premultiplying and unpremultiplying the full surface. The transparent source
(no-op) also loses untouched RGB, violating the strict hidden-RGB gate. A
future comparator could avoid copying untouched pixels out of Cairo and
conditionally normalize *changed* pixels, but that would be a different
implementation requiring independent tests. The current adapter must **not**
be used as a canonical Drawing backend.

For 64² opaque source-over, the paired native-kernel call medians were
**37.8/35.0 μs**, Cairo's rectangle draw-only medians **6.1/5.1 μs**,
and Cairo's entire Python prepare/convert/draw/readback medians
**4,370/3,557 μs**. The three timings cover **different boundaries**:
the C++ call receives precomputed coordinates and canonical buffers;
Cairo's draw-only excludes buffer conversions, while Cairo's total includes
nonoptimized Python per-pixel format conversion. These observations cannot
establish that Cairo is faster or slower for a production stroke. There are
no GPU, Windows, or physical input-to-visible results, and Cairo is optional,
not a substitute for **Blend2D and Skia CPU comparisons**. No raster backend
was adopted; the ticket remains In Progress.

## 2026-11-04 optional Blend2D 0.21.2 CPU parity screen (not adoption)

The user supplied the official `blend2d-0.21.2.tar.gz` archive with bundled
AsmJit; SHA-256 verified as
`234ba57a64153c96885a6271f15fdcf6c594ac8cb03adaad19abb8d3b2b533fa`.
A disposable local Release CMake build (JIT enabled) supplies `libblend2d.so`.
The standalone `t068_blend2d_bridge.cpp` shim draws one opaque-edged rectangle
into caller-owned little-endian **premultiplied BGRA32**, not canonical Drawing
straight RGBA8; it is never installed as a GDExtension or runtime library.
[`T068_2026-11-04_blend2d_cpu.json`](benchmarks/T068_2026-11-04_blend2d_cpu.json)
retains both nine-trial runs and per-scenario mismatched pixel counts.

Reproduce from an externally supplied source tree and built shared library:

```bash
sha256sum -c <<<'234ba57a64153c96885a6271f15fdcf6c594ac8cb03adaad19abb8d3b2b533fa  /path/to/blend2d-0.21.2.tar.gz'
cmake -S /path/to/blend2d -B /tmp/blend2d-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DBLEND2D_TEST=OFF -DBLEND2D_DEMOS=OFF -DBLEND2D_NO_INSTALL=ON -DBLEND2D_NO_STDCXX=OFF
cmake --build /tmp/blend2d-build --parallel 4
T068_BLEND2D_ARCHIVE=/path/to/blend2d-0.21.2.tar.gz \
T068_BLEND2D_SOURCE=/path/to/blend2d T068_BLEND2D_BUILD=/tmp/blend2d-build \
  python3 -m unittest discover -s tests -p test_t068_blend2d_cpu.py -v
python3 tools/benchmarks/t068_blend2d_cpu.py \
  --archive /path/to/blend2d-0.21.2.tar.gz --source /path/to/blend2d \
  --library-dir /tmp/blend2d-build --runs 2 --trials 9 --sides 32 64 128 \
  --output /tmp/t068-blend2d-cpu.json
```

**72 checked scenarios** (2 runs × 3 sides × 6 operations × 2 conversion scopes)
all reproduced the independent **checked C++** oracle; **42** Blend2D
conversion/scoping scenarios disagreed with exact canonical RGBA8. This is a
correctness screen, not "72 passing Blend2D parity cases":

| Operation | Full-tile PRGB32 roundtrip | Edit-region-only PRGB32 roundtrip |
|---|---|---|
| Opaque replace | exact | exact |
| Opaque source-over | exact | exact |
| Transparent source-over | non-parity (including untouched) | non-parity (touched only) |
| Translucent source-over | non-parity (including untouched) | non-parity (touched only) |
| Translucent replace | non-parity (including untouched) | non-parity (touched only) |
| Erase | non-parity (untouched only) | exact |

The full-tile conversion can destroy *outside* hidden RGB and slightly alter
nonzero translucent RGB just by premultiplying and unpremultiplying. Restricting
premultiplied storage to a bounded edit rectangle and pasting only those rows
preserves every outside source byte, including hidden RGB, but **does not**
restore exact values of touched translucent pixels. A transparent source-over
must be short-circuited *before* any format conversion to be an exact no-op;
this comparator deliberately measures the raw library path. Exact-source
replacement is better implemented by a canonical byte copy rather than a
round-tripped premultiplied source. Opaque paint and scoped erase are usable
*operation-level* parity observations, not reasons to select a dependency.

The two clocks are **not comparable backend races**: checked-kernel duration
covers a `ctypes` call on prepared points and source/output/delta buffers;
Blend2D's context duration includes context begin, style, rectangle, and
synchronous end on preconverted bytes, and its "total" includes naïve Python
RGBA↔BGRA loops, detached buffers, and patch reconstruction. For the 64²
opaque source-over case, inspect exact per-run medians in raw evidence rather
than inferring a speedup from the render-only values. Source is pinned; the
local Linux compiler, Mesa software-GPU context and Python overhead do not
represent the user's physical Intel GPU or any Windows deployment. There is
no shape/AA oracle, mixed-layer or mask workload, live GDExtension bridge,
production pointer path, peak memory test, or matched native conversion cost.
**No Blend2D source/binary has been imported into Drawing/Atlas.** Continue
Skia/shape and real hardware evaluation; T-068 stays In Progress.


## 2026-11-04 optional Skia-python 144.1 CPU RGBA8 + path screen (not adoption)

The externally supplied [Skia-python 144.1 wheel](https://pypi.org/project/skia-python/144.1/)
was SHA-256 verified as
`a008767c16671f3704ea5e1a8cee99854047044632c0d71a37105d6b632b816a`.
It bundles a Skia native library in a Python binding, **not** the source or
linkable native SDK; this is an executable CPU pixel screen, **not** a direct
Skia C++ performance comparison. `tools/benchmarks/t068_skia_cpu.py` creates
CPU-only `SkSurface.MakeRasterDirect` surfaces, uses explicitly disabled
antialiasing for rectangular parity, and checks the *same* independent
straight-RGBA8 oracle and checked C++ kernel as Blend2D and Cairo.

To reproduce using the uploaded wheel without installing anything in the
Drawing/Atlas repository:

```bash
python3.13 -m pip install --target /tmp/t068-skia-deps   /path/to/skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl
T068_SKIA_WHEEL=/path/to/skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl PYTHONPATH=/tmp/t068-skia-deps python3.13 -m unittest discover -s tests -p test_t068_skia_cpu.py -v
PYTHONPATH=/tmp/t068-skia-deps python3.13 tools/benchmarks/t068_skia_cpu.py   --wheel /path/to/skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl   --runs 2 --trials 9 --sides 32 64 128   --output /tmp/t068-skia-cpu.json
```

The separate *manual-only* workflow pins the wheel and Python 3.13; ordinary
push CI validates contracts without installing Skia. Two independent runs of
9 trials × 3 sizes × 7 operations × 3 transfer paths yield **126** rect
scenarios. **60** showed non-canonical Skia pixels (30 per run):

| Transfer mode | Non-parity cases per run (of 21) | Untouched hidden RGB | Key distinction |
|---|---:|---|---|
| Direct straight-RGBA8 SkSurface | 3 | Preserved | Only transparent-color replacement disagreed in fixed matrix; two seeded random blend mismatches/run |
| Premultiplied full tile | 15 | Damaged | Source roundtrip alters unpainted bytes, even for zero-alpha source-over |
| Premultiplied region and patch | 12 | Preserved | Touched translucent colors/alpha still differ from canonical rounding |

Example at 64²: direct translucent source-over has **0** disagreements in
this fixed fixture, while region-premultiplied has **782 touched** disagreements
and full-premultiplied additionally has **2,025 untouched** mismatches. Direct
transparent-color replacement loses the explicit color in **1,024** touched
zero-alpha pixels; it is **not** equivalent to Drawing's replacement rule.
Skia's straight RGBA8 surface sometimes reproduces exact source-over values,
but 16 seeded randomized sources × 3 operations exposed **2 touched rounding
mismatches per run**, with zero untouched modifications. Do not silently
consider the six fixed matrix passes proof of universal exactness.

An independent CPU SkPath quadratic triangle screen produces **634** hard-edge
changed pixels and **737** AA changed pixels (including **83** partial-alpha
edge pixels) in a 64² image; every modified byte stayed in its conservative
bounds and both runs were deterministic. There is **no** canonical hard-brush
geometry, mask or gesture oracle for this AA screen, so it is capability
coverage rather than exact functional acceptance.

For the 64² opaque source-over fixture the two independent run medians are:
C++ kernel call **30.827/30.786 µs**, Skia direct draw-only **6.129/3.015 µs**,
and Python Skia direct create+copy+draw **25.678/15.523 µs**. By contrast,
premultiplied full-image conversion+render+unconversion costs
**4,004.64/3,644.276 µs** in this deliberately naïve Python path. These
clocks have *different* setup, language and memory-copy boundaries; there is
no valid native performance ranking or claim of user-visible acceleration.

**Decision by operation:** keep canonical Godot/direct C++ pixel publication
for exact source-over/replace, hidden alpha, masks, and undo. Direct Skia
RGBA8 is interesting for noncanonical previews or later vector AA/shape
support, but its 0-alpha source replacement and rare source-over rounding
must be addressed and independently retested before any canonical backend
consideration. Retain Skia as an optional comparator only; no binary or
runtime dependency was added to the shipped application. Outstanding:
matched native C++ Skia/marshalling benchmarks, real brush/path masks and
transforms, portable Godot extension/standalone builds, Windows and Linux
physical end-to-visible p95 and RAM/VRAM/multithread results. **T-068 stays
In Progress.** Raw evidence: [Skia CPU JSON](benchmarks/T068_2026-11-04_skia_cpu.json).


## 2026-11-04 optional Skia vs *canonical Godot brush* stencil screen

The [prior Skia rectangle and standalone quadratic path screen](#2026-11-04-optional-skia-python-1441-cpu-rgba8--path-screen-not-adoption)
confirmed the CPU API runs but did not compare Skia geometry against the
**actual** Drawing hard brush. The new experiment freezes a Godot 4.8 beta 2
fixture from `DrawingEditSession` rather than defining a supposedly equivalent
Python stroke oracle. Each case authors a new 32² document with an RGBA8 tile
containing zero-alpha *hidden RGB* and uses far signed anchors beyond 2^53;
its `coverage_indices` include no-op covered pixels, while `changed_indices`
and `after_sha256` describe the actual committed transaction. The independent
Python `source_over` oracle confirms all 11 generated case digests and
changed-pixel sets. Continuous vs split-batch strokes produce identical Godot
coverage and commits, including overlap semantics.

Reproduce with the **externally installed**, SHA-pinned Skia 144.1 wheel:

```bash
# Regenerate the frozen Godot fixture (check JSON equality before replacing it).
godot --headless --path . --script res://tests/drawing_t068_skia_brush_oracle.gd -- /tmp/t068-godot-brush.json
T068_GODOT=godot python3 -m unittest discover -s tests -p test_t068_skia_brush.py -v
# The second invocation requires Python 3.13 and the optional installed wheel.
T068_SKIA_WHEEL=/path/to/skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl \
  python3.13 -m unittest discover -s tests -p test_t068_skia_brush.py -v
python3.13 tools/benchmarks/t068_skia_brush.py \
  --wheel /path/to/skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl \
  --runs 2 --trials 7 --output /tmp/t068-skia-brush.json
```

The live runner uses CPU `SkSurface.MakeRasterDirect` on **A8** for one
non-antialiased round-capped, round-joined Skia stroke and also executes the
same shape directly against a detached straight-RGBA8 surface. It independently
replays a software canonical blend over the Skia-generated stencil. A
rectangular, sparse, or inverted selection is applied *after* drawing in
Python, not implemented with Skia's native clip API. Neither the Skia
prototype nor its fixture is linked to the real Drawing application.

| Godot fixture group | Cases per run | Skia stencil coverage errors | Direct RGBA8 case errors | Observation |
|---|---:|---:|---:|---|
| Stationary, axis-aligned and diagonal hard brushes | 4 | 0 | 0 | Exact in **these fixtures only** |
| Self-crossing whole / split-batch gesture | 2 | 2 × one missing pixel | 2 × one mismatched pixel | Skia's stroked path does not cover every Godot brush pixel |
| Rectangle, sparse, inverted post-selection | 3 | 0 | 0 | Tested postmask semantics, **not** native Skia clipping |
| Erase on source with hidden transparent RGB | 1 | 0 | 0 | Exact bounded erased pixel bytes |
| Alpha-zero self-crossing | 1 | 1 missing coverage pixel | 0 | Coverage differs even when output bytes are a no-op |

Two independent runs, each seven timing trials per case, reported the same
three coverage exceptions per run (**6/22**), and two direct-pixel exceptions
per run (**4/22**). The exact same geometry gap is present when Skia's stencil
is blended with the independent canonical math, so replacing Skia's color
compositor alone cannot achieve hard-brush parity. Shape mask and draw-only
microseconds are included as **descriptive Python-call diagnostics** in
[`T068_2026-11-04_skia_brush.json`](benchmarks/T068_2026-11-04_skia_brush.json);
they omit surface creation, selection postmask, native API marshaling, Godot
history/publication and GPU display. No backend speedup is inferred.

**Operation-level decision:** retain the existing canonical Godot brush,
mask and undo implementation for exact editing. Skia CPU is still a candidate
for *future noncanonical previews or quality-directed AA paths*, not a drop-in
source of hard brush geometry, even if its alpha math were corrected in a
postpass. A future native test must explicitly compare all path cap/join,
transformed masks, clipping and same-gesture repeated-sample cases, and must
measure native C++ and Godot upload boundaries before any integration decision.
Physical Windows/Linux p95 and memory/VRAM, standalone release packaging and
user-facing latency gates also remain open. **T-068 is In Progress.**


## 2026-11-04 Skia vs transformed Godot brush follow-up (not adoption)

A schema-2 regeneration of `tools/benchmarks/t068_skia_brush_oracle.json`
adds five real `DrawingEditSession` non-identity view transforms. Godot
receives the **transformed view-space** points and freezes a transform for
the gesture; the source tile and `DrawingSelection` remain **raster-local**
and use signed global anchors beyond 2^53. The five transformations are
uniform zoom/pan with rectangular selection, 90° rotation with inverted
selection, x-mirroring with self-overlap, nonuniform scaling with a sparse
pixel mask, and shear while erasing pixels that may contain hidden RGB.
Brush width is deliberately raster-local, as it is in the canonical API;
this comparison does not model screen-space brush scaling or rotated grid
cells from Atlas.

The independent Python reader now inverts all serialized view samples,
rejects malformed/singular matrices or inconsistent local paths, verifies
canonical source-over and checked Godot output digests, and insists that
each transformed case matches its untransformed geometric baseline. These
are deterministic exact-pixel **correctness** fixtures, not native-compute
or hardware-timing measurements. Reproduction:

```bash
godot --headless --path . --script res://tests/drawing_t068_skia_brush_oracle.gd -- /tmp/t068-transform-oracle.json
T068_GODOT=godot python3 -m unittest discover -s tests -p test_t068_skia_brush.py -v
# For live Skia checks, add externally installed 144.1 to PYTHONPATH and set T068_SKIA_WHEEL.
python3.13 tools/benchmarks/t068_skia_brush.py \
  --wheel /path/to/skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl \
  --runs 2 --trials 7 --output /tmp/t068-skia-brush.json
```

| Additional transform case | Coverage difference per run | Direct RGBA8 difference | Interpretation |
|---|---:|---:|---|
| Zoom/pan + raster-local rectangle | 0 | 0 | Tested view-to-local coordinates, not native clip |
| 90° rotation + inverted rectangle | 0 | 0 | Same local coverage as untransformed case |
| Mirrored self-crossing | 1 Godot pixel missing | 1 pixel | Mirrors existing Skia stencil counterexample |
| Nonuniform scale + sparse postmask | 0 | 0 | Tested declared raster-local width |
| Shear + hidden-RGB erase | 0 | 0 | No untouched byte changed |

Across **16 cases/run × 2 independent seven-trial runs** (32 total), **eight**
cases have noncanonical Skia coverage, and **six** have noncanonical
straight-RGBA8 output; the same discrepancies repeat both runs. Of those,
the five new transform cases add one coverage and one final-pixel mismatch
per run. Skia A8 and direct RGBA8 still draw in **raster-local coordinates**
after Python inverse mapping; selection is applied afterward in Python.
Thus this check neither implements native Skia transforms/clipping nor tests
GDExtension marshaling and does not resolve physical Linux/Windows latency,
RAM/VRAM or portable-release acceptance. The pinned two-run JSON was refreshed
in [`T068_2026-11-04_skia_brush.json`](benchmarks/T068_2026-11-04_skia_brush.json).
**Keep canonical Godot brushes and T-068 In Progress.**


## 2026-11-04 isolated Godot GDExtension marshaling density screen

Repro: `python3 tools/benchmarks/t068_bridge/run_bridge.py --godot
/path/to/Godot_v4.8-beta2_linux.x86_64 --runs 2 --output /tmp/t068.json`.
The manual-only runner builds the checked scalar C++ GDExtension against the
engine-generated header in a throwaway project. It now adds
`t068_marshal_profile.gd` with the same source, mask and precovered point array
for whole-tile typed ptrcall, whole-tile generic `Variant` call and sparse
native output; the copy-only control duplicates the input packed bytes. The
canonical `_blend` oracle and strict count/index/before/after decoder verify
all touched *and untouched* RGBA8 values **outside the measured intervals**.

**Two independent runs; 16 timed calls/mode/workload per run, with three
warmup calls each; microseconds below are *ranges of per-run medians*, not
confidence intervals or physical latency:**

| Tile / precovered workload | Changed pixels | Full / sparse native return | Full direct µs | Sparse direct µs |
|---|---:|---:|---:|---:|
| 32², one point | 1 | 4,096 / 16 B | 1 / 1 | 1 / 1 |
| 32², sparse masked | 101 | 4,096 / 1,216 B | 4 / 4 | 4 / 4 |
| 32², dense overlapped | 202 | 4,096 / 2,428 B | 7 / 7 | 7 / 7 |
| 128², one point | 1 | 65,536 / 16 B | 5 / 4 | 1 / 1 |
| 128², sparse masked | 102 | 65,536 / 1,228 B | 8 / 7 | 4 / 4 |
| 128², dense overlapped | 3,277 | 65,536 / 39,328 B | 99 / 99 | 103 / 103 |
| 256², one point | 1 | 262,144 / 16 B | 15 / 16 | 1 / 1 |
| 256², sparse masked | 102 | 262,144 / 1,228 B | 19 / 19 | 4 / 4 |
| 256², dense overlapped | 13,106 | 262,144 / 157,276 B | 412 / 456 | 502 / 434 |

Raw records include **p95, min/max, generic Variant call, duplicate-call
controls, input point/mask byte counts and the immutable-source proof**:
[`T068_2026-11-04_gdextension_marshal.json`](benchmarks/T068_2026-11-04_gdextension_marshal.json).
Both runs passed **731/731** marshal checks and 443/370/219/128/173 existing
native/texture/document/batch/sparse checks, respectively. The Python harness
requires all nine unique workloads and plausible sample ordering before
accepting evidence; fast runner-contract tests mutate evidence to verify this.

**Interpretation:** sparse native output reduces return bytes dramatically for
small edits, but still pays for packed source and point input, mask handling,
and kernel bookkeeping. Dense sparse output can be slower than whole-tile output.
The nominal 0-µs duplicate readings reflect the integer-microsecond clock's
resolution, not zero copying. No meaningful physical p95 can be inferred from
16 short samples. This is **not** a direct comparison with GDScript's geometric
brush rasterization, full Document publication, or Skia/Blend2D C++ paths.
Selection masking is consumed by the checked native batch, but transformed
four-corner geometry is not generated by this benchmark. The experimental
bridge remains isolated from production Drawing and Atlas; physical GPU,
Windows builds, native publishing cost and release acceptance are still open.


## 2026-11-04 native Blend2D A8 brush and C++ selection/straight-RGBA8 screen

The pinned Blend2D **0.21.2** source release with bundled AsmJit now runs a
*detached* C++ brush-path benchmark against the same real Godot
`DrawingEditSession` 16-case, 32×32 hard-brush/selection fixture as the Skia
screen. Unlike the prior premultiplied-rectangle test, Blend2D is used **only
to rasterize an A8 coverage stencil**. The shim thresholds alpha, applies
binary rectangle/sparse/inverted eligibility in **native C++**, and invokes
Godot's canonical straight-RGBA8 source-over/erase formula once per accepted
pixel. A source with alpha=0 and hidden RGB is never converted to PRGB32;
unpainted bytes remain exact, including under masking. Original inputs are
immutable; error paths do not partially publish detached outputs. Five frozen
view transforms are inverse-mapped in Python to raster-local geometry, not
executed as a native transformed four-corner clip.

**Two independent runs × seven trials × 16 cases × two A8 thresholds**
produce 64 comparisons. The following counts are *per run*:

| Native A8 cutoff | Exact Godot coverage | Cases with coverage mismatch | Cases with final RGBA8 mismatch | Interpretation |
|---|---:|---:|---:|---|
| `>=128` | 14/16 | 2 | 2 | Two inverted-selection cases each miss one Godot-covered pixel; all other cases match exact RGBA8 |
| `>=1` | 0/16 | 16 | 15 | Even small AA fringes overpaint; the remaining alpha-zero case leaves RGBA8 unchanged |

The independent Python validator reconstructs the full output from the
recorded native coverage and checked Godot source, recomputes SHA-256 and
changed/mismatched counts, verifies selection containment and compares
both independent runs. `tests/test_t068_blend2d_brush.py` injects invalid
native call lengths, nonfinite widths, invalid masks, aliasing and alpha
thresholds; sentinel buffers and timings must remain untouched. Untrusted
third-party bytes are not committed; the optional CI workflow checks the
SHA-256 of the downloaded archive before compiling. Raw native stencil,
canonical C++ compositor, ctypes preparation/call/extraction timings and
per-case missing/extra indices:
[`T068_2026-11-04_blend2d_brush.json`](benchmarks/T068_2026-11-04_blend2d_brush.json).

Reproduce with an externally built `libblend2d.so` (no changes to shipped
Drawing or Atlas code):

```bash
T068_BLEND2D_ARCHIVE=/path/to/blend2d-0.21.2.tar.gz \
T068_BLEND2D_SOURCE=/path/to/blend2d \
T068_BLEND2D_BUILD=/path/to/blend2d-build \
python3 -m unittest discover -s tests -p test_t068_blend2d_brush.py -v
python3 tools/benchmarks/t068_blend2d_brush.py \
  --archive /path/to/blend2d-0.21.2.tar.gz \
  --source /path/to/blend2d --library-dir /path/to/blend2d-build \
  --trials 7 --runs 2 --output /tmp/t068-blend2d-brush.json
```

**Decision:** retain Godot's hard-brush geometry as authoritative; do not
choose Blend2D thresholding as an exact hard-brush replacement on this
limited screen. The masked C++ straight-RGBA8 pipeline is a useful boundary
experiment, **not** a native Godot extension, physical input-to-visible
measurement, complete production CPU workload, or Skia C++ benchmark. T-068
still requires hardware, full-size document, release and approval gates.


## 2026-11-04 detached native Blend2D full-size scaling (not Godot frame timings)

The pinned 0.21.2 C++ A8 path comparator from the earlier 32² Godot parity
screen now supports **512²/1024²/2048²** input/output tiles. It uses
straight-RGBA8 source buffers with nonzero hidden RGB under zero alpha,
three additional alpha classes and independent once-per-pixel canonical
source-over/erase reconstruction. Four synthetic gestures are placed at the
center of each tile with eligible spans of **128 or 256 pixels**, keeping
local path geometry fixed while the surrounding storage region grows:
4px long stroke, 256px round dab, 64px self-crossing sparse-mask erase and
transparent source-over no-op. The synthetic coverage is from **Blend2D**,
not Godot's hard brush; this screen does **not** establish geometry parity.

Two independent runs, three timed calls per case: 3 sizes × 4 workloads ×
2 runs = **24 independently byte-replayed outputs**. The `call_us` medians
include Python `ctypes` call and native stencil/composition but exclude
Python input preparation and output unpacking (both separately recorded).
All timings below are *ranges of the two run medians*; just three samples
per cell cannot establish a reliable p95 or production speedup.

| Storage side | 4px stroke call median | 256px dab call median | Sparse crossing erase call median | Transparent no-op call median | Whole-tile output bytes |
|---:|---:|---:|---:|---:|---:|
| 512 | 706–900 µs | 1,571–1,720 µs | 556–725 µs | 491–552 µs | 1 MiB |
| 1024 | 3,180–3,322 µs | 3,129–3,370 µs | 2,334–2,921 µs | 2,183–2,647 µs | 4 MiB |
| 2048 | 13,502–15,483 µs | 10,622–11,914 µs | 11,153–13,061 µs | 11,146–11,294 µs | 16 MiB |

The 4px gesture changes only **460 pixels** at every size, yet the same
full-size returned RGBA8 buffer scales from 1 to 16 MiB. Under an entirely
separate **hypothetical** display grid, four touched 128² tiles would require
256 KiB, and four touched 256² tiles would require 1 MiB of full-tile updates.
These values are **computed** from changed pixels and region geometry, not
measured GPU transfer, GDExtension output, or evidence that `ImageTexture`
supports subrectangle uploads. Actual native-compositor work also includes
a full-tile scan and source copy, explaining why no-op calls still scale.
Selection and final RGBA8 bytes, compressed native selected-pixel masks,
no-op preservation, dirty-region counts and native timing samples are
fail-closed in [the two-run raw results](benchmarks/T068_2026-11-04_blend2d_scale.json).

Reproduce after building the externally pinned `libblend2d.so`, without
copying the library into the repository:

```bash
T068_BLEND2D_ARCHIVE=/path/to/blend2d-0.21.2.tar.gz \
T068_BLEND2D_SOURCE=/path/to/blend2d \
T068_BLEND2D_BUILD=/path/to/blend2d-build \
python3 -m unittest discover -s tests -p test_t068_blend2d_scale.py -v
python3 tools/benchmarks/t068_blend2d_scale.py \
  --archive /path/to/blend2d-0.21.2.tar.gz \
  --source /path/to/blend2d --library-dir /path/to/blend2d-build \
  --runs 2 --trials 3 --output /tmp/t068-blend2d-scale.json
```

**Conclusion:** the fixed output-size scan/copy penalty is measurable under
large canonical storage strides; pursue bounded region and sparse native
publication experiments before considering native adoption. Transformed
four-corner selection/Godot brush parity, Skia native C++ matching, real
Godot marshaling, physical Windows/Linux p95/RAM/VRAM and standalone release
validation remain open. T-068 is **In Progress**.


## 2026-11-04 actual large-tile Godot hard-brush parity (not a speed benchmark)

The previous 512/1024/2048 benchmark measured isolated native CPU work and
reconstructed its straight-RGBA8 output, but the input stencil came from
Blend2D itself. The new
[`drawing_t068_blend2d_large_oracle.gd`](../tests/drawing_t068_blend2d_large_oracle.gd)
compares those **same geometries and masks** against actual Godot 4.8b2
`DrawingEditSession` hard-brush coverage, at signed world anchors
`9007199254740993,-9007199254740993`. Every storage side uses a centered
128/256 pixel-local eligibility region; each gesture's view path is
transformed and inversed inside Godot (zoom, 90° rotation, shear, identity).
The Godot document begins *blank* and its detached gesture is cancelled
after recording coverage; this is a geometry oracle, **not a full real-Godot
mixed-opacity source/output comparison**. For final-pixel mismatch counts,
Python applies the independent canonical straight-RGBA8 blend/erase oracle
to the same mixed-opacity input as the already verified native runs.

**50% native A8 threshold; two independent stored native runs, 12 cases each:**

| Workload | Godot covered / size | Native covered / size | Missing native coverage (512/1024/2048) | Extra native coverage | Canonical final-pixel mismatches (per run) |
|---|---:|---:|---:|---:|---:|
| 4px long stroke | 460 | 460 | 0 / 0 / 0 | 0 | 0 / 0 / 0 |
| 256px round dab | 51,468 | 51,432 | 36 / 36 / 36 | 0 | 36 / 36 / 36 |
| 64px sparse crossing erase | 27,258 / 27,137 / 27,258 | 27,243 / 27,114 / 27,243 | 15 / 23 / 15 | 0 | 15 / 23 / 15 |
| Transparent no-op | 7,068 | 7,046 | 22 / 22 / 22 | 0 | 0 / 0 / 0 |

**Across both runs:** 24 comparisons, 18 coverage non-parity cases, 12
RGBA8 non-parity cases, 454 missing native-covered pixels and zero extras.
An alpha-zero no-op still tests stencil footprint but, correctly, does not
modify hidden RGB. The complete compressed masks are replayed (not inferred
from these summary counts). Fail-closed tests check the binary DEFLATE length,
strict case set, transform inversion, exact selection containment, source
specification, representative full-buffer pixels and evidence-tampering.
Regenerate the Godot fixture and compare JSON payloads with:

```bash
T068_LARGE_GODOT=/path/to/Godot_v4.8-beta2_linux.x86_64 \
  python3 -m unittest discover -s tests -p test_t068_blend2d_large_parity.py -v
python3 tools/benchmarks/t068_blend2d_large_parity.py \
  --output /tmp/t068-blend2d-large-parity.json
```

The [raw 24-row cross-implementation evidence](benchmarks/T068_2026-11-04_blend2d_large_parity.json)
links SHA-256 digests of both the Godot and native scaling fixtures; the
optional Blend2D workflow also accepts **fresh checked native runs**. No
new native timing or Godot/GDExtension/physical presentation numbers arise
from the comparison. The observed 256px-edge misses prohibit treating an
A8 threshold of 128 as exact Godot hard-brush semantics. T-068 remains
In Progress pending transformed four-corner clipping, native Skia C++ and
matched publication benchmarks, physical Windows/Linux RAM/VRAM/p95 and
standalone-release validation. No production backend was changed.

## 2026-11-04 native convex four-corner selection micro-contract

A detached native Blend2D bridge now constructs **binary scope eligibility**
from all four transformed raster pixel corners, rather than accepting only a
precomputed local mask. Godot's real `AtlasFill._allows_pixel()` produced eight
64² scope fixtures (identity, rotation, shear, mirror, nonuniform transform
with density, diamond, disabled and empty). In two native passes, **16/16
masks matched byte-for-byte**, including exact counts 1,056, 1,008, 1,397,
1,258, 1,505, 1,059, 4,096 and 0. The C++ function is failure-atomic and
its mask is consumed by the existing detached once-per-pixel Blend2D brush
compositor without changing canonical straight-RGBA8 or untouched hidden RGB.

The fixtures **exclude exact transformed corners on scope polygon edges**.
An initial aligned nonuniform-scale case differed on 43 edge-tie pixels,
so boundary inclusion remains **unverified**, not fixed by this research
patch. This isolated mask computation contains no raster brush geometry,
Godot UI publication, physical GPU, CPU-to-present timing or backend selection.
See [pinned native evidence](benchmarks/T068_2026-11-04_blend2d_quad.json),
`tests/drawing_t068_quad_scope_oracle.gd`, and
`tools/benchmarks/t068_blend2d_quad.py`.


## 2026-11-04 follow-up — boundary-inclusive native polygon scopes

The previous eight-case native/Godot four-corner scope comparison excluded
pixel-quad vertices on the exact boundary. The detached C++ selection predicate
now accepts points exactly on a segment, matching Godot's documented inclusive
`Geometry2D.is_point_in_polygon()` result for these cases. An independently
regenerated Godot fixture adds seven boundary-tie scenarios: CW and CCW
rectangles, rotation, shear, nonuniform raster density, diamond corners and a
one-pixel strip. The two-run pinned evidence covers **30 byte-exact masks of
64×64 pixels**, with **zero missing or extra coverage**; individual rectangle
and strip pixels are also independently checked in Python.

This is narrow CPU-only correctness evidence. It does **not** demonstrate
Godot's approximate boundary comparisons at arbitrary near-edge floating
coordinates, a complete optional native integration, exact Blend2D brush
footprints, display/GPU publication cost or hardware acceptance. T-068
remains **In Progress**, and the production raster backend is unchanged.
See [raw evidence](benchmarks/T068_2026-11-04_blend2d_quad.json).


## 2026-11-04 — isolated scalar C++ hard-brush coverage compared with Godot

A small **dependency-free C++17 scalar** comparator now screens the native
hard-brush geometry that Blend2D A8 thresholding cannot reproduce exactly.
It evaluates pixel-center distances to round swept segments and unions their
coverage once before enforcing a binary pixel-local selection. The comparison
reuses actual Godot-generated oracle output rather than a Python-generated
brush stencil. Two complete native passes match **16/16 small 32²** and
**12/12 large 512²/1024²/2048²** cases, or **56/56 total masks**, byte-for-byte.
The comparison also checks re-created canonical straight-RGBA8 results for
small-source fixtures and validates full large bitmap coverage. No new
Godot-side or native timing measurements have been taken: these figures
**must not be represented as speedup or physical responsiveness evidence**.
The detached kernel does not composite, stage detached chunks, marshal through
GDExtension, create undo deltas, or upload display tiles. It does not validate
arbitrary float-tie geometries or transformed board-space quad selection
beyond the separate native mask screen.

Source: `tools/benchmarks/t068_scalar_hard_brush.cpp` and
`tools/benchmarks/t068_scalar_hard_brush.py`; regression:
`tests/test_t068_scalar_hard_brush.py`; raw evidence:
[56 complete comparisons](benchmarks/T068_2026-11-04_scalar_hard_brush.json).

**Operation-specific recommendation unchanged:** keep Godot for canonical
hard-pixel edits while evaluating a *narrow optional scalar/SIMD native path*
for the same semantics. Blend2D remains a candidate for future AA/vector
work, not the canonical hard-brush replacement. Physical and release gates
still block T-068 closure.

## T-068 — isolated scalar native hard-brush and straight-RGBA8 compositing (2026-11-04)

The standalone `t068_scalar_hard_brush.cpp` now exposes a second ABI that
returns detached full-tile RGBA8 and a postselection coverage bitmap from the
same checked C++17 geometry comparator. It blends each covered pixel exactly
once against the original straight RGBA8 source, using Godot's half-away
channel rounding; alpha-zero source-over retains hidden RGB, and erasure clears
all four channels. All caller dimensions, byte capacities, mask values,
geometry parameters, output/input aliases and operation flags must validate
before either output can be modified.

Two independent passes matched **56/56** complete expected coverage and RGBA8
outputs across 28 pinned cases: 16 small Godot oracles including real
`DrawingEditSession` full-pixel hashes; 12 large (512²/1024²/2048²) Godot
*coverage-only* oracles with independent patterned-source pixel reconstruction.
Outputs are hashed and replayed from pinned sources, including changed counts
and selections. See [raw evidence](benchmarks/T068_2026-11-04_scalar_rgba8.json),
[tests](../tests/test_t068_scalar_rgba8.py) and the T-068 ticket.

This is a **functional/parity checkpoint**, not a benchmark speed comparison.
There are no matched Godot-native timings, full-size Godot pixel witnesses,
physical input-to-visible p95, RAM/VRAM or GPU publication results; no production
backend was selected. T-068 remains **In Progress**.


## 2026-11-04 detached scalar hard-brush sparse output screen

The exact-footprint C++17 scalar prototype now supports a **bounded sparse
before/after RGBA8 wire** (4-byte little-endian changed count and 12 bytes per
changed pixel), alongside the earlier full-tile output. It scans tile-local
hard-brush geometry and applies each selected pixel once; only changed pixels
are emitted, with source bytes retained and output capacity/alias errors
rejected before any caller-memory mutation. Two native runs reconstruct all
28 pinned Godot-derived cases exactly (**56/56**). The 16 small cases have
real Godot pixel witnesses; the large cases have Godot coverage witnesses
plus independent RGBA8 composition on a patterned source.

| 2048² workload | Changed pixels | Sparse wire | Whole-tile RGBA8 |
|---|---:|---:|---:|
| 4px long stroke | 460 | 5,524 B | 16,777,216 B |
| 256px dab | 51,468 | 617,620 B | 16,777,216 B |
| Alpha-zero no-op | 0 | 4 B | 16,777,216 B |

These figures are **payload sizes**, not native/Godot interop timing,
publication costs, GPU upload or resident memory. The bounded fixture caller
reserves up to 65,536 changed records; dense edits require a larger explicit
capacity or a full buffer. The implementation and tests remain detached from
Godot and Drawing/Atlas production paths. No native technology was selected.
[Complete reproducible two-run evidence](benchmarks/T068_2026-11-04_scalar_deltas.json).

## 2026-11-04 — scalar sparse brush through Godot's opt-in native boundary

The previously detached C++17 exact hard-brush kernel now has a real
**temporary-project Godot 4.8 beta 2 GDExtension** entrypoint. An 8-argument
call accepts immutable canonical straight-RGBA8, a 0/1 local selection mask,
byte-packed little-endian float64 local stroke samples, brush width and paint,
erase flag, and an explicit maximum number of changed pixels (at most 65,536).
It returns the prior exact sparse before/after record format or an empty
rejection. No native binary or descriptor is shipped with Drawing/Atlas.

Two independent full isolated bridge runs each passed **31 scalar tests**
in addition to every existing suite. For a 16² self-crossing 4px stroke on a
seeded hidden-RGB source, **63 changed pixels** yielded **760 sparse bytes**
versus **1,024 whole-tile RGBA8 bytes**. The native output was compared with
actual `DrawingEditSession.paint_path()` pixel output before a
revision-checked one-step canonical document commit and Undo/Redo. Masked
one-pixel output was 16 bytes; transparent paint was a valid four-byte no-op;
erasure removed all hidden RGB. Malformed input and output-capacity shortage
returned empty rejection without changing source bytes.

This **closes only a tested Godot↔scalar native correctness boundary**. It
omits converted real-time pointer events, measured CPU-native call overhead,
large-tile publication timing, GPU uploads, physical-device p95, Windows
binaries and standalone release proofs. In particular, the test precomputes
raster-local geometry and validates native changes against the complete
Godot oracle before allowing publication; this is *not* a production adapter
or a claim that untrusted native deltas can be accepted without independent
completeness checking.

[Two-run scalar native integration evidence](benchmarks/T068_2026-11-04_scalar_gdextension.json) ·
[reproduction harness](../tools/benchmarks/t068_bridge/run_bridge.py) ·
[contract tests](../tests/test_t068_scalar_gdextension.py).


## 2026-11-04 — counterbalanced opt-in Godot/native publication timing

The research-only Godot 4.8 beta 2 C++17 scalar GDExtension bridge compares
real canonical `DrawingEditSession.paint_path()` + commit to native sparse
brush generation + checked decoding + detached staging + commit on **identical
fresh sources**. The previous fixed-order five-sample diagnostic is replaced
with a two-warmup/six-timed-trial paired design **alternating which path runs
first**, with three samples per execution order and six workloads per run.
An untimed trusted Godot oracle is computed once per workload before the timed
pairs, and native bytes must match it before any native edit is staged.
Two independent full bridge runs each passed **536 publication assertions**,
including pixel-exact native reconstruction, hidden RGBA8, one revision,
Undo/Redo and deterministic sparse counts. All six CPU phase samples, order,
paired totals, and derived min/median/max are retained and independently
validated (schema v2); medians use the upper of the two center samples.

| Tile / gesture | Changed pixels / sparse bytes | Canonical median, two runs | Native path median, two runs |
|---|---:|---:|---:|
| 32² short | 138 / 1,660 B | 1.193–1.916 ms | 0.912–1.538 ms |
| 128² short | 618 / 7,420 B | 8.278–8.575 ms | 6.631–7.287 ms |
| 256² crossing | 1,908 / 22,900 B | 18.955–21.991 ms | 13.371–13.631 ms |

**These observations do not establish a production speedup.** A total is
computed per trial (rather than summing independently reported medians).
Alternating order removes one *systematic* bias, but six samples per case,
headless execution, run-to-run variability, unmatched inner staging
algorithms and possible cache/thermal noise preclude a robust performance
claim. Source/document construction, path packing, one untimed canonical
oracle computation per workload, whole-tile verification, Undo/Redo,
and UI/event/render/GPU/present work occur outside the timing boundaries.
The optional binary lives only in the temporary test project, not a
standalone release or Drawing runtime.

Reproduce with `python3 tools/benchmarks/t068_bridge/run_bridge.py --godot
/path/to/Godot_v4.8-beta2_linux.x86_64 --runs 2 --output /tmp/t068.json`.
[Source-pinned counterbalanced two-run timing](benchmarks/T068_2026-11-04_scalar_publication.json)
· [evidence validator](../tests/test_t068_scalar_publication.py).
T-068 remains **In Progress**.


## 2026-11-04 — transformed native sparse brush correctness screen (not timing)

The isolated, explicit-load Godot 4.8 beta 2 GDExtension now compares six
**32×32 and 64×64** cases against actual canonical
`DrawingEditSession.paint_path()` painting. Godot first applies a view
transform (identity, rotation, shear, mirroring, nonuniform scale or zoom/pan)
and constructs a rectangular, inverted or sparse binary selection; the
client inverts the view-space path to local float64 samples for the native
scalar kernel. The verified native sparse before/after records are reconstructed
into exact straight-RGBA8 and compared byte-for-byte with the independent Godot
output before staged publication. Undo/Redo, a hidden-RGB source, real erasure,
mask confinement and insufficient-capacity rejection are covered.

| Case | Side | Changed pixels | Native sparse bytes |
|---|---:|---:|---:|
| Identity rectangle | 32² | 92 | 1,108 |
| Rotated inverted selection | 32² | 24 | 292 |
| Sheared sparse erase | 32² | 27 | 328 |
| Mirrored crossing gesture | 64² | 596 | 7,156 |
| Nonuniform inverted sparse erase | 64² | 62 | 748 |
| Zoom/pan single dab | 64² | 13 | 160 |

**Two independent full native runs passed 110/110 new correctness checks each,
with identical pixel hashes and sparse counts.** The source-pinned evidence
is [here](benchmarks/T068_2026-11-04_scalar_transform.json), and the
[opt-in runner](../tools/benchmarks/t068_bridge/run_bridge.py) verifies it.
The transformed binary mask is computed in Godot, **not** by the native
Atlas four-corner convex scope implementation. This is not a benchmark
of real input latency, staging throughput, texture upload, Windows behavior,
peak memory, or a portable release, and cannot justify changing the runtime
backend. T-068 remains **In Progress**.
