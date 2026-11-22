extends SceneTree
## Native Brush publication validates the entire transfer descriptor before
## asking any lazy source provider for pixels.

const HIDDEN: int = 0x00335577
var checks: int = 0
var failures: int = 0

class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(_layer_id: String, _key: String) -> DrawingResult:
		reads += 1
		return DrawingResult.failure("LAZY_CALLED", "Invalid publication touched a source")


class ReentrantDocument:
	extends DrawingDocument
	var images_ref: Dictionary[String, PackedByteArray] = {}
	var bounds_ref: Dictionary[String, Rect2i] = {}
	var sources_ref: Dictionary[String, Variant] = {}
	var mode: String = ""
	var reads: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		reads += 1
		if reads == 1:
			match mode:
				"image":
					var changed: PackedByteArray = images_ref[key].duplicate()
					changed.encode_u32(0, 0xff123456)
					images_ref[key] = changed
				"bounds":
					bounds_ref[key] = Rect2i(0, 0, 2, 1)
				"source":
					sources_ref[key] = DrawingRasterTile.new(tile_stride)
				"extra":
					images_ref["1,0"] = images_ref[key].duplicate()
					bounds_ref["1,0"] = Rect2i(0, 0, 1, 1)
					sources_ref["1,0"] = null
		return super._resolve_chunk(layer_id, key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T234_NATIVE_PUBLICATION_FAILED: " + label)


func counted(stride: int) -> Dictionary:
	var doc: CountingDocument = CountingDocument.new("t234-" + str(stride), stride)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	return {"doc": doc, "layer": layer, "base": doc.revision}


func reject_without_reads(context: Dictionary, images: Dictionary[String, PackedByteArray],
		bounds: Dictionary[String, Rect2i], code: String, label: String,
		omit_later_source: bool = false) -> void:
	var doc: CountingDocument = context.doc
	var revision: int = context.base
	var sources: Dictionary[String, Variant] = {}
	for key: String in images:
		if omit_later_source and key == "1,0":
			continue
		sources[key] = null
	var rejected: DrawingResult = doc._publish_native_tile_edit(
		context.layer, revision, revision + 1, images, sources, bounds, true, true)
	check(not rejected.ok and rejected.code == code, label + " rejected before lazy read")
	check(doc.reads == 0 and doc.revision == revision and doc._native_raster_store == null,
		label + " leaves sources/revision/native attachment intact")
	check(doc._nodes[context.layer].tiles.is_empty(), label + " publishes no tiles")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "compiled native ABI is available")
	var wide: Dictionary = counted(2048)
	var big_images: Dictionary[String, PackedByteArray] = {}
	var big_bounds: Dictionary[String, Rect2i] = {}
	for index: int in range(6):
		var key: String = "%d,0" % index
		big_images[key] = PackedByteArray()
		big_bounds[key] = Rect2i(0, 0, 1, 1)
	reject_without_reads(wide, big_images, big_bounds, "NATIVE_TILES",
		"six 2048px tiles exceed the conservative 256 MiB envelope")

	var crowded: Dictionary = counted(64)
	var many_images: Dictionary[String, PackedByteArray] = {}
	var many_bounds: Dictionary[String, Rect2i] = {}
	for index: int in range(129):
		var key: String = "%d,0" % index
		many_images[key] = PackedByteArray()
		many_bounds[key] = Rect2i(0, 0, 1, 1)
	reject_without_reads(crowded, many_images, many_bounds, "NATIVE_TILES",
		"more than 128 tiles")

	var valid_bytes: PackedByteArray = PackedByteArray()
	valid_bytes.resize(64 * 64 * 4)
	valid_bytes.encode_u32(0, HIDDEN)
	var first_valid: Dictionary[String, PackedByteArray] = {"0,0": valid_bytes}
	var valid_bounds: Dictionary[String, Rect2i] = {"0,0": Rect2i(0, 0, 1, 1)}
	var malformed: Dictionary[String, PackedByteArray] = first_valid.duplicate()
	malformed["1,0"] = PackedByteArray([1, 2, 3])
	var two_bounds: Dictionary[String, Rect2i] = valid_bounds.duplicate()
	two_bounds["1,0"] = Rect2i(0, 0, 1, 1)
	reject_without_reads(counted(64), malformed, two_bounds, "RGBA",
		"malformed later tile buffer")

	var bad_key: Dictionary[String, PackedByteArray] = first_valid.duplicate()
	bad_key["01,0"] = valid_bytes
	var bad_key_bounds: Dictionary[String, Rect2i] = valid_bounds.duplicate()
	bad_key_bounds["01,0"] = Rect2i(0, 0, 1, 1)
	reject_without_reads(counted(64), bad_key, bad_key_bounds, "COORD",
		"noncanonical later tile ID")

	var bad_dirty: Dictionary[String, PackedByteArray] = first_valid.duplicate()
	bad_dirty["1,0"] = valid_bytes
	var bad_dirty_bounds: Dictionary[String, Rect2i] = valid_bounds.duplicate()
	bad_dirty_bounds["1,0"] = Rect2i(63, 0, 2, 1)
	reject_without_reads(counted(64), bad_dirty, bad_dirty_bounds, "COORD",
		"out-of-tile later dirty bounds")

	var missing_source: Dictionary[String, PackedByteArray] = first_valid.duplicate()
	missing_source["1,0"] = valid_bytes
	reject_without_reads(counted(64), missing_source, two_bounds, "STALE_PIXEL",
		"missing later source", true)

	for mode: String in ["image", "bounds", "source", "extra"]:
		var reentrant: ReentrantDocument = ReentrantDocument.new("t234-" + mode, 64)
		var reentrant_layer: String = str(reentrant.create_layer(
			DrawingLayerNode.RASTER, "Ink").value)
		var old_revision: int = reentrant.revision
		var input_images: Dictionary[String, PackedByteArray] = first_valid.duplicate()
		var input_bounds: Dictionary[String, Rect2i] = valid_bounds.duplicate()
		var input_sources: Dictionary[String, Variant] = {"0,0": null}
		reentrant.images_ref = input_images
		reentrant.bounds_ref = input_bounds
		reentrant.sources_ref = input_sources
		reentrant.mode = mode
		var result: DrawingResult = reentrant._publish_native_tile_edit(
			reentrant_layer, old_revision, old_revision + 1,
			input_images, input_sources, input_bounds, true, true)
		check(reentrant.reads == 1 and not result.ok and result.code == "STALE_PIXEL",
			"reentrant " + mode + " mutation rejects the frozen publication")
		check(reentrant.revision == old_revision and
			reentrant._nodes[reentrant_layer].tiles.is_empty(),
			"reentrant " + mode + " mutation leaves pixels and revision intact")

	var good: DrawingDocument = DrawingDocument.new("t234-valid", 64)
	var layer: String = str(good.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var base: int = good.revision
	var sources: Dictionary[String, Variant] = {"0,0": null}
	var planned: DrawingResult = good._publish_native_tile_edit(layer, base, base + 1,
		first_valid, sources, valid_bounds, true, true)
	check(planned.ok and planned.delta != null and planned.delta.tile_stride == 64,
		"bounded valid descriptor prepares native tile delta")
	check(planned.ok and planned.regions.size() == 1 and
		planned.regions[0].x == 0 and planned.regions[0].width == 1,
		"dirty region remains exact for valid publication")
	check(good.revision == base and good._nodes[layer].tiles.is_empty(),
		"dry run does not publish pixels or revision")
	if planned.ok:
		var installed: DrawingResult = good._install_prepared_native_tile_edit(
			layer, base, base + 1, planned)
		check(installed.ok and good.revision == base + 1,
			"prepared valid source installs exactly one document revision")
		check(int(good.read_pixel(layer, 0, 0).value) == HIDDEN,
			"alpha-zero hidden RGB preserved through publication")

	if failures == 0:
		print("T234_NATIVE_PUBLICATION_PASSED checks=%d failures=0" % checks)
	else:
		print("T234_NATIVE_PUBLICATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
