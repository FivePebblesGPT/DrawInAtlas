# T-264 — docked icon/group lost-release recovery (2026-11-22)

## Reproduction and fail-first

- Baseline local parent: `9369f281`; remote PR #22 remained `7b1fd306` when this ticket began.
- Runtime: Godot `4.8.beta3.official.c51ff06e8`, native Rust `DrawingNativeBrush`, Linux X11/Xvfb, Mesa llvmpipe. Standalone window 1500×980, simulated content scale 100%, 150% and 200%; Atlas embedding 1450×900.
- Real `SceneTree.root.push_input` left press on a dock panel icon or unnamed group marker, motion with `MOUSE_BUTTON_MASK_LEFT` toward the canvas (valid detach preview), **no mouse-up or focus-out**, then another motion with `button_mask=0`. A later left-button release arrives over the canvas.
- The unmodified workspace retained `dock_drag.is_dragging()` and `_drag_candidate_id`, left the detach/drop hint visible and allowed the late release to float a panel/group. **Eighteen negative-control assertions failed** in the six expanded-icon/group cases at 100/150/200%. The original fail-first fixture subsequently attempted to access a dock icon after the erroneous detach had changed the layout; it stopped with a script error. Do **not** count that interrupted negative-control run as a completed suite.
- The regression was then hardened to reset any modified negative-control fixture between independent cases. The corrected implementation and current tests have no script, parse, or resource-load errors.

## Implementation

[`DrawingWorkspace._input`](../../addons/drawing/workspace.gd) recognizes an unpressed motion **only while the right dock owns a pending tab/group candidate or active cross-dock drag**. It marks the potential late release suppressed, cancels the planner transaction and clears all transient hints. This never commits an ownership change. A fresh left press on a dock panel or group starts its own lifetime and clears any suppression inherited from a lost release. The floating-host implementation remains separate and unchanged.

Document pixels, layer metadata, Undo/Redo, native texture publication and Hokusai Rust are untouched.

## Completed local verification

| Test | Result |
| --- | --- |
| `drawing/tests/t264_dock_lost_release_native.gd` | **40/40**, exit 0 |
| `tests/t264_atlas_dock_lost_release_native.gd` | **19/19**, exit 0 |
| `make test-dock-release TOOLCHAIN=system` (offline vendor) | **exit 0**, native Rust build, both project imports/ABI checks and both graphical tests |
| T-222, T-223, T-224 native | 3 suites, exit 0 |
| T-251 dock native | **306/306**, exit 0 |
| T-254 flyout native | **178/178**, exit 0 |
| T-259 floating lost release native | **28/28**, exit 0 |
| T-080 dock reorder native | **70/70**, exit 0 |
| T-082 cross-dock native | **57/57**, exit 0 |
| T-251, T-254 and T-259 Atlas integrations | **17/17**, **12/12**, **10/10**, exit 0 |
| `python3 -m unittest discover -s tests -p 'test_t078_t083_docking_plan.py'` | **10/10**, exit 0 |
| `python3 -m unittest discover -s tests -p 'test_t091_dock.py'` | **4/4**, exit 0 |
| `python3 tests/check_explicit_types.py` | **590 project scripts / 33 skill documents**, pass |
| `python3 tools/validate_ticket_store.py` | **264 tickets and manual-review gates**, pass |

Direct native invocation used:

```sh
xvfb-run -a -s '-screen 0 2200x1500x24' godot \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t264_dock_lost_release_native.gd
xvfb-run -a -s '-screen 0 2200x1500x24' godot \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path . --script res://tests/t264_atlas_dock_lost_release_native.gd
```

The clean Make path was run with `GODOT=/mnt/data/toolchain/bin/godot`, `CARGO=/mnt/data/toolchain/rust/bin/cargo`, `CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor` and `CARGO_NET_OFFLINE=true`; both consumers printed `NATIVE_EXTENSION_READY`. The on-demand GitHub workflow uses Godot 4.8 beta 3, Rust 1.99.1 and clean native imports. **It has not run on GitHub.**

## Limits and owner gates

A synthetic lost mouse-up under software X11 is an actionable engine-path regression, not evidence of physical OS input delivery. Neither Windows/Linux physical-device Alt+Tab/release behavior nor the owner's dock UX acceptance is tested here. **T-091 stays In Progress, T-083 stays unapproved, and T-250 stays Manual Review.** No other Atlas feature ticket is being closed.
