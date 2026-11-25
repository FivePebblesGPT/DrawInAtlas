# T-274 — full-width native ColorPicker and optional strict RGBA8 (2026-11-23)

## Base, real visual comparison

- Base: local `903eef01` on the owner's Godot 4.8.beta4 sprint, descended from
  remote `main` `bbae76c33a6066582b2cd89e07cc3246fef942ce` (PR #22 squash).
- Original design reference: `docs/assets/drawing-ux-2026-11-22/DrawInAtlasColorPanelConcept.png`;
  current rejected app screenshot: `docs/assets/drawing-ux-2026-11-22/DrawingCurrent.png`.
- **Opened and inspected** the previous native X11 output
  `/mnt/data/t273-final/expanded.png`: the 226px expanded dock lost another
  34px to a full-height right toggle gutter; the inline picker retained its
  ~298px native minimum, cropped its hue/slider/hex right edge, and pushed
  another set of always-visible custom hex and RGBA8 fields below.
- Corrected native X11 screenshot artifacts, **opened and visually inspected**:
  `/mnt/data/t274-final/{expanded,recent-colors,minimized,flyout,floating,narrow,scale-150,scale-200}.png`.
  The 1280x800 normal image now displays the complete native color square,
  adjacent hue, numeric channels, modes and native hex across the 390px dock;
  two historical recents occupy two of six *narrow vertical* bar positions,
  rather than widening into massive color blocks.
- Full-height gutter removed. Only the first group header reserves a 34px
  toggle exclusion plus 10px header clearance; content below uses full width.
  The fixed right-edge overlay remains keyboard reachable and receives real
  pointer clicks when a scrolled native child has a larger raw rect.
- Root cause of the old 226px dock despite a nominal 270px preference:
  `HSplitContainer.split_offset = split.size.x - width` was positive and
  clamped to its right-pane minimum. Measured **live** 1280px root before the
  correction: `split_offset=890`, dock width 226, native picker minimum 298,
  viewport 218. A negative `-390` yields dock width 390, viewport/native
  picker 382; narrow `-226` retains horizontal scrolling for focusable native
  controls. The default/reset is 390, **not** a 390px hard minimum; the dock
  floor remains 226 and persists user-resized widths.
- The native RGB/HSV/Linear, native hex, alpha, swatches and hue controls are
  visible by default. Our **stricter** canonical hex / RGBA8 channel editors
  (including alpha-zero hidden RGB) are still available through the compact
  `Exact RGBA8` disclosure, instead of repeating the native entry fields at
  all times. Default black/white remains a compact adjacent action; FG/BG swap
  and the deliberate six-bar recent history remain in the top strip.
- At 350px floating size the native picker remains usable through its own
  horizontal scroll; native vertical scroller exposes the remaining controls.
  With 150/200% UI scale on a 1920x1200 actual framebuffer, the picker and
  right-edge toggle are readable and reachable, with naturally vertically
  scrollable content. At the minimum 226px dock the native right fields require
  horizontal scrolling; this is deliberate, not a claim of full-width use at
  the smallest possible panel.

## Functional evidence (not a cosmetic placement oracle)

Godot **4.8.beta4**, compiled Rust-backed `godot-rust` extension, real X11
(Xvfb, Mesa llvmpipe), Drawing staged/reimported and Atlas editor imported.
The new `drawing/tests/t274_color_compact_native.gd` uses `root.push_input`
for actual hue selection, exact RGBA8 disclosure/typing, outer-edge toggle,
minimized/flyout/floating/dock transitions and native focus/scroll at narrow
sizes; it captures real framebuffer images but does **not** assert visual
coordinates or screenshot hashes. Exact document revision/dirty/history is
unchanged, including alpha-zero hidden RGB. Atlas's embedded native witness
now opens/closes the disclosure with real clicks and checks focus before
exercising existing native color drag/campaign Save/Open and exact tile bytes.

| Witness | Observed checks, failures |
| --- | --- |
| T-274 standalone native visual/interaction | 24, **0** |
| T-251 right-edge standalone / Atlas | 92 / 19, **0** |
| T-252 settled-color native standalone / Atlas | 35 / 35, **0** |
| T-226 native standalone / Atlas | 37 / 17, **0** |
| T-092 native standalone color/history | 53, **0** |
| T-261 interrupted color gesture standalone / Atlas | 17 / 10, **0** |
| T-081 floating / T-083 persistence / T-091 one-group X11 | 66 / 63 / 43, **0** |
| T-226 / T-252 / T-092 headless palette model | 21 / 56 / 66, **0** |
| `tools/validate_ticket_store.py` | 274 tickets and manual gates validated |

The T-226 native **old fixture** initially had 2/37 failures: it set a positive
split offset while resizing, then assumed the native picker must horizontally
scroll. Corrected the witness to settle the window resize and explicitly
request the 226px narrow width before checking native focus/scroll: 37/37.
The T-252 headless **old fixture** initially had 2/56 failures: it simulated
spin dragging while the new strict editors were collapsed. The fixture now
expands the disclosure first: 56/56. These are test contract adjustments,
not evidence that a bad visual arrangement has passed an automated oracle.

**Boundary:** This is independent engineering completion. No physical-device
UX signoff, full CI signoff or owner approval is inferred. Owner must perform
T-250 manual review against the committed concept, including dense Selection
Delete responsiveness on their actual workstation; Atlas product gates remain.
