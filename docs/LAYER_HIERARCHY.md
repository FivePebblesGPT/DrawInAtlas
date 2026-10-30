# T-018 — compact authored-detail and map-link hierarchy (review candidate)

**Status:** interactive design candidate; product acceptance **pending**. The user has not yet approved relationship semantics, discovery or space use. See [[Tickets/T-018]] and [[Index]].

## Proposed relationship model

- **Board / authored detail D0–D32:** one continuous document coordinate space, not a child document per grid hex. Switching viewing detail or editing layer cannot create new map documents or transform artwork.
- **Layer:** explicit editing target within a single authored detail level. An ink layer owns individual editable strokes; raster selections currently operate on the whole raster layer, and terrain remains cell-based.
- **Object:** rows under their owning layers. Currently individual ink strokes, whole raster objects and terrain summaries. New typed editable path and text objects must appear under their owning layer when T-026/T-027 introduce those types; their interaction is not implemented by this ticket.
- **Map link:** a directed reference to an *independent* map/floor, shown in a separate `MAP LINKS` group. Links do not own artwork. A marker's **Locate** action centers the current board without retargeting editing; **Edit** opens the existing metadata form; **Enter** navigates to that independent destination. Existing spatial legacy placements remain readable/editable; new battlemat containers are not created.
- **Grid:** geometry and measurement settings live in the toolbar's Grid popover (T-008), not the hierarchy or map-link rows. Editing masks remain in the inspector and are not document links.

## UI candidate

The Layers sidebar now contains a single compact expandable Tree with D-group headers, layer rows and nested object rows, plus a distinct map-link group. Selected layers show an editing-target mark. Clicking a layer selects it; clicking a stroke selects that object on its actual owning layer. Separate link-row icons locate, edit and enter. `+ Link to independent map…` opens the existing form for creating a *marker* to an existing document. An inline action on each layer row selects it and opens its settings. A disclosure shows layer name, visibility, lock, authored-detail assignment and opacity; the existing icon toolbar handles creation, import and reordering. The old inspector `Linked maps…` button is hidden, and the View menu opens the Layers sidebar rather than a second link entry surface.

Long object lists are bounded at the first 80 strokes per ink layer (with an explanatory overflow row) to protect sidebar responsiveness. This does not restrict the artwork count or selection through the canvas. Expansion state survives layer-model redraws, but is a transient UI preference, not persisted in campaign saves.

## Evidence and acceptance gate

`tests/layer_hierarchy_smoke.gd` demonstrates authored grouping, object selection, link actions, disclosure and unaffected campaign identity. `tests/layer_hierarchy_visual.gd` verifies rendering and canvas clearance at 960×660 and 800×600 using real X11/Mesa framebuffer output. Screenshots are recorded in the ticket's execution evidence.

**Owner review needed:** whether *Find* should share this view, the exact link-row actions and category labels, discovery of object rows when an ink layer contains many strokes, and whether the sidebar is dense/readable enough at compact sizes. Do not check T-018 in the index before that review, or treat the placeholders for paths/text as already implemented.
