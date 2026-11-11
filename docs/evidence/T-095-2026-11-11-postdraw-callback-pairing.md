# T-095 — Correlate actual Canvas draws with Godot post-draw callbacks (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **State:** `In Progress`, `manual_review: true` (no owner approval).

## Issue and change

The 1,024-record `frame_phases_us` history already correlates compositor, upload,
full Canvas `_draw` CPU and outstanding input age, but `frame_post_draw` was
stored only in the mutable `last_frame_metrics`. An owner could not tell which
individual Canvas frame, if any, produced a later engine render callback.

`DrawingCanvas` now associates **only the most recently submitted active
stroke draw** with the next `RenderingServer.frame_post_draw` callback, storing
`frame_post_draw_callback_us` and nonnegative `frame_end_to_post_draw_us` in that
frame's retained record. A callback is consumed once. An unmatched earlier draw
is left unmatched if two draws precede a callback. Cancel/commit and new
stroke sessions do not acquire stale callbacks. Lifetime
`frame_post_draw_matches` and `max_frame_end_to_post_draw_us` remain exact
after the 1,024-frame ring evicts old samples; the retained percentile is
explicitly **latest-window-only**, and missing callbacks remain absent rather
than zero-delay successes. Existing CPU/backlog timing fields are unchanged.

**This is an engine callback interval, not OS input timestamps, GPU completion,
display scanout or physical input-to-photon latency.** The optional graphical
witness prints `T095_NATIVE_POSTDRAW_SUMMARY` (matched/retained/total frame
counts and p50/p95 callback delay). No timing budget or owner approval was
inferred from software-rendered results.

## Independent red/green controls

Godot `4.8.beta3.official.c51ff06e8`, local Linux. The test
`drawing/tests/t095_frame_post_draw_pairing_smoke.gd` ran against the previous
Canvas staged **only in the local Drawing test copy** and exited **1** with
**5 failures in 14 checks**, covering missing callback correlation and live
frame evidence. The updated canonical Canvas was restaged and passed **23/23**
with exit **0**, including a strict `T095_POSTDRAW_PAIR_PASSED` marker validated
by `tools/check_godot_model_log.py`. An initial false-green test harness had
an invalid typed-dictionary assignment: the fail-closed log validator rejected
it, and the harness was corrected before these verified results. The final
test covers:

- Exact callback-to-submit association, out-of-order clock clamp, single-use
  callback consumption, and unmatched earlier draws when two draws precede
  one callback.
- Stale callback after publication/cancellation cannot mutate the completed
  gesture. Over 1,024 retained frames, exact lifetime match count and worst
  delay survive eviction; retained callback timestamps remain ordered.
- A **real Canvas draw** during a 60px detached Brush gesture has a paired
  callback, and the committed metrics retain it. RGBA8 source bytes match an
  independently staged stroke, including Undo/Redo.

All **11** adjacent headless model checks exited zero with the strict expected
success markers: frame phase **19/19**, frame backlog **24/24**, no-op redraw
**24/24**, preview-index reuse **529/529**, stage-batch history, duplicate drain
**195/195**, sample-latency window, NativeHard rollback **113/113**, Hokusai
rollback **57/57**, mixed-edit rollback, and original Brush coverage **32/32**.

Graphical Xvfb/Mesa (`1280×900×24`, Godot GL compatibility) exited **0** for
released-stroke navigation **48/48**, native Brush integration **30/30**,
native fallback **7/7**, and five real mouse-event 60px strokes at 786% zoom.
That witness observed **150** matching frame callbacks among **275** Canvas
draws, matched delay p50 **13.699 ms**, p95 **19.355 ms**; stage p95
**193.828 ms** and release-to-commit p95 **62.607 ms**. Unmatched draws are
not treated as a latency value. These are *one* software-renderer run, not
before/after performance evidence.

Fresh standalone Drawing import with the extension removed: editor import
exit **0**, new oracle **23/23** with strict marker and native-absent fallback
**7/7**, all exit **0**. The on-demand T-095 workflow retains the raw test log
and uses the existing fail-closed checker. Required fast CI is unchanged.

## Open gates

Original owner-reported 60px lag on the physical GPU/input device is still
unverified and not accepted. Hosted CI was not run. **T-095 stays In Progress**
with manual review required; **T-096 stays independently in Manual Review**.
