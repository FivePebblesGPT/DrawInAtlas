# T-179 — Checked native semantic-only subtree removal

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-179](../Tickets/T-179.md) Done locally. T-148 stays In Progress,
T-149 stays Blocked, and T-095's owner/physical-device review remains open.
No hosted CI, hardware latency approval, or universal native-raster authority
is claimed by this evidence.

## Defect and scope

T-173 checked public metadata mutations and T-176 checked semantic structural
Undo/Redo. However, the public `DrawingDocument.remove_subtree()` path for
subtrees with **zero raster descendants** still called `_erase_subtree()`
first and `_advance_nonraster_revision()` afterwards. When an attached native
store rejected the post-mutation revision for a busy stroke or a native-ahead
store, the Godot hierarchy was already deleted and the canonical Rust store
could be detached. The resulting document/history was not retryable without
losing native source authority.

The changed path acquires `_advance_checked_layer_metadata()` after semantic
subtree preflight and **before** deterministic Godot node erasure. On a native
rejection the hierarchy, Godot revision, local/host history, unsaved state and
Rust tile bytes/Undo tokens remain unchanged. On success, Rust and Godot
advance exactly once; recorded local Undo/Redo still uses the checked
T-176 replay. Both unrecorded and externally managed removal preserve the
same native store. Raster-bearing removals still use T-168's independent
park/retire/unreferenced bridge; native-absent historical deletion is unchanged.

## Fail-first control and positive witness

The same 62-assertion fixture
[`drawing/tests/t179_semantic_subtree_removal_native_fence.gd`](../../drawing/tests/t179_semantic_subtree_removal_native_fence.gd)
was executed against the **original pre-fix** canonical addon staged to the
standalone Drawing app, with the real installed Hokusai/Rust GDExtension:

- Before the fix: process exit **1**, `T179_SEMANTIC_REMOVE_RESULT checks=62 failures=16`.
  Failures include busy-native recorded/unrecorded/host deletions, revision
  mismatch, a detached native source, failed retries and native-ahead acceptance.
- After the fix: process exit **0**, `T179_SEMANTIC_REMOVE_RESULT checks=62 failures=0`,
  `T179_SEMANTIC_REMOVE_PASSED`.

The witness covers nested semantic groups/Objects, an existing native Hokusai
Ink stroke, an alpha-zero pixel with nonzero hidden RGB, the exact existing
Rust source buffer and Undo count, local recorded structural Undo/Redo, no
invented local history for untracked or externally owned removal, active
native transaction rejection/retry, native-ahead rejection, native-absent
compatibility, subsequent painting with the **same** Rust store and
`.drawing` Save/Open.

## Final local verification

| Check | Result |
| --- | --- |
| T-179 real-native regression | **62/62 passed** |
| Identical pre-fix control | **16/62 failed as expected**, exit 1 |
| Offline pinned Rust unit tests | **25/25 passed** |
| Rust formatting, strict Clippy `-D warnings`, release build | Passed |
| T-173, T-176, T-177, T-178 metadata/structural/text replay neighbors | Passed |
| T-168/T-169/T-175 subtree delete/import, other T-148 tile/history | Passed |
| Atlas native history, transfer Undo and Object Editor/Save | Passed |
| Graphical Canvas X11 | Passed |
| Strict 96px Hokusai 100-event / 512² full-canvas X11 witness | **262,144/262,144 source pixels covered** |
| Ticket store validator | **179 tickets valid**, review gates intact |

The checked matrix contains **28 passing invocations** with exit code 0 and
the expected script/build success marker; see
[`summary.tsv`](T-179-2026-11-16-semantic-removal-raw/summary.tsv).
Rust source did not change, but the pinned offline release library was still
built and tested. `rustfmt` and the staging helper are quiet on success; their
zero exit codes are the success condition. The Object Editor test reported
Godot Canvas/Texture/ObjectDB resource-leak diagnostics at shutdown despite
its expected PASS marker and zero exit. The diagnostics are retained verbatim
rather than reported as a clean shutdown.

The **single** software-X11 Hokusai trial measured **416.956 ms**
down-to-postdraw with **122.593 ms** native staging CPU, with
`native_ffi_calls=62`, `tile_ffi_calls=51`, and no per-pixel tile stream.
These are software measurements, **not** T-095 reference-device p95 or
physical input-to-photon acceptance.

The complete raw process logs, benchmark JSON and time measurements,
pre-fix failure output, and SHA-256 manifests are stored under
[`T-179 raw evidence`](T-179-2026-11-16-semantic-removal-raw/).
`sha256sum -c SHA256SUMS` passes for every retained file.

## Reproduce

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cd /mnt/data/archive_unpacked/godot_bundle/rust-hokusai
cargo test --offline --locked --manifest-path /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml
cargo clippy --offline --locked --manifest-path /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml --all-targets -- -D warnings
cd /mnt/data/work/DrawInAtlas
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --audio-driver Dummy --path drawing --script res://tests/t179_semantic_subtree_removal_native_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-179-2026-11-16-semantic-removal-raw && sha256sum -c SHA256SUMS)
```
