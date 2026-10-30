extends SceneTree
## T-023: native framebuffer pointer preview, Escape cancellation, release/undo and compact UI.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("BUCKET VISUAL FAILED: " + description)


func _frames(count: int = 4) -> void:
	for frame: int in range(count):
		await process_frame


func _button(canvas: AtlasCanvas, point: Vector2, pressed: bool, shift: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.global_position + point
	event.global_position = event.position
	event.shift_pressed = shift
	event.pressed = pressed
	root.push_input(event, true)
	await _frames()


func _key(key: Key) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.keycode = key
	press.pressed = true
	root.push_input(press, true)
	await _frames()
	var release: InputEventKey = InputEventKey.new()
	release.keycode = key
	release.pressed = false
	root.push_input(release, true)
	await _frames()


func _sample(canvas: AtlasCanvas, document_point: Vector2) -> Color:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	return image.get_pixelv(Vector2i(canvas.global_position + canvas.document_to_local(document_point)))


func _pixel(layer: AtlasRasterLayer, point: Vector2i) -> Color:
	var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
	var chunk: AtlasRasterChunk = layer.chunks.get("%d,%d" % [coord.x, coord.y])
	return chunk.image.get_pixelv(point - coord * 256)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires native framebuffer")
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
	_check(editor.create_board("Bucket visual", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64)),
		"isolated board created")
	var canvas: AtlasCanvas = editor.canvas
	canvas.show_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 8.0
	var image: Image = Image.create_empty(9, 7, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.85, 0.1, 0.1, 1))
	for y: int in range(7):
		image.set_pixel(4, y, Color(0.15, 0.3, 0.9, 1))
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	raster.id = "bucket-visual-raster"
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	layers.append(raster)
	_check(editor.apply_layers(layers, raster.id), "raster installed as active layer")
	editor.select_layer(raster.id)
	editor._choose_tool(AtlasCanvas.Tool.FILL)
	canvas.brush_color = Color(0.0, 0.9, 0.25, 1)
	var target: Vector2 = Vector2(2.5, 2.5)
	await _frames(8)
	var before: Color = await _sample(canvas, target)
	var undo_before: AtlasEditCommand = editor.edits.get_undo_command()
	await _button(canvas, canvas.document_to_local(target), true)
	_check(canvas._fill_pending and canvas._preview_layer != null,
		"real press stages detached visible preview")
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(2, 2)).r > 0.8
		and editor.edits.get_undo_command() == undo_before,
		"preview does not mutate raster or history")
	var preview_color: Color = await _sample(canvas, target)
	_check(preview_color.g > before.g + 0.35, "framebuffer displays preview before commit")
	await _key(KEY_ESCAPE)
	_check(not canvas._fill_pending and canvas._preview_layer == null,
		"Escape cancels pending pointer fill")
	var cancelled: Color = await _sample(canvas, target)
	_check(absf(cancelled.g - before.g) < 0.08 and editor.edits.get_undo_command() == undo_before,
		"cancel restores original framebuffer and preserves undo history")
	await _button(canvas, canvas.document_to_local(target), false)
	_check(editor.edits.get_undo_command() == undo_before,
		"pointer release after Escape cannot commit stale preview")
	await _button(canvas, canvas.document_to_local(target), true)
	await _button(canvas, canvas.document_to_local(target), false)
	_check(not canvas._fill_pending and canvas._preview_layer == null
		and _pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(2, 2)).g > 0.8,
		"release commits whole connected region")
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(6, 2)).r > 0.8,
		"paint does not cross dissimilar-color boundary")
	var committed: Color = await _sample(canvas, target)
	_check(committed.g > before.g + 0.35, "committed framebuffer matches preview")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	var frame: Image = root.get_texture().get_image()
	_check(frame.save_png("user://validation/bucket-native.png") == OK,
		"saved native bucket witness")
	editor._on_undo()
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(2, 2)).r > 0.8,
		"single undo restores original region")
	editor._on_redo()
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(2, 2)).g > 0.8,
		"single redo restores filled region")
	# Shift temporarily selects Global on raster; disconnected matching pixels
	# on the right side of the blue barrier become green in one transaction.
	editor._on_undo()
	await _button(canvas, canvas.document_to_local(target), true, true)
	_check(canvas._fill_pending and canvas._preview_layer != null
		and _pixel(canvas._preview_layer as AtlasRasterLayer, Vector2i(6, 2)).g > 0.8,
		"Shift press stages global mode for disconnected matching pixels")
	await _button(canvas, canvas.document_to_local(target), false, true)
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(6, 2)).g > 0.8,
		"Shift release commits global fill even when checkbox is off")
	editor._on_undo()
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(6, 2)).r > 0.8,
		"global fill undo restores disconnected region in one step")
	# Exiting the board cancels an in-flight fill without needing release on canvas.
	await _button(canvas, canvas.document_to_local(target), true)
	canvas._clear_brush_cursor()
	_check(not canvas._fill_pending and editor.artwork._pending_fill == null,
		"leaving board cancels preview instead of allowing an accidental commit")
	await _button(canvas, canvas.document_to_local(target), false)
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(canvas.size.x > 190 and editor.inspector._bucket_section.visible,
		"compact window retains canvas and Bucket options")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_BUCKET_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
