# T-174 — Fail-closed native semantic/density revisions

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-174](../Tickets/T-174.md) is Done locally. T-148 remains In Progress;
T-149 remains Blocked. No hosted CI green or physical-device acceptance is claimed.

## Defect and repair

`DrawingDocument.add_object`, `move_object`, `commit_text` (new and existing
text) and `set_density` previously changed Godot state before invoking
`_advance_nonraster_revision`. An active Rust edit or a native-ahead store
could reject `advance_metadata_revision` *after* the Godot mutation; the old
helper detached `_native_raster_store`, discarded source identities, and
returned apparent success. In that state a later Brush operation could lose
native history or require an unrelated source rebase.

All four public methods now validate and prepare the replacement first,
call `_advance_checked_layer_metadata()` before changing any live semantic
state, and propagate its explicit failure. Busy Rust returns
`NATIVE_METADATA`; native-ahead returns `STALE_REVISION`. Rejection leaves
Godot revision, Undo/Redo cursor, object/text identity, density, native
attachment and straight RGBA8 (including transparent hidden RGB) unchanged.
Retried commands advance both revisions exactly once, retain existing Rust
Undo tokens and work with future Hokusai edits. Identical text/density no-ops
remain legal, as do native-absent edits pending T-150.

## Fail-first test and positive proof

`drawing/tests/t174_semantic_native_preflight.gd` uses real Godot 4.8 beta3,
the Rust/Hokusai extension, and a painted native 64px Ink layer. The test
holds an actual Rust edit; repeats with a native-ahead revision; and covers
object insertion/movement, text creation/edit, density changes, source/history
continuity, text Undo/Redo, later painting, native-absent compatibility,
no-ops, and real `.drawing` Save/Open.

- **Pre-fix** (same 48 checks after import with previous `document.gd`):
  exit **1**; `T174_SEMANTIC_RESULT checks=48 failures=25`. Source/history
  detachment and Godot-only semantic writes are detected.
- **Fixed**: exit **0**; `T174_SEMANTIC_RESULT checks=48 failures=0`,
  `T174_SEMANTIC_PASSED`. The patched implementation was restored after
  the negative control, reimported and independently rerun.

Both runs include their preceding Godot resource import; a standalone cold
script without the resource import cannot resolve the bundled Lato font and
is *not* acceptable as a correctness control.

## Local validation matrix

| Test/build | Observed result |
| --- | --- |
| New T-174 Godot fixture | **48/48**, exit 0 |
| Native Rust tests | **25/25**, exit 0 |
| rustfmt; strict Clippy (`-D warnings`) | Passed |
| Offline Rust release GDExtension build | Passed |
| Standalone Drawing resource copy and root/standalone imports | Passed |
| T-173 metadata and existing 61-check T-148 metadata fixture | Passed |
| Root Drawing text, Atlas/Object history, native move/undo/export tests | Passed |
| T-154/T-156/T-162/T-165/T-168/T-169 native regressions | Passed |
| Graphical Canvas tile-cutover witness | **46/46**, exit 0 |
| Hokusai Hard Round 96px, 512×512, 100-pointer witness | **262,144/262,144** source pixels covered |
| Ticket-store validator; CI workflow parse | **174 tickets valid**; YAML parsed |

**28/28 final test/build/import invocations passed**, each exit code 0 with
required success marker where applicable. The single software-X11 96px run
measured **354.526 ms to post-draw** and **109.386 ms staging CPU**. This is
neither the reference-device p95 nor physical input-to-photon latency and
does **not** satisfy T-095's hardware/manual-review gate.

Raw evidence: [T-174 logs](T-174-2026-11-16-native-semantic-preflight-raw/),
[summary.tsv](T-174-2026-11-16-native-semantic-preflight-raw/summary.tsv),
[negative-control.log](T-174-2026-11-16-native-semantic-preflight-raw/negative-control.log),
[SHA256SUMS](T-174-2026-11-16-native-semantic-preflight-raw/SHA256SUMS).
Every file listed in the manifest was SHA-256 verified after capture.

## Reproduction

Use the offline Cargo source config and Godot 4.8 beta3 described in
[T-173 evidence](T-173-2026-11-16-native-layer-metadata.md). In the checkout:

```sh
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path drawing --import --quit
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t174_semantic_native_preflight.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-174-2026-11-16-native-semantic-preflight-raw && sha256sum -c SHA256SUMS)
```

## Remaining integration gate

This ticket only protects these four public, semantic/density entry points.
Internal structural history replay and semantic-only subtree import still
use the older post-mutation bridge, and host-owned detached history remains
open under T-148. T-149 stays Blocked; T-095 stays owner-gated.
