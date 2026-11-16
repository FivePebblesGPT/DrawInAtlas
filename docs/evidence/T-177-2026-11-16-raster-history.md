# T-177 — Checked native raster structural Undo/Redo

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-177](../Tickets/T-177.md) Done locally. Parent T-148 remains In Progress,
T-149 Blocked, and T-095 owner/hardware review unchanged. No hosted CI green
or physical input-to-photon performance is claimed.

## Defect and change

T-176 fenced semantic structural history, but the local
`DrawingDocument._replay_structure()` raster-create/subtree-removal branch
changed Godot nodes *before* calling native `advance_unreferenced_layers_revision`
or `advance_parked_layers_revision`. If an active edit, divergent revision or
retained source/history blocked Rust, Undo/Redo could still advance the Godot
tree and cursor. A rejected parked transition could additionally fall through
into a GDScript-only revision path, leaving canonical Rust bytes/history behind.

The replay now validates the history target, checks exact attached-native
revision and commits the appropriate bounded Rust transition **before** any
Godot mutation. The parked path requires successful Rust park/unpark and verifies
complete source RGBA8, including transparent hidden RGB. The never-authorized
path requires a successful unreferenced-layer bridge. Both use
`discard_redo=false`, advance exactly one native and Godot revision and
preserve existing unrelated tokens. Native-absent history keeps its former
one-step GDScript behavior. A created raster that has *already been native
painted* cannot be deleted through the unreferenced bridge, even after the
stroke has been undone: this replay intentionally fails closed, leaving a
more general history-aware create/delete lifecycle for T-148.

## Fail-first and positive control

`drawing/tests/t177_raster_history_native_fence.gd` uses the real
Godot 4.8 beta3 GDExtension/Hokusai Hard Round preset and a native-owned Ink
tile. It records three different structural commands: creating a new raster,
removing a never-authorized raster child from a group, and recording removal of
a **painted native-owned** raster child (which Rust parks). For each command it
holds a real Rust transaction and checks rejected Undo and Redo, exact
unchanged tree/dirty/cursor/bytes/native Undo state, then release/retry. It
also tests a native-ahead store, corrupt parked snapshot, retained-native-token
create refusal, hidden RGB, a subsequent Hokusai Brush Undo/Redo, `.drawing`
Save/Open, and native-absent raster history.

- **Pre-fix:** the staged `drawing/addons/drawing/document.gd` was replaced
  temporarily with exact `HEAD` source. The same 89-check fixture exited
  **1**, reporting `T177_RASTER_RESULT checks=69 failures=16`. Its broken
  Undo prevented some later assertions from running, hence 69 rather than 89
  executed checks. No successful Rust/Godot synchronization was claimed.
- **Patched:** the standalone addon was regenerated from canonical source.
  The fixture exited **0** with `T177_RASTER_RESULT checks=89 failures=0`
  and `T177_RASTER_PASSED`.

## Verification matrix

| Check | Result |
| --- | --- |
| T-177 real-native history regression | **89/89 passed** |
| Identical pre-fix control | **16/69 failed as expected**, process exit 1 |
| Offline Rust unit tests | **25/25 passed** |
| rustfmt, strict Clippy (`-D warnings`), release build | Passed |
| Native tile contract | **312/312 passed** |
| T-154/156/162/165/168/169/173/174/175/176 and T-148 neighbors | Passed |
| Atlas history, Object source, transfer and Object Editor | Passed (Object Editor emits shutdown RID leak warnings despite exit 0) |
| Graphical Canvas tile cutover | **46/46 passed**, software-X11 |
| Hokusai 96px/512×512, 100 pointer events | **262,144/262,144 covered**, strict checker passed |
| Ticket-store validation / CI YAML parsing | **177 valid** / parsed |

All **34 final build/test/import invocations** had process exit 0 and passing
markers (where applicable); see
[summary.tsv](T-177-2026-11-16-raster-history-raw/summary.tsv).
The one software-X11 96px run measured **377.668 ms** down-to-postdraw and
**118.383 ms** native staging CPU, not physical T-095 acceptance. A Godot
Object Editor smoke test emitted known resource-leak warnings on shutdown; its
process exit and `OBJECT_EDITOR_PASSED` marker were successful, and its raw
stderr is retained.

Logs, benchmark source histogram/FFI/framebuffer witness, negative-control
log and SHA-256 manifest are in
[T-177 raw evidence](T-177-2026-11-16-raster-history-raw/).

## Reproduce

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cd /mnt/data/archive_unpacked/godot_bundle/rust-hokusai
cargo test --offline --locked --manifest-path \
  /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml
cargo clippy --offline --locked --manifest-path \
  /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml \
  --all-targets -- -D warnings
cd /mnt/data/work/DrawInAtlas
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path drawing --import --quit
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t177_raster_history_native_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-177-2026-11-16-raster-history-raw && sha256sum -c SHA256SUMS)
```
