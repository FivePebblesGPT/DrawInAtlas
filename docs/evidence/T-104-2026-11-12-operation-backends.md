# T-104 — operation-specific raster backend decision (2026-11-12)

**Decision:** keep optimized **GDScript/Godot** as the portable hard Brush/Eraser,
source, history and display default. Retain **NativeHard only as an optional**
verified hard-brush path, and **Hokusai only for its opt-in `.myb` natural-media
model**. **Reject** Blend2D/Skia as drop-in hard-brush replacements on existing
fixtures; **defer** third-party CPU engines for fill, shapes/text and display
until an *operation-matched* editor-level benchmark passes canonical parity.
No new runtime dependency, binary, feature, or renderer backend is introduced.
This is T-104's bounded **research decision**, not T-068/T-095/T-096 closure,
T-105 portability, or physical-device acceptance.

## Evidence fidelity and acceptance boundaries

- Source: local branch `6f6032471b327d2327e57117aab106c489294479`
  (T-103), after T-099/T-100/T-101/T-102. At the time checked, PR #17's last
  published remote HEAD remained `79b8959e9eac01b3bb10a144a46407acc6901aed`.
  T-052 and T-097 are Done. No owner/manual gates were altered.
- **Pinned replay:** `python3 tools/benchmarks/t104_backend_decision.py --verify`
  validates T-068 matched native ABI parity against independently generated
  Godot 32²/512² straight RGBA8, large masked source/hard-brush oracle,
  signed-anchor Skia fixture, 512/1024/2048 Linux worker HWM records, and
  ABBA synthetic Godot frame data. The `T104_2026-11-12_backend_decision.json`
  file records all ten native pairs, 16 Skia cases, nearest-rank warm-call
  p50/p95 per pair, and exact source/evidence digests. Tampering with the four
  archived source records, equality decisions, p95, or memory fails tests.
- Source-data SHA-256: matched native
  `dafefde39ed0e16ef4c111c540b8e29387aca0b7638c32e9113045fd10392e34`,
  fresh native-worker memory
  `77246a21c96148caf21f533f54611dd0ce7d8ac1232e7d9b7b42185da5045d56`,
  Skia
  `f1df8bef7828046e7b0fff4ed16f0f37d3a194830a96f76b50da57c9483ab37f`,
  and software Godot ABBA
  `d4a23ae81b524552957cf2fc66ff345b27d5bbb677b651b9920700369f7da80f`.
  Those archives were generated in the earlier T-068 experiment; this ticket
  **replays and audits** rather than pretending they were freshly rebuilt.
- **Time-boundary warning:** both detached native ABIs are preallocated and
  *prewarmed*, with two runs × five counterbalanced calls. The provided
  p50/p95 are **warm kernel ABI**, excluding input, Godot stage/preview,
  publication, source storage, display and VRAM. They are not cold editor or
  like-for-like Skia/Hokusai results. Linux worker `/proc` HWM includes Python
  and ctypes buffers, **not isolated library heap**, and cannot be conflated
  with the Godot process memory below.

## Identical-source matched kernels (from pinned T-068 controls)

| Godot-generated fixture | Scalar C++ warm p50/p95 (µs) | Blend2D 0.21.2 warm p50/p95 (µs) | Direct canonical equivalence |
| --- | ---: | ---: | --- |
| 32² stationary dab | 10 / 25 | 11 / 22 | Exact |
| 32² horizontal fractional | 18 / 19 | 13 / 22 | Exact |
| 32² diagonal | 19 / 38 | 13 / 17 | Exact |
| 32² self-crossing | 37 / 72 | 28 / 34 | Exact |
| 32² hidden-RGB erase | 16 / 43 | 10 / 16 | Exact |
| 32² zero-alpha no-op | 26 / 28 | 10 / 15 | Exact |
| 512² 4px long stroke | 782 / 976 | 607 / 798 | Exact |
| 512² 256px round brush | 2,365 / 7,864 | 1,990 / 3,562 | **36 missing pixels** |
| 512² sparse crossing erase | 1,465 / 3,435 | 738 / 1,215 | **15 missing pixels** |
| 512² transparent no-op | 772 / 1,053 | 600 / 679 | **22 missing coverage pixels**; changed RGBA8 still matches due no-op |

The seven exact cases out of ten (**7/10**) are a subset, not an automatic backend selection.
The last three faster Blend2D figures are **not comparable backend wins**:
geometry disagrees with the Godot reference. The scalar custom kernel matches
this subset but has not been measured as a shipping full-editor replacement;
its detached microseconds do not justify adoption. Skia 144.1's independent
16-case Godot source fixture disagrees in continuous and batched crossing,
mirrored crossing, and no-op coverage. Its Python shape mask uses postcomputed
selection and inverse-mapped transforms, *not* a Godot Skia native bridge;
calling it operation-identical is unsupported.

On the only recorded native memory workload with exact common parity (4px
long stroke), the archived fresh Linux worker HWM p50/p95 (MiB, binary) was:

| Side | Scalar | Blend2D |
| --- | ---: | ---: |
| 512² | 101.35 / 101.36 | 103.37 / 103.65 |
| 1024² | 121.00 / 121.03 | 123.00 / 123.12 |
| 2048² | 198.93 / 198.93 | 200.77 / 200.97 |

Per worker, input+mask = 5 × side² bytes and full RGBA8 output = 4 × side²
bytes before native temporary allocation. This is not editor RAM, native heap
isolation, or GPU VRAM.

## Editor operation boundary — same 96px hard Brush

Pinned Godot `4.8.beta3.official.c51ff06e8`, Linux Mesa 25.0.7 llvmpipe,
Xvfb 1280×900×24, Dummy audio. Both use the same injected 100 mouse events,
96px opaque red, full 512² document, 296 staged segments, 262,144 byte-exact
red source pixels, one history revision and Undo/Redo. They include input
handling, source staging/publication, preview composition, texture creation
and a Godot post-draw callback. The callback is **not physical photons**.

T-102's bounded cold display scheduler means one `frame_post_draw` no longer
proves all newly committed corners are visible. A **red control** on the old
witness asserted four false framebuffer failures in each original Legacy and
NativeHard software run **despite exact source hashes** (process and strict
checker exit 1). The updated witness retains its original time-to-first
postdraw metric, then waits **up to 40 extra process/postdraw pairs** for
`cold_tiles_deferred == 0` and checks the framebuffer at all four corners.
One-step Undo/Redo and source assertions remain unchanged. No engine render
code or latency budget was altered.

| Validated same-source run | First callback (ms) | Stage CPU (ms) | Publish CPU (ms) | Preview compositor CPU (ms) | Extra settlement frames | Godot static peak (MB) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Legacy cold, 3-run process | 4,889.509 | 1,492.519 | 1,312.842 | 853.637 | 6 | 183.1 |
| Legacy warm, same process #2 | 4,026.180 | 1,275.913 | 763.169 | 804.770 | 7 | 193.7 |
| Legacy warm, same process #3 | 4,259.148 | 1,367.092 | 823.546 | 889.598 | 5 | 193.7 |
| NativeHard cold, separate one-stroke process | 4,205.329 | 1,240.355 | 1,035.119 | 809.046 | 6 | 183.0 |

The exact NativeHard single-run values are in the retained raw log; they do
not establish a matched warmed cohort. The **three-stroke NativeHard** trials
printed the successful marker but the outer command did **not** return
successfully before its watchdog. They are **excluded** from accepted
cold/warm editor statistics. A success marker alone cannot override process failure.

- Legacy warm first-postdraw **p50/p95 = 4,026.180 / 4,259.148ms** (n=2);
  full 3-run p50/p95 = **4,259.148 / 4,889.509ms**. The valid NativeHard
  standalone cold one-run value is **4,205.329ms**; no comparable warm
  NativeHard p50/p95 can be asserted from this run. Earlier T-101
  before-T-102 paired three-process NativeHard/Legacy real-pointer witnesses
  gave **4,788.1ms vs 4,780.2ms** median respectively, not a total-gesture
  win. Avoid cross-revision percentage claims.
- Legacy first run used 1,048,576 bytes persistent display textures and
  peak static Godot memory 183,055,360 bytes (~174.6MiB); warmed process
  peak 193,692,952 bytes (~184.7MiB). This is **Godot allocator** memory,
  not total OS RSS or GPU VRAM. Both paths keep a 6ms **soft** drain budget;
  tested drains exceeded 17ms for Legacy and 20ms for NativeHard.
- A separate isolated 65,536-coordinate stage benchmark at the T-101 commit
  measured NativeHard dispatch p50 **232.5ms** versus generic p50 **284.2ms**
  (p95 309.4 vs 415.9ms); input/render/history excluded. The Hokusai
  60px `.myb` preset at T-101 staged p50 around **197.7ms** and spent about
  14–15ms in its native paint call, with source and Undo checks, but its
  pigment/pressure/preset semantics are **not equal** to the 96px hard Brush.
  It must not appear in the same hard-brush speed ranking.

**Raw evidence retained in this commit:**
`docs/evidence/t104-raw-logs/` contains the two passing single-stroke
Legacy/NativeHard runs and the passing three-stroke Legacy run, alongside the
old-witness red controls and a **non-accepted** NativeHard multi-stroke log.
Exact SHA-256 and outcome are derived from these files; a printed
`T095_FULL_CANVAS_PASSED` without an observed exit 0 **is not a pass**.

## Operation-by-operation recommendation

| Operation | Default / optional | Blend2D / Skia | Decision |
| --- | --- | --- | --- |
| Hard Brush/Eraser, signed/masked + hidden RGB | Optimized Godot/GDScript; NativeHard stays optional | 3/10 Blend2D geometry differences; 4/16 Skia cases differ | **Choose GDScript**, **defer** any native default; **reject** both third-party drop-ins |
| `.myb` pigment / natural media | Current opt-in Hokusai/GDExtension with no-native fallback | Not equivalent brush mechanics | **Choose** existing optional Hokusai for presets only; no cross-model ranking |
| Flood fill, source selection | Existing GDScript sparse/tile source | No matched end-to-end fill or source transaction | **Defer** native adoption |
| AA paths/shapes/text | No parity-covered equivalent shipping tool | Blend2D/Skia might serve future path raster, not hard Brush | **Defer** decision pending editor feature need and canonical fixture |
| Preview compositing / texture uploads | Existing cache and 128px display tiles | No measured Godot source-to-texture integration | **Choose** current Godot compositor; no raster backend substitution |
| Source publication + Undo | T-100 sparse atomic GDScript path | No candidate with comparable atomic history and rollback | **Choose** current GDScript publication |

## Licenses, binary size, maintenance and hard gates

- **GDScript/Godot:** existing standalone, no extra native dependency;
  simple portable fallback and source-authoritative semantics. Still misses
  the physical latency target and software frame-stall budgets.
- **NativeHard:** the optional local Rust `DrawingNativeBrush` is already
  wired with source-verified fallback. Hokusai v0.3.0 is **MIT OR Apache-2.0**
  in the supplied offline license manifest; gdext, vendored Rust crates,
  native CPU architecture and per-OS builds require continued maintenance.
  `drawing/addons/drawing/native/bin/libdrawing_brush.so` in the local staging
  is ~2.10 MB Linux-only; **not** proof of a portable Windows artifact.
- **Blend2D 0.21.2:** upstream zlib license; bundled AsmJit/JIT and native
  compiler/architecture requirements. Pinned source archive SHA-256 is
  `234ba57a64153c96885a6271f15fdcf6c594ac8cb03adaad19abb8d3b2b533fa`.
  Direct PRGB32 blending is not a substitute for canonical straight RGBA8
  with hidden colors and the reference's exact once-per-coverage rule.
- **Skia 144.1:** BSD 3-Clause; GN/Ninja, larger optional native build,
  codecs/fonts and CPU-surface configuration; Python Skia testing is not an
  integrated C++ GDExtension or Windows portable release. A production
  binary/footprint comparison remains unmeasured.
- **libmypaint:** ISC, upstream has `json-c` as a core dependency; natural
  preset/surface mechanics are not the hard brush/fill/edit/compositor API.
  Not shortlisted as a like-for-like hard-brush replacement.
- Official references: [Blend2D downloads/build](https://blend2d.com/download.html),
  [Blend2D license](https://github.com/blend2d/blend2d/blob/master/LICENSE.md),
  [Skia build](https://skia.org/docs/user/build/),
  [Skia license](https://github.com/google/skia/blob/main/LICENSE),
  [libmypaint README](https://github.com/mypaint/libmypaint/blob/master/README.md),
  pinned local Rust/Hokusai dependency license manifest.

**T-105 independently remains Ready:** Windows/MSVC, portable exports, native
RSS/VRAM/process memory and ABI/build evidence are absent. T-068 remains
`In Progress`. T-095 stays `In Progress`, `manual_review: true`; T-096 stays
`Manual Review`; there is no owner-device acceptance or hosted CI claim.

## Reproduction and results

```sh
python3 tools/benchmarks/t104_backend_decision.py --verify
python3 -m unittest -v tests.test_t104_backend_decision \
  tests.test_t068_matched_brush tests.test_t068_native_memory \
  tests.test_t068_skia_brush tests.test_t068_visual_counterbalanced
python3 tools/validate_ticket_store.py

GODOT=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
python3 tools/build_drawing_app.py --in-place
"$GODOT" --headless --editor --path drawing --import --quit
DRAWING_BRUSH_BACKEND=NativeHard T095_FULL_CANVAS_RUNS=1 \
  timeout 85s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd > /tmp/t104-pointer.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t104-pointer.log \
  --marker T095_FULL_CANVAS_PASSED
```

The new decision suite plus four T-068 source controls: **26 Python tests
passed, five opt-in skips, process 0**. Strict decision JSON verification
passed; the new pointer settle witness **Legacy 0/0** and **NativeHard 0/0**
(process/checker), with exact source/framebuffer/Undo. The original
unsettled pointer witness **Legacy 1/1** and **NativeHard 1/1** due to
four premature corner checks. Hosted runs, native ABI Windows/MSVC, GPU
residency and physical mouse-to-photon remain unverified.
