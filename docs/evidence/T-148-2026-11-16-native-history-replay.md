# T-148 checkpoint — fail-closed native tile history replay after reentrant lazy sources

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148 **In Progress** · **Verified GitHub baseline before this turn:** `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa` (the previous 15 commits remain local). T-149 stays Blocked; T-095 retains its physical owner-review gate.

## Defect and fix

`DrawingDocument._replay_native_tile_delta()` resolves referenced RGBA8 source tiles before consuming a Rust history token or applying Atlas/local Undo/Redo. A lazy source provider can reenter the document during that preflight. Previously replay did not check the **final** document revision, editability, node identity, earlier source objects/bytes or caller-owned history snapshots after the callbacks. In the reproduced negative case, a provider locked the layer while the first Undo was loading its source; the old implementation accepted the replay and consumed the native token after the document authority had changed. A later provider can also replace an earlier checked source without changing the revision.

The new preflight captures the starting document revision and target node, validates canonical signed tile keys, safe coordinates, complete before/after key sets, a bound of 128 tiles, and exact RGBA8 buffer lengths **before** loading referenced sources. It then takes detached byte snapshots and resolves each source. Following **all** potentially reentrant calls, it checks revision, layer editability, node identity, absence of pending tile sources, every source object's identity, current source bytes, and both saved delta dictionaries. Only afterward can it call `DrawingNativeTiles.replay_history_token()` or install prebuilt whole-tile replacements. The normal top-of-stack Rust token path and the older/evicted detached byte fallback remain distinct; this checkpoint does **not** serialize Rust history or remove the fallback. No new per-painted-pixel Brush hot-path work was added.

## Regression and negative control

`tests/t148_native_history_reentrant_replay.gd` uses the real compiled extension for a native Brush on signed 64px storage tiles. **25 checks pass** with zero failures:

- A lazy callback locks the layer and advances the shared document/Rust revision. Undo fails with `STALE_REVISION` without consuming the local history cursor or Rust token; committed RGBA8 bytes survive, and unlock → Undo → Redo restores the exact source.
- In a separate two-tile detached replay, the **second** lazy provider substitutes the already verified **first** source without changing the revision. The complete final source check fails with `STALE_PIXEL`. Repairing the source permits a two-tile replay with exact RGBA8 bytes, including transparent hidden RGB and signed tile keys.
- A noncanonical tile key rejects before any provider executes, without touching source or native revision.

The negative-control run temporarily restored the **previous committed `document.gd`** while retaining the new test. It **exited 1 with 12 failed assertions**, including accepting an unauthorized Undo; see `negative-original-expected-failure.txt`. It is **not** counted as a passing process. The tested production file was restored immediately afterward and the passing new regression rerun.

## Adjacent verification (pinned Godot 4.8 beta3 / real native extension)

Independent Godot process return codes were checked. Existing `_RESULT` witnesses were verified to report their exact `failures=0` result; `_PASSED` markers were also validated with `tools/check_godot_model_log.py`. Raw logs and SHA-256 checksums are retained in [this evidence directory](T-148-2026-11-16-history-replay-raw/SHA256SUMS).

| Witness | Result |
| --- | --- |
| New reentrant native history replay | **25 checks, 0 failures** |
| Atlas native global history / Object native draft lifecycle | **43 / 38 checks, 0 failures** |
| Object asset / Atlas campaign bundle | **95 / 86 checks, 0 failures** |
| Persistent native document / external raster adoption | **44 / 28 checks, 0 failures** |
| Native tile bridge / document tile publication / metadata and structure | **312 / 55 / 61 checks, 0 failures** |
| Live X11 native-tile Canvas | **46 checks**, `tile_pixel_stream_calls=0` |
| 96px full-canvas NativeHard / Hokusai, explicit backend selected | **Both passed** source oracles, 262,144 source pixels |
| Offline Rust unit tests / rustfmt / strict Clippy | **23 passed / passed / passed** |
| Ticket-store validator | **152 tickets valid**; manual gates unchanged |

Single-run **software-rendered** 96px input-to-settled-postdraw timing: NativeHard **818.885 ms**, Hokusai **533.062 ms**. Both remain above the proposed 100ms target and neither measures physical input-to-photon latency. This change is a history-safety fix, not a performance optimization.

### Reproduction

```bash
cd /mnt/data/DrawInAtlas.sprint_2026-11-15
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64 \
  --headless --audio-driver Dummy --path . \
  --script res://tests/t148_native_history_reentrant_replay.gd
python3 tools/check_godot_model_log.py \
  docs/evidence/T-148-2026-11-16-history-replay-raw/root-t148_native_history_reentrant_replay.log \
  --marker T148_HISTORY_REENTRANT_PASSED
python3 tools/build_drawing_app.py --in-place
# Run root and standalone neighboring scripts using the process arguments in the raw evidence.
source /mnt/data/dev-bundle/setup-rust-env.sh
(cd native/drawing_brush && cargo test --offline --locked --lib && \
  cargo fmt --all --check && cargo clippy --offline --locked --all-targets -- -D warnings)
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-148-2026-11-16-history-replay-raw && sha256sum -c SHA256SUMS)
```

## Remaining T-148 acceptance

This protects the preflight-before-replay transaction boundary in both live-token and detached fallback paths. The detached fallback is still Godot-owned; native history is not yet universally authoritative for all producers, and source/history lifecycle tracing and full native persistence acceptance remain outstanding. **T-148 is not Done.**
