extends SceneTree
## T-253 end-to-end 512² real-window Delete and Deselect: input to
## first updated OS framebuffer, not a detached eight-pixel microbenchmark.

const RED: int = 0xff0000ff
const HIDDEN: int = 0x00224466
const BOUNDS: Rect2i = Rect2i(-256, -256, 512, 512)
const RECTS: Array[Rect2i] = [Rect2i(-188, -150, 110, 195),
	Rect2i(76, -151, 95, 230), Rect2i(-80, 130, 260, 110)]
const PROTECTED: Vector2i = Vector2i(-100, -100)
const HIDDEN_POINT: Vector2i = Vector2i(10, 105)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T253_NATIVE_FAILED: " + label)


func frames(count: int = 2) -> void:
	for i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func key(code: Key, ctrl: bool = false) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.pressed = true
	down.keycode = code
	down.ctrl_pressed = ctrl
	root.push_input(down, true)
	var up: InputEventKey = down.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up, true)


func pixel(doc: DrawingDocument, layer: String, point: Vector2i) -> int:
	var result: DrawingResult = doc.read_pixel(layer, point.x, point.y)
	return int(result.value) if result.ok else -1


func percentile(times: Array[int], fraction: float) -> int:
	var ordered: Array[int] = times.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(float(times.size()) * fraction) - 1, 0, times.size() - 1)]


func seed_dense_source(doc: DrawingDocument, layer: String) -> int:
	var amount: int = 0
	for area: Rect2i in RECTS:
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				var key: String = DrawingDocument.TILES.tile_key64(x, y, doc.tile_stride)
				var tile: DrawingRasterTile = doc._nodes[layer].tiles.get(key)
				if tile == null:
					tile = DrawingRasterTile.new(doc.tile_stride)
					doc._nodes[layer].tiles[key] = tile
				var local: Vector2i = DrawingDocument.TILES.local_offset64(x, y, doc.tile_stride)
				tile.sparse_pixels()[local.y * doc.tile_stride + local.x] = RED
				amount += 1
	var key: String = DrawingDocument.TILES.tile_key64(HIDDEN_POINT.x, HIDDEN_POINT.y,
		doc.tile_stride)
	var tile: DrawingRasterTile = doc._nodes[layer].tiles.get(key)
	if tile == null:
		tile = DrawingRasterTile.new(doc.tile_stride)
		doc._nodes[layer].tiles[key] = tile
	var local: Vector2i = DrawingDocument.TILES.local_offset64(HIDDEN_POINT.x,
		HIDDEN_POINT.y, doc.tile_stride)
	tile.sparse_pixels()[local.y * doc.tile_stride + local.x] = HIDDEN
	return amount + 1


func capture(label: String) -> void:
	var directory: String = OS.get_environment("T253_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var capture_status: int = root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	if capture_status != OK:
		print("OPTIONAL_VISUAL_CAPTURE_FAILED: drawing/tests/t253_selection_delete_native.gd: " + str(capture_status))


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real window required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 795)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(12)
	var canvas: Control = app.canvas
	canvas.zoom = 1.19
	canvas.camera = Vector2.ZERO
	canvas.show_grid = false
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	var filled: int = seed_dense_source(doc, layer)
	# Test fixture inserts immutable source only before any edit; force the
	# viewer to rebuild, since no document transaction was recorded for seeding.
	canvas._cache_revision = -1
	canvas._display_tiles.clear()
	canvas.queue_redraw()
	var selected: DrawingSelection = DrawingSelection.new(BOUNDS, true)
	check(selected.combine_rectangle(Rect2i(PROTECTED, Vector2i.ONE), "Subtract"),
		"mask hole protects an occupied red pixel")
	canvas.set_selection_mask(selected)
	await frames(6)
	check(filled > 70000 and doc.tile_keys(layer).size() == 4,
		"71,901-pixel owner-like 512² source occupies four tiles")
	check(pixel(doc, layer, PROTECTED) == RED and pixel(doc, layer, HIDDEN_POINT) == HIDDEN,
		"source includes protected red and selected hidden RGB")
	await capture("before-delete")
	var sample_point: Vector2i = Vector2i(canvas.global_position +
		canvas.pixel_to_position(Vector2(-180.0, -140.0) + Vector2(0.5, 0.5)))
	var source_frame: Color = root.get_texture().get_image().get_pixelv(sample_point)
	check(source_frame.r > 0.9 and source_frame.g < 0.1 and source_frame.b < 0.1,
		"pre-Delete OS framebuffer visibly contains the dense red sample")
	var baseline_history: int = doc.history_length()
	var delete_us: Array[int] = []
	var undo_us: Array[int] = []
	for trial: int in range(7):
		canvas.grab_focus()
		var previous: int = doc.revision
		var start: int = Time.get_ticks_usec()
		key(KEY_DELETE)
		await frames(1)
		delete_us.append(Time.get_ticks_usec() - start)
		if trial == 0:
			var erased_frame: Color = root.get_texture().get_image().get_pixelv(sample_point)
			check(erased_frame != source_frame and erased_frame.r < 0.9,
				"first updated OS framebuffer visibly erases the same source pixel")
			await capture("after-delete")
		check(doc.revision == previous + 1 and doc.history_length() == baseline_history + 1,
			"Delete produces exactly one atomic history command %d" % trial)
		check(pixel(doc, layer, PROTECTED) == RED and
			pixel(doc, layer, HIDDEN_POINT) == 0 and
			pixel(doc, layer, Vector2i(-180, -140)) == 0,
			"Delete preserves mask hole, clears hidden RGB and red content %d" % trial)
		check(doc._native_raster_store != null,
			"tile authority is native after first dense Delete %d" % trial)
		canvas.grab_focus()
		var undo_start: int = Time.get_ticks_usec()
		key(KEY_Z, true)
		await frames(1)
		undo_us.append(Time.get_ticks_usec() - undo_start)
		check(pixel(doc, layer, HIDDEN_POINT) == HIDDEN and
			pixel(doc, layer, Vector2i(-180, -140)) == RED and
			pixel(doc, layer, PROTECTED) == RED,
			"Undo restores exact source data and mask hole %d" % trial)
	# Deselect never edits pixels or advances history, independently of Delete.
	var deselect_us: Array[int] = []
	for trial: int in range(7):
		canvas.set_selection_mask(selected)
		await frames(1)
		canvas.grab_focus()
		var previous_revision: int = doc.revision
		var previous_history: int = doc.history_length()
		var began: int = Time.get_ticks_usec()
		key(KEY_D, true)
		await frames(1)
		deselect_us.append(Time.get_ticks_usec() - began)
		check(not canvas.selection_mask.enabled and doc.revision == previous_revision and
			doc.history_length() == previous_history,
			"Ctrl+D changes selection only %d" % trial)
	canvas.set_selection_mask(selected)
	await frames(2)
	await capture("after-undo")
	print("T253_X11_INPUT_TO_FRAME: size=512x512 occupied=%d tiles=%d engine=%s" % [
		filled, doc.tile_keys(layer).size(), Engine.get_version_info().get("string", "")])
	print("T253_X11_INPUT_TO_FRAME: Delete p50=%d p95=%d max=%d us samples=%s" % [
		percentile(delete_us, 0.5), percentile(delete_us, 0.95), delete_us.max(), delete_us])
	print("T253_X11_INPUT_TO_FRAME: Undo p50=%d p95=%d us samples=%s" % [
		percentile(undo_us, 0.5), percentile(undo_us, 0.95), undo_us])
	print("T253_X11_INPUT_TO_FRAME: Deselect p50=%d p95=%d us samples=%s" % [
		percentile(deselect_us, 0.5), percentile(deselect_us, 0.95), deselect_us])
	# A true 1 s frozen main thread violates this even in slow software X11.
	check(percentile(delete_us, 0.95) < 500000,
		"Delete complete real X11 input-to-frame p95 below 500ms")
	print("T253_NATIVE: %d checks; %d failures" % [checks, failures])
	if failures == 0 and checks >= 40:
		print("T253_NATIVE_PASSED")
	app.queue_free()
	await frames(2)
	quit(1 if failures else 0)
