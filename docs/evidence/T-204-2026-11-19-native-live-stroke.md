# T-204 — restore T-085 native live-stroke regression fixtures

**Date:** 2026-11-19. **Source:** PR #21 local branch on top of
`c437a41d`, remote PR head `9aa1cbe0`. Godot `4.8.beta3.official.c51ff06e8`,
Linux x86-64, the supplied offline Rust/Hokusai extension, and Xvfb/Mesa
llvmpipe for framebuffer tests. No remote CI, Windows or real pointing device
was exercised.

## Fail-first and root causes

| Attempt | Exit | Observed failure |
| --- | --- | --- |
| Original T-085 headless model | 1 | `T085_MODEL: 77 checks; 8 failed`: three direct-Legacy-to-Hokusai queue byte comparisons, plus five no-change narrow/stationary mask/Eraser assertions |
| Original T-085 native X11 | Unconfirmed after a bounded interrupted run | Three initial stationary-dab assertions failed, followed by a GDScript `String` constructor error at the layer-switch fixture. No final native marker was emitted. |
| Initial updated native comparison | 1 | 11/134 assertions failed: invalid layer creation inside active native transaction; and nine native reference mismatches from reconstructed, not actually routed, synthetic source samples |

The original X11 test tried to create a new layer **while a Rust stroke
transaction was active**. The failed create result had no layer ID, leading
to an invalid `String(...)` conversion and an unhandled script error rather
than exercising the intended layer-switch cancellation. The replacement layer
now exists before the pending stroke; the fixture switches to its valid ID
while the stroke is open.

`root.push_input`'s routed pointer positions were not always byte-for-byte
equal to `source_position(pixel_to_position(synthetic_target))`, especially
at 50% and 25% zoom (intermediate diagnostics found 365/424/464 differing
motion samples respectively). The native comparison must use the **actual
sample buffers accepted by Canvas** and the actual release endpoint, rather
than an idealized reconstruction. The per-event input counter is checked
before reading those buffers, so missing or duplicate routed events fail
explicitly. The full synthetic target series and endpoint/source-pixel
assertions remain independently checked.

The old single-call `DrawingEditSession.paint_path` used the retired
non-Hokusai Brush raster algorithm. It cannot be an exact native Brush
pixel oracle. Both T-085 suites now replay **identical input source positions
and receipt timestamps through an independent Hokusai transaction with no
Canvas renderer/frame callbacks**. The headless test additionally verifies
that changing the reference brush width changes its source RGBA8, so the
comparison would detect a real divergence. Historical explicit
`paint_path` tests of the edit-session API remain intact.

Selection holes, inverted/deny-all masks, selection-change cancellation,
Eraser cancellation, nonpublication before release, crossing/loop coverage,
process-global input restoration, one-step native Undo and live framebuffer
readback are not relaxed. Native mask strokes now use real pixel-changing
width/motion rather than assuming a 1px stationary initial dab must paint.
No production Canvas, Rust, renderer or persistence source changed.

## Repeated final test results

Commands use `GODOT_SILENCE_ROOT_WARNING=1` and the immutable supplied Godot
binary; X11 commands additionally specify
`xvfb-run -a --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy`.

| Test | Zero exits | Result |
| --- | ---: | --- |
| `--headless --path drawing --script res://tests/live_stroke_smoke.gd` | 4/4 | `T085_MODEL: 81 checks; 0 failed` on each |
| X11 `--path drawing --script res://tests/live_stroke_native.gd` | 4/4 | `T085_NATIVE: 144 checks; 0 failed` on each |
| T-087 image-frame headless | 1/1 | 82/82 |
| T-087 image-frame X11 | 1/1 | 104/104 |
| T-095 frame-backlog headless | 1/1 | Pass |
| T-187 native preview X11 | 1/1 | 183/183 |
| T-197 first-preview X11 | 1/1 | 9/9 |
| Native Drawing integration headless | 1/1 | 32/32 |
| Native tile contract headless | 1/1 | 312/312 |
| Offline Rust (`tools/build_native_brush.sh --test`) | 1/1 | 35/35 |
| `make python-test` | 1/1 | 56/56 |
| Offline Ruff / ty | 1/1 each | Both pass |
| Explicit GDScript type audit | 1/1 | 520 project scripts, 33 skill documents |
| T-085 strict CI model log parser | 1/1 | Accepted `T085_MODEL_PASSED` |
| `tools/validate_ticket_store.py` | 1/1 | 204 tickets, dependency and review gates validated |

Every native-X11 final run contains **nine 840-point burst trials** (three
trials at each zoom 1.0/0.5/0.25), with exact native source parity and
one-step Undo. The software-frame callback percentile and long-burst
release-to-commit numbers logged by the test are **synthetic-local CPU
observations**; they do not prove 200ms p95, sustained 12/60 FPS, OS
mouse-to-photon latency or physical-device responsiveness. The independent
native control uses the **same brush implementation**; it checks queue and
instrumentation equivalence, not artistic correctness of the preset.

**Neighboring known failure:** `t130_pending_source_context_smoke.gd`
returned **exit 1** with `T130_CONTEXT_FAILED checks=34 failures=1`
(`Deselect cannot invalidate source on later frame`). This pre-existing
failure was already recorded under T-203; it is explicitly out of scope.
No hosted GitHub CI was run on the unpushed patch. The T-149 architecture
and T-085 owner Linux/Windows physical input-to-preview acceptance stay
open, as do T-106/T-180 CI/portability gates. No owner signoff was assumed.

All captured stdout/stderr, source/native-binary hashes and observed process
exits are in [byte-preserved raw evidence](T-204-2026-11-19-native-live-stroke-raw/).
The first baseline X11 run has **no confirmed process exit** and is not
counted as a completed passing or failing suite; a later partial fixture
with an explicit nonzero exit is retained separately. `git diff --check`
passes for the final changes.
