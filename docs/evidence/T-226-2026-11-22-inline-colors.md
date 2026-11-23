# T-226 — Inline Colors / native picker verification (2026-11-22)

## Scope and ownership

T-226 is the presentation and interaction replacement for T-092's former popup/collapsed advanced picker. The same `addons/drawing/workspace.gd` is used by standalone Drawing and the embedded Atlas host. T-092's History/preferences and T-059/T-083 owner-facing usability gates remain **In Progress / unapproved**. No owner signoff is claimed.

## Implementation

- A single header splits approximately evenly between FG/BG role blocks (active-role border) with compact previous-color restores and a sequence of narrow vertical recent-color bars; full RGBA8 hex identity is available through button tooltips and the dedicated strict hex field. Swap/Default remain keyboard-focusable with descriptive tooltips.
- Six-entry bounded history uses canonical packed **straight RGBA8**, retaining zero-alpha RGB, avoiding duplicate histories from float representation, and filtering both active FG and BG **at display time**. A bar applies its **visible filtered index**, not its raw storage index, to the active role only. Previously hidden colors reappear as current roles change.
- Godot's complete native `ColorPicker` stays visible inline, with exact hex and byte channel editor; there is no popup or second picker engine. Its intrinsic minimum width exceeds a 190px dock, so a dedicated **horizontal** `ScrollContainer` keeps its native controls reachable without widening the outer dock. The outer dock, minimized flyout, and floating host each retain their own **vertical** scroll, focus following and wheel scrollbar.
- Color changes are UI pigment edits, not raster/source edits or document history gestures. FG is the brush color; BG never substitutes itself for foreground paint. RGBA8 and hidden RGB are preserved on the canonical packed path.

## Verification environment and commands

Local Linux/x86_64, Godot **4.8.beta3.official.c51ff06e8**, X11 via Xvfb, OpenGL Compatibility via Mesa llvmpipe **25.0.7-2**. Headless and native checks operate on the canonical package, staged into `drawing/` after the code edit and imported using `godot --headless --editor --path drawing --import --quit`. X11 tests use `xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy`.

| Script | Evidence |
| --- | --- |
| `drawing/tests/t226_colors_model.gd` (headless) | **19/19** checks: canonical zero-alpha hidden RGB, alpha-unique recents, dedup/filter restoration, six-slot bound, role-safe picker signal/hex/brush, previous FG/BG, Swap/Default, no document history/dirty |
| `drawing/tests/t226_colors_native.gd` (X11) | **45/45** checks: two-part header, rendered FG/selection border, actual BG/FG/hex/recents pointer inputs, real native picker color-square pointer, wheel over native picker and host scrollbar, focus, 190px/490px short dock, 150%/200% UI scaling, native horizontal scroll, minimized flyout and 260×325 floating vertical scroll, no content/history mutation; six optional screenshot files enabled with `T226_SCREENSHOTS` |
| `tests/t226_atlas_colors_native.gd` (X11 under Atlas) | **17/17** checks: single hosted view, BG/FG/filtered bar pointer, external history unchanged, alpha-zero native tile, Atlas campaign Save/Open with byte-exact RGBA8 equality and cleanup |
| Historical T-092 headless / native regression | **66/66** and **52/52**; prior tests now expect the superseding always-inline picker and canonical recent identity |
| T-063 compact native workspace | **75/75**; legacy test now checks T-222's already-removed full-width minimizer correctly |
| T-222 native dock | **47/47** without optional screenshots |

Native screenshots were captured to `T226_SCREENSHOTS` as separate conversation artifacts (`expanded`, `narrow-short`, `scale-150`, `scale-200`, `flyout`, `floating`), not checked into the repo. These show actual software-X11 frames, **not** owner hardware validation. Plain vertical wheel inside the native picker is forwarded to the hosting vertical panel scroll without changing the pigment; modified wheel gestures remain available to native controls. Each host also permits scrolling on its scrollbar, and horizontally clipped picker controls remain reachable inside the dedicated horizontal viewport. The originally failing 190px width and original stale SVG import cache were addressed and rechecked after import.

## Remaining gates

Owner physical feedback on responsiveness, compactness, keyboard and wheel UX still belongs to **T-059/T-083/T-092**. PR #22's previously identified independent CI failures (export packaging root `project/` and the outdated literal T-083 dependency assertion) are not repaired or claimed green by this UI ticket. Native tests exercise software X11; no physical multi-monitor or Windows claim is made.
