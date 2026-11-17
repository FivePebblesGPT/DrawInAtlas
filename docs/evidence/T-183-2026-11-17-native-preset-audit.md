# T-183 — native preset identity/edge audit (2026-11-17)

**Scope:** one ticket, no UI redesign or backend change. Workspace `OptionButton`
metadata `hard|soft|ink|airbrush` selects `Canvas.BUNDLED_PRESETS`, whose `.myb`
bytes are passed as a string by `DrawingEditSession.begin_native_stroke()` to
Rust `DrawingNativeBrush.begin_stroke()`. Hokusai parses the preset and Rust
replaces the HSV color and base `radius_logarithmic = ln(width / 2)`; the remaining
settings (including pressure and speed input maps, hardness, `opaque`,
`opaque_multiply`, `dabs_per_actual_radius`, and `opaque_linearize`) are retained.
The Canvas/`paint_path_native` mouse path sends pressure **1.0**, not 0.5,
and `delta_seconds = 0.01`, so the MyPaint `opaque_multiply` pressure
curve directly governs default mouse opacity. Preset metadata IDs are correct;
this was **preset-parameter behavior**, not mislabeled selector IDs or a missing
native extension.

## Reproduction and corrected native source profiles

The same X11/llvmpipe (Godot 4.8 beta3, software GL), workspace, mouse path,
opaque foreground color, 256×256 image, unmasked raster layer, 9-point horizontal
stroke from `(-40.5, 0.5)` to `(40.5, 0.5)`, sampled pressure 1.0, and 60/96px
widths were used for the before/fail-first and after/green runs. New graphical
regression: `drawing/tests/t183_preset_profiles.gd`. It selects each preset via
the *real* workspace selector, records detached preview and committed source
RGBA8, verifies Eraser source-alpha decrease, exact Undo/Redo for brush and
eraser, and screenshots framebuffers at **100% and 50%** zoom. Source radial
samples are at x=0, y proportional to **half the selected nominal diameter**.
The checker-backed view at both zooms is also checked for visible pixel changes;
these are engine-rendered/software framebuffers, **not physical input-to-photon
latency or owner sign-off**.

The central/edge source-alpha evidence (8-bit alpha; radial fractions
`0%, 75%, 90%, 95%, 100%, 105%` of nominal radius) is:

| Preset | Width | Old alpha samples | New alpha samples |
| --- | ---: | --- | --- |
| Hard Round | 60 | 137 / 111 / 80 / 44 / 24 / 0 | **255 / 246 / 226 / 166 / 100 / 0** |
| Hard Round | 96 | 113 / 112 / 81 / 44 / 11 / 0 | **255 / 255 / 228 / 168 / 53 / 0** |
| Soft | 60 | 9 / 4 / 1 / 0 / 0 / 0 | **124 / 57 / 19 / 4 / 0 / 0** |
| Soft | 96 | 9 / 4 / 1 / 0 / 0 / 0 | **116 / 61 / 20 / 6 / 0 / 0** |
| Ink | 60 | 255 / 237 / 142 / 20 / 0 / 0 | unchanged |
| Ink | 96 | 255 / 241 / 147 / 38 / 0 / 0 | unchanged |
| Airbrush | 60 | 56 / 15 / 5 / 1 / 0 / 0 | unchanged |
| Airbrush | 96 | 103 / 17 / 5 / 1 / 0 / 0 | unchanged |

Both Hard Round's old `opaque_multiply(pressure=1) = 0.52` and Soft's old
`opaque_multiply(pressure=1) ≈ 0.0646` explain their weak pigment at ordinary
mouse pressure even though `hardness = 1.0` and `0.63` respectively. The old
Hard Round applied additional radius pressure and speed curves **after** Rust's
width override, meaning a selected diameter was not stable. Its new pressure
opacity multiplier ramps 0→1 and radius offset ramps −0.69→0 (nominal diameter
at full pressure), retaining stylus-sensitive input without the old speed
modulation. Soft now has a stronger but still sub-opaque pressure multiplier
ramping 0→0.8, retaining its `hardness = 0.63` feathering. No new rasterization
backend or polygonal/swept-circle shortcut was introduced.

The four presets remain intentionally different: Hard Round is firm and
opaque with a short anti-aliased edge; Soft is feathered with more pigment than
previously; Ink remains a near-opaque pen shaped by speed/pressure/tracking;
Airbrush remains a diffuse low-opacity smooth application. There are **no grain
or speckled spray particles** in these bundled curves (`offset_by_random = 0`,
`radius_by_random = 0` for all four); the owner was correct to observe none
from Soft. Airbrush is a soft pigment falloff, not a new particle engine.

### Preset hashes

| Preset | Before (SHA-256) | After (SHA-256) |
| --- | --- | --- |
| hard | `40838b34344409a0830a3b63f14120113a02635bdbeabd4d69ad2a62d24c5905` | `d321de8649e6b5cd529d0bf739ccfa9744ead7e5454ab5744d91c21d38bff3ad` |
| soft | `ad21f74d762fa19ecc5b03a3d0e8f1d952a8a66c8a21fc0e30cb3139235dbb0b` | `171af13ad646106c13c6e14bb1b9702bc097ab4f2165f280e5af6b298c6fc6a6` |
| ink | `917faff8f6bbd6b42a8f25f8a64fb2faf1bbb794c9e892c3fdd88f9669598a47` | unchanged |
| airbrush | `66bc41eafc5b061ac540ec674e80d8166a35f252b39b2962a00a50b0cae9cdff` | unchanged |

The original upstream MyPaint 2.0.2 preset licenses and mapping remain in
`addons/drawing/brushes/{README.md,Licenses.dep5}`; only Hard Round and Soft are
now explicitly tagged adaptations. The PopupMenu item tooltips document the
intended behavior without replacing T-184's separately scoped visual Brushes
panel.

## Fail-first / green and history/renderer checks

- **Red control:** same 189-check workspace/graphical regression while staging
  original `hard_round.myb` and `soft.myb` from `f5904146`: **6 failures**.
  Hard Round did not meet center/inside-edge assertions at either width, and
  the nearly invisible 96px Soft Eraser was pixel-no-op, so the ensuing Undo
  could not restore that brush stroke. All four old preset IDs and hashes were
  independently logged with real source alpha; no fake failing fixtures.
- **Green:** staged modified preset files, **189/189 pass**, including 60/96px,
  preview and commit, 100% and 50% framebuffers, all presets' native Eraser,
  Brush+Eraser Undo/Redo exact RGBA8, and selector metadata and tooltips.
- Additional checks: **25/25 Rust tests**; `native_brush_integration` 32 checks;
  `t148_native_tiles_contract` **312/312**; Atlas native history **43/43**;
  standalone smoke; T-182 selector
  **16/16**; graphical T-181 preview retention **19/19**. Toolchain `doctor`
  succeeds, `make check` passed 17 Python unit tests and Ruff/ty but was
  interrupted by the sandbox time limit at the broad Atlas project import;
  no claim that full `make check` completed. The dedicated listed native and
  Drawing tests completed independently after the interruption.

## Comparable 96px full-canvas control (not T-185)

On the identical Rust `libdrawing_brush.so` SHA-256
`07f91f19efa67b42517d8efcee1fc67ae7d8e0cbe67123519a323e592adc8b9c`,
Godot 4.8 beta3, X11 + Mesa llvmpipe, the T-146 **512×512, 100-event,
96px serpentine gesture** was rerun as 3 fresh cold processes per preset hash,
using `tools/run_t146_hokusai_bench.py --cold 3 --warm 0`. Each of the 6
runs independently validated as `valid=True`, full 262,144-pixel source coverage,
no holes, real native tiles, and correct Undo/Redo (no pixel fallback).

| Metric (ms) | Old Hard Round: 3 runs, median / range | New Hard Round: 3 runs, median / range |
| --- | --- | --- |
| Scripted down→settled post-draw | 604.08 / 572.89–729.91 | **569.72 / 506.61–657.86** |
| Release→commit | 552.85 / 518.80–675.38 | **517.37 / 455.54–604.17** |
| Native staging CPU (cumulative) | 121.78 / 120.28–145.78 | **120.32 / 113.17–130.10** |
| Compose CPU (cumulative) | 336.04 / 306.87–425.19 | **304.36 / 274.08–374.26** |
| First post-draw | 56.36 / 53.12–58.33 | **50.86 / 45.66–51.79** |

This small, noisy, three-run cold comparison only establishes a **new fixed-hash
baseline** for future T-185 profiling; it does not prove a performance
improvement, 250/200ms attainment, 60 FPS, or physical device acceptance.
T-185 still must profile real frame intervals, backlog, critical path and
T-181's overlapping caches on the updated hash.

**Local raw evidence** (ignored generated files): `.build/evidence/T-183/`
contains pre-change/final X11 logs, 16 pre-change and 16 corrected PNG
screenshots (`hard|soft|ink|airbrush` × `60|96` × `zoom-100|zoom-50`),
Rust/headless/graphical logs, and original/new three-run benchmark logs,
resource timings and machine-readable `summary.json`. These are test artifacts
rather than a checked-in performance contract. The commit includes the
reproducible test harness and the numerical results above.
