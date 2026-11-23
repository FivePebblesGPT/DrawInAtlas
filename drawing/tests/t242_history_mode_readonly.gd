extends SceneTree
## T-242: host/local history ownership must be changed only through the checked API.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const PAINT: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T242_HISTORY_MODE_FAILED: " + label)


func new_document(name: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(name, STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	return {"document": doc, "layer": layer}


func test_host_owner_cannot_be_bypassed() -> void:
	var pair: Dictionary = new_document("t242-host")
	var doc: DrawingDocument = pair.document
	var layer: String = pair.layer
	check(doc.set_external_history(true).ok and doc.external_history,
		"explicit checked handoff enables host ownership")
	var first: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"-1,4": 0}, {"-1,4": HIDDEN})
	var second: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"64,0": 0}, {"64,0": PAINT})
	check(first.ok and second.ok and doc._native_raster_store != null,
		"host records two native raster commands")
	var store: Object = doc._native_raster_store
	var before: Dictionary = store.call("stats")
	var revision_before: int = doc.revision
	check(not doc.set_external_history(false).ok and doc.external_history,
		"checked API refuses a host-to-local takeover")
	# This was possible before T-242: a public variable bypassed that API.
	doc.external_history = false
	check(doc.external_history, "direct property write cannot disable host history")
	doc.set("external_history", false)
	check(doc.external_history, "Object.set cannot disable host history")
	doc.set_indexed(NodePath("external_history"), false)
	check(doc.external_history, "indexed reflection cannot disable host history")
	check(doc.revision == revision_before and store.call("stats") == before and
		doc._native_raster_store == store and doc.history_length() == 0,
		"rejected property writes preserve native history tokens and revision")
	check(int(doc.read_pixel(layer, -1, 4).value) == HIDDEN and
		int(doc.read_pixel(layer, 64, 0).value) == PAINT,
		"rejected property writes preserve hidden RGB and painted pixels")
	check(doc.replay_delta(second.delta.detached_copy(), true).ok and
		doc.replay_delta(first.delta.detached_copy(), true).ok,
		"host can undo both native entries after attempted takeover")
	check(doc.replay_delta(first.delta.detached_copy(), false).ok and
		doc.replay_delta(second.delta.detached_copy(), false).ok,
		"host can redo both native entries after attempted takeover")
	check(doc.external_history and doc.history_length() == 0,
		"host command replay never creates local history")


func test_local_owner_cannot_be_bypassed() -> void:
	var pair: Dictionary = new_document("t242-local")
	var doc: DrawingDocument = pair.document
	var layer: String = pair.layer
	check(not doc.external_history, "new document defaults to local history")
	var edit: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"0,0": 0}, {"0,0": HIDDEN})
	check(edit.ok and doc.history_length() == 1 and doc._native_raster_store != null,
		"local document holds a native content entry")
	check(not doc.set_external_history(true).ok and not doc.external_history,
		"checked API refuses a local-to-host takeover")
	doc.external_history = true
	check(not doc.external_history, "direct property write cannot enable host history")
	doc.set("external_history", true)
	check(not doc.external_history, "Object.set cannot enable host history")
	doc.set_indexed(NodePath("external_history"), true)
	check(not doc.external_history, "indexed reflection cannot enable host history")
	check(doc.history_length() == 1 and doc.can_undo() and
		int(doc.read_pixel(layer, 0, 0).value) == HIDDEN,
		"local history remains available with exact pixels")
	check(doc.undo().ok and doc.redo().ok and
		int(doc.read_pixel(layer, 0, 0).value) == HIDDEN,
		"local native Undo/Redo survives attempted takeover")


func test_checked_preedit_transitions() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t242-pristine", STRIDE)
	doc.external_history = true
	check(not doc.external_history, "direct write cannot opt into host mode even before edits")
	check(doc.set_external_history(true).ok and doc.external_history,
		"explicit mode API permits pristine host selection")
	check(doc.set_external_history(false).ok and not doc.external_history,
		"explicit mode API permits pristine local selection")
	check(doc.set_external_history(true).ok and doc.external_history,
		"legitimate repeated pre-edit handoffs still work")
	check(doc.set_external_history(true).ok and doc.external_history,
		"idempotent host selection stays valid")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension available")
	test_host_owner_cannot_be_bypassed()
	test_local_owner_cannot_be_bypassed()
	test_checked_preedit_transitions()
	if failures == 0:
		print("T242_HISTORY_MODE_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T242_HISTORY_MODE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
