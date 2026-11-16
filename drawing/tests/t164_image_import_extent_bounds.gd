extends SceneTree
## T-164: image import must validate the *entire* signed rectangle.

const LIMIT: int = 1152921504606846976
const STRIDE: int = 64
const INK: int = 0xff224466
var checks: int = 0
var failures: int = 0


class CountingDocument:
	extends DrawingDocument
	var resolves: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolves += 1
		return super._resolve_chunk(layer_id, key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T164_IMAGE_EXTENT_FAILED: " + label)


func source_image() -> Image:
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	for y: int in range(2):
		for x: int in range(2):
			image.set_pixel(x, y, Color(0.2, 0.4, 0.8, 1.0))
	return image


func rejected(doc: CountingDocument, layer_id: String, image: Image,
		left: int, top: int, label: String) -> void:
	var revision_before: int = doc.revision
	var epoch_before: int = doc.display_source_epoch
	var dirty_before: Dictionary = doc._dirty_tiles.duplicate()
	var history_before: int = doc.history_length()
	var resolve_before: int = doc.resolves
	var result: DrawingResult = DrawingRasterImport.import_image(
		doc, layer_id, image, left, top, revision_before)
	check(not result.ok and result.code == "COORD_RANGE", label + " rejected as COORD_RANGE")
	check(doc.revision == revision_before and doc.display_source_epoch == epoch_before
		and doc._dirty_tiles == dirty_before and doc.history_length() == history_before
		and doc.resolves == resolve_before,
		label + " never reads sources or mutates document/history")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "required native extension present")
	var image: Image = source_image()
	var old: CountingDocument = CountingDocument.new("t164-non-native", STRIDE)
	var old_layer: String = str(old.create_layer(DrawingLayerNode.RASTER, "Old").value)
	# Starting exactly at +LIMIT is valid for one pixel, but not a 2px image.
	rejected(old, old_layer, image, LIMIT, 0, "rightmost pixel above positive x limit")
	rejected(old, old_layer, image, 0, LIMIT, "bottom pixel above positive y limit")
	rejected(old, old_layer, image, LIMIT, LIMIT, "both positive endpoints")
	rejected(old, old_layer, image, -LIMIT - 1, 0, "negative x starting anchor")
	rejected(old, old_layer, image, 0, -LIMIT - 1, "negative y starting anchor")
	# Both ends are inclusive and preserve legacy 64-bit source addressing.
	var positive: DrawingResult = DrawingRasterImport.import_image(
		old, old_layer, image, LIMIT - 1, LIMIT - 1, old.revision)
	check(positive.ok, "inclusive positive 2x2 upper edge still imports")
	var negative: DrawingResult = DrawingRasterImport.import_image(
		old, old_layer, image, -LIMIT, -LIMIT, old.revision)
	check(negative.ok, "inclusive negative 2x2 lower edge still imports")
	if positive.ok and negative.ok:
		check(int(old.read_pixel(old_layer, LIMIT, LIMIT).value) != 0 and
			int(old.read_pixel(old_layer, -LIMIT, -LIMIT).value) != 0,
			"far signed endpoints store imported pixels without truncation")
		check(old.undo().ok and old.redo().ok, "historical non-native Undo/Redo remains available")

	# A Hokusai-owned document must also reject before any native transaction.
	var doc: CountingDocument = CountingDocument.new("t164-native", STRIDE)
	var layer_id: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = doc.begin_edit(layer_id, doc.revision)
	check(opened.ok, "native edit session created")
	if opened.ok:
		var edit: DrawingEditSession = opened.value as DrawingEditSession
		var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
		var configured: DrawingResult = edit.begin_native_stroke(brush,
			FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
			8.0, INK, Rect2i(-16, -16, 64, 64), true)
		check(configured.ok, "real Hokusai stroke configured")
		if configured.ok:
			check(edit.paint_path_native(PackedVector2Array([
				Vector2(2, 4), Vector2(9, 4)]), INK, false, null).ok,
				"native pigment staged")
			var committed: DrawingResult = edit.commit()
			check(committed.ok and committed.delta != null and
				committed.delta.native_history_token > 0, "Rust native history committed")
			if committed.ok:
				var store: Object = doc._native_raster_store
				var token: int = committed.delta.native_history_token
				var bytes: PackedByteArray = store.call("read_tile", layer_id, 0, 0, false).get("bytes")
				rejected(doc, layer_id, image, LIMIT, 0, "native positive x overhang")
				rejected(doc, layer_id, image, 0, LIMIT, "native positive y overhang")
				check(int(store.call("stats").get("revision", -1)) == doc.revision and
					store.call("has_history_token", token, doc.revision, true),
					"rejected overhang preserves native revision and token")
				check(store.call("read_tile", layer_id, 0, 0, false).get("bytes") == bytes,
					"rejected overhang preserves exact canonical Rust bytes")
				check(doc.undo().ok and doc.redo().ok and
					store.call("read_tile", layer_id, 0, 0, false).get("bytes") == bytes,
					"native Undo/Redo remains exact")
		else:
			edit.cancel()

	print("T164_IMAGE_EXTENT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0 and checks >= 20:
		print("T164_IMAGE_EXTENT_PASSED (%d checks; 0 failed)" % checks)
	quit(1 if failures else 0)
