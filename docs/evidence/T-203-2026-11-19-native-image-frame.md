# T-203 — restore required-native T-087 image-frame regressions

**Date:** 2026-11-19. **Base:** PR #21 remote `9aa1cbe0`, after seven local
commits through `1d1e01d3`. Linux x86_64, Godot `4.8.beta3.official.c51ff06e8`,
compiled `DrawingNativeBrush` and `DrawingNativeTiles`, software X11/Mesa
llvmpipe for graphical tests. No hardware or remote CI execution.

## Reproduced failure (unmodified test files)

| Godot invocation | Exit | Result |
| --- | ---: | --- |
| `--headless --path drawing --script res://tests/image_frame_smoke.gd` | 1 | `T087_MODEL: 78 checks; 5 failed` |
| `xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/image_frame_native.gd` | 1 | `T087_NATIVE: 104 checks; 17 failed` |

The model expected an unchanged clip/camera gesture to create source pixels and
history even when the input was a 1px stationary Legacy-style tap. The actual
Hokusai transaction correctly committed **no change**. The native fixture made
the same assumption in snap and policy/camera tests. Its Eraser also compared
the entire 32-bit RGBA value to integer zero, contrary to canonical straight
RGBA8: clearing alpha retains hidden RGB. After widening the actual input,
previously painted frame-edge pixels invalidated one stale-release test's
`== 0` precondition. These mismatches were verified, not waived.

## Repair and controls

- Headless: use a genuine 16px swept unbounded stroke spanning negative
  source pixels beyond the image guide. Wait up to 180 Canvas frames for the
  current native session to finish. Assert a **nonzero outside-frame pixel**,
  one revision and a native batch, and require Undo to restore that pixel.
  Repeat for a camera-stable 8px native stroke, including Redo/Undo. Camera
  change, clipping change and snap mapping still cancel before publication.
- Graphical: deliver real X11 `InputEventMouseButton` plus pointer motion,
  not a synthetic source mutation. Native Brush gestures use 16px widths and
  checked source/history changes. Existing 104 checks still cover snap,
  visible grid, checker at fractional zoom, frame-boundary clipping,
  stale-gesture rollback and real changed framebuffer preview.
- Eraser: require alpha-zero output with the **exact previous RGB bytes**,
  off-frame sparse pixel identity, then byte-exact Undo. Camera/clip stale
  release compares against the source snapshot taken immediately before
  the pending gesture, rather than requiring an independently painted
  boundary to be empty.

All production Canvas, Hokusai and data-preservation code is untouched. The
changed tests would still fail if the gesture were canceled rather than
published, if paint were clipped while the policy was disabled, if Undo
lost its pixels, or if Eraser discarded RGB at alpha zero.

## Validation and limitations

| Check | Exit | Result |
| --- | ---: | --- |
| T-087 model ×6, headless | 0 each | 82/82 each |
| T-087 X11 framebuffer ×4 | 0 each | 104/104 each |
| T-187 graphical native preview | 0 | 183/183 |
| T-197 graphical callback attribution | 0 | 9/9 |
| Drawing native integration | 0 | 32/32 |
| Drawing native tile contract | 0 | 312/312 |
| Atlas native tile/history | 0 | 43/43 |
| Offline native Rust | 0 | 35/35 |
| Make Python test suites | 0 | 56/56 |
| T-094 CI log contract unit tests | 0 | 24/24 |
| Explicit GDScript type checker | 0 | 520 project scripts and 33 skill docs |
| Strict T-087 model log marker | 0 | `T087_MODEL_PASSED` accepted |

A neighboring T-130 pending-source context smoke still exits **1**, with
one failed Deselect assertion (34 checks). It is not silently included in
the passing matrix; the failure was retained for a separate task. The
historical T-085 model also remains red (8/77). The fresh **required** hosted
fast-desktop workflow has not been rerun on these unpushed commits. The
October/November owner physical UX review, Windows portability and the
T-197 200ms p95/physical frame-pacing gates remain open.

Exact console output, source hashes and exit codes are retained in
[raw evidence](T-203-2026-11-19-native-image-frame-raw/). Frame checks are
software-renderer assertions, **not** hardware display FPS or mouse-to-photon
measurements.
