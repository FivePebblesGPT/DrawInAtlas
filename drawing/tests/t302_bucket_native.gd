extends SceneTree
## Actual viewport pointer events on the shared standalone/Object workspace.
const RED: int = 0xff0000ff
const NEAR: int = 0xff0000f5
const BLUE: int = 0x80402010
const HIDDEN: int = 0x00112233
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T302_FAILED: " + label)

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

func seed_pixels(doc: DrawingDocument, layer: String) -> void:
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(edit.fill_rect(Rect2i(-2, 0, 4, 2), RED).ok, "signed seed")
	check(edit.fill_rect(Rect2i(1, 0, 1, 2), NEAR).ok, "near match seed")
	check(edit.fill_rect(Rect2i(2, 0, 1, 1), HIDDEN).ok, "hidden RGB seed")
	check(edit.commit().ok, "seed commit")

func capture(label: String) -> void:
	var directory: String = OS.get_environment("T302_SCREENSHOTS")
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


func rejection_cases(app: Control, canvas: Control) -> void:
	app.new_drawing()
	await frames()
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	canvas.camera = Vector2.ZERO
	canvas.zoom = 2.0
	canvas.image_bounds = Rect2i(-260, -260, 520, 520)
	var path: String = OS.get_cache_dir().path_join(DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok and not doc.is_dirty(), "clean savepoint for rejection oracle")
	DirAccess.remove_absolute(path)
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var start: int = Time.get_ticks_msec()
	click(point(canvas, Vector2i.ZERO))
	print("T302_BUDGET_REJECTION_MS: %d" % (Time.get_ticks_msec() - start))
	check(app.status.text.contains("pixel budget") and not canvas.has_pending_stroke(), "over-budget fill rejects without detached residue")
	check(doc.revision == revision and doc.history_length() == history and not doc.is_dirty() and doc.tile_keys(layer).is_empty(), "budget failure leaves saved document and tiles intact")
	canvas.image_bounds = Rect2i(-8, -8, 16, 16)
	canvas.zoom = 20.0
	canvas.bucket_tolerance = -0.01
	click(point(canvas, Vector2i.ZERO))
	check(app.status.text.contains("Invalid fill tolerance") and not doc.is_dirty() and doc.revision == revision, "invalid tolerance rejected before edit")
	canvas.bucket_tolerance = 0.0
	mouse(point(canvas, Vector2i.ZERO), true)
	check(canvas.has_pending_stroke(), "blank frame accepts a bounded preview")
	motion(point(canvas, Vector2i.ONE), false)
	mouse(point(canvas, Vector2i.ONE), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision and not doc.is_dirty(), "lost release cancels preview")
	mouse(point(canvas, Vector2i.ZERO), true)
	canvas.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	mouse(point(canvas, Vector2i.ZERO), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision and not doc.is_dirty(), "focus loss cancels preview")
	mouse(point(canvas, Vector2i.ZERO), true)
	mouse(Vector2(2, 2), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision and not doc.is_dirty(), "release outside cancels preview")
	mouse(point(canvas, Vector2i.ZERO), true)
	canvas.set_selection_mask(DrawingSelection.new(Rect2i(-2, -2, 4, 4), true))
	mouse(point(canvas, Vector2i.ZERO), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision and not doc.is_dirty(), "selection change cancels preview")
	canvas.clear_selection()
	check(doc.set_locked(layer, true).ok, "lock active raster")
	revision = doc.revision
	history = doc.history_length()
	click(point(canvas, Vector2i.ZERO))
	check(app.status.text.contains("locked") and not canvas.has_pending_stroke() and doc.revision == revision and doc.history_length() == history, "locked layer denies Bucket")
	check(doc.set_locked(layer, false).ok, "unlock active raster")
	# Real released native Brush input retains its session and journal when a
	# Bucket press is attempted before the queued samples finish draining.
	canvas.image_bounds = Rect2i(-90, -80, 180, 160)
	canvas.zoom = 2.0
	click(app.tool_buttons["Brush"].get_global_rect().get_center())
	app._set_brush_width(12.0)
	mouse(point(canvas, Vector2i(-40, 0)), true)
	for i: int in range(840):
		motion(point(canvas, Vector2i(-40 + i % 80, -20 + (i % 2) * 40)), true)
	mouse(point(canvas, Vector2i(40, 0)), false)
	var pending: DrawingEditSession = canvas.session
	check(pending != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING, "real Brush release has queued native samples")
	if pending != null:
		var count: int = pending.change_count()
		var before_size: int = pending._before.size()
		var epoch: int = pending._preview_epoch
		var native_deferred: bool = pending._hokusai_deferred
		revision = doc.revision
		history = doc.history_length()
		click(app.tool_buttons["Bucket"].get_global_rect().get_center())
		click(point(canvas, Vector2i.ZERO))
		check(canvas.session == pending and pending.change_count() == count and pending._before.size() == before_size and pending._preview_epoch == epoch and pending._hokusai_deferred == native_deferred, "Bucket cannot materialize or replace pending Brush")
		check(doc.revision == revision and doc.history_length() == history, "rejected Bucket adds no revision or history")
		canvas.cancel_gesture()
		check(doc.revision == revision and doc.history_length() == history, "discarded Brush remains unpublished")


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
	check(app.tool_buttons.has("Bucket"), "discoverable Bucket button")
	if not app.tool_buttons.has("Bucket"):
		quit(1)
		return
	var canvas: Control = app.canvas
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	seed_pixels(doc, layer)
	canvas.image_bounds = Rect2i(-8, -8, 16, 16)
	canvas.camera = Vector2.ZERO
	canvas.zoom = 22.0
	canvas.show_pixel_grid = false
	app._set_foreground(Color8(16, 32, 64, 128))
	click(app.tool_buttons["Bucket"].get_global_rect().get_center())
	await frames()
	check(app.active_tool == "Bucket" and app.top_bar.active_options == "Bucket", "pointer selects Bucket and options")
	app.bucket_tolerance_control.value = 5
	check(is_equal_approx(canvas.bucket_tolerance, 0.05), "tolerance control routes to canvas")
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var selected: DrawingSelection = DrawingSelection.new(Rect2i(-2, 0, 4, 2), true)
	selected.combine_rectangle(Rect2i(0, 1, 1, 1), "Subtract")
	canvas.set_selection_mask(selected)
	mouse(point(canvas, Vector2i(-1, 0)), true)
	await frames()
	check(canvas.has_pending_stroke() and doc.revision == revision and read(doc, layer, Vector2i(0, 0)) == RED, "press previews without publication")
	await capture("bucket-preview")
	escape()
	mouse(point(canvas, Vector2i(-1, 0)), false)
	check(not canvas.has_pending_stroke() and doc.revision == revision and doc.history_length() == history, "Escape cancels atomically")
	click(point(canvas, Vector2i(-1, 0)))
	await frames()
	check(doc.revision == revision + 1 and doc.history_length() == history + 1, "one fill history event")
	check(read(doc, layer, Vector2i(-2, 0)) == BLUE and read(doc, layer, Vector2i(0, 0)) == BLUE and read(doc, layer, Vector2i(1, 0)) == BLUE, "signed seam and tolerant near match retain exact replacement alpha")
	check(read(doc, layer, Vector2i(0, 1)) == RED and read(doc, layer, Vector2i(2, 0)) == HIDDEN, "mask hole and hidden RGB preserved")
	app._undo()
	check(read(doc, layer, Vector2i(-1, 0)) == RED and read(doc, layer, Vector2i(1, 0)) == NEAR and app.active_tool == "Bucket", "Undo restores source bytes and tool context")
	app._redo()
	check(read(doc, layer, Vector2i(1, 0)) == BLUE, "Redo restores fill")
	canvas.clear_selection()
	app.bucket_tolerance_control.value = 0
	click(point(canvas, Vector2i(-4, -4)))
	check(read(doc, layer, Vector2i(-8, -8)) == BLUE and read(doc, layer, Vector2i(7, 7)) == BLUE and read(doc, layer, Vector2i(8, 7)) == 0, "transparent region fills only inside image frame")
	check(read(doc, layer, Vector2i(2, 0)) == HIDDEN, "exact zero tolerance preserves distinct hidden RGB")
	await frames()
	await capture("bucket-committed")
	app.new_object()
	await frames()
	canvas.camera = Vector2.ZERO
	canvas.zoom = 20.0
	doc = app.current_document()
	layer = app.current_layer()
	seed_pixels(doc, layer)
	revision = doc.revision
	history = doc.history_length()
	click(point(canvas, Vector2i(4, 4)))
	check(doc.revision == revision and doc.history_length() == history and not canvas.has_pending_stroke(), "unbounded Object blank rejected")
	click(point(canvas, Vector2i(-1, 0)))
	check(read(doc, layer, Vector2i(0, 0)) == BLUE and read(doc, layer, Vector2i(1, 0)) == NEAR, "Object editor shares exact Bucket path")
	await frames()
	await capture("bucket-object")
	root.size = Vector2i(800, 600)
	await frames(12)
	await capture("bucket-narrow")
	root.size = Vector2i(1280, 795)
	root.content_scale_factor = 1.5
	await frames(12)
	await capture("bucket-hidpi")
	root.content_scale_factor = 1.0
	await frames(12)
	await rejection_cases(app, canvas)
	print("T302_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	root.remove_child(app)
	app.free()
	quit(0 if failures == 0 else 1)
