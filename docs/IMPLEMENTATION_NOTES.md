# Implementation Notes

## Editor-module readability follow-up — 2026-10-24

Starting from merged readability PR #3 (`dace0fc`), `AtlasEditor` is reduced
from **1,462 to 716 lines**, with all **23 fixed-control constructor call sites**
removed (including shared builders).
Two scene-owned forms replace the remaining inspector/sidebar builders:
`prefab/inspector.tscn` and `prefab/campaign_browser.tscn`. Their controllers
own presentation and emit typed intents. Existing public controls/actions are
retained as references/facades for menus and integrations.

`AtlasArtworkEditor` owns scoped artwork operations and workspace-local
clipboard state. `AtlasMapNavigator` owns camera/floor/layer memory, Back and
the opt-in zoom gate. Both receive concrete dependencies without an editor
backpointer. The workspace retains session/save/load, document-level commands
and undo/redo coordination. See [Code readability](CODE_READIBILITY.md) for
the ownership table and representative floor workflow.

Verification on Godot **4.8-beta1**:

- Headless editor import and all **15 headless smoke suites** passed, including
  organization (32), floor/view (102), overview (67), preview cache (46),
  tools UI (36), layers/recovery and the existing editing/domain suites.
- `tests/editor_modules_smoke.gd`: **32 new checks** for scene-owned controls,
  metadata submission/undo, form routing, numeric transforms, read-only
  browsing/preferences, campaign replacement, pre-startup clipboard
  initialization, expanding Search/Layers lists and two-workspace state isolation.
- Real-renderer `tests/visual_smoke.gd`: zero sampled changes outside the
  canvas; ink/erase/undo, layer order/opacity, raster move/scale/fill, grid
  invariance, 800×600 layout and compact dialog all passed.
- Matching-beta Web release export passed; browser smoke remains deferred.
- Opened the authored inspector in the native Godot editor and inspected its
  layout: no wrapping-label warnings. The root has a preview size for standalone
  scene authoring; the workspace container still determines its runtime size.
  Editor output did contain existing Godot AI configuration/port warnings and
  shutdown cleanup warnings, so this is not a claim that all editor output is
  warning-free.

**Persistence direction:** the intended replacement format is native Godot
`.res`/`.scn`. The current JSON/WebP checkpoint implementation is still behind
`AtlasCampaignStore`; this UI refactor does not implement that migration or
change canonical save data.

## Execution milestone 4 — local editing and asset placement

- **L/R/O** create line, rectangle and ellipse **outlines** on ink layers. Each drag is one command, including recovery from an initially zero-width shape. **B/E** paint/erase editable ink or raster pixels. New raster layers start empty; pen gestures lazily allocate canonical chunks, including negative coordinates. Raster erasing clears RGBA pixels instead of painting a backdrop.
- **V** selects active-layer artwork. Click picks the topmost hit stroke or a raster asset; a marquee selects whole padded stroke bounds / the whole raster layer. Shift adds ink to the selection. Drag the selection to move, or its bottom-right handle for proportional resize. Numeric move/scale/rotation works about the selection center. Ink widths scale proportionally. Imported/pasted images enter selection mode ready for placement.
- Previews are detached and do not dirty data until release. Escape/focus loss/tool/map changes cancel them. Save during a manipulation commits that accepted gesture first; mouse release cannot apply it twice. Undo/redo targets the original board/layer. Stale, hidden or locked selections cannot be transformed or deleted.
- **F** bucket-fills connected terrain or raster pixels. Tile fill uses the content grid (not the overlay); unbounded background fill is rejected unless a finite cell scope bounds it. Raster fill traverses existing chunk pixels only. Limits are atomic: 8,192 terrain cells, 262,144 flood pixels, and 1,048,576 candidate brush pixels; rejection never leaves partial source edits.
- **Ctrl+C/X/V**, **Ctrl+A**, Delete and Edit-menu actions operate on typed artwork. Ink paste targets a compatible editable ink layer; raster paste creates a new independent layer with self-contained pixels. Raster copy includes lossless WebP, not references to the source filesystem. Native clipboard images can also become raster assets. Tile copy uses the selected matching content-grid cell; paste refuses incompatible shape/spacing/rotation instead of reinterpreting coordinates. Native distance labels are never converted.
- The native OS clipboard is used only for explicit clipboard actions; headless/native automation uses the internal clipboard flag to preserve the user's clipboard. An internal fallback remains for platforms without synchronous clipboard access. Payloads are bounded to 16 MiB, with typed validation and pixel/hash verification.
- **Lock to selected cell** is a central document-space scope. With no selected cell it blocks writes. New vector paths are inset/clipped by brush radius, raster writes require the full pixel quad inside the scope, and cell edits require their whole polygon inside it. Move/resize/delete require both footprints wholly contained. Ink erase under scope conservatively leaves crossing strokes intact rather than changing their off-cell portions. Copy is read-only and may read outside the edit scope.
- Schema **v5** stores raster placement transforms and reads v1–v4; v4 assets migrate to identity placement. Transform commands change geometry, not source chunk hashes. Existing recoverable checkpoints, image verification and layer guards remain in force.

### Milestone 4 verification

- `tests/fill_scope_smoke.gd`: **123 checks** for finite/atomic fills, raster paint/erase, negative/partial chunks, transforms, scope filtering and snapshots.
- `tests/clipboard_smoke.gd`: **436 checks** for detached typed payloads, invalid/corrupt/bounded data, exact RGBA and tile normalization.
- `tests/selection_smoke.gd`: **202 checks** for outlines, hits/marquees, stale/locked selection guards, proportional transforms, unchanged raster assets and migration/persistence.
- `tests/tools_ui_smoke.gd`: **36 native input/UI checks**, including previews, shape/move/resize gestures, mid-gesture Save, clipboard cross-board isolation, scope enforcement, raster painting/fill/erase, tile content-grid routing and save/load.
- Native framebuffer checks confirm asset movement/resizing without changed pixel hashes, outline pixels, raster fill and undo restoration, plus prior opacity/clipping/compact-layout checks.
- Live KWin input moved selected shapes by exactly 100×50 board units in one command; Ctrl+Z restored their original coordinates. The dedicated preview did not write the user's save or clipboard.

These are whole-stroke and whole-raster-asset selections, not per-pixel lasso or nonuniform ink warping. Bucket fill targets raster/terrain content, not vector-outline interiors. Raster brushes are hard round pixel replacement; pressure/antialiased raster painting and a richer asset catalog remain refinements. Web smoke remains deferred per user direction.

## Execution milestone 3 — typed layers and recoverable native saves

The **local client** is the current acceptance target. The user explicitly postponed Web smoke testing to reduce compute/token cost; compatibility boundaries and optional tests are retained, but the new browser import/recovery flow is not claimed verified.

- Floors own ordered, typed `AtlasTileLayer`, `AtlasInkLayer` and `AtlasRasterLayer` content. The Layers sidebar selects the edit target, creates ink/terrain layers, renames, raises/lowers, and controls visibility, locks and opacity. Hidden/locked content is rejected by typed stroke/tile commands and cannot be overwritten through generic layer transactions; metadata changes such as unlocking remain possible.
- Layer transactions capture deep before/after snapshots and preserve IDs across undo/redo. Terrain painting is now reversible. CanvasGroup compositing applies layer opacity once to overlapping content, rather than making stroke intersections darker. Raster chunks render in board coordinates and the grid remains a separate overlay.
- **Import image…** uses the native file picker for PNG/JPEG/WebP input. A selected image becomes a new raster layer with bounded 256-pixel RGBA8 chunks. Canonical persistence always encodes lossless WebP and verifies exact decoded bytes, including hidden RGB beneath alpha=0. Import is bounded to 32 MiB encoded / 4096 pixels per edge; moving/resizing/raster painting is milestone 4.
- Schema **v4** migrates v1–v3 floor terrain/ink into typed layers without rescaling art or losing frozen tile geometry. Layer IDs/types/flags, chunk references and nested map/floor/link/placement data are validated before activation. Failed Load keeps current work/history; recovered Load reports the backup source and marks the session dirty for repair.
- Save stages/verifies immutable content-addressed assets, writes/verifies full-precision metadata with a checksum, preserves a validated previous head at `.bak`, then renames the staged head into place. Pending files are ignored by recovery. Corrupt heads never overwrite valid backups; failed saves cannot clear dirty state. The injection seam is `AtlasStoreIO`, with diagnostics in `AtlasStoreResult`.

### Milestone 3 verification

- Layer transactions/migrations/guards: `tests/layers_smoke.gd`.
- Recovery, interrupted/torn writes and rename failures, asset reuse/corruption, exact RGBA WebP: `tests/storage_smoke.gd` (**135 checks**).
- Native integrated layer controls, raster import pipeline, failed-load state preservation and visible recovery status: `tests/layer_ui_smoke.gd`.
- Existing 174 artwork and 448 board/grid checks continue to pass. Native framebuffer checks cover order, visibility, raster alpha and equal opacity at overlapping stroke intersections, plus clipping/grid invariance and compact layout.
- A live KWin session exercised the real KDE file picker, imported a PNG into the client, rendered it and saved a verified WebP checkpoint with a clean dirty state. The dedicated preview used a separate validation save path.
- A minimal browser picker probe found and fixed a beta bridge Boolean/int mismatch using a typed string handshake. Extended upload/retry/IndexedDB recovery remains **deferred**; no completed M3 browser smoke is claimed. `tests/browser_smoke.py --extended-storage` retains that future validation path.

Remaining storage limits: one retained backup (not full journaling/autosave), no orphan-asset garbage collection, and snapshot-based history unsuitable for unbounded editing sessions. Filesystem flush/rename guarantees are bounded by the platform API; there is no claim of hardware power-loss durability. Networking/projector privacy remains milestones 7–8.

## Execution milestone 2 — independent boards and grids

- **File → New board** / Ctrl+N opens a scrollable creation form. Empty names are rejected; no grid is the default. Square/pointy-hex/flat-hex boards retain chosen spacing, origin, rotation, visibility and native distance/unit. Each gets a stable random ID, empty artwork and no automatically invented links.
- A shared typed grid form drives creation and the inspector. Hex size is labeled as radius in board units, distinct from native distance per cell. Gridless boards retain unit/configuration metadata without fabricating cells. Existing custom unit labels survive editing other fields.
- `AtlasCreateMap` and `AtlasGridEdit` use the same history as ink. Creation undo returns to a valid source board; redo restores the same ID/configuration. A changed or newly linked board cannot be silently removed by stale creation undo. Grid commands reject invalid/no-op/stale inputs and reset stale cell selection when geometry changes.
- Overlay edits do not rewrite vectors, link positions or placement transforms. Legacy cell terrain keeps a frozen geometry basis (`terrain_grid`), even when the overlay changes shape or becomes gridless. Prototype terrain painting is blocked when its original geometry no longer matches the overlay; freehand drawing is unaffected.
- Grid rendering uses visible bounds and hides overly dense grids rather than drawing an incomplete central patch or stalling the board. Stored geometry is unchanged.
- Runtime schema **v3** persists visibility/terrain basis and accepts v1/v2 campaigns. Full-precision JSON preserves rotation and other numeric settings exactly through the real store. The single-slot save remains non-atomic; recoverable persistence is milestone 3.

### Milestone 2 verification

- `tests/board_grid_smoke.gd`: **448 checks** covering all four grid modes/five units, creation guards, stale undo, snapshots, exact artwork/terrain invariance, saved branches, invalid data, legacy defaults and real-store precision.
- Integrated viewport tests exercise the actual creation dialog/inspector, cancellation, undo/redo, original-map isolation and save/load with unchanged ink.
- Native framebuffer checks report **zero terrain pixels moved** after changing overlay geometry, alongside ink/erase/undo and compact 800×600 dialog/layout checks.
- Browser checks create a configured board through the form, draw, edit its overlay, compare exact saved ink/source-board data, undo/redo, and reload/re-save through IndexedDB. No script/browser errors are accepted.
- KWin live-session input also edited cell size to 96, created a blank board and verified its grid. The dedicated preview had a separate save path; the user's default save was not written.

## UI consistency follow-up

There is one real Godot `MenuBar`, with `PopupMenu` children for File, Edit and View. File owns new board/save/load/reset; Edit owns undo/redo with history-aware enabled states; View owns sidebar/grid toggles and Back. Accelerator hints retain the existing context-aware keyboard handlers, so text/numeric inputs keep their own undo behavior.

The duplicated workspace command row and ink strip are removed. The document title/dirty marker sits at the right of the single top bar, and the canvas starts directly beneath it. A padded inspector groups Tools, Ink, Map and Links/References; terrain/placement controls appear only for their corresponding tool. Menus, inputs and controls share the dark theme and focus styling.

The integrated smoke test checks the single-bar layout, menu dispatch/state, title updates and focused-input undo. The browser smoke invokes File Save and Edit Undo/Redo through their actual menus, exercises View, captures the menu popups, and retains artwork/IndexedDB reload checks.

## Execution milestone 1 — freehand drawing

Implemented on top of the integration checkpoint:

- Typed `AtlasStroke` vector artwork in continuous document coordinates. Ink crosses grid cells freely and works without a grid; changing grid geometry does not rewrite stroke data.
- Pen color/width, grid-overlay visibility, and a geometric eraser that splits ink into surviving vector fragments. The eraser accounts for ink width and swept motion, including long/fast segments and dots; it does not paint a background-colored patch. This is a round vector centerline eraser, not raster pixel editing.
- One press/drag/release is one drawing command. Pending strokes are previews, not persistent edits. Escape, tool changes, resize, focus loss and map switches cancel pending ink. Wheel zoom is suppressed during a drawing gesture, and leaving the canvas stops adding points so editor chrome is not drawn through.
- Campaign-local undo/redo captures deep before/after snapshots and the original map/floor target. Saved checkpoints use unique history states, including after divergent branches. Successful Save clears the dirty asterisk; undo away from a save makes it dirty again. Failed Save cannot clear dirty state. Load/reset replaces the old history.
- **B**: pen; **E**: eraser; **Ctrl/Cmd+Z**: drawing undo; **Ctrl/Cmd+Shift+Z** or **Ctrl/Cmd+Y**: redo; **Ctrl/Cmd+S**: save; **Escape**: cancel preview. Text inputs retain their own keyboard editing behavior. In the legacy battlemap tool Q/E still rotates the footprint.
- Vector artwork is structured JSON, not a raster image. Campaign schema **v2** carries strokes; v1 files load with empty ink, while old v1-only readers reject v2 rather than silently discarding artwork. Invalid new stroke payloads reject loading instead of dropping ink.

New code: `scripts/artwork/stroke.gd`, `atlas_edit_command.gd`, `atlas_stroke_edit.gd`; `scripts/editing/history.gd`, `atlas_stroke_eraser.gd`. Layer ordering/locking, raster artwork, stroke selection and optimized delta/chunk histories are later milestones. Current history snapshots all ink on an edited floor, which is suitable for this initial slice rather than a large-campaign memory solution.

### Milestone 1 verification

- `tests/artwork_smoke.gd`: **174 checks passed**, covering vector validation/roundtrips, partial swept erasure, dots, history isolation, stale/no-op commands, deep snapshots, original targets, redo branches and saved-state tracking.
- `tests/smoke.gd`: passes including real viewport mouse/keyboard input on a gridless board, negative/subcell coordinates, one gesture per command, erase/undo/redo, cancellation, save/load and failure dirty-state handling. Tests use a separate save path, never the user's real slot.
- `tests/visual_smoke.gd`: passes framebuffer clipping plus actual ink pixels, an erased gap revealing original board background, surviving ink and undo restoration. Screenshots include `user://validation/freehand.png`, `erased.png` and `undo-erase.png`.
- `tests/browser_smoke.py`: passes actual Web mouse/keyboard drawing, erasing, undo/redo, and exact vector persistence through IndexedDB → page reload → re-save, together with the independent native-unit regression.

## Integration checkpoint — 2026-10-23

The `gpt/feat/gdscript-editor-scaffold` prototype has been reconciled with the current `origin/main` and the local activity sidebar on `aidev`. Origin's addons, utilities, input actions and display/render settings are retained. This is one tested integration milestone, **not** a completed drawing editor or VTT.

**Drawing-board-first:** continuous artwork is the product's primary content. Optional grids provide exploration/measurement overlays; linked maps do not require recursive physical subdivision. The inherited cell-painting tool remains a prototype while document-space freehand drawing is the next slice.

## Technology constraints

- **Engine:** Godot **4.8-beta1**, standard build (`4.8.beta1.official.4d10419ca` locally). Do not downgrade to the scaffold's former 4.7.2 baseline.
- **Application language:** typed GDScript; no C# or mandatory GDExtension. The inherited `.NET` assembly-name setting is inert metadata, not an application dependency.
- **Rendering/export:** Compatibility / WebGL 2, single-thread Web, extension support off. The Web preset keeps development tests out of the exported application.
- **Canonical raster storage:** lossless `.webp`; only derived previews may be lossy. Typed raster layers store verified, content-addressed WebP chunks. PNG screenshots/test fixtures/export-shell icons are not canonical campaign artwork.
- **Browser storage:** `user://` maps to IndexedDB in the tested Chromium environment. Browser profiles/quota/private-mode policies still determine durability. Native file pickers, windowing or threads are not core requirements.

## Running behavior

Open `project.godot` in Godot 4.8-beta1 and run the main scene (F5).

- **Sidebar:** Maps lists campaign documents; Search filters name/type and opens results by double-click; Layers controls ordered tile/ink/raster content. Clicking the active icon collapses/reopens the panel. Ctrl+B / Command+B toggles it; dragging its divider changes width.
- **Canvas:** freehand ink plus legacy cell paint/select/lock, pointer-centered wheel zoom, and middle/right-drag pan. The canvas clips its custom drawing, so artwork/grid/preview commands cannot paint over editor chrome. The inspector scrolls when its controls exceed the available height.
- **Navigation:** use map/search results, a double-clicked link marker or Back. Automatic linked-map zoom is **off by default**. When explicitly enabled, exactly three additional logical steps at the zoom limit enter/return; leaving the link or beginning another interaction resets pending progress.
- **Native map scale:** the inspector separates native distance/unit from overlay spacing, shape, origin and rotation. Neither operation rescales artwork or converts linked maps. The sample world uses 3 mi/cell; loaded values are preserved.
- **Inherited encounter prototype:** drag a rotated footprint to create an independent encounter map. In Select mode, double-clicking a marker navigates; Pen/Eraser clicks stay drawing actions. Spatial terrain references are read-only; symbolic placements do not render child art as a physically aligned overlay. Parent freehand-reference previews still await refinement. This is a secondary feature, not the next development priority.
- **Persistence:** Save/Load uses `user://drawinatlas_campaign.json` with a validated `.bak` and adjacent `.assets` chunks. Recovery is reported; failed Load never replaces active work.
- Existing F11 / Alt+Enter fullscreen and F5 reload actions are routed through `util/global_shortcuts.gd`.

## Code layout

```text
main.tscn                      Origin scene root + CanvasLayer UI
prefab/ui.tscn, ui.gd           Menu, split layout and sidebar integration
prefab/sidebar.tscn, .gd        Reusable activity rail/view container
scripts/campaign/              Grid, floor, independent maps, links and placements
scripts/editing/, navigation/    History, three-step gate and document navigation
scripts/persistence/            Staged store/IO and WebP codec
scripts/interface/editor.gd      Workspace composition, session and document commands
scripts/interface/inspector.gd   Scene-owned inspector presentation and intents
scripts/interface/campaign_browser.gd Maps/search/forms and read-only previews
scripts/interface/artwork_editor.gd Scoped edits, selection/import and clipboard
scripts/navigation/map_navigator.gd Per-workspace view memory, zoom and Back
scripts/interface/canvas.gd      Clipped canvas rendering, picking and input
tests/smoke.gd                 Headless domain + integrated scene checks
tests/artwork_smoke.gd         Vector artwork, eraser and drawing history checks
tests/board_grid_smoke.gd      Board/grid commands, migration and invariance checks
tests/layers_smoke.gd          Typed layer transactions and migration/validation
tests/storage_smoke.gd         Failure-injected storage and exact raster roundtrips
tests/layer_ui_smoke.gd        Native UI layer/repair integration
tests/fill_scope_smoke.gd      Bounded fills, raster brush and central cell scope
tests/clipboard_smoke.gd       Typed, self-contained clipboard codec
tests/selection_smoke.gd       Outline/selection/transform and migration checks
tests/tools_ui_smoke.gd        Native editing gestures, clipboard and persistence
tests/editor_modules_smoke.gd  Forms, module wiring and two-workspace isolation
tests/visual_smoke.gd          Real framebuffer clipping regression
tests/browser_smoke.py         Optional external Playwright UI/storage smoke
```

## Repeatable validation

With the exact beta executable available as `godot`:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/smoke.gd
godot --headless --path . --script res://tests/artwork_smoke.gd
godot --headless --path . --script res://tests/board_grid_smoke.gd
godot --headless --path . --script res://tests/layers_smoke.gd
godot --headless --path . --script res://tests/storage_smoke.gd
godot --headless --path . --script res://tests/layer_ui_smoke.gd
godot --headless --path . --script res://tests/fill_scope_smoke.gd
godot --headless --path . --script res://tests/clipboard_smoke.gd
godot --headless --path . --script res://tests/selection_smoke.gd
godot --headless --path . --script res://tests/tools_ui_smoke.gd
godot --headless --path . --script res://tests/editor_modules_smoke.gd
godot --headless --path . --script res://tests/organization_ui_smoke.gd
godot --headless --path . --script res://tests/floors_view_smoke.gd
godot --headless --path . --script res://tests/overview_smoke.gd
godot --headless --path . --script res://tests/preview_cache_smoke.gd
godot --headless --path . --quit-after 10
godot --path . --script res://tests/visual_smoke.gd
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

Browser validation is deferred for current development. When revisited, optional tooling can run in an isolated uv environment (the extended M3 path remains unverified):

```sh
uv run --no-project --with playwright python -m playwright install chromium --only-shell
uv run --no-project --with playwright python tests/browser_smoke.py
uv run --no-project --with playwright python tests/browser_smoke.py --extended-storage
```

The visual test requires a real display/renderer and writes `user://validation/integrated-editor.png`. It compares rendered images with and without the canvas: drawing must change pixels inside the canvas and **zero sampled pixels outside**. The browser test uses an isolated profile and fixed 1280×720 viewport, captures UI states, changes Greyhaven to 7.5 km/cell while the world remains 3 mi/cell, saves to IndexedDB, reloads, re-saves, and checks the resulting campaign exactly. It also fails on browser/script errors.

### Verified locally

- Exact-beta script import and main-scene headless launch: passed.
- Smoke suite: grid/placement geometry, JSON and file roundtrip, independent units, lossless WebP, default no-navigation, opt-in three-step gate, pointer reset, cell lock, parent isolation, sidebar search/collapse: passed.
- Real native framebuffer regression: passed, zero sampled pixels changed outside the canvas.
- Web release export using matching **4.8-beta1** single-thread templates: passed.
- Isolated Chromium/WebGL 2 UI plus IndexedDB save → page reload → re-save: passed without script/browser errors and without cross-origin isolation headers.

The GitHub workflow is updated to install/check the exact beta and run headless checks/Web export. No remote CI run is claimed. The user's custom godot-ci image/tag is not established by this checkpoint; the workflow uses the official matching engine/templates instead of guessing that image.

## Remaining limitations / next milestone

Execution milestones 1–4 are complete for the local client. Next is floors and map organization/overview/previews (milestone 5), not additional battlemap recursion. Web smoke remains deferred rather than part of this completion claim.

Legacy linked-map placement actions still await undoable commands; floor-switching UI and campaign import/export UX are later work. See milestone 4 for conservative scope/selection semantics and raster limits. Trackpad behavior beyond the tested wheel normalization remains device-dependent. Milestone 3 storage/history scaling limits and deferred browser validation still apply.
