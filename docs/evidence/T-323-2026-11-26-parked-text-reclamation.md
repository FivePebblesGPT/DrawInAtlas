# T-323 abandoned parked text raster sources

2026-11-26, branch `sprint/2026-11-25`. Verified PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`; resumed local T-322 at `e64b6404`.
Pinned offline Godot 4.8.beta4.official.b070e63b1 and Rust 1.99.1.

## Fail-first and correction

The initial native Godot witness failed 10 of 41 checks before the code change:
metadata and selection branches left glyph reservations, source identities and
blank paint authorizations after abandoning conversion Redo. The initial fixed
run passed 35/35 (the pre-fix fixture counted each leaked identity separately).
The expanded fixture uses stable assertion counts, checks actual resident
memory reduction, semantic-layer removal/Undo, unchanged native revision,
unrelated pending edits and token retention, hidden RGB, failed release,
corrupted retained snapshots and subsequent conversion Undo/Redo.

Local redo truncation now releases abandoned content tokens in reverse order,
then reclaims checked empty creations and parked glyph conversions. The host
requires a complete retained raster projection matching native RGBA8, with a
semantic or absent live layer. Rust independently verifies exact revision,
parking, complete resident/authorized cardinality and absence of retained
raster history references. Reclamation releases no live or unrelated tiles;
it does not advance revision or cancel an unrelated pending edit. If the
snapshot is malformed or the owner stale, reclamation fails closed and the
unused source can remain resident.

## Verification

- `make test-parked-text-reclamation` completed both project imports and native
  readiness, final T-323 77/77, and 45/45 Rust unit tests (exit 0).
- Adjacent clean headless runs: T-313 32/32, T-318 52/52, T-321 64/64,
  T-319 51/51, T-320 46/46, T-177 89/89, native tile contract 312/312,
  binary codec 307/307, T-322 142/142, Atlas native history 43/43,
  Drawing history 101/101. All exit zero.
- Python T-211/T-228/T-287 CI contracts 29/29, explicit typing and ticket
  validation passed. CI and ordinary Make test target include the new witness.
- An intermediate run following staging lacked imported font resources;
  re-importing both projects corrected that environmental failure.

## Boundaries

Only local abandoned conversion lifetime is changed. General applied removed
subtree reclamation, external structural command ownership, full native
consolidation, hardware latency, Windows and hosted CI are not closed.
No UI appearance change. T-148 remains In Progress, T-250 Manual Review.
