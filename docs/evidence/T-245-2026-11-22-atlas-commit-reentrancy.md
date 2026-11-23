# T-245 — Atlas command append is atomic across Drawing publication callbacks

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Environment:** bundled Godot 4.8 beta3, Linux x86-64, compiled native Rust
GDExtension; headless standalone and Atlas scripts, not hosted CI or owner hardware.

## Failure and fix

`AtlasEditHistory.commit_drawing()` checked campaign/document eligibility and
then synchronously committed the session. The document's lazy source callbacks
could invoke **another Atlas timeline operation** while the current native
raster command had not yet been appended. Reentrancy could mutate the timeline
cursor/redo branch, saved/dirty identifiers, grid commands, or campaign owner,
or perform a nested commit that consumed the pending session first.

`_committing_drawing` reserves the timeline through `session.commit()`,
`_append_applied`, and `_remember_revisions`. Mutating host entry points refuse
reentrancy during this window. A failing publication releases the reservation
without recording an Atlas command. The synchronous `changed` signal is inside
the reserved boundary, preventing listeners from inserting a second command or
marking an incomplete transaction saved.

| Test | Previous code | With T-245 |
| --- | --- | --- |
| `tests/t245_atlas_commit_reentrancy.gd` | `T245_ATLAS_COMMIT_RESULT checks=119 failures=22` | `T245_ATLAS_COMMIT_PASSED checks=126 failures=0` |

The test forces callbacks **inside** `_publish_edit` source resolution (not
during initial staging), covers nested commit, Atlas command, selection,
Undo/Redo, dirty/save marks, reset and synchronous signal listeners, then
verifies exactly one native-backed Atlas command, signed hidden RGB and exact
Undo/Redo. A separate rejected-publication fixture verifies the timeline
reservation releases on failure.

## Neighboring checks

- T-244 real Atlas pending-session ownership: **18/18**.
- T-242 Atlas read-only owner: **18/18**.
- T-148 Atlas native history: **43/43**.
- Atlas global history smoke: **101/101**.
- T-148 reentrant native history: **26/26**; history payload: **20/20**.
- T-241 host ownership: **29/29**; T-243 native active owner: **40/40**.
- T-244 standalone pending sessions: **50/50**.
- T-239 native token ordering: **36/36**.
- Native tile ABI: **312/312**.

**Not claimed:** hosted exact-head CI, arbitrary externally mutated campaign
state inside callbacks, complete native-owned command lifecycle, owner hardware
acceptance, or closure of T-148/T-149.
