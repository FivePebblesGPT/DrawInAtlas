# T-231 — Bounded direct external native tile adoption

**Date:** 2026-11-22 · **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
Baseline remote PR #22 SHA `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Bundled Godot 4.8 beta3, Rust 1.99.1 and native Linux x86-64 GDExtension;
X11 via software renderer. No owner-hardware or hosted CI claim.

## Fail-first reproduction

Before rebuilding the code, the previous staged Godot/Rust binary ran the new
`drawing/tests/t231_direct_native_transfer_budget.gd` with **8 failures of 21
checks** (exit 1). Both direct pixel and tile-local paths tried to resolve
sources instead of rejecting the oversized envelope; both Rust recorded and
untracked adoption entry points failed the early budget assertion. The 129
sparse-tile cases also reached source resolution. No oversized RGBA8 fixture
buffers were allocated as part of the negative oracle.

## Fix and boundaries

- With Rust already attached, `_publish_edit` counts unique storage tile IDs
  from validated signed pixel keys *before* calling `_resolve_chunk`; tile-local
  `_publish_tile_edit` preflights its patch tile count before resolving sources.
  `_install_prepared_edit` repeats the stride-aware cap before assembling
  native full-tile before/after buffers. The existing 128-tile limit remains.
- Conservative three-span envelope:
  `count * stride * stride * 4 * 3 <= 268,435,456` bytes. Six 2048px tiles
  require 301,989,888 bytes (288 MiB), which rejects before loading or copying.
  A 129-tile 64px transaction rejects by identity count even though its byte
  envelope is small. Failed calls preserve pending lazy identity, Godot/Rust
  revisions, live tiles and history.
- Independently, the shared Rust `commit_external_tiles` bridge checks the
  same envelope before `PackedByteArray` -> `Vec<u8>` conversion for both
  `adopt_external_edit` and `adopt_untracked_edit`; `external_bytes_received`
  stays at zero on rejection. A 64px native-attached positive control verifies
  signed pixel-map adoption, untracked tile-local publication, exact alpha-zero
  RGB, Undo/Redo, Save/Open and matching canonical Rust revision.

## Local verification

| Evidence | Result |
| --- | --- |
| New T-231 Godot test (post-fix) | **24/24** headless checks |
| `tools/build_native_brush.sh --test` | **36/36** Rust tests |
| T-148 external raster adoption | **28/28** |
| T-148 tile publication | **56/56** |
| T-162 untracked native publication | **25/25** |
| T-165 attached native revision fence | **51/51** |
| T-229 native history budget | **18/18** |
| T-230 detached legacy pixel bootstrap | **33/33** |
| T-156 legacy pixel native history | **38/38** |
| T-148 Atlas native history | **43/43** |
| T-157 lazy source reentrancy | **23/23** |
| T-148 native tile ABI | **312/312** |
| T-148 detached native replay | **21/21** |
| T-148 detached native bootstrap | **34/34** |
| T-148 Canvas native X11 integration | **46/46**, zero pixel-stream FFI calls |
| T-211 required-native CI contract | **5/5** Python tests |
| Godot model-log marker validation, Rust formatting and workflow YAML | Passed |
| `tools/validate_ticket_store.py` | **231 tickets**, review gates checked |

The required-native fast desktop CI job was updated to invoke the strict
`T231_DIRECT_BUDGET_PASSED checks=24 failures=0` marker. This workflow has
**not** run on GitHub at this local commit; a local YAML parse and source
contract do not establish hosted green CI.

## What remains open

This is a conservative *per-edit transfer* bound, **not** a guarantee of
bounded total resident memory, process RSS, or a completed migration of
non-Brush producers or Atlas-owned history commands. Native-absent direct
editing behavior is intentionally unchanged until T-150. T-148 remains
In Progress; T-149 is Blocked; owner/hardware and hosted-CI gates remain open.
