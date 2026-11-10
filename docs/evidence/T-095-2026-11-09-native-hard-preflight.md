# T-095 — NativeHard whole-batch validation and retry safety (2026-11-09)

**State:** Engineering checkpoint only. T-095 remains **In Progress** with
`manual_review: true`; no owner-device latency acceptance, hosted-CI result,
or PR merge is implied. This work changes the opt-in `NativeHard` GDExtension,
not the default Legacy backend or Hokusai's `.myb` rasterizer.

## Defect and fix

`DrawingNativeBrush.hard_segments()` previously inserted covered pixels and
advanced `last_hard` while iterating a batch. If a **later** point was NaN,
infinite, outside the safe coordinate range, or formed an oversized candidate
window, it returned an error **after changing the native state**. GDScript
received no pixel array for that failed call, and retrying a valid path skipped
pixels or inherited the failed cursor.

The Rust GDExtension now validates **every** point and clipped candidate window
before mutating coverage. Checked signed `i64` multiplication/addition bounds
candidate arithmetic, and a **1,048,576 candidate-pixel total per call** limits
work across many otherwise individually valid segments. Only after the entire
batch passes does the original swept-circle pixel predicate run. Coordinates,
clip semantics, once-per-stroke coverage, and the existing RGBA8 transaction
publisher remain unchanged for accepted calls. The limit is a conservative
native-only safety policy; an oversized stroke is explicitly rejected, not
silently truncated.

The API still cannot roll back native Hokusai pigment after a later **GDScript
source-resolution** failure. This checkpoint does not claim general native/GDScript
cross-boundary rollback or all-brush error recovery. Canvas cancels an invalid
stroke on a reported staging error, and regular editing continues to use the
Legacy fallback where configured.

## Independent negative control and tests

- **Prior binary:** `drawing/tests/t095_native_hard_atomic.gd` exited 1 and
  failed **6 of 28** assertions: four late-invalid/oversize-state comparisons,
  cumulative-budget rejection, and its subsequent state-parity check.
- **Rebuilt debug GDExtension:** the same test exited 0, **28/28**; all rejected
  batches returned `ok=false` without any partially emitted delta, and a
  subsequent valid batch matched a separate unmodified reference instance.
- **Rust:** `cargo test --offline --locked` with the supplied vendored crate
  directory passed **3/3** (including a new geometry/budget preflight test);
  `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` passed.
- **Godot 4.8.beta2, Debian Linux:** `native_brush_integration.gd` **30/30**,
  `stroke_navigation_native.gd` **48/48**,
  `native_brush_fallback.gd` **6/6** with native binary,
  `brush_coverage_smoke.gd` **32/32**, and
  `t095_native_export_cache.gd` **81/81**. Clean standalone import with the
  manifest and binary both absent passed fallback **6/6** with `native=false`.
- **Software-rendered 60px native mouse workload:** five 120-motion strokes
  at 786% zoom on pinned Godot 4.8 beta 2, Xvfb/llvmpipe, all passed.
  `NativeHard` staged CPU p50/p95 **164.433/166.331 ms**;
  release→commit p50/p95 **40.534/43.125 ms**; max queued inputs **12**.
  This is a single post-fix run, **not a paired performance gain** and not
  owner hardware input-to-photon evidence.

## CI and remaining gates

The optional `godot-native-t095-brush.yml` workflow now builds pinned Cargo
sources in release mode on Linux, stages the manifest/binary, pre-registers the
extension before editor import, and checks the atomicity script with the
fail-closed named marker `T095_NATIVE_HARD_ATOMIC_PASSED`. The existing 46
required fast-GDScript CI check IDs are unchanged. The workflow definition
parses locally; **GitHub Actions execution has not been observed**.

Owner-device sustained Brush response, cross-platform native distribution,
additional performance headroom, hosted CI, and explicit owner re-acceptance
are still outstanding. Keep T-096's independent Manual Review unchanged.
