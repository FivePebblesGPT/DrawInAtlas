# T-222 — compact dock half-circle and icon interactions

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`. **Last verified remote PR #22 head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`. Owner UX reference: `docs/DRAWING_UX_REVIEW_2026-11-20.md`. All results are **local software runs**; screenshots are delivered in the ChatGPT handoff, not committed into the source tree.

## Implemented

1. `addons/drawing/dock_toggle.gd` is a 30×56 logical-pixel **half-circle**, translucent with vector stroke/glyph, hover/focus feedback and a keyboard-focusable Button. `workspace.gd` creates **one persistent overlay** outside the dock scroll, positions it beside the canvas/dock seam on resize, and uses it for both expanded and minimized states. The former `MinimizeDock` full-width row and `ExpandDock` rail row are absent. `Window > Minimize/expand panel dock` remains available.
2. Expanded panel icons select an inactive tab and uncollapse its group; an already-active icon toggles that group's **existing** collapsed bit. Minimized icons instead toggle/switch only the existing temporary flyout through `DrawingDockLayout.activate_from_rail`, with collapse and selected tab preserved through minimize/re-expand/restart. Floating hosts retain their prior active-tab no-op; **T-225** will convert their text tabs into icons. This work adds no shadow views, legacy backend, or alternate document history.
3. Each expanded/rail panel icon opens a **panel-scoped** native Godot `PopupMenu` on RMB; Shift+F10/Menu on the focused icon provides keyboard access. It offers transactional left/right tab movement, split, and floating the clicked panel (not the group's active tab by mistake). Popup opening does not select/collapse/mutate the model. The existing 7px dock drag candidate threshold now guards the `Button.pressed` signal even when mouse-release event and GUI signal order differ, and refuses drags triggered by motion without the held left button.
4. Existing named group headings and separate group buttons are intentionally retained for **T-223**, and floating text tabs for **T-225**. Owner screenshot/design feedback is not approval of the final integrated dock.

## Validation

Godot `4.8.beta3.official.c51ff06e8`, X11/Xvfb, Mesa llvmpipe OpenGL compatibility renderer, x86_64 Linux toolchain. Source was staged with `python3 tools/build_drawing_app.py --in-place`; standalone Godot editor resource import completed successfully; Atlas uses the same `addons/drawing` shared package.

| Test / command (run with bundled Godot) | Result |
| --- | --- |
| `--path drawing --script res://tests/t222_dock_native.gd` under X11 (with `T222_SCREENSHOTS` set) | **53/53**; real LMB, RMB, Shift+F10, drag motion and release; 100/150/200% `Window.content_scale_factor`, 420px narrow viewport, persistence/restart; six framebuffer screenshots |
| `--path . --script res://tests/t222_atlas_dock_native.gd` under X11 | **12/12**; embedded host, original panel view, flyout, no Atlas window-quit takeover or edit-history mutation |
| `drawing/tests/dock_ui_native.gd` under X11 (T-079 superseding chrome assertions updated) | **40/40**; original groups, focus, flyout, viewport and document guards preserved |
| `drawing/tests/dock_reorder_native.gd` (T-080) | **70/70** |
| `drawing/tests/dock_float_native.gd` (T-081) | **58/58** |
| `drawing/tests/dock_cross_native.gd` (T-082) | **57/57** |
| `drawing/tests/dock_persistence_native.gd` (T-083) | passed |
| `drawing/tests/dock_single_group_native.gd` (T-091) | **44/44** |
| `drawing/tests/dock_grip_redock_native.gd` (T-091) | **53/53** |
| `dock_layout_smoke.gd`, `dock_drag_smoke.gd`, `dock_float_smoke.gd`, `dock_cross_smoke.gd`, `dock_persistence_smoke.gd`, `dock_single_group_smoke.gd` | all six passed, 82/60/64/66/unknown/54 checks respectively |
| `python3 tools/validate_ticket_store.py` | 227 tickets, valid manual/dependency gates |

**Regressions and remaining limitations:** Existing PR #22 fast-desktop CI remains **unverified/red** at the last remote head: the Linux standalone export directory inventory and an obsolete T-083 exact-dependency assertion in `tests/test_t078_t083_docking_plan.py` are unrelated to T-222 and were **not** repaired here. The latter focused Python test still fails because T-083 correctly gained more prerequisites; no dependency was weakened to satisfy it. No hosted CI run, physical DPI hardware input, compositor/scanout timing or owner approval has been claimed. The T-083 final owner dock review remains open; T-091 physical interaction review, T-223 group marker, T-224 proximity grouping and T-225 floating icon tabs are separately tracked.
