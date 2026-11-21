# T-223 — narrow triangle group marker and native docking witness

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`. **Last verified remote PR #22 head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`. The standalone/Atlas code changes are **local** until pushed by an authorized workflow. Owner design is in [2026-11-20 UX review](../DRAWING_UX_REVIEW_2026-11-20.md).

## Implementation

- `DrawingDockGroupMarker` is one **24×45 logical-pixel flat, focusable button**, with a drawn vector triangle rather than a text label or bitmap. Its expanded/collapsed orientation is bound directly to `DrawingDockLayout.group_info(id).collapsed`; name and keyboard actions are available through tooltip and accessibility property. It shares the `GroupBar` row with the horizontally scrollable panel icons. The former `GroupHeader`, group title `Label`, independent `GroupDrag_` and always-visible `Arrange_` are removed. The temporary flyout also has **no visible group-name heading**; close is an affordance beside the tabs.
- A left click toggles only that group's persisted collapse bit, exactly as a T-222 active expanded panel-icon click. Both calls use the same model method, not duplicate UI state. A 7px movement with left button held begins the existing `DrawingDockDrag.GROUP` transaction, and its release never activates the marker button. Cancelling/invalid drops preserve ownership, active panel, collapse and ordering.
- RMB or Shift+F10/Menu on a focused marker opens a **group-specific `PopupMenu`**. Its six valid-when-enabled actions cover group up/down, merge into neighbor, split the active panel and float the whole group into a new single-group host. Existing model commit/rollback performs each mutation. Panel icon RMB remains panel-scoped, and floating hosts retain the T-091 grip, close and edge resize; no duplicate panel views or source changes.
- The new marker is included in the shared `addons/drawing` package staged for standalone and embedded in Atlas. It adds no alternate drawing engine, history, or persisted schema change.

## Local evidence

Godot `4.8.beta3.official.c51ff06e8`, x86_64 Linux, X11/Xvfb, Mesa llvmpipe OpenGL compatibility renderer, native Rust GDExtension. Standalone source staged by `python3 tools/build_drawing_app.py --in-place`; Godot editor imports succeeded for both standalone Drawing and Atlas. Each script uses `quit(1)` on failed checks. All screenshots are captured from the native viewport into the conversation's `t223-native-screenshots/` folder (not committed to Git).

| Scope | Result |
| --- | --- |
| `drawing/tests/t223_dock_native.gd` | **47/47**; marker dimensions and header removal, LMB vs active icon, subthreshold activation, GROUP pointer/ESC rollback, RMB/Shift+F10 menu, reorder/split/float, restart persistence, 150/200% and 420px viewport, seven framebuffer screenshots |
| `tests/t223_atlas_dock_native.gd` | **13/13**; Atlas embedding, one original Colors view, marker and icon share collapse bit, nonmutating RMB, one-group floating host, re-dock and unchanged document revision/dirty status |
| `drawing/tests/dock_reorder_native.gd` (T-080) | **70/70**; group-pointer move/merge, auto-scroll, tab split/reorder and cancellation. Updated one legacy pointer target to account for the removed 40px header; originally failing target had landed in the group-edge zone, not its interior |
| `drawing/tests/dock_ui_native.gd`, `dock_float_native.gd`, `dock_cross_native.gd`, `dock_persistence_native.gd` | **40/40**, **58/58**, **57/57**, **63/63**, respectively (T-079/081/082/083) |
| `drawing/tests/dock_single_group_native.gd`, `dock_grip_redock_native.gd` | **44/44**, **53/53** (T-091 invariant/grip) |
| `drawing/tests/t222_dock_native.gd`, `t226_colors_native.gd` | **47/47**, **39/39** (without screenshot environment variables) |
| `tests/t222_atlas_dock_native.gd`, `t226_atlas_colors_native.gd` | **12/12**, **17/17** |
| Six headless dock model suites (`dock_layout`, `dock_drag`, `dock_float`, `dock_cross`, `dock_persistence`, `dock_single_group`) | **82/82**, **60/60**, **64/64**, **66/66**, **46/46**, **54/54** |
| `drawing/tests/t226_colors_model.gd` | **19/19**; underlying Colors semantics unaffected |

**Known limitations:** Automated X11 pointer events and software framebuffer/scaling are **not** owner hardware, compositor DPI, scanout timing or final UX signoff. The legacy T-080 script emits a Godot nested-scroll `ensure_control_visible` warning even with all 70 assertions passing. T-083 docking UX, T-091 physical floating behavior and T-059 Drawing overall owner gates remain unapproved. T-224 icon-proximity merge and T-225 floating icon tabs remain separate deliverables; T-148/T-149 native architecture work is not bypassed. PR #22 hosted fast-desktop CI was red/unverified at the last remote SHA due to an unrelated strict Linux package export staging directory and an obsolete T-083 exact-dependency test; those failures are not asserted fixed by this ticket.
