# T-272 — Appearance-only UI assertion audit and cleanup

**Date:** 2026-11-23. **Source:** PR #22 after `0e2db61` (root `AGENTS.md` policy).
**Scope:** automated Drawing/Atlas UI test assertions and source/CI contracts,
not the editor's production layout. This document records dispositions against
the **pre-cleanup** line numbers; line numbers shift after removal.

## Actual visual inspection and authority

The owner's two screenshots were opened and inspected, not merely listed:
`image(2).png` (expanded dock, ColorPicker blank space and reversed arrow)
and `image(3).png` (minimized rail, toggle far from intended edge).
They show the historical layout contracts did not guarantee acceptable
placement. They are the owner's **real running editor** captures, not generated
mockups. No new standalone/Atlas build or 150/200% framebuffer screenshot
could be obtained in this session; therefore no fresh native or HiDPI visual
acceptance, no statement that the UI has been fixed, and no T-250 approval
is claimed. Previous local screenshot-generation evidence in T-251/T-260
is retained as history, not proof the owner-approved layout was seen.

## Disposition by test family

| Previous location | Appearance-only assertion and disposition | Functional checks retained |
| --- | --- | --- |
| `drawing/tests/t251_dock_toggle_native.gd:51-82` | Drop fixed top-left anchor and 34px gutter oracle; replace 30×56 size test with keyboard focus, and 56px slot height with icon-displacement behavior | Actual dock-vs-canvas hit rect, no button interception, rail slot ownership, clicks, focus, DPI and persistence |
| `drawing/tests/dock_float_native.gd:121-170,287-311` | Remove fixed 226px floor, 34px gutter, 48px rail minimum, exact anchor, minimum host frame and decorative hide-button width checks; use width stability/contraction, reachability and focus | Canvas width invariance, host ownership, pointer move/resize, clamping, hide/reopen, history |
| `drawing/tests/t222_dock_native.gd:98-109,223-239` | Remove oversized-chrome-absence and fixed toggle dimensions/34px seam | Canvas pointer non-interception, real icon collapse/flyout, drag threshold, scaled click reachability, restart |
| `drawing/tests/t223_dock_native.gd:95-107,233-235` | Remove group-header chrome/marker-width ratio/visual-neighbor assertions | Group collapse, menu/drag, keyboard focus, float/redock, persistence |
| `drawing/tests/t225_floating_icons_native.gd:85-100` | Remove icon-only, centered-icon and fixed 42px tab assertions | Tab focus and accessible names, active-state changes, float/hide/reopen/restart |
| `drawing/tests/t226_colors_native.gd:78-86` | Remove 50:50 FG/BG/recents visual width and picker-below-strip assertions | Color identity/hex/rgba, inline parent ownership, scroll reachability, actual pigment feedback |
| `drawing/tests/t227_brush_native.gd:111-139` | Remove two-column grid, fixed dock width, density-input decorative width | Native parameter bindings, preview/preset selection, accessible input, keyboard/floating behavior |
| `drawing/tests/t254_flyout_icons_native.gd:79-85,265-268` | Remove visual icon parity/textless/42px tab assertions | Tab focus/tooltips, active pressed state, RMB/keyboard context, cancellation, transfer and persistence |
| `drawing/tests/responsive_workspace_native.gd:96-139,197-206,270-280` | Remove tool-icon framebuffer centroid/radius and edge-color visual oracles; stop counting screenshot writes | Real tool click routing, tabs, focus, resize canvas reachability, More/keyboard/wheel and unsaved close |
| `drawing/tests/color_history_native.gd:218-225` | Replace fixed 120/69px input widths with editable/focusable inputs actually in viewport | FG/BG, recent color, history/prefs, narrow and floating access |
| `drawing/tests/compact_workspace_smoke.gd:86-94,234-237,299-310` | Remove decorative divider/More-button order; remove one-row heights and icon-only assertions | Accessible tool actions, overflow menu access, scroll/wheel, focus, document/history safety |
| `drawing/tests/dock_ui_native.gd:132-143` | Replace 62px rail, 40px button width and textless-icon assertions with state, focus, tooltip | Grouped rail state and selected flyout behavior |
| `drawing/tests/t184_brush_panel_native.gd:132-137` | Remove exact 92×32 preview-art dimension; keep nonempty native image | Source-backed raster content, selectable presets and mapped native parameters |
| `tests/t223_atlas_dock_native.gd:54-56` | Remove marker-vs-tab width relationship | One shared focusable marker, embedded group state, history |
| `tests/t225_atlas_floating_icons_native.gd:47-66` | Remove icon equality and textlessness | Tab availability/focus, active selection, hide/reopen ownership |
| `tests/t227_atlas_brush_native.gd:39-40` | Remove two-column picker-grid assertion | Shared Brush panel identity and native parameter usage |
| `tests/t254_atlas_flyout_native.gd:65-69` | Remove icon equality, textless and fixed 42px assertions | Focusable named tabs, Atlas host state/selection/history |
| `tests/test_t081_float_native.py:15-35` | Remove source-text assertions for 226/34/48 and stale native labels | Floating canvas-width/recovery regression contract and strict native log verifier |
| `tests/test_t090_responsive_workspace.py:64-107` | Remove source-text oracles for 42/34 centered glyphs and decorative plus/close buttons | Real native tool clicks, close guard, focus, CI/log strictness and icon-license verification |

Additional UI screenshot-save checks were demoted from test counts to
**optional diagnostic capture status** (reported with
`OPTIONAL_VISUAL_CAPTURE_FAILED`) in Drawing dock reorder/UI, T-224,
T-252, T-255–T-257, T-221/T-253 selection witnesses and all affected
screenshotted suites above. Captures remain available for human opening and
comparison. A screenshot being saved is no longer a UI-acceptance assertion.

## Deliberately retained behavioral geometry

- Clipped floating tab rectangles in T-255/T-256 genuinely determine whether
  a pointer event reaches an invisible tab, close button or move grip.
- T-257/T-258/T-259 host rectangles confirm exact geometry **rollback** after
  Escape, focus loss and missing mouse-up; they test a state transition.
- Canvas minimum usable area, out-of-bounds clipping, scrollbar reachability
  and avoidance of input overlap are necessary functional contracts.
- Raster framebuffer RGBA/hidden-RGB parity and native brush-preview pigment
  evidence protect pixel **data correctness**, not subjective panel styling.
- History, persistence, source identity, accessibility, input focus, density
  and Delete latency checks were not intentionally weakened.

## CI/test contracts and commands

T-081's minimum complete native log changes **71 → 65 checks** after removal of
four explicit size/gutter oracles, one optional screenshot count and one
aesthetic small-host dimension check. T-090's complete native GUI log changes
**83 → 29 checks** (three 14-check glyph-centering sweeps, seven optional
screenshot counts, three framebuffer edge-color checks and two dock-edge-color
checks removed). Neither verifier allows missing markers, real script errors,
failed assertions or an incomplete surviving check floor. Historical evidence
continues to quote the original count as historical evidence.

The required hosted fast-desktop workflow now runs both targeted Python
source/log contract suites (`test_t090_responsive_workspace.py` and
`test_t081_float_native.py`) in addition to its regular tests.

Re-run, with a checkout and Godot/Rust/X11 tooling available:

```sh
python3 -m unittest tests.test_t081_float_native tests.test_t090_responsive_workspace
python3 tools/validate_ticket_store.py
make test-dock-toggle test-dock-flyout test-floating-tabs test-floating-dock \
  test-color-interruption TOOLCHAIN=system
```

**Validation boundary:** A static source/contract review alone is not a
fresh Godot render. Native runs must be observed before claiming new GUI
performance, interaction or visual results. Owner T-250 remains Manual Review.
