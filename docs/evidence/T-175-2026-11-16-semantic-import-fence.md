# T-175 — Native-authoritative semantic-only subtree import

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-175](../Tickets/T-175.md) is Done locally. T-148 remains In Progress;
T-149 remains Blocked; no owner hardware review or hosted CI pass is implied.

## Defect and repair

`DrawingDocument.import_subtree()` already builds and validates a detached
hierarchy before publication. The raster-descendant branch was fail-closed
under T-169, but the **semantic-only branch** still called
`_advance_nonraster_revision()`. That helper advances Godot's revision before
trying `DrawingNativeTiles.advance_metadata_revision`; a busy or native-ahead
Rust store rejects and the helper detaches canonical Rust source/history,
yet the importer still publishes nodes and reports success. Standalone Copy
can consequently half-publish a destination.

The semantic-only branch now calls `_advance_checked_layer_metadata()` after
preparing node IDs, children and object copies, but *before* installing any
live nodes or updating untracked history. A busy native edit returns
`NATIVE_METADATA`; a native-ahead revision returns `STALE_REVISION` without
mutating the Godot tree, dirty state, history cursor, original Rust attachment,
or canonical RGBA8. Successful imports commit one shared metadata revision;
old native-absent behavior remains available until T-150.

## Fail-first control and positive witness

`drawing/tests/t175_semantic_import_native_fence.gd` runs in Godot 4.8-beta3
with the real offline Rust/Hokusai GDExtension. It imports a detached nested
Group with editable Text and Objects into a document that has an existing
Hokusai-painted 64px Ink layer and retained Rust Undo token.

- **Pre-fix:** same fixture against `HEAD:addons/drawing/document.gd`, with
  its own resource import, exits **1** with
  `T175_SEMANTIC_IMPORT_RESULT checks=27 failures=13`. Failures include
  accepting a busy native store, partial standalone Copy, dropping the Rust
  attachment, advancing document/history state, and broken Undo/Redo continuity.
- **Fixed:** same fixture after restoring the patch and importing resources,
  exits **0** with `checks=27 failures=0` and
  `T175_SEMANTIC_IMPORT_PASSED`. This covers retry after releasing the native
  transaction, native-ahead rejection, immutable donor, full semantic tree,
  exact Rust RGBA8/Undo token preservation, further native painting, Brush
  Undo/Redo, real `.drawing` Save/Open and native-absent compatibility.

The negative control and final matrix are separate runs. No failed cold font
import is used as a defect oracle; both control and final positive test have
Godot resource-import evidence.

## Validation matrix

| Test / build / integration | Result |
| --- | --- |
| New T-175 Godot fixture | **27/27**, exit 0 |
| Pre-fix negative control | **13/27 failed as expected**, exit 1 |
| Rust unit tests | **25/25 passed**, offline/locked |
| rustfmt, strict Clippy (`-D warnings`) | Passed |
| Offline Rust release build | Passed; `.so` copied to Drawing GDExtension path |
| Standalone Drawing bundle and root/standalone Godot imports | Passed |
| T-174/T-173/T-148 metadata, text/structure import regressions | Passed |
| T-154/T-156/T-162/T-165/T-168/T-169 native history/publisher regressions | Passed |
| Atlas history, transfer Undo/Copy and Object Editor regressions | Passed |
| Graphical native Canvas tile cutover | **46/46**, exit 0 |
| Hokusai 96px, 100-pointer, 512×512 witness | **262,144/262,144 pixels covered**, exit 0 |
| Ticket validator; CI workflow parse | **175 tickets valid**, YAML parsed |

**All 29 final build/test/import invocations passed**, with exit status 0
and required success marker where applicable. The one software-X11 96px trial
reported **342.665 ms** down-to-postdraw, **108.425 ms** staging CPU and
full pixel coverage. This is not a physical-device p95 or input-to-photon
measurement and does **not** close T-095's owner/manual-review gate.

Raw evidence: [logs](T-175-2026-11-16-semantic-import-fence-raw/),
[summary](T-175-2026-11-16-semantic-import-fence-raw/summary.tsv),
[negative control](T-175-2026-11-16-semantic-import-fence-raw/negative-control.log)
and [SHA256SUMS](T-175-2026-11-16-semantic-import-fence-raw/SHA256SUMS).
All logged files in the manifest have been verified with `sha256sum -c`.

## Reproduction

Use Godot 4.8-beta3 and the pinned offline Rust setup from
[T-174 evidence](T-174-2026-11-16-native-semantic-preflight.md):

```sh
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path drawing --import --quit
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t175_semantic_import_native_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-175-2026-11-16-semantic-import-fence-raw && sha256sum -c SHA256SUMS)
```

## Remaining gate

This proves the semantic-only *import* boundary, not internal structural
Undo/Redo replay, global host-owned detached history, or universal Rust
raster authority. T-148 stays In Progress, T-149 Blocked, T-095 manual.
