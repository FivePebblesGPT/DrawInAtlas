# T-147 — unified Rust stroke engine and GDScript bridge

Date: 2026-11-15. Branch `sprint/2026-11-15`, source baseline `5df5f25e` (T-146) on `a83e5055` (GitHub remote). Scope **only T-147**. Tests run against the actual bundled `DrawingNativeBrush` library built from `native/drawing_brush/src/lib.rs` and imported into **Godot 4.8 beta 3**, Linux/Mesa/Xvfb for graphical witnesses; supplied Rust 1.99.1 and vendored crates offline. `DrawingNativeBrush` v1 is **alpha** and deliberately breaks the prior hard/preset native entry points.

## Runtime architecture change

- Both NativeHard and Hokusai use a single `begin_stroke` → `append_samples` → `preview_changes` → `acknowledge_batch` → `commit_stroke`/`abort_stroke` lifecycle, in one Rust class, one handle per instance, one shared sample parser, pending/accepted batch journal, frozen clip/revision and fail-closed errors. Internal Hard coverage and Hokusai state/surface/published export restore their own pre-batch state. Both preserve their native brush-specific opacity/overlap semantics.
- Canvas and edit session share one handle-based gesture dispatch. Contiguous packed floats avoid per-dab Godot↔Rust boundary calls. Native batch rollback after a source-read failure leaves the previous accepted preview and exact state retryable. Session documents, selection, source reads, RGBA compositing, preview and Undo are still GDScript-owned until T-148.
- Historic native direct-API tests now instantiate a **test-only** fixture that drives ABI v1; scripted source-read mocks now use a test-only bridge. No production compatibility shim is retained. This is not an early implementation of native tiles.

[ABI v1 and planned native tile-buffer contract](../NATIVE_STROKE_ABI_V1.md) specify types, lifecycle, signed tile IDs, straight RGBA8, row stride, base source revision, generation, dirty bounds, buffer lifespan, atomic errors, and the T-148 ownership handoff.

## Verified test matrix

| Trial | Result | What it checks |
| --- | --- | --- |
| Offline `cargo test --offline --locked` with bundle-vendored config | **10/10 pass** | Hard geometric parity, input validation, partial-pressure discontinuity, rejection/rollback; Hokusai native export/cache behavior |
| Offline `cargo clippy --all-targets -- -D warnings` with bundle-vendored config | **Pass** | No Clippy findings for compiled targets |
| Godot headless `t147_native_stroke_contract.gd` | **35 checks, 0 failures** | Invalid/wrong/stale handles; pending batch/commit order; hard/preset rollback and retry; pressure/signed coordinates; profile payload count |
| Real-native `t095_native_hard_source_atomic.gd` | **113 checks, 0 failures** | Injected source read failure, negative/high signed anchor, selection holes, transparent hidden RGB, Brush and Eraser rollback, retry/skip, Undo/Redo |
| Real-native `t095_native_pigment_atomic.gd` | **57 checks, 0 failures** | Late source read failure, pigment state/quantized export cache rollback, same-object retry, selection/hidden RGB, signed anchor, Undo/Redo |
| Graphical `native_brush_integration.gd` | **32 checks, 0 failures** | NativeHard/Legacy source regression, native erasure, four Hokusai `.myb` presets, selection hole, actual Canvas commit, Undo/Redo |
| `native_brush_fallback.gd` | **7 checks, 0 failures (native installed)** | ABI v1 runtime selection, invalid preset, session lifecycle |
| Additional 9 headless fixture tests | **9/9 scripts exit 0** | Historical packed hard/pigment export, exact preflight/scanline, tile commit and shifts, Hokusai bulk, native dispatch, export-cache regression |
| `tools/validate_ticket_store.py` | **152 tickets valid** | Single entries, hard dependencies, manual review gates |

Representative command for native/headless tests:

```bash
/mnt/data/dev-bundle/run-godot-headless.sh --path drawing \
  --script res://tests/t147_native_stroke_contract.gd
```

For Rust, source bundle's `setup-rust-env.sh`, set `CARGO_BUILD_TARGET=x86_64-unknown-linux-gnu`, and supply a temporary `--config` containing `[source.crates-io] replace-with="vendored-sources"` and `[source.vendored-sources] directory="/path/to/bundle/rust-hokusai/vendor"`. `cargo clippy` takes `--config` **after** `clippy`; otherwise Cargo may ignore the replacement configuration.

The [verbatim process logs and SHA-256 manifest](T-147-2026-11-15-raw/manifest.json) preserve all **16** verified Godot processes (13 headless regressions + 3 graphical witnesses). Their process exit codes were 0; no silent runtime error was counted as a pass.

## Native FFI count and batch volume

The real `t147_native_stroke_contract.gd` process reported the following per-stroke boundary counters:

| Strategy | `ffi_calls` | `input_floats` | `exported_ints` | Meaning |
| --- | ---: | ---: | ---: | --- |
| NativeHard | 13 | Packed batches | 1,824 | 13 calls for begin/batch/preview/ack/stats, not 912 individual pixel calls |
| Hokusai | 8 | Packed batches | 2,784 | 8 calls for begin/batch/preview/ack/stats, not 928 pixel calls |

The `exported_ints` totals are **before** GDScript consumption: NativeHard emits pairs, Hokusai triples. A full 96px gesture can still emit 600k+ Hokusai pixel triples across batches and invoke source-tile staging in GDScript; native FFI call counts alone do **not** demonstrate T-148 or physical responsiveness. `Canvas.last_gesture_metrics.native_ffi_stats` exposes these counts in an actual Canvas gesture; in the graphical cancellation/retry witness the 10-sample retry used 8 Rust FFI calls, 40 input floats and 25,683 output ints.

## Separate 96px 512×512 software X11 source witnesses

One graphical process per strategy under Xvfb/Mesa (not a paired p95 comparison):

| Measure | NativeHard | Hokusai hard-round |
| --- | ---: | ---: |
| Input events | 100 | 100 |
| Canvas | 512 × 512 | 512 × 512 |
| Source alpha coverage | 262,144 / 262,144 | 262,144 / 262,144 |
| Transparent holes | 0 | 0 |
| Fully opaque alpha | 262,144 | **0** (translucent pigment, expected) |
| Input → settled postdraw, software | **5,443.317 ms** | **2,756.192 ms** |
| GDScript stage CPU | **1,608.713 ms** | **828.316 ms** |
| Native brush CPU metric | n/a | **132.413 ms** |
| Result | **PASS** `T095_FULL_CANVAS_PASSED` | **PASS** `T146_HOKUSAI_BENCHMARK_PASSED` |

The Hokusai source digest remained **`b9b330c75fe7dae6d4e89f71b7a1fc008e8ec8fe0c1eb2ae420771828930f73e`** after Undo/Redo. Mask/transparent hidden-RGB and cancel/retry checks passed. NativeHard retained the independent exact hard-red oracle. Graphical integration separately covered Brush/Eraser, mask and four preset modes.

These are **single-run smoke measurements**. Neither strategy meets a 100ms target; no reliable physical input-to-photon p95, device-specific UX validation, speedup claim or T-095 owner signoff is implied. The measured GDScript stage/commit cost and provisional per-pixel streams explicitly motivate **T-148**.

## Scope and remaining gates

- **Done T-147:** cohesive versioned Rust stroke API, unified Canvas dispatch, native state/error rollback, documented tile-buffer contract, integration/96px evidence, FFI call-count observability.
- **Ready T-148:** Rust-owned canonical tiled raster, blending, masks, source-read authorization, native dirty tile buffers and atomic reversible Undo history. Do not confuse T-147's GDScript staging adapter with native authority.
- **Still blocked:** T-149 Godot display/save, T-150 Legacy retirement, T-151 post-retirement profiling and T-152 targeted optimization. **T-095 stays In Progress** with owner hardware review; T-068 remains independent.
