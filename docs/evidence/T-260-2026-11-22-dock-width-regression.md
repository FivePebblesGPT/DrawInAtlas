# T-260 — current dock width contract and clean-native workflow, 2026-11-22

## Fail-first reproduction

On local HEAD `5e06b0ed`, `python3 -m unittest discover -s tests -p
 'test_t081_float_native.py' -v` failed its stable-dock minimum assertion:
`const EXPANDED_DOCK_MIN_WIDTH: int = 192` is no longer in
`addons/drawing/workspace.gd` (constant is **226** after T-251). The
existing Godot 4.8 beta 3 native X11 T-081 fixture passed **58/58** on the
same unmodified implementation, demonstrating that its former `>= 190px`
check was too weak to detect a 34px gutter regression.

## Correction

- `tests/test_t081_float_native.py` requires the correct 226px floor, 34px
  gutter and 48×56px toggle slot; checks the new native assertions and the
  pinned native-build workflow.
- `drawing/tests/dock_float_native.gd` now checks the real rendered
  expanded/minimized dock rectangle, clickable toggle anchoring, actual rail
  icon displacement, canvas width after toggling and fixed minimum after
  floating an entire group. It does not mutate document or native history.
- `tools/check_native_t081_log.py` requires **71** assertions rather than
  accepting the old 58. The duplicate, incomplete, failed and unexpected
  diagnostic rejection tests remain mandatory.
- `.github/workflows/godot-native-t081-floating.yml` pins Rust 1.99.1 and
  uses `make build TOOLCHAIN=system` to compile native code and import both
  Godot projects before running the existing X11 test and uploading logs.

## Validation (local Linux X11/Mesa)

Using the supplied pinned Godot `4.8.beta3.official.c51ff06e8`, Rust
`1.99.1`, Linux/Xvfb and Mesa llvmpipe:

| Check | Result |
| --- | --- |
| Repaired `test_t081_float_native.py` | **5/5** passed |
| T-081 native X11 after import | **71/71** passed |
| `check_native_t081_log.py` on updated native log | Passed |
| Clean native build + Drawing/Atlas imports, `make build TOOLCHAIN=system` | Passed with supplied `CARGO_VENDOR_DIR` and offline Cargo |
| T-251 dock-toggle X11 | Passed marker, exit 0 |
| T-083 persistence X11 | Passed marker, exit 0 |
| T-091 one-group floating X11 | **44/44** passed |
| T-251 Atlas X11 | Passed marker, exit 0 |

The initial no-vendor `CARGO_NET_OFFLINE=true` system build was unable to
resolve the `godot` Cargo crate. Supplying the provided `toolchain/vendor`
directory allowed the same Make build and both consumer imports to finish.
This is a local clean build of tracked sources, **not** a hosted GitHub CI
run or a real hardware/Windows acceptance test. T-250 remains Manual Review,
T-083/T-091 remain In Progress, and no owner approval is inferred.
