# T-288 — Godot beta4 native fill-to-frame CI and profile provenance

**Base:** local commit `5a0e44f6` on sprint/2026-11-23-godot-beta4;
remote `main` at the start: `bbae76c3`. Linux x86-64, official Godot
4.8.beta4 `b070e63b161aa816afac71dcfc9d60859d38f220`, Rust 1.99.1
from the supplied offline toolchain; software X11/Mesa llvmpipe. This is
**not** a hosted Actions or owner-acceptance run.

## Before, reproduction and negative control

- The on-demand `godot-native-t068-fill.yml` initially called `godot --import`
  before the real `make build`; it neither installed pinned Rust nor
  registered the required GDExtension on clean checkout. The first two
  Python contract tests failed until those steps were added.
- The unchanged `tests/drawing_fill_frame_native.gd` run was executed with
  `xvfb-run -a <toolchain>/bin/godot --display-driver x11
  --rendering-method gl_compatibility --audio-driver Dummy --path .
  --script res://tests/drawing_fill_frame_native.gd -- --trials 5
  --output /mnt/data/t288-before.json --screenshot /mnt/data/t288-before.png`.
  Exit 1: 15 expected `DrawingDelta.after` length failures among 96 checks.
- After replacing the retired delta count with an exact canonical RGBA8
  rectangle and clear-border oracle, five trials passed 96/96. Altering
  expected target RGBA8 to the pre-fill source made 15/15 cases fail again;
  process exit 1. No production rasterization code changed.

## Build and runner parity

- `make build TOOLCHAIN=system` with `GODOT`, `CARGO`, `UV`, `RUST_BIN`
  pointing into the supplied beta4/Rust toolchain and offline vendored Cargo
  inputs: exit 0; both project imports and `NATIVE_EXTENSION_READY` succeeded.
- `python -m unittest tests.test_t068_fill_process_profile
  tests.test_t288_fill_native_ci -v`: all 8 tests pass, including malformed
  engine version/hash, missing build, changed toolchain and reordered build.
- The profiling wrapper ran
  `python tools/benchmarks/t068_fill_process_profile.py
  --godot <toolchain>/bin/godot --output-dir /mnt/data/t288-profile-final
  --runs 2 --trials 21 --sample-ms 10 --timeout-seconds 70`:
  770 checks passed, both process exits 0. Captures are in `evidence.json`
  and separate run logs. The full *measured* interval ends at
  `RenderingServer.frame_post_draw`, before canonical byte verification.
- Neighboring native headless runs: `drawing_fill_frontier_smoke.gd`
  56/56; `drawing_fill_tile_cache_smoke.gd` 39/39;
  `drawing_fill_verified_stage_smoke.gd` 36/36; `fill_scope_smoke.gd`
  103/103. All exits 0.

The 21-trial runs report 96px framebuffer p95 228.023/214.903ms and
Godot-only sampled VmRSS maximum 282,984/280,096 KiB. The result is
synthetic software-X11, not production Bucket/physical-device latency.
Snapshots `/mnt/data/t288-profile-final/run_1.png` and `run_2.png`
are transient captures, not committed product-appearance acceptance.

## Retained artifacts

The adjacent folder preserves original/green native logs, the pixel
mutation, full Make build log, Python contracts, both successful 21-trial
process logs, and the full evidence JSON with engine version/hash and
Linux process memory samples. A new hosted CI run remains pending.
