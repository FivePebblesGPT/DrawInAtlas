extends SceneTree
## Host-owned command timelines cannot silently turn into local histories after edits.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const PAINT: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T241_HOST_OWNER_FAILED: " + label)


func fixture(label: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	check(doc.set_external_history(true).ok and doc.external_history,
		"new document transfers history authority to host")
	return {"document": doc, "layer": layer}


func test_host_native_timeline() -> void:
	var pair: Dictionary = fixture("t241-native-host")
	var doc: DrawingDocument = pair.document
	var layer: String = pair.layer
	var first: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"-1,4": 0}, {"-1,4": HIDDEN})
	var second: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"64,0": 0}, {"64,0": PAINT})
	check(first.ok and second.ok, "host records two valid native raster commands")
	check(doc.history_length() == 0 and doc._native_raster_store != null,
		"host events live outside the local timeline while Rust owns pixels")
	var store: Object = doc._native_raster_store
	var revision_before: int = doc.revision
	var native_before: Dictionary = store.call("stats")
	var refused: DrawingResult = doc.set_external_history(false)
	check(not refused.ok and refused.code == "HISTORY_OWNED" and doc.external_history,
		"mode handoff refuses to discard live host-owned commands")
	check(doc.revision == revision_before and doc._native_raster_store == store and
		store.call("stats") == native_before,
		"refused handoff preserves native owner, revision and history stacks")
	check(int(doc.read_pixel(layer, -1, 4).value) == HIDDEN and
		int(doc.read_pixel(layer, 64, 0).value) == PAINT,
		"refused handoff preserves signed RGBA8 including hidden RGB")
	check(doc.set_external_history(true).ok and doc.external_history,
		"repeated enable is idempotent")
	check(not doc.set_external_history(false).ok and doc.external_history,
		"repeated enable cannot reset the ownership boundary")
	check(doc.replay_delta(second.delta.detached_copy(), true).ok and
		int(doc.read_pixel(layer, 64, 0).value) == 0,
		"host Undo retains exact native replay")
	check(doc.replay_delta(first.delta.detached_copy(), true).ok and
		int(doc.read_pixel(layer, -1, 4).value) == 0,
		"host can undo all content without releasing timeline ownership")
	check(not doc.set_external_history(false).ok and doc.external_history,
		"returning pixels to the original value does not reset ownership")
	check(doc.replay_delta(first.delta.detached_copy(), false).ok and
		doc.replay_delta(second.delta.detached_copy(), false).ok and
		int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"host native Redo remains functional after refused handoff")
	check(doc.history_length() == 0 and doc.external_history,
		"no local timeline accidentally appears after host replay")


func test_untracked_and_semantic() -> void:
	var pair: Dictionary = fixture("t241-untracked")
	var doc: DrawingDocument = pair.document
	check(doc._publish_edit(pair.layer, doc.revision,
		{"0,0": 0}, {"0,0": HIDDEN}, false).ok,
		"host mode permits deliberate untracked raster publication")
	check(not doc.set_external_history(false).ok and doc.external_history,
		"untracked host changes also prevent unsafe ownership transfer")
	var structural: Dictionary = fixture("t241-structure")
	var tree: DrawingDocument = structural.document
	var created: DrawingResult = tree.create_layer(DrawingLayerNode.GROUP,
		"Group", "root", "new-group", -1, true)
	check(created.ok and tree.history_length() == 0,
		"host owns recorded semantic-only structural commands")
	check(not tree.set_external_history(false).ok and tree.external_history,
		"semantic-only host command cannot silently become a local timeline")
	check(tree.has_node("new-group") and tree.revision > 0,
		"refused semantic handoff preserves layer tree")


func test_safe_mode_selection() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t241-pristine", STRIDE)
	check(doc.set_external_history(true).ok and doc.external_history,
		"pristine document accepts host owner")
	check(doc.set_external_history(false).ok and not doc.external_history,
		"unchanged document can return to local owner")
	check(doc.set_external_history(true).ok and doc.external_history,
		"pristine owner selection can be repeated safely")
	var invalid: DrawingResult = doc.create_layer("bad-kind", "Invalid")
	check(not invalid.ok, "invalid operation is rejected")
	check(doc.set_external_history(false).ok and not doc.external_history,
		"rejected operation does not consume ownership window")
	var local_layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc._publish_edit(local_layer, doc.revision,
		{"0,0": 0}, {"0,0": PAINT}).ok and doc.history_length() == 1,
		"local mode records its own native history")
	check(not doc.set_external_history(true).ok and not doc.external_history,
		"existing local commands still block transfer to host")
	check(doc.undo().ok and doc.redo().ok and
		int(doc.read_pixel(local_layer, 0, 0).value) == PAINT,
		"refused local-to-host transfer keeps local history functional")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension available")
	test_host_native_timeline()
	test_untracked_and_semantic()
	test_safe_mode_selection()
	if failures == 0:
		print("T241_HOST_OWNER_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T241_HOST_OWNER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
