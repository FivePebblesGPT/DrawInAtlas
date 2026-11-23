# T-230 — First detached legacy-pixel replay boots Rust authority

**Date:** 2026-11-22 · **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
Verified GitHub PR #22 head: `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`;
this checkpoint builds on nine **local** unpushed commits through T-229.
Bundled Godot 4.8 beta3 and the compiled Rust GDExtension were used locally.

## Before / after

A historical local or Atlas-owned `DrawingDelta` with `tile_stride == 0`
replayed via `_publish_edit` (GDScript-only) whenever
`DrawingDocument._native_raster_store` was null. In an otherwise native-capable
runtime, Undo/Redo therefore advanced the host document without attaching a
Rust tile store. The next native stroke would need a source/history rebase.

The **pre-fix** 23-check `drawing/tests/t230_detached_pixel_bootstrap.gd`
completed with **eight failed checks** (process exit 1): local and Atlas-style
Undo did not attach Rust, both owners' revisions/byte projections were absent,
and detached replay after portable Open remained Godot-only. All failures were
from the expected ownership gap; no test source or expected-result change was
used to make the pre-fix pass.

The single production dispatch change uses `_replay_pixel_delta_native` when
either a Rust store is attached **or** the `DrawingNativeTiles` GDExtension
class exists. This reuses T-156's sparse-map-to-tile conversion and T-229's
bounded transfer checks, followed by the existing T-148 provisional native
store bootstrap. No Rust ABI changes, new history tokens or per-pixel Brush
hot-path operations were introduced.

The **final 33/33** native test covers:

- Local pre-Brush Undo/Redo, shared revision, exact signed positive/negative
  tile bytes and transparent hidden RGB in canonical Rust versus Godot.
- A real subsequent Hokusai native stroke using the same Rust store.
- Atlas-style externally owned detached Undo/Redo and source parity, plus
  busy native transaction refusal, cancellation and retry.
- Portable `.drawing` Save/Open followed by replay into a fresh native store.
- Noncanonical pixel IDs, incorrect source pixels and 129 distinct tiles:
  rejection leaves the revision and absent native attachment unchanged.

T-156's former assertion that historical never-native Undo/Redo must remain
Godot-only was updated to require a native store with the exact host revision;
its extended regression passes **38/38**.

## Local regression evidence

| Target | Result |
| --- | --- |
| New T-230 real-native fixture | 33/33 |
| Existing T-156 historical pixel fixture | 38/38 |
| T-162 untracked external publication | 25/25 |
| T-157 reentrant lazy sources | 23/23 |
| T-154 native text parking | 30/30 |
| T-155 native text rerasterization | 32/32 |
| T-229 history budget | 18/18 |
| T-148 native tiles ABI contract | 312/312 |
| T-148 external adoption | 28/28 |
| T-148 document tile publication | 56/56 |
| T-148 persistent document | 44/44 |
| Atlas native tile timeline | 43/43 |
| Atlas detached bootstrap | 34/34 |
| Atlas detached replay | 21/21 |
| Atlas payload guard | 20/20 |
| Atlas reentrant history replay | 26/26 |
| Atlas drawing history timeline | 101/101 |
| Object native Save/Save As lifecycle | 38/38 |
| **18 headless suites total** | **922/922** |
| Compiled Rust extension unit tests | 36/36 |
| Native-X11 Canvas tile cutover | 46/46; tile-pixel stream FFI calls = 0 |
| Ticket-store / manual dependency validation | 230 tickets valid |

The initial T-154 and T-155 runs failed to find the staged Lato font because
Godot had not yet imported its assets. Both passed after a fresh successful
`--headless --editor --path drawing --import --quit` run; no source change
was made to resolve that environment issue.

The required-native Godot workflow now executes the new test with a strict
`T230_PIXEL_BOOTSTRAP_PASSED checks=33 failures=0` marker. The hosted workflow
has **not** run these local commits. Static workflow/YAML checks and diff
integrity are recorded separately at commit time.

## Remaining contract and limits

Native-first history replay does **not** migrate the direct/GDScript producer
that originally created the pixel delta, serialize the host-owned command
queue, or establish native ownership for every unreferenced layer. With no
native extension, the historical direct replay path remains temporarily in
place (until T-150). Non-Brush producer migration and host-owned lifetime
still belong to T-148; T-149 remains Blocked. No hardware owner approval or
hosted CI success is inferred.
