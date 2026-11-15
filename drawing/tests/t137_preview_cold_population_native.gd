extends SceneTree
## Real X11 cold preview frame budget, progressive completion and framebuffer parity.
var checks: int = 0
var failures: int = 0
var collected: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T137_NATIVE_FAILED: " + label)

func frames(n: int = 2) -> void:
	for _i: int in range(n):
		await process_frame

func pixel(canvas: Control, at: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var screen: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(at))
	if image == null or image.is_empty() or screen.x < 0 or screen.y < 0 \
			or screen.x >= image.get_width() or screen.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(screen)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real X11 display required")
		quit(1)
		return
	root.size = Vector2i(780, 600)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var doc: DrawingDocument = DrawingDocument.new("t137-cold-preview", 256)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var committed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	var positions: Array[Vector2] = [
		Vector2(-500.5, -190.5), Vector2(-380.5, 60.5),
		Vector2(-255.5, -190.5), Vector2(-130.5, 60.5),
		Vector2(-5.5, -190.5), Vector2(130.5, 60.5),
		Vector2(255.5, -190.5), Vector2(380.5, 60.5),
		Vector2(500.5, -190.5)]
	var prepared: bool = true
	for point: Vector2 in positions:
		if not committed.paint_path(PackedVector2Array([point]), 0xff2233ed, 12.0).ok:
			prepared = false
	check(prepared and committed.commit().ok, "nine committed signed source tiles prepared")
	var base_revision: int = doc.revision
	var draft: DrawingEditSession = doc.begin_edit(layer, base_revision).value as DrawingEditSession
	check(draft.paint_path(PackedVector2Array([Vector2(0.5, 260.5)]),
		0xffdd2233, 12.0).ok, "detached preview in a new display tile")
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(24, 24)
	canvas.size = Vector2(600, 450)
	canvas.zoom = 0.5
	canvas.tool = "Pan"
	canvas.set_process(false)
	canvas._metrics.merge({"preview_frames": 0, "compose_cpu_us": 0,
		"texture_cpu_us": 0, "preview_index_cpu_us": 0,
		"bytes_uploaded": 0, "first_preview_submit_us": 0,
		"frame_phase_total": 0, "frame_phases_us": []}, true)
	canvas.document = doc
	canvas.layer_id = layer
	canvas.session = draft
	root.add_child(canvas)
	canvas.set_process(false)
	await frames(3)
	var first: Dictionary = canvas.last_frame_metrics.duplicate()
	collected.append(first)
	check(int(first.get("preview_index_built", 0)) == 1,
		"real detached preview provides complete index")
	check(int(first.get("cold_budgeted", 0)) == 1,
		"preview cold population is frame-budgeted")
	check(int(first.get("tiles_composited", 99)) > 0 and
		int(first.get("tiles_composited", 99)) <= 4,
		"first native frame composites at most four cold tiles")
	check(int(first.get("cold_tiles_deferred", 0)) >= 5,
		"other cold tiles are explicitly deferred to later frames")
	var settled: bool = false
	for index: int in range(12):
		canvas.queue_redraw()
		await frames(2)
		collected.append(canvas.last_frame_metrics.duplicate())
		if int(canvas.last_frame_metrics.get("cold_tiles_deferred", 0)) == 0:
			settled = true
			break
	check(settled, "bounded cold preview settles in subsequent draw frames")
	check(doc.revision == base_revision and int(doc.read_pixel(layer, 0, 260).value) == 0,
		"settled preview does not modify canonical source or revision")
	check(pixel(canvas, Vector2(0.5, 260.5)).b > 0.6,
		"preview-only blue pixel appears in final framebuffer")
	check(pixel(canvas, Vector2(-5.5, -190.5)).r > 0.6,
		"committed red pixel appears in final framebuffer")
	check(canvas._display_tiles.size() <= canvas.MAX_DISPLAY_TILES,
		"retained GPU cache remains bounded")
	draft.cancel()
	canvas.session = null
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(0.5, 260.5)).b < 0.4 and
		pixel(canvas, Vector2(-5.5, -190.5)).r > 0.6,
		"preview cancellation removes only detached pixels")
	var commit_blue: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(commit_blue.paint_path(PackedVector2Array([Vector2(0.5, 260.5)]),
		0xffdd2233, 12.0).ok and commit_blue.commit().ok,
		"same pixels can commit as a separate transaction")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(0.5, 260.5)).b > 0.6,
		"committed blue appears in framebuffer")
	check(doc.undo().ok, "Undo source transaction")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(0.5, 260.5)).b < 0.4,
		"Undo removes blue without changing committed red")
	check(doc.redo().ok, "Redo source transaction")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(0.5, 260.5)).b > 0.6,
		"Redo restores blue source pixel")
	print("T137_NATIVE_METRICS " + JSON.stringify({"first": first,
		"frames": collected.size(), "final": canvas.last_frame_metrics}))
	print("T137_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
