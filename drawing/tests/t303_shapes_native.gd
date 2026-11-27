extends SceneTree
## Actual viewport pointer events on the shared standalone/Object workspace.
const RED: int = 0xff0000ff
const BLUE: int = 0x80402010
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T303_FAILED: " + label)

func frames(count: int = 3) -> void:
	for i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func click(point: Vector2) -> void:
	mouse(point, true)
	mouse(point, false)

func escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)

func point(canvas: Control, pixel: Vector2i) -> Vector2:
	return canvas.global_position + canvas.pixel_to_position(Vector2(pixel) + Vector2(0.5, 0.5))

func read(doc: DrawingDocument, layer: String, pixel: Vector2i) -> int:
	return int(doc.read_pixel(layer, pixel.x, pixel.y).value)

func capture(label: String) -> void:
	var directory: String = OS.get_environment("T303_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join(label + ".png")) != OK:
		printerr("OPTIONAL_VISUAL_CAPTURE_FAILED: " + label)

func motion(position: Vector2, held: bool) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)


func press_key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)


func drag(canvas: Control, a: Vector2i, b: Vector2i, release: bool = true) -> void:
	mouse(point(canvas, a), true)
	motion(point(canvas, b), true)
	if release:
		mouse(point(canvas, b), false)


func set_kind(app: Control, index: int) -> void:
	app.shape_kind_control.select(index)
	app.shape_kind_control.item_selected.emit(index)


func set_style(app: Control, index: int) -> void:
	app.shape_style_control.select(index)
	app.shape_style_control.item_selected.emit(index)


func set_pigment(app: Control, index: int) -> void:
	app.shape_color_control.select(index)
	app.shape_color_control.item_selected.emit(index)


func fresh(app: Control, canvas: Control) -> void:
	app.new_drawing()
	await frames()
	canvas.image_bounds = Rect2i(-12, -12, 24, 24)
	canvas.camera = Vector2.ZERO
	canvas.zoom = 18.0
	canvas.show_pixel_grid = false
	canvas.clear_selection()
	app._change_tool("Shapes")
	root.warp_mouse(point(canvas, Vector2i(-5, -5)))
	await frames()


func begin_example(canvas: Control, kind: int) -> void:
	if kind == 2:
		for vertex: Vector2i in [Vector2i(-5, -5), Vector2i(5, -5), Vector2i(0, 5)]:
			click(point(canvas, vertex))
	else:
		drag(canvas, Vector2i(-5, -5), Vector2i(5, 5), false)


func finish_example(canvas: Control, kind: int) -> void:
	if kind == 2:
		press_key(KEY_ENTER)
	else:
		mouse(point(canvas, Vector2i(5, 5)), false)


## Independent source/preview comparison at every pixel, not visual bounds.
func snapshot(doc: DrawingDocument, layer: String, edit: DrawingEditSession = null) -> PackedInt64Array:
	var pixels: PackedInt64Array = PackedInt64Array()
	var stride: int = doc.tile_stride
	for y: int in range(-8, 9):
		for x: int in range(-8, 9):
			var rgba: int = read(doc, layer, Vector2i(x, y))
			if edit != null:
				var key: String = DrawingDocument.TILES.tile_key64(x, y, stride)
				var offset: Vector2i = DrawingDocument.TILES.local_offset64(x, y, stride)
				rgba = int(edit.preview_tile(key).get(offset.y * stride + offset.x, rgba))
			pixels.append(rgba)
	return pixels


func shape_matrix(app: Control, canvas: Control) -> void:
	for kind: int in range(3):
		for style: int in range(2):
			await fresh(app, canvas)
			set_kind(app, kind)
			set_style(app, style)
			set_pigment(app, 1)
			app.shape_width_control.value = 1
			var doc: DrawingDocument = app.current_document()
			var layer: String = app.current_layer()
			var inside: Vector2i = Vector2i(-1, 0) if style == 0 else Vector2i(-1, -5)
			var excluded: Vector2i = Vector2i(0, 0) if style == 0 else Vector2i(0, -5)
			var base: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
			check(base.fill_rect(Rect2i(inside, Vector2i.ONE), RED).ok and base.commit().ok, "seed opaque source for exact blend")
			var mask: DrawingSelection = DrawingSelection.new(Rect2i(-7, -7, 14, 14), true)
			mask.combine_rectangle(Rect2i(excluded, Vector2i.ONE), "Subtract")
			canvas.set_selection_mask(mask)
			var revision: int = doc.revision
			var history: int = doc.history_length()
			var before: PackedInt64Array = snapshot(doc, layer)
			begin_example(canvas, kind)
			await frames()
			check(canvas.session != null and canvas.session.change_count() > 0 and snapshot(doc, layer) == before, "detached %d/%d" % [kind, style])
			var preview: PackedInt64Array = snapshot(doc, layer, canvas.session)
			finish_example(canvas, kind)
			check(doc.revision == revision + 1 and doc.history_length() == history + 1 and snapshot(doc, layer) == preview, "exact preview/commit and one history entry %d/%d" % [kind, style])
			check(read(doc, layer, inside) == 0xff201087 and read(doc, layer, excluded) == 0, "source-over RGBA8 and mask %d/%d" % [kind, style])
			if style == 1 and kind == 0:
				check(read(doc, layer, Vector2i(-1, -6)) == 0 and read(doc, layer, Vector2i(-1, -4)) == 0, "one-pixel rectangular stroke does not paint two adjacent rows")
			app._undo()
			check(snapshot(doc, layer) == before and app.active_tool == "Shapes", "exact Undo and tool context %d/%d" % [kind, style])
			app._redo()
			check(snapshot(doc, layer) == preview, "exact Redo %d/%d" % [kind, style])
			check(doc.set_locked(layer, true).ok, "lock %d/%d" % [kind, style])
			revision = doc.revision
			history = doc.history_length()
			begin_example(canvas, kind)
			finish_example(canvas, kind)
			check(doc.revision == revision and doc.history_length() == history and snapshot(doc, layer) == preview and not canvas.has_pending_stroke(), "locked rejection %d/%d" % [kind, style])


func interruption_cases(app: Control, canvas: Control) -> void:
	await fresh(app, canvas)
	set_kind(app, 0)
	set_style(app, 0)
	set_pigment(app, 0)
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var before: PackedInt64Array = snapshot(doc, layer)
	mouse(point(canvas, Vector2i(-5, -5)), true)
	var opening: DrawingEditSession = canvas.session
	for i: int in range(20):
		motion(point(canvas, Vector2i(2 + i % 4, 3)), true)
	check(opening != null and canvas.session == opening and opening.change_count() == 0, "motion burst coalesces before frame staging")
	await frames()
	check(canvas.session.change_count() > 0, "latest motion stages on frame")
	mouse(point(canvas, Vector2i(5, 5)), false)
	check(read(doc, layer, Vector2i(5, 5)) == RED and doc.revision == revision + 1, "release commits latest coordinate")
	app._undo()
	revision = doc.revision
	history = doc.history_length()
	for kind: int in range(3):
		set_kind(app, kind)
		begin_example(canvas, kind)
		await frames()
		canvas.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		finish_example(canvas, kind)
		check(not canvas.has_pending_stroke() and doc.revision == revision and doc.history_length() == history and snapshot(doc, layer) == before, "focus cancellation %d" % kind)
		begin_example(canvas, kind)
		await frames()
		canvas.set_selection_mask(DrawingSelection.new(Rect2i(-1, -1, 2, 2), true))
		finish_example(canvas, kind)
		check(not canvas.has_pending_stroke() and doc.revision == revision and snapshot(doc, layer) == before, "selection change cancels %d" % kind)
		canvas.clear_selection()
		begin_example(canvas, kind)
		await frames()
		set_style(app, 1)
		finish_example(canvas, kind)
		check(not canvas.has_pending_stroke() and doc.revision == revision, "style change cancels %d" % kind)
		set_style(app, 0)
	set_kind(app, 1)
	drag(canvas, Vector2i(0, 0), Vector2i(4, 0))
	check(not canvas.has_pending_stroke() and doc.revision == revision, "degenerate ellipse")
	set_kind(app, 0)
	drag(canvas, Vector2i(-4, -4), Vector2i(4, 4), false)
	motion(point(canvas, Vector2i(4, 4)), false)
	mouse(point(canvas, Vector2i(4, 4)), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision, "lost release cancels rectangle")
	set_kind(app, 2)
	for vertex: Vector2i in [Vector2i(-5, -5), Vector2i(5, 4), Vector2i(4, -5), Vector2i(-5, 5)]:
		click(point(canvas, vertex))
	press_key(KEY_ENTER)
	check(not canvas.has_pending_stroke() and doc.revision == revision, "self-intersecting polygon rejected")
	for vertex: Vector2i in [Vector2i(-5, -5), Vector2i(5, -5), Vector2i(0, 5), Vector2i(5, 5)]:
		click(point(canvas, vertex))
	press_key(KEY_BACKSPACE)
	check(canvas._shape_vertices.size() == 3 and canvas.session.change_count() > 0, "Backspace restores three-vertex preview")
	click(point(canvas, Vector2i(-5, -5)))
	check(not canvas.has_pending_stroke() and doc.revision == revision + 1 and read(doc, layer, Vector2i(0, 0)) == RED, "click first vertex closes once")
	app._undo()
	revision = doc.revision
	set_kind(app, 0)
	canvas.image_bounds = Rect2i(-350, -350, 700, 700)
	canvas.zoom = 0.5
	var start: int = Time.get_ticks_msec()
	drag(canvas, Vector2i(-300, -300), Vector2i(300, 300))
	print("T303_BUDGET_REJECTION_MS: %d" % (Time.get_ticks_msec() - start))
	check(not canvas.has_pending_stroke() and doc.revision == revision and snapshot(doc, layer) == before, "over-budget shape rejected before publishing")
	# Preserve a real released native Brush session while the toolbar changes.
	canvas.image_bounds = Rect2i(-90, -80, 180, 160)
	canvas.zoom = 2.0
	app._change_tool("Brush")
	app._set_brush_width(12.0)
	mouse(point(canvas, Vector2i(-40, 0)), true)
	for i: int in range(840):
		motion(point(canvas, Vector2i(-40 + i % 80, -20 + (i % 2) * 40)), true)
	mouse(point(canvas, Vector2i(40, 0)), false)
	var pending: DrawingEditSession = canvas.session
	check(pending != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING, "released native Brush still queued")
	if pending != null:
		var count: int = pending.change_count()
		var epoch: int = pending._preview_epoch
		var journal: bool = pending._hokusai_deferred
		app._change_tool("Shapes")
		drag(canvas, Vector2i(-4, -4), Vector2i(4, 4))
		check(canvas.session == pending and pending.change_count() == count and pending._preview_epoch == epoch and pending._hokusai_deferred == journal, "Shapes cannot replace or materialize pending Brush")
		canvas.cancel_gesture()
		check(doc.revision == revision and snapshot(doc, layer) == before, "queued Brush and rejected shape never published")


func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "real display and mandatory native extension required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 795)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(12)
	check(app.tool_buttons.has("Shapes"), "discoverable Shapes button")
	if not app.tool_buttons.has("Shapes"):
		quit(1)
		return
	var canvas: Control = app.canvas
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	canvas.image_bounds = Rect2i(-12, -12, 24, 24)
	canvas.camera = Vector2.ZERO
	canvas.zoom = 18.0
	canvas.show_pixel_grid = false
	app._set_foreground(Color8(255, 0, 0))
	app._set_background(Color8(16, 32, 64, 128))
	click(app.tool_buttons["Shapes"].get_global_rect().get_center())
	await frames()
	check(app.active_tool == "Shapes" and app.top_bar.active_options == "Shapes", "pointer opens Shapes options")
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-8, -8, 16, 16), true)
	mask.combine_rectangle(Rect2i(0, 0, 1, 1), "Subtract")
	canvas.set_selection_mask(mask)
	drag(canvas, Vector2i(-4, -3), Vector2i(3, 3), false)
	await frames()
	check(canvas.has_pending_stroke() and canvas.session.change_count() > 0 and doc.revision == revision and read(doc, layer, Vector2i(-1, 0)) == 0, "rectangle preview detached")
	await capture("rectangle-preview")
	escape()
	mouse(point(canvas, Vector2i(3, 3)), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision and doc.history_length() == history, "rectangle Escape leaves no edit")
	drag(canvas, Vector2i(-4, -3), Vector2i(3, 3))
	check(doc.revision == revision + 1 and doc.history_length() == history + 1, "rectangle commits once")
	check(read(doc, layer, Vector2i(-4, -3)) == RED and read(doc, layer, Vector2i(3, 3)) == RED and read(doc, layer, Vector2i(4, 3)) == 0 and read(doc, layer, Vector2i(0, 0)) == 0, "exact signed rectangle and mask hole")
	app._undo()
	check(read(doc, layer, Vector2i(-1, 0)) == 0 and app.active_tool == "Shapes", "Undo restores signed pixels and mode")
	app._redo()
	check(read(doc, layer, Vector2i(-1, 0)) == RED, "Redo restores rectangle")
	app._undo()
	canvas.clear_selection()
	app.shape_kind_control.select(1)
	app.shape_kind_control.item_selected.emit(1)
	app.shape_color_control.select(1)
	app.shape_color_control.item_selected.emit(1)
	check(canvas.shape_kind == "Ellipse" and canvas.shape_use_background, "contextual ellipse and BG options")
	revision = doc.revision
	drag(canvas, Vector2i(-5, -4), Vector2i(4, 3), false)
	await frames()
	check(canvas.session.change_count() > 0 and doc.revision == revision, "ellipse detached preview")
	await capture("ellipse-preview")
	escape()
	mouse(point(canvas, Vector2i(4, 3)), false)
	check(doc.revision == revision and not canvas.has_pending_stroke(), "ellipse Escape")
	drag(canvas, Vector2i(-5, -4), Vector2i(4, 3))
	check(read(doc, layer, Vector2i(0, 0)) == BLUE and read(doc, layer, Vector2i(-1, 0)) == BLUE and read(doc, layer, Vector2i(-5, -4)) == 0, "ellipse center exact BG RGBA8, corners empty, signed seam")
	app._undo()
	app.shape_kind_control.select(2)
	app.shape_kind_control.item_selected.emit(2)
	app.shape_color_control.select(0)
	app.shape_color_control.item_selected.emit(0)
	app.shape_style_control.select(1)
	app.shape_style_control.item_selected.emit(1)
	app.shape_width_control.value = 2
	check(canvas.shape_kind == "Polygon" and canvas.shape_style == "Stroke" and canvas.shape_width == 2, "polygon outline and width controls")
	revision = doc.revision
	for vertex: Vector2i in [Vector2i(-5, -4), Vector2i(5, -4), Vector2i(0, 5)]:
		click(point(canvas, vertex))
	await frames()
	check(canvas.has_pending_stroke() and canvas.session.change_count() > 0 and doc.revision == revision, "polygon fixed vertices preview without release commit")
	await capture("polygon-preview")
	escape()
	check(not canvas.has_pending_stroke() and doc.revision == revision, "polygon Escape")
	for vertex: Vector2i in [Vector2i(-5, -4), Vector2i(5, -4), Vector2i(0, 5)]:
		click(point(canvas, vertex))
	press_key(KEY_ENTER)
	check(doc.revision == revision + 1 and read(doc, layer, Vector2i(-1, -4)) == RED and read(doc, layer, Vector2i(0, 0)) == 0, "polygon one commit, signed stroke, hollow center")
	app._undo()
	check(read(doc, layer, Vector2i(-1, -4)) == 0, "polygon Undo")
	app._redo()
	check(read(doc, layer, Vector2i(-1, -4)) == RED, "polygon Redo")
	app._undo()
	revision = doc.revision
	for vertex: Vector2i in [Vector2i(-4, 0), Vector2i(0, 0), Vector2i(4, 0)]:
		click(point(canvas, vertex))
	press_key(KEY_ENTER)
	check(doc.revision == revision and not canvas.has_pending_stroke(), "degenerate polygon rejected")
	app.shape_kind_control.select(0)
	app.shape_kind_control.item_selected.emit(0)
	drag(canvas, Vector2i(0, 0), Vector2i(0, 4))
	check(doc.revision == revision and not canvas.has_pending_stroke(), "degenerate rectangle rejected")
	check(doc.set_locked(layer, true).ok, "lock target")
	revision = doc.revision
	drag(canvas, Vector2i(-4, -4), Vector2i(4, 4))
	check(doc.revision == revision and not canvas.has_pending_stroke(), "locked raster rejected")
	check(doc.set_locked(layer, false).ok, "unlock target")
	app.shape_style_control.select(0)
	app.shape_style_control.item_selected.emit(0)
	canvas.image_bounds = Rect2i(-2, -2, 4, 4)
	drag(canvas, Vector2i(-4, -4), Vector2i(4, 4))
	check(read(doc, layer, Vector2i(-2, -2)) == RED and read(doc, layer, Vector2i(2, 0)) == 0 and read(doc, layer, Vector2i(-3, 0)) == 0, "frame clipping")
	root.size = Vector2i(800, 600)
	await frames(12)
	await capture("shapes-narrow")
	app.shape_style_control.select(1)
	app.shape_style_control.item_selected.emit(1)
	var top: Control = app.top_bar
	var before_scroll: int = top.options_scroll.scroll_horizontal
	for i: int in range(4):
		if top.right_cue.visible and not top.right_cue.disabled:
			var target: Vector2 = top.right_cue.get_global_rect().get_center()
			root.warp_mouse(target)
			await frames()
			click(target)
			await frames()
	check(top.options_scroll.scroll_horizontal > before_scroll, "narrow overflow chevron is a reachable pointer target")
	var before_width: float = canvas.shape_width
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.position = app.shape_width_control.get_global_rect().get_center()
	wheel.global_position = wheel.position
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.warp_mouse(wheel.position)
	await frames()
	root.push_input(wheel, true)
	await frames()
	check(canvas.shape_width == before_width + 1, "scrolled stroke width responds to real wheel input")
	await capture("shapes-narrow-options")
	root.size = Vector2i(1280, 795)
	root.content_scale_factor = 1.5
	await frames(12)
	await capture("shapes-hidpi")
	root.content_scale_factor = 1.0
	await frames(12)
	await shape_matrix(app, canvas)
	await interruption_cases(app, canvas)
	print("T303_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	root.remove_child(app)
	app.free()
	quit(0 if failures == 0 else 1)
