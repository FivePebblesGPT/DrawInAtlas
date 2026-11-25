extends SceneTree
## Undo a created raster after undoing its pixels, without forfeiting native Redo.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const PAINT: int = 0xff663399
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T321_FAILED: " + label)


func fixture() -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t321", STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Other", "root", "other").ok,
		"create unrelated layer")
	check(doc._publish_edit("other", doc.revision, {"1,1": 0}, {"1,1": PAINT}).ok,
		"commit unrelated native history")
	check(doc.create_layer(DrawingLayerNode.RASTER, "New", "root", "new", -1, true).ok,
		"record raster creation")
	check(doc._publish_edit("new", doc.revision,
		{"-1,1": 0, "0,1": 0}, {"-1,1": HIDDEN, "0,1": PAINT}).ok,
		"record signed native edit")
	return doc


func test_cycle() -> void:
	var doc: DrawingDocument = fixture()
	var store: Object = doc._native_raster_store
	var token: int = (doc._events[2]["delta"] as DrawingDelta).native_history_token
	var old_token: int = (doc._events[0]["delta"] as DrawingDelta).native_history_token
	check(doc.undo().ok and doc._nodes["new"].tiles.is_empty(), "Undo pixels leaves blank authorized tiles")
	var rev: int = doc.revision
	var undone: DrawingResult = doc.undo()
	check(undone.ok and not doc.has_node("new") and doc.revision == rev + 1,
		"Undo creation removes the now-empty raster")
	check(bool(store.call("is_layer_parked", "new")) and
		bool(store.call("has_retained_history_token", token)) and
		bool(store.call("has_retained_history_token", old_token)), "park and preserve both native tokens")
	if not undone.ok:
		return
	check(doc.undo().ok and int(doc.read_pixel("other", 1, 1).value) == 0,
		"Undo earlier unrelated edit")
	check(doc.redo().ok and int(doc.read_pixel("other", 1, 1).value) == PAINT,
		"Redo unrelated edit")
	check(doc.redo().ok and doc.has_node("new") and doc._nodes["new"].tiles.is_empty() and
		not bool(store.call("is_layer_parked", "new")), "Redo creation restores an empty raster")
	check(bool(store.call("has_history_token", token, doc.revision, false)), "paint Redo is still native")
	check(doc.redo().ok and int(doc.read_pixel("new", -1, 1).value) == HIDDEN and
		int(doc.read_pixel("new", 0, 1).value) == PAINT, "Redo paint restores exact signed RGBA8")
	check(doc._native_raster_store == store and doc._native_save_projection_matches(), "one canonical owner throughout")
	var path: String = ProjectSettings.globalize_path("user://t321-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok, "save restored raster")
	var loaded: DrawingResult = DrawingFileIO.open(path)
	check(loaded.ok and int((loaded.value as DrawingDocument).read_pixel("new", -1, 1).value) == HIDDEN and
		int((loaded.value as DrawingDocument).read_pixel("new", 0, 1).value) == PAINT,
		"reopened binary source preserves signed hidden RGB")
	DirAccess.remove_absolute(path)
	check(doc.undo().ok and doc.undo().ok and doc.redo().ok and doc.redo().ok,
		"repeat structural cycle")


func test_untracked_nonempty() -> void:
	var doc: DrawingDocument = DrawingDocument.new("nonempty", STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER, "New", "root", "new", -1, true).ok, "create recorded layer")
	var tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	tile.set_rgba(1, 1, HIDDEN)
	doc._nodes["new"].tiles["0,0"] = tile
	var rev: int = doc.revision
	check(not doc.undo().ok and doc.revision == rev and doc.has_node("new") and
		doc.history_position() == 1 and int(doc.read_pixel("new", 1, 1).value) == HIDDEN,
		"untracked hidden RGB must not disappear on creation Undo")


func test_rejections() -> void:
	var doc: DrawingDocument = fixture()
	var store: Object = doc._native_raster_store
	check(doc.undo().ok, "prepare empty native source")
	var rev: int = doc.revision
	var cursor: int = doc.history_position()
	var token: int = (doc._events[cursor]["delta"] as DrawingDelta).native_history_token
	var held: DrawingResult = doc.begin_edit("other", rev)
	check(held.ok and not doc.undo().ok and doc.revision == rev and doc.history_position() == cursor,
		"open script edit blocks creation history")
	(held.value as DrawingEditSession).cancel()
	var active: Dictionary = store.call("begin_edit", "other", rev, false)
	check(bool(active.get("ok", false)) and not doc.undo().ok and doc.revision == rev,
		"native edit blocks creation history")
	check(bool(store.call("discard_edit", int(active.get("transaction", 0)))), "release native edit")
	var source: String = "new:-1,0"
	doc._native_source_identities.erase(source)
	check(not doc.undo().ok and doc.revision == rev and doc.has_node("new") and
		bool(store.call("has_history_token", token, rev, false)), "omitted canonical blank authorization rejects")
	doc._native_source_identities[source] = null
	doc._nodes["new"].name = "Diverged"
	check(not doc.undo().ok and doc.revision == rev, "untracked metadata divergence rejects")
	doc._nodes["new"].name = "New"
	var snapshot: DrawingLayerNode = doc._events[cursor - 1]["node"]
	snapshot.kind = DrawingLayerNode.GROUP
	check(not doc.undo().ok and doc.revision == rev, "changed snapshot kind cannot bypass raster fence")
	snapshot.kind = DrawingLayerNode.RASTER
	check(doc.undo().ok, "Undo creation retries after restoring authority")
	var parked_revision: int = doc.revision
	check(bool(store.call("advance_metadata_revision", parked_revision, false)), "inject stale native owner")
	check(not doc.redo().ok and not doc.has_node("new") and doc.revision == parked_revision and
		bool(store.call("is_layer_parked", "new")), "stale native revision rejects creation Redo atomically")


func test_branch_cleanup(selection_branch: bool) -> void:
	var doc: DrawingDocument = fixture()
	var store: Object = doc._native_raster_store
	var token: int = (doc._events[2]["delta"] as DrawingDelta).native_history_token
	var other_token: int = (doc._events[0]["delta"] as DrawingDelta).native_history_token
	check(doc.undo().ok and doc.undo().ok, "park creation before branching")
	if not bool(store.call("is_layer_parked", "new")):
		return
	var rev: int = doc.revision
	if selection_branch:
		doc.record_selection_history = true
		var active: Dictionary = store.call("begin_edit", "other", rev, false)
		check(bool(active.get("ok", false)), "unrelated native edit held during selection branch")
		var before: DrawingHistoryContext = DrawingHistoryContext.new()
		var after: DrawingHistoryContext = DrawingHistoryContext.new()
		after.selected_layer_ids.append("other")
		check(doc.record_selection_change(before, after) and doc.revision == rev,
			"selection branch abandons creation without content revision")
		check(bool(store.call("discard_edit", int(active.get("transaction", 0)))),
			"branch reclamation preserves unrelated pending transaction")
	else:
		check(doc.rename_layer("other", "Renamed", true).ok and doc.revision == rev + 1,
			"metadata branch abandons creation")
	check(not doc.can_redo() and not bool(store.call("is_layer_parked", "new")) and
		not bool(store.call("has_source", "new", -1, 0, doc.revision)) and
		not doc._native_source_identities.has("new:-1,0"), "abandoned creation releases reserved blank sources")
	check(not bool(store.call("has_retained_history_token", token)) and
		bool(store.call("has_retained_history_token", other_token)), "discard only the abandoned native event")
	check(doc.create_layer(DrawingLayerNode.RASTER, "Reused", "root", "new", -1, true).ok,
		"abandoned ID can be reused after branching")


func test_pending_and_detached() -> void:
	var doc: DrawingDocument = DrawingDocument.new("pending", STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER, "New", "root", "new", -1, true).ok, "create pending fixture")
	doc._pending_tiles["new:0,0"] = {"ref": "unresolved"}
	var rev: int = doc.revision
	check(not doc.undo().ok and doc.revision == rev and doc.has_node("new") and
		doc._pending_tiles.has("new:0,0"), "unresolved source cannot disappear")
	doc._pending_tiles.clear()
	doc._known_refs["new:0,0"] = {"ref": "orphan"}
	check(not doc.undo().ok and doc.revision == rev, "physical source reference cannot disappear")
	doc._known_refs.clear()
	check(doc.undo().ok and doc.redo().ok, "never-imported creation replays without native owner")
	var detached: DrawingDocument = fixture()
	check(detached.undo().ok and detached.undo().ok, "park before owner detachment")
	detached._native_raster_store = null
	detached._native_source_identities.clear()
	check(detached.redo().ok and detached.has_node("new") and detached._nodes["new"].tiles.is_empty(),
		"detached empty creation restores without inventing source pixels")
	check(detached.redo().ok and detached._native_raster_store != null and
		int(detached.read_pixel("new", -1, 1).value) == HIDDEN and detached._native_save_projection_matches(),
		"detached subsequent paint Redo reacquires native authority")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension available")
	test_cycle()
	test_untracked_nonempty()
	test_rejections()
	test_branch_cleanup(false)
	test_branch_cleanup(true)
	test_pending_and_detached()
	print("T321_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T321_RASTER_CREATION_HISTORY_PASSED")
	quit(0 if failures == 0 else 1)
