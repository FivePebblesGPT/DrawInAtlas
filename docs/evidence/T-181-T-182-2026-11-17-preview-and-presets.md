# T-181 / T-182 — Moving preview retention and native brush controls

Source fix: `da234cc7d985422303530ccfa6144e173c00461e`, PR #20.
Owner report: `/home/t0ast/Videos/Screencasts/Screencast_20261117_033517.webm`
(VP9, 1419×795, 60 fps, 7.2 seconds). The video was read without modification.

## Reproduction and diagnosis

The recording shows 128px display blocks disappearing during motion, with the
old picture returning when the cursor stops while the button remains held.

`drawing/tests/t181_native_preview_retention.gd` reproduces this in a real
graphical viewport with the real `DrawingNativeBrush` / `DrawingNativeTiles`
classes. It seeds a 512×512 document (256px storage tiles), warms all sixteen
128px display textures, and sweeps a 96px Hokusai Hard Round stroke at 54% zoom.
Every moving frame samples all sixteen tile centers from the actual framebuffer.
It also checks stationary holding, uncommitted source revision and publication.

**Before fix:** 19 checks, **11 failures**. Moving frames lose 8–12 tile-center
samples; frame metrics show four textures composited and up to twelve deferred,
despite all sixteen textures already being cached. Cache eviction counts are zero.

Ranked hypotheses were: deferred warm-texture submission; native cumulative
dirty-generation invalidation; incomplete native preview data. The first is the
direct cause of the visible holes. `Canvas._draw()` clears its previous draw
commands, then wrongly applies the cold-population budget to existing textures
whose preview stamp changed. Its `continue` skips texture submission entirely.
Stopping motion allows progressive refresh to catch up, matching the video.

**Fix:** only an *empty cache entry* can take the cold-population defer branch.
Existing textures are refreshed against the current preview and submitted in
the same frame. This is not a stale-texture fallback; cancellation, source
changes and publication still pass through ordinary compositing/invalidation.
Cold misses retain their budget and the GPU cache remains bounded.

**After fix:** 19 checks, **zero failures**, repeatedly on Wayland and Xvfb/X11.
All sixteen probes remain visible during movement, stationary holding and commit.
The original graphical cold-population, focal-retention and native history
neighbors also pass. The new test is available through `make test-graphical`
(requires `xvfb-run`) and is wired into the dedicated hosted toolchain workflow.

## Native brush selector

The shared workspace exposed a width control but no way to choose the four
presets already implemented by Canvas. Brush and Eraser now show:

- **Hard Round** (`hard`, default)
- **Soft** (`soft`)
- **Ink** (`ink`)
- **Airbrush** (`airbrush`)

The selector appears beside **Brush px**, whose maximum remains 96 pixels.
Changing it does not edit the document or replace the required Hokusai renderer.
Preset metadata stays separate from display labels. Existing scrollable options
and focus navigation keep it accessible in narrow windows.

All option controls are owned by the hidden options stash before first use.
This also fixes the previously orphaned, never-selected selection dropdown:
tearing down the test workspace no longer leaks its popup viewport and textures.

`t182_brush_preset_controls.gd` passes **16 checks** for preset labels/metadata,
staged `.myb` settings, 96px selection, tool switches and unchanged document
history. The compact workspace regression passes **75 checks**, including narrow
layouts, focus/wheel behavior and Save/Open/unsaved-state flows. That older
fixture now scrolls the width field into view before injecting its wheel event,
and uses a real swept native stroke instead of a sub-dab stationary click.

The actual standalone GUI was also driven through KWin EIS: opening the popup,
choosing Soft then Hard Round, typing width 96, zooming to 54%, painting a large
stroke, then moving a second stroke while holding the button. Screenshots show
the complete existing picture during motion and stationary holding. The virtual
session used an isolated HOME and was stopped after inspection.

## Validation

| Check | Result |
| --- | --- |
| `make check TOOLCHAIN=system` | exit 0; bootstrap, Ruff, ty, Rust format/25 tests, brush/tile/standalone/Atlas suites, new 16-check preset test |
| `make test-graphical TOOLCHAIN=system` | exit 0; T-181 19 checks, zero failures; strict log policy passes |
| `t137_preview_cold_population_native.gd` | exit 0; 18 checks, zero failures |
| `t138_preview_focal_plan_native.gd` | exit 0; 22 checks, zero failures |
| `t148_canvas_tile_cutover_x11.gd` | exit 0; 46 checks, zero failures |
| `compact_workspace_smoke.gd` (Xvfb/X11) | exit 0; 75 checks, zero failures; strict log policy passes |
| `python3 -m unittest discover -s tests -p 'test_*.py'` | 544 tests pass, 16 opt-in skips |
| Explicit GDScript typing check | pass |
| Ticket validator | 182 tickets; pass |

[Hosted workflow 44028692686](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/44028692686)
passes on the source fix `da234cc7`: fresh bundle generation, cold offline
native build/tests (including the 16 preset checks), two offline lint passes,
then the new real Xvfb framebuffer regression with **19 checks, zero failures**
and the strict log verifier. Its generated bundle retains the original
`3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2`
SHA-256 and 263,487,525-byte size.

The [broader desktop workflow](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/44028692901)
retains its previous **42/46** result and the same four failed check IDs
(T-085, T-087, Linux export, T-066). These focused fixes do not grant
release-export, physical input-latency or universal native-authority gates.

Early direct UI probes were launched before editor import, and one parallel
test restaged assets while another process was loading them. Their missing-SVG
errors are harness setup failures, not accepted green results. The final UI
checks run after import without concurrent restaging and pass the strict error
log verifier. The early failures are retained alongside the corrected runs.

## 96px fill benchmark and remaining performance work

One virtual Wayland run of `t146_hokusai_full_canvas_native.gd` with
`T146_RUNS=1` confirms actual Hokusai / Hard Round / width 96:

```text
source_pixels=262144
covered=262144 zero=0 full_coverage=true holes=0
total_to_postdraw_ms=529.487
release_to_commit_ms=485.408
stage_cpu_ms=114.730
compose_cpu_ms=279.539
tile_pixel_stream_calls=0
target_met=false
T146_HOKUSAI_BENCHMARK_PASSED
```

The marker certifies the test's correctness assertions, **not** its proposed
100ms latency target. Warm texture refresh can still cost tens of milliseconds:
native cumulative dirty descriptors currently invalidate broad storage-tile
footprints after each accepted batch. This change fixes lost presentation;
per-batch/per-display dirty generations and throughput optimization remain
separate native display work. T-095 physical responsiveness, T-148 universal
authority and T-149's broader integration gates are not closed.

The existing toolchain archive is unchanged: neither the repository nor these
GDScript sources are packaged inside it. No bundle rebuild or new upload is
needed to use this source correction.

## Raw evidence

`raw/T-181-T-182-2026-11-17-preview-and-presets.tar.zst` contains the fail-first
and final logs, frame metrics, selected GUI screenshots, video contact sheet,
exact command/exit-code records and hosted results. The original owner video
is not duplicated into the repository.
