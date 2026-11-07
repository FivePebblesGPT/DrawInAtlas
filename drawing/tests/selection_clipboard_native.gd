extends SceneTree
## T-088: actual X11/Mesa frame readback and viewport-delivered pointer/keys.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T088_NATIVE_FAILED: " + label)


func frames(count: int = 4) -> void:
	for index: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func position(canvas: Control, pixel: Vector2) -> Vector2:
	return canvas.global_position + canvas.pixel_to_position(pixel)


func button(canvas: Control, pixel: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position(canvas, pixel)
	event.global_position = event.position
	root.push_input(event, true)


func motion(canvas: Control, pixel: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position(canvas, pixel)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func key(code: Key, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.ctrl_pressed = ctrl
	root.push_input(event, true)


func color(canvas: Control, pixel: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var location: Vector2i = Vector2i(position(canvas, pixel))
	if image == null or image.is_empty() or location.x < 0 or location.y < 0 or \
		location.x >= image.get_width() or location.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(location)


func delta(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func percentile(values: Array[float], fraction: float) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)] \
		if not sorted.is_empty() else -1.0


func pixel(doc: DrawingDocument, layer: String, x: int, y: int) -> int:
	var fetched: DrawingResult = doc.read_pixel(layer, x, y)
	return int(fetched.value) if fetched.ok else -1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display is mandatory")
		quit(1)
		return
	root.size = Vector2i(1010, 740)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_persistence_enabled = false
	root.add_child(workspace)
	await frames(8)
	var canvas: Control = workspace.canvas
	canvas.zoom = 4.0
	canvas.camera = Vector2.ZERO
	canvas.show_grid = false
	canvas.snap_to_grid = false
	var doc: DrawingDocument = workspace.current_document()
	var layer: String = workspace.current_layer()
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(seed._stage(-17, 0, 0xff188fe0).ok and
		seed._stage(-16, 0, 0xff188fe0).ok and
		seed._stage(-15, 0, 0xff188fe0).ok and
		seed._stage(-14, 0, 0xff188fe0).ok and seed.commit().ok,
		"seed exact colored pixels across negative 16px seam")
	await frames()
	var start_dirty: bool = doc.is_dirty()
	var start_revision: int = doc.revision
	var start_history: int = doc.history_length()

	# Select clicking empty does NOT make a 1px selection. Clicking outside an
	# existing selection deselects without creating a document edit.
	workspace._change_tool("Select")
	button(canvas, Vector2(20.5, 20.5), true)
	button(canvas, Vector2(20.5, 20.5), false)
	check(not canvas.selected.has_area() and not canvas.selection_mask.enabled,
		"single click empty does not select a 1px square")
	check(doc.revision == start_revision and doc.is_dirty() == start_dirty and
		doc.history_length() == start_history, "empty click changes no content or history")
	button(canvas, Vector2(-18.5, -1.5), true)
	motion(canvas, Vector2(-14.5, 1.5))
	await frames(2)
	check(canvas.selected == Rect2i() and canvas.selecting and canvas._marquee_dragged,
		"marquee draws a detached preview until pointer release")
	button(canvas, Vector2(-14.5, 1.5), false)
	check(canvas.selection_mask.enabled and canvas.selected.has_point(Vector2i(-17, 0)) and
		canvas.selected.has_point(Vector2i(-15, 0)), "native drag makes intended area")
	check(doc.revision == start_revision and doc.history_length() == start_history,
		"selection-only rectangle is non-dirty with history toggle off")
	button(canvas, Vector2(20.5, 20.5), true)
	button(canvas, Vector2(20.5, 20.5), false)
	check(not canvas.selected.has_area(), "click outside active marquee deselects")

	# Add and subtract through real drags, leaving a hole at -15.
	button(canvas, Vector2(-18.5, -1.5), true)
	motion(canvas, Vector2(-14.5, 1.5))
	button(canvas, Vector2(-14.5, 1.5), false)
	workspace._set_selection_mode("Subtract")
	button(canvas, Vector2(-15.5, -1.5), true)
	motion(canvas, Vector2(-14.5, 1.5))
	button(canvas, Vector2(-14.5, 1.5), false)
	check(canvas.selection_mask.allows(Vector2i(-17, 0)) and
		not canvas.selection_mask.allows(Vector2i(-15, 0)),
		"Subtract drag produces channel hole, not merely bounding rectangle")
	workspace._set_selection_mode("Add")
	button(canvas, Vector2(1.5, -1.5), true)
	motion(canvas, Vector2(3.5, 1.5))
	button(canvas, Vector2(3.5, 1.5), false)
	check(canvas.selection_mask.allows(Vector2i(2, 0)) and
		not canvas.selection_mask.allows(Vector2i(-15, 0)),
		"Add drag creates second selectable island without filling hole")
	workspace._set_selection_mode("Replace")

	# Masked brush edits exact source pixels before release, but not committed
	# document bytes. The live preview respects deselected pixels.
	workspace._change_tool("Brush")
	canvas.brush_width = 1.0
	canvas.color_rgba = 0xffffbb22
	var original: int = pixel(doc, layer, -17, 0)
	var untouched: int = pixel(doc, layer, -15, 0)
	var frame_before: Color = color(canvas, Vector2(-17.5, 0.5))
	button(canvas, Vector2(-17.5, 0.5), true)
	motion(canvas, Vector2(-14.5, 0.5))
	await frames(5)
	var in_progress: Color = color(canvas, Vector2(-17.5, 0.5))
	check(canvas.session != null and pixel(doc, layer, -17, 0) == original and
		pixel(doc, layer, -15, 0) == untouched,
		"masked stroke stays detached under held mouse")
	check(delta(in_progress, frame_before) > 0.15,
		"selected brush pixel visibly updates in framebuffer before release")
	button(canvas, Vector2(-14.5, 0.5), false)
	await frames(6)
	check(canvas.session == null and pixel(doc, layer, -17, 0) != original and
		pixel(doc, layer, -15, 0) == untouched,
		"masked stroke commits only selected pixels; hole unchanged")
	var post_stroke_revision: int = doc.revision
	workspace._undo()
	check(doc.revision == post_stroke_revision + 1 and pixel(doc, layer, -17, 0) == original,
		"stroke is one undo step and revision stays monotonic")
	workspace._redo()
	check(pixel(doc, layer, -17, 0) != original,
		"redo restores masked paint")

	# The Move ghost is an actual detached composited source-clear + target-
	# paste edit, never a screen-space overlay. Cancellation restores framebuffer.
	workspace._change_tool("Eraser")
	var eraser_old: int = pixel(doc, layer, -17, 0)
	var protected_hole: int = pixel(doc, layer, -15, 0)
	var before_eraser_frame: Color = color(canvas, Vector2(-17.5, 0.5))
	button(canvas, Vector2(-17.5, 0.5), true)
	motion(canvas, Vector2(-14.5, 0.5))
	await frames(5)
	check(canvas.session != null and pixel(doc, layer, -17, 0) == eraser_old and
		delta(color(canvas, Vector2(-17.5, 0.5)), before_eraser_frame) > 0.08,
		"held-button Eraser previews masked source removal without commit")
	button(canvas, Vector2(-14.5, 0.5), false)
	await frames(4)
	check(pixel(doc, layer, -17, 0) == 0 and pixel(doc, layer, -15, 0) == protected_hole,
		"Eraser clears selected pixels but not channel hole")
	workspace._undo()
	check(pixel(doc, layer, -17, 0) == eraser_old,
		"Eraser is one undoable mask-constrained content operation")

	workspace._change_tool("Move")
	await frames(4)
	var src: Vector2 = Vector2(-17.5, 0.5)
	var dest: Vector2 = Vector2(-8.5, 0.5)
	var before_move_source: Color = color(canvas, src)
	var before_move_dest: Color = color(canvas, dest)
	var move_rev: int = doc.revision
	button(canvas, src, true)
	motion(canvas, dest)
	await frames(5)
	check(canvas._move_preview != null and doc.revision == move_rev and
		pixel(doc, layer, -8, 0) == 0, "Move has uncommitted session while mouse is down")
	var ghost_source: Color = color(canvas, src)
	var ghost_destination: Color = color(canvas, dest)
	check(delta(ghost_source, before_move_source) > 0.08 and
		delta(ghost_destination, before_move_dest) > 0.08,
		"held-button Move clears source and draws destination at layer depth")
	key(KEY_ESCAPE)
	await frames()
	check(canvas._move_preview == null and doc.revision == move_rev and
		pixel(doc, layer, -17, 0) != 0,
		"Escape cancels Move with no document publication")
	check(delta(color(canvas, src), before_move_source) < 0.05 and
		delta(color(canvas, dest), before_move_dest) < 0.05,
		"canceled Move leaves no compositing ghost")
	# First release ends the pointer drag, NOT the detached floating piece.
	var intermediate: Vector2 = Vector2(-10.5, 0.5)
	button(canvas, src, true)
	motion(canvas, intermediate)
	await frames(5)
	button(canvas, intermediate, false)
	await frames(5)
	check(canvas.has_floating_move() and canvas._move_preview != null and
		doc.revision == move_rev and pixel(doc, layer, -17, 0) != 0 and
		pixel(doc, layer, -10, 0) == 0,
		"mouse-up retains detached floating pixels without source publication")
	check(canvas.selection_mask.allows(Vector2i(-10, 0)) and
		canvas.selection_mask.allows(Vector2i(9, 0)),
		"floating selection mask translates with the first drag, including island")
	check(delta(color(canvas, intermediate), before_move_dest) > 0.08,
		"floating pixels stay visible in framebuffer after mouse release")
	# Second drag must accumulate from original source, never recapture the
	# previously cleared preview or leave an extra copy behind.
	button(canvas, intermediate, true)
	motion(canvas, dest)
	await frames(3)
	button(canvas, dest, false)
	await frames(5)
	check(canvas.has_floating_move() and doc.revision == move_rev and
		canvas._move_preview_offset == Vector2i(9, 0) and
		pixel(doc, layer, -8, 0) == 0 and pixel(doc, layer, -17, 0) != 0,
		"second drag accumulates without publishing or resampling the source")
	check(canvas.selection_mask.allows(Vector2i(-8, 0)) and
		canvas.selection_mask.allows(Vector2i(11, 0)) and
		not canvas.selection_mask.allows(Vector2i(-6, 0)),
		"translated mask preserves subtract hole and distant Add island")
	key(KEY_ENTER)
	await frames(5)
	check(not canvas.has_floating_move() and canvas._move_preview == null and
		doc.revision == move_rev + 1 and pixel(doc, layer, -17, 0) == 0 and
		pixel(doc, layer, -8, 0) != 0 and pixel(doc, layer, -10, 0) == 0,
		"Enter commits one exact source-to-final-target transaction")
	check(canvas.selected.has_point(Vector2i(-8, 0)) and
		canvas.selection_mask.allows(Vector2i(11, 0)),
		"confirmed Move retains complete translated mask")
	workspace._undo()
	check(pixel(doc, layer, -17, 0) != 0 and pixel(doc, layer, -8, 0) == 0 and
		canvas.selection_mask.allows(Vector2i(-17, 0)),
		"Move undo restores original pixels and mask context")
	workspace._redo()
	check(pixel(doc, layer, -8, 0) != 0 and
		canvas.selection_mask.allows(Vector2i(-8, 0)),
		"Move redo restores pixel destination and selection context")

	# Escape after release cancels the entire next floating transaction.
	var prior_confirmed_revision: int = doc.revision
	button(canvas, dest, true)
	motion(canvas, Vector2(-5.5, 0.5))
	button(canvas, Vector2(-5.5, 0.5), false)
	await frames(3)
	check(canvas.has_floating_move() and doc.revision == prior_confirmed_revision,
		"third gesture can float existing confirmed selection")
	key(KEY_ESCAPE)
	await frames(3)
	check(not canvas.has_floating_move() and doc.revision == prior_confirmed_revision and
		pixel(doc, layer, -8, 0) != 0 and pixel(doc, layer, -5, 0) == 0 and
		canvas.selection_mask.allows(Vector2i(-8, 0)),
		"Escape after mouse-up restores original pixels and mask without history")

	canvas.grab_focus()
	key(KEY_C, true)
	await frames(1)
	check(workspace.drawing_clipboard != null and workspace.drawing_clipboard.width > 0,
		"Ctrl+C reaches active-layer Drawing clipboard")
	var before_cut: int = doc.revision
	key(KEY_X, true)
	await frames(3)
	check(doc.revision == before_cut + 1 and pixel(doc, layer, -8, 0) == 0,
		"Ctrl+X cuts selected pixels in one transaction")
	key(KEY_V, true)
	await frames(3)
	check(pixel(doc, layer, 0, 8) != 0 and canvas.selected.has_point(Vector2i(0, 8)),
		"Ctrl+V places and selects translated active-layer paste")
	canvas.grab_focus()
	key(KEY_DELETE)
	await frames(2)
	check(pixel(doc, layer, 0, 8) == 0, "Delete key clears selected pixels")
	workspace._undo()
	check(pixel(doc, layer, 0, 8) != 0, "Undo restores keyboard Delete")

	# Zoom and negative seam navigation remain source aligned; selection only
	# changes never modify .drawing storage or the save/open roundtrip.
	var preview_frame_ms: Array[float] = []
	workspace._change_tool("Move")
	for scale: float in [0.5, 1.0, 2.0, 4.0]:
		canvas.zoom = scale
		canvas.camera = Vector2.ZERO
		canvas.set_selection_mask(DrawingSelection.new(Rect2i(0, 8, 1, 1), true), false)
		canvas.queue_redraw()
		await frames(3)
		check(canvas.position_to_pixel(canvas.pixel_to_position(Vector2(-16.4, 0.2))) ==
			Vector2i(-17, 0), "negative storage seam maps consistently at zoom %.2f" % scale)
		var before_test: int = doc.revision
		button(canvas, Vector2(0.5, 8.5), true)
		var started_us: int = Time.get_ticks_usec()
		motion(canvas, Vector2(2.5, 8.5))
		await process_frame
		await RenderingServer.frame_post_draw
		var observed_us: int = Time.get_ticks_usec()
		preview_frame_ms.append(float(observed_us - started_us) / 1000.0)
		check(canvas._move_preview != null and doc.revision == before_test and
			pixel(doc, layer, 0, 8) != 0,
			"held-button Move publishes no pixels at zoom %.2f" % scale)
		key(KEY_ESCAPE)
		await frames(2)
		check(canvas._move_preview == null and doc.revision == before_test,
			"Escape cancels source-space Move at zoom %.2f" % scale)
	var saved: String = ProjectSettings.globalize_path("user://t088-native.drawing")
	check(DrawingFileIO.save(doc, saved).ok, "native pointer-edited document saves")
	var reopened: DrawingResult = DrawingFileIO.open(saved)
	check(reopened.ok and pixel(reopened.value as DrawingDocument, layer, 0, 8) != 0,
		"native Ctrl+V/Undo content survives file reopen")
	workspace.queue_free()
	await frames(2)
	print("T088_NATIVE_PREVIEW_TO_FRAME_POST_DRAW_MS p50=%.3f p95=%.3f n=%d (software upper-bound, not input-to-photon)" % [
		percentile(preview_frame_ms, 0.50), percentile(preview_frame_ms, 0.95), preview_frame_ms.size()])
	print("T088_NATIVE: %d checks; %d failed (Godot %s, display %s, 1010x740, zoom 50/100/200/400%%)" % [
		checks, failures, Engine.get_version_info().get("string", ""), DisplayServer.get_name()])
	if failures == 0:
		print("T088_NATIVE_PASSED")
	quit(1 if failures else 0)
