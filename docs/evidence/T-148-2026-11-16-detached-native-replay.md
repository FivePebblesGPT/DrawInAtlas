# T-148 checkpoint — native authority during in-sync detached history replay

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148 **In Progress** · **GitHub baseline:** `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa` (17 local commits before this checkpoint). T-149 remains Blocked; T-095 stays manual owner-gated.

## Defect and bounded change

A native Brush event whose Rust history token was evicted, invalidated by another timeline operation, or detached could still Undo/Redo through `DrawingDelta`'s whole-tile before/after snapshots. When the persistent native store was **still on the exact current document revision**, the old Godot-only fallback published the detached RGBA8 bytes and advanced only the document revision. The Rust canonical tiles stayed unchanged. Subsequent Brush gestures therefore needed a checked destructive rebase; an observer inspecting the already-attached Rust store could see divergent tile bytes/revision in the meantime.

`DrawingNativeTiles.replay_detached_history(layer, revision, tiles)` now accepts one bounded (1–128) batch of signed tile IDs and exact expected/replacement `PackedByteArray` RGBA8 spans. Rust validates the complete transaction before changing any tile: revision and quiescence, layer editability/parking, canonical coordinates, unique IDs, stride/length, exact source bytes including transparent hidden RGB, changed data, and bounded memory. Empty packed bytes represent an all-zero source or replacement tile. The success path updates canonical tile generations and the *single* document/native revision, leaving unrelated source untouched. It clears native Undo/Redo tokens that no longer represent the host's detached chronology; it does **not** synthesize a token without a matching document command.

`DrawingDocument._replay_native_tile_delta` still validates *all* lazy providers, source identities, snapshots, permissions and the shared revision before the irreversible native call. Live valid tokens continue to use the stricter `replay_history_token` full-event parity check. Only an unavailable token **with an in-sync native store** uses the new native detached path. After native acceptance Godot installs only the already-prepared display/save projection and updates native-source identities, with no further provider invocation. When the native store is absent or has a different revision, the old Godot-only detached fallback still exists; this ticket does **not** claim universal history ownership or serialized native tokens.

## Verification and observed limits

Real Rust/Godot 4.8 beta 3 binaries were compiled offline using the pinned bundle. Every listed Godot process exited with code 0 and its exact zero-failure marker; the new witness was also checked with the strict log parser.

| Witness | Result |
| --- | ---: |
| Rust unit tests, including atomic multi-tile detached replay and stale/duplicate/malformed source rejection | **25 passed** |
| rustfmt, strict Clippy (`-D warnings`), release GDExtension | Passed |
| New real-native detached history regression | **21 checks passed** |
| Native payload guard; reentrant lazy-source replay | 20 / 25 checks passed |
| Atlas native global history; Object native lifecycle | 43 / 38 checks passed |
| Direct native 512² tile store; publication; external adoption; persistent document | 312 / 55 / 28 / 44 checks passed |
| Live graphical Canvas | 46 checks, zero pixel-stream calls |
| Real NativeHard 96px 512² full canvas | Passed; **763.034ms** single-run software input→postdraw |
| Real Hokusai 96px 512² full canvas | Passed; **610.577ms** single-run software input→postdraw |
| Ticket/Kanban validator | 152 tickets valid |

The new Godot regression makes **two real NativeHard strokes**, verifies the second Undo through a live Rust token, replaces the earlier token with an unavailable positive ID, and traverses detached Undo/Redo of both strokes through the *same attached Rust tile store*. Every resulting RGBA8 tile, transparent hidden RGB and shared revision agree; unrelated history tokens are invalidated, and a new Brush stroke immediately records a fresh Rust token without source reimport. A malformed detached FFI source is rejected without changing either revision. The Rust unit test independently rejects malformed second tiles, wrong sources, duplicate IDs and stale revisions before mutation and validates a blank replacement with signed coordinates beyond 32-bit range.

**Performance caveat:** Neither one-off 96px witness met the proposed 100ms software target. These are not physical input-to-photon measurements, and this checkpoint makes no measured performance-improvement claim.

## Reproduce

```bash
cd /mnt/data/DrawInAtlas.sprint_2026-11-15
source /mnt/data/dev-bundle/setup-rust-env.sh
(cd native/drawing_brush && cargo test --offline --locked --lib && cargo fmt --all --check && \
  cargo clippy --offline --locked --all-targets -- -D warnings && cargo build --offline --locked --release)
# Copy the release .so to the two ignored root / drawing addon native/bin directories.
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/dev-bundle/run-godot-headless.sh --path . \
  --script res://tests/t148_detached_native_replay.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-148-2026-11-16-detached-native-raw && sha256sum -c SHA256SUMS)
```

Raw independent process logs and SHA-256 checksums are in [the evidence directory](T-148-2026-11-16-detached-native-raw/SHA256SUMS).

**Remaining acceptance:** Godot-owned detached history snapshots and absent/stale-store replay, plus other raster producers, still prevent T-148 from being universally native-owned. T-148 stays **In Progress**; T-149 remains Blocked and T-095 owner review is unchanged.
