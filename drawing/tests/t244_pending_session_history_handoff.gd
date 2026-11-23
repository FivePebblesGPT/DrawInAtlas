extends SceneTree
## A pending, Godot-staged edit must reserve its command owner before native attachment.

const HIDDEN: int = 0x00335577
const VISIBLE: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T244_PENDING_SESSION_FAILED: " + label)


func fixture(label: String, host: bool) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	check(not layer.is_empty(), "raster layer created")
	if host:
		check(doc.set_external_history(true).ok, "host owns initial timeline")
	return {"doc": doc, "layer": layer}


func test_pending_commit(host: bool) -> void:
	var pair: Dictionary = fixture("t244-commit-host" if host else "t244-commit-local", host)
	var doc: DrawingDocument = pair.doc
	var layer: String = pair.layer
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "standalone edit session opened")
	var session: DrawingEditSession = opened.value
	check(doc._native_raster_store == null and session.change_count() == 0,
		"session exists before native store and pixel staging")
	var tried: DrawingResult = doc.set_external_history(not host)
	check(not tried.ok and tried.code == "HISTORY_OWNED" and doc.external_history == host,
		"pending, unpainted session prevents changing command owner")
	check(session.fill_rect(Rect2i(-1, 4, 2, 1), HIDDEN).ok,
		"staged edit can paint signed transparent hidden RGB")
	check(doc._native_raster_store == null and doc.revision == opened.revision,
		"staging still has no native attachment or committed document revision")
	check(not doc.set_external_history(not host).ok,
		"staged pixel edit prevents changing command owner")
	check(doc.set_external_history(host).ok and doc.external_history == host,
		"idempotent owner selection is allowed")
	var committed: DrawingResult = session.commit()
	check(committed.ok and doc._native_raster_store != null and
		int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"committed session establishes native owner and exact signed bytes")
	if host:
		check(doc.history_length() == 0 and committed.delta.native_history_token > 0,
			"host-only command receives reversible native token")
		check(doc.replay_delta(committed.delta.detached_copy(), true).ok and
			doc.replay_delta(committed.delta.detached_copy(), false).ok,
			"host Undo/Redo retains exact raster")
	else:
		check(doc.history_length() == 1 and doc.undo().ok and doc.redo().ok,
			"local Undo/Redo retains exact raster")
	check(int(doc.read_pixel(layer, -1, 4).value) == HIDDEN and
		not doc.set_external_history(not host).ok,
		"completed command preserves history ownership and hidden RGB")


func test_cancel_and_multiple_sessions() -> void:
	var pair: Dictionary = fixture("t244-multiple", false)
	var doc: DrawingDocument = pair.doc
	var layer: String = pair.layer
	var first: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var second: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(first != null and second != null, "independent sessions can coexist")
	first.cancel()
	check(first._closed and not doc.set_external_history(true).ok,
		"cancelled first session cannot release second session's reservation")
	check(second.fill_rect(Rect2i(0, 0, 1, 1), VISIBLE).ok,
		"second session can continue staging after first cancellation")
	second.cancel()
	check(second._closed and doc.set_external_history(true).ok,
		"cancelling the last live session unlocks pristine handoff")
	check(doc.set_external_history(false).ok, "pristine document can return to local owner")
	var empty: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var no_op: DrawingResult = empty.commit()
	check(not no_op.ok and no_op.code == "NO_CHANGE" and empty._closed and
		doc.set_external_history(true).ok,
		"a no-change commit closes its reservation without creating history")


func test_direct_session_constructor() -> void:
	var pair: Dictionary = fixture("t244-direct", false)
	var doc: DrawingDocument = pair.doc
	var direct: DrawingEditSession = DrawingEditSession.new(doc, pair.layer,
		doc.revision, Transform2D.IDENTITY, 0, 0)
	check(direct != null and not doc.set_external_history(true).ok,
		"direct EditSession constructor cannot bypass owner reservation")
	direct.cancel()
	check(doc.set_external_history(true).ok,
		"direct constructor releases owner reservation on cancel")


func test_dropped_session() -> void:
	var pair: Dictionary = fixture("t244-dropped", false)
	var doc: DrawingDocument = pair.doc
	var layer: String = pair.layer
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	var session: DrawingEditSession = started.value
	var weak: WeakRef = weakref(session)
	check(weak.get_ref() != null and not doc.set_external_history(true).ok,
		"live session reserves owner without any committed pixels")
	started = null
	session = null
	check(weak.get_ref() == null,
		"document tracks pending sessions weakly and does not retain abandoned edits")
	check(doc.set_external_history(true).ok,
		"released session no longer blocks a pristine ownership change")


func test_failed_commit_and_native_guard() -> void:
	var pair: Dictionary = fixture("t244-stale", false)
	var doc: DrawingDocument = pair.doc
	var layer: String = pair.layer
	var session: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(session.fill_rect(Rect2i(0, 0, 1, 1), VISIBLE).ok,
		"stale-session fixture stages one pixel")
	check(doc.rename_layer(layer, "Ink renamed").ok,
		"metadata advances revision without recording local history")
	var stale: DrawingResult = session.commit()
	check(not stale.ok and stale.code == "STALE_REVISION" and session._closed,
		"stale commit cancels and closes its pending owner reservation")
	check(doc.set_external_history(true).ok,
		"failed session no longer blocks a safe owner change")
	check(int(doc.read_pixel(layer, 0, 0).value) == 0,
		"failed commit has not published pixel")
	var store: Object = doc._native_store_for_edit(doc.revision)
	check(store != null and bool(store.call("set_layer_editable", layer, true)),
		"native store can be configured after stale session")
	var begin: Dictionary = store.call("begin_edit", layer, doc.revision, false)
	check(bool(begin.get("ok", false)), "native transaction begins")
	check(not doc.set_external_history(false).ok and doc.external_history,
		"native transaction guard remains effective without an open script session")
	check(bool(store.call("discard_edit", int(begin.get("transaction", 0)))),
		"native transaction cancels")
	check(doc.set_external_history(false).ok,
		"pristine host owner can transfer after native cancellation")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native tiles extension loaded")
	test_pending_commit(false)
	test_pending_commit(true)
	test_cancel_and_multiple_sessions()
	test_direct_session_constructor()
	test_dropped_session()
	test_failed_commit_and_native_guard()
	if failures == 0:
		print("T244_PENDING_SESSION_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T244_PENDING_SESSION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
