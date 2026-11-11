# T-095 — Changed-preview stage-to-Canvas and post-draw correlation (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **State:** `In Progress`, `manual_review: true`, **not owner accepted**.

## Why and what changed

The preceding frame-phase and `frame_post_draw` histories could time the Canvas and
renderer callback, but neither identified **how long a newly changed Brush preview
waited after CPU staging** before its first Canvas `_draw` or a matched Godot
callback. Raw pending-queue age is not the same interval: a staged sample can
leave the queue while its detached preview still awaits a draw.

After a successful Brush/Eraser batch **that advances the detached preview epoch**,
`DrawingCanvas` retains the completion timestamp of the **earliest yet-unsubmitted
changed batch**. The next active-stroke Canvas draw consumes that timestamp and
records `preview_stage_completed_us` and `preview_stage_to_frame_end_us` in the
same 1,024-frame history as draw phases and input backlog. If an engine
`frame_post_draw` callback is matched to that exact frame, it additionally
records `preview_stage_to_post_draw_us`. Unmatched frames have **no callback
interval**; cursor-only and unchanged-preview draws have **no staging interval**.
Cancellation, commit, and new sessions clear an unsubmitted timestamp. Exact
lifetime submission/callback counts and maxima survive bounded history eviction.

These are **Godot CPU completion, Canvas submission and renderer callback times**.
They are not original OS device timestamps, GPU completion, scanout, display
photons or owner hardware acceptance. Multiple changes between draws share the
earliest completion witness; a frame callback may be missing or coalesced.

## Independent red/green regression and logs

On pinned Godot `4.8.beta3.official.c51ff06e8` (Linux):

- `drawing/tests/t095_preview_stage_postdraw_smoke.gd` against the previous
  staged `DrawingCanvas` exited **1** and failed **4/13** assertions. Only the
  staged test copy was changed. Reinstating the canonical source exited **0**
  and passed **22/22**, with exact `T095_PREVIEW_STAGE_POSTDRAW_PASSED` and
  strict log validation. The initial implementation run had a typed-dictionary
  test-harness assignment error; that run was rejected, corrected and rerun
  cleanly before counting it.
- The oracle covers earliest-stage preservation across batches, real changed
  preview vs cursor-only redraws, duplicate and overwritten callbacks, session
  cancellation, two lifetime maxima and two exact lifetime counts across a
  1,024-frame ring wrap, a real 60px detached Brush Canvas frame, byte-for-byte
  independent RGBA8 output and one-step Undo/Redo.
- Individually passing, strict headless neighbors: post-draw pairing **23/23**,
  frame backlog **24/24**, frame phase **19/19**, no-op redraw **24/24**,
  preview-index reuse **529/529**, duplicate drain **195/195**, Brush coverage
  **32/32**, deferred staging **492/492**, mixed-edit rollback **504/504**,
  NativeHard source rollback **113/113**, Hokusai rollback **57/57**.
- Xvfb/Mesa `1280×900×24`, Godot GL compatibility: released-stroke navigation
  **48/48**, real native integration **30/30**, present-native fallback **7/7**,
  and five complete 60px/786% mouse-event strokes all exit **0**. The latter
  reported **129** changed-preview Canvas submissions, **124** matched
  callbacks, stage-to-draw p50/p95 **14.504/26.483 ms** and stage-to-callback
  p50/p95 **26.072/41.884 ms** on retained samples. Staging p95 **194.989 ms**
  and release-to-commit p95 **59.636 ms**. This is **one software-renderer run**,
  not a before/after latency speedup.
- Fresh standalone Drawing with both the native library **and its descriptor**
  removed: editor import exited **0** with no script/runtime errors, the new
  test passed **22/22** and native-absent fallback **7/7**, both exit 0. An
  initial standalone attempt removed only the binary, leaving expected
  extension-load errors; it is **not** counted as a clean import.

The on-demand `.github/workflows/godot-native-t095-brush.yml` runs the new
oracle through the fail-closed `check_godot_model_log.py` and preserves
`/tmp/t095-preview-stage-postdraw.log` even on failure. Required fast-CI
checks and the T-094 strict log policy are unchanged. Workflow YAML and
`tools/validate_ticket_store.py` pass locally (**96 tickets**).

## Still open

The owner-reported approximately minute-long 60px Brush lag has **not** been
reproduced or accepted on the physical device. Owner reference GPU/driver,
true input-to-photon measurements, hosted GitHub Actions, and explicit manual
review approval remain open. **T-095 stays In Progress**; **T-096 remains
independently in Manual Review**. No remote push or merge is implied.
