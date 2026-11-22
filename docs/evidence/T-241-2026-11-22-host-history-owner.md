# T-241 — Host-owned history transition fence

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote PR #22 reference:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
**Local environment:** bundled Linux Godot 4.8 beta3, native Rust GDExtension;
headless/Atlas software tests, not hosted CI or owner physical hardware.

## Fail-first reproduction

`drawing/tests/t241_host_history_owner_fence.gd` records native Raster edits
while `external_history=true`, then attempts to switch to local history. It
also covers repeated owner selection, Undo-to-original-data, an untracked
raster edit, a semantic-only structural host command, invalid operations,
and the existing local-history transfer rejection.

On the previous document code: `T241_HOST_OWNER_RESULT checks=29 failures=6`.
The six failures show accepted ownership handoffs after host revisions and
loss of external history mode. With the fix:
`T241_HOST_OWNER_PASSED checks=29 failures=0`.

The new `_external_history_anchor_revision` is set only on a genuine switch
to host mode and is never reset by an idempotent call. A return to local mode
is allowed only if the document revision remains unchanged. A rejected handoff
keeps native source pixels (including alpha-zero hidden RGB), the native store,
history tokens, revision and future external Undo/Redo intact.

## Local verification

- T-241 — **29/29**, with 6 fail-first failures on the old implementation.
- Native history ordering T-239 — **36/36**; native pixel bootstrap T-233 —
  **37/37**; historical pixel bootstrap T-230 — **33/33**.
- Detached history payload T-237 — **40/40**.
- Native tile ABI — **312/312**; native document publication — **56/56**.
- Atlas global-history smoke — **101/101**.
- Atlas native tile history — **43/43**; detached bootstrap — **34/34**.

The required-native fast-desktop workflow now asserts the exact 29-check
marker. That source change is **not** evidence of GitHub-hosted CI passing.
No owner/physical approval or T-148/T-149 completion is claimed.
