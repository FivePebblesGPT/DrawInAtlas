extends SceneTree
## Immediate authority for every raster in a detached subtree, including first use.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T314_FAILED: " + label)


func matches(doc: DrawingDocument, layer: String, key: String) -> bool:
	var store: Object = doc._native_raster_store
	if store == null:
		return false
	var coords: PackedStringArray = key.split(",")
	return bool(store.call("has_source", layer, int(coords[0]), int(coords[1]), doc.revision)) and \
		store.call("read_tile", layer, int(coords[0]), int(coords[1]), false).get("bytes") == doc._nodes[layer].tiles[key].to_rgba8()


func run() -> void:
	var donor: DrawingDocument = DrawingDocument.new("donor", STRIDE)
	var group: String = str(donor.create_layer(DrawingLayerNode.GROUP, "Bundle", "root", "bundle").value)
	var first: String = str(donor.create_layer(DrawingLayerNode.RASTER, "First", group, "first").value)
	var second: String = str(donor.create_layer(DrawingLayerNode.RASTER, "Second", group, "second").value)
	var empty: String = str(donor.create_layer(DrawingLayerNode.RASTER, "Empty", group, "empty").value)
	var tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	tile.set_rgba(1, 2, 0x00112233)
	tile.set_rgba(3, 4, 0xff987654)
	donor._nodes[first].tiles["-1,1"] = tile
	donor._nodes[second].tiles["2,-3"] = tile.detached_copy()
	var snapshot: Dictionary = donor.export_subtree(group).value
	var target: DrawingDocument = DrawingDocument.new("recipient", STRIDE)
	var before: int = target.revision
	check(target.import_subtree(snapshot, "root", true).ok, "first-use multi-layer import succeeds")
	check(target.revision == before + 1 and target.history_length() == 0, "one untracked structural revision")
	check(matches(target, first, "-1,1") and matches(target, second, "2,-3"), "all signed sources immediately native")
	var store: Object = target._native_raster_store
	check(store != null, "first import attaches owner")
	if store == null:
		finish()
		return
	check(int(store.call("stats").get("tiles")) == 2 and int(store.call("stats").get("undo")) == 0, "no empty tombstone or duplicate history")
	check(not bool(store.call("is_layer_parked", empty)), "empty layer not parked")
	var projected: DrawingRasterTile = target._nodes[second].tiles["2,-3"]
	projected.set_rgba(1, 2, 0x00445566)
	check(not target.snapshot_for_save().ok and not target.export_subtree(group).ok, "projection corruption rejected before any paint")
	projected.set_rgba(1, 2, 0x00112233)
	check(target.snapshot_for_save().ok, "exact source can save")
	check(target.remove_subtree(group, true).ok and bool(store.call("is_layer_parked", first)) and bool(store.call("is_layer_parked", second)), "recorded removal parks both sources")
	check(target.undo().ok and matches(target, first, "-1,1") and matches(target, second, "2,-3"), "structural undo restores both sources")
	check(target.redo().ok and target.undo().ok, "structural replay repeatable")
	check(target.remove_subtree(group).ok and not bool(store.call("has_source", first, -1, 1, target.revision)), "unrecorded retirement removes canonical source")
	check(target.import_subtree(snapshot, "root", true).ok and matches(target, second, "2,-3"), "retired ID may be reused")
	var invalid: Dictionary = donor.export_subtree(group).value
	invalid["nodes"][second].tiles["bad-key"] = tile.detached_copy()
	before = target.revision
	var layers: int = target.layer_count()
	check(not target.import_subtree(invalid, "root").ok and target.revision == before and target.layer_count() == layers, "late invalid tile rejects whole tree")
	var pristine: DrawingDocument = DrawingDocument.new("pristine", STRIDE)
	check(not pristine.import_subtree(invalid, "root").ok and pristine._native_raster_store == null and pristine.layer_count() == 0, "failed bootstrap stays detached")
	var bad_storage: Dictionary = donor.export_subtree(group).value
	bad_storage["nodes"][second].tiles["2,-3"]._pixels[-1] = 0xff112233
	check(not pristine.import_subtree(bad_storage, "root", true).ok and pristine._native_raster_store == null, "malformed sparse storage rejected before encoding")
	var bad_packed: Dictionary = donor.export_subtree(group).value
	bad_packed["nodes"][second].tiles["2,-3"]._rgba8 = PackedByteArray([1])
	check(not pristine.import_subtree(bad_packed, "root", true).ok and pristine.layer_count() == 0, "malformed packed storage rejected before encoding")
	var out_of_range: Dictionary = donor.export_subtree(group).value
	out_of_range["nodes"][second].tiles["9223372036854775807,0"] = tile.detached_copy()
	check(not pristine.import_subtree(out_of_range, "root", true).ok and pristine.revision == 0, "unprojectable signed coordinate rejects complete tree")
	# A second import must retain native history of an unrelated layer.
	var ink: String = str(target.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	var edit: DrawingEditSession = target.begin_edit(ink, target.revision).value
	check(edit.fill_rect(Rect2i(-2, -2, 4, 4), 0x00445566).ok and edit.commit().ok, "unrelated native edit")
	var prior: Dictionary = store.call("stats")
	var copied: DrawingResult = target.import_subtree(snapshot, "root")
	check(copied.ok and target._native_raster_store == store and int(store.call("stats").get("undo")) == int(prior.get("undo")), "remapped import retains unrelated native token")
	var new_children: Array[String] = target.list_children(str(copied.value))
	check(new_children.size() == 3 and matches(target, new_children[0], "-1,1") and matches(target, new_children[1], "2,-3"), "remapped multi-source exact native adoption")
	check(target.undo().ok and int(target.read_pixel(ink, -1, -1).value) == 0 and target.redo().ok and int(target.read_pixel(ink, -1, -1).value) == 0x00445566, "unrelated native Undo/Redo crosses import")
	var path: String = ProjectSettings.globalize_path("user://t314-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(target, path).ok, "mixed subtree saves")
	var opened: DrawingResult = DrawingFileIO.open(path)
	check(opened.ok and int((opened.value as DrawingDocument).read_pixel(first, -STRIDE + 1, STRIDE + 2).value) == 0x00112233, "Save/Open preserves signed hidden RGB")
	DirAccess.remove_absolute(path)
	# Reject descriptor batches without consuming revision, source or history.
	var bytes: PackedByteArray = tile.to_rgba8()
	var one: Dictionary = {"layer": "a", "tile_x": -1, "tile_y": 2, "bytes": bytes}
	var two: Dictionary = {"layer": "b", "tile_x": -1, "tile_y": 2, "bytes": bytes}
	var ids: PackedStringArray = PackedStringArray(["a", "b"])
	var malformed: Array[Dictionary] = [one, {"layer": "b", "tile_x": 0, "tile_y": 0, "bytes": PackedByteArray([1])}]
	var duplicate: Array[Dictionary] = [one, one]
	var good: Array[Dictionary] = [one, two]
	before = target.revision
	prior = store.call("stats")
	check(not bool(store.call("publish_subtree_revision", before, ids, malformed)), "late malformed bytes fail atomically")
	check(not bool(store.call("publish_subtree_revision", before, ids, duplicate)), "duplicate tile identity rejected")
	check(not bool(store.call("publish_subtree_revision", before, PackedStringArray(["a"]), good)), "unknown layer descriptor rejected")
	check(not bool(store.call("publish_subtree_revision", before, PackedStringArray(["a", "a"]), good)), "duplicate layer identity rejected")
	check(not bool(store.call("publish_subtree_revision", before - 1, ids, good)), "stale revision rejected")
	check(not bool(store.call("publish_subtree_revision", before, PackedStringArray([first, "a"]), [one] as Array[Dictionary])), "live ownership cannot be overwritten")
	var after: Dictionary = store.call("stats")
	check(int(after.get("revision")) == before and int(after.get("tiles")) == int(prior.get("tiles")) and int(after.get("undo")) == int(prior.get("undo")) and not bool(store.call("has_source", "a", -1, 2, before)), "all rejected batches leave native state untouched")
	var isolated: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(bool(isolated.call("configure", STRIDE, 0)) and bool(isolated.call("publish_subtree_revision", 0, ids, good)), "same signed tile coordinates in different layers accepted atomically")
	check(bool(isolated.call("has_source", "a", -1, 2, 1)) and bool(isolated.call("has_source", "b", -1, 2, 1)), "both distinct namespaces owned")
	var pending: DrawingEditSession = target.begin_edit(ink, target.revision).value
	before = target.revision
	check(not target.import_subtree(snapshot, "root").ok and target.revision == before, "pending detached edit rejects import")
	pending.cancel()
	var wrong_stride: DrawingDocument = DrawingDocument.new("different-stride", 32)
	check(not wrong_stride.import_subtree(snapshot, "root", true).ok and wrong_stride.layer_count() == 0, "mismatched tile stride rejects before publication")
	finish()


func finish() -> void:
	print("T314_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T314_NATIVE_SUBTREE_PASSED")
	quit(0 if failures == 0 else 1)
