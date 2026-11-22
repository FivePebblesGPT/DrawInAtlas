# T-257 — Escape rollback for floating geometry

**2026-11-22, PR #22** · Godot 4.8 beta 3 `c51ff06e8`, Linux x86_64, Xvfb/X11 2200×1500×24, Mesa llvmpipe/GL compatibility, Dummy audio; same pinned local required-native Rust extension in both Drawing and Atlas. Real desktop/Windows hardware and hosted workflow **not** verified.

## Failure and correction

The existing floating host stores `_frame_start` on a grip/edge press and updates its `position/size` during mouse motion. Escape set `_suppress_release` and called `_clear_gesture`, but did not undo the geometry update. A fresh test against the unchanged production host failed **18 of 31** standalone assertions (move and both corner resizes at 100%, 150%, 200% scale), and the Atlas-hosted negative control failed **4 of 8** assertions. Both commands returned exit 1, with `T257_*_FAILED` markers. These are actual `Viewport.push_input` pointer/key inputs, not only source scans.

The fix calls `set_host_rect(_frame_start)` before clearing a canceled `move` or `resize` gesture. `set_host_rect` preserves existing client-boundary/size clamps, so an intervening window resize still cannot put the host offscreen. A tab/whole-group drag has no geometry rollback; its existing drag cancellation remains unchanged. Cancel emits no committed `state_changed` event, and the already-present release suppression remains in force.

## Positive results

| Test | Result |
| --- | --- |
| Standalone `drawing/tests/t257_floating_cancel_native.gd` | **31 checks, 0 failures** after staging/importing the canonical Drawing package; at each scale test real grip move, top-left/bottom-right resize, Escape geometry restoration and suppressed late release. A subsequent valid grip move works, with no source or ownership change. |
| Embedded Atlas `tests/t257_atlas_floating_cancel_native.gd` | **8 checks, 0 failures**, including move+corner cancellation, exact geometry/source/ownership invariants |
| Floating host, T-081 | **58/58** |
| One-group floating host / T-091 | **44/44** |
| Grip redock / T-091 | **53/53** |
| T-083 docking persistence | **63/63** |
| T-225 floating icon parity | **81/81** |
| T-255 clipped tab pointer | **20/20** |
| T-256 floating context menus | **28/28** |
| T-254 flyout icons | **178/178** |
| Atlas T-255 clipped pointer | **14/14** |

The run logs retain the expected X11 V-Sync and running-as-root diagnostics; they have no `SCRIPT ERROR` or `T257_*_FAILED` markers on the positive witnesses. The new on-demand workflow builds and imports both native consumers, runs both witnesses, and uploads logs plus optional screenshots; it has not run on GitHub. The ordinary source image pixels, canvas revision/dirty bit and native/global history ownership are unchanged.

## Reproduce

```sh
make test-floating-cancel TOOLCHAIN=system
# Or after native build and both imports:
T257_SCREENSHOTS=/tmp/t257-screens xvfb-run -a --server-args='-screen 0 2200x1500x24' \
  godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t257_floating_cancel_native.gd
xvfb-run -a --server-args='-screen 0 2200x1500x24' \
  godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path . --script res://tests/t257_atlas_floating_cancel_native.gd
```

T-091 stays In Progress for physical Windows/Linux pointer validation. T-083 and T-250 remain unapproved (T-250 at Manual Review); this engineering success cannot close those gates.
