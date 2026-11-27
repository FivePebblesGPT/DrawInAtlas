# T-322 native history reclamation

Date: 2026-11-26. Branch `sprint/2026-11-25`; verified PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`. The original checkout archive
was restored and all 20 patches in the T-321 mailbox applied; local replayed
commit IDs differ from the preceding session. The same remote base and patch
sequence are retained. The pinned offline bundle verified Godot
4.8.beta4.official.b070e63b1 and Rust 1.99.1.

## Fail-first / correction

The new `tests/t322_history_reclamation.gd` ran before code changes: 111 checks,
10 failures. Grid, selection, external dirty-state and reset paths left future
native tokens allocated across two documents; reset also left an applied token.
Local selection-only branching had the same leak. No raster revision occurs
for these branches, so clearing Redo only during a raster mutation is insufficient.

Rust's `forget_history_token` validates exact revision, layer, token and stack.
Local redo truncation releases content tokens alongside the existing empty
creation cleanup. Atlas's timeline releases exactly discarded Drawing commands
across documents, including all commands at explicit reset. The timeline is
reserved throughout cleanup and changed notification, including selection and
external-change entry points. Stack-tail order avoids needless scanning/shifting
in the common case. It does not clear unrelated history or source authorization.

The corrected initial run passed 111/111; the expanded witness passed 142/142
on the first implementation build plus the final script changes. Final rebuilt Godot witness and both imports passed again (142/142). The new checks include stale native
revision rejection and callbacks attempting nested Undo/Redo/reset. The native
unit witness independently checks incorrect revision, token, layer and stack,
source bytes, memory release, active edit reservation and remaining replay.

## Final verification

`make test-history-reclamation` completed both imports and the Godot witness
(142/142) on the rebuilt extension. The first Rust test compile exposed a
signed/unsigned fixture revision mismatch; the next run exposed a transparent
brush sample that produced no actual change. Both corrections were limited to
the new unit-test fixture. The final direct `tools/build_native_brush.sh --test`
through the verified bundle passed all 44 Rust tests. The Make wrapper was not
rerun after the final test-only color correction.

Adjacent headless suites (all exit zero, no script errors): T-148 Atlas history
43/43, T-245 126/126, T-246 206/206, T-247 259/259, T-248 70/70, T-249 84/84,
Drawing history 101/101, T-148 reentrant replay 26/26, T-321 64/64, native tile
contract 312/312. CI workflow and native contract Python suites: 29/29
(T-287, T-211, T-228). Explicit types and ticket validation passed. Hosted
CI was not run against these unpublished commits.

## Boundaries

This releases only known abandoned raster command tokens. If a native owner
is stale, it fails closed; detached/absent tokens need no action. A stale owner's
buffers may remain until it is recovered or destroyed. Parked structural text
and removed-layer snapshots, arbitrary external ownership violations, full
native consolidation, physical performance, Windows and hosted CI are not closed.
No UI appearance changes. T-250 remains Manual Review.
