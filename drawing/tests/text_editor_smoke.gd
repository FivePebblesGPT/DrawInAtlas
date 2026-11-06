extends SceneTree
## T-058 native editor witness: no-mutation text tool/cancel, typed text edit and rasterize.

var checks: int = 0
var failures: int = 0


func _check(value: bool, what: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DRAWING_TEXT_UI_FAILED: " + what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1100, 720)
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var doc: DrawingDocument = app.current_document()
	var first_count: int = doc.layer_count()
	var starting_revision: int = doc.revision
	app._change_tool("Text")
	_check(doc.revision == starting_revision, "Switching tools has no content effect")
	var world_point: Vector2i = Vector2i(-24, -19)
	app._edit_text_at(world_point)
	_check(doc.revision == starting_revision and app.text_dialog.visible,
		"Opening text dialog creates no layer")
	app.text_dialog.hide()
	_check(doc.revision == starting_revision and doc.layer_count() == first_count,
		"Cancel creates no layer")
	app._edit_text_at(world_point)
	app.text_edit.text = "The Harbor"
	app._commit_text_dialog()
	var text_id: String = app.current_layer()
	_check(doc.layer_count() == first_count + 1, "First committed text adds one layer")
	_check(doc.inspect_node(text_id).text_element.position == world_point, "Click sets negative world position")
	app._edit_text_at(Vector2i(99, 99))
	app.text_edit.text = "Harbor East"
	app._commit_text_dialog()
	_check(doc.layer_count() == first_count + 1, "Editing selected text reuses layer")
	_check(doc.inspect_node(text_id).text_element.content == "Harbor East", "Text edit persists")
	app._edit_text_at(world_point)
	app.text_font.select(1)
	app.text_edit.text = "Harbor East"
	app._commit_text_dialog()
	_check(doc.inspect_node(text_id).text_element.font_id == "lato-bold-v1", "Bold style selected in UI")
	app._rasterize_text()
	_check(doc.inspect_node(text_id).kind == DrawingLayerNode.RASTER, "Explicit action makes raster")
	app._undo()
	_check(doc.inspect_node(text_id).kind == DrawingLayerNode.TEXT, "Undo restores editable text")
	app.layer_search.text = "harbor"
	app._refresh_layers()
	_check(app.layers.get_root().get_child_count() == 1, "Search filters layer rows")
	app.layer_search.text = ""
	app._refresh_layers()
	var path: String = OS.get_cache_dir().path_join("text-ui-t058.drawing")
	app._save_file(path)
	_check(FileAccess.file_exists(path), "Standalone UI saves text")
	app._open_file(path)
	_check(app.current_document().inspect_node(text_id).text_element.content == "Harbor East", "UI reopen preserves text-only document")
	_check(app.current_document().layer_count() == first_count + 1, "UI reopen adds no phantom raster")
	_check(app.current_document().inspect_node(text_id).text_element.font_id == "lato-bold-v1", "Reopen retains selected font style")
	# A large label list is paged; searching semantic content narrows the rows.
	var many: DrawingDocument = DrawingDocument.new("many-labels", 32)
	for index: int in range(425):
		var label: DrawingTextElement = DrawingTextElement.new()
		label.content = "Marker %d" % index
		label.position = Vector2i(index * 3, index * 4)
		many.commit_text("", label, many.revision)
	app.tabs[app.active_tab]["document"] = many
	app.tabs[app.active_tab]["layer"] = many.list_children()[0]
	app.canvas.document = many
	app.canvas.layer_id = many.list_children()[0]
	app.layer_search.text = ""
	app.layer_page = 0
	app._refresh_layers()
	_check(app.layers.get_root().get_child_count() == 200 and app.layer_page_label.text.begins_with("1/3"),
		"Large label list displays bounded pages")
	app._change_layer_page(2)
	_check(app.layers.get_root().get_child_count() == 25, "Last label page contains remainder")
	app.layer_search.text = "Marker 405"
	app.layer_page = 0
	app._refresh_layers()
	_check(app.layers.get_root().get_child_count() == 1, "Search finds actual label content")
	DirAccess.remove_absolute(path)
	print("DRAWING_TEXT_UI_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
