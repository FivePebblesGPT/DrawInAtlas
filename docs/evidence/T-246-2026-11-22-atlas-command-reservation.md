# T-246 — Non-Drawing Atlas command reservation

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Environment:** bundled Godot 4.8 beta3 Linux x86-64, root Atlas project,
headless script tests with native extension present. Hosted CI is not verified.

## Reproduction and correction

The host history protected Drawing `commit_drawing()` callbacks (T-245) but
ordinary Atlas `execute()`, asset-rebind and transfer operations could invoke
synchronous user/context callbacks before recording their commands. Reentry
could consume a redo branch, insert a second command, mutate savepoint and
external revision, or clear the whole history before appending the first.

`_executing_command` now reserves every host mutation entry point through
context capture, `apply()`, append, signal emission and revision bookkeeping;
`_timeline_reserved()` combines that with the existing Drawing reservation.
Rejection releases the flag. Guards also prevent replay-triggered checkpoint
or reset changes.

| Test | Old `history.gd` | New `history.gd` |
| --- | --- | --- |
| `tests/t246_atlas_command_reservation.gd` | `T246_ATLAS_COMMAND_RESULT checks=206 failures=60` | `T246_ATLAS_COMMAND_PASSED checks=206 failures=0` |

The fixture covers 21 combinations of context-provider, command-apply and
`changed`-signal callbacks with execute, Undo, Redo, reset, savepoint,
external mutation and selection recording. It checks one canonical command,
replay parity and callback invocation. Additional cases exercise Save As
rebind, independent cross-document copy, and reservation release after a
rejected host command.

## Neighboring local validation

- T-245 Atlas Drawing commit reentrancy: **126/126**.
- Atlas global history smoke: **101/101**.
- T-244 Atlas pending-session ownership: **18/18**.
- T-242 Atlas read-only history ownership: **18/18**.
- T-148 Atlas native history: **43/43**.
- T-170 cross-document move: **30/30**.
- T-172 transfer undo preflight: **30/30**.
- T-171 subtree export preflight: **33/33**.
- T-148 history reentrancy and payload guard: **26/26** and **20/20**.

No claim of hosted GitHub required-CI success, physical owner review, full
native authority, or protection against direct campaign/model mutations.
