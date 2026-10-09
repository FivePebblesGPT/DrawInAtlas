# Product Design Specification

**Status:** proposed design, October 2026. Nothing here implies that the feature is already implemented.

## 1. Purpose and audience

DrawInAtlas is a map-centric creative editor and tabletop presentation application built with Godot. It is optimized for West Marches campaigns, where a GM needs to maintain a large, explorable hexcrawl while also drawing settlements, dungeons, building floors, and one-off encounter maps. The central product metaphor is **a whiteboard of connected, independently editable maps**.

Primary user: a GM preparing and running a local table with a projector. Secondary users: remote players, assistants/co-GMs, and collaborative worldbuilders. The initial release should not try to replace a full rules-engine VTT.

## 2. Non-negotiable interaction rules

1. **Exactly one active editable `MapDocument` per editor workspace.** Parent/child art shown concurrently is read-only.
2. **Map scale is not the same as floor elevation.** A tower's floors are contained in a map, not represented by repeatedly zooming geographically.
3. **Links need not imply physical correspondence.** A city symbol inside one six-mile hex may link to a freeform city map of unrelated dimensions. Geographically aligned links are optional.
4. **Any map can host battlemap placements.** The user draws and rotates a footprint to instantiate a child battlemap with its own workspace, layers, grid, and objects.
5. **Automatic semantic zoom uses a three-wheel-step buffer** at both maximum (enter child) and minimum (return) zoom boundaries. The wheel input that first reaches a boundary does not count.
6. **Child maps are discoverable without visiting them.** Provide markers, thumbnails, spatial previews where meaningful, and a searchable overview of child maps.
7. **Tile editing is unrestricted by default.** An optional selected-cell lock clips edits to one hex/square, while allowing camera navigation and selection outside it.
8. **The projector never exposes GM-only layers or unrevealed previews.** Player presentation and editor state are different views.

## 3. Key workflows

### 3.1 Draw a hexcrawl, then add detail

1. Open or create a campaign; create a world map with six-mile hexes.
2. Paint terrain into hex cells; optionally paint roads/rivers across neighbors.
3. Place a settlement marker inside a hex and link it to a new city document.
4. Enter the city by clicking its marker or by deliberately zooming through the semantic boundary.
5. Draw the city with independent layers, assets, and a square or gridless reference grid.
6. Return to the original world camera position via Back or zooming out through the buffered boundary.

### 3.2 Create a battlemap anywhere

1. In the active parent map select **Create Battlemap Grid**.
2. Drag a rectangular footprint; rotate freely with a handle or shortcut, optionally snap angle.
3. Choose columns/rows, grid cell size, and whether the footprint is **spatially aligned** or **symbolic**.
4. Choose persistent battlemap or temporary encounter (later milestone).
5. Enter the new **independent** battlemap document. Only its content is editable.
6. By default, show the parent artwork as a translucent **read-only reference underlay**; permit hiding it and changing opacity.
7. Paint encounter detail and place objects/tokens without changing the parent map.
8. Return to the parent view; moving/rotating the footprint on the parent need not destructively resample the child art.

### 3.3 Find an old encounter map

1. On the current region or world map enable child-map markers or thumbnails.
2. Inspect adjacent hexes without entering each one.
3. Open a **Map Overview** listing descendants attached to the visible area, selected cell, or entire map.
4. Filter by name, tags, kind, or path; hover/expand for preview.
5. Click a result to focus its anchor or enter its document. Ambiguous overlapping links are selectable, never chosen silently.

### 3.4 Constrain edits while painting a single tile

1. Select a hex or square using the selection tool.
2. Toggle **Lock edits to selected cell**. If no cell is selected, the locked state blocks edits rather than silently choosing one.
3. Brush strokes, fills, cuts, pastes, object placements, and spatial battlemap footprints obey the selected-cell boundary.
4. Toggle the lock off to continue painting roads or rivers across neighbors (default behavior).
5. Camera movement, preview inspection, and choosing a different selected cell always remain available.

### 3.5 Run a projected encounter

1. GM uses a full editor/control view; projector runs a separate fullscreen player view.
2. Player view contains only allowed map layers, revealed fog, tokens, and approved labels.
3. GM controls player camera/map independently (with optional follow-GM behavior).
4. Calibrate the projected grid to physical miniature size.
5. Later: join remote clients, sync approved operations, and enforce the same visibility model at the network boundary.

## 4. Feature catalogue and release priority

| Area | Main features | Target |
| --- | --- | --- |
| Campaign management | Documents, links, names/tags, searchable index, assets | MVP |
| Canvas | Pan, geometric zoom, cursor-centric zoom, grid overlays, fit view | MVP |
| Tile editing | Brush, eraser, bucket, line, tile palettes, selection | MVP |
| Raster/object editing | Raster brush, layer selection, cut/copy/paste, props | MVP/next |
| Layers | Ordered stacks, visibility, lock, opacity, rename | MVP |
| Grids | Hex pointy/flat, square, gridless, distance units, snapping | MVP |
| Battlemap creation | Drag/resize/rotate grid; separate document and reference | MVP |
| Navigation | Manual links, history, three-step buffered semantic zoom | MVP |
| Discovery | Markers, thumbnails, overview/search; spatial overlays | MVP/next |
| Vertical floors | Independent floor layers, basement/roof, floor switch | Next |
| Persistence | Save/load, autosave, undo/redo, chunking | MVP/next |
| Projector | Dual views, grid calibration, fog and secret visibility | Next |
| Multiplayer | Hosted sessions, cursors, synced commands, owner/role ACL | Later |
| Advanced VTT | Initiative, measurement shapes, lights, dynamic LOS, dice | Optional |

The MVP should prioritize the architectural vertical slice over large brush libraries or an advanced VTT rules system.

## 5. UI and interaction model

Suggested desktop layout:
- Left: campaign/map graph and location search.
- Center: active canvas; cursor hints and three-step boundary progress appear non-modally.
- Right: context panel (layers, floor, selected cell, Map Overview, object properties).
- Top: selection, painting, grid-placement, and reference/preview tools.
- Bottom: active map, grid/distance, layer, edit-scope, preview mode, zoom, and save state.

### Preview modes on a parent map

- **Off:** no child indication.
- **Markers:** child existence/type/count; best for broad hexcrawls.
- **Thumbnails:** cached read-only images anchored near relevant locations.
- **Overlay:** spatially aligned child previews transformed over the parent's canvas; symbolic links fall back to pinned thumbnails.

For multiple linked documents at one anchor, display a collapsible stack. Show map name and breadcrumbs on hover. The overview panel can search recursively with bounded depth; render no unauthorized GM previews for player clients.

### Reference modes inside a child map

- Parent reference appears behind editable child content.
- Default semitransparent; independently set visibility and opacity.
- Crop, origin, and rotation are retained as reference settings.
- For spatial placements, crop/transform derive from footprint geometry.
- For symbolic placements, choose a reference region manually; no false claim of real-world alignment.
- References do not participate in selection, bucket fill, clipboard, or ordinary exports unless intentionally flattened by the user.

## 6. Explicit non-goals for the first release

- Full D&D character sheet, combat system, automation and initiative tracker.
- Physically accurate cross-scale projection for every link.
- Automatic continuous blending of all hand-drawn art at every scale.
- Real-time multi-writer CRDT editing in the first implementation.
- Dynamic light/vision simulation in the MVP.
- Seamless editing of multiple map levels at once.

## 7. UX acceptance criteria

- A world hex links to a city with its own grid and arbitrary canvas size.
- A city contains two overlapping, differently rotated battlemap footprints; choosing one is deterministic.
- The battlemap has an independent editable workspace with adjustable read-only parent underlay.
- A three-step inward wheel buffer never switches maps before its third **additional** step; outward uses the same rule.
- The viewer returns to its previous map and camera via history.
- The map overview finds encounters under multiple adjacent hexes without entering any of them.
- With cell lock OFF, a road stroke crosses a hex border; with lock ON it is clipped to the selected hex.
- The GM's secret content is absent from unauthorized projector/network previews.

See [Architecture](ARCHITECTURE.md), [Maps and grids](MAPS_AND_GRIDS.md), and [Semantic zoom](SEMANTIC_ZOOM.md) for implementable contracts.
