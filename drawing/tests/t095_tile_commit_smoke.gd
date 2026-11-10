extends SceneTree
## T-095: independent native tile-commit transaction oracle. The expected
## canonical history comes from the original _stage() + _publish_edit() path.

const ORIGIN_X: int = 2147483673
const ORIGIN_Y: int = -2147483711
const COLOR: int = 0x804060e0
const CLIP: Rect2i = Rect2i(-90, -90, 180, 180)

class DeltaSource:
	extends RefCounted
	var deltas: PackedInt32Array
	func preset_segments(_path: PackedVector2Array, _pressure: float) -> PackedInt32Array:
		return deltas

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_TILE_COMMIT_FAILED: " + label)

func make_target(label: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	var source: PackedByteArray = PackedByteArray()
	for i: int in range(16 * 16):
		source.append_array(PackedByteArray([i % 251, 93, 211, 0 if i % 11 == 0 else 120]))
	check(seed.apply_region(Rect2i(-8, -8, 16, 16), source).ok and seed.commit().ok,
		label + " seeded with partially transparent and hidden RGB pixels")
	return {"doc": doc, "layer": layer}

func begin(target: Dictionary) -> DrawingEditSession:
	var doc: DrawingDocument = target["doc"]
	return doc.begin_edit(target["layer"], doc.revision, Transform2D.IDENTITY,
		ORIGIN_X, ORIGIN_Y).value as DrawingEditSession

func snapshot(target: Dictionary) -> PackedByteArray:
	var doc: DrawingDocument = target["doc"]
	var result: DrawingResult = DrawingRenderer.render(doc, Rect2i(-90, -90, 180, 180),
		ORIGIN_X, ORIGIN_Y, 180 * 180)
	check(result.ok, "render %s" % String(target["layer"]))
	return result.value.get_data() if result.ok else PackedByteArray()

func run() -> void:
	var target: Dictionary = make_target("tile-direct")
	var reference: Dictionary = make_target("pixel-oracle")
	var native_edit: DrawingEditSession = begin(target)
	var old_edit: DrawingEditSession = begin(reference)
	var source: DeltaSource = DeltaSource.new()
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-85, -85, 170, 170), true)
	check(mask.combine_rectangle(Rect2i(-4, -4, 9, 9), "Subtract"), "selection hole")
	var path: PackedVector2Array = PackedVector2Array([Vector2(-40.5, -40.5)])
	for batch: int in range(3):
		var pixels: PackedInt32Array = PackedInt32Array()
		for y: int in range(-72, 73, 3):
			for x: int in range(-72, 73, 3):
				pixels.append_array(PackedInt32Array([x, y,
					0x10203040 if (x + y + batch) % 13 == 0 else
					(0x30a080e0 if batch == 0 else 0x7080c040)]))
		source.deltas = pixels
		check(native_edit.paint_path_hokusai(path, COLOR, mask, source, CLIP).ok,
			"direct batch %d accepted" % batch)
		var reference_ok: bool = true
		for index: int in range(0, pixels.size(), 3):
			var point: Vector2i = Vector2i(pixels[index], pixels[index + 1])
			if not CLIP.has_point(point) or not mask.allows(point):
				continue
			var pigment: int = int(pixels[index + 2]) & 0xffffffff
			var alpha: int = (((pigment >> 24) & 255) * ((COLOR >> 24) & 255) + 127) / 255
			var rgba: int = (pigment & 0xffffff) | (alpha << 24)
			if not old_edit._stage(point.x, point.y, rgba, null, false, true).ok:
				reference_ok = false
				break
		check(reference_ok, "reference batch %d accepted" % batch)
		check(native_edit.change_count() == old_edit.change_count(),
			"native change count matches original %d" % batch)
	check(native_edit._hokusai_deferred and native_edit._before.is_empty() and
		native_edit._after.is_empty(), "native commit reaches tile-only publication")
	var preview: DrawingResult = DrawingRenderer.render(target["doc"],
		Rect2i(-90, -90, 180, 180), ORIGIN_X, ORIGIN_Y, 180 * 180, native_edit)
	check(preview.ok, "native detached preview is valid")
	var direct_result: DrawingResult = native_edit.commit()
	var oracle_result: DrawingResult = old_edit.commit()
	check(direct_result.ok and oracle_result.ok, "both publication paths succeed")
	check(native_edit.change_count() == 0 and old_edit.change_count() == 0 and
		 not native_edit._hokusai_deferred, "successful commit clears closed-session staging state")
	if direct_result.ok and oracle_result.ok:
		check(direct_result.delta.before == oracle_result.delta.before,
			"canonical before-history keys and pixels match exactly")
		check(direct_result.delta.after == oracle_result.delta.after,
			"canonical after-history keys and pixels match exactly")
		check(direct_result.delta.after.size() > 1000,
			"large paint commit exercises thousands of changed pixels")
		check(direct_result.regions.size() == oracle_result.regions.size(),
			"direct publication emits the same number of dirty regions")
		var region_map: Dictionary[String, Rect2i] = {}
		for region: DrawingDirtyRegion in oracle_result.regions:
			region_map["%d,%d,%d,%d" % [region.x, region.y, region.width, region.height]] = Rect2i(
				region.x, region.y, region.width, region.height)
		for region: DrawingDirtyRegion in direct_result.regions:
			check(region_map.has("%d,%d,%d,%d" % [region.x, region.y, region.width, region.height]),
				"dirty region exists in original publication")
	var final_native: PackedByteArray = snapshot(target)
	var final_reference: PackedByteArray = snapshot(reference)
	check(final_native == final_reference and preview.value.get_data() == final_native,
		"preview and committed bytes match old path including transparent RGB")
	check(target["doc"].undo().ok and reference["doc"].undo().ok and
		snapshot(target) == snapshot(reference), "one history undo exact")
	check(target["doc"].redo().ok and reference["doc"].redo().ok and
		snapshot(target) == final_reference, "one history redo exact")

	# Test an invalid *later* patch after a valid earlier tile. Neither the
	# earlier tile nor history may be published by partial preparation.
	var invalid_doc: Dictionary = make_target("invalid-later-tile")
	var invalid: DrawingEditSession = begin(invalid_doc)
	source.deltas = PackedInt32Array([-60, -60, 0x60ffffff, 62, 62, 0x60ffffff])
	check(invalid.paint_path_hokusai(path, COLOR, null, source).ok,
		"two-tile native batch is valid")
	var before_invalid: PackedByteArray = snapshot(invalid_doc)
	var revision_invalid: int = invalid_doc["doc"].revision
	var key_last: String = DrawingDocument.TILES.tile_key64(
		ORIGIN_X + 62, ORIGIN_Y + 62, invalid_doc["doc"].tile_stride)
	var bad_patch: Dictionary = invalid._preview_tiles[key_last]
	bad_patch[-1] = 0x80ff00ff
	invalid._preview_tiles[key_last] = bad_patch
	var invalid_result: DrawingResult = invalid.commit()
	check(not invalid_result.ok and invalid_result.code == "COORD",
		"late bad tile offset fails closed")
	check(invalid.change_count() == 0 and not invalid._hokusai_deferred,
		"failed commit clears closed-session staging state")
	check(invalid_doc["doc"].revision == revision_invalid and
		snapshot(invalid_doc) == before_invalid,
		"late failure publishes zero tiles and zero history")

	# A revision change while paint is draining must still reject the old
	# transaction after preparing its detached preview.
	var stale: DrawingEditSession = begin(invalid_doc)
	source.deltas = PackedInt32Array([38, 38, 0x60aabbcc])
	check(stale.paint_path_hokusai(path, COLOR, null, source).ok,
		"stale-test native delta initially accepted")
	var concurrent: DrawingEditSession = begin(invalid_doc)
	check(concurrent.fill_rect(Rect2i(-19, -19, 1, 1), 0x80ff1122).ok and
		concurrent.commit().ok, "concurrent source commit succeeds")
	var revision_stale: int = invalid_doc["doc"].revision
	var unchanged_stale: PackedByteArray = snapshot(invalid_doc)
	var stale_result: DrawingResult = stale.commit()
	check(not stale_result.ok and stale_result.code == "STALE_REVISION",
		"stale native edit cannot commit after revision change")
	check(invalid_doc["doc"].revision == revision_stale and
		snapshot(invalid_doc) == unchanged_stale,
		"stale edit cannot alter committed pixels or history")

	# Internal tile replacement without a revision increment is detectable by
	# identity; never trust a detached session cache as a publication source.
	var replaced: DrawingEditSession = begin(invalid_doc)
	source.deltas = PackedInt32Array([41, 41, 0x60ffffff])
	check(replaced.paint_path_hokusai(path, COLOR, null, source).ok,
		"source-identity native delta accepted")
	var tile_key: String = DrawingDocument.TILES.tile_key64(
		ORIGIN_X + 41, ORIGIN_Y + 41, invalid_doc["doc"].tile_stride)
	var active_doc: DrawingDocument = invalid_doc["doc"]
	var old_tile: DrawingRasterTile = active_doc._nodes[invalid_doc["layer"]].tiles.get(tile_key)
	if old_tile == null:
		active_doc._nodes[invalid_doc["layer"]].tiles[tile_key] = DrawingRasterTile.new(64)
	else:
		active_doc._nodes[invalid_doc["layer"]].tiles[tile_key] = old_tile.detached_copy()
	var replaced_result: DrawingResult = replaced.commit()
	check(not replaced_result.ok and replaced_result.code == "STALE_PIXEL",
		"source tile replacement rejects native transaction")
	check(active_doc.revision == revision_stale,
		"rejected source replacement does not publish a history event")

	print("T095_TILE_COMMIT_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
