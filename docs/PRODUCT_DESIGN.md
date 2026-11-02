# Product Design Specification

> [!important] Active product contract and evidence (2026-11-02)
> The owner-approved decisions are [[DECISIONS_DRAWING_ATLAS_2026-11-01]] and the approved feature inventory is [[DRAWING_FEATURE_INVENTORY]]. This page describes the current **two-application** target and verified implementation. The compact BarDivider workspace is still a **proposed** layout ([[DRAW_MODULE_UI_SPEC]], T-063), not hands-on approval. T-056/T-059 retain final UX signoff; T-009 retains Search/Find naming and scope approval.

## 1. Purpose and audience

DrawInAtlas serves a GM authoring a continuous map/world for local tabletop play, alongside an independently usable **Drawing** editor for raster art, text and reusable objects. A West Marches campaign may contain multiple independently navigable maps, but detail within one map is *not* a tree of per-hex child documents. Local Windows/Linux desktops are the active release target. Web is archived under T-044; network multiplayer and projector privacy gates are not complete.

The product separates **Atlas** (campaigns, map graph, floors, authored-detail selection, grids, entrances, linked objects, global history, player presentation) from the **generic Drawing package** (drawing documents, layer/group tree, brush and selection transactions, text, snapping, rendering, standalone file I/O and local history). Both applications use the same source package `addons/drawing/`; the standalone project's build stages that package without Atlas code. See [architecture](ARCHITECTURE.md).

## 2. Current and approved interaction rules

1. **Map → Floor → Detail → Layers.** Atlas owns map IDs and floor IDs; the `(map_id, floor_id, D-level)` registry resolves exactly one **internal** `DrawingDocument` per detail. These are not user-facing files/tabs. Standalone Drawing owns independent ordinary document tabs. A floor is an Atlas metadata grouping, not a Drawing-specific type. ([T-051](Tickets/T-051.md), [T-061](Tickets/T-061.md))
2. **Continuous signed space and explicit densities.** All D0–D32 of one map align in the same world coordinates. Each detail may use a different rational pixel density. A hex selects or constrains content; it never owns a separate drawing document. ([world mapping](DRAWING_WORLD_MAPPING.md))
3. **Blank missing detail.** Switching to an unpainted D-level shows no D0 art as an underlay. Grid, entrance and navigation overlays remain functional. Derived preview LOD is a different mechanism from authored D-level selection.
4. **Paint first; navigate deliberately.** Painting over an entrance paints; qualified double-click in Selection/Object Selection or Pan may navigate. Atlas owns the same-entrance arbitration, not Drawing's brush. ([composition](DRAWING_ATLAS_COMPOSITION.md))
5. **Object reuse is source/instance based.** Create a Drawing-powered Object Asset; place distinct Atlas instances with IDs and transforms. Editing a draft does not publish. Save updates linked instances, Save As from instance A creates new asset B and rebinds A alone; undo rebinds A without deleting B. Nested assets/Asset Browser remain T-064/T-065 work. ([asset guide](../scripts/objects/README.md))
6. **History belongs to the host.** Standalone Drawing has local undo/redo; Atlas has one global chronological undo across maps/details and restores the originating editing context. Navigation alone does not add history entries; zoom remains unchanged during undo. Selection-only history is optional and OFF by default. ([T-054](Tickets/T-054.md))
7. **One text element per text layer.** Selection of Text does not create a layer; successful text commit does. Rasterization is explicit and undoable; portable licensed font bytes are saved. ([T-058](Tickets/T-058.md))
8. **Publishing and privacy remain gated.** Player/projector views must be authorized at the data boundary, but T-039/T-043 have not received required approval. No test fixture or feature-inventory approval grants publication permission.

## 3. Supported end-to-end user flows versus remaining scope

### 3.1 Author a world and detail (implemented minimum path)

1. Create/open an Atlas campaign and select a map, Atlas floor and D-level; select the canonical raster editing target.
2. Paint or erase in the active DrawingDocument. Edit transactions pin the starting map/floor/detail even if the view changes mid-gesture; the same gesture is one Atlas history command.
3. Switch from authored D0 to an empty D1: D1 artwork is transparent; the grid and entrances remain visible. Switch back to D0 to see D0 art.
4. Save the **entire portable project directory**, not just a `Campaign.scn` path. `Campaign.atlas.json` points to immutable `Drawings/` generations, linked `Objects/` versions and licensed `Fonts/`. Reopen and verify exact pixels, stable IDs, and a blank untouched D-level. ([T-066](Tickets/T-066.md))

### 3.2 Edit reusable art (implemented lifecycle, future browser)

1. Open a dedicated Object Editor for an object source/instance; paint, edit text or modify layers in a private Drawing draft.
2. **Save** publishes the source version to all its linked instances. **Save As** from instance A publishes B and rebinds only A; undo/redo changes the binding without removing B.
3. Nested reusable assets, cycle-safe dependencies and the complete Asset Browser dock are **not yet delivered** (T-064/T-065). The proposed compact workspace remains T-063.

### 3.3 Independent Drawing (implemented minimum witness)

Start the standalone Drawing Godot project without the Atlas root. Create group/layers; brush and erase; select/move pixels; undo/redo; save and reopen a portable `.drawing` file. Text can be edited and rasterized explicitly. Its minimum end-to-end witness is **not** equivalent to completion of all 47 Essential inventory items or the owner's final UX approval.

### 3.4 Navigation, projected play and discovery (mixed)

Atlas map links are independent navigation targets and can have multiple incoming entrances. The historic rotated child-battlemap footprint is compatibility geometry, **not** the preferred new art-reuse workflow. An authored higher-detail level lives on the same map/world reference, and a linked city/dungeon is a separately navigable map with its own coordinates. Existing navigation and previews have test coverage, but Search/Find product purpose is pending T-009; projector privacy and publishing are pending T-039/T-043. The Web client is not an active deliverable.

## 4. Product scope and acceptance boundaries

| Area | Proven implementation | Still pending / requires other ticket |
| --- | --- | --- |
| Canvas and Painting | Canonical shared raster editing, layers/groups, selection/move, text, signed sparse tiles | Full 47-Essential inventory, polish and T-059 owner acceptance |
| Map/Detail/Navigation | Atlas floor/detail registry, blank D-levels, grids, entrances, bounded previews | UX acceptance T-056, T-017 floor link validation |
| Reusable art | Object source/instance registry, dedicated editor, Save and Save As | T-064 nested assets; T-065 browser dock |
| Storage | T-066 versioned root pointers, immutable sparse blobs and recovery | Future physical packs, 512 default adoption, arbitrary-power-loss verification |
| Performance | T-067 tile benchmark, T-068 optimized tile-run renderer | T-068 native library and GDExtension comparison; T-057 GPU research |
| Player, Search, Collaboration | Separate engineering proofs and current navigation functionality | T-009/T-039/T-043/T-048 review gates and production integration |

**Historical proposal (superseded):** the October 2026 concept used Create Battlemap Grid, nested child battlemap footprints, a default parent-art underlay, palette-painted terrain hexes and linked whole-map drawings as the main art reuse mechanism. Those are **not** the active accepted authoring contract. New authoring uses shared-world D-levels and linked Object Assets. The old placement audit remains only a read-only/historical diagnostic; see [legacy placement](LEGACY_PLACEMENT_MIGRATION.md). The desired user-facing compact UI is still a proposal, not automatically accepted.

## 5. Practical acceptance examples

- A stroke crossing a hex boundary reaches both cells when the selected-cell edit mask is off; when on, it clips without creating per-hex documents.
- Switching to an unpainted higher D-level exposes blank pixels but preserves entrance navigation overlays.
- Two Atlas maps place the same published Object Asset; a private edit changes neither until Save, then both resolve the new version. Save As from one placement produces independent B and undo retains B.
- Undo an edit originally made on another map: show the originating map/detail without changing zoom, and pan only if affected content was not already partly visible.
- Move a saved project directory: manifests, signed raster addresses, Object Asset links and font license survive. A missing referenced file generates a diagnostic rather than a fabricated blank image.
- Publish GM-only content to player/projector **only after** independent policy/security acceptance under T-039/T-043, not on the strength of editor tests.

See [architecture](ARCHITECTURE.md), [data model](DATA_MODEL.md), [Drawing inventory](DRAWING_FEATURE_INVENTORY.md), and [verification plan](DRAWING_TEST_PLAN.md).
