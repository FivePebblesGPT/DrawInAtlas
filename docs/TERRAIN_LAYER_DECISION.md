# Terrain artwork retirement and future procedural map tools

**Owner decision (2026-10-31):** DrawInAtlas is a digital substitute for a traditionally drawn map. **Retire the palette-cell `AtlasTerrainLayer` (`TILES` in the former wire format) from the target artwork architecture.** The grid and hex-region properties are separate concerns (some region-property workflows remain future work). Raster is primary for painting the visual map, while vector is retained for editable semantic objects. Implementation completed under [[T-050]]; raster-first *authoring defaults* remain pending under [[T-049]].

## Distinct responsibilities

| Concern | Architectural owner / direction |
| --- | --- |
| Cartographic appearance (biomes, mountains, water, roads, textures) | Chunked raster artwork, with editable semantic vector objects where needed |
| Coordinates and grid geometry | Independent board grid (hex, square or none), not a palette of painted tile IDs |
| Hex/region properties | A separate semantic data model; artwork neither requires nor silently changes these properties |
| Navigation, biome classifications and other type masks | Future explicit semantic masks / brush-authored classifications; not equivalent to reading RGBA colors and not yet implemented |
| 5-foot map tilemaps / procedural content generation | Possible future **local-scale** tool or intermediate representation; can produce raster art, editable objects and/or semantic data, without requiring a general terrain-artwork layer |
| Retired `AtlasTerrainLayer` | Obsolete palette-ID cell painting model, removed in [[T-050]] |

A type-aware texture brush could later paint pixels and a separate classification mask in one user action. Whether its mask is brush-authored, object-based, or derived from a generator needs its own design. **Do not infer movement or biome type solely from the color of pixels**; an illustration is not authoritative gameplay metadata. No auto-tiling, PCG, 5-foot grid behavior or semantic-mask schema is approved by this decision.

## Historical inventory (before T-050; no longer executable)

`scripts/artwork/terrain_layer.gd` defined `AtlasTerrainLayer`, whose sparse cell values were integer palette IDs. It was integrated with floor defaults, type-specific brush/fill/eraser and edit commands, selection, clipboard, layer UI, tests and persistence. The T-050 implementation removed these palette-cell paths rather than retaining a legacy compatibility shim. [[T-031]] recorded its previous naming/type consistency and still describes the pre-removal runtime; its earlier verification remains historical evidence, not a reason to retain terrain artwork.

## Removal boundary

- **Remove** terrain artwork classes, `TILES` user-facing layer creation/editing and terrain-specific rendering, clipboard, tool dispatch, commands, codecs and save fields, with tests updated for the new schema. Inventory every reference before deletion; avoid leaving unreachable compatibility APIs posing as supported features.
- **Keep** the continuous grid/board, coordinates, cell-based selection masks and snapping, authored detail levels, existing document metadata, raster painting and vector editing. Region-property storage remains a separate design concern, not a required terrain-layer dependency. Cell-scoped masks must continue clipping pixel/geometry edits correctly even without a terrain layer.
- **No migration framework:** the owner reports no real user data requiring migration. Existing development fixtures may be regenerated/replaced, with intentional native-save format changes documented and tests proving current raster/vector content survives round-trip. Do not claim historical terrain-bearing saves remain compatible if the reader rejects them.
- **Keep future PCG separate:** 5-foot tile generation is a future tool concern, not a reason to perpetuate an otherwise redundant whole-map terrain layer. Any future material/type-mask API needs an independent design and acceptance ticket.

## Work sequencing

1. [[T-050]] completed the removal and revalidated editing, history, clipping, exports and native saves. Native save version 2 and dictionary schema 7 intentionally reject older palette-cell prototype saves.
2. [[T-049]] then implements raster-first defaults and semantic-vector tool affordances without a terrain fallback. This can be coordinated in the same design but remains a separate ticket with its own testing and acceptance.
3. [[T-018]] ensures layer UI emphasizes raster/vector rather than an obsolete terrain layer. Later, if needed, spec a dedicated type-mask/5-foot PCG workflow; do not silently attach it to T-050.

This supersedes older architectural prose treating `TILES`/`AtlasTerrainLayer` as a third artwork representation. Archived tickets retain historical test evidence; the current runtime supports raster and ink only.
