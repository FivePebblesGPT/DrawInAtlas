extends SceneTree
## Native high-resolution raster scribble: input fidelity, stable work and alpha.

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("DRAWING FAILED: " + label)


func _frames(count: int = 2) -> void:
	for index: int in range(count):
		await process_frame


func _button(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(10)
	editor.create_board("Drawing performance", AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 64))
	var canvas: AtlasCanvas = editor.canvas
	canvas.show_grid = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	canvas.brush_color = Color(1, 1, 1, 0.4)
	canvas.brush_width = 8.0
	canvas.edit_scope = AtlasEditScope.new(canvas.map.grid.cell_polygon(Vector2i.ZERO), true)
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	var original_accumulation: bool = Input.use_accumulated_input
	for layer_id: String in ["raster"]:
		editor.select_layer(layer_id)
		await _frames()
		var center: Vector2 = canvas.size * 0.5
		var point: Vector2 = center + Vector2(16, 0)
		_button(canvas, point, true)
		_check(not Input.use_accumulated_input, "drawing receives unmerged OS motion events")
		var redraws: Array[int] = [0]
		var count_redraw: Callable = func() -> void: redraws[0] += 1
		canvas._layer_drawers[layer_id].draw.connect(count_redraw)
		var early_us: int = 0
		var late_us: int = 0
		for batch: int in range(64):
			var start: int = Time.get_ticks_usec()
			# 32 distinct pointer positions before any rendering/frame signal.
			for sample: int in range(32):
				var angle: float = (batch * 32 + sample + 1) * 0.13
				point = center + Vector2(cos(angle), sin(angle)) * 16.0
				var motion: InputEventMouseMotion = InputEventMouseMotion.new()
				motion.position = canvas.global_position + point
				motion.global_position = motion.position
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				root.push_input(motion, true)
			_check(canvas._draft_stroke != null and canvas._draft_stroke.points.size() == (batch + 1) * 32 + 1,
				"every between-frame motion sample is retained")
			# Measure actual preview CPU work separately from the display's frame cap.
			canvas._process(0.0)
			var elapsed: int = Time.get_ticks_usec() - start
			if batch >= 4 and batch < 12:
				early_us += elapsed
			elif batch >= 56:
				late_us += elapsed
			await _frames(1)
		print("DRAWING_PERF layer=%s early_batch_us=%d late_batch_us=%d samples=2049" % [layer_id, early_us / 8, late_us / 8])
		_check(late_us <= early_us * 4 + 40000, "preview update cost does not grow with gesture history")
		canvas._layer_drawers[layer_id].draw.disconnect(count_redraw)
		await _frames()
		await RenderingServer.frame_post_draw
		var pixel: Vector2i = Vector2i(canvas.global_position + center + Vector2(0, -16))
		var preview_color: Color = root.get_texture().get_image().get_pixelv(pixel)
		_button(canvas, point, false)
		_check(Input.use_accumulated_input == original_accumulation, "release restores input accumulation")
		await _frames(3)
		await RenderingServer.frame_post_draw
		var committed_color: Color = root.get_texture().get_image().get_pixelv(pixel)
		_check(absf(preview_color.r - committed_color.r) < 0.025,
			"self-overlapping translucent preview agrees with committed artwork")
		_check(preview_color.r > 0.3 and preview_color.r < 0.65,
			"overlapping batches apply gesture opacity only once")
		await RenderingServer.frame_post_draw
		var hole: Color = root.get_texture().get_image().get_pixelv(Vector2i(canvas.global_position + center))
		_check(absf(hole.r - AtlasCanvas.EMPTY_COLOR.r) < 0.015, "loop preserves its unpainted hole")
		canvas.camera_center = Vector2(4, -3)
		canvas.camera_zoom = 2.0
		canvas.queue_redraw()
		await _frames(3)
		await RenderingServer.frame_post_draw
		pixel = Vector2i(canvas.global_position + canvas.document_to_local(Vector2(0, -16)))
		var moved: Color = root.get_texture().get_image().get_pixelv(pixel)
		_check(absf(moved.r - committed_color.r) < 0.025, "camera changes rebuild view-dependent coverage")
		canvas.floor.layer_by_id(layer_id).opacity = 0.5
		canvas.queue_redraw()
		await _frames(3)
		await RenderingServer.frame_post_draw
		var faded: Color = root.get_texture().get_image().get_pixelv(pixel)
		_check(absf(faded.r - lerpf(AtlasCanvas.EMPTY_COLOR.r, committed_color.r, 0.5)) < 0.025,
			"layer opacity remains independent of gesture opacity")
		canvas.floor.layer_by_id(layer_id).opacity = 1.0
		canvas.camera_zoom = 1.0
		canvas.camera_center = Vector2.ZERO
		editor._on_undo()
		await _frames()
		_button(canvas, center, true)
		canvas.cancel_edit()
		_check(Input.use_accumulated_input == original_accumulation, "cancel restores input accumulation")
		_button(canvas, center, false)
	root.remove_child(scene)
	scene.free()
	print("ATLAS_DRAWING_PERFORMANCE_%s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
