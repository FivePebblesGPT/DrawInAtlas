extends SceneTree
## Software-X11 viewport witness: large sparse zoom, exact pixels and fallback.
## No physical display timing or input-to-photon claim.

var checks: int = 0
var failures: int = 0
var sampled_draw_us: Array[int] = []


func check(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("T135_NATIVE_FAILED: " + label)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func paint(doc: DrawingDocument, layer: String, area: Rect2i, pixel: int) -> bool:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(area.size.x * area.size.y * 4)
	for index: int in range(area.size.x * area.size.y):
		bytes.encode_u32(index * 4, pixel)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return false
	var edit: DrawingEditSession = started.value as DrawingEditSession
	return edit.apply_region(area, bytes).ok and edit.commit().ok


func sample(canvas: Control, source: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var at: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(source))
	if image == null or image.is_empty() or at.x < 0 or at.y < 0 \
			or at.x >= image.get_width() or at.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(at)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real X11 framebuffer is required")
		quit(1)
		return
	root.size = Vector2i(820, 610)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(28, 28)
	canvas.size = Vector2(512, 384)
	canvas.zoom = 0.25
	canvas.tool = "Pan"
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t135-sparse", 256)
	var bottom: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Bottom").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	check(paint(doc, bottom, Rect2i(-90, -90, 82, 82), 0xff2020ef),
		"red signed-area source committed")
	check(paint(doc, top, Rect2i(8, 8, 82, 82), 0xffee5520),
		"blue positive-area source committed")
	canvas.document = doc
	canvas.layer_id = bottom
	await frames(4)
	var left: Color = sample(canvas, Vector2(-48, -48))
	var right: Color = sample(canvas, Vector2(48, 48))
	check(left.r > 0.7 and left.b < 0.3 and right.b > 0.7,
		"signed red and positive blue compositing visible in native framebuffer")
	canvas.zoom = 0.01
	canvas.queue_redraw()
	await frames(4)
	var sparse: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(sparse.get("tiles_visible", 0)) > 50000,
		"cold zoom exposes over fifty thousand display cells")
	check(int(sparse.get("sparse_draw", 0)) == 1,
		"known committed sparse occupancy selects indexed draw")
	check(int(sparse.get("tiles_examined", 99999)) < 32,
		"indexed draw actually visits only the bounded occupied tile set")
	check(int(sparse.get("empty_skipped", 0)) >= int(sparse.get("tiles_visible", 0)) - 32,
		"empty tiles remain omitted without allocating textures")
	check(canvas._display_tiles.size() <= canvas.MAX_DISPLAY_TILES,
		"retained display textures stay bounded")
	check(int(sparse.get("visible_layer_plan_builds", 2)) <= 1,
		"multiple sparse display tiles share one visible layer plan")
	for i: int in range(7):
		canvas.queue_redraw()
		await frames(2)
		sampled_draw_us.append(int(canvas.last_frame_metrics.get("draw_cpu_us", -1)))
	check(sampled_draw_us.size() == 7 and sampled_draw_us.min() >= 0,
		"seven repeat-frame CPU timing samples recorded")
	canvas.zoom = 0.25
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(-48, -48)).r > 0.7 and
		sample(canvas, Vector2(48, 48)).b > 0.7,
		"zoom cycle preserves both exact source color areas")
	# Unknown/invalid occupancy must retain the original conservative path.
	canvas._occupancy_unknown = true
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics.get("sparse_draw", 1)) == 0,
		"unknown occupancy safely bypasses sparse enumeration")
	check(sample(canvas, Vector2(-48, -48)).r > 0.7,
		"unknown occupancy does not hide existing visible pixels")
	canvas._rebuild_occupancy()
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics.get("sparse_draw", 1)) == 1,
		"restored complete occupancy re-enables the sparse draw path")
	var expected_revision: int = doc.revision
	check(paint(doc, bottom, Rect2i(-40, -40, 1, 1), 0xff28f028),
		"one-pixel signed edit committed independently of renderer")
	canvas.queue_redraw()
	await frames()
	check(doc.revision == expected_revision + 1 and
		int(canvas.last_frame_metrics.get("sparse_draw", 0)) == 1,
		"dirty source revision revalidates sparse display without full-window scan")
	canvas.zoom = 4.0
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(-39.5, -39.5)).g > 0.65,
		"one-pixel source edit appears in native framebuffer")
	check(doc.undo().ok and doc.redo().ok,
		"Undo and Redo retain canonical source transactions")
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(-39.5, -39.5)).g > 0.65,
		"Redo pixel remains visible after sparse viewport reuse")
	canvas.zoom = 0.25
	canvas.queue_redraw()
	await frames()
	check(doc.set_visibility(top, false).ok,
		"top-layer visibility changes invalidate source occupancy")
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(48, 48)).b < 0.4,
		"hidden top layer cannot leave stale cached texture")
	check(doc.set_visibility(top, true).ok,
		"top-layer visibility can be restored")
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(48, 48)).b > 0.7,
		"restored top layer becomes visible again")
	var samples_ms: Array[float] = []
	for value: int in sampled_draw_us:
		samples_ms.append(float(value) / 1000.0)
	samples_ms.sort()
	print("T135_NATIVE_TIMING " + JSON.stringify({"engine": Engine.get_version_info().get("string"),
		"zoom": 0.01, "visible_tiles": sparse.get("tiles_visible"),
		"tiles_examined": sparse.get("tiles_examined"),
		"warm_draw_ms": samples_ms, "p50_ms": samples_ms[3], "p95_ms": samples_ms[6]}))
	print("T135_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
