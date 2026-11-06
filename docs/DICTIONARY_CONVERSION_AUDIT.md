# Dictionary conversion audit — T-029

## Decision and boundaries

**2026-10-30: Retain the current single-file native `.scn` Resource format and schema v6.** No legacy JSON campaign writer or loader exists in the production save path. Consequently **no dictionary conversion method can be removed safely as an obsolete JSON save routine** on the evidence reviewed here. The `to_dict` / `from_dict` names predate the native format but their callers still have active, distinct responsibilities. Removing them without replacements would silently weaken integrity or history guarantees; this ticket does not authorize a new persistence schema or a lossy migration.

The only production cleanup in this ticket removes **unnecessary decoded-Image copies during collection *validation***. `AtlasLayerCodec._validated_metadata()` uses the existing `from_dict(layer.to_dict())` validator, checks live raster chunk validity and coordinate-key consistency, then returns metadata without images. `valid_collection()` uses it instead of `clone()`. `clone()` uses the same validator and **still duplicates every decoded `Image`** for independent edits. The dictionary parser remains the **one authority** for layer metadata; the live-image and chunk-key checks are additional invariants that dictionaries alone cannot represent. This also rejects an inconsistent raster chunk key before attempting a clone.

## Inventory: production adapters and callers

| Adapter | Current purpose | Representative callers | Disposition |
| --- | --- | --- | --- |
| `AtlasCampaign.to_dict/from_dict` | Validate the entire graph, create a detached native snapshot, compute semantic digest, inspect legacy schema fixtures | `AtlasNativeScene`, legacy-load tests | **Keep**: deleting either removes native validation and integrity checks |
| `AtlasMapDocument.to_dict/from_dict` | Snapshot and validate map identity, floors, terrain and grids; history of map creation and linked maps | `AtlasCreateMap`, `AtlasLinkEdit`, `AtlasNativeScene`, `AtlasCampaign` | **Keep** |
| `AtlasFloor.to_dict/from_dict` | Typed/legacy layer reconstruction, grid hydration, native graph validation | `AtlasMapDocument`, `AtlasCampaign` | **Keep** |
| `AtlasGrid.to_dict/from_dict` | Validate geometry, units and visibility; create clipboard geometry; serialize legacy-compatible grid metadata | `AtlasMapDocument`, `AtlasLayerCodec`, `AtlasClipboard`, `AtlasTileLayer` | **Keep** |
| `AtlasStroke.to_dict/from_dict` | Validate stroke geometry, closed/filled paths, editable paths and text; exchange selections through versioned clipboard | `AtlasInkLayer`, `AtlasLayerCodec`, `AtlasClipboard`, editor comparisons | **Keep**; typed `AtlasStroke.copy()` is used for ordinary stroke copying |
| `AtlasLayer` and `AtlasInkLayer/AtlasTileLayer/AtlasRasterLayer.to_dict` with `AtlasLayerCodec.from_dict` | One strict validator of all layer metadata and content, independent copies, stale-state protection, ordering, detail/visibility and native-save checks | `AtlasLayerCodec.clone/valid_collection`, `AtlasLayerEdit`, `AtlasTileEdit`, `AtlasSelection`, `AtlasSelectionGeometry`, `AtlasClipboard`, `AtlasNativeScene` | **Keep**; avoid copying Image bytes merely to validate |
| `AtlasRasterChunk.to_dict/from_dict` | Validate chunk coordinate, size and **content hash reference**, not decoded Image bytes | `AtlasRasterLayer`, `AtlasLayerCodec`; native scene separately checks decoded WebP against hash | **Keep**; raw pixels are preserved separately and must not be replaced by dictionary metadata |
| `AtlasMapLink.to_dict/from_dict` | Validate directed links and take immutable undo/redo and dialog snapshots | `AtlasLinkEdit`, `AtlasLinkDialog`, `AtlasLinkedMaps`, `AtlasCampaign` | **Keep** while links remain |
| `AtlasPlacement.to_dict/from_dict` | Validate existing spatial legacy placements and protect their undo/navigation history | `AtlasLinkEdit`, `AtlasLinkDialog`, `AtlasCampaign`, `AtlasLegacyMigrationAudit` | **Keep** until T-015 migration is approved and completed; not safe to remove now |

The `to_dict()` comparisons in the UI and `AtlasSelection` are deliberate optimistic-concurrency / stale-edit guards. They are not writing a campaign JSON file. `AtlasLayerCodec.same_layers()` compares snapshots for history/floor actions; `clone_all()` still builds detached layer instances. `AtlasPreviewCache` serializes a **cache key** with `JSON.stringify` to avoid string delimiter collisions. `AtlasClipboard` deliberately uses versioned, strictly validated JSON for interchange. The browser file-picker script uses `JSON.stringify` for safe JavaScript string quoting. `AtlasLegacyMigrationAudit` emits dictionaries only for a read-only report. None are obsolete native-save writers.

## Native save authority and immutable boundaries

- `AtlasCampaignStore` is the only end-user campaign store. It stages native PackedScenes, checks a candidate before activation, retains the last verified generation, and loads the backup if needed. Old JSON saves are **not** automatically converted.
- `AtlasNativeScene._snapshot()` calls the full graph validator, then **duplicates raw RGBA8 Images** and encodes lossless WebP into native chunk resources. The snapshot must not share mutable stroke, text, grid, link, or Image objects with the source.
- `AtlasNativeScene._validate_and_hydrate()` uses the strict graph validator again and checks losslessly decoded pixels, dimensions, and SHA-256 IDs. `_digest()` canonicalizes sorted semantic dictionaries via JSON **in memory only**; it is a deterministic checksum input, not a JSON save format.
- Undo/history and selection/clipboard carry snapshots or typed deep copies. Replacing these conversions with Godot's generic `Resource.duplicate(true)` is not equivalent without an explicit study of nested exported arrays, transient pixel caches and resource identity.
- The current dictionary schema is an internal validation/compatibility contract, **not a second persisted source of truth**. Native `.scn` remains authoritative; no schema version bump, renderer rewrite, or legacy data deletion is warranted for T-029.

## Regressions and follow-ups

`tests/dictionary_conversion_audit_smoke.gd` covers dictionary validation without side effects; duplicate IDs; malformed raster metadata and stale chunk keys; exact partial-chunk RGBA8 including hidden RGB; independent raster and editable-text clones; native PackedScene graph round-trip; and independent native decoded pixels. CI runs it alongside existing `layers_smoke`, `storage_smoke`, clipboard/selection/history tests, native framebuffer tests and Web/save portability checks.

**Follow-ups (not authorized in T-029):** T-015 owns legacy placement migration and any resulting schema decision. T-030 owns raster import/chunk design. T-031 owns tile-layer type/naming authority. T-032 owns field encoding documentation. Performance work on history/digest allocation should be separately measured before introducing typed serializers or alternate integrity formats. No existing adapter was removed because the audit found no conversion with an exclusively obsolete use.
