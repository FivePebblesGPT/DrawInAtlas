extends SceneTree
## File and Object Save As completions must belong to the tab that opened them.

var checks: int = 0
var failures: int = 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T132_DIALOG_FAILED: " + label)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func app_ready() -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.start_blank_document = false
	root.add_child(app)
	await frames(3)
	return app


func seed_document(doc: DrawingDocument, layer: String, color: int) -> void:
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(edit != null and edit._stage(2, 3, color).ok and edit.commit().ok,
		"seed distinct canonical pixel")


func pixel(doc: DrawingDocument) -> int:
	var rendered: DrawingResult = DrawingRenderer.render(doc, Rect2i(2, 3, 1, 1))
	check(rendered.ok, "single pixel renders")
	if not rendered.ok:
		return -1
	var bytes: PackedByteArray = (rendered.value as Image).get_data()
	return int(bytes[0]) | (int(bytes[1]) << 8) | (int(bytes[2]) << 16) | (int(bytes[3]) << 24)


func test_file_dialog(base: String) -> void:
	var app: Control = await app_ready()
	app.new_drawing()
	var a: DrawingDocument = app.current_document()
	seed_document(a, app.current_layer(), 0xff234567)
	app.new_drawing()
	var b: DrawingDocument = app.current_document()
	seed_document(b, app.current_layer(), 0xff765432)
	check(a != b and pixel(a) != pixel(b), "two tabs contain independent pixel content")
	var danger: String = base.path_join("existing.drawing")
	var sentinel: String = "EXTERNAL FILE MUST NOT BE OVERWRITTEN\n"
	var stream: FileAccess = FileAccess.open(danger, FileAccess.WRITE)
	check(stream != null, "sentinel target is writable")
	if stream != null:
		stream.store_string(sentinel)
		stream.close()
	app._activate(0)
	app._ask_save()
	app._activate(1)
	app.save_dialog.file_selected.emit(danger)
	check(FileAccess.get_file_as_string(danger) == sentinel,
		"stale FileDialog cannot overwrite prior document path with another tab")
	check(String(app.tabs[1]["path"]).is_empty(),
		"stale selection cannot bind a target path to the wrong tab")
	check(app.status.text.contains("document") or app.status.text.contains("tab"),
		"stale target rejection is visible")
	# A genuine Save As completion for the original tab should still work.
	app._activate(0)
	var good: String = base.path_join("saved-a.drawing")
	app._ask_save()
	app.save_dialog.file_selected.emit(good)
	var opened: DrawingResult = DrawingFileIO.open_with_frame(good)
	check(opened.ok, "current-tab Save As completes normally")
	if opened.ok:
		check(pixel(opened.value["document"] as DrawingDocument) == pixel(a),
			"saved file contains originating document RGBA8")
	check(String(app.tabs[0]["path"]) == good and String(app.tabs[1]["path"]).is_empty(),
		"only the originating tab acquires a saved path")
	# A dismissed file picker cannot authorize a later stale file_selected callback.
	app._ask_save()
	app.save_dialog.canceled.emit()
	app._activate(1)
	app.save_dialog.file_selected.emit(danger)
	check(FileAccess.get_file_as_string(danger) == sentinel,
		"cancellation invalidates a late FileDialog event")
	# The selected index may now designate an entirely different document.
	app._activate(0)
	app._ask_save()
	app._close_index(0)
	check(app.active_tab == 0 and app.current_document() == b,
		"closed originating tab is replaced by another at the same index")
	app.save_dialog.file_selected.emit(danger)
	check(FileAccess.get_file_as_string(danger) == sentinel,
		"reused tab index never authorizes saving an unrelated document")
	# Direct, already-authorized Save is not a file-dialog completion.
	var direct: String = base.path_join("direct-b.drawing")
	app._save_file(direct)
	var direct_opened: DrawingResult = DrawingFileIO.open_with_frame(direct)
	check(direct_opened.ok, "direct Save still accepts an explicit destination")
	if direct_opened.ok:
		check(pixel(direct_opened.value["document"] as DrawingDocument) == pixel(b),
			"direct Save keeps the intended active document's pixel identity")
	app.queue_free()
	await frames(2)


func test_local_object_file_dialog(base: String) -> void:
	var app: Control = await app_ready()
	app.new_object()
	var first: DrawingObjectEditorSession = app.current_object()
	app.new_object()
	var second: DrawingObjectEditorSession = app.current_object()
	var destination: String = base.path_join("unrelated-object.drawing")
	app._activate(0)
	app._ask_save()
	app._activate(1)
	app.save_dialog.file_selected.emit(destination)
	check(not FileAccess.file_exists(destination),
		"local Object file chooser cannot publish the wrong source")
	check(first.source_id.is_empty() and second.source_id.is_empty(),
		"rejected Object chooser does not bind either source identity")
	check(String(app.tabs[1].get("path", "")).is_empty(),
		"rejected Object chooser cannot rebind another tab's path")
	app._activate(0)
	app._ask_save()
	app.save_dialog.file_selected.emit(destination)
	var loaded: DrawingResult = DrawingObjectEditorFile.open(destination)
	check(loaded.ok, "correct local Object FileDialog still publishes a source")
	check(not first.source_id.is_empty() and second.source_id.is_empty(),
		"only the originating Object session receives a published source id")
	app.queue_free()
	await frames(2)


func test_object_variant_dialog() -> void:
	var app: Control = await app_ready()
	var first: DrawingObjectEditorSession = DrawingObjectEditorSession.new(
		DrawingDocument.new(), "a", 1, "Object A")
	var second: DrawingObjectEditorSession = DrawingObjectEditorSession.new(
		DrawingDocument.new(), "b", 1, "Object B")
	var calls: Dictionary = {"a": 0, "b": 0, "name": ""}
	first.save_as_publisher = func(draft: DrawingObjectEditorSession) -> DrawingResult:
		calls["a"] = int(calls["a"]) + 1
		calls["name"] = draft.variant_name
		return DrawingResult.failure("FIXTURE", "Intentional nonpublishing fixture")
	second.save_as_publisher = func(_draft: DrawingObjectEditorSession) -> DrawingResult:
		calls["b"] = int(calls["b"]) + 1
		return DrawingResult.failure("FIXTURE", "Intentional nonpublishing fixture")
	check(app.attach_object_session(first).ok and app.attach_object_session(second).ok,
		"two independent hosted Object tabs mount")
	app._activate(0)
	app._ask_save()
	app.variant_name.text = "Variant of Object A"
	app._activate(1)
	app.variant_dialog.confirmed.emit()
	check(int(calls["a"]) == 0 and int(calls["b"]) == 0,
		"stale named Save As cannot publish a different Object source")
	check(first.variant_name.is_empty() and second.variant_name.is_empty(),
		"rejected stale confirmation changes neither Object variant name")
	app._activate(0)
	app._ask_save()
	# A dismissed variant dialog must also drop close-after-save intent.
	app._closing_index = app.active_tab
	app._close_after_save = true
	app.variant_dialog.canceled.emit()
	check(app._closing_index == -1 and not app._close_after_save,
		"cancelled variant dialog clears stale save-and-close intent")
	app.variant_dialog.confirmed.emit()
	check(int(calls["a"]) == 0 and int(calls["b"]) == 0,
		"late confirmation of cancelled variant dialog cannot publish")
	app._ask_save()
	app.variant_name.text = "Variant of Object A"
	app.variant_dialog.confirmed.emit()
	check(int(calls["a"]) == 1 and int(calls["b"]) == 0 and
		calls["name"] == "Variant of Object A",
		"genuine named Save As invokes only the originating publisher")
	check(first.variant_name.is_empty(), "failed publisher rolls back staged metadata")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t132-dialog-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "fixture directory created")
	await test_file_dialog(base)
	await test_local_object_file_dialog(base)
	await test_object_variant_dialog()
	if failures == 0:
		print("T132_DIALOG_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T132_DIALOG_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
