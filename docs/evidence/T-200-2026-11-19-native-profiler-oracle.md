# T-200 — Repair historical profiling oracles against Hokusai-native painting

**2026-11-19.** This is a **test correctness** milestone only. Application
Canvas/GDExtension sources, stroke scheduling, persistent tile state and source
file formats are unchanged. The confirmed regression environment is the
uploaded offline toolchain, Godot `4.8.beta3.official.c51ff06e8`, X11 via
`xvfb-run`, Mesa/llvmpipe and the native Hokusai extension.

## Failure witnessed before this change

T-199 retained two genuine failing graphical exits:
[`t095_frame_post_draw_pairing_smoke`](T-199-2026-11-19-validation/t095_frame_post_draw_pairing_smoke.txt)
(23 checks, 1 failure) and
[`t095_frame_phase_window_smoke`](T-199-2026-11-19-validation/t095_frame_phase_window_smoke.txt)
(19 checks, 1 failure). Both asserted equality between current native
Hokusai and the older `DrawingEditSession.paint_path` rasterizer. Re-running
neighboring tests during T-200 revealed two additional baseline failures:
[`t095_frame_input_backlog_smoke`](T-200-2026-11-19-validation/t095_frame_input_backlog_smoke.txt)
(24 checks, 1 failure from the same obsolete oracle) and
[`t095_preview_stage_postdraw_smoke`](T-200-2026-11-19-validation/t095_preview_stage_postdraw_smoke.txt)
(22 checks, 3 failures: obsolete oracle and a manually called renderer
callback that had not been matched to an actual changed Canvas frame).
Do not interpret an old-vs-native pixel mismatch as a loss of native source
integrity or a profiler regression. Conversely, these two kinds of paint
are **not** expected to produce identical RGBA8 after T-153.

## Replacement coverage

`drawing/tests/t200_native_stroke_reference.gd` creates a separate native
Hokusai stroke on an invisible Canvas. It is rooted (so Godot/native setup
remains real) but has no rendering/postdraw callback connection. It uses
source-space points, preset `hard`, identical width, color and explicit
press/release receipt stamps, runs the normal native atomic edit, and renders
committed RGBA8 through the standard DrawingRenderer. Failed native start,
failed publication, missing history or rejected rendering fail closed.

Each live profiling smoke now requires its visible native stroke to modify
source pixels, match every RGBA8 byte to its hidden/callback-free native
control, and survive exact Undo/Redo. The callback-pairing test also requires
its native comparator to detect a changed pigment; the frame-phase test
requires it to detect a changed brush width. These controls ensure the
comparison is capable of rejecting nonidentical strokes, not merely accepting
empty/identical placeholder buffers.

The preview-stage test no longer manually invokes `_on_frame_post_draw` after
one unrelated `process_frame`. It stages a real changing 60px Brush stroke
and waits for a **matched changed-preview Canvas frame and real engine
postdraw callback** (max 45 frame events), then checks both the live and
completed timing fields before comparing native source. Existing synthetic
stale/missing callback, bounded-ring, chronology, input-backlog and exact
history assertions are preserved. No production code changed.

## Validation and process exits

For each graphical test, invoked three separate processes:

```
GODOT_SILENCE_ROOT_WARNING=1 timeout 70 xvfb-run -a \
  /mnt/data/toolchain/bin/godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/<test>.gd
```

Raw captured stdout/stderr for all 12 processes and a per-process
`EXIT_STATUS=0` witness are retained in
[`T-200-2026-11-19-validation/`](T-200-2026-11-19-validation/).

| Graphical script | Checks per run | 3 runs | Result |
| --- | ---: | ---: | --- |
| `t095_frame_post_draw_pairing_smoke` | 23 | 3/3 | Pass |
| `t095_frame_phase_window_smoke` | 19 | 3/3 | Pass |
| `t095_frame_input_backlog_smoke` | 23 | 3/3 | Pass |
| `t095_preview_stage_postdraw_smoke` | 21 | 3/3 | Pass |
| **Total** | **86** | **12/12** | **258 checks passed** |

Other independent validations (zero-exit observed and outputs preserved under
`T-200-2026-11-19-validation/`):

- `t197_first_preview_callback`: **9/9**; `t187_direct_native_preview`:
  **183/183**; `t196_release_deferred`: **99/99** (native X11).
- Native Drawing `native_brush_integration`: **32/32**; native tile
  contract: **312/312**; Atlas native history: **43/43** (headless).
- Native Rust: `cargo test --locked --offline --target x86_64-unknown-linux-gnu`
  with supplied vendored Rust toolchain: **35 passed**.
- `make python-test`: **36 passed**; pinned offline Ruff `0.17.5` and
  ty `0.0.104`: both passed.
- `python3 tools/validate_ticket_store.py`: **200 validated**, including
  dependencies and manual-review gates; `git diff --check`: passed.

The only engine output in the four final graphical test classes is an
X11/llvmpipe VSync warning. No timing/FPS/p95 improvement, physical scanout,
Windows/export success or full remote CI is claimed. A mirrored Hokusai
control can test whether profiling changes native Brush pixels, but **cannot
serve as a separate implementation of the artistic brush oracle**. T-095
remains In Progress with its T-152 dependency and owner manual approval open;
T-197 retains its 200ms and physical frame-pacing gates.
