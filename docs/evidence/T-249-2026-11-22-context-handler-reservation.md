# T-249 — Atlas history context-handler reservation

**Date:** 2026-11-22 · **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`
**Remote baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`
**Environment:** bundled Godot 4.8 beta 3 Linux headless, compiled native extension. These are local software tests, **not** GitHub-hosted CI or physical owner approval.

## Failure and repair

During an Atlas history reservation, the public `context_provider` and
`context_restorer` properties remained assignable. A context provider could
replace itself after the before snapshot but before the after snapshot. A
`changed` observer or Undo/Redo restorer could also replace the callback pair
while the current command was being reported or restored. Replacing these
handlers neither requires a new command nor alters the active-map property,
so the T-245–T-248 timeline guards did not catch it.

The handlers now have checked setters with private backing Callables. Direct
assignments and `Object.set()` attempts return without changing either
handler while `_timeline_reserved()` or `_replaying` is true. Normal editor
setup, idle switching, and legitimate failed-command recovery are unchanged.

| Fixture | Result |
| --- | --- |
| Previous `scripts/editing/history.gd` at `ad989ca7` | `T249_CONTEXT_OWNER_RESULT checks=84 failures=42` (nonzero exit) |
| Patched source | `T249_CONTEXT_OWNER_PASSED checks=84 failures=0` (exit 0) |

The fixture exercises both assignment forms during context capture, apply,
changed notifications, and restoration. It checks original before/after
selection-context parity, chronological Undo/Redo, failure cleanup, idle
handler replacement, and a real Atlas-owned native Drawing edit with signed
transparent hidden RGB. The prior-source control temporarily substituted
`git show HEAD:scripts/editing/history.gd` and restored the working copy
immediately afterward.

## Neighboring regressions

All zero exit, executed against patched source under Godot headless:

| Suite | Result |
| --- | --- |
| T-245 Atlas Drawing commit reentrancy | 126/126 |
| T-246 ordinary Atlas command reservation | 206/206 |
| T-247 Atlas changed notifications | 259/259 |
| T-248 active-map reservation | 70/70 |
| T-148 real Atlas native history | 43/43 |
| T-244 Atlas pending sessions | 18/18 |
| T-242 Atlas mode ownership | 18/18 |
| Atlas `drawing_history_smoke` | 101/101 |
| T-148 detached native replay | 21/21 |
| T-221 Atlas selection deletion | Passed |

Additional final local validation: T-148 native-X11 Canvas **46/46** on Mesa
llvmpipe, with `tile_pixel_stream_calls=0`; required-native CI source contracts
**23/23**; `tools/validate_ticket_store.py` accepted **249 tickets**; workflow
YAML parsing and staged Git diff integrity succeeded. These results do not
substitute for a fresh hosted required-CI run.

Exploratory-only: a separate 70-command native token retention/replay probe
passed 218/218 checks across Rust's 64-event ring. No source change was needed
for that scenario; it is not part of this ticket's committed test matrix.

**Outstanding:** hosted required-CI, T-148 universal native authority,
T-149 native UI seam integration, and owner-hardware reviews. No manual gate
was approved by these results.
