# T-327 checked host transfer publication

2026-11-26, `sprint/2026-11-25`; verified PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`, local parent `aeea990d` (T-326).
Pinned Godot 4.8.beta4.official.b070e63b1 and bundled native toolchain.

## Fail-first and correction

The original 44-check real-native fixture failed seven checks: locked and
hidden copied roots could not Undo/Redo, ordered Move Undo consumed a second
revision, an exhausted semantic source dirtied the destination despite failure,
and a lazy provider's destination revision change was accepted. Initial
corrected run 46/46; expanded final run 91/91.

Host transfer capture records both revisions before lazy export and verifies
the destination source epoch. The publication fence compares the outgoing
hierarchy, materialized tile set, canonical RGBA8 and retained native sources
without invoking providers. A late pending source or altered retained bytes
reject before the other document changes. Structural revision headroom is
checked, including a native semantic-only source at the signed ceiling.

Move uses a single detached logical snapshot and checks the destination root
parent separately. Original sibling order is installed in the import
revision, so Move Undo at the last available revision succeeds. Copy captures
its remapped detached tree before publication. The fault-injection destination
rejects any live export: neither Move nor Copy calls it after import, including
replay. Copy Undo can remove a protected imported root after verifying the
retained snapshot, native sources and editable parent; ordinary removal
continues to refuse locked/hidden roots. Snapshot mutation does not alias
live bytes, and restoring the exact snapshot allows retry. Native tokens
remain with their original owners as in T-326.

## Verification

- `make test-transfer-publication-boundary TOOLCHAIN=bundle BUNDLE=/tmp/dia-toolchain`
  exit 0 after final restaging of both projects; exact 91/91 native-backed
  regression and required extension readiness. No Rust changes or new ABI.
- Adjacent Atlas: T-170 30/30, T-171 33/33, T-172 33/33, T-325 190/190,
  T-326 96/96, T-148 Atlas history 43/43, T-322 142/142, T-245 126/126,
  T-246 206/206, T-247 259/259, Drawing chronological history 101/101.
- Adjacent Drawing: T-175 27/27, T-179 62/62, T-314 35/35, T-324 96/96,
  T-148 native tile contract 312/312, T-321 64/64, T-310 binary 307/307.
  All eighteen processes exited zero without failure markers.
- Explicit typing: 650 scripts and 33 skill documents. Python CI contract
  checks (`test_godot_ci_order`, `test_godot_ci_fail_late`,
  `test_t228_fast_ci_contract`, `test_t211_native_ci_contract`): 35/35.
  Ticket-store validation: 327 tickets. Diff check clean.

## Boundaries

This is checked host-coordinated publication, not one atomic Rust transaction
across two independent stores. Unexpected internal failure still takes the
defensive compensating path, and callbacks during source capture can have
independent side effects which are not rolled back. A changed or evicted
source at preparation/application boundary requires re-preparation. Copy Redo
trusts its independently retained snapshot while the copy is absent. The
existing bounded native admission limits and other T-148 acceptance criteria
remain open. No new UI appearance, physical hardware, Windows or hosted CI
verification. Local LFS unavailable; stage only the explicit source/docs/test
changes, not the hydrated existing assets. T-148 In Progress; T-250 Manual Review.
