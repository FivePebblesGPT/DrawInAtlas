# T-095 — 96px full-canvas red Brush pointer benchmark (2026-11-11)

**Engineering and comparative diagnostic; not a performance acceptance.** T-095 stays
`In Progress`, `manual_review: true`. This one-ticket checkpoint adds a real
Godot graphical pointer-driven integration witness and a repeatable proposed
100ms *rapid-input → post-draw callback* budget. It neither adds a fill shortcut
nor asserts that Godot engine callbacks are physical input-to-photon.

## Workload and independent correctness

- Godot 4.8.beta3, 512×512 new single raster layer, 96px hard Brush, opaque
  straight red `0xff0000ff`, clipping enabled, 1× zoom and fully visible canvas.
- One 100-event rapid pointer gesture: down, 98 motions, up, following nine
  alternating horizontal sweeps with source-space Y separation at most 64px.
  Every pixel center is at most 32px from a horizontal sweep, less than the
  48px Brush radius. This represents roughly 262,144 source pixels, **not**
  nine `fill_rect` calls. All input goes through `SceneTree.root.push_input` and
  the real `DrawingCanvas` brush / queue / detached compositor / commit path.
- Each test asserts one document revision, exact input receipt count, queue
  drain, full source coverage via the independent SHA-256 of four 256×256
  opaque-red RGBA8 tiles, real software framebuffer red center plus inset
  corners, one-step Undo and Redo, and unchanged input-accumulation state.
  `ff 00 00 ff` repeated 65,536 times has SHA-256
  `b8b9b478324141d9331328a2150e74ec5feb266a743a51cab73d903247247ea4`.
- Capture a timestamp before the virtual pointer down and after a completed
  engine `RenderingServer.frame_post_draw` callback. Record separate
  release→commit, staging CPU, pending samples and draining frames. The rapid
  event burst models maximum throughput, *not* a human-paced held gesture.
  Physical OS pointer latency, display scanout and owner subjective feedback
  are not captured. Existing held-preview tests remain separate.

`drawing/tests/t095_full_canvas_brush_native.gd` defaults to one complete
new-document run, avoiding CI-host resource amplification. For repeated runs,
execute several independent processes; an optional `T095_FULL_CANVAS_RUNS` of
1–3 is also supported. On designated owner/reference hardware only, set
`T095_FULL_CANVAS_P95_BUDGET_MS=100` to make exceeding the **proposed** budget
fail with a nonzero exit. Default on-demand Xvfb CI checks correctness and
always reports `target_met`, without claiming software timing is hardware
acceptance. Other backends can be selected using `DRAWING_BRUSH_BACKEND`; an
unavailable requested NativeHard must fail, not silently fall back.

## Same-host Godot measurements, Legacy backend

Linux Xvfb 1280×900×24, Mesa llvmpipe 25.0.7, Godot
`4.8.beta3.official.c51ff06e8`, `gl_compatibility`, dummy audio.
Runs are **separate processes** (cold document and new app each time):

| Run | virtual pointer-down→engine post-draw | release→commit | stage CPU | drain frames | max pending |
|---|---:|---:|---:|---:|---:|
| 1 | 11,377.688ms | 11,227.825ms | 1,835.577ms | 164 | 99 |
| 2 | 9,771.557ms | 9,619.046ms | 1,533.193ms | 165 | 99 |
| 3 | 8,942.746ms | 8,800.451ms | 1,428.450ms | 163 | 99 |
| p50 / nearest-rank p95 | 9,771.557 / **11,377.688ms** | 9,619.046 / 11,227.825ms | — | — | — |

All three final-version tests exited 0 and printed the strict `T095_FULL_CANVAS_PASSED`
marker; every source tile and framebuffer sample passed. The opt-in 100ms
budget produced the expected exit 1, with an explicit budget failure, while
independent 60px source oracle passed 32/32. A queue of ~99 samples and ~160
frames to complete a single virtual gesture is compelling evidence that the
whole-input pipeline, not just the scalar paint loop, needs investigation.
These runs provide **no real-owner-device acceptance**, and show that the
proposed 100ms goal is **not achieved** by Legacy under llvmpipe.

## PhotoCraft software-renderer comparison (context, NOT identical timing)

From the user-supplied pinned toolbox, PhotoCraft 0.21.0's local control
bridge (`photocraft --control`, `photocraft-cli mcp --bridge`) was run on
**the same Xvfb/llvmpipe host** using its CPU renderer. A fresh transparent
512×512 document, hard round Brush at size 96px and opacity/hardness 1, opaque
`#ff0000`, and the same 100-event document-coordinate serpentine path were
sent via one `ui_pointer` MCP call per run. The exported PNG was read back
with Pillow: all 262,144 pixels were exactly `(255,0,0,255)` including the
four corners; no fill command was used.

| Run | PhotoCraft internal stroke-trace CPU time | Total MCP pointer call elapsed |
|---|---:|---:|
| 1 | 78.62ms | 125.129ms |
| 2 | 88.78ms | 157.736ms |
| 3 | 79.05ms | 153.583ms |
| p50 / nearest-rank p95 | 79.05 / **88.78ms** | 153.583 / **157.736ms** |

**Crucial caveat:** PhotoCraft's `stroke_trace` reports *internal stroke work*,
not its input-to-frame-post-draw latency. The MCP round trip includes tool
transport/UI dispatch but not a guaranteed display scanout. The Godot total
includes input injection, queue drain and an engine post-draw callback.
PhotoCraft's document-coordinate UI bridge and Godot's Godot-event injection
are not the same operating-system pointer interface. The brush implementations,
blend edges, screen scaling and rendering engines also differ. Therefore the
numbers are **not** a valid speedup ratio, despite the large diagnostic gap.
This is evidence for prioritizing the production pipeline, not owner acceptance.

## Run and remaining gates

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
xvfb-run -a -s '-screen 0 1280x900x24' \
  godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd
# On owner reference hardware ONLY, set T095_FULL_CANVAS_P95_BUDGET_MS=100.
```

The on-demand `godot-native-t095-brush.yml` workflow checks the exact marker
with T-094's existing fail-closed verifier and retains the raw log under
`if: always()`. It does not alter the required fast-CI check set, manual
review gate, or T-096 state. Hosted run of this new workflow, actual owner
hardware and physical device-to-photon measurements are outstanding. Existing
PR #17 fast-desktop CI is separately red on other checks; this checkpoint
does not attempt to change T-068/T-094 or unrelated ticket baselines.
