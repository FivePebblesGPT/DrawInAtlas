# T-153 — Hokusai-only Brush/Eraser cutover and software integration evidence

**Date:** 2026-11-16. **Branch:** `sprint/2026-11-15`. **Pre-change remote HEAD:**
`fa36c19909ebaf056aaa375fe358151805928b51` (verified from PR #19 before work).
**Environment:** Godot `4.8.beta3.official.c51ff06e8`, Linux x86-64,
Rust `1.99.1`, vendored Hokusai `0.3.0`, godot-rust `0.5.5` (4.7 stable API),
Mesa software renderer through Xvfb (GL compatibility). Native release build
uses `tools/build_native_brush.sh` with the owner's pinned offline bundle.

## Five-step execution result

1. The sole Brush/Eraser ABI is `begin_stroke(layer,preset_text,width,rgba,
   revision,clip) → append_samples → required_tiles → apply_tile_batch →
   commit_tiles/abort_stroke`. Bundled `hard_round`, `soft`, `ink`, `airbrush`
   `.myb` files select MyPaint behavior; no mode parameter remains.
2. Removed NativeHard Rust raster kernel, dispatch/state/rollback paths,
   Canvas selector and hard-only smoke/performance fixtures. Kept the **shared**
   Rust tile storage/history/selection system and GDScript non-Brush tools.
   Legacy `DrawingEditSession.paint_path` remains as an unreachable separate
   renderer for dependency-ordered T-150; **not a silent Canvas fallback**.
3. Eraser now applies Hokusai dab alpha to immutable source alpha in Rust;
   original RGB (including transparent hidden RGB) is preserved. Native
   handles/revisions, preflighted source/masks, rejection/retry, signed tile
   coordinates, Undo/Redo and document Save/Open tested. Valid native path and
   a deliberately removed `.so` both passed `native_brush_fallback` (the
   absent run reports the expected Godot missing-library error, **exit 0**
   for the fail-closed fixture; it publishes no raster/history).
4. Replaced NativeHard-only/Legacy parity tests with independently checked
   Hokusai source coverage, alpha histogram, pixels/masks, cancellation,
   Undo/Redo and actual 100-event software-X11 input/viewport witness.
5. Updated active stroke/tile ABI documentation, native build notes, bench
   reporter and on-demand CI native commands. Host hardware/T-095 unchanged.

## Raw process exits and strict result markers

| Command / fixture | Exit | Assertion / verification result |
| --- | ---: | --- |
| Cargo `test --locked --offline` | 0 | 22/22 Rust tests |
| Cargo `fmt -- --check` | 0 | formatting checked |
| Cargo `clippy --config <vendored> --locked --offline --all-targets -- -D warnings` | 0 | zero warnings |
| `tools/build_native_brush.sh <bundle>` | 0 | release `.so` rebuilt and loaded |
| standalone `--editor --import --quit` | 0 | import succeeds |
| `t147_native_stroke_contract` | 0 | 20 checks, zero failures |
| `native_brush_fallback` (with extension) | 0 | 4 checks, zero failures |
| `native_brush_fallback` (temporarily missing `.so`) | 0 | 4 checks, zero failures, `present=false` |
| `native_brush_integration` | 0 | 32 checks, zero failures |
| `t148_native_tiles_contract` | 0 | 312 checks, zero failures; 512² native fill has 262144 covered pixels |
| X11 `t148_canvas_tile_cutover_x11` | 0 | 46 checks, zero failures |
| X11 `t146_hokusai_full_canvas_native` | 0 | `T146_HOKUSAI_BENCHMARK_PASSED` |
| Python `tests.test_t104_backend_decision`, `tests.test_t146_hokusai_bench` | 0 | 17 unit tests |
| Root Godot `--editor --import --quit` | 0 | Atlas import succeeds |
| Root `t148_atlas_native_tile_history` | 0 | 43 checks, zero failures |
| Root `t148_detached_native_bootstrap` | 0 | 34 checks, zero failures |
| Root `t148_detached_native_replay` | 0 | 21 checks, zero failures |
| Root `t148_native_history_payload_guard` | 0 | 20 checks, zero failures |
| Root `t148_native_history_reentrant_replay` | 0 | 25 checks, zero failures |
| Root `t148_object_native_source` | 0 | 38 checks, zero failures (Object Save/Save As/registry reload/export) |
| Standalone `t095_native_pigment_atomic` and eight updated T-148 tests | 0 each | independent native source/history regressions |
| `python3 tools/validate_ticket_store.py` | 0 | 153 tickets validated |

The old `t099_preview_schedule_native` (10 legacy parity/scheduling failures)
and `t124_queued_brush_native` (4 opaque/Legacy comparison failures) were also
executed and exited **1**. Those old fixture expectations predate T-153 and
are **not accepted as Hokusai correctness oracles**; their rewritten
native-specific pointer/preview variants belong with T-149/T-150. The
old NativeHard cases have been removed from the on-demand T-095 workflow;
this is **not** a claim of hosted CI green.

## 96px Hard Brush Fill Bench™️ — real software X11, one cold trial

Command:

```sh
python3 tools/run_t146_hokusai_bench.py \
  --godot /path/to/Godot_v4.8-beta3_linux.x86_64 \
  --output /tmp/t153-bench --cold 1 --warm 0 --timeout 180
```

- Python reporter **exit 0**, underlying Godot process **exit 0**,
  strict log checker **exit 0**, complete one-run validator **valid=true**.
- Event count **100**; source **512×512**, width **96px**, full source
  coverage **262144/262144**, no source-alpha holes, Undo/Redo SHA256
  `b9b330c75fe7dae6d4e89f71b7a1fc008e8ec8fe0c1eb2ae420771828930f73e`.
- Alpha counts: zero **0**, 1–63 **6**, 64–127 **10352**,
  128–191 **247691**, 192–254 **4095**, 255 **0**. Natural MyPaint
  Hard Round currently yields translucent pigment; **do not interpret this
  as NativeHard opaque-red parity**. The unchanged `.myb` is the explicit
  hard-round preset under test.
- Actual phase evidence: **62** native stroke FFI calls, **47** native tile
  calls, **5,505,024** bytes exported, **zero tile per-pixel stream calls**;
  no imaginary standalone Rust CPU counter. Real framebuffer sampling,
  cancellation/retry and masked hidden-RGB cases passed in Godot.
- One-run times: pointer-down to post-draw **356.941 ms**; release to
  native document commit **316.765 ms**; stage CPU **109.787 ms**;
  first preview submit **21.656 ms**, first post-draw **56.125 ms**;
  max drain **12.610 ms**; peak RSS **266328 KiB**;
  user CPU **1.45 s**, system CPU **0.50 s** for the full process. Those
  figures are **not** p95, hardware input-to-photon latency, a release
  performance guarantee, or T-095 signoff.

**Review boundaries:** T-148 remains **In Progress** for universal native
raster/history authority; T-149 and T-150 remain blocked on their dependencies.
T-095 physical hardware latency and owner approval remain outstanding.
Old benchmark comparisons are retained as historical evidence only. No
Windows/runtime portability, hosted CI green, or owner review is claimed.
