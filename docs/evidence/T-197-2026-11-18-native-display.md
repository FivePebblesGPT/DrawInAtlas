# T-197 — native display-only zero-alpha conversion and matched Eraser A/B

2026-11-18 · `sprint/2026-11-17` · T-197 **In Progress** · no manual acceptance claimed

## Cause and bounded change

`DrawingRenderer.render` already selected Rust's tile-local 128px RGBA8 crop
for a single native raster layer, but rejected it if the cropped draft
contained any zero-alpha pixel with nonzero hidden RGB. In native Eraser this
rejected the crop and called the pixel-loop GDScript `_composite_raster`,
repeatedly retrieving/exporting a full 256px tile while staging preview.
The original renderer skips zero-alpha pixels; its **display** result must
contain `(0,0,0,0)` at those positions, even when the authoritative source
retains color bytes.

`DrawingNativeTiles.read_tile_region_display` now copies exactly the same
bounded native crop, then zeros RGB only where alpha is zero. The normal
`read_tile_region` stays byte-exact and still exposes its hidden RGB. The
`DrawingEditSession.preview_rgba8_region` cache distinguishes `display` and
`source` variants without relaxing the eight-entry per-tile bound; revision
and edit invalidation remain unchanged. `DrawingRenderer` requests the
sanitized preview crop only for the previous single-layer/tile-local guard.
It does not change brush dabs, native source/history ownership, commit,
selection, persistence, texture uploads, or release scheduling.

The additional diagnostic `DRAWING_T197_RAW_HIDDEN_COUNTERFACTUAL=1` reproduces
the previous behavior *on the same binary*: it requests source-exact cropped
bytes, accepts that crop only when there is no hidden RGB, otherwise routes
to the unchanged GDScript compositor. The older
`DRAWING_T187_FULL_TILE_COUNTERFACTUAL=1` instead forces **every** preview
to that compositor and is not a fair baseline for already-fast Brush.

## Native and graphical parity

The T-187 live X11 test now performs 183/183 checks, adding native Eraser,
zero-alpha source/display cache isolation, source re-read after display
conversion, and exact image matching to both full-tile and historical hidden
RGB counterfactuals. Signed coordinates, multilayer fallback, native
Undo/Redo, and bounded arbitrary crops remain covered. The Rust unit
regression checks alpha 0/1/128/255, idempotence and source immutability.
The existing T-196 and Atlas smoke cases cover selection holes, cancellation,
standalone native Save/Open, native history and restoration of hidden RGB.

## Real Drawing workspace A/B, not synthetic render-only timing

A confirmed zero-exit four-process **R → O → O → R** series uses the same
native binary (SHA-256
`dcaf73fa6e0b113f76aa12d6072a598406dea19e5a12a026db47334df2e45074`),
the same full Drawing workspace test and deterministic 96px Hokusai input:
54% and 100% zoom, each with cold/warm/held Brush then Eraser. `R` sets
`DRAWING_T197_RAW_HIDDEN_COUNTERFACTUAL=1`; `O` leaves it unset.
Every process has one valid `T185_PROFILE_PASSED cases=8 failures=0` marker,
a confirmed `/usr/bin/time -v` exit 0, and eight strict, parsed native source
transactions. All eight per-case **canonical after-RGBA SHA-256 hashes match
across all four processes**; 32/32 corresponding completed source cases pass.
The order deliberately reverses the environment switch. RSS in the four
processes: 323044 / 324440 / 325280 / 324140 KiB.

| Gesture / zoom | R composition CPU (ms, 2 runs) | O composition CPU (ms, 2 runs) | R first postdraw (ms) | O first postdraw (ms) |
| --- | ---: | ---: | ---: | ---: |
| 54% cold Brush | 3.3 / 3.2 | 3.4 / 4.0 | 33.1 / 33.5 | 27.6 / 33.3 |
| 54% warm Brush | 2.9 / 2.8 | 3.2 / 3.3 | 21.6 / 25.5 | 23.3 / 35.6 |
| 54% held Brush | 2.9 / 3.0 | 3.0 / 3.0 | 29.1 / 22.2 | 23.9 / 29.6 |
| **54% Eraser** | **80.7 / 76.7** | **3.0 / 3.3** | **39.9 / 35.3** | **23.1 / 20.6** |
| 100% cold Brush | 2.9 / 3.0 | 3.4 / 3.5 | 27.0 / 26.7 | 26.6 / 27.7 |
| 100% warm Brush | 2.9 / 2.9 | 3.1 / 3.1 | 25.0 / 30.0 | 27.0 / 27.0 |
| 100% held Brush | 2.9 / 2.6 | 2.9 / 3.1 | 26.2 / 23.7 | 23.4 / 28.4 |
| **100% Eraser** | **81.9 / 77.0** | **3.1 / 3.5** | **32.2 / 31.4** | **23.1 / 26.8** |

CPU composition drops at least 95% for each observed Eraser gesture.
This is a **component CPU improvement**, not a claim about population p95
or physical latency. At least one postdraw interval ≥83.33ms remains in
each of the four workspace processes. Their combined counts in order are
5 / 5 / 5 / 4. Across the Eraser trials, worst postdraw interval is still
101.7–111.6ms in optimized mode versus 106.3–115.0ms in reference mode;
other cases have noisy or regressed tails. The 200ms p95, paced FPS and
owner mouse-to-photon acceptance are still open. Do not extrapolate a
stable FPS from this low-N software-X11 sampling.

## Raw artifacts and failures retained

`T-197-2026-11-18-native-display-raw/exact-round-*` contains each
full-workspace original `.log`, independent `.time` process exit, the strict
validator's `summary.json` and a `runner.exit` sentinel. Earlier exploratory
`round-0` through `round-4` forced *all* previews through the full-tile
counterfactual, showing how misleading that choice is for Brush; these are
**not** the matched baseline quoted above. The original `round-3-reference`
ended with a success marker but no independently confirmed exit and an empty
`.time`; it is deliberately retained as **incomplete/unverified** and is not
counted. `round-4-reference-retry` succeeded independently, but none of these
exploratory trials form part of the final exact-reference A/B.

`validation/` includes native 35-pass Rust tests, T-187 183-pass X11 parity,
T-197 9-pass callback integrity, T-196 99-pass release/history parity,
T-181 19-pass retention, T-186 14-pass preview, T-188–T-195 focused
native regressions (all independently zero-exit), Atlas T-148 43-pass
native history, 24 Python unittest passes and pinned Ruff/ty. Ticket-store
validation checks all 197 ticket records and dependency/manual-review gates.
No physical owner, Windows portability, or full native-transition signoff.

## Remaining T-197 work

Diagnose and improve the residual frame pacing and first-preview tails with
reproducible source-exact tests. The 250/200ms thresholds must be evaluated
using a sufficiently large, explicitly defined sample and release/held-stroke
metrics, without changing the approved manual-review gates T-095, T-105,
T-148/T-149 or consolidation T-151/T-152.

The additional headless native integration (32 checks) and Drawing native
store contract (312 checks) exited 0. Standalone smoke and T-182 preset
controls also exited 0 and printed their success markers, **but emitted
nonfatal Godot engine errors** (`Condition "p_button.is_null()" is true`)
in the headless test environment; those full logs are retained and the runs
are not presented as warning-free. The validation evidence is therefore
limited to process exits and checked assertions, not a blanket clean stderr.
