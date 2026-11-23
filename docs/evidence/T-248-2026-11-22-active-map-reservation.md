# T-248 — Atlas active-map reservation

**Date:** 2026-11-22. **PR:** #22, branch
`sprint/2026-11-20-selection-dock-colors-brushes`.
**Verified remote baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Environment:** supplied Linux Godot 4.8 beta 3, project-root headless
scripts and native extension. This is local software evidence, **not** hosted
CI or physical owner approval.

## Regression and fix

The history timeline already blocked nested `execute`, `undo`, `redo`, reset,
checkpoint and selection calls during synchronous callbacks, but the public
`active_map_id` property could still be assigned directly or via `Object.set`.
A context provider or `changed` listener could silently point the host at a
different map before the containing operation completed.

`tests/t248_atlas_active_map_reservation.gd` covers direct/reflective assignment
at context capture, command apply, native Drawing source publication, changed
notification, Undo/Redo restoration and reset. It also checks ordinary idle navigation and successful chronological
command replay after every blocked assignment.

| Implementation | Exact fixture result |
| --- | --- |
| Prior source | `T248_ATLAS_ACTIVE_MAP_RESULT checks=70 failures=14` |
| Guarded property | `T248_ATLAS_ACTIVE_MAP_PASSED checks=70 failures=0` |

The property retains an ordinary backing map identifier and refuses writes
while `_timeline_reserved()` or `_replaying` is true. No new raster buffers,
history entries or native tokens are introduced.

## Neighboring local checks

- T-245 Drawing publication: 126/126.
- T-246 ordinary Atlas commands: 206/206.
- T-247 synchronous history notifications: 259/259.
- Atlas global Drawing history smoke: 101/101.
- Atlas editor-history smoke: 16/16.

The standalone/Atlas native-authority parent T-148 and owner/hosted CI gates
remain open; this ticket does not claim they are complete.
