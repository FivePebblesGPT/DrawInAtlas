extends SceneTree
## Standalone project contract and UI/pointer/file witness. Exit status is authoritative.

var passes: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, description: String) -> void:
	if value:
		passes += 1
	else:
		failures += 1
		push_error("DRAWING_STANDALONE_FAILED: " + description)


func read_pixel(document: DrawingDocument, layer: String, x: int, y: int) -> int:
	var result: DrawingResult = document.read_pixel(layer, x, y)
	check(result.ok, "pixel read: " + result.message)
	return int(result.value) if result.ok else -1


func mouse(canvas: Control, point: Vector2i, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.pixel_to_position(Vector2(point) + Vector2(0.5, 0.5))
	canvas._gui_input(event)


func gesture(canvas: Control, begin: Vector2i, finish: Vector2i) -> void:
	mouse(canvas, begin, true)
	if finish != begin:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = canvas.pixel_to_position(Vector2(finish) + Vector2(0.5, 0.5))
		canvas._gui_input(motion)
	mouse(canvas, finish, false)


func _run() -> void:
	var shell: Control = load("res://main.tscn").instantiate()
	shell.layout_persistence_enabled = false
	root.add_child(shell)
	await process_frame
	await process_frame
	check(shell.tabs.size() == 1, "launch creates one document tab")
	var document: DrawingDocument = shell.current_document()
	var layer: String = shell.current_layer()
	check(document.layer_count() == 2 and document.has_node(layer), "group and layer exist")
	var group_id: String = document.list_children()[0]
	check(document.node_metadata(layer)["parent"] == group_id, "layer belongs to new group")
	var canvas: Control = shell.canvas
	check(canvas.document == document, "UI uses canonical DrawingDocument")
	canvas.tool = "Brush"
	gesture(canvas, Vector2i(-3, 2), Vector2i(-2, 2))
	var painted: int = read_pixel(document, layer, -3, 2)
	check(painted != 0 and document.revision > 2, "pointer paint commits raster edit")
	canvas.tool = "Eraser"
	gesture(canvas, Vector2i(-3, 2), Vector2i(-3, 2))
	check(read_pixel(document, layer, -3, 2) == 0, "pointer eraser clears raster")
	check(document.undo().ok and read_pixel(document, layer, -3, 2) == painted, "undo eraser")
	check(document.redo().ok and read_pixel(document, layer, -3, 2) == 0, "redo eraser")
	check(document.undo().ok, "restore paint for move")
	canvas.tool = "Select"
	gesture(canvas, Vector2i(-4, 1), Vector2i(0, 4))
	check(canvas.selected == Rect2i(-4, 1, 5, 4), "pointer creates rectangular selection")
	canvas.tool = "Move"
	gesture(canvas, Vector2i(-3, 2), Vector2i(7, 7))
	check(read_pixel(document, layer, -3, 2) == 0 and read_pixel(document, layer, 7, 7) == painted,
		"pointer moves selection as one edit")
	check(document.undo().ok and read_pixel(document, layer, -3, 2) == painted and
		read_pixel(document, layer, 7, 7) == 0, "undo selection move")
	check(document.redo().ok and read_pixel(document, layer, 7, 7) == painted, "redo selection move")
	var opened: DrawingResult = document.begin_edit(layer, document.revision)
	check(opened.ok, "prepare straight-alpha witness")
	var edit: DrawingEditSession = opened.value as DrawingEditSession
	check(edit.apply_region(Rect2i(20, 20, 1, 1), PackedByteArray([17, 34, 51, 0])).ok,
		"stage hidden-RGB transparent pixel")
	check(edit.commit().ok and read_pixel(document, layer, 20, 20) == 0x00332211,
		"transparent hidden RGB committed")
	var file_path: String = ProjectSettings.globalize_path("user://drawing-t053-test.drawing")
	shell._save_file(file_path)
	check(FileAccess.file_exists(file_path) and not document.is_dirty(), "Save produces clean standalone file")
	shell._open_file(file_path)
	check(shell.tabs.size() == 2, "Open creates a new document tab")
	var reopened: DrawingDocument = shell.current_document()
	var reopened_layer: String = shell.current_layer()
	check(reopened.id == document.id and reopened_layer == layer and
		reopened.list_children()[0] == group_id, "file preserves document/group/layer IDs")
	check(read_pixel(reopened, layer, 7, 7) == painted and
		read_pixel(reopened, layer, 20, 20) == 0x00332211 and
		read_pixel(reopened, layer, -3, 2) == 0, "file preserves exact pixels and alpha")
	check(not reopened.is_dirty(), "reopened savepoint is clean")
	var payload: DrawingResult = DrawingFileIO.encode(reopened)
	check(payload.ok, "standalone format encodes opened document")
	var damaged: Dictionary = (payload.value as Dictionary).duplicate(true)
	var blobs: Dictionary = damaged["blobs"]
	if not blobs.is_empty():
		var key: String = String(blobs.keys()[0])
		blobs[key] = "AAAA"
		var failed: DrawingResult = DrawingFileIO.decode(damaged)
		check(not failed.ok and failed.code == "CORRUPT_TILE", "corrupted pixel blobs rejected")
	var saved_id: String = reopened.id
	var duplicated: DrawingResult = DrawingFileIO.decode(payload.value)
	check(duplicated.ok and (duplicated.value as DrawingDocument).id == saved_id,
		"standalone decoder remains independent of UI")
	canvas.document = reopened
	canvas.layer_id = reopened_layer
	canvas.queue_redraw()
	await process_frame
	# A bounded composited image must be drawable, not just a valid data model.
	var rendered: DrawingResult = DrawingRenderer.render(reopened, Rect2i(5, 5, 6, 6))
	check(rendered.ok and (rendered.value as Image).get_width() == 6,
		"framebuffer render succeeds after file open")
	DirAccess.remove_absolute(file_path)
	print("DRAWING_STANDALONE: %d passed; %d failed" % [passes, failures])
	if failures == 0:
		print("DRAWING_STANDALONE_PASSED")
	quit(1 if failures else 0)
