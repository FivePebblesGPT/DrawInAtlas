# T-326 transferred raster history between document visits

2026-11-26, `sprint/2026-11-25`; verified PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`, local parent `b806923a` (T-325).
Pinned Godot 4.8.beta4.official.b070e63b1 and bundled Rust toolchain.

## Fail-first and correction

The native two-document witness failed 9/83 checks before implementation:
Move retired original-layer tokens, undoing Move/Copy retired destination
paint Redo, and repeated moves lost both visits' original native events.
Detached tile replay could produce the right pixels while invalidating the
actual Rust tokens. Corrected initial run 83/83, expanded final run 96/96.

A reversible external transfer now releases affected resident tiles,
authorizations and editability but retains the document's native paint
history. Explicit transfer re-admission permits history-referenced IDs
only in the absence of live/parked native sources. The union of materialized
source coordinates and retained history coordinates is bounded and admitted
as one native revision. Coordinates absent in the detached snapshot are
explicitly authorized blank RGBA8; native token replay still checks exact
source and target bytes. The native store rejects omitted history coordinates,
invalid descriptors, stale/active owners and live or parked overlap. Native
history matching and direct stack replay reject absent sources. Ordinary
creation/import refuses identity reuse while native history reserves the ID.
Existing command-owner exact-token cleanup handles discarded transfer branches
and reset; no independent parked-source tombstone is introduced.

## Verification

- `make test-transfer-source-history TOOLCHAIN=bundle BUNDLE=...` exit 0:
  both project imports/native readiness, Godot witness 96/96 and 47/47 Rust
  tests, including independent native transfer release/re-admission rejection.
- Adjacent Atlas: T-170 30/30, T-172 33/33, T-325 190/190, T-148 Atlas
  history 43/43, T-322 142/142, T-245 126/126, T-246 206/206,
  T-247 259/259, Drawing chronological history 101/101.
- Adjacent Drawing: T-175 27/27, T-179 62/62, T-314 35/35, T-324 96/96,
  T-148 native tiles 312/312, T-321 64/64, T-310 binary 307/307.
  All sixteen processes exited zero without failure markers.
- Explicit typing (649 scripts, 33 skill documents); 29 Python CI contract
  checks and 17 subtests; ticket-store validation and diff check.
- Initial Rust string conversion compile error was corrected. An early
  Godot invocation overlapped extension binary replacement and crashed;
  subsequent post-build direct run, both project imports, full Make target
  and adjacent processes passed. No runtime crash reproduced after staging.

## Boundaries

This is explicit host-coordinated source re-admission, not a single native
transaction across both documents. Structural source snapshots remain in the
host; detached fallback can still be necessary if native history is evicted
or the store is replaced. The existing 128-layer, 8192-descriptor and
256 MiB native admission limits include retained history and reauthorized
blank sources. A returning large source can be refused at that boundary.
No appearance changes, new storage format, Windows, physical performance,
or hosted CI verification. T-148 remains In Progress, T-250 Manual Review.
