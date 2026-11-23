# T-238 — Native Brush source-byte reentrancy guard

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Last verified remote PR #22 head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Linux x86-64, bundled Godot 4.8 beta3, existing compiled Rust extension.

## Reproduction and correction

A simulated reentrant lazy provider changes an **earlier** resident tile's
hidden/visible RGBA8 while resolving the second Brush source. Both sources
retain their object identities, the document revision remains unchanged and
the caller's image/dirty/source dictionaries are untouched. Previously,
`_publish_native_tile_edit` returned a valid-looking dry-run and stale
`before_tiles`, because its final validation only compared object identities.
This affects the native-absent preparation case and an already-attached Rust
owner; it is not necessarily detectable by descriptor revalidation.

The native Brush preflight now compares the full current bytes of every
resolved source to the `before_bytes` already captured during staging.
It returns `STALE_PIXEL` before yielding a prepared publication if a later
callback changed an earlier source. The stored source snapshots already
belong to the reversible tile-delta envelope: this guard adds a live read and
comparison but **does not retain a second full-size source buffer set**.
Provider-originated changes themselves are not rolled back.

The same final `drawing/tests/t238_brush_source_reentrancy.gd` was executed
against the previous document source temporarily staged in the Drawing app
and then restored to the fixed implementation:

- Previous source: `T238_BRUSH_SOURCE_RESULT checks=18 failures=2`.
- Fixed source: `T238_BRUSH_SOURCE_PASSED checks=18 failures=0`.

The fixture verifies rejected native-absent and attached-store mutations,
unchanged document/history/Rust revision, no publication of either requested
Brush pixel, and valid two-tile dry-run/installation retaining exact
alpha-zero hidden RGB. The provider's own pixel mutation is explicitly not
claimed to be undone.

## Local regression validation

| Check | Result |
| --- | --- |
| T-238 fail-first / after fix | 2 expected failures / 18 of 18 pass |
| T-234 native publication preflight | 32/32 pass |
| T-235 tile-patch source guard | 34/34 pass |
| T-236 direct pixel-map source guard | 35/35 pass |
| T-237 detached history payload preflight | 40/40 pass |
| T-148 document tile publication | 56/56 pass |
| T-148 native tiles ABI | 312/312 pass |
| T-148 persistent native document | 44/44 pass |
| T-148 external raster adoption | 28/28 pass |
| T-232 first tile-local native bootstrap | 34/34 pass |
| T-233 first pixel-map native bootstrap | 37/37 pass |
| T-148 Atlas native history | 43/43 pass |
| T-148 native history reentrant replay | 26/26 pass |
| T-148 native history payload guard | 20/20 pass |
| T-148 detached native bootstrap | 34/34 pass |
| T-148 native-X11 Canvas | 46/46 pass; `tile_pixel_stream_calls=0` |
| Rust unit tests (bundled offline toolchain) | 36/36 pass |
| Required-native CI source contracts | 12/12 pass |
| Ticket-store validator and workflow YAML parse | 238 tickets valid; pass |

Local testing uses software X11 and the bundled toolchain. The new required
CI assertion was added but **hosted CI on a pushed commit has not run**.
No owner hardware responsiveness, manual UX acceptance or universal
host-owned native history lifetime is claimed. T-148 remains In Progress,
T-149 Blocked and existing owner-review gates unchanged.
