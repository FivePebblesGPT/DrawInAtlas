# T-247 — Synchronous Atlas history notification reservation

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Environment:** supplied Godot 4.8 beta3 Linux x86-64, native extension,
root Atlas project, headless script fixtures. Hosted CI not run.

## Reproduction

`AtlasEditHistory` already reserved synchronous changed observers during
`execute`, `execute_drawing_transfer`, `execute_asset_rebind`, and
`commit_drawing`. However `undo`, `redo`, `record_selection_change`, `reset`,
`mark_saved`, and `mark_external_change` could emit `changed` with no owner
reservation. An observer could insert commands, recursively replay, reset or
change save/external-revision state while the current notification was still
on the stack. This could spuriously branch or discard the host command history.

The new fixture `tests/t247_atlas_history_notifications.gd` exercises **42
combinations** of six outer notification sources and seven reentrant operations
(ordinary command, Undo, Redo, reset, savepoint, external change, selection).
It checks the callback sees a reserved but inspectable completed timeline, one
notification, unchanged history/dirty/grid state under rejected reentry, and
ordinary follow-up replay or modification after the callback disconnects.

| Fixture | Before | After |
| --- | --- | --- |
| T-247 Atlas changed notifications | `T247_ATLAS_NOTIFICATION_RESULT checks=259 failures=124` | `T247_ATLAS_NOTIFICATION_PASSED checks=259 failures=0` |

The fix routes all host `changed` emissions through `_emit_changed()`, with a
nested-state-safe `_notifying_changed` reservation included in
`_timeline_reserved()`. No new history commands or raster copies are introduced.

## Neighboring local validation

- T-245 Atlas Drawing publication: **126/126**.
- T-246 ordinary Atlas commands/transfer/asset: **206/206**.
- Atlas global history: **101/101**.
- T-148 Atlas native history: **43/43**.
- T-244 pending-session owner: **18/18**.
- T-242 read-only history owner: **18/18**.
- T-170 cross-document transfer: **pass**.
- T-148 native history reentrant replay: **26/26**.
- T-148 native history payload guard: **20/20**.
- T-148 Canvas graphical X11 / Mesa native-store path: **46/46**, with **zero** per-pixel tile-stream FFI calls.
- Required-native CI source contract: **21/21**, ticket-store validator: **247** records; explicit GDScript typing and workflow YAML syntax: pass.

No claim of hosted required-CI success, reference-device responsiveness,
physical owner signoff, or completed T-148 universal authority.
