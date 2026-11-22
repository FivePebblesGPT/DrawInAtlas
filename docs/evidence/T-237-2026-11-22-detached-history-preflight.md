# T-237 — Detached native tile-history payload preflight

**Date:** 2026-11-22

**Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`

**Remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146` (16 local commits preceding this task).

## Failure and fix

The old `_replay_native_tile_delta` validated each tile key and RGBA8 buffer
just before `_resolve_chunk` for that tile. A malformed *later* key/buffer
could trigger earlier lazy-source effects. A source callback could also
change a subsequent delta entry before the code copied it, making the replay
use bytes different from the original requested snapshot.

The new two-phase path checks and freezes **all** before/after tiles before
any callback. Subsequent work reads only frozen buffers; the final guard
compares full live delta membership, bytes, layer, stride and native token,
in addition to the prior source-byte/revision checks. Invalid initial keys,
lengths and mismatched sets fail without any provider invocation; reentrant
delta changes reject with `STALE_PIXEL` before native history consumption.
The preexisting 128-tile/256 MiB limit remains in force.

## Fail-first and positive test

The same final `drawing/tests/t237_detached_tile_replay_preflight.gd`
was run against the original `HEAD:addons/drawing/document.gd` temporarily
staged **only** in `drawing/addons/drawing/document.gd`:

- Old implementation: `T237_HISTORY_PREFLIGHT_RESULT checks=40 failures=24` (exit 1).
- Fixed implementation: `T237_HISTORY_PREFLIGHT_PASSED checks=40 failures=0` (exit 0).

The test covers invalid later keys, missing originals and malformed RGBA8;
changes to future expected/replacement bytes and key sets; edits to native
history token or stride; native-absent and already-attached store rejection;
and valid host-style detached Undo/Redo, signed alpha-zero hidden RGB,
byte-exact Rust tile agreement and portable Save/Open.

## Local regression results

| Test | Outcome |
| --- | --- |
| T-237 fail-first / after fix | 24 failures before; 40/40 after |
| T-148 native history reentrant replay | 26/26 |
| T-148 detached native bootstrap | 34/34 |
| T-148 detached native replay | 21/21 |
| T-148 native history payload guard | 20/20 |
| T-229 native history memory budget | 18/18 |
| T-230 detached legacy pixel bootstrap | 33/33 |
| T-156 historical pixel replay | 38/38 |
| T-148 tile ABI | 312/312 |
| T-148 tile publication | 56/56 |
| T-148 Atlas native tile history | 43/43 |
| T-235 and T-236 direct publication guards | 34/34; 35/35 |
| T-233 first direct pixel-map bootstrap | 37/37 |
| Rust unit tests (bundled toolchain, offline) | 36/36 |
| Native-X11 Canvas tile cutover | 46/46, zero per-pixel tile-stream FFI calls |
| Required-native CI source contract | 11/11 |
| Ticket-store validation | 237 tickets valid |

Tests used the bundled Godot 4.8 beta 3 and the existing compiled native
extension. These are local software checks, not a claim of hosted CI, owner
hardware approval or complete host-history authority. T-148 remains In
Progress and T-149 Blocked.
