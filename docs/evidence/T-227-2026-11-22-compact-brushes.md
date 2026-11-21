# T-227 — compact visual Hokusai brush selector and verified dab-density mapping

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Last verified remote PR #22 head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146` (unchanged remotely at the start of this work). **Local parent:** T-225 `375cc199`.

## Engineering deliverable

- The existing four **actual native Hokusai-rendered** 92×32 previews are now in a two-column icon-only `GridContainer` with distinct active/pressed state, keyboard focus, persistent tooltips and explicit accessibility names. Removed the bulky heading, repeating description text and four stacked text rows; small labeled Width, Opacity, Edge and Dabs/r input rows plus a short Reset remain, usable in a ~192px dock. No new popup or duplicate panel authority.
- `dabs_per_actual_radius` is present in **all four** bundled `.myb` files with empty input mappings, and Hokusai 0.3's `stroke.rs::count_dabs_to` reads it when calculating how many actual-radius-distance dabs are due. `opaque_linearize` also uses the setting to compensate dab overlap. Exposing the base value as **1–8 dabs/actual radius**, step 0.25, changes actual Rust raster output rather than an inactive GDScript approximation. Native starting values: Hard Round **4.02**, Soft **3.14**, Ink **2.20**, Airbrush **5.75**. Hokusai receives unchanged source `.myb` bytes for all-default settings. `radius_logarithmic`, `opaque_multiply`, pressure, speed and custom input curves remain unchanged.
- No unsupported **flow, spray, grain, smear or random texture** sliders were added. `dabs_per_basic_radius` and `dabs_per_second` remain bundled at zero; their existence is not enough to justify new UX controls or promises. Very high densities increase native work, so 8 is a deliberate bound, not an engine maximum.
- Shared `DrawingWorkspace` stores per-preset `density` overrides and exposes the selected value to the same Canvas used by standalone and embedded Atlas, Brush and Eraser. In-flight `DrawingNativeBrush.begin_stroke` already receives an immutable MyPaint source string, now including density; queued gesture snapshots include density. Invalid/out-of-range/NaN/Inf values reject before native startup rather than reaching Rust.
- App settings schema **v3** stores `brush.density` per preset (alongside existing width, opacity and hardness). Strict decoder now accepts finite integral schema versions from *actual JSON-parsed numbers*: a fail-first native test caught that earlier v2/v3 integer checking rejected valid files after serialization. Valid v1/v2 preferences remain readable, with missing density defaults inferred from the native preset. No density setting is stored in `.drawing` document history.

## Local validation

**Environment:** bundled Godot **4.8.beta3**, Linux x86-64, Xvfb native-X11/Mesa OpenGL compatibility, compiled Rust `DrawingNativeBrush`/`DrawingNativeTiles`; fresh `drawing/` staging followed by Godot resource import. Generated staging assets and imported `.import` sidecars are test setup only, not staged into Git.

| Test / invariant | Verified result |
| --- | --- |
| `drawing/tests/t227_brush_settings.gd` | **47/47 headless**; four preset defaults, exact source bytes, unchanged pressure/speed mapping, invalid value rejection, schema-v2 decode and v3 JSON round-trip, all four native image labels, no-history edit, shared Brush/Eraser value and reset |
| `drawing/tests/t227_brush_native.gd` | **46/46 native-X11 checks**; real mapped pixel differences, one native history commit, native cancel rollback, exact Undo/Redo/Save/Open, unchanged in-flight and queued settings, 96px high-density path, dock/floating, narrow and 150%/200% native frames and restart restoration |
| `tests/t227_atlas_brush_native.gd` | **13/13 native-X11**; same Drawing panel and value authority under Atlas, shared Eraser, per-preset defaults/overrides/reset, floating single view and host independence, unchanged Atlas external history |
| `drawing/tests/t184_brush_panel_native.gd` | **77/77 native-X11** after changing one historical visibility assertion: compact Reset can now be visible **without** requiring a positive scroll offset; retains wheel and focus checks |
| `drawing/tests/t184_native_brush_panel.gd` | **53/53** existing native-X11 controls and parameter effects |
| `drawing/tests/t182_brush_preset_controls.gd` | **16/16** existing native-X11 compact preset selector |
| `drawing/tests/t225_floating_icons_native.gd`, `drawing/tests/t226_colors_native.gd` | Both passed after T-227; unrelated dock/Colors UI untouched |

**Measured native output:** same 16px Hard Round path at density 1 versus 8 yielded alpha-channel sums **191,327** and **212,960** (identical comparison rectangle, no image postprocessing); both nonzero, byte-different and undoable. One 96px density-8 local native-X11 stroke completed in **~105–114ms** across a few software runs. This is only a bounded **sanity check** of this short test path, not a p95 benchmark, not physical owner-hardware responsiveness, and not the T-095 96px *full-canvas* 200ms target.

Screenshots from real X11 framebuffer separately delivered in chat: `t227-native-screenshots/compact.png`, `floating.png`, `scale-150.png`, `scale-200.png`. They are not checked into Git.

## Open gates

T-227 has `manual_review: false`, its T-184 dependency is Done, and the scoped UI/native-control deliverable is complete. **Do not infer owner acceptance** of Brush responsiveness or the wider Drawing workspace: T-095/T-059 remain In Progress and need real owner-device review. T-148/T-149 native-authority work and PR #22 hosted CI remain independent; earlier packaging/export and obsolete dependency-test failures are not repaired here. No remote PR push or hosted CI rerun was performed as part of this ticket.
