extends SceneTree
## Delayed authoring confirmation must never mutate a different document or layer.

var checks: int = 0
var failures: int = 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T134_DIALOG_FAILED: " + label)


func frames(count: int = 3) -> void:
	for _index: int in range(count):
		await process_frame


func app_ready() -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.start_blank_document = false
	root.add_child(app)
	await frames()
	return app


func test_drawing_dialogs() -> void:
	var app: Control = await app_ready()
	app.new_drawing()
	var original: DrawingDocument = app.current_document()
	var first_layer: String = app.current_layer()
	app.new_drawing()
	var other: DrawingDocument = app.current_document()
	var other_layer: String = app.current_layer()
	check(original != other and first_layer != other_layer, "independent drawing layers")
	var old_name: String = String(other.node_metadata(other_layer)["name"])
	var old_count: int = other.layer_count()
	var old_count_original: int = original.layer_count()
	var old_frame: Rect2i = app.canvas.image_bounds
	var old_grid: int = app.canvas.grid_spacing
	app._activate(0)
	app._ask_layer_rename()
	app.layer_rename_field.text = "Wrong document rename"
	app._activate(1)
	app.layer_rename_dialog.confirmed.emit()
	app.layer_rename_dialog.hide()
	check(other.node_metadata(other_layer).get("name") == old_name,
		"stale layer rename cannot mutate a different tab")
	check(original.node_metadata(first_layer).get("name") != "Wrong document rename",
		"stale layer rename also leaves origin unchanged")
	check(app.status.text.contains("dialog") or app.status.text.contains("tab"),
		"stale layer confirmation reports a visible refusal")
	app._activate(0)
	app._edit_text_at(Vector2i(13, 24))
	app.text_edit.text = "Wrong document text"
	app._activate(1)
	app.text_dialog.confirmed.emit()
	app.text_dialog.hide()
	check(other.layer_count() == old_count,
		"stale Text editor cannot create a layer in another tab")
	check(original.layer_count() == old_count_original,
		"stale Text editor does not mutate its origin either")
	app._activate(0)
	app._ask_image_frame()
	app.image_frame_fields[2].value = 777
	app._activate(1)
	app.image_frame_dialog.confirmed.emit()
	app.image_frame_dialog.hide()
	check(app.canvas.image_bounds == old_frame,
		"stale image-frame dialog cannot rewrite another tab")
	app._activate(0)
	app._ask_grid_settings()
	app.grid_fields[0].value = 71
	app._activate(1)
	app.grid_dialog.confirmed.emit()
	app.grid_dialog.hide()
	check(app.canvas.grid_spacing == old_grid,
		"stale grid dialog cannot change the other tab view")
	# Cancellation must revoke the confirmation's authority even without a tab switch.
	app._ask_layer_rename()
	app.layer_rename_field.text = "Cancelled rename"
	app.layer_rename_dialog.canceled.emit()
	app.layer_rename_dialog.hide()
	app.layer_rename_dialog.confirmed.emit()
	app.layer_rename_dialog.hide()
	check(other.node_metadata(other_layer).get("name") == old_name,
		"cancelled layer rename cannot be replayed by a late confirmation")
	# Same-tab layer selection and document revision must remain the captured target.
	app._ask_layer_rename()
	app.layer_rename_field.text = "Wrong selected layer"
	var added: DrawingResult = other.create_layer(DrawingLayerNode.RASTER, "New layer", DrawingDocument.ROOT_ID)
	check(added.ok, "independent layer creation succeeds")
	if added.ok:
		app._select_layer_node(String(added.value), false)
	app.layer_rename_dialog.confirmed.emit()
	app.layer_rename_dialog.hide()
	check(other.node_metadata(String(added.value)).get("name") == "New layer" if added.ok else true,
		"stale layer dialog cannot rename a newly selected layer")
	app._select_layer_node(other_layer, false)
	# A new dialog from the active tab must still be able to commit normally.
	app._ask_layer_rename()
	app.layer_rename_field.text = "Authorized rename"
	app.layer_rename_dialog.confirmed.emit()
	app.layer_rename_dialog.hide()
	check(other.node_metadata(other_layer).get("name") == "Authorized rename",
		"current-tab layer dialog commits to its intended row")
	app._edit_text_at(Vector2i(17, -11))
	app.text_edit.text = "Authorized text"
	var before_text: int = other.layer_count()
	app.text_dialog.confirmed.emit()
	app.text_dialog.hide()
	check(other.layer_count() == before_text + 1,
		"current-tab Text dialog commits to original document")
	app._ask_grid_settings()
	app.grid_fields[0].value = 27
	app.grid_dialog.confirmed.emit()
	app.grid_dialog.hide()
	check(app.canvas.grid_spacing == 27, "current-tab grid dialog updates its own view")
	app._ask_image_frame()
	app.image_frame_fields[2].value = 333
	app.image_frame_dialog.confirmed.emit()
	app.image_frame_dialog.hide()
	check(app.canvas.image_bounds.size.x == 333,
		"current-tab image-frame dialog updates its own view")
	# Reusing the same tab index after close must never authorize a stale modal.
	app._activate(0)
	app._ask_layer_rename()
	app.layer_rename_field.text = "Reused index rename"
	app._close_index(0)
	check(app.active_tab == 0 and app.current_document() == other,
		"origin tab closed and another document occupies its index")
	app.layer_rename_dialog.confirmed.emit()
	app.layer_rename_dialog.hide()
	check(other.node_metadata(other_layer).get("name") == "Authorized rename",
		"reused tab index cannot authorize an old layer rename")
	app.queue_free()
	await frames(2)


func test_object_dialogs() -> void:
	var app: Control = await app_ready()
	app.new_object()
	var original: DrawingObjectEditorSession = app.current_object()
	app.new_object()
	var other: DrawingObjectEditorSession = app.current_object()
	check(original != null and other != null and original != other,
		"two Object Editor sessions are distinct")
	var initial_name: String = other.name
	var initial_origin: Vector2i = other.origin
	app._activate(0)
	app._ask_rename_object()
	app.rename_field.text = "Wrong Object rename"
	app._activate(1)
	app.rename_dialog.confirmed.emit()
	app.rename_dialog.hide()
	check(other.name == initial_name and original.name != "Wrong Object rename",
		"stale Object rename cannot change either source")
	app._activate(0)
	app._ask_object_frame()
	app.frame_fields[0].value = 444
	app._activate(1)
	app.frame_dialog.confirmed.emit()
	app.frame_dialog.hide()
	check(other.origin == initial_origin and original.origin != Vector2i(444, 0),
		"stale Object frame cannot change another source")
	app._ask_rename_object()
	app.rename_field.text = "Correct Object name"
	app.rename_dialog.confirmed.emit()
	app.rename_dialog.hide()
	check(other.name == "Correct Object name", "current Object rename still works")
	app._ask_object_frame()
	app.frame_fields[0].value = -42
	app.frame_dialog.confirmed.emit()
	app.frame_dialog.hide()
	check(other.origin.x == -42, "current Object frame still works")
	app.queue_free()
	await frames(2)


func run() -> void:
	await test_drawing_dialogs()
	await test_object_dialogs()
	if failures == 0:
		print("T134_DIALOG_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T134_DIALOG_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
