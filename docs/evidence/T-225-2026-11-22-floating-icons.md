# T-225 — icon parity for floating tabbed hosts

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`. **Verified remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`; the local changes here build on T-224 commit `1dbe805f`. No GitHub push/hosted CI or physical owner acceptance is claimed.

## Implementation and boundaries

- New shared `DrawingDockIcons.for_panel()` loads `dock_<panel_id>.svg` where present and `dock_panel.svg` for future registered panels. Both `DrawingWorkspace._dock_icon()` and `DrawingFloatingHost.render()` use that one resolver; tab, dock, rail and flyout retain matching `Texture2D` identity, without a fixed panel enumeration.
- The floating strip displays centered 42×42 icon-only toggle buttons, with active pressed state, keyboard focus, tooltips and accessibility names rather than persistent tab captions. An active floating icon selects but **does not** collapse, minimize, or close its group; re-render retains the focused tab if focus has not moved elsewhere. The test first detected a real focus-loss regression and the implementation now restores focus after the re-render.
- Floating groups still use one in-app host with a move/redock grip, close/hide control, edge/corner resize, scrollable icon strip, transactional one-panel icon drag and whole-group grip drag. Tab order, active membership, owned `Control` views, document bytes, and persistence version remain unchanged. Temporary future-plugin fixture is registered only **after** persisted default panels are restored; no fake assumption that an unregistered plugin round-trips is made.

## Local verification

Godot **4.8.beta3**, x86_64 Linux X11 via Xvfb, Mesa llvmpipe/OpenGL compatibility, native Rust GDExtension. `python3 tools/build_drawing_app.py --in-place` stages the shared Drawing package. Existing SVG `.import` sidecars were copied into the local staging directory (only) after staging; those generated files are not included in Git. All regression scripts return nonzero on failed checks.

| Test | Outcome |
| --- | --- |
| `drawing/tests/t225_floating_icons_native.gd` | **87/87** native-X11 checks: exact icon identity/fallback, tooltip/accessibility/pressed states, active click and Enter, keyboard focus retained, individual icon vs grip drag, Escape rollback, hide/reopen, restart, four/five tabs, scaling 150/200%, screenshot artifacts and unchanged document revision |
| `tests/t225_atlas_floating_icons_native.gd` | **10/10** Atlas-embedded native-X11 checks: shared icons, one host group, original panel `Control` reused, active tab not hidden, reopen, unchanged document history and Atlas window ownership |
| Existing headless docking model suites | `dock_layout_smoke`, `dock_drag_smoke`, `dock_float_smoke`, `dock_cross_smoke`, `dock_persistence_smoke`, `dock_single_group_smoke` plus `t224_dock_model`: **all passed** |
| Existing native T-079, T-080, T-081, T-082, T-083 suites | **40/40, 70/70, 58/58, 57/57, 63/63**, respectively |
| Existing native T-091 single-group and grip suites | **44/44, 53/53**; rerun after keyboard focus fix |
| Existing native T-222, T-223, T-224, T-226 suites | **47/47, 40/40, 43/43, 39/39**; T-224 rerun after focus fix |
| Existing Atlas T-222, T-223, T-224, T-226 suites | **12/12, 13/13, 12/12, 17/17**; T-224 rerun after focus fix |

Native framebuffer PNGs are delivered separately under `t225-native-screenshots/` (single icon, four/five tabs, hidden/reopened, 150% and 200%). Screenshots are not stored in Git.

## Remaining gates

This ticket has `manual_review: false`, its T-081 prerequisite is Done, and its icon-chrome scope is satisfied. **Parent T-091 and T-083 remain In Progress**, with physical Windows/Linux and independent owner UX review not approved. Required hosted CI at the exact final remote PR head was not run; the pre-existing PR #22 packaging/export and brittle dependency-assertion failures remain outside this one-ticket change. Tests in a virtual framebuffer are not a substitute for physical hardware evaluation.
