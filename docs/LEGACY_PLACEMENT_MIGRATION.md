# T-015 — Historical battlemat ownership audit and safe-conversion proposal

> [!warning] **Historical migration proposal, not an active user migration.**
> The owner confirmed that no historical user-save migration is required. This page preserves an earlier read-only diagnostic and optional conversion discussion for archaeology, **not** a request for owner approval to modify nonexistent user data. See [[DECISIONS_DRAWING_ATLAS_2026-11-01]], [[T-015]] and [[Index]].

## Current decision and legacy-audit scope (2026-11-02)

The approved owner decision is [[DECISIONS_DRAWING_ATLAS_2026-11-01]]: **there are no historical user saves requiring migration.** Accordingly, this T-015 document is retained as a **historical design/audit record**, not a required or planned destructive migration. Do not execute its proposed copy-first converter merely because a sample map contains `BATTLEMAP`. `AtlasLegacyMigrationAudit.inspect()` remains a read-only prototype diagnostic and can be tested without converting anything. The underlying old `.scn` scene codec and placements are compatibility/test paths; new authoritative Atlas saves use verified versioned `Drawings/` generations under the `.atlas.json` root (T-066).

**2026-11-03 retirement checkpoint:** All *new* low-level `AtlasCreateMap`
commands reject `BATTLEMAP`; `AtlasLinkEdit` and the visible linked-map form
no longer create or edit parent/child footprint bundles. New map links are
independent navigation markers. The old `AtlasPlacement` record/serializer,
spatial reference presentation, and legacy migration auditor are still
compiled for historical fixtures, so T-015 is **In Progress**, not Done.
The owner waived migration, but removing these residual readers safely
remains a separate outstanding part of this same ticket. The historical
conversion proposal below is not a supported implementation plan.

The active design has generic internal `DrawingDocument` identities per `(map, floor, D-level)` under Atlas's registry, shared signed world coordinates, and no per-hex child files. Reuse authored objects through versioned `Object Assets` and linked `Object Instances` under `Objects/`; an Atlas map link is a navigation edge, *not* a reusable Drawing source. A missing D-level is blank, not a legacy child-battlemap underlay. See [world mapping](DRAWING_WORLD_MAPPING.md), [object registry](../scripts/objects/README.md), and [architecture](ARCHITECTURE.md).

**Historical conversion proposal below is not approved for implementation or needed for existing users.** T-015 may separately remove obsolete model code after regression coverage; that maintenance must not be equated to altering saved campaigns.

## Historical native-prototype ownership and compatibility dependencies

| Historical data or entry point | Native-prototype responsibility at the audit date | Former removal hazard / disposition |
| --- | --- | --- |
| `AtlasCampaign.maps` / `AtlasMapDocument`, `AtlasFloor`, `AtlasLayer` | Registry of **independent** documents, each with floors and separately authored detail layers. `kind == "BATTLEMAP"` is a historical string, **not** proof the map is safely mergeable. | Keep genuinely independent documents. Classify each legacy document and every inbound/outbound link before changing ownership. |
| `AtlasCampaign.links` / `AtlasMapLink` | Directed source-map/floor → target-map/floor navigation with arrival focus and zoom. Marker-only links need no placement. Links can be reciprocal/cyclic or target a map from several parents. | Do not flatten the entire graph or delete dangling markers. Retain meaningful inter-document navigation. |
| `AtlasCampaign.placements` / `AtlasPlacement` (`battlemap_placement.gd`) | Optional polygon for a link. Stores parent/child IDs, origin, rotation, rows/columns, **both** units-per-cell and a symbolic flag. A spatial link uses a polygon for picking, not a marker radius. | Check unreferenced, shared and mismatched placements. Never infer geographic registration from a symbolic footprint. Keep existing placement reader until conversion and rollback are verified. |
| `AtlasLinkEdit`, `AtlasCreateMap`, `AtlasEditHistory` | Snapshot-checked link/placement edits, placement sharing/undo and newly created independent documents. `AtlasLinkedMaps` and `AtlasLinkDialog` now prohibit **new** legacy footprints, but allow editing old ones. | The underlying command still accepts legacy records for compatibility and must not be deleted while old saves can be loaded. Preserve undo/redo behavior and source/target edit scopes. |
| `AtlasMapNavigator`, `AtlasOverview`, `AtlasMapReferences`, `AtlasPreviewPanel`, `AtlasLinkDialog` | Legacy navigation, backlinks, hit-testing, registered previews, parent reference crops and editing of old footprints. The current T-003 preview overlays depend on spatial registration. | Do not remove readers, visuals or backlinks until replacement references are explicitly defined. Symbolic/marker links intentionally have **no** aligned overlay. |
| `AtlasCampaignStore`, `AtlasNativeScene`, `AtlasCampaignSaveRoot`, `AtlasMapSaveNode`, `AtlasMapDocument.to_dict/from_dict` | Native `.scn` stores a Resource graph with child map nodes, validated semantic digest and exact raster images. Legacy dictionary fields remain accepted for validation and old data; native-save generation has `.bak.scn` recovery. | Preserve full original native file and backup, including raster chunk RGBA8, IDs, layer order, floor identities, grids, and art metadata. Do not bump schema or edit user save as part of an unapproved investigation. |
| `AtlasTileLayer.grid`, `AtlasRasterLayer.transform/chunks`, `AtlasStroke` | Art can be indexed by its **own** terrain grid, signed raster chunks and local raster affine transform, or by continuous stroke points/widths. Grid overlays and native measurement units are separate concerns. | Renaming a child layer into a parent is **not** an artwork conversion. Ensure exact source grid basis, transforms, α, colors, widths and image pixels remain recoverable. |

The shipped example includes Greyhaven as a separate document connected from the
world by a marker. This demonstrates a **genuine independent-map** use case; it is
not evidence that Greyhaven should be flattened. Older tests and save fixtures
also create `BATTLEMAP` documents and spatial/symbolic placements on purpose.

### Historical coordinate contract (facts, not an approved conversion)

For a non-symbolic `AtlasPlacement`, child coordinate `p` has a candidate position
on the parent board:

```text
parent_point = placement.child_to_parent() * child_point
             = origin + rotate(rotation) * (parent_units_per_cell / child_units_per_cell) * child_point
```

This describes the stored transform, **not** guaranteed physical accuracy. The
world hex grid, parent grid, source terrain-layer grid, and source native distance
units may all differ. The placement's `columns × rows` bounds define the
registered child crop, **not** a guarantee that all child art lies within it.
A child can have artwork outside the crop or share one placement with multiple
entrances. Transforming raster requires composing the source `RasterLayer`
transform and resampling, including negative chunk coordinates and translucent
pixels. Terrain needs a preserved per-layer grid or an explicitly approved
conversion; simply assigning square-grid cells to parent hex-cell keys loses data.

## Implemented read-only preflight

`AtlasLegacyMigrationAudit.inspect(campaign)` returns a detached report with
`approval_required: true`; it never edits a map, link, placement or pixel.
It inventories:

- Every document ID/kind/name, floor and layer ID/order, type, `detail_level`,
  visibility/lock/opacity and each map's native grid metadata.
- Stroke/object counts (including text, image props and editable wall paths),
  token counts and per-floor fog state; raster chunk keys (including signed
  keys), pixels-per-unit and raster transform **metadata**. Historical terrain
  terrain-layer migration is a separate approval concern; new authoring no
  longer creates palette-cell terrain layers (T-050). Pixel bytes are not copied into
  the report. Raw raster pixels remain in the original native save.
- Every source/target link and arrival setting, placement geometry/units/symbolic
  state, candidate spatial transform, shared/orphaned placement and mismatched
  or missing references. It also flags old `BATTLEMAP` kinds **even if unplaced**.
- For **nonsymbolic** placements, conservative per-floor/layer/object warnings
  when semantic strokes or nontransparent raster-pixel rectangles extend outside
  the stored child-coordinate crop. Signed chunks, raster density and affine
  transforms are accounted for. Empty-alpha chunks do not count as painted art.
  Rotated rectangular extents can produce warnings without actual clipped pixels;
  text/props, fog and tokens are deliberately escalated for separate review,
  not treated as automatically portable. Warnings never authorize conversion.

The report contains facts for human review, not a conversion queue or an
assumption that every map with a placement belongs inside its parent. Call it
on a *separately loaded* campaign for a dry-run inventory. It is not an
interactive migration UI and does not save or rewrite any campaign.

`tests/legacy_migration_audit_smoke.gd` covers separate maps with multiple floors,
ink, square-grid metadata, signed raster chunks and alpha; shared, symbolic, orphaned,
conflicting and missing placements; repeatability, no side effects, native-save
roundtrip and exact decoded raster pixel preservation. It only writes to a
private `user://atlas_legacy_audit/fixture.scn` slot, never the editor save.

## Archived opt-in conversion policy (not needed; not authorized)

1. **Default to retaining an independent map.** A `BATTLEMAP` label alone, a
   marker-only link, or a legacy footprint is insufficient evidence that it
   should be deleted. Treat each map and incoming relationship as an explicit
   review item. Cyclic/shared/multiple-parent relationships are blocking
   ambiguities for automatic flattening.
2. **Spatial placements:** Offer an opt-in, **copy-first** authored-detail
   conversion only for a user-selected source map/floor, destination parent/floor,
   `D` level and placement. Show the stored transform and bounds and ask whether
   its scale/rotation/offset are correct. Keep the original separately addressable
   until post-conversion verification and explicit discard approval; never move
   original layers in-place.
3. **Symbolic, unregistered, conflicting or multiply placed maps:** Do **not**
   guess coordinates, pick one parent, or infer geography from marker radii.
   Leave them independent with existing navigable links until the owner supplies
   an explicit mapping or confirms they should remain independent.
4. **Lossless art policy:** Preserve IDs, names, ordering, visibility, lock state,
   opacity, native measurement and all D-levels. Copy ink with an appropriate
   transformed coordinate/width model; preserve independent terrain grids and
   transformed raster art. If a representation cannot preserve opaque and
   partially transparent pixels, cell geometry and editability to an agreed
   tolerance, **block that conversion** rather than degrade the artwork.
   Layer and floor ID collisions require explicit remapping; never overwrite.
5. **Links and backlinks:** Maintain all genuinely independent-map links.
   For a converted source, propose a replacement spatial *location/focus* on
   the shared board only after the owner identifies which old navigation
   entries are obsolete. Do not rewrite links on a guessed one-to-one basis;
   unresolved or dangling references must remain recoverable.
6. **Transactional rollout:** Read from a copy, retain the original `.scn` and
   its valid backup in an immutable, versioned recovery slot, and create a
   **new** native save generation. Verify exact original pixels and metadata,
   converted art geometry, references, history, source/pack interoperability,
   rerun deterministically (no duplicate layers), and only then offer an
   explicit, reversible commit of the migrated save. Conversion failures leave
   the original untouched. Historic undo operations must not be rewritten into
   invalid commands; a migration may require a clear new history boundary.

### Approval questions

The following **historical** policy choices would have required a separate decision **before implementing
any saved-data rewrite or removing compatibility readers**:

- Is **copy-first, opt-in conversion of individually selected spatial maps** the
  intended default, leaving ambiguous/symbolic or unrelated maps independent?
- Should a **separate, explicit choice** be required to discard a successfully
  converted legacy map and replace its old links, even after tests pass?
- May an incompatible terrain/raster representation **block conversion** until
  exact/acceptable preservation is demonstrated, rather than using lossy
  automatic flattening?

Until approved, T-015 stays **unchecked** in [[Index]]. Removing model classes,
creating automatic migration or changing stored saves would be premature. Later
UI-hierarchy and navigation refactoring has separate scope in [[T-018]],
[[T-017]] and [[T-009]].
