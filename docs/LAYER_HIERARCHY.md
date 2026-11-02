# T-018 — compact authored-detail and map-link hierarchy (review candidate)

> [!important] Current model and proposed interaction (2026-11-02)
> Approved architecture: [[DECISIONS_DRAWING_ATLAS_2026-11-01]]; implemented registry: [world mapping](DRAWING_WORLD_MAPPING.md) and [Drawing core](../addons/drawing/README.md). This page retains **T-018's legacy Layers-tree UI proposal/implementation evidence**, not owner acceptance of the final shared Drawing workspace (T-063/T-056/T-059).

**Status:** Atlas's map/floor/detail registry and canonical Drawing layers are implemented (T-052/T-055/T-061); T-018's compact hierarchy UX remains a separately tracked Ready/design candidate. The current legacy layer list may coexist with the canonical Drawing tree during integration; do not treat all rows below as a final accepted UI.

## Implemented data ownership before the UI proposal

- **Atlas** owns `AtlasCampaign` map IDs, `AtlasFloor` metadata, grids, entrances, navigation, token/fog state and the global history. `AtlasDrawingRegistry` resolves `(map_id, floor_id, D-level)` to a stable internal generic document ID. **A floor is not a Drawing class or document type.**
- **Drawing** owns generic `DrawingDocument` layer/group trees, sparse raster pixels, text/semantic elements, editing, snapping and local history in standalone mode. Internal map/detail documents are not independently opened user file tabs; standalone ordinary drawings and dedicated Object Editor documents can be tabs.
- **Object reuse** uses `Object Asset` published sources under `Objects/` and independent `Object Instance` IDs/transforms on maps. That is distinct from a map link, which owns navigation and no reusable artwork. Instance Save As changes only the originating binding, retaining the newly saved source after undo.
- **Detail** is authored artwork D0–D32 at one shared signed world coordinate reference, with each document's explicit pixel density. A missing higher-detail drawing is blank; grid and entrance overlays still work. It is not a per-hex child file or an always-visible D0 underlay. See [T-061](Tickets/T-061.md).

**Still pending:** the polished BarDivider workspace (T-063), nested assets (T-064), Asset Browser dock (T-065), and owner UX gates (T-056/T-059). The old `AtlasInkLayer`/`AtlasRasterLayer` object rows and footprint edit commands described below are prototype compatibility UI, not a declaration of canonical Drawing layer subclasses.

## Historical T-018 relationship model and layer-tree proposal

- **Board / authored detail D0–D32:** one continuous document coordinate space, not a child document per grid hex. Switching viewing detail or editing layer cannot create new map documents or transform artwork.
- **Layer:** explicit editing target within one authored detail level. Raster layers own chunked paint pixels (currently selected as whole layers); Objects layers own individually editable paths, text, props and legacy stroke records. The retired terrain-cell paint model is not an authoring target.
- **Object:** rows under their owning Objects layers for editable paths, text, image props and other legacy stroke objects. Raster layers expose a whole-layer pixel summary; raster paint pixels are not individual selectable objects. The hierarchy reflects the raster-first model (T-049), not a separate ink-authoring target.
- **Map link:** a directed reference to an *independent* map/floor, shown in a separate `MAP LINKS` group. Links do not own artwork. A marker's **Locate** action centers the current board without retargeting editing; **Edit** opens the existing metadata form; **Enter** navigates to that independent destination. Existing spatial legacy placements remain readable/editable; new battlemat containers are not created.
- **Grid:** geometry and measurement settings live in the toolbar's Grid popover (T-008), not the hierarchy or map-link rows. Editing masks remain in the inspector and are not document links.

## Historical T-018 UI candidate (implementation evidence, no final signoff)

The Layers sidebar now contains a single compact expandable Tree with D-group headers, layer rows and nested object rows, plus a distinct map-link group. Selected layers show an editing-target mark. Clicking a layer selects it; clicking a stroke selects that object on its actual owning layer. Separate link-row icons locate, edit and enter. `+ Link to independent map…` opens the existing form for creating a *marker* to an existing document. An inline action on each layer row selects it and opens its settings. A disclosure shows layer name, visibility, lock, authored-detail assignment and opacity; the existing icon toolbar handles creation, import and reordering. The old inspector `Linked maps…` button is hidden, and the View menu opens the Layers sidebar rather than a second link entry surface.

Long object lists remain bounded to **80 regular object rows per Objects layer**: the oldest 40 and newest 40 are shown when there are more than 80. The skipped middle is explicitly summarized. When a middle object is selected on the canvas, a single temporary row appears in canonical index order and scrolls into view; it is removed on deselection, multi-selection or a stale object snapshot. The 80-row limit does not restrict the actual artwork or canvas selection. Expansion state survives layer-model redraws, but is a transient UI preference, not persisted in campaign saves.

The `MAP LINKS` rows are also **snapshot-bound action handles**. Focus, Edit and Enter
must refer to the same source document/floor, link revision, optional placement,
and destination shown in that row. If any of these change before the click,
the action is rejected, the hierarchy refreshes on the next frame, and the GM
receives a message to select the refreshed entry. This prevents navigating from
an outdated inline entry (including after deletion or reuse of a stable ID)
without altering persisted links, destination maps or save schemas.

## Evidence and acceptance gate

`tests/layer_hierarchy_smoke.gd` demonstrates authored grouping, object selection, link actions, disclosure, unaffected campaign identity, bounded large-object grouping and temporary selection rows. `tests/layer_hierarchy_visual.gd` verifies rendering, canvas clearance and selected-row visibility at 960×660 and 800×600 using real X11/Mesa framebuffer output. Screenshots are recorded in the ticket's execution evidence.

**Unresolved UX questions:** whether *Find* shares this view (T-009 has its own owner gate), the exact link-row actions/categories, large-object discovery and compact-space readability. The acceptance of the shared native workspace is under T-056/T-059, not established by the older T-018 visual tests. T-026/T-027 prototype text/path records do not make them identical to canonical Drawing text and raster layers. Ticket status remains governed by `docs/Index.md`, not this historical note.
