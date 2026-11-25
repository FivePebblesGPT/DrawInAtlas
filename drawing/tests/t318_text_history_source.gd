extends SceneTree
## Text raster history must never restore detached glyphs outside native authority.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T318_FAILED: " + label)


func fixture() -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t318", STRIDE)
	var text: DrawingTextElement = DrawingTextElement.new()
	text.content = "Signed glyph"
	text.position = Vector2i(-40, -30)
	text.font_size = 22
	check(doc.commit_text("", text, doc.revision, "root", "glyph").ok, "text creation")
	check(doc.rasterize_text("glyph", doc.revision).ok, "text rasterization")
	return doc


func detach(doc: DrawingDocument) -> void:
	doc._native_raster_store = null
	doc._native_source_identities.clear()


func glyph_bytes(doc: DrawingDocument) -> Dictionary:
	var result: Dictionary = {}
	for key: String in doc.tile_keys("glyph"):
		result[key] = (doc.request_chunk("glyph", key).value as DrawingRasterTile).to_rgba8()
	return result


func glyph_bytes_from_snapshot(doc: DrawingDocument) -> Dictionary:
	var result: Dictionary = {}
	var node: DrawingLayerNode = doc._events[doc._cursor]["after"]
	for key: String in node.tiles:
		result[key] = node.tiles[key].to_rgba8()
	return result


func native_matches(doc: DrawingDocument, expected: Dictionary, parked: bool) -> bool:
	var store: Object = doc._native_raster_store
	if store == null or int(store.call("stats").get("revision", -1)) != doc.revision or \
			bool(store.call("is_layer_parked", "glyph")) != parked or expected.is_empty():
		return false
	for key: String in expected:
		var xy: PackedStringArray = key.split(",")
		var read: Dictionary = store.call("read_tile", "glyph", int(xy[0]), int(xy[1]), false)
		if not bool(read.get("ok", false)) or read.get("bytes") != expected[key]:
			return false
		if not parked and not doc._native_source_matches("glyph", key, doc._nodes["glyph"].tiles[key]):
			return false
	return true


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension available")
	var doc: DrawingDocument = fixture()
	var bytes: Dictionary = glyph_bytes(doc)
	var original_revision: int = doc.revision
	var original_cursor: int = doc.history_position()
	detach(doc)
	check(doc.undo().ok and doc.revision == original_revision + 1 and doc.history_position() == original_cursor - 1,
		"detached raster Undo advances once")
	check(native_matches(doc, bytes, true), "detached Undo acquires and parks glyph source")
	check(doc.snapshot_for_save().ok, "semantic snapshot after detached Undo")
	check(doc.redo().ok and native_matches(doc, bytes, false), "Redo restores native owner and exact projection")
	check(glyph_bytes(doc) == bytes, "exact signed raster after replay")
	check(doc.undo().ok, "rewind rasterization")
	detach(doc)
	check(doc.redo().ok and native_matches(doc, bytes, false), "detached Redo bootstraps native ownership")
	check(doc.undo().ok and native_matches(doc, bytes, true), "new owner parks source on next Undo")

	var stale: DrawingDocument = fixture()
	var store: Object = stale._native_raster_store
	var cursor: int = stale.history_position()
	var rev: int = stale.revision
	# Deliberately simulate an older host-only revision to test the stale fence.
	stale.revision += 1
	check(not stale.undo().ok and stale.revision == rev + 1 and stale.history_position() == cursor and
		stale.inspect_node("glyph").kind == DrawingLayerNode.RASTER and stale._native_raster_store == store,
		"stale attached owner rejects raster Undo without tree/history mutation")
	stale.revision = rev
	# The pre-fix code may have consumed the Undo above; use a fresh fixture below.
	var stale_redo: DrawingDocument = fixture()
	check(stale_redo.undo().ok, "prepare stale Redo")
	store = stale_redo._native_raster_store
	cursor = stale_redo.history_position()
	rev = stale_redo.revision
	stale_redo.revision += 1
	check(not stale_redo.redo().ok and stale_redo.revision == rev + 1 and stale_redo.history_position() == cursor and
		stale_redo.inspect_node("glyph").kind == DrawingLayerNode.TEXT and stale_redo._native_raster_store == store,
		"stale attached owner rejects raster Redo without tree/history mutation")
	stale_redo.revision = rev

	var tampered: DrawingDocument = fixture()
	detach(tampered)
	var key: String = tampered.tile_keys("glyph")[0]
	var tile: DrawingRasterTile = tampered._nodes["glyph"].tiles[key]
	var pixel: int = tile.get_rgba(0, 0)
	tile.set_rgba(0, 0, pixel ^ 0x00112233)
	rev = tampered.revision
	cursor = tampered.history_position()
	check(not tampered.undo().ok and tampered._native_raster_store == null and tampered.revision == rev and
		tampered.history_position() == cursor, "detached Undo rejects changed live raster against history")
	tile.set_rgba(0, 0, pixel)
	check(tampered.undo().ok and native_matches(tampered, glyph_bytes_from_snapshot(tampered), true),
		"restoring detached live bytes permits exact retry")
	var attached: DrawingDocument = fixture()
	bytes = glyph_bytes(attached)
	check(attached.undo().ok, "prepare unreferenced attached Redo")
	detach(attached)
	store = attached._native_store_for_edit(attached.revision)
	check(store != null, "attach fresh owner without glyphs")
	check(attached.redo().ok and attached._native_raster_store == store and native_matches(attached, bytes, false),
		"unreferenced attached Redo adopts glyphs without replacing owner")
	check(attached.undo().ok and native_matches(attached, bytes, true), "adopted source remains reversible")

	var extra: DrawingLayerNode = attached._events[attached._cursor]["after"]
	var extra_tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	extra_tile.set_rgba(0, 0, 0x00112233)
	extra.tiles["-20,20"] = extra_tile
	rev = attached.revision
	cursor = attached.history_position()
	check(not attached.redo().ok and attached.revision == rev and attached.history_position() == cursor and
		native_matches(attached, bytes, true), "unowned extra glyph tile cannot escape parked source authority")
	extra.tiles.erase("-20,20")
	check(attached.redo().ok and native_matches(attached, bytes, false), "complete parked snapshot retries")

	var pending: DrawingDocument = fixture()
	var ink: String = str(pending.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	detach(pending)
	var edit: DrawingEditSession = pending.begin_edit(ink, pending.revision).value
	rev = pending.revision
	cursor = pending.history_position()
	check(not pending.undo().ok and pending._native_raster_store == null and pending.revision == rev and
		pending.history_position() == cursor, "pending script edit prevents detached history admission")
	edit.cancel()
	check(pending.undo().ok and pending._native_raster_store != null, "same Undo retries after cancel")

	var malformed: DrawingDocument = fixture()
	check(malformed.undo().ok, "prepare malformed Redo")
	detach(malformed)
	var snapshot: DrawingLayerNode = malformed._events[malformed._cursor]["after"]
	var bad_key: String = "01,0"
	snapshot.tiles[bad_key] = DrawingRasterTile.new(STRIDE)
	rev = malformed.revision
	cursor = malformed.history_position()
	check(not malformed.redo().ok and malformed._native_raster_store == null and malformed.revision == rev and
		malformed.history_position() == cursor, "malformed late tile rejects entire provisional admission")
	snapshot.tiles.erase(bad_key)
	check(malformed.redo().ok and native_matches(malformed, glyph_bytes(malformed), false), "corrected detached Redo retries")

	var empty: DrawingDocument = DrawingDocument.new("t318-empty", STRIDE)
	var transparent: DrawingTextElement = DrawingTextElement.new()
	transparent.content = "Invisible"
	transparent.color_rgba = 0x00112233
	check(empty.commit_text("", transparent, empty.revision, "root", "glyph").ok and
		empty.rasterize_text("glyph", empty.revision).ok and empty.tile_keys("glyph").is_empty(), "empty glyph fixture")
	detach(empty)
	check(empty.undo().ok and empty._native_raster_store != null and
		not bool(empty._native_raster_store.call("is_layer_parked", "glyph")), "empty detached Undo advances without tombstone")
	check(empty.redo().ok and empty.tile_keys("glyph").is_empty() and
		int(empty._native_raster_store.call("stats").get("revision")) == empty.revision, "empty Redo shares native revision")

	# Existing owner with an unrelated native redo entry: an unreferenced
	# history import is not a new branch, so it must not clear that entry.
	var foreign: DrawingDocument = fixture()
	bytes = glyph_bytes(foreign)
	check(foreign.undo().ok, "prepare unrelated redo fixture")
	detach(foreign)
	store = foreign._native_store_for_edit(foreign.revision)
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(STRIDE * STRIDE * 4)
	raw.encode_u32(0, 0x00112233)
	var descriptor: Array[Dictionary] = [{"tile_x": -1, "tile_y": 0, "before": PackedByteArray(), "after": raw}]
	# Use the FFI's direct transaction to retain a redo token without adding
	# a competing Godot command. It is independent from the glyph source.
	check(bool(store.call("set_layer_editable", "ink", true)), "authorize unrelated native edit layer")
	check(bool(store.call("import_source", "ink", -1, 0, foreign.revision, PackedByteArray())), "prepare unrelated blank native source")
	var adopted: Dictionary = store.call("adopt_external_edit", "ink", foreign.revision, descriptor)
	check(bool(adopted.get("ok", false)), "unrelated native edit")
	check(bool((store.call("undo_edit") as Dictionary).get("ok", false)), "unrelated native Undo retains Redo token")
	foreign.revision = int(store.call("stats").get("revision"))
	check(int(store.call("stats").get("redo")) == 1, "one unrelated redo token before source replay")
	check(foreign.redo().ok and native_matches(foreign, bytes, false) and
		int(store.call("stats").get("redo")) == 1, "detached glyph Redo retains unrelated native Redo")
	check(bool((store.call("redo_edit") as Dictionary).get("ok", false)) and
		store.call("read_tile", "ink", -1, 0, false).get("bytes") == raw, "retained unrelated native Redo restores hidden RGB")
	print("T318_TEXT_HISTORY_SOURCE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
