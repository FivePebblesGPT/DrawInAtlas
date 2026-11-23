# T-232 — First tile-local non-Brush edit acquires Rust authority

**Date:** 2026-11-22 · **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
Remote PR #22 baseline `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Bundled Godot 4.8 beta3 and existing Rust GDExtension on Linux x86-64.
No native library code changed; no hosted CI or physical owner validation claimed.

## Fail-first witness

The new `drawing/tests/t232_tile_native_bootstrap.gd` was run against the
previous `DrawingDocument` implementation before modifying production code:
**8 failed of 24 checks** (nonzero exit). The existing publisher committed
pixel-only history, did not attach Rust at first local or host tile edit,
and did not enforce the native transfer budget before resolving an absent
source. The subsequent test expansion adds untracked publication and the
129-tile count bound.

## Change

- With a native class available, the initial tile-local producer validates
  signed projection, unique tile count and conservative three-span budget
  before lazy chunk resolution. The direct *pixel-map* producer is unchanged.
- After all source identities have been verified, a provisional native store
  is configured at the document revision. All touched original RGBA8 tile
  images are imported into this store (including a loaded nonempty tile),
  and Rust either accepts the whole atomic external edit or the provisional
  store is discarded. No provider callback occurs after native adoption.
- On successful recorded adoption, the document publishes full-tile history
  bytes and the native token; on untracked adoption, it advances Rust and
  Godot without fabricating an Undo event. Later pixel edits reuse the same
  native store. Host-controlled history replays through the native token
  seam, and portable Open can bootstrap a new store on its next tile edit.
- Updated T-100 oracle checks compare changed RGBA8 values against independent
  per-pixel history without requiring native deltas to materialize global
  string-keyed maps. The earlier T-160 non-native >2^53 history expectation
  was stale after T-230: edit publication remains supported, but subsequent
  native history replay must reject those unsafe coordinates atomically.

## Local validation

| Check | Result |
| --- | --- |
| T-232 pre-fix witness | 8 expected failures / 24 checks, nonzero exit |
| T-232 post-fix | **34/34**, recorded/untracked, signed RGBA8, host Undo/Redo, Save/Open, failures |
| T-100 independent sparse and dense pixel oracle | **197/197** |
| T-160 signed publisher/replay boundary | **46/46** |
| T-148 tile publication | **56/56** |
| T-148 external adoption | **28/28** |
| T-148 persistent native document | **44/44** |
| T-162 untracked native publication | **25/25** |
| T-165 revision-fence | **51/51** |
| T-229 / T-230 / T-231 | **18/18, 33/33, 24/24** |
| T-156 legacy native replay | **38/38** |
| T-148 native tile ABI | **312/312** |
| Atlas native document history | **43/43** |
| Atlas selection Delete and save/reopen | **19/19** |
| Native-X11 Canvas on Xvfb/Mesa llvmpipe | **46/46**, zero native tile pixel-stream FFI calls |

## Remaining limitations

Only direct **tile-local** publication bootstraps the new Rust store.
Some callers still construct source or history pixels in GDScript, and the
global-pixel `_publish_edit` path can still originate without Rust. The host
retains independent detached command snapshots; complete native history
lifetime, production-level mask/selection/clipboard migration, T-149 display
and persistence seams, and owner hardware review remain open. A CI workflow
source change is not a GitHub Actions success on the unpushed commit.
