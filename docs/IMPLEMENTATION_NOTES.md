# Implementation Notes

## Integration checkpoint — 2026-10-23

The `gpt/feat/gdscript-editor-scaffold` prototype has been reconciled with the current `origin/main` and the local activity sidebar on `aidev`. Origin's addons, utilities, input actions and display/render settings are retained. This is one tested integration milestone, **not** a completed drawing editor or VTT.

**Drawing-board-first:** continuous artwork is the product's primary content. Optional grids provide exploration/measurement overlays; linked maps do not require recursive physical subdivision. The inherited cell-painting tool remains a prototype while document-space freehand drawing is the next slice.

## Technology constraints

- **Engine:** Godot **4.8-beta1**, standard build (`4.8.beta1.official.4d10419ca` locally). Do not downgrade to the scaffold's former 4.7.2 baseline.
- **Application language:** typed GDScript; no C# or mandatory GDExtension. The inherited `.NET` assembly-name setting is inert metadata, not an application dependency.
- **Rendering/export:** Compatibility / WebGL 2, single-thread Web, extension support off. The Web preset keeps development tests out of the exported application.
- **Canonical raster storage:** lossless `.webp`; only derived previews may be lossy. `AtlasWebPStore` is tested, but canonical raster layers are **not implemented**. PNG screenshots/export-shell icons are validation/UI artifacts, not persisted campaign artwork.
- **Browser storage:** `user://` maps to IndexedDB in the tested Chromium environment. Browser profiles/quota/private-mode policies still determine durability. Native file pickers, windowing or threads are not core requirements.

## Running behavior

Open `project.godot` in Godot 4.8-beta1 and run the main scene (F5).

- **Sidebar:** Maps lists campaign documents; Search filters name/type and opens results by double-click; Layers honestly reports the single-terrain-layer prototype. Clicking the active icon collapses/reopens the panel. Ctrl+B / Command+B toggles it; dragging its divider changes width.
- **Canvas:** cell paint, select-cell/lock, pointer-centered wheel zoom, and middle/right-drag pan. The canvas now clips its custom drawing, so terrain/grid/preview commands cannot paint over editor chrome. The inspector scrolls when its controls exceed the available height.
- **Navigation:** use map/search results, a double-clicked link marker or Back. Automatic linked-map zoom is **off by default**. When explicitly enabled, exactly three additional logical steps at the zoom limit enter/return; leaving the link or beginning another interaction resets pending progress.
- **Native map scale:** the inspector exposes distance per cell and unit independently for each gridded map. This changes measurement labels only: no art rescaling, grid-pitch change or linked-map conversion. The sample world uses 3 mi/cell; loaded campaign values are preserved. A map-creation dialog and visual grid-spacing controls are pending.
- **Inherited encounter prototype:** drag a rotated footprint to create an independent encounter map. Spatial references are read-only; symbolic placements do not render child art as a physically aligned overlay. This is a secondary feature, not the next development priority.
- **Persistence:** Save/Load uses `user://drawinatlas_campaign.json`; File menu actions use the same pathways. Do not use the provisional single save slot as the sole copy of valuable campaign work.
- Existing F11 / Alt+Enter fullscreen and F5 reload actions are routed through `util/global_shortcuts.gd`.

## Code layout

```text
main.tscn                      Origin scene root + CanvasLayer UI
prefab/ui.tscn, ui.gd           Menu, split layout and sidebar integration
prefab/sidebar.tscn, .gd        Reusable activity rail/view container
scripts/domain/                Grid, floor, independent maps, links and placements
scripts/services/              Three-step gate, prototype JSON store, WebP utility
scripts/ui/atlas_editor.gd      Workspace controls/navigation and scaffold edits
scripts/ui/atlas_canvas.gd      Clipped canvas rendering, picking and input
tests/smoke.gd                 Headless domain + integrated scene checks
tests/visual_smoke.gd          Real framebuffer clipping regression
tests/browser_smoke.py         Optional external Playwright UI/storage smoke
```

## Repeatable validation

With the exact beta executable available as `godot`:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/smoke.gd
godot --headless --path . --quit-after 10
godot --path . --script res://tests/visual_smoke.gd
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

In a second terminal, optional browser tooling can run in an isolated uv environment:

```sh
uv run --no-project --with playwright python -m playwright install chromium --only-shell
uv run --no-project --with playwright python tests/browser_smoke.py
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

Do not expand battlemap tooling before the drawing-board slice. Freehand document-space artwork, independently adjustable grid overlays, per-map creation settings, stroke commands and undo are next.

The scaffold still mutates terrain/placements directly, with no undo or dirty-state policy. Floors/layers are not configurable. The JSON store is a single non-atomic slot, does not robustly validate all nested data, and lacks recovery/import/export UX. These are known prototype boundaries; typed commands, validation and recoverable WebP chunk storage remain future work. Selected-cell lock currently protects tile painting only, not every possible command. Trackpad gesture behavior beyond the tested wheel normalization remains device-dependent.
