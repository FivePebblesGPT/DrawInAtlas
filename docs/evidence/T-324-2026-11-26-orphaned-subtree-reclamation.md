# T-324 applied orphaned subtree reclamation

2026-11-26, `sprint/2026-11-25`; PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`, local parent `f5842cab` (T-323).
Pinned offline Godot 4.8.beta4.official.b070e63b1 and Rust 1.99.1.

## Fail-first and implementation

The original document code failed 17/47 checks in the corrected negative
control fixture: permanently removing a group after its nested raster and
inner group had been removed in recorded commands left the raster parked,
its native paint token and projection identity retained, and unusable
commands obstructing otherwise valid Undo. The check covers both a group
with no remaining live raster and one with a live raster sibling. The first
fixture run had a secondary null-result cast on failed ID reuse; the cleaned
negative control has no script errors. The fixed initial suite passed 47/47.

Permanent local removal scans applied removal snapshots newest-first to find
absent descendants whose parent will no longer be restorable. It validates
hierarchy and native source bytes without loading pending sources. A single
`retire_orphaned_layers_revision` call checks current revision, no active
transaction, unique live/parked IDs, lifecycle and complete resident/authorized
cardinality for parked sources, then retires both sets and their native
history. The old direct retirement API still rejects parked IDs. Godot erases
the affected tree and projection identities and installs a prebuilt surviving
applied history. The old redo tail is released first, so an unrelated future
creation's parked source does not leak. Recorded ancestor deletion still
parks instead of retiring and retains exact signed/hidden RGB through replay.

## Verification

- `make test-orphaned-subtree-reclamation TOOLCHAIN=bundle BUNDLE=...` exit 0;
  both project imports and native readiness, 96/96 Godot checks, 46/46 Rust
  unit tests, including independent mixed retirement atomicity.
- Adjacent headless Drawing: unrecorded retire 34/34, T-168 30/30, T-176
  121/121, T-177 89/89, T-179 62/62, T-319 51/51, T-320 46/46,
  T-321 64/64, T-323 77/77, T-316 58/58 and T-310 binary 307/307.
- Adjacent Atlas: T-148 native history 43/43, T-172 transfer preflight
  33/33, T-322 142/142 and Drawing chronology 101/101. All 15 adjacent
  processes exited zero without failure markers.
- Explicit typing (647 scripts, 33 skill documents), 29 Python CI contract
  checks (T-211/T-228/T-287) and ticket-store validation passed. New witness
  is wired into ordinary Make test and required fast desktop CI.

## Boundaries

Local unrecorded ancestor removal only when there are orphaned parked native
sources. Combined live/parked retirement is bounded to 128 raster IDs.
Snapshot parity is checked in the host before the synchronous native call;
Rust independently checks counts and lifecycle. Unreachable semantic-only
history without parked raster sources and external structural command
lifetime are not generalized. A stale, malformed or ambiguous retained
snapshot can reject permanent removal instead of silently discarding data.
No UI appearance change. Hosted CI, Windows and physical performance remain
unverified. T-148 remains In Progress; T-250 remains Manual Review.
