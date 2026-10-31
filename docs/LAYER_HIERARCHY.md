# T-018 — compact authored-detail and map-link hierarchy (review candidate)

**Status:** interactive design candidate; product acceptance **pending**. The user has not yet approved relationship semantics, discovery or space use. See [[Tickets/T-018]] and [[Index]].

## Proposed relationship model

- **Board / authored detail D0–D32:** one continuous document coordinate space, not a child document per grid hex. Switching viewing detail or editing layer cannot create new map documents or transform artwork.
- **Layer:** explicit editing target within one authored detail level. Raster layers own chunked paint pixels (currently selected as whole layers); Objects layers own individually editable paths, text, props and legacy stroke records. The retired terrain-cell paint model is not an authoring target.
- **Object:** rows under their owning Objects layers for editable paths, text, image props and other legacy stroke objects. Raster layers expose a whole-layer pixel summary; raster paint pixels are not individual selectable objects. The hierarchy reflects the raster-first model (T-049), not a separate ink-authoring target.
- **Map link:** a directed reference to an *independent* map/floor, shown in a separate `MAP LINKS` group. Links do not own artwork. A marker's **Locate** action centers the current board without retargeting editing; **Edit** opens the existing metadata form; **Enter** navigates to that independent destination. Existing spatial legacy placements remain readable/editable; new battlemat containers are not created.
- **Grid:** geometry and measurement settings live in the toolbar's Grid popover (T-008), not the hierarchy or map-link rows. Editing masks remain in the inspector and are not document links.

## UI candidate

The Layers sidebar now contains a single compact expandable Tree with D-group headers, layer rows and nested object rows, plus a distinct map-link group. Selected layers show an editing-target mark. Clicking a layer selects it; clicking a stroke selects that object on its actual owning layer. Separate link-row icons locate, edit and enter. `+ Link to independent map…` opens the existing form for creating a *marker* to an existing document. An inline action on each layer row selects it and opens its settings. A disclosure shows layer name, visibility, lock, authored-detail assignment and opacity; the existing icon toolbar handles creation, import and reordering. The old inspector `Linked maps…` button is hidden, and the View menu opens the Layers sidebar rather than a second link entry surface.

Long object lists remain bounded to **80 regular object rows per Objects layer**: the oldest 40 and newest 40 are shown when there are more than 80. The skipped middle is explicitly summarized. When a middle object is selected on the canvas, a single temporary row appears in canonical index order and scrolls into view; it is removed on deselection, multi-selection or a stale object snapshot. The 80-row limit does not restrict the actual artwork or canvas selection. Expansion state survives layer-model redraws, but is a transient UI preference, not persisted in campaign saves.

## Evidence and acceptance gate

`tests/layer_hierarchy_smoke.gd` demonstrates authored grouping, object selection, link actions, disclosure, unaffected campaign identity, bounded large-object grouping and temporary selection rows. `tests/layer_hierarchy_visual.gd` verifies rendering, canvas clearance and selected-row visibility at 960×660 and 800×600 using real X11/Mesa framebuffer output. Screenshots are recorded in the ticket's execution evidence.

**Owner review needed:** whether *Find* should share this view, the exact link-row actions and category labels, discovery of object rows when an Objects layer contains many entries, and whether the sidebar is dense/readable enough at compact sizes. T-026/T-027 now provide path/text objects, but this does not imply their interaction has received owner acceptance. Do not check T-018 in the index before that review.
