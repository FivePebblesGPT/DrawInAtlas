# T-173 — Fail-closed native-attached public layer metadata

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-173](../Tickets/T-173.md) completed locally. T-148 remains In Progress,
T-149 Blocked, and T-095 retains its owner/physical-device acceptance gate.
No hosted CI or physical-device performance approval is claimed.

## Defect and correction

`DrawingDocument.create_layer`, `rename_layer`, `set_visibility`,
`set_locked` and `reorder` formerly changed the Godot tree first, then invoked
`_advance_nonraster_revision()`. That helper advanced the Godot revision even
if `DrawingNativeTiles.advance_metadata_revision` rejected a held native edit
or native-ahead revision. It detached the Rust store and dropped its source
identity mapping, with a nominally successful metadata command and a now-
unsynchronized native history timeline.

`_advance_checked_layer_metadata()` now advances Rust's existing, atomic
metadata revision **before** the deterministic Godot tree write. It returns
`STALE_REVISION` on attached revision divergence or `NATIVE_METADATA` for
other native refusal (including a live native transaction). No-op metadata
calls leave revision unchanged. Rejected commands preserve tree membership,
layer properties, canonical RGBA8 and transparent hidden RGB, the same native
store instance and Undo tokens. Successful commands retain native history
while invalidating a branched native Redo as before.

The historical native-absent path remains until T-150. This change does not
replace general metadata mutation paths outside these five public commands.

## Fail-first and corrected native regression

`drawing/tests/t173_native_metadata_preflight.gd` runs against Godot 4.8
beta3 and the existing rebuilt Rust/Hokusai GDExtension. It exercises a real
painted 64px native layer, held Rust edit and native-ahead revision, all five
metadata commands, exact tree/revision/source/history preservation, retries
on the same native store, recorded metadata Undo/Redo, later Brush editing,
no-op commands and native-absent compatibility.

- **Before fix:** same fixture against the committed previous
  `addons/drawing/document.gd`: exit `1`, `T173_METADATA_RESULT checks=31
  failures=22`. The old path accepts unsafe mutations, detaches the Rust
  store and breaks retry/history continuity.
- **After fix:** exit `0`, `T173_METADATA_RESULT checks=31 failures=0`,
  `T173_METADATA_PASSED`.

Two existing fixtures contained older behavioral assumptions. The 61-check
`drawing/tests/t148_metadata_native_revision.gd` now requires atomic refusal
of corrupted subtree deletion (T-168) rather than a Godot-only rebase. The
46-check graphical Canvas witness now explicitly tests a lazy callback's
**rejected** `set_locked` call during a native stroke; unchanged source
ownership allows the stroke to commit and create one new Undo event. Neither
fixture accepts an unauthorized native-source mutation.

## Final local test/build matrix

| Check | Observed result |
| --- | --- |
| T-173 real native fixture | **31/31**, exit 0 |
| Pre-fix negative control | **22/31 failed as expected**, exit 1 |
| Older native metadata regression | **61/61**, exit 0 |
| Rust unit tests | **25/25**, exit 0 |
| rustfmt and strict Clippy `-D warnings` | Passed |
| Offline Rust release GDExtension build | Passed |
| Root and standalone Godot resource import | Passed |
| T-170/T-171/T-172 native transfer, T-148 history, Atlas/Object | Passed |
| T-154/T-156/T-162/T-165/T-168/T-169 regressions | Passed |
| Graphical Canvas tile-cutover witness | **46/46**, exit 0 |
| Hokusai Hard Round 96px, 512×512, 100-pointer software-X11 witness | **262,144/262,144 covered**, exit 0 |
| Ticket-store validator / CI YAML parse | **173 tickets valid**, parsed |

**All 26 final test/build/import invocations passed** (exit 0 and required
success markers). The one software-X11 96px full-canvas trial recorded
**342.405 ms** to postdraw and **111.218 ms** staging CPU, with zero
per-pixel tile FFI stream calls. These are software timings, not the T-095
reference-device p95 or input-to-photon acceptance.

Raw logs and checksum evidence:
[T-173 raw evidence](T-173-2026-11-16-native-layer-metadata-raw/),
[summary.tsv](T-173-2026-11-16-native-layer-metadata-raw/summary.tsv),
[negative-control.log](T-173-2026-11-16-native-layer-metadata-raw/negative-control.log),
[SHA256SUMS](T-173-2026-11-16-native-layer-metadata-raw/SHA256SUMS).

## Reproduction

Use the pinned offline Rust vendor config and the installed Godot 4.8 beta3
bundle described in [T-172's execution evidence](T-172-2026-11-16-atlas-undo-preflight.md).
For this ticket's focused test:

```sh
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t173_native_metadata_preflight.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-173-2026-11-16-native-layer-metadata-raw && sha256sum -c SHA256SUMS)
```

## Remaining work

T-173 closes the five public metadata mutations under a busy or divergent
native store, not all semantic document revisions or the host-owned detached
history timeline. T-148 remains In Progress; T-149 remains Blocked. T-095
still requires its owner/hardware review.
