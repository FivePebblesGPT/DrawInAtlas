# T-095 — per-session source/preview tile-reference reuse (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **State:** In Progress · `manual_review: true` · **Branch:** `sprint/2026-11-11` · **Parent local HEAD:** `4faa38827e0c90a5cae0ebae45b467e8a3fd728b`. This is one engineering checkpoint, **not** owner acceptance or hardware responsiveness closure. T-096 remains independently in Manual Review.

## Defect and bounded change

The tile-local Brush/Eraser `_stage_brush_tile()` already reused the signed storage-tile key for adjacent pixels. It nevertheless repeatedly fetched `_source_tiles[tile_key]` (the immutable source snapshot) and `_preview_tiles.get(tile_key, {})` (the detached patch) for *each accepted pixel*. At 60px width, this inner loop processes many candidates in a single storage tile, so the repeated Dictionary lookups were avoidable.

`addons/drawing/edit_session.gd` now tracks the most recent tile's **resolved source tile** (`DrawingRasterTile` or a correctly resolved null tile) and **mutable detached preview patch** reference. On entering another tile, it initializes both from authoritative session dictionaries. A source load rejected by `document._resolve_chunk()` is never treated as a resolved empty tile (`_brush_cached_source_ready` remains false), so retry invokes the loader again. Failed paint-batch rollback invalidates the tile key, source-ready flag, source reference and patch reference, guarding against a stale dictionary after the batch journal is restored. The canonical-key staging fallback for non-Brush edits is unchanged. No new global, cross-session or cross-revision cache is used.

This is an optimization of local GDScript work, **not** the previous Rust NativeHard preflight/rollback or Hokusai pigment path, and it does not change the tile sampling/filtering fix from PR #14.

## Independent pixel/history oracle

After staging canonical sources with `python3 tools/build_drawing_app.py --in-place`, on Godot `4.8.beta3.official.c51ff06e8`:

```sh
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/work/Godot_v4.8-beta3_linux.x86_64 \
  --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_brush_tile_reference_cache_smoke.gd \
  > /tmp/t095-brush-tile-reference.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t095-brush-tile-reference.log \
  --marker T095_BRUSH_TILE_REFERENCE_PASSED
```

**Result: 626/626 checks, process exit 0, strict marker accepted.** A second document and edit session use the original canonical-key publisher (`_brush_tile_publish = false`) as the reference, not the cached patch path. Test cases include:

- Five storage strides (3, 16, 30, 64, 255); signed beyond-32-bit world anchors `(-1099511627873, 1099511627929)`, source-tile crossing and revisiting;
- Brush **and Eraser**, opaque/transparent and partial-alpha seeded pixels, selection subtraction holes and viewport clipping, several sequential `paint_path` calls;
- Per-batch exact rendered RGBA8 preview, change count, exact delta `before`/`after`, published image and Undo/Redo for both implementations;
- Late one-shot `DrawingDocument._resolve_chunk()` error after a successful batch, retry of the same path **or** skipping it, requiring no partial preview/history and a reset cache;
- Direct tile-read rejection and retry, requiring that a failed source read not become a cached null tile.

A **deliberately corrupted current-tile patch-cache** temporary staged source produced **95 failed assertions in 603 checks** (including preview, commit, history and Eraser failures), after which the correct implementation was restored and passes 626/626. The corrupt control was not committed.

## Isolated CPU measurement (not pointer latency)

Optional reproducible synthetic trajectory bench: `drawing/tests/t095_brush_reference_bench.gd`. It stages 130 waypoints at 60px across a single session, with three layouts (`axis`, `dab`-pattern, `oblique`) and seven document repetitions per layout. Positions share the same edit session; these are **not** independent isolated mouse dabs. Staging CPU is measured with `Time.get_ticks_usec()`; `commit()` occurs *after* the timed interval. The unchanged pixel-change counts across the runs are respectively 58,116; 36,691; 84,658. All values below are **medians in milliseconds**; optimized/control/optimized swaps used the exact same test runner and software environment.

| Trajectory | Optimized A | Control | Optimized B |
| --- | ---: | ---: | ---: |
| Axis-aligned waypoints | 302.334 | 311.452 | 300.884 |
| Dab-pattern waypoints | 278.813 | 321.934 | 281.579 |
| Oblique waypoints | 462.909 | 521.469 | 481.203 |

CPU time for these isolated workloads was lower in both optimized runs. Small samples, warmup, source swaps and layout all limit transferability; the benchmark does not include real pointer receipt, engine queue, texture upload, frame post-draw or monitor input-to-photon.

## Actual pointer-event Xvfb/Mesa witness (no demonstrated speedup)

The existing `drawing/tests/brush_latency_native.gd` used **five 60px Brush strokes**, **120 motion events per stroke**, **786% zoom**, a **512×512** canvas and actual Godot input event delivery via Xvfb 1280×900 software graphics. An optimized/control/optimized local run sequence reported:

| Metric p95 (ms) | Optimized A | Control | Optimized B |
| --- | ---: | ---: | ---: |
| Total per-stroke staging CPU | 179.878 | 174.234 | 159.175 |
| Release → commit | 58.369 | 56.045 | 59.330 |
| Event receipt → staged | 88.826 | 85.878 | 76.909 |
| Compositor frame CPU | 18.414 | 18.723 | 18.205 |

All three runs printed `T095_NATIVE_PASSED`. **No reliable full-pointer-stroke speedup** is claimed from these measurements. In particular, the original owner-reported minute-long catch-up has not been reproduced on owner hardware, and engine frame callback timing is **not physical input-to-photon latency**.

## Regression and CI scope

The local beta3 headless checks all returned **exit 0** with the expected strict log marker: tile-reference oracle **626/626**, tile-key reuse **33,037/33,037**, signed lookup **4,193/4,193**, deferred staging **492/492**, mixed rollback **504/504**, axis bounds **278/278**, oblique geometry **86/86**, tile publication **56/56**, sparse preview **133/133**, result ownership **30/30**, 60px Brush/Eraser coverage **32/32**, native Hokusai pigment transaction **57/57**, NativeHard source-read transaction **113/113** and native export cache **81/81**. The real installed GDExtension fallback check completed **7/7**, validated by exit 0 plus its exact summary line (the script does *not* emit a `*_PASSED` marker). The graphical Xvfb native integration test passed **30/30**, navigation after release **48/48**, and an additional pointer-driven 5×120 motion run printed `T095_NATIVE_PASSED` with stage CPU p50/p95 **163.644/177.246ms** and release→commit p50/p95 **55.902/61.184ms**. The first batch harness incorrectly expected two different marker names for the export-cache/fallback scripts despite their zero exits; both were then verified using their actual output contracts, not silently counted green by the first harness.

A fresh isolated standalone package built with `python3 tools/build_drawing_app.py --output <empty-dir>`, with its optional `addons/drawing/native` removed **before first editor import**, had a clean `--headless --editor --import --quit` exit 0. The same cache oracle passed **626/626** and its native-absent fallback passed **7/7** (`native=false`), both process exit 0. A repeat of the committed optional synthetic benchmark produced median stage CPU **297.996 / 285.987 / 508.836ms** (axis/dab-pattern/oblique; 7 samples per group) and identical changed-pixel counts. The original configured control values in the table above remain the intended paired-order comparison, not a claim of stable improvement across machines.

Use `tools/check_godot_model_log.py` for scripts with exact markers, and preserve explicit nonzero exits or Godot shutdown errors separately from assertion counts. Validation of `docs/Index.md` and ticket frontmatter with `tools/validate_ticket_store.py` passed **96 tickets**; the on-demand workflow YAML parsed successfully. All of this is local, and hosted GitHub Actions was not run.

The **on-demand**, non-gating `.github/workflows/godot-native-t095-brush.yml` adds the independent cache oracle and records `/tmp/t095-brush-tile-reference.log` using the existing fail-closed checker. The **46 required fast-GDScript CI check IDs are unchanged**. Hosted CI, real-device GPU/driver responsiveness, the owner 60px recheck and explicit approval remain **unverified**; T-095 stays In Progress.
