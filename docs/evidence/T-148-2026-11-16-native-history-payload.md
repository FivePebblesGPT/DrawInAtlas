# T-148 checkpoint — atomic Rust verification of detached history payloads

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148 **In Progress** · **GitHub branch head before work:** `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa` (16 local sprint commits already ahead). Manual T-095 remains owner-gated; T-149 stays Blocked.

## Defect and change

The earlier history-replay preflight compared the *source* against the detached `DrawingDelta` and guarded against reentrant lazy callbacks. However, `replay_history_token(token, revision, undo)` took **only** a token: Rust would replay the correct canonical `History.before/after` while Godot independently installed the **caller-controlled** `delta.before_tiles/after_tiles`. Changing a valid-length **replacement** tile in a local/Atlas history payload left the expected source untouched, so all previous preflight checks could succeed and produce divergent Rust and Godot pixels after token consumption.

The Rust `replay_history_token` ABI now also requires the owning layer and a bounded (1–128) array of `{tile_x, tile_y, expected, replacement}` packed RGBA8 spans. In the **same native call before mutation**, it compares the complete, unique signed tile-ID set with the top token's original Rust history event in the requested Undo/Redo direction, validates byte lengths/blank-tile semantics and exact before/after bytes (including hidden RGB), and checks that each currently canonical Rust tile still equals that event's expected source. Any discrepancy returns an error **without consuming a token, changing a revision or installing any tile**. On success Rust performs the original atomic token replay; Godot installs its already-detached matching buffers. History snapshots are not converted to per-pixel maps.

`has_history_token` remains only a cheap top-of-stack probe, **not** publication authorization. The full payload comparison is mandatory for the native-token path. Evicted or detached snapshot fallback still resides in GDScript and is **not** fixed by this checkpoint. The changed ABI is intentionally breaking for pre-release callers.

## Tests and reproducibility

The real Godot 4.8 beta3 / Rust GDExtension regression `tests/t148_native_history_payload_guard.gd` passes **20 checks**:

- One real NativeHard stroke crosses signed 64px tile boundaries, retaining transparent hidden RGB and recording a single two-tile Rust history event.
- Replacing the caller's Undo target bytes with a different, correctly sized image rejects with `NATIVE_HISTORY` without changing either store/revision, any source tile, or either history cursor. Restoring the payload permits exact Undo.
- A correctly sized but altered Redo target also fails atomically; repairing it permits byte-identical Redo. The local cursor, Rust Undo/Redo token counts, and shared revision agree throughout.

A new Rust unit test checks two-tile history including large signed coordinates, concealed RGB, duplicate/missing tiles, wrong layer/direction, altered expected/target bytes and directly tampered Rust canonical source. The rejected cases do not advance native history or revision. **24 Rust unit tests pass**, strict Clippy and rustfmt pass, and the release GDExtension compiles.

Neighboring independent Godot processes passed (exit 0 and exact `failures=0` markers):

| Witness | Checks |
| --- | ---: |
| New real-native history payload guard | **20** |
| Reentrant lazy-source history guard | 25 |
| Atlas native global history / Object native lifecycle | 43 / 38 |
| Direct Rust tile bridge / tile publication | 312 / 55 |
| External raster adoption / persistent native document | 28 / 44 |
| Metadata and structure history | 61 |
| Live software-X11 native Canvas | 46, `tile_pixel_stream_calls=0` |
| NativeHard / Hokusai 96px full-canvas witnesses | Both passed |

The single-run software-rendered 96px input-to-postdraw results were **721.894ms NativeHard** and **687.063ms Hokusai**, above the proposed 100ms target. They are not physical input-to-photon measurements and are not controlled performance improvement evidence.

The exact independent root/standalone/X11/Rust process logs and hashes are in [the raw log directory](T-148-2026-11-16-history-payload-raw/SHA256SUMS). The two 96px markers, the new payload-guard marker and the old reentrant replay marker were also validated by `tools/check_godot_model_log.py` (the native tile-bridge marker passed the same strict check).

```bash
cd /mnt/data/DrawInAtlas.sprint_2026-11-15
source /mnt/data/dev-bundle/setup-rust-env.sh
(cd native/drawing_brush && cargo test --offline --locked --lib && \
  cargo fmt --all --check && cargo clippy --offline --locked --all-targets -- -D warnings && \
  cargo build --offline --locked --release)
# Copy the built libdrawing_brush.so into addons/drawing/native/bin/ (ignored binary).
GODOT=/mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --audio-driver Dummy --path . \
  --script res://tests/t148_native_history_payload_guard.gd
python3 tools/build_drawing_app.py --in-place
"$GODOT" --headless --audio-driver Dummy --editor --path drawing --import --quit
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t148_native_tiles_contract.gd
# X11 witnesses used xvfb-run, Dummy audio and explicit NativeHard/Hokusai env.
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-148-2026-11-16-history-payload-raw && sha256sum -c SHA256SUMS)
```

**Remaining acceptance:** native history eviction/detachment still uses a Godot snapshot fallback; unbridged raster producers and universal source/history ownership remain. T-148 stays **In Progress**; T-149 stays Blocked and T-095 owner review remains open.
