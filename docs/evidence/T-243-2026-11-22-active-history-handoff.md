# T-243 — Native active-edit history handoff fence

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Validation:** bundled Godot 4.8 beta3 and offline Rust native extension on
Linux x86-64; local tests only.

## Reproduction and fix

With an open Rust `begin_edit`, the unchanged `DrawingDocument` handoff returned
success before either owner had committed a revision. A detached host or local
command could subsequently be filed under the wrong owner. The new native
`has_active_edit()` probe is read-only. A non-idempotent history mode handoff
fails with `HISTORY_OWNED` until `discard_edit` or commit releases the active
transaction. A missing native probe fails closed instead of silently selecting
the other timeline. The original owner, revision, statistics, native source,
ongoing transaction and content are unchanged by a rejected handoff.

| Run | Outcome |
| --- | --- |
| Original binary / original owner check | `T243_ACTIVE_OWNER_RESULT checks=40 failures=10` |
| Rebuilt native + checked owner | `T243_ACTIVE_OWNER_PASSED checks=40 failures=0` |
| Rust offline unit tests | 36 passed, 0 failed |
| T-241 owner handoff | 29/29 |
| T-242 getter-only owner | 25/25 |
| T-239 retained native token order | 36/36 |
| T-237 detached history preflight | 40/40 |
| T-148 native tile ABI | 312/312 |
| T-233 direct pixel bootstrap | 37/37 |
| T-242 real Atlas history | 18/18 |
| T-148 Atlas native tile history | 43/43 |
| T-230 detached pixel bootstrap (Drawing project) | 33/33 |
| T-148 native-X11 Canvas tile cutover | 46/46, 0 per-pixel tile-stream calls |
| Required-native CI source contracts | 17/17 |
| Ticket store and manual gates | 243 tickets valid |

The 40-check fixture confirms both local-to-host and host-to-local rejection,
idempotent owner calls, cancellation, allowed pristine transitions, exact
alpha-zero hidden RGB and subsequent local/host Undo/Redo. The `T-243` run is
wired into the required-native fast workflow with its strict pass marker.

**Not verified here:** hosted CI on the local commit, physical device behavior,
complete host-owned native command authority or T-149. No owner signoff is
inferred; T-148 stays In Progress.
