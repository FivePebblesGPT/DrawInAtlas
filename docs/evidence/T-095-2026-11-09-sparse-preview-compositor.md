# T-095 — sparse live-preview compositor checkpoint (2026-11-09)

**Scope:** One T-095 follow-up on `sprint/2026-11-07`, building on the
unpublished Hokusai checkpoints. **Status remains `In Progress`,
`manual_review: true`.** Owner re-acceptance has not occurred. This is local
software-renderer and byte-exact correctness evidence, not physical device
input-to-photon latency evidence.

## Bottleneck and change

`DrawingRenderer._composite_raster()` previously iterated all pixels of a
128px display tile whenever an edit's detached preview patch was nonempty,
even if its canonical source chunk and the patch together had only a few
occupied pixels. That occurs at the beginning/end of native/legacy strokes,
near sparse canvas boundaries, and during small finishing marks. It also
looked up the canonical pixel **before** checking whether a dense preview
patch completely overrode it.

The renderer now uses bounded sparse iteration when a storage-tile scanline
run is at least 16px and the **combined number** of canonical source and
preview entries is at most `min(64, run_length / 2)`. Each source entry in the
run is read with preview precedence, including zero-alpha erasure; additions
present only in the preview patch are composited afterward. Each coordinate
is visited once, and alpha-zero values are skipped just as before. The
full sequential scan remains the fallback for dense patches and narrow
storage-tile runs; the dense path fetches canonical pixels only when a
preview replacement does not exist. The renderer never modifies document or
preview-owned storage. Sparse limits cap repeated dictionary walks across
scanlines.

No brush algorithm, file format, history semantics, or native-binary default
was changed. There is **no new custom/textured-brush feature**. A separate
experiment to fuse Hokusai preflight/composition into private candidate
patches was **rejected** after the same-environment test showed a worse
staging p95 (233.663ms versus the then-current 222.444ms); no fused code
is included in this checkpoint.

## Independent correctness witness

New `drawing/tests/t095_sparse_preview_smoke.gd` produces an independent
per-pixel source-over reference and compares the renderer's complete RGBA8
byte buffer, not another invocation of the same renderer. It covers:

- two sparse composited raster layers, alpha-0 hidden RGB, fully opaque and
  partly transparent RGBA8, preview-only additions and transparent erasures;
- an actual subtracted selection hole (excluded pixels must stay unchanged);
- signed 64-bit world anchors (`2147483651`, `-2147483671`), crossing a
  storage-tile Y boundary, and direct versus revision-pinned planned frames;
- no early document publication, one atomic commit, Undo and Redo;
- a 100-pixel mixed-alpha patch to force the dense fallback and explicit
  cancellation without changing the previously committed image.

The **133/133** oracle passed using pinned Godot
`4.8.beta2.official.cafc17a19` with a headless framebuffer. The on-demand
`godot-native-t095-brush.yml` workflow now stages/runs this test with the
fail-closed `check_godot_model_log.py` checker and retains its raw log.

## Same-machine controlled measurements

All numbers below were collected on the same Linux container with the pinned
Godot 4.8b2 build. The old renderer from parent commit `1d84032` was staged
**only into the standalone test project** for the control; the canonical
modified renderer was restored after the run. Raw runs are command-output
witnesses; not a statistically representative physical GPU test.

**Targeted CPU compositor witness:** a 128×128 render of the same two-layer,
sparse, detached-preview document at the signed anchors above, 25 render
calls per run after establishing the test document. Image creation and
source/preview resolution are included; texture upload and physical frame
presentation are **not** included. The old and new renderers both pass the
same 133-check byte equality oracle.

| Build | Render median (µs) | Render p95 (µs) | Samples |
| --- | ---: | ---: | ---: |
| Original renderer, controlled re-stage | 2611 | 2854 | 25 |
| Sparse-aware renderer, run A | 608 | 740 | 25 |
| Sparse-aware renderer, run B | 589 | 686 | 25 |

The targeted sparse case is about **4.3× faster in median CPU time** in run
A. This improvement is specific to small patches; it is **not a claim that a
full 60px Brush stroke became 4× faster**.

**Actual pointer-driven 60px Hokusai witness:** Xvfb
`1280×900×24`, Mesa llvmpipe 25.0.7-2, GL compatibility; 512×512 source,
786% zoom, five 60px Brush strokes with 120 `InputEventMouseMotion` samples
plus real press/release per stroke, four motions per frame burst. Each run
includes cold first and four warm strokes. Exactly the same test runner,
engine, native extension, and edit-session code was used for both renderers.

| Metric | Previous renderer | Sparse-aware renderer |
| --- | ---: | ---: |
| Total stroke staging p95 | 219.122 ms | 207.569 ms |
| Per-frame compositor CPU p95 | 16.710 ms | 16.562 ms |
| Release → commit p95 | 72.715 ms | 71.527 ms |
| Maximum sampled backlog | 4 | 4 |
| Test completion | `T095_NATIVE_PASSED` | `T095_NATIVE_PASSED` |

The small full-stroke differences are **within the likely run-to-run noise**
and do not demonstrate improved physical responsiveness. A same-environment
Legacy control with the new renderer stages at **175.927ms p95**, versus
Hokusai's **207.569ms p95**. Do not infer that Hokusai is now faster overall.

## Neighboring regression and packaging checks

After fresh standalone staging and Godot reimport, all selected tests exited
zero locally: hard Brush source oracle (32 checks), 114,688-pair blend oracle,
Hokusai signed-delta oracle (**126/126**), sparse-preview oracle (**133/133**),
renderer sparse plan (**74/74**), preview index, selection large, and live
stroke model; graphical native preset integration (**30/30**), post-release
navigation (**48/48**), live stroke (**125/125**), viewport cache (**153/153**),
and signed pixel boundary (**17/17**). The pixel-boundary witness still emits
known post-exit Godot resource-leak diagnostics; do **not** call that a clean
engine shutdown.

Native-present fallback passed **6/6**. In a newly created external
standalone stage, removing `addons/drawing/native/` **before the first
Godot import** gave a clean headless/editor import, sparse-preview oracle
**133/133**, and graphical fallback **6/6** with `native=false`, without
engine error diagnostics. By contrast, manually removing the `.gdextension`
manifest from an **already imported** project leaves an extension entry in
Godot's `.godot` registry and produces missing-extension startup errors even
though the same 6/6 fallback assertions pass. Fresh missing-binary staging
is verified locally; shipping native binaries in other OS exports is still
unverified. The CI workflow was edited but **hosted CI was not run**.

Reproduction:

```bash
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --path drawing \
  --script res://tests/t095_sparse_preview_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' env DRAWING_BRUSH_BACKEND=Hokusai \
  /path/to/Godot_v4.8-beta2_linux.x86_64 --display-driver x11 \
  --rendering-method gl_compatibility --path drawing \
  --script res://tests/brush_latency_native.gd
```

**Unresolved:** Physical owner 60px response/input-to-photon, persistent
preview/texture upload/frame-time on actual GPU, cross-platform native export,
Hokusai-versus-Legacy total-stage headroom, hosted CI, and explicit owner
acceptance. T-095 stays **In Progress** and T-096 remains independently in
**Manual Review**. Neither PR #16 merge nor manual signoff is authorized.
