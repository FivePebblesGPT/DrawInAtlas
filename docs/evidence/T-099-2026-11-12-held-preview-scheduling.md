# T-099 — bounded held-preview redraw scheduling (2026-11-12)

**Baseline remote ref:** `sprint/2026-11-11` at `79b8959e9eac01b3bb10a144a46407acc6901aed` (T-098). **Engine:** `4.8.beta3.official.c51ff06e8`, Xvfb 1280×900×24, Mesa llvmpipe GL compatibility, Dummy audio. **Source:** `addons/drawing/canvas.gd` SHA-256 `d25be8d25480efde76ad3f8a884c9c9695f756ad296d3feabb885bf84d0947e4` (candidate); Git blob `b2f8ebe0f482ddc9a8643dd3a3391a87d46ce0fa`.

## Scheduling change and negative-control policy

The old source recomposed the detached preview after every pixel-changing drain call, giving 158–160 changed redraws for 296 raster segments from 100 Godot mouse events. Its budget was already soft, checked only between atomic `paint_path` calls, so a staged-only 30ms budget or changing 24px interpolation into longer/merged raster batches risks long held input stalls. Trial 36/48px interpolation and two-segment *atomic* batching were rejected after observing 65–146ms single-call spikes despite lower total wall time; **none** of those staging changes is in this patch.

The production candidate keeps the original per-call work and 6ms budget byte-for-byte. When a backlog is still present it defers one queued preview redraw, never more than two *separate* drain calls or 20ms of monotonic Godot time after the first changed call. The first stationary dab and the last changed held sample are immediately scheduled; a paused capture cannot starve. A Canvas submission tags the earliest changed input/stage; drawing, commit, rollback and cancellation clear pending state. No input positions are skipped, interpolated in a different coordinate space, or changed in order.

The new optional `T099_MAX_PREVIEW_FRAMES=110` oracle runs **the existing real 100-event pointer test**. Reverting only Canvas to remote T-098 source while retaining the new test gave exit **1** (`T095_FULL_CANVAS_FAILED: ... at most 110 ... (got 160)`), with the full red source and the other assertions still passing. The candidate returned exit **0**, strict single marker `T095_FULL_CANVAS_PASSED`. This threshold is a narrow scheduling regression, **not** a 100ms hardware speed gate.

## Paired cold/warm software measurements

Each pair used the exact same test code, with just the original Canvas versus candidate Canvas staged into the isolated standalone Drawing app. Each separate engine process drew a cold stroke (index 0) and a warm second stroke (index 1). Every line had `T095_FULL_CANVAS_PASSED`, exact four 256px red source-tile SHA-256 digests, five red framebuffer samples, 100 accounted pointer samples, one document revision, one Undo and Redo. **No event dropping**: `segments_staged=296` in all eight runs. Times in milliseconds; engine-receipt timing is not physical input-to-photon.

| Pair / index | Variant | Whole stroke | Release→commit | Changed previews | Compositor CPU | Input→draw p50 / p95 / max | Input→postdraw p95 | Queue depth p95 / max | Oldest queue age p95 | Drain calls / max CPU |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | ---: | --- |
| 1 / cold | T-098 | 5386.3 | 5258.1 | 159 | 1360.2 | 1914 / 3730 / 3878 | 3738 | 93 / 99 | 3730 | 161 / 18.9 |
| 1 / cold | T-099 | 5294.4 | 5160.8 | 81 | 890.3 | 1764 / 3554 / 3775 | 3560 | 92 / 99 | 3554 | 164 / **76.6** |
| 1 / warm | T-098 | 5031.2 | 4884.5 | 158 | 1360.9 | 1790 / 3541 / 3704 | 3546 | 93 / 99 | 3541 | 160 / 11.4 |
| 1 / warm | T-099 | 4691.8 | 4548.1 | 79 | 877.4 | 1602 / 3148 / 3276 | 3155 | 93 / 99 | 3148 | 159 / 16.5 |
| 2 / cold | T-098 | 5843.3 | 5698.9 | 160 | 1484.8 | 2018 / 4026 / 4247 | 4074 | 92 / 99 | 4026 | 162 / 22.6 |
| 2 / cold | T-099 | 4899.9 | 4763.6 | 79 | 821.6 | 1555 / 3112 / 3251 | 3118 | 94 / 99 | 3112 | 159 / 13.7 |
| 2 / warm | T-098 | 5496.8 | 5350.9 | 160 | 1502.2 | 2257 / 4087 / 4259 | 4116 | 93 / 99 | 4087 | 162 / 18.0 |
| 2 / warm | T-099 | 4159.3 | 4022.5 | 79 | 763.7 | 1473 / 2853 / 2970 | 2860 | 93 / 99 | 2853 | 160 / 10.6 |

Preview cost improvement is the relevant controlled change: total CPU composition fell ~35–49%, with about half the dirty preview frames. **Drain calls did not fall** (159–164 versus 160–162): the ticket improves render scheduling/backlog wall time, not input raster throughput. The one 76.6ms candidate-stage outlier must not be hidden: no code path enlarged its atomic work, and the fixed 6ms deadline cannot preempt an in-progress `paint_path`. The paired samples do **not** statistically establish a strict maximum frame time or hardware responsiveness. The release→commit CPU cost remains dominated by staging and sparse publication (T-100).

## Tests, commands, exit codes and raw-log provenance

```sh
# From the repository root, after copying the pinned Godot binary to $GODOT:
python3 tools/build_drawing_app.py --in-place
$GODOT --headless --audio-driver Dummy --editor --path drawing --import --quit
# Baseline: temporarily stage Canvas bytes from remote 79b8959e; restore the candidate after runs.
T095_FULL_CANVAS_RUNS=2 timeout 120s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/t095_full_canvas_brush_native.gd
# Candidate: same command, with opt-in scheduling oracle:
T095_FULL_CANVAS_RUNS=2 T099_MAX_PREVIEW_FRAMES=110 timeout 120s xvfb-run -a \
  -s '-screen 0 1280x900x24' "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd
# Additional real pointer source/navigational witness:
timeout 100s xvfb-run -a -s '-screen 0 1280x900x24' "$GODOT" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/t099_preview_schedule_native.gd
# Every test checks its exact marker through T-094's fail-closed log checker:
python3 tools/check_godot_model_log.py RAW_LOG --marker T095_FULL_CANVAS_PASSED
python3 tools/check_godot_model_log.py RAW_LOG --marker T099_PREVIEW_SCHEDULE_PASSED
```

- Two baseline paired processes, two candidate paired processes: **0/0** process/verifier exit codes each, all 8 mouse strokes pass. Red-control baseline with `T099_MAX_PREVIEW_FRAMES=110`: process exit **1**, required assertion fails as intended. Separate changed-preview control was exercised without weakening the source/Undo oracle.
- T-099 held X11 input test: **0/0**, **46 checks**, `Brush` and `Eraser` (each 61 actual mouse events) paint through signed source-tile boundaries and a selection hole; both retain 4 held preview frames, queue source positions across release→pan/zoom and compare unsliced oracle RGBA8 with Undo/Redo. The held zoom-cancel control also verifies rollback and input owner restoration. Log SHA-256: `3387b0a2164874caa45a511ce252f0db8ee273a44924843de5ea580be8030b9f`.
- Existing headless strict passes (all **0/0**): `t095_preview_stage_postdraw_smoke`, `t095_preview_input_postdraw_smoke`, `t095_frame_post_draw_pairing_smoke`, `t095_input_queue_compaction_smoke`, `t095_frame_input_backlog_smoke`, `t098_preview_display_cache_smoke` (the latter also runs graphically in its on-demand CI step).
- Additional headless strict passes (**0/0**): `t095_duplicate_drain_batch_smoke`, `t095_latency_window_smoke`, `t095_stage_batch_window_smoke` and `t095_owner_trace_smoke`. The native-absent fallback test `native_brush_fallback.gd` exited **0** (no marker is emitted by that standalone witness). Graphical `stroke_navigation_native.gd` exited **0** with **48/48** checks, and `brush_latency_native.gd` exited **0** with `T095_NATIVE_PASSED`. These are independent from a real NativeHard/Hokusai extension load, which was **not** recompiled for this ticket.
- Paired raw-log SHA-256s (baseline 1/2 then candidate 1/2): `01d8d2647b3c65d5a69afdb6747aad927f860f3176c7d3fa279fc823343fcba7`, `e0df2c1996f7fa59006ed3518a0aebb1616dca3bb53839fd875ef66ee9bfcba2`, `af0e8a7770c5aa8a0cf4fdea091690f2506b507b8d6adbf72be106f98a05c460`, `637002fe6198e8ca50602227214cee5ba8d642799006d7bdca31ba8944ac32b0`. Red-control log SHA-256: `782389a9528a19064800b1598fc6428c80803d899c60f545738797b4e578473c`.

## Gates not claimed

The fast 46-check required workflow was **not replayed in full**, nor were hosted on-demand Actions results or physical Linux/Windows owner timing accepted. The previously queued run outcomes on T-098 were unverified. T-095 remains **In Progress, `manual_review: true`**, and T-096 remains **Manual Review**; neither receives implied owner approval. T-100 sparse publication and T-101 optional native performance are independent open deliverables. No raw-budget increase, fixed hardware speed threshold, new ticket dependency or additional fast-CI step was introduced.
