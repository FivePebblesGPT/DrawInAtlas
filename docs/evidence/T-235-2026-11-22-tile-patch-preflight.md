# T-235 — Tile-local publication descriptor/reentrancy preflight

**Date:** 2026-11-22
**Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`
**Baseline:** PR #22 remote `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146` (14 local commits before T-235)

## Failure mode and scope

`DrawingDocument._publish_tile_edit` checked one patch and resolved its source
before inspecting the later patches. A bad later key, index, RGBA8 value or
missing session source could therefore invoke a prior source callback. A
provider could change a subsequent patch, add session source entries, or
mutate an earlier tile's *content* while keeping the same object identity and
revision. The old installation path compared tile identities, not those
already-read source bytes. Invalid publication could commit the wrong delta.

The fix validates all keys, projection bounds, indices, replacements, and
required session sources before the first lazy read. It freezes patch values
and the entire verified source descriptor map (including unchanged source
entries), stages from the frozen patches, captures canonical RGBA8 tile fingerprints, and
rechecks descriptors and earlier source bytes after all callbacks. Rejection
is before the native adoption boundary, with no document revision/history
advance, no new Rust owner and no changed target pixels. Provider-side
mutations to canonical source objects are **not undone** by this guard; they
remain unauthorized and must be repaired by their owner.

## Reproduction and local evidence

- Compiled `DrawingNativeTiles` loaded in Godot 4.8 beta 3 headless.
- Unchanged `HEAD:addons/drawing/document.gd` staged temporarily in the
  isolated Drawing project: `T235_TILE_PREFLIGHT_RESULT checks=34 failures=17`, exit 1.
- Fixed source: `T235_TILE_PREFLIGHT_PASSED checks=34 failures=0`, exit 0.
- Four invalid-later-descriptor cases prove zero lazy source calls; three
  reentrant cases prove no publication for changed patches, source-map keys
  or source bytes. A valid multi-tile native adoption with extra unchanged
  session source, exact alpha-zero RGB, Undo/Redo and untracked follow-up passes.
### Neighboring regression matrix

All below were executed locally against the fixed canonical source, with
native extension loaded and successful exit status unless stated otherwise.

| Witness | Result |
| --- | --- |
| T-235 full-source preflight | 34/34 |
| T-100 independent sparse oracle | 197/197 |
| T-148 native tile publication | 56/56 |
| T-148 external raster adoption | 28/28 |
| T-148 persistent native store | 44/44 |
| T-148 native tile ABI | 312/312 |
| T-160 signed direct publication | 46/46 |
| T-165 attached revision fence | 51/51 |
| T-229 history transfer envelope | 18/18 |
| T-231 direct transfer envelope | 24/24 |
| T-232 first tile-local native adoption | 34/34 |
| T-233 first pixel-map native adoption | 37/37 |
| T-234 native Brush descriptor preflight | 32/32 |
| T-148 Atlas native history | 43/43 |
| T-221 Atlas selection Delete | passed |
| T-148 native-X11 Canvas cutover | 46/46; zero tile-pixel-stream calls |
| Rust compiled extension unit tests | 36/36 |
| Python required-native CI source contracts | 9/9 |
| Ticket store / manual-review validation | 235 tickets valid |

Godot logs use the strict assertion markers enforced by required-native CI;
`git diff --check` and workflow YAML parsing also passed. The unchanged-code
negative control runs with the previous `HEAD` document temporarily copied
into the staged standalone project, then restores the fixed source. This
matrix does **not** constitute a hosted CI run on the unpublished commit.

## Remaining validation

Local software tests are not hardware input/output latency measurement,
physical owner approval, official release export or hosted required CI.
T-148 universal native history/source authority and T-149 integration remain
open. No manual-review ticket was advanced.
