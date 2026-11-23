extends SceneTree
## T-238: Brush tile publication must detect in-place changes to earlier sources.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const INTRUDER: int = 0xff997755
const PAINT: int = 0xff2288cc
var checks: int = 0
var failures: int = 0


class ReentrantDocument:
	extends DrawingDocument
	var first_source: DrawingRasterTile
	var mutate_on_second: bool = false
	var reads: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		reads += 1
		if mutate_on_second and key == "1,0":
			# Same tile object and revision: identity checks alone miss this.
			first_source.set_rgba(3, 0, INTRUDER)
		return super._resolve_chunk(layer_id, key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T238_BRUSH_SOURCE_FAILED: " + label)


func create_fixture(mutate: bool) -> Dictionary:
	var doc: ReentrantDocument = ReentrantDocument.new("t238-" + str(mutate), STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var first: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	first.set_rgba(3, 0, HIDDEN)
	doc._nodes[layer].tiles["0,0"] = first
	doc.first_source = first
	doc.mutate_on_second = mutate
	var first_bytes: PackedByteArray = first.to_rgba8()
	first_bytes.encode_u32(0, PAINT)
	var second_bytes: PackedByteArray = PackedByteArray()
	second_bytes.resize(STRIDE * STRIDE * 4)
	second_bytes.encode_u32(0, PAINT)
	var images: Dictionary[String, PackedByteArray] = {"0,0": first_bytes, "1,0": second_bytes}
	var sources: Dictionary[String, Variant] = {"0,0": first, "1,0": null}
	var bounds: Dictionary[String, Rect2i] = {
		"0,0": Rect2i(0, 0, 1, 1), "1,0": Rect2i(0, 0, 1, 1)}
	return {"doc": doc, "layer": layer, "images": images,
		"sources": sources, "bounds": bounds}


func test_mutating_callback() -> void:
	var fixture: Dictionary = create_fixture(true)
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var base: int = doc.revision
	var result: DrawingResult = doc._publish_native_tile_edit(layer, base, base + 1,
		fixture.images, fixture.sources, fixture.bounds, true, true)
	check(doc.reads == 2, "both sources passed through the callback boundary")
	check(not result.ok and result.code == "STALE_PIXEL",
		"in-place edit of a previously resolved tile rejects Brush preflight")
	check(doc.revision == base and doc.history_length() == 0,
		"rejected publication does not advance document or create history")
	check(doc._native_raster_store == null and doc._dirty_tiles.is_empty(),
		"rejected publication does not attach Rust or publish dirty tiles")
	check(int(doc.read_pixel(layer, 0, 0).value) == 0 and
		int(doc.read_pixel(layer, STRIDE, 0).value) == 0,
		"neither Brush replacement was published")
	check(int(doc.read_pixel(layer, 3, 0).value) == INTRUDER,
		"provider's own source mutation remains its responsibility")


func test_unchanged_sources() -> void:
	var fixture: Dictionary = create_fixture(false)
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var base: int = doc.revision
	var result: DrawingResult = doc._publish_native_tile_edit(layer, base, base + 1,
		fixture.images, fixture.sources, fixture.bounds, true, true)
	check(result.ok and doc.reads == 2, "valid two-tile Brush preflight succeeds")
	check(result.ok and result.delta != null and result.delta.tile_stride == STRIDE,
		"preflight includes reversible native tile history")
	check(doc.revision == base and doc.history_length() == 0,
		"dry run does not change document/history")
	if result.ok:
		var installed: DrawingResult = doc._install_prepared_native_tile_edit(
			layer, base, base + 1, result)
		check(installed.ok and doc.revision == base + 1 and doc.history_length() == 1,
			"prepared valid pair installs one revision and one history entry")
		check(int(doc.read_pixel(layer, 0, 0).value) == PAINT and
			int(doc.read_pixel(layer, STRIDE, 0).value) == PAINT,
			"both Brush pixels commit")
		check(int(doc.read_pixel(layer, 3, 0).value) == HIDDEN,
			"untouched alpha-zero hidden RGB stays byte-exact")


func test_attached_rejection() -> void:
	var fixture: Dictionary = create_fixture(false)
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var originals: Dictionary[String, int] = {"0,0": 0}
	var replacements: Dictionary[String, int] = {"0,0": PAINT}
	var initial: DrawingResult = doc._publish_edit(layer, doc.revision,
		originals, replacements)
	check(initial.ok and doc._native_raster_store != null,
		"ordinary direct edit first acquires a persistent native store")
	if not initial.ok:
		return
	var base: int = doc.revision
	var owner: Object = doc._native_raster_store
	var previous_history: int = doc.history_length()
	var source: DrawingRasterTile = doc._nodes[layer].tiles["0,0"]
	doc.first_source = source
	var new_bytes: PackedByteArray = source.to_rgba8()
	new_bytes.encode_u32(0, 0xff123456)
	var images: Dictionary[String, PackedByteArray] = fixture.images
	images["0,0"] = new_bytes
	var sources: Dictionary[String, Variant] = fixture.sources
	sources["0,0"] = source
	doc.mutate_on_second = true
	var rejected: DrawingResult = doc._publish_native_tile_edit(
		layer, base, base + 1, images, sources, fixture.bounds, true, true)
	check(not rejected.ok and rejected.code == "STALE_PIXEL",
		"attached native document rejects same-object source mutation")
	check(doc.revision == base and doc._native_raster_store == owner,
		"rejection keeps the native owner and its revision unchanged")
	check(int(owner.call("stats").get("revision", -1)) == base and
		doc.history_length() == previous_history,
		"rejection leaves native history and document timeline unchanged")
	check(int(doc.read_pixel(layer, 0, 0).value) == PAINT and
		int(doc.read_pixel(layer, STRIDE, 0).value) == 0,
		"attached rejection publishes no requested new Brush pixels")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native raster extension loaded")
	test_mutating_callback()
	test_unchanged_sources()
	test_attached_rejection()
	if failures == 0:
		print("T238_BRUSH_SOURCE_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T238_BRUSH_SOURCE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
