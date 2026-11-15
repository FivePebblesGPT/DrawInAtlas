# T-146 — 96px Hokusai hard-round, full-canvas pointer benchmark (2026-11-15)

**Verdict:** **Viable as a real, repeatable full-canvas pigment stroke** on this software-X11 reference setup. The bundled `hard_round.myb` native Hokusai path paints all **262,144 of 262,144** 512×512 source pixels with **zero transparent holes**, but intentionally **does not make opaque Legacy-red pixels**. This closes **the T-146 benchmark**, **not** T-095 physical responsiveness or T-147 native tile-ownership design. The multi-second settled-stroke latency is still unacceptable as a final UX target; do not interpret results as an input-to-photon or production-hardware latency pass.

## Reproduction and identity

- Repo/ref before measurement: `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa` (branch `sprint/2026-11-15`).
- Godot: **4.8 beta 3** (`4.8.beta3.official.c51ff06e8`), binary `/mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64` from `Godot_v4.8b3_rust_hokusai_bundle8.tar.zst`.
- Native **release** GDExtension SHA-256: `e85fcac79311e52c38e291100f8a65321d7cd58756491b899bba086679515b75` (`addons/drawing/native/bin/libdrawing_brush.so`).
- Bundled preset `hard_round.myb` SHA-256: `40838b34344409a0830a3b63f14120113a02635bdbeabd4d69ad2a62d24c5905`.
- Linux + `xvfb-run` 1280×900×24bpp, Godot **X11** display, `gl_compatibility` OpenGL software Mesa 25.0.7 / llvmpipe (LLVM 19.1.7), Dummy audio, `LIBGL_ALWAYS_SOFTWARE=1`. This is **not headless rendering**; the X11 framebuffer is sampled after actual compositor submission.
- Each gesture uses a fresh **512×512** raster document, **96px** hard-round Brush, viewport size/camera/zoom identical to the existing T-095 witness, nine serpentine passes, **99** ordered waypoints, **100** actual `root.push_input` mouse events (down + 98 move + up). All backends share that trajectory. The pointer events are **synthetic**, not a physical pen/mouse.
- Cold = **three independent complete Godot processes**, one gesture each; warm = **one fresh Godot process** with **two gestures** on fresh documents, measuring gestures individually. There are **12 processes / 15 measured gestures**: 3+2 each of Legacy, NativeHard, Hokusai.
- Legacy/NativeHard use the unchanged `t095_full_canvas_brush_native.gd` oracle (every source pixel equals its opaque red reference). Hokusai uses **its own** `t146_hokusai_full_canvas_native.gd` native-required oracle (source alpha distribution, red pigment, all pixels covered, history, framebuffer points, transactions). No cross-backend pixel equality is requested. The preset is **not tuned** or altered.

Commands from the repo root (replace bundle/toolchain path and output directory as needed):

```bash
bash tools/build_native_brush.sh /mnt/data/dev-bundle
python3 tools/build_drawing_app.py --in-place
/mnt/data/dev-bundle/prepare-godot-example.sh drawing res://addons/drawing/native/drawing_brush.gdextension
/mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64 --headless --editor --path drawing --import --quit
/usr/bin/python3 tools/run_t146_hokusai_bench.py \
  --godot /mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64 \
  --output docs/evidence/T-146-2026-11-15-raw --cold 3 --warm 2 --timeout 120
/usr/bin/python3 -m unittest discover -s tests -p test_t146_hokusai_bench.py -v
/usr/bin/python3 tools/validate_ticket_store.py
```

The runner stores **verbatim process logs** (`*.log`), each process's `/usr/bin/time -v` record (`*.time`), command line, exit code, `check_godot_model_log.py` outcome, per-gesture observations, SHA-256 of logs, and medians/percentiles in [raw summary](T-146-2026-11-15-raw/summary.json). It requires both **exit code 0** and the **strict validator** (including success marker); a printed marker alone never passes. All **12/12** real process runs passed, including full-row-major source `SHA-256` across Undo/Redo. No process timeout; no benchmark log was omitted from the table. Following final fail-closed source-coverage and reporter assertions, a separate **one-gesture Hokusai regression** exited 0 and passed the same strict model-log checker ([verification log](T-146-2026-11-15-raw/hokusai-final-regression.log)); it is not counted as an extra matrix sample.

## Matched editor-stroke wall time

Units: **milliseconds**; every measurement is **p50 / p95** with **nearest-rank** percentile. At n=2 or 3, p95 is the **sample maximum**, not a statistically stable tail estimate. Timing `input → settled postdraw` is measured from pointer-down before event dispatch to the first frame-post-draw callback after the **whole gesture's queued input and commit** complete; it does not measure actual monitor photons. `release → commit` uses the existing canvas release and history commit timestamps. `stage CPU` is a summed per-gesture instrumentation counter, not a wall-time fraction.

| Backend | Mode | Gestures (n) | Input → settled postdraw p50 / p95 | Release → commit p50 / p95 | GDScript stage CPU p50 / p95 |
| --- | --- | ---: | ---: | ---: | ---: |
| Legacy | cold | 3 | 5,227.4 / 5,472.2 | 5,179.2 / 5,414.5 | 1,504.5 / 1,518.1 |
| Legacy | warm | 2 | 4,615.4 / 5,188.4 | 4,567.2 / 5,139.5 | 1,378.6 / 1,600.1 |
| NativeHard | cold | 3 | 4,713.3 / 6,480.1 | 4,662.9 / 6,417.9 | 1,406.3 / 1,789.6 |
| NativeHard | warm | 2 | 5,000.6 / 5,150.8 | 4,936.1 / 5,089.1 | 1,488.7 / 1,506.0 |
| Hokusai | cold | 3 | 2,603.4 / 2,703.6 | 2,554.8 / 2,655.4 | 793.5 / 886.5 |
| Hokusai | warm | 2 | 2,433.9 / 2,751.9 | 2,386.8 / 2,693.0 | 845.0 / 854.8 |

The Hokusai full-stroke cold-process median (**2,603.4 ms**) was lower than the Legacy (**5,227.4 ms**) and NativeHard (**4,713.3 ms**) cold medians **on this specific software-rendered workload**, with different alpha/opacity semantics. This is not a general or physically validated latency claim, and all three results remain measured in **seconds**.

## Hokusai phases and first preview

All figures p50 / p95, **cold n=3** and **warm n=2**. Unless a row explicitly states counts, the unit is **milliseconds**.

| Phase / observation | Cold p50 / p95 | Warm p50 / p95 |
| --- | ---: | ---: |
| Native preset compute | 110.2 / 123.5 | 115.2 / 128.3 |
| GDScript staging (cumulative) | 793.5 / 886.5 | 845.0 / 854.8 |
| Commit + source publication (combined) | 1,388.5 / 1,477.1 | 1,044.2 / 1,330.4 |
| Preview/display composition | 237.2 / 254.9 | 230.1 / 324.6 |
| Texture work | 6.2 / 10.0 | 5.2 / 14.1 |
| Worst single queue drain | 59.4 / 69.8 | 77.1 / 90.7 |
| Worst complete frame draw | 19.1 / 20.0 | 19.7 / 73.1 |
| Pointer down → first preview submit | 51.7 / 55.5 | 37.9 / 52.6 |
| Pointer down → first matching postdraw | 126.8 / 128.9 | 83.2 / 105.5 |
| Native changed-pixel volume (counts, not unique) | 600,683.0 / 600,683.0 | 600,683.0 / 600,683.0 |

- Native Hokusai instrumentation reports `native_us`, `stage_us` and changed-pixel count; the volume **600,683** counts changed pixel records across passes, **not** 600,683 distinct canvas pixels. This is about **7.2 MB** if expressed as three packed 32-bit integers per changed pixel, before bridge/container overhead. It demonstrates expensive remaining changed-pixel marshalling, **not** native tile buffers or per-pixel FFI calls.
- `stage_cpu_ms` includes existing GDScript preflight/staging/blending work; the native `stage_us` subcounter is separately serialized in `T146_NATIVE_PHASE perf`. The current production timing counters **do not isolate source publication from the broader `commit_cpu_ms`**; `commit_cpu_ms` therefore covers commit/source publication together rather than falsely reporting a dedicated publication time.
- Input queue depth, age, number of drain calls, preview submissions, frame compositor p95 and max are preserved per gesture in raw `T099_FRAME_METRICS` and `T146_HOKUSAI_RUN`. The cold first preview's **postdraw** p50 was **126.8ms** (p95 **128.9ms**), but the raw input-to-per-frame wait can be much longer under accumulated synthetic input. Postdraw submission is **not** visibility through the display pipeline. For Hokusai the worst warm measured full frame draw was **73.1ms**.
- Per-process memory from `/usr/bin/time -v` (peak **RSS KiB**, not native-extension-exclusive): Legacy cold **409,652 / 410,860**, NativeHard cold **407,932 / 409,540**, Hokusai cold **424,660 / 430,380** (p50/p95 across three processes). Native Godot memory probes (`T100_POINTER_MEMORY`) also remain in raw logs.

## Actual source coverage, framebuffer and history

All five Hokusai gestures have the **same** final 512×512 row-major **source RGBA8** digest after paint and after Redo:

`b9b330c75fe7dae6d4e89f71b7a1fc008e8ec8fe0c1eb2ae420771828930f73e`

| Alpha bucket | Pixels |
| --- | ---: |
| Completely transparent (0) | **0** |
| 1–63 | 6 |
| 64–127 | 10,352 |
| 128–191 | 247,691 |
| 192–254 | 4,095 |
| Completely opaque (255) | **0** |
| **Total covered (alpha > 0)** | **262,144 / 262,144** |

Every covered source pixel has red-dominant pigment in this fixture. Therefore the preset **fills the intended source area with no holes**, but is **visibly translucent** and **not a drop-in opaque equivalent**. The test verifies **five actual software framebuffer points** (four near image corners, one center) as red-tinted after deferred tile population settles; it does **not** claim an exhaustive per-pixel post-composition screenshot oracle. This is a known visible-opacity difference rather than a hidden failure.

For each measured gesture: one history transaction and one revision bump; Undo returns to empty tiles and Redo reconstructs exact row-major RGBA bytes. Separate **untimed** Hokusai-specific assertions exercise cancellation before commit, retry and single-history publication, a rectangular selection mask (inside painted/outside untouched), and survival of transparent **hidden RGB** `0x00332211` through the masked brush, Undo and Redo. The benchmark stroke itself contains **no direct pixel writes or `fill_rect`/bucket substitution**. The isolated mask fixture seeds one hidden-RGB pixel through a normal edit session **after** timed runs.

## Native identity / negative control

The test requires `DRAWING_BRUSH_BACKEND=Hokusai`, **registered `DrawingNativeBrush`**, all three required native preset methods, and a **successful real `configure_preset`** call before measurement. It asserts the active backend is **Hokusai** after pointer-down on every gesture, and it fails closed rather than using Legacy/NativeHard fallback. In an **isolated copy** of the staged drawing app with native extension unavailable, the same real X11 witness exited **2** with `T146_HOKUSAI_FAILED: real native class is registered`, and did **not** produce the success marker: [expected-failure raw log](T-146-2026-11-15-raw/hokusai-native-missing.log), [metadata](T-146-2026-11-15-raw/negative-control.json). It is **not** included as a passing matrix process.

## Interpretation and next ticket

**T-146 result: benchmark/correctness acceptance met, with an explicitly non-opaque preset and unsolved high editor wall time.** Real sample processing is backed by the existing native GDExtension; however the editor still uses costly GDScript staging/commit, per-change marshalling, and compositing. The source data supports **continuing to T-147** (shared Rust stroke transaction contract) and T-148/149 (native-owned tiles, batched dirty-tile publication). Do **not** retire Legacy early; it remains a comparator until T-150. Do **not** resolve T-095's human approval gate or claim the physical 100ms target from software X11 postdraw.

**Limitations:** n=3 cold/2 warm; synthetic batched pointer-event trajectory vs real stylus event cadence; Mesa llvmpipe not GPU hardware; source alpha threshold `>0` is not subjective opacity; five framebuffer spots are not whole-frame pixel diff; present profiler mixes some commit/publication responsibilities; CPU stage counters need not sum to wall time; filesystem and process launch conditions differ from a real editor session.
