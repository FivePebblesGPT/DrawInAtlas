# T-095 — NativeHard conservative oblique row pruning (2026-11-11)

**Scope and status:** `sprint/2026-11-11`, T-095 only. In Progress,
`manual_review: true`; T-096 remains Manual Review. This is a local CPU
engineering checkpoint, not owner-device acceptance or hosted CI.

## Mechanism

`native/drawing_brush/src/lib.rs`'s whole-batch validator still accounts
for every *full* rectangular window and rejects over 1,048,576 candidates
before touching coverage. For each accepted oblique row, `hard_row_bounds`
uses an f64 conservative interpolation of the part of the segment reachable
within `radius + 4px` of that row, then a further 1px horizontal margin.
Only impossible X candidates are skipped. The **original** f32 nearest-point
projection, squared-distance gate, y/x emission order, once-only set, cursor,
transaction acknowledgment and rollback journal are unchanged. Near-horizontal
slopes or coordinates above the 1M threshold take the original full rectangle.
The default Legacy and Hokusai backends are untouched.

## Reproduce and negative control

Use the supplied offline Rust/Cargo/Hokusai bundle and Godot 4.8.beta3.
Source its `setup-rust-env.sh`; configure Cargo offline against its vendored
`rust-hokusai/vendor` as in `tools/build_native_brush.sh` and build with
`cargo build --manifest-path native/drawing_brush/Cargo.toml --release --locked`.
Stage the binary plus canonical addon with `python3 tools/build_drawing_app.py
--in-place`. With a preloaded extension and a clean editor import, run:

```sh
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --audio-driver Dummy \
  --path drawing --script res://tests/t095_native_hard_scanline_smoke.gd \
  > /tmp/t095-native-hard-scanline.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t095-native-hard-scanline.log \
  --marker T095_NATIVE_HARD_SCANLINE_PASSED
```

The original native binary passes **42/42**. The optimization also passes
**42/42**, with exactly ordered old/full-rectangle pixels in 12 cases:
60px rising/falling/mixed diagonals, shallow and nearly horizontal motion,
stationary and axis paths, signed clips, and fractional widths. At view
coordinate ~10M, the original Rust binary produced 462 pixels, whereas an
independent GDScript imitation produced 464 because engine-side arithmetic
rounds two boundary pixels differently; the GDScript oracle therefore checks
the fixed **462-pixel old-native witness**, and the Rust unit oracle compares
that case's exact original native f32 predicate. The Rust unit test also
compares the exact ordered outputs on 11 fixed and 96 deterministic random
segments. A deliberate *test-only* replacement of `radius + 4.0` with
`radius - 7.0` in the native row bound caused test exit 1 and numerous
oracle mismatches (e.g. first 60px rising diagonal: 17,849 rather than 18,158
pixels). The production bound was restored and rebuilt before final tests.

## Local results

- Rust `cargo test --offline --locked --lib`: **6/6**; Clippy `-D warnings`
  and rustfmt check pass. Release library rebuilt after negative control.
- Real native scanline **42/42**, NativeHard preflight **28/28**, NativeHard
  GDScript-source atomicity **113/113**, Hokusai-source atomicity **57/57**,
  four-preset native integration **30/30**, native export cache **81/81**.
- Independent Brush coverage **32/32**, oblique/axis **513/513**, **278/278**,
  original geometry **86/86**, tile reference **626/626**, tile key
  **33,037/33,037**, source lookup **4,193/4,193**, deferred staging
  **492/492**, mixed rollback **504/504**, tile commit **56/56**.
- Additional independent legacy tile commit **519/519**, sparse preview
  **133/133**, sustained input queue **31/31**, native-present fallback
  **7/7**, actual Xvfb released-stroke navigation **48/48** all exit 0.
- The first combined model sweep timed out *after* 15 successes; its later
  cases were re-run individually with clean process exits. Do not treat the
  timed-out aggregate invocation as a pass.

## Measurements and limits

`drawing/tests/t095_native_hard_scanline_bench.gd` is **opt-in** and times only
one real `hard_segments` call, recreating/resetting the native object each
trial. Ten warm timed trials per run; cold trial excluded, 60px diagonal of
~331x292 source-space units clipped to 384², **29,175** emitted pixels each:

| Order | Median (ms) | P95 (ms) |
| --- | ---: | ---: |
| New binary, 1st | 3.530 | 3.805 |
| Previous binary, middle | 5.909 | 8.728 |
| New binary, 2nd | 3.474 | 3.691 |

These numbers include NativeHard coverage and returning packed coordinates,
**not** GDScript patching, preview composition, texture uploads, full pointer
backlog, rendering, or human input-to-photon latency. The five-stroke/120-motion
786% Xvfb NativeHard pointer witness passes: stage p95 **105.258ms**, release
to commit p95 **64.648ms**, frame callback first-post-draw p95 **78.498ms**.
No paired whole-gesture or owner-hardware speedup is inferred from this.

**Remaining gates:** physical device and renderer/driver profile of original
owner-rejected 60px scenario; explicit owner re-acceptance; hosted CI/export
unverified. Do not mark T-095 or T-096 Done and do not merge PR #16.

A fresh standalone export-staging directory was created from canonical
sources with **both** optional native manifest and binary removed. The cold
Godot 4.8b3 editor import exited 0 without script/engine errors; the absent-
native fallback test exited 0 (**7/7**, `native=false`) and independent
Legacy Brush coverage exited 0 (**32/32**). This is a local Linux import,
not a hosted export or platform-package acceptance result.
