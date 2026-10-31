# T-009 — World discovery: scenarios, references and proposed UX contract

**Status:** Research and reproducible current-state demonstration completed on
2026-10-30. **Product naming, searchable entities, and actions are recommendations
awaiting owner confirmation**, not accepted feature requirements. No new
searchable-place model or user-facing search behavior has been implemented.

## Problem and constraints

The original question in [[ManualReview_2026-10-30]] is *“What does Search do?”*
The existing **Search** rail tab is an `AtlasOverview` browser of map/floor
metadata and directed links; its local/visible/cell modes inspect link
entrances. Its global mode enumerates independently stored map/floor documents.
The user's confirmed shared-board model ([[E-002]], [[E-006]]) instead has
continuous artwork spanning neighboring hexes, separately authored D0…Dn
artwork in the **same board coordinates**, and an explicit editing target.
A place should not need a separate child document or a hex-owned canvas to be
found. Layers/LOD are not substitutes for geographic entities. Floors are
separate from detail levels. A search result should not change the editing
layer or create a document while locating it.

## Comparative research (primary product sources)

| Product | Supported user workflow | Transferable lesson / caveat |
| --- | --- | --- |
| [LegendKeeper](https://www.legendkeeper.com/features/) | Atlas maps show pins; names in the sidebar pan to pins, and tags filter them. Its [0.7 release](https://www.legendkeeper.com/changelog/legendkeeper-0-7-0-0-fates/) describes “Fly to pin” and pin filtering; its [0.6 release](https://www.legendkeeper.com/changelog/legendkeeper-0-6-elemental/) adds project-wide search. | Distinguish **find the entity** from **locate the pin**. Do not copy its nested-map/navigation ontology: [LegendKeeper itself describes confusing differences between Atlas maps, boards and wiki pages](https://www.legendkeeper.com/progress-on-the-new-unified-ux/). |
| [World Anvil](https://www.worldanvil.com/learn/beginner-tutorials/get-started-maps) | Map markers carry names/descriptions, link to locations/articles and can show details without leaving the map. The [map guide](https://www.worldanvil.com/learn/map-making/maps) describes points, labels, lines, circles and polygons. | A discoverable place may be a point or area, and opening information needn't move/replace the map canvas. Article/wiki authoring is **not** an existing DrawInAtlas capability. |
| [Kanka](https://docs.kanka.io/en/latest/entries/maps/markers.html) | Map Explorer supports pins, labels, circles, areas and paths, associated entries, groups and per-marker visibility. | The type, location and visibility of a result matter. **Permission filtering** is a later collaboration/projection concern, not a license to expose GM secrets. |
| [Obsidian Leaflet](https://community.obsidian.md/plugins/obsidian-leaflet-plugin) | Notes can supply markers by file, folder, tag and link relationship; map markers link back to notes. | Spatial anchors can be separate from the note/metadata object; search does not require a new map per note. An Obsidian-note integration is not proposed for this ticket. |

All references above are feature documentation/changelogs, not evidence of
usability or of current support for undocumented versions. The design below
is a **DrawInAtlas proposal**, not a claim that these apps use an identical
shared-board model.

## Tasks a world builder needs to accomplish

1. **Find the town to prepare.** A GM types `Greyhaven` and sees a named
   settlement result with the containing world/region, floor and a `Locate`
   action. They jump to the marked spot on the **current shared board**, not
   automatically into a child map or a new editing target. An optional
   `Open details` action is available only when actual notes/details exist.
2. **Find tagged sites while planning a route.** Query `#ruins` within the
   visible world area (or whole campaign) and distinguish two named ruins
   with type, context and approximate position. `Locate` pans and briefly
   highlights the matching area/marker; it never paints or changes D0/D1.
3. **Locate an area across hex borders.** A named forest/river/region has a
   board-space footprint that may cross several hex cells and signed raster
   chunks. The result locates its spatial footprint; it does **not** claim
   that a cell owns a map or an independent document.
4. **Use an empty hex.** The GM navigates to an empty world cell, zooms and
   draws new detail without an existing link, searchable entity or assigned
   child map. Search can honestly return no results, without blocking
   navigation or generating a document.
5. **Disambiguate floors and levels.** Two `Old Tower` markers on different
   floors have distinct floor labels; `D1` is presentation context and never
   masquerades as a floor. Locating a result doesn't silently retarget a
   stroke in progress.

## Proposed product decisions — confirmation required

| Decision | Recommended contract | Alternatives / reason |
| --- | --- | --- |
| Rail action | **Find** (magnifier, accessible tooltip: “Find places and maps”). Panel heading **Find in world**. | `Search` describes a text operation but not a result's spatial purpose; `Explore` suggests a map browsing mode rather than targeted retrieval. No rename has been made. |
| Primary scope | **Places** on the shared board: named point markers and named bounded areas. Each has a human-readable name, kind, tags and optional description/linked notes, a board-space anchor/bounds and floor identity. | Do **not** generate places from hex tiles, document descendants or unlabeled brush strokes; don't imply arbitrary painted pixels can be semantically searched. |
| Secondary scope | Independently stored **Maps** (if they remain after legacy cleanup), and explicit link destinations and floor names, labeled as such. | Keep existing data discoverable while T-012/T-015/T-018 retire the old battlemat/link presentation; do not make these the only search entities. |
| Query/filter | Free text over display names, type and tags; `#tag` exact match; scope switch **World / Visible / Selected cell**. Optional type/floor chips when enough content exists. | “Current floor links” should not be the default discovery mode. Visible and selected-cell filters need board-space intersection, not recursive document walking. |
| Result context | Name, **Place / Area / Map / Link**, floor, world/region breadcrumb if established, concise tags/description, spatial marker or “No location” state. | Never surface raw map IDs or invented country/region names; do not imply precise position when only a legacy link is known. |
| Actions | Primary **Locate** centers and highlights an anchored point/area; secondary **Open details** only if present; **Open map** only for a real independent map; return/Back retains prior camera. | No auto-create, auto-enter child documents, automatic editing-target switch or implicit D0↔D1 change. A result without a valid anchor offers no Locate action. |
| Presentation/permissions | Preserve zoom/Lod controller and explicit edit target. Restrict GM-only results in any later player-facing search (T-039/T-043/T-046). | Privacy filtering needs an explicit player projection contract; not implemented by T-009. |

**Non-goals for this investigation:** introduce a persisted place schema, migrate
legacy map links, implement marker/region authoring, alter save format or change
automatic LOD. Those require a separately accepted design/implementation scope
and data migration policy. Future search should be indexed over authoritative
metadata, not serialized artwork images or costly per-pixel scans.

## Reproducible discovery demonstration (current implementation only)

Run from the project root with the pinned Godot 4.8 beta2 engine:

```sh
godot --headless --path . --script res://tests/research/t009_discovery_probe.gd
```

The probe opens the original Northern Marches example in an actual editor
scene. It selects **Search → Current floor links**, types `greyHAVEN` (no
internal `map_id`/`link_id` knowledge), checks the named result/breadcrumb,
presses **Focus source anchor**, and verifies that the camera centers on the
source marker while the world board, floor and editing layer stay unchanged.
It then searches globally for `Greyhaven`: it finds the document by name,
**but no board-space anchor exists in the campaign result**. A query for
`Southwatch Ruins` yields no result because arbitrary named board places are
not indexed. The probe checks that search/locate do not dirty the campaign.

This intentionally tests the **current ability and its limitation**, not a
future accepted UX. It is a manual research witness, **not wired into CI**;
future work may replace this obsolete document-link behavior.

## Acceptance and ownership boundary

- [x] Scenarios and sourced product comparisons above.
- [x] Proposed naming, searchable object types, context and actions recorded,
      with alternatives and compatibility constraints.
- [x] Reproducible no-ID search-and-locate demonstration plus explicit failure
      cases for arbitrary shared-board places.
- [ ] **Owner agrees** to the proposed label, entity scope and result actions
      *before* a production implementation starts.

The missing item is a user/product decision, not a failing engine test. Leave
[[T-009]] unchecked in [[Index]] until it is explicitly confirmed; do not
interpret passing the legacy-search witness as acceptance of the proposed
world-discovery design.
