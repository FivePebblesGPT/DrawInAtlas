# T-268 — Native T-096 large selection/Move CI (2026-11-22)

## Starting state and fail-first control

Branch `sprint/2026-11-20-selection-dock-colors-brushes` at
`f5b83845` (20 commits beyond last observed PR #22 remote
`7b1fd306`). The prior `.github/workflows/godot-native-t096-selection.yml`
never built/registered the required Rust `.so`, although it invoked tests
against Drawing after checkout and import. The archive does not track the
compiled `.so`; a new clean runner is not guaranteed to have one.

`tests/test_t268_large_move_ci.py` initially failed **3 workflow/Make
contracts** (missing pinned Rust and native build, absent Make target, and
missing Atlas diagnostics) while its strict log tests passed except for a
fixture using a nonstandard Godot compact-error timestamp. That fixture was
corrected to the engine's actual `E 0:00:01:234` form. The full corrected
contract suite passes 9/9. No product implementation regression is implied by
the CI-only negative control.

## Changes

- On-demand workflow installs pinned Rust 1.99.1 and Godot 4.8 beta 3,
  executes `make build TOOLCHAIN=system`, and strictly verifies all three
  diagnostic streams while preserving logs on failure.
- `tools/check_t096_logs.py` rejects incomplete, duplicated, late or reordered
  summaries/markers; missing/non-finite timing metrics; script, engine and
  native process errors. Timings are **diagnostic only**; no synthetic
  hardware latency budget is asserted.
- `make test-large-move` reproduces the compile/import/test sequence with
  Bash `pipefail`, so a killed Godot process cannot be hidden by `tee`.
- New `tests/t268_atlas_large_move.gd` uses a **real Atlas campaign** and
  canonical Drawing detail with 64px native storage tiles. It seeds a 96×70
  signed rectangle, a 14×13 subtractive hole and 8×8 disconnected island;
  the selected source contains more than 6,000 occupied RGBA8 pixels,
  including hidden RGB at alpha 0. The Move shifts by (+128,+16), crossing
  signed tile boundaries into new destination tiles. The witness checks
  native whole-tile history (no per-pixel shadow timeline), original and
  destination exact bytes after Undo/Redo, excluded pixels, and saved/reopened
  Atlas campaign generation bytes. This is test-only integration preparation;
  the T-250 hard gate on new Atlas features is not completed or relaxed.

## Local test evidence

- Environment: Godot `4.8.beta3.official.c51ff06e8`, Rust 1.99.1,
  Linux x86_64 X11/Xvfb, Mesa llvmpipe (OpenGL compatibility),
  offline vendored Cargo dependencies. This is **not** Windows, hosted CI,
  or owner physical hardware.
- Baseline T-096 model **13,847 checks, 0 failures** and real X11 **34 checks,
  0 failures** before workflow modification.
- New Atlas test **22/22** under the native Godot/Atlas consumer.
- Full `make test-large-move` **exit 0**: actual Rust build, both imported
  consumers report `NATIVE_EXTENSION_READY`, model **13,847/13,847**, X11
  **34/34**, Atlas **22/22**, each verified with the strict log checker.
- X11 diagnostic sample from the Make run: motion-to-preview-submit p95
  **9.513ms**, input-to-submit p95 **10.998ms**, callback p95 **44.134ms**;
  these are small local software-X11 samples, *not* physical input-to-photon
  or a general p95 performance claim.
- Python T-268 CI verifier and negative controls: **9/9**; combined with
  neighboring T-267/T-088 log contracts: **20/20**.
- Neighboring required-native selection clipboard X11 **52/52**, Atlas
  native tile history **43/43**, Atlas dense Delete/history **15/15**.
- Explicit GDScript typing **593 project scripts / 33 skill documents**;
  Ruff, ty, ticket-store validation **268 tickets** all pass.
- The complete Make target passed twice after the verifier import-path
  correction, including the final script/CLI form and both native imports.

Reproduction with the provided offline toolchain:

```sh
export PATH=/path/to/toolchain/rust/bin:$PATH
export CARGO_NET_OFFLINE=true CARGO_VENDOR_DIR=/path/to/toolchain/vendor
make test-large-move TOOLCHAIN=system \
  GODOT=/path/to/toolchain/bin/godot CARGO=/path/to/toolchain/rust/bin/cargo
python3 -m unittest tests.test_t268_large_move_ci -v
```

## Acceptance boundaries

T-096 stays **Blocked** on T-149's future native mask/preview seam;
no final owner Move usability signoff was performed. T-088 remains In Progress,
T-094/T-180 hosted CI and release obligations remain open, and T-059/T-250
retain explicit owner-review gates. No completed ticket claims a physical
hardware input-to-photon latency from simulated X11.
