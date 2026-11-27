extends SceneTree
## A detached subtree removal must restore/park all of its raster sources atomically.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T319_FAILED: " + label)


func fixture() -> DrawingDocument:
	var donor: DrawingDocument = DrawingDocument.new("donor", STRIDE)
	donor.create_layer(DrawingLayerNode.GROUP, "Bundle", "root", "bundle")
	donor.create_layer(DrawingLayerNode.RASTER, "First", "bundle", "first")
	donor.create_layer(DrawingLayerNode.RASTER, "Second", "bundle", "second")
	donor.create_layer(DrawingLayerNode.RASTER, "Empty", "bundle", "empty")
	var tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	tile.set_rgba(1, 2, 0x00112233)
	tile.set_rgba(3, 4, 0xff987654)
	donor._nodes["first"].tiles["-1,1"] = tile
	donor._nodes["second"].tiles["2,-3"] = tile.detached_copy()
	var doc: DrawingDocument = DrawingDocument.new("recipient", STRIDE)
	check(doc.import_subtree(donor.export_subtree("bundle").value, "root", true).ok, "import two raster sources")
	check(doc.remove_subtree("bundle", true).ok, "record subtree removal")
	return doc


func detach(doc: DrawingDocument) -> void:
	doc._native_raster_store = null
	doc._native_source_identities.clear()


func native_matches(doc: DrawingDocument, parked: bool) -> bool:
	var store: Object = doc._native_raster_store
	if store == null or int(store.call("stats").get("revision", -1)) != doc.revision:
		return false
	for layer: String in ["first", "second"]:
		var key: String = "-1,1" if layer == "first" else "2,-3"
		var xy: PackedStringArray = key.split(",")
		var read: Dictionary = store.call("read_tile", layer, int(xy[0]), int(xy[1]), false)
		var bytes: PackedByteArray = read.get("bytes", PackedByteArray())
		if not bool(read.get("ok", false)) or bytes.size() != STRIDE * STRIDE * 4 or \
				bytes.decode_u32((2 * STRIDE + 1) * 4) != 0x00112233 or \
				bytes.decode_u32((4 * STRIDE + 3) * 4) != 0xff987654 or \
				bool(store.call("is_layer_parked", layer)) != parked:
			return false
		if not parked and (not doc.has_node(layer) or not doc._native_source_matches(layer, key, doc._nodes[layer].tiles[key])):
			return false
	return true


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension ready")
	var doc: DrawingDocument = fixture()
	detach(doc)
	var prior: int = doc.revision
	check(doc.undo().ok and doc.revision == prior + 1 and doc.history_position() == 0, "detached Undo restores tree once")
	check(native_matches(doc, false), "detached Undo immediately owns both raster sources")
	check(doc.redo().ok and native_matches(doc, true), "restored subtree Redo parks both sources")
	check(doc.undo().ok and native_matches(doc, false), "second Undo restores exact native sources")
	# Detach after the restoration, not before it.
	detach(doc)
	prior = doc.revision
	check(doc.redo().ok and doc.revision == prior + 1 and native_matches(doc, true), "detached Redo adopts and parks exact sources")
	check(doc.undo().ok and native_matches(doc, false), "detached Redo can be restored")
	# A newly attached owner may have unrelated history, but no affected IDs.
	var attached: DrawingDocument = fixture()
	detach(attached)
	var store: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(bool(store.call("configure", STRIDE, attached.revision)), "replacement owner configured")
	attached._native_raster_store = store
	check(attached.undo().ok and attached._native_raster_store == store and native_matches(attached, false), "replacement owner restores instead of trusting stale parked flag")
	# Invalid late descriptor must not publish any preceding layer.
	var malformed: DrawingDocument = fixture()
	detach(malformed)
	var snapshot: DrawingLayerNode = malformed._events[0]["nodes"]["second"]
	var tile: DrawingRasterTile = snapshot.tiles["2,-3"]
	snapshot.tiles["bad-key"] = tile.detached_copy()
	prior = malformed.revision
	check(not malformed.undo().ok and malformed.revision == prior and malformed.history_position() == 1 and not malformed.has_node("bundle") and malformed._native_raster_store == null, "invalid later descriptor rejects atomically")
	snapshot.tiles.erase("bad-key")
	check(malformed.undo().ok and native_matches(malformed, false), "retry after malformed snapshot")
	# Detached removal compares live bytes with the retained history source.
	detach(malformed)
	var live: DrawingRasterTile = malformed._nodes["second"].tiles["2,-3"]
	live.set_rgba(1, 2, 0x00445566)
	prior = malformed.revision
	check(not malformed.redo().ok and malformed.revision == prior and malformed.history_position() == 0 and malformed.has_node("bundle") and malformed._native_raster_store == null, "changed detached live bytes reject Redo")
	live.set_rgba(1, 2, 0x00112233)
	check(malformed.redo().ok and native_matches(malformed, true), "retry exact detached Redo")
	# The newly admitted parked snapshot cannot gain an unauthorized tile.
	var adopted: DrawingLayerNode = malformed._events[0]["nodes"]["second"]
	adopted.tiles["4,4"] = tile.detached_copy()
	prior = malformed.revision
	check(not malformed.undo().ok and malformed.revision == prior and malformed.history_position() == 1 and native_matches(malformed, true), "extra parked tile rejects instead of publishing unowned pixels")
	adopted.tiles.erase("4,4")
	check(malformed.undo().ok and native_matches(malformed, false), "parked source remains usable after rejecting extra tile")
	malformed._nodes["second"].tiles["4,4"] = tile.detached_copy()
	prior = malformed.revision
	check(not malformed.redo().ok and malformed.revision == prior and malformed.history_position() == 0 and native_matches(malformed, false), "extra live tile rejects instead of silently discarding bytes")
	malformed._nodes["second"].tiles.erase("4,4")
	check(malformed.redo().ok and native_matches(malformed, true), "exact live subtree can park again")
	# A replacement owner must preserve unrelated native redo history.
	var foreign: DrawingDocument = fixture()
	detach(foreign)
	store = foreign._native_store_for_edit(foreign.revision)
	var raw: PackedByteArray = tile.to_rgba8()
	var descriptor: Array[Dictionary] = [{"tile_x": -1, "tile_y": 0, "before": PackedByteArray(), "after": raw}]
	check(bool(store.call("set_layer_editable", "ink", true)) and
		bool(store.call("import_source", "ink", -1, 0, foreign.revision, PackedByteArray())), "unrelated native source prepared")
	check(bool((store.call("adopt_external_edit", "ink", foreign.revision, descriptor) as Dictionary).get("ok", false)) and
		bool((store.call("undo_edit") as Dictionary).get("ok", false)), "unrelated native Redo retained")
	foreign.revision = int(store.call("stats").get("revision"))
	check(foreign.undo().ok and native_matches(foreign, false) and int(store.call("stats").get("redo")) == 1, "subtree adoption keeps unrelated Redo")
	check(foreign.redo().ok and native_matches(foreign, true) and int(store.call("stats").get("redo")) == 1, "subtree parking keeps unrelated Redo")
	check(bool((store.call("redo_edit") as Dictionary).get("ok", false)) and
		store.call("read_tile", "ink", -1, 0, false).get("bytes") == raw, "retained native token restores exact unrelated bytes")
	# A stale or busy replacement owner cannot be bypassed by detaching it.
	var guarded: DrawingDocument = fixture()
	detach(guarded)
	store = guarded._native_store_for_edit(guarded.revision)
	prior = guarded.revision
	check(bool(store.call("advance_metadata_revision", prior, false)), "advance replacement owner independently")
	check(not guarded.undo().ok and guarded.revision == prior and guarded.history_position() == 1 and guarded._native_raster_store == store and not guarded.has_node("bundle"), "stale replacement rejects without clearing owner")
	guarded.revision = int(store.call("stats").get("revision"))
	check(bool(store.call("set_layer_editable", "ink", true)), "allow unrelated transaction")
	var held: Dictionary = store.call("begin_edit", "ink", guarded.revision, false)
	prior = guarded.revision
	check(bool(held.get("ok", false)) and not guarded.undo().ok and guarded.revision == prior and guarded.history_position() == 1, "busy replacement rejects atomically")
	check(bool(store.call("discard_edit", int(held.get("transaction", 0)))), "release unrelated transaction")
	check(guarded.undo().ok and native_matches(guarded, false), "subtree retries after transaction release")
	# Detached script reservation and invalid hierarchy are checked before bootstrap.
	var reserved: DrawingDocument = fixture()
	reserved.create_layer(DrawingLayerNode.RASTER, "Other", "root", "other")
	detach(reserved)
	var edit: DrawingEditSession = reserved.begin_edit("other", reserved.revision).value
	prior = reserved.revision
	check(not reserved.undo().ok and reserved.revision == prior and reserved.history_position() == 1 and reserved._native_raster_store == null, "script reservation blocks provisional owner")
	edit.cancel()
	var tree: DrawingLayerNode = reserved._events[0]["nodes"]["bundle"]
	tree.children.append("missing")
	check(not reserved.undo().ok and reserved.revision == prior and reserved._native_raster_store == null, "invalid retained hierarchy fails before source publication")
	tree.children.pop_back()
	var bad: DrawingRasterTile = reserved._events[0]["nodes"]["second"].tiles["2,-3"]
	bad._pixels[-1] = 0xff123456
	check(not reserved.undo().ok and reserved.revision == prior and reserved._native_raster_store == null, "invalid sparse backing fails before provisional publication")
	bad._pixels.erase(-1)
	check(reserved.undo().ok and native_matches(reserved, false), "valid retained sources retry after all rejections")
	var path: String = ProjectSettings.globalize_path("user://t319-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(reserved, path).ok, "restored subtree saves before first paint")
	var opened: DrawingResult = DrawingFileIO.open(path)
	check(opened.ok and native_matches(opened.value as DrawingDocument, false), "restored subtree Save/Open preserves signed hidden RGB")
	DirAccess.remove_absolute(path)
	var changed: DrawingRasterTile = reserved._nodes["second"].tiles["2,-3"]
	changed.set_rgba(1, 2, 0x00445566)
	check(not reserved.snapshot_for_save().ok and not reserved.export_subtree("bundle").ok, "restored authority protects Save and Copy before first paint")
	changed.set_rgba(1, 2, 0x00112233)
	check(reserved.snapshot_for_save().ok, "exact restored projection saves again")
	# No original native store or parked flag is required for an old retained raster.
	var legacy: DrawingDocument = DrawingDocument.new("legacy", STRIDE)
	legacy.create_layer(DrawingLayerNode.GROUP, "Bundle", "root", "bundle")
	legacy.create_layer(DrawingLayerNode.RASTER, "First", "bundle", "first")
	legacy.create_layer(DrawingLayerNode.RASTER, "Second", "bundle", "second")
	legacy._nodes["first"].tiles["-1,1"] = tile.detached_copy()
	legacy._nodes["second"].tiles["2,-3"] = tile.detached_copy()
	check(legacy.remove_subtree("bundle", true).ok and legacy._native_raster_store == null and not bool(legacy._events[0].get("native_parked", false)), "legacy detached removal fixture")
	check(legacy.undo().ok and native_matches(legacy, false) and legacy.redo().ok and native_matches(legacy, true), "legacy retained subtree acquires authority on first Undo")
	# Purely empty removal retains the existing metadata-only path.
	var empty: DrawingDocument = DrawingDocument.new("empty", STRIDE)
	empty.create_layer(DrawingLayerNode.RASTER, "Empty", "root", "empty")
	check(empty.remove_subtree("empty", true).ok and empty.undo().ok and empty.redo().ok and empty._native_raster_store == null, "all-empty detached history does not allocate an owner")
	print("T319_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T319_SUBTREE_HISTORY_SOURCE_PASSED")
	quit(0 if failures == 0 else 1)
