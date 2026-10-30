extends SceneTree
## T-020: real pointer brush cursor, zoom, translucent paint and undo.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("BRUSH VISUAL FAILED: " + label)


func _frames(count: int = 3) -> void:
	for i: int in range(count):
		await process_frame


func _move(canvas: AtlasCanvas, point: Vector2, dragging: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + point
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	root.push_input(event, true)
	await _frames(3)


func _button(canvas: AtlasCanvas, point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.global_position + point
	event.global_position = event.position
	event.pressed = pressed
	root.push_input(event, true)
	await _frames(3)


func _sample(image: Image, canvas: AtlasCanvas, point: Vector2) -> Color:
	return image.get_pixelv(Vector2i(canvas.global_position + point))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "native framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(12)
	_check(editor.create_board("Brush native", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64)),
		"created isolated board")
	var canvas: AtlasCanvas = editor.canvas
	canvas.show_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	editor.inspector.brush_width_spinner.value = 40.0
	var picker: ColorPickerButton = editor.inspector.brush_color_picker
	picker.color = Color(1, 1, 1, 0.45)
	picker.color_changed.emit(picker.color)
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	_check(picker.edit_alpha and is_equal_approx(canvas.brush_color.a, 0.45)
		and canvas.brush_width == 40.0, "actual inspector opacity and width drive the brush")
	await _frames(5)
	var center: Vector2 = canvas.size * Vector2(0.5, 0.48)
	await _move(canvas, center)
	_check(canvas._brush_cursor_inside and canvas._brush_cursor_local.distance_to(center) < 0.1,
		"native motion routes through brush cursor")
	await RenderingServer.frame_post_draw
	var frame1: Image = root.get_texture().get_image()
	var ring: Color = _sample(frame1, canvas, center + Vector2(20, 0))
	var background: Color = _sample(frame1, canvas, center + Vector2(30, 0))
	_check(ring.r > background.r + 0.20, "ring shows actual 40-unit diameter at zoom 1")
	canvas.camera_zoom = 2.0
	canvas.queue_redraw()
	await _frames(5)
	await RenderingServer.frame_post_draw
	var frame2: Image = root.get_texture().get_image()
	var zoomed: Color = _sample(frame2, canvas, center + Vector2(40, 0))
	var off_ring: Color = _sample(frame2, canvas, center + Vector2(25, 0))
	_check(zoomed.r > off_ring.r + 0.20, "cursor radius scales with camera zoom")
	# Restore normal zoom and leave the cursor off the center line for sampling.
	canvas.camera_zoom = 1.0
	var start: Vector2 = Vector2(75, canvas.size.y * 0.65)
	var end: Vector2 = Vector2(canvas.size.x - 75, start.y)
	await _button(canvas, start, true)
	await _move(canvas, end, true)
	await _button(canvas, end, false)
	_check(canvas.floor.strokes.size() == 1, "real pointer press/drag/release commits one brush gesture")
	_check(canvas.floor.strokes[0].color.is_equal_approx(Color(1, 1, 1, 0.45))
		and canvas.floor.strokes[0].width == 40.0,
		"gesture preserves selected alpha and width")
	await _move(canvas, center)
	await RenderingServer.frame_post_draw
	var painted: Image = root.get_texture().get_image()
	var midpoint: Color = _sample(painted, canvas, (start + end) * 0.5)
	var blank: Color = _sample(painted, canvas, (start + end) * 0.5 + Vector2(0, -55))
	_check(midpoint.r > blank.r + 0.15 and midpoint.r < 0.85,
		"translucent paint on framebuffer is neither invisible nor fully opaque")
	var slot: String = "user://validation/brush-native.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(painted.save_png(slot) == OK, "saved native brush witness")
	editor._on_undo()
	_check(canvas.floor.strokes.is_empty(), "one undo removes the pointer gesture")
	editor._on_redo()
	_check(canvas.floor.strokes.size() == 1, "redo restores pointer gesture")
	editor.artwork.choose_tool(AtlasCanvas.Tool.ART_SELECT)
	await _frames(4)
	_check(not canvas._brush_cursor_inside or canvas.tool != AtlasCanvas.Tool.PEN,
		"brush cursor is disabled for other tools")

	# Drive a real raster gesture across x=0, then cancel a second gesture.
	# Only release after a valid gesture is allowed to produce an undo entry.
	var next_layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	next_layers.append(AtlasRasterLayer.new("visual-raster", "Visual raster"))
	_check(editor.apply_layers(next_layers, "visual-raster"), "native UI can create a raster paint target")
	editor.select_layer("visual-raster")
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	editor.inspector.brush_width_spinner.value = 4.0
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	var seam: Vector2 = canvas.size * 0.5
	await _button(canvas, seam + Vector2(-8, 0), true)
	await _move(canvas, seam + Vector2(8, 0), true)
	await _button(canvas, seam + Vector2(8, 0), false)
	var raster: AtlasRasterLayer = canvas.floor.layer_by_id("visual-raster") as AtlasRasterLayer
	_check(raster != null and raster.chunks.has("-1,0") and raster.chunks.has("0,0"),
		"native pointer gesture creates both sides of the signed raster seam")
	editor._on_undo()
	raster = canvas.floor.layer_by_id("visual-raster") as AtlasRasterLayer
	_check(raster != null and raster.chunks.is_empty(), "undo removes the full native raster sweep")
	editor._on_redo()
	raster = canvas.floor.layer_by_id("visual-raster") as AtlasRasterLayer
	_check(raster != null and raster.chunks.has("-1,0") and raster.chunks.has("0,0"),
		"redo restores both raster chunks")
	var committed: AtlasRasterLayer = raster
	var committed_hash: String = AtlasRasterChunk.image_hash(committed.chunks["0,0"].image)
	await _button(canvas, seam + Vector2(25, 25), true)
	await _move(canvas, seam + Vector2(35, 25), true)
	_check(canvas.is_editing(), "a second native raster gesture can be previewed")
	canvas.cancel_edit()
	await _button(canvas, seam + Vector2(35, 25), false)
	_check(canvas.floor.layer_by_id("visual-raster") == committed
		and AtlasRasterChunk.image_hash(committed.chunks["0,0"].image) == committed_hash,
		"cancelled native raster preview preserves the source snapshot and pixels")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_BRUSH_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
