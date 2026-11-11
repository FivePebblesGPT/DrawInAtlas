# T-095 — Godot built-in profiler: 96px full-canvas Brush (2026-11-11)

**Diagnostic checkpoint only.** T-095 remains `In Progress`, `manual_review: true`; T-096 remains `Manual Review`. No production Brush/renderer/drain-budget change was made, and no owner-device, physical input-to-photon, or hosted CI acceptance is claimed.

## Reproduction and attribution

The previously committed `drawing/tests/t095_full_canvas_brush_native.gd` sends one 100-event Godot pointer-driven 96px opaque-red Brush gesture across a fresh 512×512 document. Full RGBA8 source hashes, rendered inset-corner/center samples, 100 receipts, one revision and Undo/Redo are checked. The test now logs cumulative **commit, compositor, texture, preview-frame, staged-segment and drain** counters in addition to its existing staging and elapsed times. It also avoids shadowing the GDScript built-in `hash` function in its SHA-256 oracle.

Host: Godot `4.8.beta3.official.c51ff06e8`, Linux Xvfb 1280×900×24, Mesa 25.0.7 llvmpipe, OpenGL compatibility, Dummy audio. To capture Godot's **built-in GDScript function profiler** in its CLI debugger output:

```sh
xvfb-run -a -s '-screen 0 1280x900x24' \
  godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --profiling --debug --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd
```

`--profiling --debug` emitted `BEGIN PROFILING` and per-frame function breakdowns with file/line, inclusive/self time and call count. The profiler adds overhead and the emitted frame snapshots are **not a complete accounting of every elapsed frame**. The heavy functions it exposed include `DrawingRenderer._composite_raster()`, `DrawingEditSession._stage_brush_tile()`, `DrawingDocument._publish_edit()` and `DrawingEditSession.commit()`; the instrumented gesture counters below quantify the full stroke phases independently.

## Measured phase totals (not physical latency)

Each line below is one **cold process**, not enough samples to establish a distribution. Times are milliseconds, rounded from actual tool output. Only the last two columns for the drain-budget experiment are deliberately paired on the same source snapshot and host. The 30ms variant was made **only in a temporary standalone staged copy** and restored byte-for-byte after testing; it must not be shipped as a responsiveness fix.

| Mode | Pointer-start → Godot post-draw | Release → commit | Staging CPU | Commit CPU | Compositor CPU | Texture CPU | Drain frames | Peak drain-call CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Legacy, original 6ms budget, first unprofiled run | 9,348.182 | 9,186.500 | 1,500.687 | not emitted | not emitted | not emitted | 166 | not emitted |
| Legacy, `--profiling --debug` (instrumented overhead) | 10,995.988 | 10,802.687 | 1,773.132 | not emitted | not emitted | not emitted | 177 | not emitted |
| Legacy, original 6ms budget, detailed unprofiled run | **9,222.331** | **9,056.946** | **1,423.290** | **1,578.058** | **4,874.646** | **85.767** | **161** | **20.090** |
| NativeHard, original 6ms budget, real local GDExtension | 8,455.913 | 8,274.409 | 1,285.517 | not emitted | not emitted | not emitted | 156 | not emitted |
| NativeHard, original 6ms budget, detailed unprofiled run | **8,010.987** | **7,872.248** | **1,300.522** | **1,475.740** | **4,118.730** | **55.503** | **154** | **20.207** |
| Legacy, staged-only 30ms soft budget | **4,718.860** | **4,572.680** | **1,312.250** | **1,579.349** | **1,363.862** | **23.082** | **39** | **37.950** |

All listed graphical runs exited 0 with `T095_FULL_CANVAS_PASSED` and byte-exact full-red correctness. The existing 60px independent source oracle passed 32/32 and the actual GDExtension NativeHard source-rollback oracle printed `T095_NATIVE_HARD_SOURCE_ATOMIC_PASSED`, with the exact strict markers checked against raw logs and process exit codes. The 96-ticket workflow validator also passed. NativeHard used a Rust `--offline --locked --release` build against the pinned toolchain and successful cold Godot import. The canonical 6ms budget remains unchanged.

**Interpretation:** on the 6ms test, the accumulated preview compositor was the biggest measured CPU component (~4.87s), with ~1.58s commit publication and ~1.42s staging. The 100-event path was split into 296 bounded segments and consumed 161 preview frames. Because stage batches can exceed the soft 6ms deadline, the observed maximum drain-call CPU was ~20ms. Raising the soft deadline to 30ms cut preview recompositions and wall time, but also raised the worst drain-call CPU to ~38ms, risking unacceptable held-input stutter. Importantly, even with fewer preview frames, **staging and publication themselves each exceed 1 second** on this software host; neither changing the budget nor swapping to NativeHard can meet the proposed 100ms target.

**Next actual implementation bottlenecks to investigate:** incremental preview composition instead of rebuilding already-composited pixels on each changed generation; a tile-local atomic publication path instead of hundreds of thousands of per-pixel coordinate-key operations; and reducing GDScript per-pixel Brush staging overhead. Preserve held-button live preview, post-release pan/zoom ownership, byte-exact brush/mask/eraser semantics, and one Undo transaction. Do not turn the 30ms staged-only experiment into a production change without explicit frame-time and interaction evidence.

## Verification boundaries

The original test remains the strict on-demand T-095 **correctness** check; the `T095_FULL_CANVAS_P95_BUDGET_MS=100` performance gate remains opt-in for designated reference hardware. Neither these figures nor `RenderingServer.frame_post_draw` measure physical sensor-to-photon latency, or establish Krita/PhotoCraft speed ratios. No required fast-CI check IDs or T-094 log policy changed. Owner still needs real-device timing and explicit acceptance.
