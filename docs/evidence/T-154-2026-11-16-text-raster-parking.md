# T-154 — checked native parking for text-derived raster history

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** [T-154](../Tickets/T-154.md) **Done**. This is one independently verified child of **T-148 In Progress**, not final universal native ownership. Baseline for the delivered mailbox is remote `fa36c19909ebaf056aaa375fe358151805928b51`, plus the unpushed local T-153 predecessor `c77d9f777b511813e38065ed5da279757f0c5d6d`. T-149 remains Blocked and physical T-095 manual approval is unchanged.

## Defect and fix

After Hokusai painting on a rasterized-text layer, Undo of the stroke left the layer's canonical source and Redo token in Rust. Undo of `rasterize_text` then called `advance_unreferenced_layers_revision` on this **already-authorized** raster ID. Rust correctly rejected the false claim, but Godot still incremented its revision. A subsequent Brush on another layer therefore rebased Rust, discarded unrelated Undo/Redo tokens and duplicated source transfers.

`DrawingDocument._replay_text_tree` now preflights native source identity and full straight-RGBA8 byte parity (including hidden RGB) before a *single* checked structural history boundary. For Rust-owned text-derived raster layers it parks/unparks through existing `advance_parked_layers_revision`; this keeps resident canonical buffers, layer authorization and token stacks, while forbidding editing of a parked layer. After successful restored raster replay, Godot rebinds the newly detached tile object identities, with no lazy provider/FFI pixel-stream fallback. For never-authorized IDs only `advance_unreferenced_layers_revision` may succeed. Neither failed path may advance either revision. A newer native store fails closed; an already-behind store remains on the previously documented explicit rebase path.

## Negative control

Built a standalone project with the **original** `HEAD:addons/drawing/document.gd`, performed the editor font import, then executed the *new* T-154 test against that original implementation. The test executed and exited **1** with `T154_PARKED_PASSED checks=30 failures=15`: it detected the Rust revision divergence, missing park, unsound snapshot Redo, lost native token and incorrect byte replay. Replacing the original document with this implementation and repeating the same fixture exited **0**, `checks=30 failures=0`. The negative-control failure was not a missing font/resource or a parser error.

## Accepted tests (all success process exits 0)

| Operation | Observed evidence |
| --- | --- |
| T-154 native Godot history + Save/Open | **30/30** real native checks |
| Updated prior text/raster guard | **32/32** checks |
| Standalone semantic text renderer | **60/60** checks (root project) |
| Native metadata, subtree import, retirement | **61 / 33 / 33** checks |
| Native tiles, persistent source, external publication, document edit | **312 / 44 / 28 / 55** checks |
| Native Brush and stroke ABI | **32 / 20** checks |
| Atlas history and Object save source | **43 / 38** checks |
| Detached bootstrap, detached replay, history payload, reentrant history | **34 / 21 / 20 / 25** checks |
| Real graphical native tile Canvas (software X11) | **46** checks, `tile_pixel_stream_calls=0` |
| Full 512², 96px Hokusai Hard Round 100-event X11 witness | **262,144/262,144** covered, zero holes, exact Undo/Redo, 326.586ms single-run down-to-postdraw, 107.484ms staging CPU |
| Rust unit, rustfmt, strict clippy | **22 tests** / pass / pass (native Rust code unchanged) |
| Ticket validator | **154 tickets** valid, manual dependency gates preserved |

All Godot fixtures in the table were run against the staged T-153 native Hokusai-only `.so` binary; this ticket modifies GDScript only. A new clean Cargo **release rebuild was interrupted by the command timeout** after 180 seconds, so no new-release-build success is claimed; the unchanged, previously validated T-153 release binary was retained. An initial attempt invoked `drawing_text_smoke.gd` against the standalone project, which does not contain that root-only test; it was rerun in the root project and passed all 60 checks. Neither setup issue is a regression or counted as a pass. The X11 benchmark is one software-rendered trial, **not** T-095 physical input-to-photon or 100ms owner signoff.

## Reproduction

Use the supplied Godot 4.8 beta3 and Rust 1.99.1 bundle (offline vendor source), stage with `python3 tools/build_drawing_app.py --in-place`, import the standalone Godot editor resources, then run:

```bash
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path drawing --script res://tests/t154_text_raster_parked_history.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path drawing --script res://tests/t148_text_raster_native_revision.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path . --script res://tests/drawing_text_smoke.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-154-2026-11-16-text-raster-parking-raw && sha256sum -c SHA256SUMS)
```

[Raw log hashes, process outcomes and strict markers](T-154-2026-11-16-text-raster-parking-raw/SHA256SUMS) retain the fail-first control, Rust suite, Godot and X11 evidence. The **complete delta** from remote still includes predecessor T-153 because its implementation commit remains unpushed. Remaining T-148 scope: new conversions of previously parked raster IDs, other raster producers and complete host-history/native authority. T-149 and manual gates remain unchanged.
