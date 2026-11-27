extends SceneTree
## Mixed legacy/projected and canonical sources must enter Rust as one removal.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0
var fetches: int = 0


func fetch(_ref: String) -> PackedByteArray:
	fetches += 1
	return PackedByteArray()


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T320_FAILED: " + label)


func fixture() -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("mixed", STRIDE)
	doc.create_layer(DrawingLayerNode.GROUP, "Bundle", "root", "bundle")
	doc.create_layer(DrawingLayerNode.RASTER, "First", "bundle", "first")
	doc.create_layer(DrawingLayerNode.RASTER, "Second", "bundle", "second")
	doc.create_layer(DrawingLayerNode.RASTER, "Empty", "bundle", "empty")
	var tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	tile.set_rgba(1, 2, 0x00112233)
	tile.set_rgba(3, 4, 0xff987654)
	doc._nodes["first"].tiles["-1,1"] = tile
	doc._nodes["first"].tiles["-2,2"] = tile.detached_copy()
	doc._nodes["second"].tiles["2,-3"] = tile.detached_copy()
	return doc


func authorize_first(doc: DrawingDocument, tile: DrawingRasterTile) -> Object:
	var store: Object = doc._native_store_for_edit(doc.revision)
	check(bool(store.call("import_source", "first", -1, 1, doc.revision, tile.to_rgba8())), "authorize one existing source")
	doc._remember_native_source("first", "-1,1", tile)
	return store


func matches(doc: DrawingDocument, parked: bool) -> bool:
	var store: Object = doc._native_raster_store
	if store == null or int(store.call("stats").get("revision", -1)) != doc.revision:
		return false
	for item: Array in [["first", -1, 1], ["first", -2, 2], ["second", 2, -3]]:
		var layer: String = item[0]
		var key: String = "%d,%d" % [item[1], item[2]]
		var read: Dictionary = store.call("read_tile", layer, item[1], item[2], false)
		var bytes: PackedByteArray = read.get("bytes", PackedByteArray())
		if not bool(read.get("ok", false)) or bytes.size() != STRIDE * STRIDE * 4 or \
				bytes.decode_u32((2 * STRIDE + 1) * 4) != 0x00112233 or \
				bytes.decode_u32((4 * STRIDE + 3) * 4) != 0xff987654 or \
				bool(store.call("is_layer_parked", layer)) != parked:
			return false
		if not parked and (not doc.has_node(layer) or not doc._native_source_matches(layer, key, doc._nodes[layer].tiles[key])):
			return false
	return bool(store.call("is_layer_parked", "empty")) == parked


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension available")
	var doc: DrawingDocument = fixture()
	var tile: DrawingRasterTile = doc._nodes["first"].tiles["-1,1"]
	var store: Object = authorize_first(doc, tile)
	var prior: int = doc.revision
	check(doc.remove_subtree("bundle", true).ok and doc.revision == prior + 1, "record mixed removal once")
	check(matches(doc, true), "mixed removal admits both an unowned sibling and an unowned tile in an owned layer")
	check(doc.undo().ok and matches(doc, false), "Undo restores all native sources")
	check(doc.redo().ok and matches(doc, true), "Redo parks all native sources")
	check(doc.undo().ok and matches(doc, false), "repeat Undo remains exact")
	# Simulate an older removal event and a replacement owner holding one parked source.
	var old: DrawingDocument = fixture()
	tile = old._nodes["first"].tiles["-1,1"]
	check(old.remove_subtree("bundle", true).ok, "retained legacy removal event")
	store = authorize_first(old, tile)
	check(bool(store.call("advance_parked_layers_revision", old.revision, PackedStringArray(["first"]), false, false)), "replacement owner parks only one raster ID")
	old.revision = int(store.call("stats").get("revision"))
	prior = old.revision
	check(old.undo().ok and old.revision == prior + 1 and matches(old, false), "mixed replacement owner adopts missing sources and unparks in one revision")
	check(old.redo().ok and matches(old, true), "mixed restored event can park all sources")
	# Recorded removal must preserve an explicit blank authorization and pending I/O.
	var guarded: DrawingDocument = fixture()
	tile = guarded._nodes["first"].tiles["-1,1"]
	store = authorize_first(guarded, tile)
	check(bool(store.call("import_source", "first", 3, 3, guarded.revision, PackedByteArray())), "authorize blank tile")
	guarded._remember_native_source("first", "3,3", null)
	var digest: String = DrawingRasterTile.digest_rgba8(tile.to_rgba8(), STRIDE)
	check(guarded.register_lazy_chunk("second", 4, 4, digest, digest, fetch).ok, "register unresolved source")
	prior = guarded.revision
	var bad: DrawingRasterTile = guarded._nodes["second"].tiles["2,-3"]
	guarded._nodes["second"].tiles["bad-key"] = bad.detached_copy()
	check(not guarded.remove_subtree("bundle", true).ok and guarded.revision == prior and guarded.has_node("bundle") and guarded.history_length() == 0, "bad later coordinate rejects before tree removal")
	check(not bool(store.call("has_source", "first", -2, 2, prior)) and not bool(store.call("is_layer_parked", "first")), "rejected batch leaves earlier source missing and owner live")
	guarded._nodes["second"].tiles.erase("bad-key")
	check(bool(store.call("import_source", "second", 8, 8, prior, bad.to_rgba8())), "inject untracked canonical source")
	check(not guarded.remove_subtree("bundle", true).ok and guarded.revision == prior and guarded.has_node("bundle"), "Rust rejects omitted canonical coordinate")
	guarded._nodes["second"].tiles["8,8"] = bad.detached_copy()
	guarded._remember_native_source("second", "8,8", guarded._nodes["second"].tiles["8,8"])
	bad.set_rgba(1, 2, 0x00445566)
	check(guarded.remove_subtree("bundle", true).ok and fetches == 0, "unowned bytes admitted without invoking lazy provider")
	check(guarded.undo().ok and guarded._pending_tiles.has("second:4,4") and fetches == 0, "pending descriptor survives Undo without I/O")
	check(guarded._native_source_matches("first", "3,3", null) and store.call("read_tile", "first", 3, 3, false).get("bytes").size() == STRIDE * STRIDE * 4, "blank authorization remains exact")
	check(guarded._native_source_matches("second", "2,-3", guarded._nodes["second"].tiles["2,-3"]), "newly adopted coordinate tracked")
	var changed: DrawingRasterTile = guarded._nodes["second"].tiles["2,-3"]
	changed.set_rgba(1, 2, 0x00778899)
	prior = guarded.revision
	check(not guarded.snapshot_for_save().ok and not guarded.export_subtree("bundle").ok, "newly admitted source fenced before first paint")
	check(not guarded.redo().ok and guarded.revision == prior and guarded.history_position() == 0, "corrupt projection cannot be parked")
	changed.set_rgba(1, 2, 0x00445566)
	var pending: Dictionary = guarded._pending_tiles["second:4,4"]
	guarded._pending_tiles["second:4,4"] = pending.duplicate(true)
	guarded._pending_tiles["second:4,4"]["sha256"] = "changed"
	check(not guarded.redo().ok and guarded.revision == prior and guarded.history_position() == 0, "changed pending descriptor cannot be erased by Redo")
	guarded._pending_tiles["second:4,4"] = pending
	check(guarded.redo().ok and guarded.undo().ok and fetches == 0, "exact restored source retries with pending descriptor")
	# A live canonical replacement is not a valid parked owner for Undo.
	var replacement: DrawingDocument = fixture()
	tile = replacement._nodes["first"].tiles["-1,1"]
	check(replacement.remove_subtree("bundle", true).ok, "legacy snapshot for guarded replacement")
	store = authorize_first(replacement, tile)
	prior = replacement.revision
	check(not replacement.undo().ok and replacement.history_position() == 1 and replacement.revision == prior and not replacement.has_node("bundle"), "live replacement source rejects Undo")
	check(bool(store.call("advance_parked_layers_revision", prior, PackedStringArray(["first"]), false, false)), "park replacement source")
	replacement.revision = int(store.call("stats").get("revision"))
	prior = replacement.revision
	var retained: DrawingRasterTile = replacement._events[0]["nodes"]["first"].tiles["-1,1"]
	retained.set_rgba(1, 2, 0x00445566)
	check(not replacement.undo().ok and replacement.revision == prior and replacement.history_position() == 1, "altered retained canonical source rejects Undo")
	retained.set_rgba(1, 2, 0x00112233)
	check(bool(store.call("set_layer_editable", "ink", true)), "prepare unrelated active transaction")
	var held: Dictionary = store.call("begin_edit", "ink", prior, false)
	check(bool(held.get("ok", false)) and not replacement.undo().ok and replacement.revision == prior, "active native edit rejects mixed Undo")
	check(bool(store.call("discard_edit", int(held.get("transaction", 0)))), "release native edit")
	check(replacement.undo().ok and matches(replacement, false), "retry restores canonical and detached bytes")
	# Unrelated Redo survives history reconciliation; direct Rust method also
	# rejects forged ownership and incomplete source descriptors.
	var foreign: DrawingDocument = fixture()
	tile = foreign._nodes["first"].tiles["-1,1"]
	check(foreign.remove_subtree("bundle", true).ok, "foreign history fixture")
	store = authorize_first(foreign, tile)
	var raw: PackedByteArray = tile.to_rgba8()
	var delta: Array[Dictionary] = [{"tile_x": -1, "tile_y": 0, "before": PackedByteArray(), "after": raw}]
	check(bool(store.call("set_layer_editable", "ink", true)) and bool(store.call("import_source", "ink", -1, 0, foreign.revision, PackedByteArray())), "authorize unrelated blank source")
	check(bool((store.call("adopt_external_edit", "ink", foreign.revision, delta) as Dictionary).get("ok", false)) and bool((store.call("undo_edit") as Dictionary).get("ok", false)), "retain unrelated Redo")
	foreign.revision = int(store.call("stats").get("revision"))
	check(bool(store.call("advance_parked_layers_revision", foreign.revision, PackedStringArray(["first"]), false, false)), "park partially owned layer with foreign Redo")
	foreign.revision = int(store.call("stats").get("revision"))
	prior = foreign.revision
	var forged: Array[Dictionary] = [{"layer": "first", "tile_x": -1, "tile_y": 1, "bytes": raw, "owned": false}]
	check(not bool(store.call("adopt_mixed_subtree_revision", prior, PackedStringArray(["first"]), forged, true, false)), "FFI cannot overwrite canonical source as unowned")
	forged[0]["tile_x"] = -2
	check(not bool(store.call("adopt_mixed_subtree_revision", prior, PackedStringArray(["first"]), forged, true, false)), "FFI rejects omission of canonical source")
	check(foreign.undo().ok and matches(foreign, false) and int(store.call("stats").get("redo")) == 1, "mixed history adoption preserves unrelated Redo")
	check(foreign.redo().ok and matches(foreign, true) and int(store.call("stats").get("redo")) == 1, "mixed replay preserves unrelated Redo")
	check(bool((store.call("redo_edit") as Dictionary).get("ok", false)) and store.call("read_tile", "ink", -1, 0, false).get("bytes") == raw, "unrelated native token restores exact bytes")
	print("T320_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T320_MIXED_SUBTREE_SOURCE_PASSED")
	quit(0 if failures == 0 else 1)
