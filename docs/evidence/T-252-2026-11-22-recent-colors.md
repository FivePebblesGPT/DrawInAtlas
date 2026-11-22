# T-252 — settled recent colors and compact native ColorPicker

**Date:** 2026-11-22 · **Ticket:** [T-252](../Tickets/T-252.md) · **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes` · **Reference:** owner's [actual UI](../assets/drawing-ux-2026-11-22/DrawingCurrent.png) vs [concept](../assets/drawing-ux-2026-11-22/DrawInAtlasColorPanelConcept.png).

## Defect and correction

Previously `ColorPicker.color_changed → _set_selected_color → _remember_recent` recorded **every in-between pigment** during a native pointer drag. The recent strip became a gradient, obscuring intentionally chosen colors. The header also had two standalone previous FG/BG restore buttons, a redundant recent-colors caption and a separate Editing FG/BG row; none match the intended compact header.

The corrected shared Drawing workspace starts one in-flight color edit for a native picker pointer press or focused keyboard/text interaction. `_on_picker_color_changed` previews each exact RGBA8 change to the selected role (and foreground brush display) **without** writing recents or app settings. At pointer release (after GUI's last event), key-up, confirmed text or role change, `_finish_color_edit` compares canonical packed colors and remembers only the **original settled pigment** if the gesture changed it. Escape restores the original without history. An uncaptured single picker change acts as one explicit edit. Swap/Default, hex input and recent selection retain normal immediate semantics; alpha-zero RGB is retained.

FG, Swap, BG and six vertical recent bars now share the top header (no previous-restore buttons or `Recent`/`Editing` heading); the real Godot ColorPicker sits directly below. Default/exact-hex and RGBA are available by scrolling beneath the picker. The same registered view is moved through dock/floating/flyout hosts, with role-focused highlight and accessible tooltips.

Settled palette state is now stored **outside `.drawing`**, in `user://drawing-recent-colors-v1.json` with strict versioned uppercase RGBA8, 6-entry bound, 512-byte reader cap, de-duplication, atomic temporary write and backup recovery. History revision/cursor, dirty state, canonical raster bytes and document Save/Open do not change from pigment selection. The standalone app can disable app-settings persistence, as in the native fixture, or configure a private path for tests.

## Local verification — pinned Godot 4.8 beta 3 / Linux X11 Mesa llvmpipe

| Witness | Result and coverage |
| --- | --- |
| `drawing/tests/t252_colors_model.gd` | **56/56** checks: 25 intermediate picker signals, settled completion, cancel/no-op, BG/FG role freezing, RGBA8 hidden RGB, typed hex, recent choice, Swap/Default, key-repeat/release, focused native LineEdit, RGBA SpinBox drag, prefs restart, malformed/duplicate/over-budget data, backup recovery, unchanged document history |
| `drawing/tests/t252_colors_native.gd` | **35/35** checks: real X11 pointer press, 22 mouse motions with >9 distinct live colors but zero recents while held, one entry on release, Escape rollback, BG drag isolation, floating/redock, no document dirty/Undo changes; optional framebuffer captures `committed-foreground.png`, `committed-background.png` |
| `tests/t252_atlas_colors_native.gd` | **31/31** checks: embedded Atlas Drawing, 19 native pointer motions, shared UI control identity, exact campaign raster RGBA8 hashes and history unchanged, generation Save/Open |
| Neighboring standalone suites | T-251 **306/306**, T-223 **40/40**, T-225 **81/81**, T-083 **63/63**, T-226 **39/39** native; T-092 **53/53** native; T-226/T-092 model and T-252 model pass |
| Neighboring Atlas suites | T-226 **17/17** and T-251 **17/17**, alongside the new T-252 Atlas checks |
| Python contracts and lint | `tests/test_t092_color_history.py` **5/5**, CI fail-late contract **8/8**, explicit typing audit **569 project scripts + 33 skill documents**, ticket-store validation after docs |

The X11 witness is **virtual Xvfb/Mesa software input**, not a physical Linux/Windows display or owner approval. One redundant combined Atlas import/test run timed out during import; each relevant Atlas suite was subsequently run and passed **separately**. The required fast-desktop CI is extended with the T-252 model marker under existing T-092 check ID; the on-demand T-092 X11 workflow now includes T-252 pointer evidence, but neither hosted run is claimed green here. This ticket is **Done for the bounded code change only**. Parent T-092 and [manual T-250 Drawing UX gate](../Tickets/T-250.md) are not approved.
