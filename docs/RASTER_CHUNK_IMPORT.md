# Raster image import and chunk ownership — T-030

## Source and output

`AtlasArtworkEditor.import_raster(image)` calls `AtlasRasterLayer.from_image_chunks(image)`. The legacy `from_image(image, scale)` method delegates to the same implementation so existing callers remain compatible. The input is a nonempty Godot `Image`; a `null` or empty image, nonfinite `scale`, or nonpositive `scale` is rejected. The returned `AtlasRasterLayer` starts at identity transform with default name/id and stores `pixels_per_unit = scale`; the editor separately assigns its id, authored detail and board-space placement. **The importer itself does not move pixels to the board or search for nontransparent content.**

## What the loop does

The two nested loops visit **rectangular regions** with top-left coordinates `(left, top)` spaced by `AtlasRasterChunk.SIZE` (256). Each iteration calls `Image.get_region(Rect2i(left, top, width, height))`, then constructs an `AtlasRasterChunk` at the corresponding `(left / 256, top / 256)` chunk coordinate and stores it under the matching `"x,y"` key. For an image `W × H`, the result contains `ceil(W/256) × ceil(H/256)` chunks. Partial right/bottom edges use `min(256, remaining pixels)` and are not padded. Image import starts at pixel `(0,0)`, so initial chunk coordinates are nonnegative; the separate `pixel_to_chunk()` helper supports signed board-space chunk addressing with floor division.

`get_region` copies the source rectangle into a temporary `Image`. The `AtlasRasterChunk` constructor then passes it to `canonical_image`, which duplicates the region, decompresses if necessary, removes mipmaps, and converts to `FORMAT_RGBA8`. The chunk retains the **second, independently owned** image and records its actual width/height. For already-RGBA8 input, the chunk's raw base-level RGBA bytes are retained, including RGB values beneath zero alpha; no per-pixel alpha search or handwritten scanning loop occurs. Non-RGBA8 inputs are converted by Godot, so matching the original source **byte-for-byte** is only meaningful for RGBA8 input; source format and data are not mutated. Failed chunk creation aborts the import instead of returning a partially populated layer.

The algorithm visits `O(ceil(W/256) × ceil(H/256))` rectangles and copies/converts an aggregate `O(W×H)` pixels. An individual temporary region and chunk duplicate are at most 256×256 pixels. Chunk memory and native-save encoding are distinct concerns: `AtlasNativeScene` later serializes validated chunks as lossless WebP inside the `.scn` resource graph and verifies exact decoded pixels. The existing separate history/clone paths still make independent decoded image copies. No concrete performance regression was found in this review, so T-030 introduces no speculative caching or wholesale re-encoding.

## Verification

`tests/raster_import_chunks_smoke.gd` checks a 513×257 patterned RGBA8 input (six chunks), byte-exact regions including transparent RGB, one-pixel bottom/right edges, scale/transform metadata, original/derived image independence, RGB8 mipmap normalization, invalid inputs, signed address arithmetic and a native Resource save round trip. Existing layer, dictionary-validation, storage, clipboard, preview and Web/source-pack portability tests continue protecting those boundaries.
