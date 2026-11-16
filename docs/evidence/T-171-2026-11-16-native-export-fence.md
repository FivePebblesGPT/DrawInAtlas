# T-171 — Native-authoritative detached subtree export and Copy

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-171](../Tickets/T-171.md) completed locally. T-148 remains In Progress,
T-149 remains Blocked and the T-095 owner/hardware gate is still open. This
is local execution evidence, not hosted CI or physical-device signoff.

## Defect and change

`DrawingDocument.export_subtree()` previously materialized pending tiles and
returned detached Godot raster projection bytes without requiring attached
Rust source parity. A document whose pixels were changed in place after a
Hokusai native stroke could export unauthorized bytes (including hidden RGB
beneath alpha zero). T-166/T-167 fenced save and snapshot; T-170's source
retirement preflight protects **moves**, not ordinary Copy. This also affected
`AtlasDrawingTransfer` at the snapshot preparation stage.

The exporter now checks the attached native revision and complete canonical
RGBA8 of authorized resident tiles **within the requested subtree** before
any provider is called and again after lazy materialization, immediately
before taking detached copies. It checks the document revision after each
lazy provider, returning typed `STALE_SOURCE` or `STALE_REVISION` rather than
publishing unauthorized snapshots. Neither check mutates Rust or consumes a
native history token. Non-selected raster layers are not part of the parity
check; the historical native-absent path remains available until T-150.

## Fail-first and positive witness

`tests/t171_native_subtree_export_fence.gd` exercises actual Hokusai-painted
sources with the Godot 4.8 beta3 runtime and the previously built Rust
GDExtension. The fixture covers:

- Direct export and standalone/Atlas Copy rejection after an in-place
  alpha-zero hidden-RGB mutation, with unchanged destination tree/revision,
  source native bytes and Rust Undo tokens.
- Correction of source bytes and successful detached export/Copy with exact
  source RGBA8 and no retirement of the source's independent native history.
- A lazy chunk provider that returns a valid digest-matched chunk **but**
  changes another resident authorized tile in place. The second source check
  catches the cross-layer reentrant mutation before returning a snapshot.
- Attached native revision ahead of Godot, which rejects direct export and
  Copy before destination mutation; native-absent source export/Copy remains
  supported.

**Patched:** exit `0`, `T171_EXPORT_RESULT checks=33 failures=0`,
`T171_EXPORT_PASSED`.

**Fail-first:** with the original `export_subtree` function restored from
local pre-T-171 `HEAD` (same fixture and native binary), exit `1`,
`T171_EXPORT_RESULT checks=32 failures=11`. The original exporter allowed
unauthorized source snapshots, standalone and Atlas Copy, the reentrant
cross-layer byte mutation, and divergent-native-revision export. The patched
function was restored and re-tested afterward. The check count differs
because the old exporter also incorrectly mutated the destination, which
prevented the fixture from reaching one copied-layer assertion.

## Final local verification

| Check | Result |
| --- | --- |
| T-171 real-native export/Copy witness | **33/33**, exit 0 |
| Original exporter negative control | **11 of 32 failed as expected**, exit 1 |
| Rust unit tests | **25/25**, exit 0 |
| Rust formatting, strict Clippy, release build | Passed |
| T-170 move; T-148 native tiles, import, retirement, persistent store | Passed |
| T-154, T-156, T-162, T-165–T-169 native/history fixtures | Passed |
| Root Atlas native/global history and Object Editor | Passed |
| Graphical Canvas tile-cutover (software X11) | **46/46**, exit 0 |
| 96px Hokusai full-canvas witness (software X11) | **262,144/262,144 covered**, exit 0 |
| Ticket validation and native CI YAML | **171 tickets valid**, parsed |

All **25 final test/build/import invocations** had exit status 0 and the
expected positive marker where applicable. The X11 full-canvas witness
reported **309.504 ms** down-to-postdraw and **106.759 ms** native staging CPU
for one 100-event 512×512/96px software run; `tile_pixel_stream_calls=0`.
These are neither hardware input-to-photon measurements nor a 100 ms owner
acceptance result. No Legacy-removal or T-149 completion is claimed.

[Raw evidence](T-171-2026-11-16-native-export-fence-raw/) includes
[`summary.tsv`](T-171-2026-11-16-native-export-fence-raw/summary.tsv),
[`negative-control.log`](T-171-2026-11-16-native-export-fence-raw/negative-control.log)
and [`SHA256SUMS`](T-171-2026-11-16-native-export-fence-raw/SHA256SUMS).

## Reproduce

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cargo test --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --lib --config /mnt/data/work/t153-cargo-config.toml
cargo fmt --manifest-path native/drawing_brush/Cargo.toml --all --check
cargo clippy --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --all-targets --config /mnt/data/work/t153-cargo-config.toml -- -D warnings
cargo build --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --release --config /mnt/data/work/t153-cargo-config.toml
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path . --import --quit
"$GODOT" --headless --audio-driver Dummy --path . \
  --script res://tests/t171_native_subtree_export_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-171-2026-11-16-native-export-fence-raw && sha256sum -c SHA256SUMS)
```

## Remaining work

T-171 closes the unauthorized *detached export* window, including Copy,
without requiring Copy to perform Move's source-retirement operation. It
does not make host-owned detached history snapshots Rust-owned, turn all
raster producers into native transactions, or provide a general atomic
multi-document commit across arbitrary host callbacks. Parent T-148 remains
In Progress and T-149 stays Blocked; T-095 manual acceptance is unchanged.
