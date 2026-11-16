extends SceneTree
## T-162: non-historical direct raster commits must still keep the resident
## Rust source/revision authoritative. They must not manufacture Undo tokens.

const STRIDE: int = 64
const HIDDEN: int = 0x00123456
const VISIBLE: int = 0xff776655
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T162_UNTRACKED_FAILED: " + label)


func tile(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = doc.request_chunk(layer, key)
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not opened.ok:
		return opened
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var configured: DrawingResult = session.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, VISIBLE, Rect2i(-64, -64, 128, 128), true)
	if not configured.ok:
		session.cancel()
		return configured
	var painted: DrawingResult = session.paint_path_native(
		PackedVector2Array([Vector2(4, 9), Vector2(12, 9)]),
		VISIBLE, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required Rust extension loaded")
	var doc: DrawingDocument = DrawingDocument.new("t162-untracked-native", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var overlay: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Overlay").value)
	var first: DrawingResult = paint(doc, ink)
	check(first.ok and first.delta.native_history_token > 0, "real Hokusai gesture attaches Rust")
	if not first.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var first_token: int = first.delta.native_history_token
	var first_bytes: PackedByteArray = tile(doc, ink, "0,0")
	var initial_revision: int = doc.revision
	check(store != null and int(store.call("stats").get("undo", -1)) == 1,
		"initial native brush token is live")
	var baseline_path: String = ProjectSettings.globalize_path("user://t162-base-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, baseline_path).ok and not doc.is_dirty(),
		"recorded Hokusai baseline saves and clears dirty state")
	DirAccess.remove_absolute(baseline_path)

	# A valid non-historical GDScript direct edit must advance the shared
	# revision and canonical Rust source, but must not invent a native Undo token.
	var direct: DrawingResult = doc._publish_edit(overlay, doc.revision,
		{"-2,3": 0}, {"-2,3": HIDDEN}, false)
	check(direct.ok and direct.delta != null and direct.delta.native_history_token == 0,
		"untracked signed pixel publishes with no history token")
	check(doc.revision == initial_revision + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		doc._native_raster_store == store, "direct publication shares a native revision")
	var negative: Dictionary = store.call("read_tile", overlay, -1, 0, false)
	check(negative.get("ok", false) and
		(negative.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32((3 * STRIDE + 62) * 4) == HIDDEN,
		"canonical native source retains signed hidden RGB")
	check(int(store.call("stats").get("undo", -1)) == 0 and
		int(store.call("stats").get("redo", -1)) == 0 and
		not store.call("has_history_token", first_token, doc.revision, true),
		"untracked write invalidates obsolete native tokens instead of inventing one")
	check(doc.history_length() == 1 and doc.history_position() == 1,
		"non-historical update does not append a Godot history entry")
	check(doc.is_dirty(),
		"untracked native publication marks source dirty since saved Hokusai baseline")

	# An invalid before-image must fail without changing either authority.
	var stamp: int = doc.revision
	var dirty: Dictionary = doc._dirty_tiles.duplicate()
	var invalid: DrawingResult = doc._publish_edit(overlay, stamp,
		{"-2,3": 0}, {"-2,3": VISIBLE}, false)
	check(not invalid.ok and invalid.code == "STALE_PIXEL" and
		doc.revision == stamp and doc._dirty_tiles == dirty and
		int(store.call("stats").get("revision", -1)) == stamp,
		"stale direct source is failure atomic")

	# Edit an already authorized tile, not just a newly imported one. Rust
	# must check the resident before-image, retain hidden RGB, and never add a
	# token for this follow-up nonhistorical mutation.
	var resident_edit: DrawingResult = doc._publish_edit(overlay, doc.revision,
		{"-3,3": 0}, {"-3,3": 0x000a1b2c}, false)
	check(resident_edit.ok and resident_edit.delta.native_history_token == 0 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"existing native source accepts a checked nonhistorical update")
	var resident: Dictionary = store.call("read_tile", overlay, -1, 0, false)
	check(resident.get("ok", false) and
		(resident.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32((3 * STRIDE + 61) * 4) == 0x000a1b2c and
		(resident.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32((3 * STRIDE + 62) * 4) == HIDDEN,
		"existing signed tile preserves both alpha-zero hidden-RGB pixels")

	# A second non-historical producer publishes tile-local patches. Its source
	# is a missing tile on the positive side, independent of the first tile.
	var patch: Dictionary[String, Dictionary] = {"0,0": {3 * STRIDE + 4: VISIBLE}}
	var source: Dictionary[String, Variant] = {"0,0": null}
	var direct_tile: DrawingResult = doc._publish_tile_edit(overlay, doc.revision,
		patch, source, false)
	check(direct_tile.ok and direct_tile.delta != null and
		direct_tile.delta.native_history_token == 0,
		"untracked tile-local publication has no history token")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		doc._native_raster_store == store, "tile-local publication shares native revision")
	var positive: Dictionary = store.call("read_tile", overlay, 0, 0, false)
	check(positive.get("ok", false) and
		(positive.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32((3 * STRIDE + 4) * 4) == VISIBLE,
		"tile-local RGBA8 bytes are resident in Rust")
	check(int(doc.read_pixel(overlay, -2, 3).value) == HIDDEN and
		int(doc.read_pixel(overlay, 4, 3).value) == VISIBLE,
		"Godot projection preserves both untracked edits")

	# Following Hokusai gestures must not rebase away the untracked source.
	var second: DrawingResult = paint(doc, ink)
	check(second.ok and second.delta.native_history_token > 0,
		"subsequent native Brush can commit")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		store.call("has_source", overlay, -1, 0, doc.revision) and
		store.call("has_source", overlay, 0, 0, doc.revision),
		"future Brush does not discard previously adopted untracked native tiles")
	check(tile(doc, overlay, "-1,0") == (store.call("read_tile", overlay, -1, 0, false) as Dictionary).get("bytes", PackedByteArray()) and
		tile(doc, overlay, "0,0") == (store.call("read_tile", overlay, 0, 0, false) as Dictionary).get("bytes", PackedByteArray()),
		"both storage projections exactly equal canonical Rust bytes")
	if second.ok:
		var after_second: PackedByteArray = tile(doc, ink, "0,0")
		check(doc.undo().ok and tile(doc, ink, "0,0") == first_bytes and
			doc.redo().ok and tile(doc, ink, "0,0") == after_second,
			"new Hokusai token restores exact first/second source on Undo/Redo")
		check(int(store.call("stats").get("revision", -1)) == doc.revision and
			int(doc.read_pixel(overlay, -2, 3).value) == HIDDEN and
			int(doc.read_pixel(overlay, 4, 3).value) == VISIBLE,
			"new stroke history does not change untracked source")

	var save_path: String = ProjectSettings.globalize_path("user://t162-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "mixed untracked source saves to .drawing")
	var opened: DrawingResult = DrawingFileIO.open(save_path)
	check(opened.ok, "mixed untracked source opens")
	if opened.ok:
		check(tile(opened.value as DrawingDocument, ink, "0,0") == tile(doc, ink, "0,0") and
			tile(opened.value as DrawingDocument, overlay, "-1,0") == tile(doc, overlay, "-1,0") and
			tile(opened.value as DrawingDocument, overlay, "0,0") == tile(doc, overlay, "0,0"),
			"Save/Open retains exact Hokusai and untracked RGBA8")
	DirAccess.remove_absolute(save_path)

	if failures == 0:
		print("T162_UNTRACKED_PASSED checks=%d failures=0" % checks)
	else:
		print("T162_UNTRACKED_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
