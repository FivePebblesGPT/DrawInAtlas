extends SceneTree
## T-221: real X11 input dispatch, command-to-frame timing, framebuffer,
## content history and non-content Deselect through the standalone workspace.

const COLOR: int = 0xff1b7fda
const MARK: Vector2i = Vector2i(8, 7)
const BOUNDS: Rect2i = Rect2i(-32, -32, 512, 512)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T221_NATIVE_FAILED: " + name)


func frames(n: int = 2) -> void:
	for i: int in range(n):
		await process_frame
	await RenderingServer.frame_post_draw


func send_key(code: Key, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.ctrl_pressed = ctrl
	root.push_input(event, true)
	var release: InputEventKey = event.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release, true)


func sample(canvas: Control) -> Color:
	var image: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position +
		canvas.pixel_to_position(Vector2(MARK) + Vector2(0.5, 0.5)))
	return image.get_pixelv(point)


func p(samples: Array[int], rate: float) -> int:
	var ordered: Array[int] = samples.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(float(ordered.size()) * rate) - 1, 0, ordered.size() - 1)]


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display is mandatory")
		quit(1)
		return
	root.size = Vector2i(1010, 720)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(8)
	var canvas: Control = app.canvas
	canvas.zoom = 4.0
	canvas.camera = Vector2.ZERO
	canvas.show_grid = false
	canvas.snap_to_grid = false
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(seed._stage(MARK.x, MARK.y, COLOR).ok and
		seed._stage(-1, -1, 0x00aabbcc).ok and seed.commit().ok,
		"seed opaque and hidden RGB across signed tiles")
	var selection: DrawingSelection = DrawingSelection.new(BOUNDS, true)
	canvas.set_selection_mask(selection)
	await frames(4)
	var before_color: Color = sample(canvas)
	var initial_history: int = doc.history_length()
	var delete_us: Array[int] = []
	var warm_color: Color
	for i: int in range(7):
		canvas.grab_focus()
		var previous: int = doc.revision
		var start: int = Time.get_ticks_usec()
		send_key(KEY_DELETE)
		await frames(2)
		delete_us.append(Time.get_ticks_usec() - start)
		warm_color = sample(canvas)
		check(int(doc.read_pixel(layer, MARK.x, MARK.y).value) == 0 and
			int(doc.read_pixel(layer, -1, -1).value) == 0 and
			doc.revision == previous + 1 and canvas.selection_mask.enabled,
			"Delete shortcut clears content, retains selection, one revision, trial %d" % i)
		send_key(KEY_Z, true)
		await frames(2)
		check(int(doc.read_pixel(layer, MARK.x, MARK.y).value) == COLOR and
			int(doc.read_pixel(layer, -1, -1).value) == 0x00aabbcc,
			"shortcut Undo restores exact RGBA, trial %d" % i)
	check(before_color != warm_color, "framebuffer changes when opaque selected pixel is erased")
	check(doc.history_length() == initial_history + 1,
		"seven Delete/Undo cycles reuse one redo position")
	var deselect_us: Array[int] = []
	for i: int in range(7):
		canvas.set_selection_mask(selection)
		await frames(2)
		canvas.grab_focus()
		var revision: int = doc.revision
		var history: int = doc.history_length()
		var began: int = Time.get_ticks_usec()
		send_key(KEY_D, true)
		await frames(2)
		deselect_us.append(Time.get_ticks_usec() - began)
		check(not canvas.selection_mask.enabled and doc.revision == revision and
			doc.history_length() == history and
			int(doc.read_pixel(layer, MARK.x, MARK.y).value) == COLOR,
			"Ctrl+D does not dirty document or remove pixels, trial %d" % i)
	canvas.set_selection_mask(selection)
	await frames(2)
	var capture_status: int = root.get_texture().get_image().save_png("/mnt/data/t221-selection-native.png")
	if capture_status != OK:
		print("OPTIONAL_VISUAL_CAPTURE_FAILED: drawing/tests/t221_selection_delete_native.gd: " + str(capture_status))
	print("T221_NATIVE_BENCH: X11 1010x720 zoom=4, input-to-render 7 samples")
	print("T221_NATIVE_BENCH: Delete p50=%d us p95=%d us samples=%s" % [p(delete_us, 0.5), p(delete_us, 0.95), delete_us])
	print("T221_NATIVE_BENCH: Deselect p50=%d us p95=%d us samples=%s" % [p(deselect_us, 0.5), p(deselect_us, 0.95), deselect_us])
	print("T221_NATIVE: %d checks, %d failures" % [checks, failures])
	if failures == 0 and checks >= 25:
		print("T221_NATIVE_PASSED")
	app.queue_free()
	await frames(2)
	quit(1 if failures else 0)
