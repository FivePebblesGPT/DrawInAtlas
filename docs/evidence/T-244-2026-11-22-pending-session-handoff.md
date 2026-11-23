# T-244 — Pending script session history ownership

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Verified PR #22 remote baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Environment:** bundled Godot 4.8 beta3 + existing native Rust extension, Linux x86-64;
headless and Xvfb/Mesa native-X11 only. No hosted GitHub or owner hardware run.

## Failure and fix

A `DrawingEditSession` may exist long before Rust's `begin_edit`: `begin_edit`
returns a detached staging session and direct `DrawingEditSession.new` callers
can construct one too. Before a document revision changes, the checked
`set_external_history()` handoff formerly accepted local ↔ host changes, letting
an already-pending command be filed under the wrong timeline.

`DrawingEditSession._init` now registers a **weak handle** on its document.
`set_external_history()` prunes dead and `_closed` handles and rejects ownership
changes while any session remains active, without altering the owner or document.
Commit (including no-change and stale-failed commit) and cancel mark sessions
closed, and abandoned RefCounted sessions are not retained. The existing
Rust `has_active_edit()` guard remains independent and active for native edits.
Same-owner calls still succeed.

| Check | Previous code | Final code |
| --- | --- | --- |
| Standalone pending script owner (`drawing/tests/t244_pending_session_history_handoff.gd`) | `T244_PENDING_SESSION_RESULT checks=50 failures=7` | `T244_PENDING_SESSION_PASSED checks=50 failures=0` |
| Real Atlas loaded-document + `AtlasEditHistory` (`tests/t244_atlas_pending_session_history.gd`) | `T244_ATLAS_PENDING_RESULT checks=18 failures=9` | `T244_ATLAS_PENDING_PASSED checks=18 failures=0` |

The Atlas fixture uses a loaded raster document attached through
`AtlasDrawingRegistry.attach_loaded_document` **after** the source layer is
created, so its host owner genuinely has no intervening command and the
negative control is not masked by T-241's revision fence. The command acquires
Rust authority on commit and is undone/redone by Atlas with exact signed
RGBA8 and alpha-zero hidden RGB.

## Local neighboring regression checks

- T-243 active Rust edit handoff: **40/40**.
- T-242 read-only owner property: **25/25**, Atlas owner: **18/18**.
- T-241 host timeline fence: **29/29**.
- T-233 pixel first-edit bootstrap: **37/37**; T-232 tile bootstrap **34/34**.
- T-239 retained-token order: **36/36**.
- T-148 native tile ABI: **312/312**; Atlas native history **43/43**.
- T-100 sparse publication oracle: **197/197**.
- T-148 native-X11 Canvas tile cutover: **46/46**, `tile_pixel_stream_calls=0`.
- Required-native CI source contracts: **18/18**; strict model log checks pass.
- Ticket store: **244 tickets valid**, preserving existing manual-review gates.

**Not claimed:** hosted exact-head CI, physical responsiveness, every source
producer, universal native authority, host-level external command retention or
owner approval. T-148 remains In Progress; T-149 remains Blocked.
