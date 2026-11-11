# T-095 — input receipt to changed-preview Canvas/callback correlation (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **Status:** `In Progress`, `manual_review: true`; no owner hardware approval.

## What changed and what it measures

The prior bounded frame history measured staging completion → Canvas draw and (when matched) → `RenderingServer.frame_post_draw`, but did not connect a *received source pointer sample* to the corresponding changed preview. The gesture can be CPU-staged while the queue ages, so that gap matters for the owner's reported 60px brush catch-up delay.

Each successful pixel-changing `DrawingCanvas._drain_segments()` batch now retains the **earliest Godot-received source sample timestamp in that batch**. Until the next changed-preview draw, the first changed batch keeps its timestamp even if subsequent batches complete. The matching active-stroke Canvas frame stores `preview_input_received_us` and `preview_input_to_frame_end_us`; only if a real `frame_post_draw` callback matches that frame does it store `preview_input_to_post_draw_us`. Lifetime maxima and exact callback counts survive the latest-1024-frame ring, including eviction of the worst frame. No-op draws, cancelled sessions, unmatched and duplicate callbacks receive no fabricated receipt→callback interval. Cancellation, commit and new gesture reset pending receipts; the previous stage→draw/callback metrics are preserved.

**Interpretation:** these are **Godot input-receipt / CPU staging / Canvas draw / rendering callback** observations. A batch may include masked, already-covered, or duplicate samples; its *earliest* receipt is a conservative batch-age witness, **not proof that exact sample changed a pixel**. Timestamps are not kernel or device event timestamps. `frame_post_draw` is not scanout or photons. Coalesced callbacks remain unmatched for older frames. No physical input-to-photon or responsiveness improvement is claimed.

## Independent red/green verification

Pinned `Godot 4.8.beta3.official.c51ff06e8` with the actual staged canonical addon:

- `drawing/tests/t095_preview_input_postdraw_smoke.gd`: **22/22** assertions pass, process exit 0, exact `T095_PREVIEW_INPUT_POSTDRAW_PASSED` marker and `tools/check_godot_model_log.py` strict validation. Covers earliest receipt across changed batches, receipt/stage/draw/postdraw ordering, no-op frames, double/coalesced callbacks, cancellation, 1,024-frame rollover with lifetime maxima, real 60px Brush Canvas draw, independent RGBA8 stroke bytes, and single-step Undo/Redo.
- **Negative control:** a staged-only source with receipt recording disabled exits 1 and fails **8** assertions. Restoring canonical source passes **22/22**, exit 0 and clean strict log. No test-only source edits were committed.
- **14/14 targeted headless regressions:** receipt 22, stage→callback 22, frame callback 23, input backlog 24, frame-phase 19, no-op redraw 24, preview-index reuse 529, duplicate drain 195, input queue 31, 60px Brush coverage 32, deferred staging 492, mixed-edit rollback 504, NativeHard source rollback 113 and Hokusai rollback 57. Each exited 0 with its exact strict marker. One initial test-runner marker mismatch for `brush_coverage_smoke.gd` was corrected to its real `T095_ORACLE_PASSED` marker; the underlying 32/32 result had already exited 0.
- **Graphical Xvfb/Mesa, 1280×900×24**, native addon present: actual 60px/786% pointer witness five strokes exit 0, released-stroke navigation **48/48**, native integration **30/30**, and native-present fallback **7/7**, each exit 0. Pointer witness: 273 Canvas draw records, 128 changed-preview receipt/draw records, 123 matched receipt/callback records; receipt→draw p50/p95 **42.158/111.903 ms**, receipt→callback p50/p95 **56.485/125.007 ms**. For comparison, stage→draw p50/p95 **14.279/25.739 ms**, stage→callback p50/p95 **25.750/38.350 ms**, staging p95 **171.567 ms**, release→commit p95 **58.164 ms**. **One software renderer run; no before/after performance claim.**
- Fresh *native-absent* standalone package: removed both `.gdextension` descriptor and `.so`, performed clean editor import (exit 0 with no runtime/script errors), then the new oracle **22/22** and fallback **7/7** both exit 0.
- `docs/Index.md`, ticket, this evidence, on-demand workflow YAML and ticket-store validation updated. `tools/validate_ticket_store.py` validates **96** tickets. The on-demand workflow uses T-094's fail-closed exact success-marker check and preserves `/tmp/t095-preview-input-postdraw.log`; the **46 fast required CI check IDs** are unchanged. Hosted Actions has not been run.

## Outstanding gates

Owner's physical OS, GPU/driver, scaling and pointer-input-to-photon evidence remain unavailable; the ~one-minute catch-up report is neither reproduced nor resolved by these timings. T-095 **stays In Progress, manual review pending**, and T-096 remains independently in Manual Review. No remote push, merge, acceptance, or hardware signoff is implied.
