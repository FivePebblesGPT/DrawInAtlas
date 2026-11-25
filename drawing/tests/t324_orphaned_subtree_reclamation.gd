extends SceneTree
## Permanent ancestor removal must not strand applied child-removal history.

var checks: int = 0
var failures: int = 0
var fetches: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T324_FAILED: " + label)

func paint(doc: DrawingDocument, layer: String, x: int, value: int) -> int:
	var key: String = "%d,0" % x
	if not doc._publish_edit(layer, doc.revision, {key: 0}, {key: value}).ok:
		return 0
	return (doc._events.back()["delta"] as DrawingDelta).native_history_token

func fixture(with_live_raster: bool) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t324", 64)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Keep", "root", "keep").ok, "keep")
	check(doc.create_layer(DrawingLayerNode.GROUP, "Outer", "root", "outer").ok, "outer")
	check(doc.create_layer(DrawingLayerNode.GROUP, "Inner", "outer", "inner").ok, "inner")
	check(doc.create_layer(DrawingLayerNode.RASTER, "Victim", "inner", "victim").ok, "victim")
	if with_live_raster:
		check(doc.create_layer(DrawingLayerNode.RASTER, "Live", "outer", "live").ok, "live raster")
	check(paint(doc, "keep", 1, 0xff123456) > 0, "keep paint")
	check(paint(doc, "victim", -65, 0x00123456) > 0, "hidden RGB paint")
	if with_live_raster:
		check(paint(doc, "live", 1, 0xff223344) > 0, "live paint")
	check(doc.remove_subtree("victim", true).ok, "record victim removal")
	check(doc.remove_subtree("inner", true).ok, "record inner removal")
	return doc

func retire(with_live_raster: bool) -> void:
	var doc: DrawingDocument = fixture(with_live_raster)
	var store: Object = doc._native_raster_store
	var keep_token: int = (doc._events[0]["delta"] as DrawingDelta).native_history_token
	var victim_token: int = (doc._events[1]["delta"] as DrawingDelta).native_history_token
	var before: int = doc.revision
	var bytes_before: int = int(store.call("stats")["bytes_used"])
	check(bool(store.call("is_layer_parked", "victim")), "victim parked")
	check(doc.remove_subtree("outer").ok, "permanent ancestor removal")
	check(doc.revision == before + 1 and int(store.call("stats")["revision"]) == doc.revision, "single revision")
	check(not bool(store.call("is_layer_parked", "victim")), "victim reservation reclaimed")
	check(not bool(store.call("has_retained_history_token", victim_token)), "orphan paint token reclaimed")
	check(int(store.call("stats")["bytes_used"]) < bytes_before, "resident bytes reclaimed")
	check(not doc._native_source_identities.has("victim:-2,0"), "parked identity reclaimed")
	check(bool(store.call("has_retained_history_token", keep_token)), "keep token retained")
	check(doc.history_length() == 1 and doc.history_position() == 1, "only reachable command retained")
	check(doc.undo().ok and int(doc.read_pixel("keep", 1, 0).value) == 0, "surviving Undo")
	check(doc.redo().ok and int(doc.read_pixel("keep", 1, 0).value) == 0xff123456, "surviving Redo")
	check(doc.create_layer(DrawingLayerNode.RASTER, "Fresh", "root", "victim").ok, "retired ID reusable")
	var fresh: DrawingResult = doc.read_pixel("victim", -65, 0)
	check(fresh.ok and int(fresh.value) == 0, "no old pigment")
	check(doc.snapshot_for_save().ok, "save clean canonical projection")

func rejection_and_recorded_replay() -> void:
	var doc: DrawingDocument = fixture(true)
	var store: Object = doc._native_raster_store
	var rev: int = doc.revision
	var size: int = int(store.call("stats")["bytes_used"])
	var history: int = doc.history_length()
	var bad: Array[Dictionary] = [{"layer": "victim", "count": 1}, {"layer": "live", "count": 1}]
	check(not bool(store.call("retire_orphaned_layers_revision", rev, PackedStringArray(), bad)), "native batch rejects live second descriptor")
	bad = [{"layer": "victim", "count": 0}]
	check(not bool(store.call("retire_orphaned_layers_revision", rev, PackedStringArray(["live"]), bad)), "incomplete parked cardinality rejects whole batch")
	bad = [{"layer": "victim", "count": 1}]
	check(not bool(store.call("retire_orphaned_layers_revision", rev - 1, PackedStringArray(["live"]), bad)), "stale revision rejects")
	check(not bool(store.call("retire_orphaned_layers_revision", rev, PackedStringArray(["victim"]), bad)), "overlapping live and parked IDs reject")
	var active: Dictionary = store.call("begin_edit", "keep", rev, false)
	check(bool(active.get("ok", false)), "unrelated active edit")
	check(not doc.remove_subtree("outer").ok, "permanent removal rejects pending edit")
	check(bool(store.call("discard_edit", int(active["transaction"]))), "pending edit retained")
	var snapshot: DrawingLayerNode = doc._events[history - 2]["nodes"]["victim"]
	var tile: DrawingRasterTile = snapshot.tiles["-2,0"]
	var old: int = tile.get_rgba(63, 0)
	tile.set_rgba(63, 0, old ^ 0x00010000)
	check(not doc.remove_subtree("outer").ok, "changed hidden RGB fails closed")
	check(doc.revision == rev and doc.history_length() == history and doc.history_position() == history and doc.has_node("outer") and doc.has_node("live"), "no partial document retirement")
	check(int(store.call("stats")["bytes_used"]) == size and bool(store.call("is_layer_parked", "victim")), "native memory and park intact")
	tile.set_rgba(63, 0, old)
	check(doc.remove_subtree("outer", true).ok, "recorded ancestor deletion remains reversible")
	check(bool(store.call("is_layer_parked", "victim")) and bool(store.call("is_layer_parked", "live")), "both retained removals parked")
	check(doc.undo().ok and doc.undo().ok and doc.undo().ok, "restore all nested removals")
	check(int(doc.read_pixel("victim", -65, 0).value) == 0x00123456, "restored exact hidden RGB")
	check(doc.redo().ok and doc.redo().ok and doc.redo().ok, "redo nested removals")
	check(doc.undo().ok and doc.remove_subtree("outer").ok, "permanent retirement after ancestor Undo")
	check(not doc.can_redo() and doc.history_length() == 1 and not bool(store.call("is_layer_parked", "victim")), "abandoned ancestor redo pruned")

func abandon_unrelated_redo() -> void:
	var doc: DrawingDocument = fixture(false)
	var store: Object = doc._native_raster_store
	check(doc.create_layer(DrawingLayerNode.RASTER, "Redo", "root", "redo", -1, true).ok, "future layer created")
	var token: int = paint(doc, "redo", 2, 0xff123456)
	check(token > 0 and doc.undo().ok and doc.undo().ok, "park unrelated future creation")
	check(bool(store.call("is_layer_parked", "redo")), "redo source parked")
	check(doc.remove_subtree("outer").ok, "retire applied orphan and abandon redo")
	check(not bool(store.call("is_layer_parked", "redo")) and not bool(store.call("has_retained_history_token", token)), "future creation reservation reclaimed")
	check(doc.history_length() == 1 and not doc.can_redo(), "only surviving applied paint remains")

func fetch(_ref: String) -> PackedByteArray:
	fetches += 1
	return PackedByteArray()

func pending_sources() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t324-pending", 64)
	check(doc.create_layer(DrawingLayerNode.GROUP, "Outer", "root", "outer").ok, "pending parent")
	check(doc.create_layer(DrawingLayerNode.RASTER, "Victim", "outer", "victim").ok, "pending raster")
	check(paint(doc, "victim", -65, 0x00123456) > 0, "native source next to pending")
	var blank: DrawingRasterTile = DrawingRasterTile.new(64)
	var digest: String = DrawingRasterTile.digest_rgba8(blank.to_rgba8(), 64)
	check(doc.register_lazy_chunk("victim", 3, -4, digest, digest, fetch).ok, "unresolved source registered")
	check(doc.remove_subtree("victim", true).ok, "record mixed resident and pending removal")
	check(doc.remove_subtree("outer").ok and fetches == 0, "permanent retirement never invokes lazy fetch")
	check(doc.history_length() == 0 and not bool(doc._native_raster_store.call("is_layer_parked", "victim")), "mixed orphan history and reservation cleared")
	check(doc.snapshot_for_save().ok, "save after dropping pending subtree")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension")
	retire(false)
	retire(true)
	rejection_and_recorded_replay()
	abandon_unrelated_redo()
	pending_sources()
	print("T324 checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T324_ORPHANED_SUBTREE_RECLAMATION_PASSED")
	quit(1 if failures else 0)
