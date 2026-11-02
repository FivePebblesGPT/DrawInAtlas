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
