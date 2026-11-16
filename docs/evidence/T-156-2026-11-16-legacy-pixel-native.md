# T-156 — native replay of historical pixel-map history

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** [T-156](../Tickets/T-156.md), Done locally. Parent [T-148](../Tickets/T-148.md) remains In Progress. Tested with Godot 4.8 beta3, offline Rust 1.99.1, and the supplied Hokusai/libmypaint bundle. This checkpoint follows unpushed T-153, T-154 and T-155; the remote-relative mailbox must include them until PR #19 advances.

## Defect and bounded fix

A pre-native `DrawingDelta` holds per-pixel `before` and `after` maps. After Hokusai painting created a persistent Rust tile/history store, replay of that older event still used Godot `_publish_edit` with `record_history=false`, advancing `DrawingDocument.revision` while the attached `DrawingNativeTiles` stayed behind. The next Brush then rebased, invalidating its old history tokens and source authorizations. This affected both standalone local history and `external_history` documents whose chronology belongs to Atlas.

`_replay_pixel_delta_native` now snapshots and validates matching old pixel keys, canonical signed coordinates, 32-bit RGBA values, and a bounded set of tile IDs (at most 128 tiles and a conservative 256MiB/three-full-spans preallocation budget). It materializes full canonical straight-RGBA8 tile before/after images, preserving all untouched pixels, including alpha-zero hidden RGB. It rechecks the caller-owned `DrawingDelta`, then enters existing `_replay_native_tile_delta`; that path repeats source/identity/revision validation after all potentially reentrant lazy callbacks and invokes Rust `replay_detached_history` atomically. A failure never publishes a Godot revision; successful replay advances the **same** attached native store without manufacturing another native Undo token. Native detached replay intentionally clears obsolete token stacks while retaining host-owned Undo/Redo envelopes and canonical unrelated tiles.

This is **not** a second Brush backend: the production Brush/Eraser remains tile-based Hokusai only. It is a cold historical-command bridge. The never-native direct pixel replay remains GDScript pending broader T-148 work. General host-history ownership, remaining non-Brush producers and native-only persistence remain outside this ticket.

## Fail-first control

The final 37-check fixture was run against the **original `addons/drawing/document.gd` from local HEAD** (commit `6bd945c9`), with the same native binary, preset, test file and Godot version as the acceptance run. It exited **1** with `T156_LEGACY_NATIVE_RESULT checks=37 failures=19`, including the intended native revision divergence and subsequent unusable native history. Replacing only the document code with the fixed version and restaging exited **0**, `checks=37 failures=0`. The control did not rely on a missing dependency or a parse failure. Raw logs: [negative-old-document.log](T-156-2026-11-16-legacy-pixel-native-raw/negative-old-document.log) and [restored-t156.log](T-156-2026-11-16-legacy-pixel-native-raw/restored-t156.log).

## Verification results

| Test | Observed result |
| --- | --- |
| New local/Atlas-style historical pixel-to-native fixture | **37/37** checks, real Hokusai source, exact Undo/Redo, same native revision/store, signed tiles, hidden RGB, Save/Open, retry, native-ahead rejection, 129-tile budget control, never-native fallback |
| Negative control against old document | **19/37 failures as expected**, exit 1; fixed result exit 0 |
| Rust unit tests, formatting, strict Clippy, release build | **23/23**, `cargo fmt --check`, `-D warnings`, pinned offline `cargo build --release` all pass (Rust code unchanged) |
| Native tile contract and source/metadata/structure neighbors | **312 / 44 / 28 / 55 / 61 / 33 / 33** checks, all pass |
| Previous text T-154/T-155 and T-148 text-raster tests | **30 / 32 / 32** checks, all pass |
| Hokusai Brush and unified stroke ABI | **32 / 20** checks, all pass |
| Root Atlas global native history and Object Save/Save As | **43 / 38** checks, all pass |
| Root detached bootstrap/replay and payload/reentrant guards | **34 / 21 / 20 / 25** checks, all pass |
| Root semantic text | **60/60**, pass |
| Graphical Canvas (X11/llvmpipe) | **46/46**, `tile_pixel_stream_calls=0` |
| 96px Hokusai Hard Round full 512² witness (X11/llvmpipe) | **262,144/262,144** covered, no holes; exact Undo/Redo; single-run **324.838 ms** total p95 and **108.189 ms** stage CPU p95; benchmark correctness passed, `target_met=false` |
| Ticket store | **156 tickets validated**, manual-review gates intact |

All **30** final suite invocations exited 0; the fixture and graphic logs contain explicit success markers. The observed 96px time is one software-X11 run, **not** hardware input-to-photon or owner acceptance for T-095. Older Legacy parity fixtures are not used as Hokusai accuracy oracles.

## Reproduce and verify

Under the offline bundle (the pinned vendor sources are in `rust-hokusai/vendor`), the final commands were:

```bash
(cd native/drawing_brush && cargo test --offline --locked --lib && cargo fmt --all --check)
(cd native/drawing_brush && cargo clippy --offline --locked --all-targets -- -D warnings)
(cd native/drawing_brush && cargo build --offline --locked --release)
python3 tools/build_drawing_app.py --in-place
"$GODOT" --headless --editor --import --quit --path drawing
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t156_legacy_pixel_native_replay.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-156-2026-11-16-legacy-pixel-native-raw && sha256sum -c SHA256SUMS)
```

The actual Rust steps passed the bundle's offline Cargo vendor `--config` and `CARGO_TARGET_DIR` (see [raw `rust-*` logs](T-156-2026-11-16-legacy-pixel-native-raw/)). All individual exits and diagnostic output are preserved at [raw test evidence](T-156-2026-11-16-legacy-pixel-native-raw/summary.tsv) with [SHA-256 manifest](T-156-2026-11-16-legacy-pixel-native-raw/SHA256SUMS).
