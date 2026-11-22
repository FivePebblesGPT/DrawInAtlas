# T-236 — Direct pixel-map preflight and reentrant source protection

**Date:** 2026-11-22

**Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`
**Remote baseline:** PR #22 `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146` (15 local commits before T-236).

## Failure and implementation

`_publish_edit` used to validate direct global-pixel originals/replacements
*while* resolving individual storage tiles. A malformed later entry could
invoke a previous lazy source. A reentrant provider could then edit the
caller-owned `before` or `after` maps or change a previously verified resident
tile *in place* without affecting its identity or document revision. The
original final source-identity guard could permit publication of a delta that
disagreed with the session's original validated inputs.

T-236 first validates all changed canonical coordinates, corresponding
originals, straight RGBA8 values and native projection/transfer budgets before
any provider call. It freezes the two caller-owned maps and resolves each
source tile once, retaining a canonical SHA-256 tile-byte fingerprint. After
all callbacks, it compares the original maps and the previously resolved
source bytes again, *before* Rust adoption or Godot publication. Only the
frozen maps feed staging/history; failures advance no document revision,
create no history or new native store and publish none of the requested edits.
The provider's own unauthorised mutation of its source object is **not**
undone by this layer.

## Unchanged-source reproduction

With the same compiled Godot 4.8 beta 3 Hokusai native extension, the final
`drawing/tests/t236_pixel_map_preflight.gd` was run against the prior
`HEAD:addons/drawing/document.gd` temporarily staged **only in the generated
Drawing project**. The exact negative control printed:

`T236_PIXEL_PREFLIGHT_RESULT checks=35 failures=16` (exit 1).

With the edited shared source restaged, the same script printed:

`T236_PIXEL_PREFLIGHT_PASSED checks=35 failures=0` (exit 0).

Cases include malformed later originals/RGBA8, before-map and after-map
mutation, a later replacement changing during a callback, and in-place bytes
on an earlier source tile. Positive controls verify real native authority,
alpha-zero hidden RGB, reversible local/Atlas detached history, untracked
publication, Save/Open and byte-for-byte source/native tile parity.

## Neighboring local regression evidence

| Test | Outcome |
| --- | --- |
| T-236 direct pixel-map fail-first/final | 16/35 failed before; 35/35 after |
| T-068 old pixel-map publication smoke | 30/30 after updating native-history oracle and synthetic signed stride |
| T-100 sparse native/oracle publication | 197/197 |
| T-148 native tile publication | 56/56 |
| T-148 native tile ABI | 312/312 |
| T-148 external adoption | 28/28 |
| T-148 persistent store | 44/44 |
| T-165 revision fence | 51/51 |
| T-232 tile ownership bootstrap | 34/34 |
| T-233 pixel-map ownership bootstrap | 37/37 |
| T-234 Brush publication preflight | 32/32 |
| T-235 tile-local publication preflight | 34/34 |
| T-148 Atlas native history | 43/43 |
| Native-X11 Canvas cutover | 46/46, zero per-pixel tile stream FFI calls |
| Compiled Rust native tests | 36/36 |
| Required-native CI source contract | 10/10 |

The T-068 original fixture was stale after T-233: it expected per-pixel
`DrawingDelta.after` even though current native history returns a full-tile
delta, and tested an over-native-projection signed coordinate with a native
stride. The original 30 assertions remain; native-history semantics are
checked for supported stride 16, and the historical 64-bit coordinate oracle
uses synthetic stride 8, which is outside Rust's supported [16, 2048] range.
This does **not** weaken native signed bounds.

All tests above were executed locally; no hosted PR-head CI, physical
owner-hardware measurement, release-template export or manual approval is
claimed. T-148, T-149 and owner-review/portability gates retain their states.
