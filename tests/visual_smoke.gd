extends SceneTree
## Run with a real display/renderer; compares actual framebuffer pixels outside the canvas.


func _initialize() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual smoke requires a real renderer, not the headless dummy driver.")
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

	editor.canvas.modulate = Color(1, 1, 1, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	var chrome_only: Image = root.get_texture().get_image()
	editor.canvas.modulate = Color.WHITE
	editor.canvas.camera_zoom = 0.5
	editor.canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var with_canvas: Image = root.get_texture().get_image()
	var bounds: Rect2 = editor.canvas.get_global_rect()
	var changed_outside: int = 0
	var changed_inside: int = 0
	for y: int in range(0, with_canvas.get_height(), 4):
		for x: int in range(0, with_canvas.get_width(), 4):
			if not chrome_only.get_pixel(x, y).is_equal_approx(with_canvas.get_pixel(x, y)):
				if bounds.has_point(Vector2(x, y)):
					changed_inside += 1
				else:
					changed_outside += 1
	var directory: String = "user://validation"
	DirAccess.make_dir_recursive_absolute(directory)
	var screenshot_error: Error = with_canvas.save_png(directory.path_join("integrated-editor.png"))
	var passed: bool = (changed_outside == 0 and changed_inside > 100
		and screenshot_error == OK and bounds.size.y >= 500.0)
	var canvas: AtlasCanvas = editor.canvas
	canvas.show_grid = false
	await process_frame
	await RenderingServer.frame_post_draw
	var terrain_before: Image = root.get_texture().get_image()
	var overlay: AtlasGrid = canvas.map.grid.copy()
	overlay.kind = AtlasGrid.Kind.SQUARE
	overlay.cell_size = 80.0
	overlay.origin = Vector2(33, -27)
	overlay.rotation = deg_to_rad(37.0)
	editor.apply_grid(overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	var terrain_after: Image = root.get_texture().get_image()
	var terrain_moved: int = 0
	for y: int in range(int(bounds.position.y), int(bounds.end.y), 4):
		for x: int in range(int(bounds.position.x), int(bounds.end.x), 4):
			if not terrain_before.get_pixel(x, y).is_equal_approx(terrain_after.get_pixel(x, y)):
				terrain_moved += 1
	passed = passed and terrain_moved == 0
	passed = passed and terrain_after.save_png(directory.path_join("independent-grid.png")) == OK
	editor._on_undo()
	var blank_grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
	blank_grid.distance_per_cell = 1.0
	blank_grid.distance_unit = "tiles"
	passed = passed and editor.create_board("Blank sketch", blank_grid)
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.floor.terrain.clear()
	var ink: Color = Color("#f5b545")
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([
		Vector2(-140, 0), Vector2(140, 0)
	]), ink, 20.0), false)
	await process_frame
	await RenderingServer.frame_post_draw
	var drawn: Image = root.get_texture().get_image()
	var center: Vector2i = Vector2i(canvas.global_position + canvas.size * 0.5)
	passed = passed and drawn.get_pixelv(center).is_equal_approx(ink)
	passed = passed and drawn.save_png(directory.path_join("freehand.png")) == OK
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([
		Vector2(0, -40), Vector2(0, 40)
	]), Color.BLACK, 30.0), true)
	await process_frame
	await RenderingServer.frame_post_draw
	var erased: Image = root.get_texture().get_image()
	var real_gap: bool = erased.get_pixelv(center).is_equal_approx(AtlasCanvas.EMPTY_COLOR)
	var surviving_ink: bool = erased.get_pixelv(center + Vector2i(-100, 0)).is_equal_approx(ink)
	passed = passed and real_gap and surviving_ink
	passed = passed and erased.save_png(directory.path_join("erased.png")) == OK
	editor._on_undo()
	await process_frame
	await RenderingServer.frame_post_draw
	var undo_image: Image = root.get_texture().get_image()
	var restored_ink: bool = undo_image.get_pixelv(center).is_equal_approx(ink)
	passed = passed and restored_ink
	passed = passed and undo_image.save_png(directory.path_join("undo-erase.png")) == OK
	editor.select_layer("ink")
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(-100, -40), Vector2(-100, 40)]), ink, 20.0), false)
	var translucent: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	(translucent[1] as AtlasInkLayer).opacity = 0.5
	editor.apply_layers(translucent, "ink")
	await process_frame
	await RenderingServer.frame_post_draw
	var alpha_frame: Image = root.get_texture().get_image()
	var line_pixel: Color = alpha_frame.get_pixelv(center + Vector2i(-60, 0))
	var crossing_pixel: Color = alpha_frame.get_pixelv(center + Vector2i(-100, 0))
	var group_opacity: bool = line_pixel.is_equal_approx(crossing_pixel) and line_pixel.r > 0.2 and line_pixel.r < 0.9
	passed = passed and group_opacity
	var blue: Color = Color("#2070ff")
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(blue)
	editor.import_raster(image)
	var raster_id: String = canvas.active_layer_id
	await process_frame
	await RenderingServer.frame_post_draw
	var raster_frame: Image = root.get_texture().get_image()
	var raster_on_top: bool = raster_frame.get_pixelv(center + Vector2i(20, 5)).is_equal_approx(blue)
	passed = passed and raster_on_top
	editor.layer_panel._move(-1)
	await process_frame
	await RenderingServer.frame_post_draw
	var reordered_frame: Image = root.get_texture().get_image()
	var layer_order: bool = not reordered_frame.get_pixelv(center + Vector2i(20, 5)).is_equal_approx(blue)
	passed = passed and layer_order
	editor.layer_panel.visibility_checkbox.button_pressed = false
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_frame: Image = root.get_texture().get_image()
	var hidden_raster: bool = hidden_frame.get_pixelv(center + Vector2i(20, 20)).is_equal_approx(AtlasCanvas.EMPTY_COLOR)
	passed = passed and hidden_raster
	editor.layer_panel.visibility_checkbox.button_pressed = true
	editor.layer_panel.opacity_spinner.value = 0.5
	editor.sidebar.select_view(&"Layers")
	await process_frame
	await RenderingServer.frame_post_draw
	var layered_frame: Image = root.get_texture().get_image()
	var partial: Color = layered_frame.get_pixelv(center + Vector2i(20, 20))
	var raster_opacity: bool = partial.b > AtlasCanvas.EMPTY_COLOR.b and partial.b < blue.b
	passed = passed and raster_opacity and canvas.floor.layer_by_id(raster_id) != null
	passed = passed and layered_frame.save_png(directory.path_join("typed-layers.png")) == OK
	editor.select_layer(raster_id)
	editor.select_all_artwork()
	var original_raster: AtlasRasterLayer = canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer
	var original_asset: String = original_raster.chunks["0,0"].asset_id
	var moved: bool = editor.transform_selection(canvas.selection, Transform2D(0.0, Vector2(120, -90)))
	await process_frame
	await RenderingServer.frame_post_draw
	var moved_frame: Image = root.get_texture().get_image()
	var asset_move_pixels: bool = (
		moved and moved_frame.get_pixelv(center + Vector2i(20, 20)).is_equal_approx(AtlasCanvas.EMPTY_COLOR)
		and moved_frame.get_pixelv(center + Vector2i(140, -70)).is_equal_approx(partial)
	)
	var delta: Transform2D = AtlasSelectionGeometry.about(canvas.selection.bounds.get_center(), Vector2.ZERO, 2.0)
	var scaled: bool = editor.transform_selection(canvas.selection, delta)
	await process_frame
	await RenderingServer.frame_post_draw
	var scaled_frame: Image = root.get_texture().get_image()
	var asset_scale_pixels: bool = scaled and scaled_frame.get_pixelv(center + Vector2i(175, -90)).b > AtlasCanvas.EMPTY_COLOR.b
	var unchanged_asset: bool = (canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer).chunks["0,0"].asset_id == original_asset
	passed = passed and asset_move_pixels and asset_scale_pixels and unchanged_asset
	passed = passed and scaled_frame.save_png(directory.path_join("selection-transform.png")) == OK
	editor._on_undo()
	editor._on_undo()
	editor.select_layer("ink")
	editor._on_stroke(AtlasShapes.stroke("RECTANGLE", Vector2(-220, -120), Vector2(-160, -60), Color.LIME, 4.0), false)
	await process_frame
	await RenderingServer.frame_post_draw
	var shape_frame: Image = root.get_texture().get_image()
	var shape_pixels: bool = shape_frame.get_pixelv(center + Vector2i(-190, -120)).g > 0.4
	passed = passed and shape_pixels
	editor.layer_panel._add_raster()
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(-60, 90), Vector2(60, 90)]), Color.RED, 20.0), false)
	canvas.brush_color = Color.BLUE
	var filled: bool = editor.fill_at(Vector2(0, 90))
	await process_frame
	await RenderingServer.frame_post_draw
	var painted_frame: Image = root.get_texture().get_image()
	var fill_pixels: bool = filled and painted_frame.get_pixelv(center + Vector2i(0, 90)).is_equal_approx(Color.BLUE)
	editor._on_undo()
	await process_frame
	await RenderingServer.frame_post_draw
	var fill_undo_pixels: bool = root.get_texture().get_image().get_pixelv(center + Vector2i(0, 90)).is_equal_approx(Color.RED)
	passed = passed and fill_pixels and fill_undo_pixels
	passed = passed and painted_frame.save_png(directory.path_join("drawing-tools.png")) == OK
	editor.open_board_dialog()
	await process_frame
	await RenderingServer.frame_post_draw
	passed = passed and root.get_texture().get_image().save_png(directory.path_join("new-board.png")) == OK
	editor.board_dialog.hide()
	root.content_scale_size = Vector2i(800, 600)
	root.size = Vector2i(800, 600)
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var compact: Image = root.get_texture().get_image()
	var compact_layout: bool = (
		is_equal_approx(canvas.global_position.y, editor.sidebar.global_position.y)
		and editor.title_label.get_global_rect().end.x <= 800.0
		and canvas.get_global_rect().end.x <= 800.0
	)
	passed = passed and compact_layout
	passed = passed and compact.save_png(directory.path_join("compact-editor.png")) == OK
	editor.open_board_dialog()
	await process_frame
	await RenderingServer.frame_post_draw
	var dialog: AtlasBoardDialog = editor.board_dialog
	var compact_dialog: bool = dialog.position.y >= 0 and dialog.position.y + dialog.size.y <= 600
	passed = passed and compact_dialog
	passed = passed and root.get_texture().get_image().save_png(directory.path_join("compact-new-board.png")) == OK
	dialog.hide()
	print("ATLAS_VISUAL_%s outside=%d inside=%d screenshot=%s" % [
		"PASSED" if passed else "FAILED", changed_outside, changed_inside,
		ProjectSettings.globalize_path(directory.path_join("integrated-editor.png"))
	])
	print("ATLAS_INK_PIXELS gap=%s surviving_ink=%s undo=%s" % [real_gap, surviving_ink, restored_ink])
	print("ATLAS_COMPACT_LAYOUT %s" % compact_layout)
	print("ATLAS_GRID_INVARIANCE moved_pixels=%d compact_dialog=%s" % [terrain_moved, compact_dialog])
	print("ATLAS_LAYER_PIXELS grouped_alpha=%s raster_top=%s order=%s hidden=%s raster_alpha=%s" % [
		group_opacity, raster_on_top, layer_order, hidden_raster, raster_opacity])
	print("ATLAS_TOOL_PIXELS move=%s scale=%s asset_unchanged=%s shape=%s fill=%s undo_fill=%s" % [
		asset_move_pixels, asset_scale_pixels, unchanged_asset, shape_pixels, fill_pixels, fill_undo_pixels])
	root.remove_child(scene)
	scene.free()
	quit(0 if passed else 1)
