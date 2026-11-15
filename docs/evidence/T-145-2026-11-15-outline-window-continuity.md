# T-145 — preserve cached selection outlines across shifted visible tile windows

**Date:** 2026-11-15. **Source:** `sprint/2026-11-14`, before-change T-144
commit `c4867d3f5edc8bc9920d6cadcafbd5ea24a91848`, tree
`98978facbff5e717f9e617d9605fcf090786c0b9`.
**Remote baseline:** `61c6f689974a848f8a7cc4040c98be418518b156`.
**Pinned engine:** Godot `4.8.beta3.official.c51ff06e8` on Linux x86-64.
**Native witness:** Xvfb/X11 with Mesa llvmpipe `gl_compatibility`, 1920×1080
window, 1680×960 Canvas, 25% programmatic zoom. Not owner GPU or stylus.

## Defect and narrowly scoped correction

T-142 preserved selection contours when a saturated focal plan changed *inside*
a stable tile window; T-143 additionally reconciled changed source clipping.
However, when a 64px camera pan actually changed the window's left/right tile
coordinates, `_sync_mask_outline_cache()` immediately cleared every cached
contour. This discarded already-computed source-coordinate line segments for
tiles shared by the new candidate plan, making a far selected island disappear
until hundreds of deferred frames could rebuild its contours at four per frame.

The updated sync method builds a bounded eligibility set when the visible tile
window changes (or the previous saturated focal/footprint reconciliation would
run) and evicts **only off-plan cache entries**. It updates the stored window,
focus and clipped footprint. Tiles remain capped at 4096, source contours and
drawing-order are unchanged, and selection mutation/deselection still clears
the cache. No selection truth, brush pixels, document revision, Undo/Redo,
source file format, or native dependencies change.

## Negative control and candidate on identical test inputs

The baseline controls use the exact committed T-144 `addons/drawing/canvas.gd`
blob staged into the independent Drawing app, together with the final T-145
model and native witness scripts. Its source checksum is retained in the run
notes; the candidate is staged from the changed canonical source. Both controls
exit nonzero and retain all failed assertions rather than generating a synthetic
success summary. The native test seeds a **valid settled cache** to avoid
waiting over 1,000 frames merely to reach the over-budget state.

| Reproduction | Unmodified T-144 | Candidate T-145 |
| --- | --- | --- |
| Headless selection/window model | 2/14 failures, process exit 1 | 14/14 pass, exit 0 |
| Native X11 exact framebuffer | 3/10 failures, process exit 1 | 10/10 pass, exit 0 |
| Shared cached contours after 64px pan | 0 retained | 4036 retained |
| Actual distant-island framebuffer delta after deselection | 0 changed pixels | 28 changed pixels |
| Selection raster/history authorization | No publication | No publication |

The camera shift translates the source clip from `(-3361, -1921)` to
`(-3297, -1921)` after the 1px contour margin and changes the window from
`(-53, -31)` to `(-52, -31)` while retaining thousands of eligible tiles.
The fast model additionally verifies that public in-place `set_mask()` and
selection replacement invalidate previously retained contours, that off-plan
tiles are removed, and that no cache exceeds 4096 entries. The test checks
that the native framebuffer really draws a selected 16×16 source island; it
is not a source-string-only or constructed-geometry-only proof.

## Neighboring verification

All were run on the candidate with the pinned Godot binary and completed with
exit code zero. All emitted their required success markers and passed
`tools/check_godot_model_log.py` (which preserves known *post-success* Godot
resource-leak diagnostics).

| Suite | Result |
| --- | --- |
| T-139–T-144 headless outline models | 14/14, 17/17, 12/12, 13/13, 14/14, 16/16 |
| T-139–T-144 native X11 outlines | 7/7, 9/9, 8/8, 11/11, 10/10, 9/9 |
| T-088 selection and clipboard | 131/131 headless, native success |
| T-088 sparse Paste and Capture | 56/56, 54/54 |
| T-096 large-selection and native Move | 13847/13847 headless, native success |
| Independent native-absent Drawing package consumer | 42/42 standalone |
| T-140–T-145 Python source/CI contracts | 23/23 passed |
| Explicit typing | 464 GDScript files, 33 skill documents |
| Ticket-store validator | 145 tickets valid; manual gates unchanged |
| Required fast CI | Still 46 unique check IDs |

The older T-142/T-143 model assertions explicitly expecting a blanket clear on
window changes were updated to reflect the new *eligibility-only* eviction;
their unchanged-window focal/clip and selection-authority regressions remain.
The native T-088 workflow remains **on demand**, separate from the 46-check
required CI inventory. Hosted GitHub CI was **not** rerun or claimed green.

## Reproduction commands

Run from the project root with the supplied pinned Godot beta3 as `godot`:

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing --script res://tests/t145_outline_window_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/t145_outline_window_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T145_MODEL_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T145_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t14*.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

All **29 retained raw run logs**, including the negative controls, are under
[`t145-outline-window-logs/`](t145-outline-window-logs/), with each file's
SHA-256 in [the manifest](T-145-2026-11-15-log-sha256.json).

## Scope and review boundaries

This is correctness and continuity for source-coordinate selection overlays.
It does not change pixels or demonstrate physical input-to-photon latency,
a dense-scene speedup, or hardware UI acceptance. T-088 remains **In Progress**,
T-096 remains **Manual Review**, and T-086/T-095 physical-performance,
T-106/T-107 hosted-CI and other owner/independent-review gates remain open.
