# T-090 current-native responsive UX engineering verification — 2026-11-22

## Scope and outcome

**Engineering Done, not owner UX approval.** This is a regression/CI-harness
closure for the historical T-090 responsive shell. The production Drawing/Atlas
runtime, pixels, saved formats, selection/history, and dock implementation
are unchanged. Source: PR #22 local branch with T-251–T-254 and T-087 already
present. Owner's T-250 Manual Review and broad T-059 remain unapproved.

## Discovered defects in verification and fixes

1. `.github/workflows/godot-native-t090-workspace.yml` staged/imported Drawing
   without building `libdrawing_brush.so`; unlike tracked source, the native
   binary is generated, so this path could not run on a clean checkout. It now
   selects pinned Rust 1.99.1 (with rustfmt) and uses the already-existing
   `make build TOOLCHAIN=system` native build + both-consumer import path.
   The result was executed locally, **not on GitHub Actions**.
2. The existing X11 T-090 shortcut fixture assumed the saved Brush width is
   always 3px. A second run after prior workspace settings failed two literal
   width assertions; explicitly initializing 3px before `[`/`]` made the
   test deterministic across repeated launches. No preference/toolbar
   production semantics changed.
3. T-063 `compact_workspace_smoke.gd` sent a wheel event to the expanded
   dock's old top-left header `(24,18)`. T-251 intentionally reserves that
   coordinate for the half-circle control. The test now scrolls from `(16,90)`
   in the empty dock gutter *below* the toggle. The unchanged runtime scrolls
   normally, and the complete 75-check X11 suite passes. No scrollbar or
   dock implementation was changed.
4. T-090's X11 regression adds six assertions over expanded/minimized dock
   transitions: actual native framebuffer edges stay non-black, tabs/topbar
   and canvas remain within the viewport, and the state matches the requested
   layout. This is an independent responsive-shell contract, not a duplicate
   owner signoff for T-251.

## Commands and observed results

Environment: Debian GNU/Linux 13 x86_64; Godot
`4.8.beta3.official.c51ff06e8`; Xvfb/X11 OpenGL compatibility; Mesa llvmpipe
25.0.7-2; pinned local Rust 1.99.1 and the supplied Linux toolchain.
Graphical tests used a 2200×1500×24 Xvfb root framebuffer and Godot's
`--audio-driver Dummy`. Import and native tests used the same canonical
repository; the observed numbers are local software evidence.

| Command / witness | Result |
| --- | --- |
| `make build TOOLCHAIN=system` (local system mode with supplied tools/vendor) | PASS; native Hokusai built, standalone Drawing + Atlas imported; both printed `NATIVE_EXTENSION_READY` |
| `python3 -m unittest discover -s tests -p test_t090_responsive_workspace.py -v` | **10/10 passed**, includes cold-workflow contract |
| `godot --headless --path drawing --script res://tests/topbar_overflow_smoke.gd` | **32/32**, `T090_OVERFLOW_PASSED` |
| `xvfb-run ... godot --path drawing --script res://tests/responsive_workspace_native.gd` | **83/83**, `T090_NATIVE_PASSED` after changes; baseline 77/77 |
| `xvfb-run ... godot --path drawing --script res://tests/compact_workspace_smoke.gd` | **75/75**, `T063_WORKSPACE_PASSED` after updated wheel position |
| `xvfb-run ... godot --path drawing --script res://tests/t120_file_object_native.gd` | PASS, `T120_NATIVE_PASSED` |
| `godot --headless --path drawing --script res://tests/t120_unified_open_smoke.gd` | PASS, `T120_MODEL_PASSED` |
| `xvfb-run ... godot --path drawing --script res://tests/t251_dock_toggle_native.gd` | PASS, `T251_DOCK_PASSED` |
| `xvfb-run ... godot --path drawing --script res://tests/t254_flyout_icons_native.gd` | PASS, `T254_FLYOUT_NATIVE_PASSED` |
| `xvfb-run ... godot --path drawing --script res://tests/color_history_native.gd` | PASS, `T092_NATIVE_PASSED` |
| `xvfb-run ... godot --path . --script res://tests/t251_atlas_dock_native.gd` | PASS, `T251_ATLAS_PASSED` |
| `xvfb-run ... godot --path . --script res://tests/t254_atlas_flyout_native.gd` | PASS, `T254_ATLAS_PASSED` |

Headless T-063/keyboard smoke is **not** a valid substitute for a native
display: both scripts explicitly require a native viewport; the X11 T-063
run is the actual evidence. The T-090 native suite was re-run after the
fixture correction and passed. No physical GPU, Windows, real DPI monitor,
first-party owner walkthrough or hosted Actions result is asserted here.

## Review boundaries

Do not mark the owner's [2026-11-05 native UX review](../DRAWING_USABILITY_REVIEW_2026-11-05.md),
[T-059](../Tickets/T-059.md), [T-250](../Tickets/T-250.md), or
[T-056](../Tickets/T-056.md) approved based on this evidence. T-090's own
`manual_review: false` only applies to its bounded engineering checklist;
Atlas feature gates remain subject to their explicit T-250 dependency.
