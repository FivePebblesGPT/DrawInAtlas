extends SceneTree
## T-160: direct/older pixel and storage-tile producers must fail closed at
## the same signed projection boundary as Hokusai publication and native replay.

const STRIDE: int = 64
const LIMIT: int = 4503599627370496
const HIDDEN: int = 0x00123456
const OPAQUE: int = 0xff336699
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T160_DIRECT_BOUNDS_FAILED: " + message)


func read_tile(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = doc.request_chunk(layer, key)
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real Hokusai and tile store are loaded")
	var doc: DrawingDocument = DrawingDocument.new("t160-direct-bounds", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "native Hokusai session starts")
	if not opened.ok:
		quit(1)
		return
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, OPAQUE, Rect2i(-64, -64, 128, 128), true).ok,
		"real Hokusai preset configured")
	check(session.paint_path_native(PackedVector2Array([
		Vector2(-8, 8), Vector2(8, 8)]), OPAQUE, false, null).ok,
		"native Hokusai samples staged")
	var painted: DrawingResult = session.commit()
	check(painted.ok and painted.delta != null and
		painted.delta.native_history_token > 0, "native stroke commits with a history token")
	if not painted.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var token: int = painted.delta.native_history_token
	var stamp: int = doc.revision
	var before_left: PackedByteArray = read_tile(doc, layer, "-1,0")
	var before_right: PackedByteArray = read_tile(doc, layer, "0,0")
	var events: int = doc.history_length()
	var dirty_before: Dictionary = doc._dirty_tiles.duplicate()
	@warning_ignore("integer_division")
	var tile_limit: int = LIMIT / STRIDE

	# A direct tile publisher with record_history=false was able to install a
	# bad source in Godot while the existing Rust tile-store revision stood still.
	var unsafe_tiles: Array[String] = [
		"%d,0" % (tile_limit + 1), "%d,0" % (-tile_limit - 1),
		"0,%d" % (tile_limit + 1), "0,%d" % (-tile_limit - 1),
		"9223372036854775807,0", "-9223372036854775808,0"]
	for key: String in unsafe_tiles:
		var patches: Dictionary[String, Dictionary] = {key: {0: HIDDEN}}
		var sources: Dictionary[String, Variant] = {key: null}
		var failed: DrawingResult = doc._publish_tile_edit(layer, stamp,
			patches, sources, false)
		check(not failed.ok and failed.code == "COORD",
			"unsafe tile rejected before staging: " + key)
		check(doc.revision == stamp and doc._dirty_tiles == dirty_before,
			"unsafe tile leaves revision and save dirties untouched: " + key)

	var unsafe_pixels: Array[String] = [
		"%d,0" % (LIMIT + 1), "%d,0" % (-LIMIT - 1),
		"0,%d" % (LIMIT + 1), "0,%d" % (-LIMIT - 1),
		"9223372036854775807,0", "-9223372036854775808,0"]
	for coordinate: String in unsafe_pixels:
		var before: Dictionary[String, int] = {coordinate: 0}
		var after: Dictionary[String, int] = {coordinate: HIDDEN}
		var failed: DrawingResult = doc._publish_edit(layer, stamp, before, after, false)
		check(not failed.ok and failed.code == "COORD",
			"unsafe pixel rejected before detaching a source: " + coordinate)
		check(doc.revision == stamp and doc._dirty_tiles == dirty_before,
			"unsafe pixel leaves revision and save dirties untouched: " + coordinate)

	for malformed: String in ["whoops,0", "01,0", "+1,0", "0,", "0,01"]:
		var rejected: DrawingResult = doc._publish_edit(layer, stamp,
			{malformed: 0}, {malformed: HIDDEN}, false)
		check(not rejected.ok and rejected.code == "COORD",
			"noncanonical or malformed direct pixel is rejected: " + malformed)
	check(doc.revision == stamp and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == stamp and
		store.call("has_history_token", token, stamp, true) and
		doc.history_length() == events and doc._dirty_tiles == dirty_before and
		read_tile(doc, layer, "-1,0") == before_left and
		read_tile(doc, layer, "0,0") == before_right,
		"all invalid submissions preserve native source, history and metadata")

	# Valid endpoints remain supported; a direct pixel producer and a direct
	# tile-local producer both become native external edits with Undo tokens.
	if doc.revision == stamp:
		var max_pixel: String = "%d,0" % LIMIT
		var accepted_pixel: DrawingResult = doc._publish_edit(layer, doc.revision,
			{max_pixel: 0}, {max_pixel: HIDDEN})
		check(accepted_pixel.ok and accepted_pixel.delta != null and
			accepted_pixel.delta.native_history_token > 0,
			"positive inclusive pixel endpoint is adopted by native history")
		var min_tile: String = "0,%d" % -tile_limit
		var patches: Dictionary[String, Dictionary] = {min_tile: {0: HIDDEN}}
		var sources: Dictionary[String, Variant] = {min_tile: null}
		var accepted_tile: DrawingResult = doc._publish_tile_edit(layer,
			doc.revision, patches, sources)
		check(accepted_tile.ok and accepted_tile.delta != null and
			accepted_tile.delta.native_history_token > 0,
			"negative inclusive tile endpoint is adopted by native history")
		var final_revision: int = doc.revision
		check(int(doc.read_pixel(layer, LIMIT, 0).value) == HIDDEN and
			read_tile(doc, layer, min_tile).decode_u32(0) == HIDDEN,
			"valid signed endpoints preserve alpha-zero hidden RGB")
		check(doc.undo().ok and doc.undo().ok and
			read_tile(doc, layer, "0,0") == before_right and
			read_tile(doc, layer, "-1,0") == before_left,
			"Undo crosses two direct edits and preserves original Hokusai tiles")
		check(doc.redo().ok and doc.redo().ok and
			doc.revision == final_revision + 4 and
			int(doc.read_pixel(layer, LIMIT, 0).value) == HIDDEN and
			read_tile(doc, layer, min_tile).decode_u32(0) == HIDDEN and
			int(store.call("stats").get("revision", -1)) == doc.revision,
			"Redo preserves both signed sources on one Rust revision timeline")
		var save_path: String = ProjectSettings.globalize_path(
			"user://t160-direct-" + DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(doc, save_path).ok, "native and direct edit snapshot saves")
		var reopened: DrawingResult = DrawingFileIO.open(save_path)
		check(reopened.ok, "snapshot with signed endpoint sources reopens")
		if reopened.ok:
			check(int((reopened.value as DrawingDocument).read_pixel(layer, LIMIT, 0).value) == HIDDEN and
				read_tile(reopened.value as DrawingDocument, layer, min_tile).decode_u32(0) == HIDDEN,
				"Save/Open preserves full RGBA8 and signed endpoints")
		DirAccess.remove_absolute(save_path)
	else:
		check(false, "rejected inputs cannot corrupt the document before valid controls")

	# Historical direct pixel publication is still supported before native
	# attachment. T-230 now requires *all* pixel-history replay to cross the
	# signed Rust projection boundary, so an out-of-range Undo must fail closed.
	var legacy: DrawingDocument = DrawingDocument.new("t160-legacy-64bit", STRIDE)
	var legacy_layer: String = str(legacy.create_layer(DrawingLayerNode.RASTER, "Old").value)
	var old_far: String = "9007199254740993,-9007199254740993"
	check(legacy._native_raster_store == null, "historical non-native session stays detached")
	var old_commit: DrawingResult = legacy._publish_edit(legacy_layer, legacy.revision,
		{old_far: 0}, {old_far: HIDDEN})
	check(old_commit.ok and int(legacy.read_pixel(legacy_layer,
		9007199254740993, -9007199254740993).value) == HIDDEN,
		"pre-native signed 64-bit direct pixel fixture remains unchanged")
	check(not legacy.undo().ok and legacy.history_position() == 1 and
		legacy._native_raster_store == null and
		int(legacy.read_pixel(legacy_layer,
		9007199254740993, -9007199254740993).value) == HIDDEN,
		"out-of-projection historical Undo fails closed without native attachment")

	if failures == 0:
		print("T160_DIRECT_BOUNDS_PASSED checks=%d failures=0" % checks)
	else:
		print("T160_DIRECT_BOUNDS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
