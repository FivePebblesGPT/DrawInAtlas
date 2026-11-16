# T-148 checkpoint — native revision bridge for detached subtree imports

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148 **In Progress**. Builds on local `e27c7f4f` (ten prior sprint commits relative to GitHub baseline `a83e5055`). T-149 remains Blocked, and T-095 retains its hardware/owner gate.

## Defect and bounded change

`DrawingDocument.import_subtree()` previously copied a detached group and then advanced only its GDScript revision. A subsequent native Brush observed an out-of-date Rust revision and rebased **all** canonical native tiles/history, even when the transferred raster layers had entirely new identifiers and could not affect prior Rust-owned source. This made ordinary copy/import operations destroy native Undo continuity for unrelated painted layers.

The import now constructs the entire detached hierarchy, remapped IDs, independent RGBA8 tile objects and dirty-tile descriptors in temporary dictionaries **before** publishing any nodes. It rejects an ID reserved by a parked native subtree. The structural commit advances the one document revision through an existing checked native bridge **before** installing the already-prepared Godot projection: `advance_metadata_revision` for semantic-only trees, or bounded `advance_unreferenced_layers_revision` for 1–128 previously unowned raster layer IDs. No lazy providers or arbitrary callbacks run after successful native advance. Rust retains existing tile bytes/authorizations and native Undo tokens. New incoming pixels remain a detached Godot source until a later Brush explicitly imports the relevant tiles; this is *not* a second canonical Rust source.

If Rust rejects a bridge (stale revision, active transaction, reused Rust-owned ID, or more than 128 raster IDs), the legacy conservative revision/rebase route remains: the Godot import still completes, but a later gesture clears and reauthorizes native state rather than silently mixing two sources. Invalid snapshot trees and parked-ID collisions fail **without** modifying the tree, either revision, or native history. Cross-document copy uses the same import path. The externally owned source document is never aliased. This does **not** make unrecorded **removal** of Rust-owned layers history-safe, nor does it migrate all raster producers or detached native history replay.

## Reproduction and test matrix

Pinned bundle-8 environment: Godot `4.8.beta3.official.c51ff06e8`, Rust/Cargo `1.99.1`, offline Hokusai vendor, software X11/Xvfb/llvmpipe. `tools/build_drawing_app.py --in-place` updated the standalone Drawing test project; the pinned release Rust GDExtension was copied into its native bin directory.

```bash
cd native/drawing_brush
cargo test --offline --locked --lib
cargo fmt --all --check
cargo clippy --offline --locked --all-targets -- -D warnings
cargo build --offline --locked --release

# From repository root; GODOT is the bundle-8 pinned Godot binary.
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path drawing --script res://tests/t148_import_subtree_native_revision.gd
python3 tools/validate_ticket_store.py
```

| Verification | Result |
| --- | --- |
| New detached subtree import regression | **33 checks passed**, zero failures |
| Rust unit tests / rustfmt / strict Clippy / release build | **22 tests passed** / pass / pass / pass |
| Metadata/parked subtree regression | **61** checks passed |
| Persistent-document / external raster adoption | **44 / 28** checks passed |
| Tile store / document tile publication | **312 / 55** checks passed |
| Mixed edit rollback / v1 stroke contract | **504 / 35** checks passed |
| Headless native brush integration | **32** checks passed |
| X11 live native-tile Canvas integration | **46** checks passed; zero pixel-stream calls |
| 96px NativeHard / Hokusai 512² graphical witnesses | Both passed full-source oracles, no holes |
| Object / Atlas standalone smoke tests | **95 / 86** checks passed (separate; not integrated native-source proof) |
| Ticket board validator | **152** tickets valid; gates preserved |

The new test exercises a detached nested group containing a signed lazy RGBA8 tile with hidden RGB and semantic objects; correct source copying, ID remapping, native history/source import counts, two Brush gestures and their Undo/Redo, first Brush on the imported layer, exact Save/Open, malformed snapshot rejection, a parked native-ID collision, cross-document copy, reuse of an unrecordedly removed native-owned ID and a 129-raster-layer over-limit fallback. Each successful run exited zero and produced its required passing marker. [Raw logs and SHA-256 manifest](T-148-2026-11-15-import-subtree-raw/SHA256SUMS) are retained.

In the independent **single-run** software-rendered 96px witnesses, input-to-settled-postdraw measured **671.189ms** NativeHard and **544.397ms** Hokusai (not physical input-to-photon; both above the proposed 100ms target). The Hokusai run reported **262,144/262,144** source pixels covered. This import-revision change does not establish a performance improvement.

## Outstanding acceptance

T-148 remains **In Progress**: direct/unrecorded native-owned subtree removals, text rasterization, other raster producers and detached history fallback may still clear Rust ownership; integrated native-source Atlas/Object persistence and universal revision authority remain unproven. T-149 remains **Blocked**, and owner-gated T-095 is unchanged.
