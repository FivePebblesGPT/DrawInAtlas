# Bundled Hokusai brush definitions (T-183)

Preset IDs are stable: `hard`, `soft`, `ink`, `airbrush`. The workspace selector
maps these IDs through `Canvas.BUNDLED_PRESETS` to the `.myb` bytes, which the
required Rust `DrawingNativeBrush.begin_stroke` parses with Hokusai. Native
stroke startup overrides HSV color and the base `radius_logarithmic` with
`ln(Brush px / 2)`. All other preset curves still apply to Hokusai's input
samples; Drawing's ordinary mouse path supplies pressure **1.0** and
`delta_seconds = 0.01`. Width is a **nominal diameter**, not a guarantee of
identical visible coverage for different native brush shapes.

| UI preset | Brush source | Intended default at mouse pressure 1.0 |
| --- | --- | --- |
| **Hard Round** | Adapted `ramon/Round.myb` | Full-opacity, hard-edged round; stable nominal diameter; variable stylus pressure controls opacity and diameter |
| **Soft** | Adapted `experimental/soft.myb` | Usable, translucent feathered round; opacity builds across passes; no spray particles |
| **Ink** | Unmodified `classic/pen.myb` | Firm, near-opaque pen with pressure-, speed- and tracking-dependent stroke dynamics |
| **Airbrush** | Unmodified `deevad/airbrush.myb` | Smooth, diffuse low-opacity falloff; not a grainy/speckled spray brush |

The original definitions come from [MyPaint Brushes v2.0.2](https://github.com/mypaint/mypaint-brushes/tree/v2.0.2).
The authoritative upstream `Licenses.dep5` assigns the `.myb` definitions
**CC0-1.0**. No upstream artwork, PNG previews, or brush-pack binary ships here.
The original SHA-256 values (pre-change controls) are:

- `hard_round.myb` `40838b34344409a0830a3b63f14120113a02635bdbeabd4d69ad2a62d24c5905`
- `soft.myb` `ad21f74d762fa19ecc5b03a3d0e8f1d952a8a66c8a21fc0e30cb3139235dbb0b`
- `ink.myb` `917faff8f6bbd6b42a8f25f8a64fb2faf1bbb794c9e892c3fdd88f9669598a47`
- `airbrush.myb` `66bc41eafc5b061ac540ec674e80d8166a35f252b39b2962a00a50b0cae9cdff`

**Corrections:** The old Hard Round had `opaque_multiply` of just `0.52`
at full pressure, explaining its ~137/255 center source alpha. It also applied
pressure/speed radius offsets after the native width override. Now opacity
multiplier ramps to `1.0` at full pressure, and a pressure-only radius offset
ramps from `-0.69` at zero pressure to `0.0` at full pressure. The old Soft
preset's `opaque_multiply` was `0.064583` at full pressure, producing a center
of only ~9/255; its revised pressure response ramps to `0.8` for visible but
still non-opaque feathering. Neither preset adds texture, grain or particles.

See `docs/evidence/T-183-2026-11-17-native-preset-audit.md` for actual 60/96px
source alpha samples, GUI captures at 100%/50%, native Eraser/Undo/Redo checks,
and matched old/new 96px full-canvas performance controls.

## T-184 visual Brushes panel and runtime parameters

The separate **Brushes** dock group has one live `DrawingBrushPanel` Control,
shared by standalone Drawing and the embedded Atlas workspace. A compact
`OptionButton`/width shortcut remains synchronized, including in Eraser mode.
Selecting a preset does not alter the current drawing or its history. Every
Brush/Eraser native stroke captures its settings at pointer-down; pending
queued gestures capture those same scalar settings and selection mask. Changing
the panel affects **future** gestures only.

| Parameter | UI range | Native meaning / behavior |
| --- | --- | --- |
| Width | 1–96 Drawing px, step 1 | Nominal MyPaint diameter; Rust overrides `radius_logarithmic` at begin-stroke. Preset shaping/pressure curves still apply. |
| Opacity | 0–100%, step 1% | Multiplies the selected preset's **base** `opaque` setting, retaining its `opaque`/`opaque_multiply` pressure and motion input curves. Not guaranteed to equal linear final pixel alpha after cumulative dabs. |
| Hardness | 0–100%, step 1% | Overrides the MyPaint `hardness.base_value`, retaining preset pressure/speed curves; affects native dab falloff (including Ink/Airbrush). |
| Dab density (`Dabs/r`) | 1–8 dabs per **actual radius**, step 0.25 | Overrides Hokusai's `dabs_per_actual_radius.base_value` (distance divided by current native dab radius times density in the `count_dabs_to()` spacing calculation). Greater density increases dabs/work, not independent opacity, grain or spray; `opaque_linearize` compensates for overlap. All four bundled presets contain this setting without input curves. |

All four presets expose these three controls; the **starting hardness** is read
from each bundled `.myb` (not copied between presets). Hardness overrides are
per preset, while width and opacity are shared across presets and Brush/Eraser.
**Reset selected brush** clears only that preset's hardness override and resets
shared width to 3 px and opacity to 100%. Default opacity/hardness uses the
original `.myb` source string byte-for-byte; changed parameters produce a
MyPaint JSON string with `version` kept an integer for Rust's parser.

The app preferences file uses schema v2 with `brush.preset`, `brush.width`,
`brush.opacity` and `brush.hardness` keyed by preset ID. Schema v1 (selection
history only) remains readable with default brush parameters. These values are
app preferences, not document/save-source data. Dock visibility, tab group,
and floating owner continue using the existing separate dock layout file.

The four 92×32 transparent PNG buttons in `previews/` are **rendered native
Hokusai strokes**, not stock icons or manually drawn stand-ins. Reproduce with
`T184_PREVIEW_OUTPUT=/absolute/output/path godot --headless --path drawing
--script res://tests/t184_generate_brush_previews.gd` **after** `make
import-drawing`; this requires both `DrawingNativeBrush` and
`DrawingNativeTiles`. The generator fails on absent native classes, empty
native strokes, or failed commit/export. The Drawing staging step copies all
four previews byte-for-byte; tests verify that no placeholder preview is used.
Visual/functional evidence and native color/edge samples are in
`docs/evidence/T-184-2026-11-17-brush-panel.md`.

## T-227 compact selector and additional verified native control (2026-11-22)

The four unchanged native preview PNGs now form a two-column **icon-only**
selector (pressed state, tooltip, accessible preset name and keyboard focus).
Small labeled rows replace multi-line instructional paragraphs. Width,
Opacity, Edge and Dabs/r remain available in the dock, narrow scrolled host
and floating view; reset restores bundled shaping plus the shared width/opacity.

**Native parameter inventory (bundled `.myb` bytes):**

| Preset | `dabs_per_actual_radius` base, dabs/r | `hardness` base | Pressure/speed/native dynamics retained |
| --- | ---: | ---: | --- |
| Hard Round | 4.02 | 1.00 | Pressure radius and `opaque_multiply`, speed2 pigment curve |
| Soft | 3.14 | 0.63 | Pressure and speed1 radius, pressure pigment curve |
| Ink | 2.20 | 0.90 | Pressure/speed1 hardness and radius, pressure pigment, slow tracking |
| Airbrush | 5.75 | 0.48 | Custom-input radius and pressure pigment, speed2 settings |

Each preset **supports** this specific density setting. The preset JSON also
contains `dabs_per_basic_radius` and `dabs_per_second` with zero defaults,
but these are **not** new UI controls, nor are flow/spray/texture knobs.
Hokusai 0.3's `count_dabs_to()` uses the actual-radius density term to
schedule samples; its `opaque_linearize` uses density to compensate overlap.
Only `dabs_per_actual_radius.base_value` changes; all other native settings
and input curves remain unchanged. The 1–8 bound prevents unbounded dab work;
the default `.myb` source remains byte-identical with no overrides.

All Brush/Eraser settings originate in the single Drawing workspace and Canvas;
native `begin_stroke` freezes serialized MyPaint settings, and pending gestures
snapshot density alongside opacity, hardness, preset and width before promotion.
Density overrides are **per preset**, width/opacity shared. Preferences use
schema v3 (`brush.density` map) with strict finite numeric validation and read
compatibility for schemas v1/v2; the new control is never saved into the
Drawing document itself. Rust owns the dabs, tile output and Undo/Redo.
See `docs/evidence/T-227-2026-11-22-compact-brushes.md` for native-output
measurements, UI screenshots and regression tests.
