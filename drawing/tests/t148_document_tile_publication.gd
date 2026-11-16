extends SceneTree
## Native Brush -> native tile transaction -> actual DrawingDocument bulk
## publication. T-148 document-side contract, not a production Canvas cutover.

const STRIDE: int = 16
const COLOR: int = 0xa0ff4411
const HIDDEN: int = 0x00bc8765
var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_DOCUMENT_TILES_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func make_rgba8(pixels: Dictionary[int, int]) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(STRIDE * STRIDE * 4)
	for index: int in pixels:
		bytes.encode_u32(index * 4, pixels[index])
	return bytes


func make_document() -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new("t148-native-tile-document", STRIDE)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var seed: DrawingRasterTile = DrawingRasterTile.from_rgba8(STRIDE,
		make_rgba8({0: HIDDEN, 17: 0x55123456}))
	document._nodes[layer].tiles["-1,0"] = seed
	return {"doc": document, "layer": layer}


func test_native_publication() -> void:
	var context: Dictionary = make_document()
	var doc: DrawingDocument = context["doc"]
	var layer: String = context["layer"]
	var start_revision: int = doc.revision
	var source: Dictionary[String, Variant] = {}
	var store: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(store != null, "real Rust tile extension loaded")
	if store == null:
		return
	check(store.call("configure", STRIDE, start_revision), "native store configured at document revision")
	check(store.call("set_layer_editable", layer, true), "native layer authority")
	for cx: int in range(-1, 2):
		var key: String = "%d,0" % cx
		var fetched: DrawingResult = doc._resolve_chunk(layer, key)
		check(fetched.ok, "source tile fetched: " + key)
		source[key] = fetched.value
		var tile: DrawingRasterTile = fetched.value as DrawingRasterTile
		var initial: PackedByteArray = tile.to_rgba8() if tile != null else PackedByteArray()
		check(store.call("import_source", layer, cx, 0, start_revision, initial),
			"authorized exact native source: " + key)
	var edit: Dictionary = store.call("begin_edit", layer, start_revision, false)
	check(edit.get("ok", false), "native edit started")
	var transaction: int = int(edit.get("transaction", 0))
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var started: Dictionary = brush.call("begin_stroke", layer, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"), 6.0,
		COLOR, start_revision, Rect2i(-12, 0, 36, 16))
	check(started.get("ok", false), "native stroke started")
	var handle: int = int(started.get("handle", 0))
	check((brush.call("append_samples", handle, start_revision,
		PackedFloat32Array([-6.0, 5.0, 1.0, 0.01, 12.0, 5.0, 1.0, 0.01])) as Dictionary)
		.get("ok", false), "native brush samples appended")
	var required: Dictionary = brush.call("required_tiles", handle, start_revision, STRIDE, 0, 0)
	check(required.get("ok", false), "native tile discovery")
	var staged: Dictionary = brush.call("apply_tile_batch", store, handle, start_revision,
		transaction, 0, 0, false)
	check(staged.get("ok", false), "Rust-only pixel blending and staging")
	var dirty: Array = store.call("dirty_tiles", transaction)
	check(not dirty.is_empty(), "dirty native tiles available")
	var images: Dictionary[String, PackedByteArray] = {}
	var bounds: Dictionary[String, Rect2i] = {}
	var confirmed: Dictionary[String, Variant] = {}
	for descriptor: Dictionary in dirty:
		var x: int = int(descriptor["tile_x"])
		var y: int = int(descriptor["tile_y"])
		var key: String = "%d,%d" % [x, y]
		var image: Dictionary = store.call("read_tile", layer, x, y, true)
		check(image.get("ok", false), "native preview whole-tile read: " + key)
		images[key] = image["bytes"] as PackedByteArray
		bounds[key] = descriptor["dirty"] as Rect2i
		confirmed[key] = source[key]
	var old: PackedByteArray = (doc._nodes[layer].tiles["-1,0"] as DrawingRasterTile).to_rgba8()
	var incomplete: Dictionary[String, PackedByteArray] = images.duplicate()
	var missing: String = images.keys()[0]
	incomplete[missing] = PackedByteArray([5, 6])
	check(not doc._publish_native_tile_edit(layer, start_revision, start_revision + 1,
		incomplete, confirmed, bounds).ok, "malformed native tile rejected prepublication")
	check(doc.revision == start_revision and
		(doc._nodes[layer].tiles["-1,0"] as DrawingRasterTile).to_rgba8() == old,
		"invalid tile leaves entire source untouched")
	check(not doc._publish_native_tile_edit(layer, start_revision, start_revision + 2,
		images, confirmed, bounds).ok, "divergent native revision rejected")
	check((brush.call("commit_tiles", store, handle, start_revision,
		transaction) as Dictionary).get("ok", false), "single Rust transaction committed")
	var committed: DrawingResult = doc._publish_native_tile_edit(layer, start_revision,
		start_revision + 1, images, confirmed, bounds)
	check(committed.ok and doc.revision == start_revision + 1,
		"document publishes exactly one native revision")
	check(committed.delta != null and committed.delta.tile_stride == STRIDE and
		committed.delta.before.is_empty() and committed.delta.after.is_empty(),
		"native history stores tiles, no per-pixel String history")
	check(doc.history_length() == 1 and doc.history_position() == 1,
		"native brush gesture enters local history once")
	check(not committed.regions.is_empty() and not doc.display_changes_since(start_revision)["full"],
		"native dirty rectangles feed display invalidation")
	check(doc.read_pixel(layer, -16, 0).value == HIDDEN,
		"transparent hidden RGB survives unrelated native pixels")
	check(not doc._publish_native_tile_edit(layer, start_revision, start_revision + 1,
		images, confirmed, bounds).ok, "old native edit cannot replay on newer revision")
	for key: String in images:
		var tile: DrawingRasterTile = doc._nodes[layer].tiles.get(key)
		check(tile != null and tile.has_packed_rgba8(),
			"native source remains packed rather than GDScript sparse map: " + key)
		check(tile.to_rgba8() == images[key], "source tile bytes equal Rust export: " + key)
	var snapshot: Dictionary = doc.snapshot_for_save()
	for key: String in images:
		check(snapshot["dirty_rgba8"][layer + ":" + key] == images[key],
			".drawing save snapshot uses identical Rust bytes: " + key)
	# The actual standalone file writer/loader must agree with native source
	# bytes, not just the in-memory snapshot's metadata.
	var path: String = ProjectSettings.globalize_path("user://t148-native-doc-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok, "real .drawing writer accepts native tile snapshots")
	var reopened: DrawingResult = DrawingFileIO.open(path)
	check(reopened.ok, "real .drawing loader accepts native-edited document")
	if reopened.ok:
		var loaded: DrawingDocument = reopened.value as DrawingDocument
		for key: String in images:
			var pieces: PackedStringArray = key.split(",")
			var fetched: DrawingResult = loaded.request_chunk_at(layer,
				int(pieces[0]), int(pieces[1]))
			check(fetched.ok and (fetched.value as DrawingRasterTile).to_rgba8() == images[key],
				"native tile persists byte-identically through disk .drawing: " + key)
	DirAccess.remove_absolute(path)
	check(doc.undo().ok and doc.revision == start_revision + 2 and
		doc.history_position() == 0, "native whole-tile Undo")
	check(doc.read_pixel(layer, -16, 0).value == HIDDEN,
		"Undo preserves source hidden RGB")
	check(doc.redo().ok and doc.revision == start_revision + 3 and
		doc.history_position() == 1, "native whole-tile Redo")
	for key: String in images:
		var pieces: PackedStringArray = key.split(",")
		var fetched: DrawingResult = doc.request_chunk_at(layer, int(pieces[0]), int(pieces[1]))
		check(fetched.ok and (fetched.value as DrawingRasterTile).to_rgba8() == images[key],
			"Redo restores byte-exact tile source: " + key)
	# Verify raster compositor directly on packed native-source tiles.
	var view: Rect2i = Rect2i(-16, 0, 48, 16)
	var rendered: DrawingResult = DrawingRenderer.render(doc, view)
	check(rendered.ok, "real renderer accepts dense native source")
	if rendered.ok:
		var output: Image = rendered.value as Image
		for point: Vector2i in [Vector2i(-16, 0), Vector2i(-6, 5),
				Vector2i(0, 5), Vector2i(12, 5), Vector2i(24, 4)]:
			var value: int = int(doc.read_pixel(layer, point.x, point.y).value)
			var actual: Color = output.get_pixel(point.x - view.position.x, point.y)
			if (value >> 24) == 255:
				check(actual == Color8(value & 255, (value >> 8) & 255,
					(value >> 16) & 255, (value >> 24) & 255),
					"rendered opaque pixel matches native source " + str(point))
	# Alias safety: after publication, mutating caller bytes must not rewrite the document.
	var first_key: String = images.keys()[0]
	var copy: PackedByteArray = images[first_key]
	copy.encode_u32(0, 0xff123456)
	images[first_key] = copy
	check(doc.snapshot_for_save()["dirty_rgba8"][layer + ":" + first_key] != copy,
		"caller mutation cannot rewrite document tile")


func test_packed_sources_and_authority() -> void:
	var base: Dictionary = make_document()
	var doc: DrawingDocument = base["doc"]
	var layer: String = base["layer"]
	var tile: DrawingRasterTile = doc._nodes[layer].tiles["-1,0"]
	check(tile.has_packed_rgba8() and tile.get_rgba(0, 0) == HIDDEN,
		"packed source stores hidden RGB without sparse conversion")
	var detached: DrawingRasterTile = tile.detached_copy()
	check(detached.set_rgba(0, 0, COLOR) and tile.get_rgba(0, 0) == HIDDEN,
		"detached tile bytes cannot alias source")
	check(detached.get_rgba(0, 0) == COLOR and detached.to_rgba8().decode_u32(0) == COLOR,
		"packed individual pixel edits preserve packed byte layout")
	var sparse: Dictionary[int, int] = detached.sparse_pixels()
	check(sparse.has(0) and sparse.has(17) and not detached.has_packed_rgba8(),
		"explicit legacy editing transition retains nonzero pixels")
	check(tile.pixel_count() == 2 and not tile.is_empty(),
		"packed pixel count includes alpha-zero hidden RGB")
	var invalid: Dictionary[String, PackedByteArray] = {"0,0": make_rgba8({0: COLOR})}
	var source: Dictionary[String, Variant] = {"0,0": null}
	var bounds: Dictionary[String, Rect2i] = {"0,0": Rect2i(0, 0, 1, 1)}
	var rev: int = doc.revision
	check(doc.set_locked(layer, true).ok, "lock target layer before native publication")
	check(not doc._publish_native_tile_edit(layer, rev + 1, rev + 2,
		invalid, source, bounds).ok, "native publication rejected on locked layer")
	check(doc.read_pixel(layer, 0, 0).value == 0,
		"locked rejection never publishes a partial tile")
	check(doc.set_locked(layer, false).ok, "unlock layer")
	var seeded: DrawingResult = doc._resolve_chunk(layer, "-1,0")
	var stale: Dictionary[String, Variant] = {"-1,0": seeded.value}
	var changed: Dictionary[String, PackedByteArray] = {"-1,0": make_rgba8({0: COLOR})}
	var region: Dictionary[String, Rect2i] = {"-1,0": Rect2i(0, 0, 1, 1)}
	var alternate: DrawingRasterTile = seeded.value.detached_copy()
	doc._nodes[layer].tiles["-1,0"] = alternate
	check(not doc._publish_native_tile_edit(layer, doc.revision, doc.revision + 1,
		changed, stale, region).ok, "native tile source identity replacement rejected")
	check((doc._nodes[layer].tiles["-1,0"] as DrawingRasterTile).get_rgba(0, 0) == HIDDEN,
		"rejection preserves substituted source identity")


func run() -> void:
	if not ClassDB.class_exists("DrawingNativeTiles"):
		printerr("T148_DOCUMENT_TILES_FAILED: native extension missing")
		quit(1)
		return
	test_packed_sources_and_authority()
	test_native_publication()
	print("T148_DOCUMENT_TILES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
