extends SceneTree
## Guard the last three document publication/replay paths from abs(INT64_MIN).

const STRIDE: int = 64
const RGBA: int = 0xff3366aa
const HIDDEN: int = 0x00224466
const MIN_SIGNED: String = "-9223372036854775808"
const MAX_SIGNED: String = "9223372036854775807"
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T159_SIGNED_REPLAY_FAILED: " + message)


func tile_bytes(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = doc.request_chunk(layer, key)
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "real native tile and Hokusai classes loaded")
	var doc: DrawingDocument = DrawingDocument.new("t159-signed", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "begin native gesture")
	if not opened.ok:
		quit(1)
		return
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, RGBA, Rect2i(-64, -64, 128, 128), true).ok,
		"configure Hokusai hard round")
	check(session.paint_path_native(PackedVector2Array([
		Vector2(-10, 8), Vector2(8, 8)]), RGBA, false, null).ok,
		"stage real native Hokusai ink")
	var painted: DrawingResult = session.commit()
	check(painted.ok and painted.delta != null and
		painted.delta.native_history_token > 0, "native edit committed with token")
	if not painted.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var stamp: int = doc.revision
	var token: int = painted.delta.native_history_token
	var left: PackedByteArray = tile_bytes(doc, layer, "-1,0")
	var right: PackedByteArray = tile_bytes(doc, layer, "0,0")
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(STRIDE * STRIDE * 4)
	payload.encode_u32(0, HIDDEN)
	var unsafe_cases: Array[Dictionary] = [
		{"tile": MIN_SIGNED + ",0", "pixel": MIN_SIGNED + ",0"},
		{"tile": "0," + MIN_SIGNED, "pixel": "0," + MIN_SIGNED},
		{"tile": MAX_SIGNED + ",0", "pixel": MAX_SIGNED + ",0"},
		{"tile": "0," + MAX_SIGNED, "pixel": "0," + MAX_SIGNED},
		{"tile": "-70368744177665,0", "pixel": "-4503599627370497,0"},
		{"tile": "0,-70368744177665", "pixel": "0,-4503599627370497"},
		{"tile": "70368744177665,0", "pixel": "4503599627370497,0"},
		{"tile": "0,70368744177665", "pixel": "0,4503599627370497"},
	]
	for entry: Dictionary in unsafe_cases:
		var key: String = String(entry["tile"])
		var images: Dictionary[String, PackedByteArray] = {key: payload}
		var sources: Dictionary[String, Variant] = {key: null}
		var bounds: Dictionary[String, Rect2i] = {key: Rect2i(0, 0, 1, 1)}
		var publication: DrawingResult = doc._publish_native_tile_edit(layer,
			stamp, stamp + 1, images, sources, bounds, true, true)
		check(not publication.ok and publication.code == "COORD",
			"unsafe native publication key rejected before tile preflight: " + key)
		var before_tiles: Dictionary[String, PackedByteArray] = {key: PackedByteArray()}
		var after_tiles: Dictionary[String, PackedByteArray] = {key: payload}
		var detached: DrawingDelta = DrawingDelta.from_owned_tile_bytes(
			layer, STRIDE, before_tiles, after_tiles)
		var native_replay: DrawingResult = doc.replay_delta(detached, false)
		check(not native_replay.ok and native_replay.code == "COORD",
			"unsafe native history tile key rejected before import: " + key)
		var pixel_key: String = String(entry["pixel"])
		var old_delta: DrawingDelta = DrawingDelta.new(layer,
			{pixel_key: 0}, {pixel_key: HIDDEN})
		var old_replay: DrawingResult = doc.replay_delta(old_delta, false)
		check(not old_replay.ok and old_replay.code == "COORD",
			"unsafe historical pixel key rejected before grouping: " + pixel_key)
		check(doc.revision == stamp and doc._native_raster_store == store and
			int(store.call("stats").get("revision", -1)) == stamp and
			store.call("has_history_token", token, stamp, true),
			"rejected coordinate retains native history authority: " + key)
	check(tile_bytes(doc, layer, "-1,0") == left and
		tile_bytes(doc, layer, "0,0") == right,
		"rejected coordinates never touched signed canvas pixels")
	check(doc.undo().ok and doc.redo().ok and
		tile_bytes(doc, layer, "-1,0") == left and
		tile_bytes(doc, layer, "0,0") == right and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"previous Hokusai token still replays exactly after failures")
	if failures == 0:
		print("T159_SIGNED_REPLAY_PASSED checks=%d failures=0" % checks)
	else:
		print("T159_SIGNED_REPLAY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
