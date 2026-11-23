# T-254 — Owner-requested icon-only minimized flyouts

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote baseline:** `7b1fd306` (includes the owner's exact two reference PNGs).
**Gate:** T-254 engineering Done; **T-250 still requires explicit owner hands-on approval**. No physical hardware or hosted CI acceptance is inferred.

## Finding and patch

The minimized dock's `DockGroupFlyout` was still built with a separate text-tab renderer (`tab.text = panel_id.capitalize()`) despite T-225 already shipping a canonical `DrawingDockIcons.for_panel()` asset loader. Flyout tabs were taller than necessary, lacked explicit `accessibility_name`, and `Shift+F10` ignored them because `_focused_dock_panel()` only inspected rail and expanded-dock buttons.

The new `_flyout_panel_button()` provides one 42×42 centered, icon-only Button for each visible panel, including the existing named SVG and `dock_panel.svg` fallback for future IDs. Tooltips and optional Godot accessibility labels retain the panel name. RMB and keyboard menu commands use `_show_dock_panel_menu(panel_id)` so that **inactive clicked tabs** retain their selection state and targeted actions are not applied to the current tab. The active tab's repeated LMB press is a no-op, and drag-suppression restores its pressed state rather than showing a false selection. Flyout tab focus is restored after selection by the existing deferred `_restore_dock_focus` transaction path. No new copies of views, alternate model ownership or custom native picker are created.

## Local native tests and negative control

Toolchain: supplied offline Godot 4.8 beta 3, Linux x86_64, Xvfb with Mesa software GL, Dummy audio. Source is staged via `python3 tools/build_drawing_app.py --in-place` and imported with `godot --headless --editor --path drawing --import --quit`; **running the import after staging is essential** for Godot SVG textures.

| Test | Observed result |
| --- | --- |
| **Previous code** (`7a480025` workspace source only), unchanged `t254_flyout_icons_native.gd` | Exit 1: **81 failures**; wrong text/icon identity, missing accessibility and keyboard menu failures. Original source restored after negative control |
| `drawing/tests/t254_flyout_icons_native.gd`, native X11 | **178 checks, 0 failures**, or **183/183** with `T254_SCREENSHOTS` enabled. Real click/drag/press, inactive context menu, 7px threshold, Escape rollback, selected-tab focus, compact/narrow/150%/200% screens, five-tab scroll including future-panel fallback, explicit layout save/restart, floating icon parity, hide/reopen, transactional redock and unchanged drawing revision/dirty flag |
| `tests/t254_atlas_flyout_native.gd`, native X11 | **12 checks, 0 failures**, canonical embedded Drawing workspace; clicked active/inactive icon behavior and unchanged Atlas raster/history state |
| T-222 native / Atlas | **47/47** / **12/12**, no regressions |
| T-223 group markers / T-224 icon proximity / T-225 floating icons | **40/40**, **43/43**, **81/81** |
| T-251 dock geometry / Atlas | **306/306** / **17/17**, same dock-local toggle |
| T-080 dock reorder / T-081 floating / T-083 persistence / T-091 one-group float | **70/70**, **58/58**, **63/63**, **44/44** |

All 12 neighboring X11/Atlas commands exited 0. The T-080 suite still emits the preexisting Godot `Unable to make the control visible because it is obscured by the inner ScrollContainer` diagnostic **after** its pass marker; do not present that as a clean log. The X11 V-sync warning is a software-rendering platform limitation.

### Reproduction

```bash
# After building the native extension and staging + importing both projects:
T254_SCREENSHOTS=/tmp/t254-screenshots xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t254_flyout_icons_native.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t254_atlas_flyout_native.gd
# With a configured toolchain, `make test-dock-flyout` runs both.
```

Five real software-framebuffer images were taken for initial/open/reopened, 150%, 200% and 600×470 narrow viewport cases (including two repeats). This evidence does not replace owner visual review of the original concept screenshots in `docs/assets/drawing-ux-2026-11-22/`.

## Remaining gates

All T-251–T-254 P0 *engineering* prerequisites are complete. T-250 now enters **Manual Review**, awaiting the owner's actual Drawing walkthrough and explicit approval or change requests; do not auto-close it. T-083 docking UX, T-059 overall Drawing, T-091 physical floating and T-088/T-095 reference-device performance review retain their independent conditions. Hosted CI is not claimed green.
