# T-095 — avoid Canvas redraw for unchanged Brush previews (2026-11-11)

**Branch:** `sprint/2026-11-11` (local, unpushed); **ticket:** T-095 (`In Progress`, `manual_review: true`). **Pinned local engine:** Godot `4.8.beta3.official.c51ff06e8`, Linux headless, with an additional Xvfb/Mesa llvmpipe 60px input witness. This is a CPU/draw scheduling checkpoint, **not** a physical GPU input-to-photon acceptance result.

## Observed work and change

`DrawingCanvas._drain_segments()` previously set `changed = true` after *every* successful `session.paint_path*()` batch, even if the pixels were already covered or excluded by the captured selection. At the end of each drain it always queued a Canvas redraw. During a held 60px Brush, duplicate samples and no-op strokes can consume stage work without changing any detached-preview bytes; unnecessarily redrawing the Canvas can still traverse visible tile caches and issue frame callbacks.

The drain now snapshots `session._preview_epoch` at entry and queues a redraw only when the session's preview generation changes. The epoch is already incremented by actual Legacy Brush patch mutations and Hokusai delta preview mutations; it is not tied to `change_count()` (which can return to the same value after a real pixel mutation). The draw-on-commit, cancellation/error redraw, per-motion cursor redraw, source-space sample drain, queue retention, and history publication are unchanged. This is intentionally **not** an input-dropping or pointer-path simplification.

## Independent negative control and corrected test

`drawing/tests/t095_noop_redraw_smoke.gd` instantiates the real `DrawingCanvas` under a running SceneTree, counts **actual `CanvasItem.draw` callbacks** and advances a process frame between successive no-op inputs. The script also checks the actual sample stage counter, changed `_preview_epoch` for a real sweep, source-image bytes against a separate reference edit, a single commit, exact Undo/Redo, and a wholly excluded selection. The test has **24 assertions**. It uses a 12px deterministic Brush, not a performance substitute for the owner's 60px case.

| Build under test | Checks | Canvas draw callbacks | Process exit |
| --- | ---: | ---: | ---: |
| Original local `c1a41cc2` Canvas temporarily staged **only in `drawing/`** | 21/24 | **55** | **1** (three expected no-op redraw failures) |
| Updated canonical Canvas, same test and engine | **24/24** | **7** | **0** |

The 48 suppressed redundant callbacks in this controlled headless witness are **not** FPS, elapsed render time or physical display measurements. Tests with the modified canonical Canvas passed the exact `T095_NOOP_REDRAW_PASSED` marker through the fail-closed `tools/check_godot_model_log.py`. The unmodified control exited nonzero as expected. The staged control was discarded before other regressions; only the canonical `addons/drawing/canvas.gd` is edited in the commit.

## Adjacent local checks

All the following runs exited **0** under pinned beta3 and their raw logs were checked for the reported zero-failure assertions:

- `t095_noop_redraw_smoke.gd`: **24/24**, strict success-marker check.
- `brush_coverage_smoke.gd`: **32/32**, strict marker.
- `t095_brush_deferred_staging_smoke.gd`: **492/492**, strict marker.
- `t095_brush_tile_reference_cache_smoke.gd`: **626/626**, strict marker.
- `t095_mixed_edit_rollback_smoke.gd`: **504/504**, strict marker.
- `t095_sparse_preview_smoke.gd`: **133/133**, strict marker.
- `t095_native_hard_source_atomic.gd`: **113/113**, strict marker.
- `t095_native_pigment_atomic.gd`: **57/57**, strict marker.
- `t095_native_hard_packed_output.gd`: **20/20**, strict marker.
- `t095_native_preset_packed_output.gd`: **69/69**, strict marker.
- `t095_native_export_cache.gd`: **81/81**, strict marker `T095_EXPORT_CACHE_PASSED`.
- `native_brush_integration.gd`: **30/30**, process pass and zero-failure summary.
- `native_brush_fallback.gd`: **7/7**, native present; process pass and zero-failure summary.
- `stroke_navigation_native.gd`: **48/48**, Xvfb process pass and zero-failure summary.
- `brush_latency_native.gd`: five pointer-event strokes, Xvfb process pass and strict `T095_NATIVE_PASSED` marker. Legacy 60px / 786% stage p95 **161.914 ms**, release-to-commit p95 **68.704 ms** in this run; **not** a paired speedup comparison.

For integration, navigation and fallback scripts, the local summary markers are `*_RESULT`, not `*_PASSED`, so no strict positive-marker pass is claimed. An initial mistaken invocation of nonexistent `t095_native_export_cache_smoke.gd` failed to load and was corrected to `t095_native_export_cache.gd` before the 81/81 pass. No failed command is silently counted as a clean pass.

A fresh `tools/build_drawing_app.py --output <empty-external-dir>` standalone, with `addons/drawing/native` removed **before** editor import, passed Godot editor import (exit 0), the new no-op redraw oracle **24/24** (exit 0), and native-absent fallback **7/7** (`native=false`, exit 0).

The on-demand, **non-required** `.github/workflows/godot-native-t095-brush.yml` now runs the new oracle before native build, checks its exact marker using the existing fail-closed log verifier, and uploads its raw log under `if: always()`. The required 46-check fast CI matrix and T-094 policy are unchanged. Hosted Actions was **not run**.

## Reproduce

Stage canonical addon: `python3 tools/build_drawing_app.py --in-place`. With the pinned Godot beta3 on `PATH`:

```sh
godot --headless --audio-driver Dummy --path drawing --script res://tests/t095_noop_redraw_smoke.gd 2>&1 | tee /tmp/t095-noop-redraw.log
python3 tools/check_godot_model_log.py /tmp/t095-noop-redraw.log --marker T095_NOOP_REDRAW_PASSED
```

This test only verifies that unchanged previews do not schedule an *additional CanvasItem draw*. A pointer **motion** can legitimately request a redraw for the cursor even without a paint mutation; it is intentionally not suppressed. The original owner's 60px Brush hardware lag, physical input-to-photon and hosted CI, review acceptance, and T-096's independent Manual Review **remain open**. Do not mark T-095 Done on this evidence.
