# T-148 checkpoint — reversible native-owned raster subtree parking

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148, **In Progress**. This checkpoint builds on local `65f42948` (nine sprint commits above GitHub `a83e5055`). T-149 remains blocked; no manual owner gate changes.

## Defect, contract and implementation

Previously, `remove_subtree` invalidated Rust's revision when *any* raster child had resident source bytes or history. A subsequent native Brush rebased and discarded otherwise valid Undo/Redo for all layers, even when the user simply removed and restored a painted group. This also prevented native history continuity when other active raster layers were painted while that group was deleted.

A recorded **local** subtree removal now performs a checked `DrawingNativeTiles.advance_parked_layers_revision(expected, ids, restore=false, discard_redo=true)` before the deterministic Godot tree mutation. It accepts 1–128 unique IDs only at an exact quiescent, non-overflowing shared revision. All specified raster layers become **parked** (at most 128 simultaneously; at least one affected layer must already be Rust-owned): the store retains RGBA8 bytes, explicit source authorization and history tokens, but denies their new imports, brush transactions and native history replay while absent. Unaffected raster layers remain paintable. Structural Undo/Redo toggles all affected IDs atomically with `restore=true/false` and `discard_redo=false`, advancing the same revision without copying Rust pixels. A source rebase clears parked IDs alongside authorization/history.

Before a recorded deletion, Godot preflights all known imported source **object identities and canonical bytes** against the corresponding Rust `read_tile` buffers; no lazy source callbacks run between this check, native park and deterministic tree removal. A structural restore rejects altered detached history snapshots before changing the tree or Rust. After restoring byte-identical snapshots, it rebinds verified source objects to the restored projection, preventing redundant imports on the next Brush. Both nested native-owned raster children can be parked/restored in one revision transition. A newly created layer cannot reuse a parked native-owned ID. Never-imported raster trees still use the original unreferenced metadata bridge and do **not** accumulate parked tombstones. Direct unrecorded removal and any rejected/stale/inconsistent native park remain on the older conservative document-revision/rebase path; this is **not** universal source ownership.

The native store retains canonical bytes across these structural events; Godot retains the detached source snapshots for Save/Open and old history replay. A 64-entry Rust Undo cap and the native 256MiB memory budget still apply. This checkpoint is **not** evidence that all other raster producers or Atlas/Object integrations use one native source authority.

## Reproduction and verification

Pinned runtime: Godot `4.8.beta3.official.c51ff06e8`, Rust/Cargo 1.99.1, offline bundle-8 vendor directory, Linux Xvfb/llvmpipe. Rebuild the native release library; run `python3 tools/build_drawing_app.py --in-place`, then install `native/drawing_brush/target/release/libdrawing_brush.so` into the staged `drawing/addons/drawing/native/bin/` directory. Use `source /mnt/data/dev-bundle/setup-rust-env.sh` and an ignored `.cargo/config.toml` pointing at the bundle's `rust-hokusai/vendor` for offline Cargo.

```bash
cd native/drawing_brush
cargo test --offline --locked --lib
cargo fmt --all --check
cargo clippy --offline --locked --all-targets -- -D warnings
cargo build --offline --locked --release

# From repository root, with the exact Godot beta3 binary in $GODOT:
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path drawing --script res://tests/t148_metadata_native_revision.gd
GODOT_SILENCE_ROOT_WARNING=1 timeout 125s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/t148_canvas_tile_cutover_x11.gd
python3 tools/validate_ticket_store.py
```

Every included process exited zero, with explicit success markers, no GDScript/runtime errors and [SHA-256-verified raw logs](T-148-2026-11-15-parked-subtrees-raw/SHA256SUMS):

| Test | Result |
| --- | --- |
| Rust unit suite / rustfmt / strict Clippy / release | **22** passing tests / pass / pass / pass |
| Expanded real-native metadata/structural regression | **61** checks, 0 failures |
| Native tile contract / document publication | **312 / 55** checks, 0 failures |
| Persistent native document / external raster adoption | **44 / 28** checks, 0 failures |
| Native brush integration / ABI contract | **32 / 35** checks, 0 failures |
| Atomic NativeHard / pigment rollback | **25 / 57** checks, 0 failures |
| Mixed-edit rollback | **504** checks, 0 failures |
| Live X11 Canvas native tile consumer | **46** checks, zero tile pixel-stream calls |
| 96px NativeHard / 96px Hokusai witnesses | full 512² source oracle, both passed |
| Object assets / Atlas campaign bundle smoke | **95 / 86** checks, 0 failures, separately |
| Kanban validator | **152** tickets valid, manual gates preserved |

In the single-run Xvfb 96px trials, input-to-settled-postdraw was **864.079ms** for NativeHard and **606.662ms** for Hokusai (not physical input-to-photon measurements; 100ms target **not** met). The standalone `.drawing` source save/reload after native-owned subtree restore was byte-exact; the Object/Atlas smoke tests are separate and do not prove integrated native-source Atlas/Object persistence.

Two initial setup attempts surfaced GDScript indentation/scope parser errors during development, which were corrected and excluded from passing evidence. The final regenerated standalone addon and extension were tested together.

## Remaining T-148 acceptance

Unrecorded/external subtree removals still rebase; text-to-raster conversion, other producers that bypass native tile adoption, detached native history across ownership evictions and integrated native-source Atlas/Object save/history acceptance remain. Park/restore is reversible only while the persistent native store and a verifiable local structural-history event are available. T-148 remains **In Progress**; T-149 is **Blocked**. T-095 stays with the owner for physical responsiveness acceptance.
