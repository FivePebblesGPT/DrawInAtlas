extends SceneTree
## T-062: independent Drawing project has real Object Editor document tabs.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DRAWING_OBJECT_UI_FAILED: " + description)


func _run() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	root.add_child(app)
	await process_frame
	await process_frame
	_check(app.tabs.size() == 1 and app.current_object() == null,
		"independent Drawing starts with a regular drawing tab")
	app.new_object()
	var session: DrawingObjectEditorSession = app.current_object()
	_check(session != null and app.tabs.size() == 2 and session.origin_instance_id.is_empty(),
		"New Object opens a dedicated tab without Atlas binding")
	_check(app.current_document() == session.document and app.current_layer() != "",
		"Object tab uses the same canonical layer and canvas engine")
	var layer: String = app.current_layer()
	var edit: DrawingResult = session.document.begin_edit(layer, session.document.revision)
	_check(edit.ok, "Object layer supports ordinary raster editing")
	if edit.ok:
		var transaction: DrawingEditSession = edit.value
		_check(transaction.apply_region(Rect2i(-3, 7, 1, 1),
			PackedByteArray([12, 34, 56, 0])).ok and transaction.commit().ok,
			"exact hidden RGB can be authored in Object tab")
	_check(session.is_dirty() and app.tab_bar.get_tab_title(app.active_tab).contains("*"),
		"dirty draft displays modified marker")
	app._ask_object_frame()
	_check(app.frame_dialog.visible, "Object Editor has editable local origin and bounds UI")
	app.frame_dialog.hide()
	await process_frame
	var frame_values: Array[int] = [-12, 16, -30, -20, 64, 96]
	for index: int in range(frame_values.size()):
		app.frame_fields[index].value = frame_values[index]
	app._change_object_frame()
	_check(session.origin == Vector2i(-12, 16) and
		session.bounds == Rect2i(-30, -20, 64, 96) and
		app.canvas.asset_bounds == session.bounds,
		"frame UI controls update authoring guides without raster edits")
	app._change_tool("Text")
	app._edit_text_at(Vector2i(6, -4))
	app.text_dialog.hide()
	await process_frame
	app._edit_text_at(Vector2i(6, -4))
	app.text_edit.text = "Object label"
	app._commit_text_dialog()
	app.text_dialog.hide()
	await process_frame
	var text_id: String = app.current_layer()
	_check(session.document.inspect_node(text_id).text_element.content == "Object label",
		"Object tab reuses real editable Drawing text tool")
	app._rasterize_text()
	_check(session.document.inspect_node(text_id).kind == DrawingLayerNode.RASTER,
		"text rasterization is explicit in Object tab")
	app._undo()
	_check(session.document.inspect_node(text_id).kind == DrawingLayerNode.TEXT,
		"Object draft undo restores text editability")
	# T-089 tracks the selected Tree row separately from the paint target.
	# Switch through the workspace API rather than mutating one private field.
	app._select_layer_node(layer, false)
	var source_path: String = ProjectSettings.globalize_path("user://t062-source.drawing")
	app._save_file(source_path)
	_check(FileAccess.file_exists(source_path) and not session.is_dirty() and session.source_id != "",
		"independent Object source saved without Atlas library")
	_check(app.current_document().read_pixel(app.current_layer(), -3, 7).value == 0x0038220c and
		session.bounds == Rect2i(-30, -20, 64, 96),
		"source pixels and bounds remain exact after source publication")
	var stable_id: String = session.source_id
	app._open_object_file(source_path)
	_check(app.current_object() != null and app.current_object().source_id == stable_id and
		app.current_object().origin == Vector2i(-12, 16) and
		app.current_object().bounds == Rect2i(-30, -20, 64, 96),
		"Open Object source restores identity and signed frame")
	var copy_path: String = ProjectSettings.globalize_path("user://t062-copy.drawing")
	app._local_save_as = true
	app._save_file(copy_path)
	var copy: DrawingObjectEditorSession = app.current_object()
	_check(copy.source_id != stable_id and FileAccess.file_exists(copy_path) and
		copy.origin == Vector2i(-12, 16) and copy.bounds == Rect2i(-30, -20, 64, 96) and
		app.current_document().read_pixel(app.current_layer(), -3, 7).value == 0x0038220c,
		"standalone Save As deep-copies IDs but preserves bytes and frame")
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(copy_path))
	metadata["object_source"]["bounds"] = [0, 0, -1, 999]
	var tampered: String = ProjectSettings.globalize_path("user://t062-tampered.drawing")
	var file: FileAccess = FileAccess.open(tampered, FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata))
	file.close()
	_check(not DrawingObjectEditorFile.open(tampered).ok,
		"untrusted negative-size bounds are rejected while decoding a portable Object source")
	DirAccess.remove_absolute(tampered)
	app._open_object_file(source_path)
	_check(app.current_object().source_id == stable_id, "original source remains separately reopenable")
	app._request_close_current()
	_check(app.tabs.size() == 3 and app.current_object() != null,
		"clean Object tab closes without a prompt")
	app.new_object()
	_check(app.current_object().is_dirty(), "new unsaved source is modified")
	var count_before: int = app.tabs.size()
	app._request_close_current()
	_check(app.close_dialog.visible and app.tabs.size() == count_before,
		"unsaved-close guard prompts instead of discarding")
	app.close_dialog.hide()
	await process_frame
	_check(app.tabs.size() == count_before, "cancelled close preserves private draft")
	app._save_and_close()
	_check(app.save_dialog.visible and app.tabs.size() == count_before,
		"Save from close prompt waits for a target file without discarding the draft")
	app.save_dialog.hide()
	app._cancel_pending_close()
	_check(not app._close_after_save and app._closing_index == -1 and
		app.tabs.size() == count_before, "cancelled file chooser clears pending close action")
	app._close_index(app.active_tab)
	_check(app.tabs.size() == count_before - 1, "explicit discard closes without publication")
	app._activate(0)
	_check(app.current_object() == null and app.canvas.document == app.current_document(),
		"switching back to drawing retains canonical canvas/document")
	DirAccess.remove_absolute(source_path)
	DirAccess.remove_absolute(copy_path)
	print("DRAWING_OBJECT_UI_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
