# T-311 — Interactive layer group disclosure (2026-11-25)

## Implementation and boundaries

The shared workspace projects real nested TreeItems, not depth-prefixed label
strings. Godot draws contrast-matched native disclosure chevrons, and eye/lock
buttons retain their independent row IDs. A folded group materializes no real
descendants in the visible page. A nonselectable placeholder gives the native
Tree a disclosure target even where no children are on the current page; it is
hidden by the collapsed parent. The page count refers to matching rows (200 per
page), with ancestor context and page hints additionally rendered. Search
traverses folded descendants and shows only matches plus ancestors; folding is
suspended while filtering. Selecting a match reveals its ancestors when clearing
search. Folding a selected descendant moves the paint target to the nonpaintable
group without recording selection or artwork history. Pending detached edits
block this relocation. Per-live-tab collapse and page state survive layout
rebuilds/tab changes. Fresh opens start expanded; no file/registry schema change.

## Fail-first and native verification

Fail-first standalone X11 test on `f08cfdf4` reproduced both missing real parent
and disclosure target (2 failed checks, exit 1). The corrected native Tree
initially emitted a selection-history event when it automatically selected a
collapsed child's parent. Suppress that implicit selection while fold state is
in flight; the fold transaction now relocates selection without recording
history, even with the optional selection-history preference enabled. The
pending-stroke regression isolates a detached session from its unrelated
Brush drain scheduler; it verifies actual fold pointer input cannot retarget it.
The hosted test initially used prepublication IDs; fixed the witness to resolve
remapped IDs from the opened private draft, rather than changing the registry.

Full pinned `make test-layer-hierarchy TOOLCHAIN=bundle BUNDLE=<supplied bundle>`
passed T-089 model 63/63, native 36/36, T-269 hosted 27/27, T-311 standalone
47/47 and actual Atlas Object Editor 11/11. The new target also runs in the
existing on-demand layer workflow. The standalone tests cover actual native
pointer and keyboard input, old descendant eye hit location, nested fold state,
painting guard, pending source, optional selection history, eye/lock,
Undo/Redo, signed RGBA8, filter navigation and selection, pagination and layout
rebuild, tab switch/fresh file open. The hosted witness checks private draft
revision/history, source-file hash and global Atlas history remain unchanged.

Adjacent tests passed: text UI 18/18, T-129 pending content edits 35/35, dock
layout 82/82, standalone persistence smoke, compact workspace 75/75 (X11; the
initial headless invocation correctly rejected a missing display). Four Python
source/log/CI regression modules passed 22 checks total. Explicit typing passed
633 project scripts and 33 skill documents.

## Actual visual review

Software X11/Mesa llvmpipe (OpenGL compatibility), Godot
`4.8.beta4.official.b070e63b1`, mandatory native Rust extension, supplied pinned
bundle. Build: `f08cfdf4` plus this ticket's workspace implementation
(blob `0a38a952ad43b554af0d1e5fb0f53e66a82fa4d9`); screenshots generated from
actual standalone/hosted windows and opened by the implementation agent. Local
capture directory `/mnt/data/t311-visual/`:

- `layers-expanded.png`: 1280×800, Terrain/Details and nested paint rows.
- `layers-nested-collapsed.png`, `layers-collapsed.png`: nested/outer disclosure,
  existing artwork still visible, selected group not a paint target.
- `layers-filtered.png`: one matched row with true ancestor context.
- `layers-page.png`: second page with ancestor context and aligned row actions.
- `layers-narrow.png`, `layers-hidpi.png`: 800×600, 100% and 150% scaling;
  the chevrons and eye/lock actions remain reachable via actual pointer input.
- `layers-atlas.png`: actual hosted Object Editor, expanded parent and collapsed
  nested group, unchanged artwork.

First visual render showed a small low-contrast default chevron and the
collapsed chevron disappeared when the placeholder was invisible. Corrected
with dedicated high-contrast 16px arrows and a nonselectable child-page hint
hidden by the collapsed parent; re-rendered and opened the corrected images.
Nested names now indent structurally while eye/lock remain aligned as a stable
right column. No cosmetic-only geometry assertions were added. Physical
monitor/GPU, Windows and hosted CI remain unverified; T-059/T-250 require
explicit owner acceptance, and T-148/T-149 remain independent.
