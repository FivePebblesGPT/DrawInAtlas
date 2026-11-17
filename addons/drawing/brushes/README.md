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
