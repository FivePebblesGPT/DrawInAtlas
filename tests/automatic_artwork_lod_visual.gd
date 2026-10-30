extends SceneTree
## T-005 native renderer: overview/local/empty/manual/automatic on one board.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("AUTOMATIC LOD VISUAL FAILED: " + label)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires X11 framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
	grid.visible = false
	_check(editor.create_board("Native LOD", grid), "creates independent test board")
	var canvas: AtlasCanvas = editor.canvas
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.render_grid = false
	var overview: AtlasInkLayer = canvas.floor.ink_layer()
	var points: PackedVector2Array = PackedVector2Array([Vector2(-45, 0), Vector2(45, 0)])
	editor._on_stroke(AtlasStroke.new(points, Color.RED, 12.0), false)
	var detail: AtlasInkLayer = AtlasInkLayer.new("detail", "D1 interior")
	detail.detail_level = 1
	detail.strokes.append(AtlasStroke.new(points, Color.GREEN, 12.0))
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	layers.append(detail)
	_check(editor.apply_layers(layers, overview.id), "adds independently authored D1 content")
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	await _witness(canvas, Color.RED, 0, "auto-lod-overview.png")
	canvas.camera_zoom = 12.0
	await _witness(canvas, Color.GREEN, 1, "auto-lod-local.png")
	_check(canvas.active_layer_id == overview.id and editor.layer_panel.show_editing_detail.visible,
		"automatic presentation leaves D0 selected and identifies hidden target")
	canvas.camera_center = Vector2(4000, 4000)
	await _witness(canvas, AtlasCanvas.EMPTY_COLOR, 0, "auto-lod-empty.png")
	canvas.camera_center = Vector2.ZERO
	await _witness(canvas, Color.GREEN, 1, "auto-lod-return.png")
	editor.layer_panel.show_editing_detail.pressed.emit()
	await _witness(canvas, Color.RED, 0, "auto-lod-manual.png")
	_check(not editor.automatic_artwork_lod, "explicit editing-level action switches to manual inspection")
	editor.layer_panel.auto_detail_checkbox.button_pressed = true
	await _witness(canvas, Color.GREEN, 1, "auto-lod-reenabled.png")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_AUTOMATIC_ARTWORK_LOD_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _witness(canvas: AtlasCanvas, expected: Color, level: int, filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var position: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(canvas.camera_center))
	_check(canvas.presented_detail_level == level, "presented D%d in %s" % [level, filename])
	_check(image.get_pixelv(position).is_equal_approx(expected),
		"%s samples the expected pixel in shared board coordinates" % filename)
	var directory: String = "user://validation"
	DirAccess.make_dir_recursive_absolute(directory)
	_check(image.save_png(directory.path_join(filename)) == OK, "saved framebuffer witness " + filename)
