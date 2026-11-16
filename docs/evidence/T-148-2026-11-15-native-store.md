# T-148 — Rust-owned tile store, direct bridge acceptance (partial)

Date: 2026-11-15. Branch `sprint/2026-11-15`. Source branch baseline `b86f9080` (T-147); GitHub remote baseline checked as `a83e5055` (T-146/T-147 are local commits, not remote). **Ticket remains In Progress**: this evidence verifies a direct native tile path; it does **not** show that the production `DrawingCanvas` stopped using `DrawingEditSession.paint_path_native()`'s per-pixel GDScript staging. The `T-149` display/save consumer is still blocked. No real-device 60/96px latency or owner acceptance is claimed.

## Actual direct native path

`native/drawing_brush/src/native_tiles.rs` registers `DrawingNativeTiles`: one sparse map of bounded, **dense RGBA8 tile byte buffers**, an explicit authorized source identity per tile, detached per-batch drafts and selection masks, native blend/erase, dirty tile rectangles, and reversible before/after history. Source tiles are byte-exact straight RGBA8 (including hidden RGB); strides are configurable independently from Hokusai's 64px and Godot display's 128px sizes. Signed world coordinates floor-divide to signed tile IDs and support anchors beyond 32-bit limits. A missing/lazy source never silently becomes empty.

One `DrawingNativeBrush` stroke uses `begin_stroke` → `append_samples` → `required_tiles` → `apply_tile_batch` (one **atomic stage and acknowledgement**; an error rolls back both native rasterizer state and tile staging) → `commit_tiles`. A successful publication consumes the brush handle, inserts **one** Undo history record, and advances **one native revision**; a no-op consumes the handle without increment or Undo entry. An inaccessible layer blocks the commit without publishing any tile; source and handle remain retryable. `DrawingNativeTiles.read_tile` yields copied, immutable-at-reader-lifetime, packed whole-tile spans; `list_tiles` paginates persistent identities. No per-pixel Godot calls or pixel stream cross the **direct tile** API; the transitional T-147 Canvas API still has a packed per-pixel delta path.

## Verified tests (actual local exit status 0)

| Test | Result | Assertion scope |
| --- | --- | --- |
| Rust `cargo test --offline --locked --all-targets` | **17 passed** | Native sparse/dense tile ops, signed seams, layer isolation, masks, hidden RGB, source failures, no-op revision, rollback, stroke pigment/hard states |
| Rust `cargo clippy --offline --locked --all-targets -- -D warnings` | **Passed** | Full Rust targets, no warnings |
| Release build, pinned Godot import | **Passed** | Real `libdrawing_brush.so`, real Godot 4.8 beta 3 engine, not an ABI mock |
| Godot `t148_native_tiles_contract.gd` | **312 checks, 0 failures** | Native 96px/512², source RGBA, dirty regions, Undo/Redo, paginated byte Save/Open parity, signed >32-bit anchor, multi-layer, mask and hidden RGB, Hokusai pressure+eraser, fail/retry and cross-layer rejection |
| Godot `t147_native_stroke_contract.gd` | **35 checks, 0 failures** | Existing ABI v1 ordering and rollback |
| Godot `t095_native_hard_source_atomic.gd` | **113 checks, 0 failures** | Existing Canvas source failure / retry and history |
| Godot `t095_native_pigment_atomic.gd` | **57 checks, 0 failures** | Existing Canvas Hokusai errors / retry |
| Godot `native_brush_fallback.gd` | **7 checks, 0 failures** | Transitional legacy fallback (to be retired by T-150) |
| X11 `native_brush_integration.gd` | **32 checks, 0 failures** | Real NativeHard, Hokusai presets and Canvas behavior |
| X11 `t146_hokusai_full_canvas_native.gd` | **PASSED**, 1 repeat | Existing 96px Hokusai X11 framebuffer and source witness, 262,144 covered/262,144, 0 transparent holes; software end-to-end ~2.6s, no physical latency claim |
| `tools/validate_ticket_store.py` | **152 tickets valid** | YAML board status and gates (run after ticket update) |

For the **direct** 96px hard test, 99 path points (four samples per input batch) painted exactly 262,144 source pixels across four 256×256 storage tiles; stage wall-clock measured **120.3ms in this one headless process** (not a native CPU-only benchmark, input-to-photon, or a cross-mode comparison). A sample instrumented store snapshot after revision 3 reported **45 store FFI calls, 0 pixel-stream FFI calls, 2,621,440 copied bytes exported from its inspection operations, and 3,145,728 counted resident/draft/history bytes**. The bridge deliberately reads whole RGBA tiles for SHA-256, mask and Save/Open checks; exported byte volume is **not** the actual live UI texture-upload workload. The design uses sparse tile **identity allocation** but dense 4-byte/pixel backing for touched tiles; this avoids string-keyed per-pixel maps, but memory/performance comparison against an alternative COW representation is still required before declaring a workload-wide winner.

## Reproduce

```bash
# After extracting the supplied bundle at /mnt/data/dev-bundle:
bash tools/build_native_brush.sh /mnt/data/dev-bundle
python3 tools/build_drawing_app.py --in-place
G=/mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64
"$G" --headless --audio-driver Dummy --editor --path drawing --import --quit
"$G" --headless --audio-driver Dummy --path drawing --script res://tests/t148_native_tiles_contract.gd > t148.log 2>&1
rc=$?; test "$rc" -eq 0
python3 tools/check_godot_model_log.py t148.log --marker T148_NATIVE_TILES_PASSED
# X11/Mesa regression (separate from the headless bridge):
DRAWING_BRUSH_BACKEND=Hokusai T095_FULL_CANVAS_RUNS=1 timeout 120s \
  xvfb-run -a -s '-screen 0 1280x900x24' \
  "$G" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t146_hokusai_full_canvas_native.gd > t146.log 2>&1
rc=$?; test "$rc" -eq 0
python3 tools/check_godot_model_log.py t146.log --marker T146_HOKUSAI_BENCHMARK_PASSED
python3 tools/validate_ticket_store.py
```

Cargo uses the supplied Rust 1.99.1 with offline vendored packages; configure Cargo's `[source.crates-io]` replacement with the extracted bundle's `rust-hokusai/vendor` path. **Raw logs** and a SHA-256 manifest are committed under [`T-148-2026-11-15-raw/`](T-148-2026-11-15-raw/manifest.json). Godot test processes returned zero before their markers were accepted. The strict marker checker passed for the new direct bridge and the Hokusai framebuffer witness; existing T-095 native source tests also passed their strict checks.

## Outstanding acceptance (no premature closure)

- Live `DrawingCanvas`/`DrawingEditSession` still calls `preview_changes` and loops across packed pixels to blend/stage GDScript dictionaries. T-148 must remove this Brush/Eraser hot path and share one native/Godot document revision; the independently instantiated tile store is not yet the active document. The T-149 renderer/persistence paths must not start with a second competing revision owner.
- Real `.drawing` save/reload, Atlas/Object publication and presentation of native held/dirty tiles still go through current GDScript source storage; the new test's native tile import/export is a byte-identity contract witness, **not** production file compatibility.
- More representative full-process transfer/RSS and sparse/dense/COW comparisons, with a calibrated workload and a real native-draft/preview display integration, remain open. No hosted GitHub CI result or physical/hardware frame latency signoff is inferred.
