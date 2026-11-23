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

Earlier source-only estimates were **71 → 65** (T-081) and **83 → 29**
(T-090). Real execution with the supplied toolchain corrected these to
**66** and **36** respectively, independently of whether optional screenshot
capture is enabled. The strict check floors now require those actual counts.
T-091 likewise requires **43** standalone host checks and **53** grip/redock
checks. Verifiers reject incomplete logs, script errors, failed assertions,
missing or duplicate markers and disallowed runtime diagnostics. Older ticket
evidence retains its historical pre-cleanup counts.

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

**Initial validation boundary:** This was written before the later local
native execution. The following completion evidence supersedes the earlier
"no new render" observation; it does not self-approve T-250.

## Local completion verification — 2026-11-23

**Inputs:** user-supplied branch snapshot at Git `5eaa24ddff4dce17`,
`drawing-toolchain-linux-x86_64.tar(2).zst` with Godot 4.8 beta 3, Rust 1.99.1,
and an offline Cargo vendor tree. Rebuilt `libdrawing_brush.so` from native
sources; imported standalone Drawing and Atlas. The initial release-profile
compiler and Atlas editor imports exceeded separate outer execution limits;
resuming with their cached outputs completed successfully. No downloaded
replacement source or substitute engine version was used.

**Test matrix:** the completed run produced **50 native X11 logs** with
zero assertion failures (including 33 standalone Drawing and 17 Atlas
witnesses), exercising T-063, T-065, T-079–083, T-090–093, T-184, T-221–227,
T-251–259, T-261, T-264–265 and T-271 paths. Representative complete
post-cleanup native check counts:

| Witness | Result | Why retained |
| --- | ---: | --- |
| T-081 floating host | 66/66 | Dock/canvas stability, pointer move/resize and unique panel ownership |
| T-090 responsive workspace | 36/36 | Real tool pointer dispatch, keyboard, resize, menu state and document tab closure |
| T-091 one-group floating host / grip-redock | 43/43; 53/53 | Edge drags, clamping, cancellation, group state and persistence |
| T-251 dock toggle / Atlas | 285/285; 17/17 | Click, focus, reparent, DPI and dock non-interception |
| T-092 Colors/history | 53/53 | Real scroll-to-visible input reachability and history safety |
| T-093 Object discovery / T-271 Atlas | 27/27; 24/24 | Browser selection, Object-source identity and global history isolation |
| T-065 Asset Browser | 19/19 | Panel registered by identity, not an arbitrary dock icon count |
| T-253 selection Delete / Atlas | 41/41; 15/15 | Native selected-pixel/history behavior |

All 50 witness logs were checked for their failure marker and zero assertion
failures. The original T-080 drag suite still emitted Godot's existing
`ERROR: Unable to make the control visible because it is obscured by the inner ScrollContainer.`
focus diagnostic after its success marker. Thus the collection is **assertion-
clean**, not literally free of Godot diagnostic output; T-080's existing
follow-up is not silently suppressed.

**Python/test-store:** 33 targeted Python tests passed across T-081/T-090/T-091/
T-092/T-093/T-270/T-271; `tests/check_explicit_types.py` passed **595
project scripts and 33 skill documents**; `tools/validate_ticket_store.py`
validated **272 tickets** with dependency/manual-review gates. Targeted
native strict log verifiers passed against real run logs. A separately run
T-063 documentation contract still fails because it expects T-056 to be
`Ready` although the authoritative ticket is correctly `Blocked` behind
T-250. This was identified before T-272 and is not an appearance-only assertion;
T-272 did not alter this unrelated product/review gate.

**Fail-first, then correction:** the first native T-092 run exposed three
wrongly written checks that assumed offscreen ColorPicker controls should
already intersect the visible dock after a History scroll. Tests now
use `ensure_control_visible` on FG, Hex and alpha separately and assert the
actual reachable state. The initial T-065 native run expected exactly four
icons, even though Brushes now registers separately; it was changed to
check browser identity/group membership. Both witnesses were rerun with
zero failures, not waived.

### Images actually opened and examined

The following were captured from the rebuilt running editor under **actual
X11/Xvfb + Mesa llvmpipe** and opened for visual inspection. Paths are
session-local capture locations, **not** durable repository references; the
user's original concept/current images under `docs/assets/drawing-ux-2026-11-22/`
remain the durable design references. Captures may also be shared as
conversation screenshot artifacts.

| Captured image (relative to local `screenshots/`) | Frame | Inspection outcome |
| --- | --- | --- |
| `t251_dock_toggle_native_drawing/expanded.png` | 1180×750 | Expanded toggle remains on an oversized left gutter; ColorPicker contents remain clipped/waste horizontal space. Not approved |
| `t251_dock_toggle_native_drawing/minimized.png` | 1180×750 | Minimized toggle remains inset/away from the intended edge; action arrow direction remains suspect. Not approved |
| `t251_dock_toggle_native_drawing/minimized-200.png` | 1180×750, simulated 200% content scale | Toggle, rail and an intentionally overlapping floating fixture visibly occupy cramped areas; not proof of hardware HiDPI ergonomics |
| `color_history_native_drawing/t092-compact-narrow.png` | 1280×800 | FG/BG strip, picker and extra controls still consume awkward space; scroll access works, design not approved |
| `color_history_native_drawing/t092-colors-floating.png` | 1280×800 | Real floating ColorPicker shown with clipping/scroll in small host; panel sizing still requires product correction |
| `dock_persistence_native_drawing/t083-after-relaunch.png` | 1240×800 | Persisted floating groups and minimized rail reappear; their current layout is functional, not aesthetically accepted |

These images were **visually compared** against the user's two real screenshot
reports, `image(2).png` and `image(3).png`, and the committed original
`DrawInAtlasColorPanelConcept.png`. The wrongly aligned toggle and redundant
ColorPicker space have **not** been fixed by removing cosmetic assertions.
Visual acceptance remains a separate owner decision under T-250; T-083 and
T-059 remain distinct manual/physical gates.

### Additional cleanup and boundaries

- Removed fixed two-column Brushes grid, numeric ColorPicker hex/dock width,
  icon-strip minimum, and T-091 decorative header/title checks where they
  claimed aesthetic correctness only. Actual scroll, keyboard focus, resize,
  group ownership and preference round-trips remain tested.
- Optional screenshot saves no longer affect behavioral assertion totals in
  additional T-082/T-083/T-091 dock witnesses, T-065 Asset Browser, T-093
  Object-source discovery, T-184 brush panels or T-271 Atlas source witness.
  Image capture failures are printed as diagnostics but do not imply the
  functional witness failed.
- `T-081`, `T-090`, and `T-091` Python log-contract fixtures and minimum
  accepted counts were reconciled against the **observed** X11 results.
- No native drawing/brush implementation, panel production geometry, Atlas
  document model, or release/owner approval state changed.
