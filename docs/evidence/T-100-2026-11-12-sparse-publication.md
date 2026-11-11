# T-100 — bounded sparse atomic Brush publication (2026-11-12)

## Scope, source and gates

- **Last verified remote PR #17 HEAD:** `79b8959e9eac01b3bb10a144a46407acc6901aed` on `sprint/2026-11-11`; unmerged. The local pre-T-100 T-099 commit is `befefa65086ff0d96eceeaccfa3c916375608c11`. The source of `addons/drawing/document.gd` on both revisions is byte-identical (SHA-256 `ed6231894b86b68b3bce42f23ba382de194592efc0786b370da7ae2bd35ca3a1`).
- **Candidate source SHA-256s:** `document.gd` = `3651283a4e2b4a88f6a33d960b9b6cfaae739fda4ea1fcae5e99547ecf7b2618`; `delta.gd` = `ab9d3bc47fc4173f4f3265becd85a653c544118e142b66e634d2c21866980ac2`.
- **Pinned engine:** `4.8.beta3.official.c51ff06e8` (`Godot_v4.8-beta3_linux.x86_64`) under Xvfb 1280×900, Mesa/llvmpipe OpenGL 4.5, Dummy audio on Linux. The bundled Rust 1.99.1 vendor sources built the real `drawing-brush` GDExtension offline with `cargo --locked --offline --release`; native-present tests below loaded that binary. No runtime or engine source was patched.
- **Gate:** This is an isolated publication throughput improvement. **T-095 remains In Progress, `manual_review: true`**, and **T-096 remains Manual Review**. Real owner hardware and input-to-photon timing, the 100ms responsiveness goal, strict max frame stalls, hosted CI, and T-101 native throughput are **not accepted**.

## Change and atomicity

`DrawingDocument._publish_tile_edit()` still checks exact signed canonical tile identifiers, in-range integer offsets and RGBA8, expected document revision, editability, no-op pixels and **identity** of each immutable source tile. After an entire tile's patch validates, it makes a detached tile candidate, applying nonzero replacements with C++-side `Dictionary.merge(patch, true)` instead of individual GDScript `get_rgba` / `set_rgba` calls. A zero replacement **erases** the sparse key; alpha-zero colors with nonzero hidden RGB are preserved. No live chunk, history event, dirty record or revision is installed until all tiles are prepared and the revision/editability is rechecked. Failed late tiles, reentrant source issues and concurrent modifications reject atomically.

For a tile-local edit, the publisher freshly builds exclusive `Dictionary[String, int]` canonical before/after history maps. `DrawingDelta.from_owned_maps()` *transfers those internally owned maps* into the single content delta; previously `DrawingDelta.new()` duplicated each map on construction. Public `DrawingDelta.new()` continues to copy caller-provided maps, and mixed API `_publish_edit()` continues to use that defensive constructor. History still stores the full exact before/after byte values, with one Undo and Redo. No source/editor history serialization contract changes.

For the tested **262,144-pixel** stroke, this eliminates **524,288 full-map entry copies** (one duplicate of each 262,144-entry map), at least **2,097,152 bytes of logical RGBA8 value payload**, *plus* the unmeasured String key/Variant/Dictionary allocator overhead. The initial full-red canvas has no resident source pixels to clone (`source_clone_rgba8_bytes=0`); candidate creation still allocates its four RGBA8 sparse tiles, and both variants retain 524,288 canonical delta entries. These counts are **operation-level lower-bound estimates**, not allocator byte totals. Godot's monotonic static-heap high-water observations are below.

## Controlled negative/positive oracle

New `drawing/tests/t100_sparse_publication_smoke.gd` runs **197 mandatory assertions** with independent signed canonical pixel-key publishing as reference. It tests three source strides (16, non-power-of-two 30 and 256), positive/negative huge signed anchors, existing/absent chunks, alpha-zero hidden RGB, zero erasures, detached resident tile ownership, patch mutation after publication, independent layer isolation, bad late offsets and RGBA8, missing/stale source, stale revision, same-byte replaced-source identity, retry, selection-mask hole, Brush/Eraser and canceled previews, canonical history map equality, byte-for-byte preview/committed values and Undo/Redo. It also checks each of the four 256px full-red chunks against the independent SHA-256 `b8b9b478324141d9331328a2150e74ec5feb266a743a51cab73d903247247ea4` and retains one 262,144-entry canonical history step.

Both baseline and candidate pass **197/197** with the optional CPU control disabled. The diagnostic-only `T100_MAX_COMMIT_MS=1850` adds one assertion: the **original** `document.gd` / `delta.gd` source failed **1/198** on the expected performance condition at **1959.402ms**, process exit **1**, strict verifier exit **1**. The **candidate** passed **198/198** at **1131.541ms**, process exit **0**, verifier exit **0**. The source oracle itself passed on both sides, so the failure is deliberately a **performance** red control, not a manufactured correctness bug. This threshold is **never set in CI** and is not a hardware or deterministic timing gate. On the new oracle's isolated headless run, Godot `OS.get_static_memory_peak_usage()` reported **194,343,736 bytes** baseline versus **151,361,620 bytes** candidate (about 43MB lower; memory accounting is Godot-internal, not measured total process RSS).

Raw control log SHA-256s: baseline `50022d0f8f60444c67dd42ff0e9469fe72f823829040540355e29168c11d768c`; candidate `1cfd360d9863384f5133dd4d2f707298c8779d80c7c11b7d59c24f7117835231`. Normal candidate 197-check log `f54ac89431ab84cf50f33b9bdd7fb9fb8a053eb10174043ec7f744eaa37df210`.

An earlier draft used an improperly typed conditional dictionary initializer; the **fail-closed T-094 log checker correctly rejected the resulting Godot `SCRIPT ERROR` even when an older smoke printed its success marker**. That draft was discarded and is not counted as passing evidence.

## Paired 96px full-canvas real-pointer measurements

For each of two independently launched baseline processes and two candidate processes, the same `t095_full_canvas_brush_native.gd` executes two strokes (cold/warm) on new documents. The only staged source difference is the candidate `document.gd` / `delta.gd`, plus the same T-100 memory reporting in both variants. NativeHard is **not** selected in this paired Legacy comparison. All eight pointer strokes: exact 100 received mouse events, 296 staged raster segments, four SHA-256-perfect source chunks, full-red framebuffer spot checks, one revision, one Undo and Redo; exact `T095_FULL_CANVAS_PASSED` marker with process/checker **0/0** each. The T-099 optional `T099_MAX_PREVIEW_FRAMES=110` oracle also passes each stroke. Software screen callbacks are not physical photons.

| Pair / phase | Variant | Publication CPU ms | Total-to-postdraw ms | Release-to-commit ms | Preview draws | Max raster drain ms | Godot peak static memory after stroke (MB, decimal) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 / cold | baseline | 1380.8 | 4956.4 | 4773.2 | 81 | 14.1 | 226.0 |
| 1 / cold | candidate | 1234.0 | 5810.5 | 5547.0 | 83 | 18.6 | 183.0 |
| 1 / warm | baseline | 1303.8 | 5168.2 | 4983.7 | 81 | 15.1 | 232.0 |
| 1 / warm | candidate | 886.2 | 4840.6 | 4720.5 | 83 | **38.5** | 193.6 |
| 2 / cold | baseline | 1465.3 | 6077.1 | 5896.6 | 84 | 32.7 | 226.0 |
| 2 / cold | candidate | 1196.2 | 6123.5 | 5956.5 | 85 | 28.7 | 183.0 |
| 2 / warm | baseline | 1317.7 | 5595.5 | 5409.5 | 83 | 15.6 | 232.0 |
| 2 / warm | candidate | 824.1 | 5275.7 | 5154.1 | 83 | 34.6 | 193.6 |

Nearest-rank p95 on four samples is the observed maximum; this tiny software cohort cannot estimate physical tails:

| Metric across four strokes | Baseline p50 / p95 / max | Candidate p50 / p95 / max |
| --- | --- | --- |
| Publication CPU | **1349 / 1465 / 1465ms** | **1041 / 1234 / 1234ms** |
| Whole gesture postdraw wall | **5382 / 6077 / 6077ms** | **5543 / 6123 / 6123ms** |
| Release-to-commit wall | **5197 / 5897 / 5897ms** | **5351 / 5957 / 5957ms** |
| Largest drain within each stroke | **15.3 / 32.7 / 32.7ms** | **31.6 / 38.5 / 38.5ms** |

**Interpretation:** Publication CPU improved in all four matched strokes, with ~23% lower median, but whole-gesture time **did not** improve in this sample (median +161ms). Raster staging, preview software compositing, scheduling and run-to-run variation remain significant. The 6ms soft stage budget was unchanged and cannot preempt a single expensive `paint_path()`. There is **no strict stall or responsiveness pass**; the 38.5ms candidate stall must not be smoothed away. Source draw/preview and transaction correctness, not hardware latency, are the confirmed outcomes.

Paired raw logs SHA-256s: baseline #1 `c1e3f1d4ecdca74fa76789f3debb73353ccbe3e3932bb507bb48c4f95e4f6ea5`, baseline #2 `657cf7fc7a8c546b30f62cda17f7eb71f711db3d59a4e8c96d45dd211ab3533a`; candidate #1 `fd7890e2d33138f0c854ded1744dce71fe4da45313270e72981d38776bdebdfc`, candidate #2 `02e6860fdf545a494439aa03095f187a2bd7b113e0b177c6776c401a28592a6d`.

## Reproduction and strict exits

```bash
# Repository root; GODOT points to supplied beta3 binary, not an ambient beta2.
python3 tools/build_drawing_app.py --in-place
"$GODOT" --headless --audio-driver Dummy --editor --path drawing --import --quit

# Independent correctness and diagnostic CPU+Godot static-memory test:
timeout 100s "$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t100_sparse_publication_smoke.gd \
  > /tmp/t100-sparse-publication.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t100-sparse-publication.log \
  --marker T100_SPARSE_PUBLICATION_PASSED

# For each comparative source variant, *same* test/script/assets; one
# process contains a cold + warm independent stroke:
DRAWING_BRUSH_BACKEND=Legacy T095_FULL_CANVAS_RUNS=2 T099_MAX_PREVIEW_FRAMES=110 \
  timeout 100s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd \
  > /tmp/t100-pointer.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t100-pointer.log \
  --marker T095_FULL_CANVAS_PASSED

# Diagnostic red control only; original source staged into the temporary
# drawing/addons tree, then *restored* from the candidate before green runs:
T100_MAX_COMMIT_MS=1850 timeout 100s "$GODOT" --headless \
  --audio-driver Dummy --path drawing \
  --script res://tests/t100_sparse_publication_smoke.gd

python3 tools/validate_ticket_store.py
```

### Other relevant tests (Godot test exit / strict verifier exit)

- Headless source/rollback: `brush_coverage_smoke` (0/0, `T095_ORACLE_PASSED`); `t095_legacy_tile_commit_smoke` (0/0, **519/519**); `t095_tile_commit_smoke` (0/0, 56/56); `t095_mixed_edit_rollback_smoke` (0/0, 504/504); `t095_brush_deferred_staging_smoke` (0/0, 492/492); `t095_tile_shift_smoke` (0/0, 422/422); `t095_sparse_preview_smoke` (0/0, 133/133).
- Graphical Mesa: `t099_preview_schedule_native` (0/0, 46/46), `t098_preview_display_cache_smoke` (0/0, canonical strict marker). All four 96px paired Legacy test processes (0/0).
- Extension **absent**: `native_brush_fallback` process 0, **7/7**, `native=false`; this witness has no success marker and its raw errors were inspected.
- Extension **present**, from offline Rust/Cargo release build: `t095_native_hard_atomic`, `t095_native_hard_source_atomic`, `t095_native_pigment_atomic`, `t095_native_preset_packed_output`, `t095_native_hard_scanline_smoke` (all 0/0 with their strict markers). The new 197-check T-100 oracle also passes 0/0 with the native extension loaded. One actual NativeHard 100-event 96px pointer stroke passes full-red/Undo and strict marker (0/0), but recorded **74.2ms maximum atomic drain**, another unresolved frame-stall warning; its commit CPU was 1480ms (unpaired, not a throughput comparison).
- `python3 tools/validate_ticket_store.py` passes all **109** canonical tickets/review-dependency gates. Required 46 fast-CI steps were **not** all replayed; the manual-on-demand T-095 workflow was not confirmed hosted-passing. The last observed remote T-098 commit workflows remained queued; no hosted green status is inferred. No owner decision or PR merge occurred.

Native Rust release build raw log SHA-256 `d3a28985bd37c4f746f9467dbff5c3d9b0c470e942297626a459b49b901086ec`. NativeHard pointer raw log SHA-256 `2c25a3350ee7bf06ea4c095ca85d395e4f6d08a5a0cba885453ac933545593a1`. The on-demand CI step retains `/tmp/t100-sparse-publication.log` and applies T-094's strict marker verifier; it does not impose the local diagnostic CPU ceiling.
