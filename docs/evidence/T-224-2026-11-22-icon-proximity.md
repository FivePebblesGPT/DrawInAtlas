# T-224 — explicit icon-proximity merge, insertion and safe rollback

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`. **Verified PR #22 remote head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146` (unmodified remotely). **Local parent:** T-223 commit `1250448f`. This engineering result does not close parent T-083's owner UX acceptance.

## Behavior and boundaries

- The workspace distinguishes **dragging one icon** from **dragging the T-223 triangle** using `DrawingDockDrag.PANEL` versus `.GROUP`. The existing threshold starts a drag at 7 logical pixels; a hover, subthreshold click, or invalid release never merges groups. Real panel icon strips and the minimized rail accept precise index insertion; explicit between-group gaps create a singleton. Hovering an expanded dock or floating panel's **body** does not produce an accidental panel merge. Whole-group marker/grip transactions still accept the established whole-group drop zones.
- Reused layout/UI logic stages a `DrawingDockDrag` candidate without changing the live `DrawingDockLayout` until commit; invalid target, Esc, focus loss, and stale external mutation preserve the snapshot. One panel ID stays in one group; removing the last icon removes the empty source group. A floating host still owns one group (never nested groups), and every panel keeps its original `Control` view.
- The **exact insertion line** is blue for within-group reorder, green for icon-to-other-group merge, amber for between-group singleton split / whole-group move. A green translucent **outline** marks the target icon strip, and a short high-contrast caption names the pending action. The prior bare-canvas detach preview still names floating, with no separate preview-time container allocation. Overlays ignore pointer input and are removed immediately on invalid hover/cancel/drop.
- Horizontal drag autoscroll activates within 22 logical pixels of a visible tab-strip edge at 310 logical px/s and recomputes the pending target. Existing 420px/s vertical dock/floating autoscroll and Ctrl+Alt keyboard panel/group alternatives are retained. Version-1 `DrawingDockPersistence` layout/settings format is unchanged.

## Local validation

Toolchain: **Godot 4.8.beta3**, x86_64 Linux, Xvfb/X11 + Mesa llvmpipe OpenGL compatibility, native Rust GDExtension. Standalone Drawing was refreshed with `python3 tools/build_drawing_app.py --in-place`; imported SVG sidecars were restored to the **local staged test copy** for the legacy icon-oracle suite. The import artifact adjustments are not in the Git commit. All test scripts exit nonzero on failed assertions.

| Test | Result |
| --- | --- |
| `drawing/tests/t224_dock_model.gd` | **52/52** headless checks: deterministic group ordering, merge/split/reorder, source singleton cleanup, floating one-group enforcement, stale commit rejection and bit-exact snapshot/restoration |
| `drawing/tests/t224_dock_native.gd` | **49/49** native-X11 checks (including screenshot assertions): actual mouse threshold, no passive merge, green outlined icon target, body-hover invalidation, same-group blue reorder, amber singleton gap, marker-only whole-group merge preview and Escape, Ctrl+Alt+Down grouping, saved layout after restart, 150/200% scaling, narrow dock, real drag horizontal autoscroll and cancel |
| `tests/t224_atlas_dock_native.gd` | **12/12** Atlas-embedded native-X11 checks: same icon preview, dock-to-dock merge, dock-to-floating single-panel transfer, stable one-group floating host, unique Colors view and unchanged document history/dirty bit |
| Existing six dock model suites (T-078/080/081/082/083/091) | **82/82**, **60/60**, **64/64**, **66/66**, **46/46**, **54/54** headless checks |
| Existing T-222/T-223/T-226 Atlas suites | **12/12**, **13/13**, **17/17** embedded-X11 checks, respectively |
| Existing T-079–T-083 native suites | **40/40**, **70/70**, **58/58**, **57/57**, **63/63**, respectively; T-079 initially had four missing-icon fixture failures when the freshly staged Drawing copy lacked `.svg.import` sidecars; retest passed after sidecars were restored locally |
| Existing T-091 native suites | **44/44**, **53/53**: floating one-group and normal grip redock unchanged |
| Existing T-222/T-223/T-226 native suites | **47/47**, **40/40**, **39/39** in graphical tests without screenshot environment variables |

Screenshots are exported separately in the conversation under `t224-native-screenshots/`: `merge-preview.png`, `reorder-preview.png`, `split-preview.png`, `scale-150.png`, `scale-200.png`, `narrow.png`. They are native framebuffer evidence, not checked into the repository.

## Remaining gates

This narrow ticket is **Done**: prerequisite T-223 is Done, its own manual flag is false, source/test/docs are updated. **Not approved:** T-083 actual owner dock UX, T-091 physical host behavior, T-059 overall Drawing UX, T-148/T-149 native authority, hosted exact-head PR CI, and the unrelated known packaging/export and legacy T-083 dependency-assertion failures. X11/Mesa virtual framebuffer does not establish real desktop pointer/compositor correctness.
