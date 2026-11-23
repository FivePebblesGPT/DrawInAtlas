extends SceneTree
## T-243: an in-flight Rust edit reserves the document's history owner.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T243_ACTIVE_OWNER_FAILED: " + label)


func fixture(label: String, host: bool) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	check(not layer.is_empty(), "raster layer available: " + label)
	if host:
		check(doc.set_external_history(true).ok, "host claimed pristine timeline")
	var store: Object = doc._native_store_for_edit(doc.revision)
	check(store != null and bool(store.call("set_layer_editable", layer, true)),
		"native tile store configured")
	return {"doc": doc, "layer": layer, "store": store}


func test_active_handoff(host: bool) -> void:
	var pair: Dictionary = fixture("t243-host" if host else "t243-local", host)
	var doc: DrawingDocument = pair.doc
	var store: Object = pair.store
	var layer: String = pair.layer
	var started: Dictionary = store.call("begin_edit", layer, doc.revision, false)
	var transaction: int = int(started.get("transaction", 0))
	check(bool(started.get("ok", false)) and transaction > 0,
		"native edit opened before history handoff")
	check(store.has_method("has_active_edit") and bool(store.call("has_active_edit")),
		"native read-only probe reports pending transaction")
	var old_revision: int = doc.revision
	var old_stats: Dictionary = store.call("stats")
	var blocked: DrawingResult = doc.set_external_history(not host)
	check(not blocked.ok and blocked.code == "HISTORY_OWNED",
		"pending edit rejects change of history owner")
	check(doc.external_history == host and doc.history_length() == 0,
		"failed mode transfer preserves owner and local cursor")
	check(doc._native_raster_store == store and doc.revision == old_revision
		and store.call("stats") == old_stats,
		"rejected mode handoff preserves native source, counters and revision")
	check(doc.set_external_history(host).ok and doc.external_history == host,
		"idempotent owner selection is safe during pending edit")
	check(store.has_method("has_active_edit") and bool(store.call("has_active_edit")),
		"read-only probe does not cancel edit")
	check(bool(store.call("discard_edit", transaction)), "cancel pending transaction")
	check(store.has_method("has_active_edit") and not bool(store.call("has_active_edit")),
		"cancel clears native activity")
	check(doc.set_external_history(not host).ok and doc.external_history != host,
		"pristine mode transfer succeeds after cancellation")
	check(doc.set_external_history(host).ok and doc.external_history == host,
		"pristine owner can be restored before publication")
	var edit: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"-1,0": 0}, {"-1,0": HIDDEN})
	check(edit.ok and doc._native_raster_store == store,
		"real edit uses preserved native store after cancellation")
	check(int(doc.read_pixel(layer, -1, 0).value) == HIDDEN,
		"exact hidden RGB is published")
	if host:
		check(doc.history_length() == 0 and doc.replay_delta(edit.delta.detached_copy(), true).ok,
			"external owner can undo native delta")
		check(doc.replay_delta(edit.delta.detached_copy(), false).ok,
			"external owner can redo native delta")
	else:
		check(doc.history_length() == 1 and doc.undo().ok,
			"local owner can undo native edit")
		check(doc.redo().ok, "local owner can redo native edit")
	check(int(doc.read_pixel(layer, -1, 0).value) == HIDDEN,
		"ownership transition never corrupts native RGBA8")
	check(not doc.set_external_history(not host).ok,
		"recorded command prevents ownership migration after commit")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native tile ABI is installed")
	test_active_handoff(false)
	test_active_handoff(true)
	if failures == 0:
		print("T243_ACTIVE_OWNER_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T243_ACTIVE_OWNER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
