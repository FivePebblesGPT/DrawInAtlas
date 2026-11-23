# T-242 — Read-only history ownership property

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Verified PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Local environment:** bundled Linux Godot 4.8 beta3, native Rust GDExtension.
These are local software checks, not hosted CI or owner hardware validation.

## Fail-first and correction

The T-241 method protected a host timeline only when callers used
`set_external_history()`. The public writable field bypassed that method.
`drawing/tests/t242_history_mode_readonly.gd` exercises direct, `Object.set`
and `set_indexed` writes on local and host-owned documents and confirms valid
explicit pristine handoffs, signed hidden-RGB pixels and native Undo/Redo.
`tests/t242_atlas_history_mode_readonly.gd` uses a real Atlas campaign registry
and `AtlasEditHistory`: two native Drawing commits interleaved with an Atlas
grid change, then the same bypass attempts, full Undo and full Redo.

| Revision | Standalone test | Atlas test |
| --- | --- | --- |
| Before (public field) | `T242_HISTORY_MODE_RESULT checks=25 failures=10` | `T242_ATLAS_MODE_RESULT checks=18 failures=9` |
| After (getter-only projection) | `T242_HISTORY_MODE_PASSED checks=25 failures=0` | `T242_ATLAS_MODE_PASSED checks=18 failures=0` |

Only the backing field `_external_history` is mutated by the checked
`set_external_history()` method. The publicly read `external_history` property
cannot be assigned through normal or reflective GDScript access, while existing
readers keep the same Boolean contract.

## Neighbor regression matrix

- T-241 history handoff **29/29**; T-239 native token ordering **36/36**.
- T-148 Atlas native tile history **43/43**; native tile ABI **312/312**.
- T-233 pixel first-edit bootstrap **37/37**.
- T-148 detached native bootstrap **34/34**.
- Atlas global history smoke exited successfully; strict count is verified
  separately by its own existing CI marker.

No owner approvals inferred. T-148/T-149, hosted required CI and physical
acceptance remain open. This is a bounded public ownership API hardening, not
an implementation of the complete host-owned command lifetime.
