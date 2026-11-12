extends SceneTree
## A Line's raster target must remain the same editable, presented Resource
## from press through release; stable IDs do not authorize a replacement.

var checks: int = 0
var failures: int = 0
var stroke_requests: int = 0
var rejected_requests: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T111_LINE_GATE_FAILED: " + reason)


func _button(canvas: AtlasCanvas, point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = canvas.document_to_local(point)
	canvas._gui_input(event)


func _motion(canvas: AtlasCanvas, point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.document_to_local(point)
	canvas._gui_input(event)


func _on_stroke(_stroke: AtlasStroke, _erasing: bool) -> void:
	stroke_requests += 1


func _on_rejected(_message: String) -> void:
	rejected_requests += 1


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Line release authorization", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 32.0)),
		"create real Atlas board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	var canvas: AtlasCanvas = editor.canvas
	canvas.stroke_requested.connect(_on_stroke)
	canvas.line_rejected.connect(_on_rejected)
	canvas.brush_width = 9.0
	canvas.brush_color = Color(0.8, 0.15, 0.1, 1.0)
	var original_map: AtlasMapDocument = canvas.map
	var original_floor: AtlasFloor = canvas.floor
	var original: AtlasRasterLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasRasterLayer
	_check(original != null and original.is_editable(), "capture editable raster target")
	if original == null:
		scene.queue_free()
		quit(1)
		return
	var start: Vector2 = canvas.camera_center - Vector2(18, 10)
	var finish: Vector2 = start + Vector2(27, 19)
	var source_before: Dictionary = original.to_dict()
	var cursor_before: int = editor.edits._cursor
	var expected_requests: int = 0
	var expected_rejections: int = 0
	for change: String in ["locked", "hidden", "different_detail", "same_id_replacement",
			"same_id_floor_replacement", "same_id_map_replacement"]:
		_button(canvas, start, true)
		_motion(canvas, finish)
		await process_frame
		_check(canvas._shape_kind == "LINE" and canvas._line_context_matches(),
			"%s: original raster target authorized at press" % change)
		_check(canvas._preview_layer != null and original.to_dict() == source_before,
			"%s: preview detached before release" % change)
		var layer_index: int = -1
		var replacement: AtlasRasterLayer = null
		match change:
			"locked":
				original.locked = true
			"hidden":
				original.visible = false
			"different_detail":
				original.detail_level = 1
			"same_id_floor_replacement":
				canvas.floor = original_floor.duplicate(true) as AtlasFloor
			"same_id_map_replacement":
				canvas.map = original_map.duplicate(true) as AtlasMapDocument
			"same_id_replacement":
				for index: int in range(canvas.floor.layers.size()):
					if canvas.floor.layers[index] == original:
						layer_index = index
						break
				replacement = AtlasRasterLayer.paint_layer(original.id, original.display_name)
				replacement.detail_level = original.detail_level
				if layer_index >= 0:
					canvas.floor.layers[layer_index] = replacement
		_check(not canvas._line_context_matches(),
			"%s: changed authorization invalidates pending draft" % change)
		_button(canvas, finish, false)
		expected_rejections += 1
		_check(stroke_requests == expected_requests and rejected_requests == expected_rejections,
			"%s: release rejects without emitting a raster command" % change)
		_check(not canvas.is_editing() and canvas._preview_layer == null,
			"%s: rejected line discards preview and input state" % change)
		_check(editor.edits._cursor == cursor_before and original.chunks.is_empty(),
			"%s: rejection leaves pixels and undo history untouched" % change)
		match change:
			"locked":
				original.locked = false
			"hidden":
				original.visible = true
			"different_detail":
				original.detail_level = 0
			"same_id_replacement":
				if layer_index >= 0:
					canvas.floor.layers[layer_index] = original
			"same_id_floor_replacement":
				canvas.floor = original_floor
			"same_id_map_replacement":
				canvas.map = original_map
		_check(canvas.floor.layer_by_id(original.id) == original and original.is_editable(),
			"%s: restore original target for another gesture" % change)
	# Valid retry must still publish a single edit after several rejections.
	_button(canvas, start, true)
	_motion(canvas, finish)
	_check(canvas._line_context_matches(), "fresh gesture is independently authorized")
	_button(canvas, finish, false)
	expected_requests += 1
	_check(stroke_requests == expected_requests and rejected_requests == expected_rejections,
		"unchanged source publishes precisely one line command")
	var painted: AtlasLayer = canvas.floor.layer_by_id(original.id)
	var painted_state: Dictionary = painted.to_dict() if painted != null else {}
	_check(editor.edits._cursor == cursor_before + 1 and painted_state != source_before,
		"valid line paints canonical pixels and creates one undo")
	var undone: bool = editor.edits.undo()
	var restored: AtlasLayer = canvas.floor.layer_by_id(original.id)
	_check(undone and restored != null and restored.to_dict() == source_before,
		"valid retry Undo restores the original canonical raster")
	var redone: bool = editor.edits.redo()
	var replayed: AtlasLayer = canvas.floor.layer_by_id(original.id)
	_check(redone and replayed != null and replayed.to_dict() == painted_state,
		"valid retry Redo restores the exact painted pixels")
	root.remove_child(scene)
	scene.free()
	print("T111_LINE_GATE_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
