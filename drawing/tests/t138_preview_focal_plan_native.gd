extends SceneTree
## Real software X11 framebuffer and cache retention under an over-budget draft.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T138_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int = 3) -> void:
	for _i: int in range(n):
		await process_frame

func pixel(canvas: Control, at: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var pos: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(at))
	if image == null or image.is_empty() or pos.x < 0 or pos.y < 0 \
			or pos.x >= image.get_width() or pos.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(pos)

func fill_chunk() -> PackedByteArray:
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(128 * 128 * 4)
	for i: int in range(128 * 128):
		pixels.encode_u32(i * 4, 0xffb04c31)
	return pixels

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires native X11 framebuffer")
		quit(1)
		return
	root.size = Vector2i(1230, 920)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var doc: DrawingDocument = DrawingDocument.new("t138-overbudget-preview", 128)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var data: PackedByteArray = fill_chunk()
	var digest: String = DrawingRasterTile.digest_rgba8(data, 128)
	var loader: Callable = func(_ref: String) -> PackedByteArray: return data
	var registered: bool = true
	for y: int in range(-6, 6):
		for x: int in range(-8, 8):
			if x == 0 and y == 0:
				continue # Preview-only center tile must compete with committed textures.
			if not doc.register_lazy_chunk(layer, x, y, "%d,%d" % [x, y], digest, loader).ok:
				registered = false
	check(registered and doc.tile_keys(layer).size() == 191,
		"191 real signed source chunks registered around a preview-only hole")
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(42, 40)
	canvas.size = Vector2(1080, 800)
	canvas.zoom = 0.5
	canvas.tool = "Pan"
	canvas.set_process(false)
	canvas._metrics.merge({"preview_frames": 0, "compose_cpu_us": 0,
		"texture_cpu_us": 0, "preview_index_cpu_us": 0,
		"bytes_uploaded": 0, "first_preview_submit_us": 0,
		"frame_phase_total": 0, "frame_phases_us": []}, true)
	canvas.document = doc
	canvas.layer_id = layer
	root.add_child(canvas)
	canvas.set_process(false)
	await frames(4)
	var committed: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(committed.get("focal_plan_tiles", 0)) == 144,
		"over-budget committed view uses existing focal retention")
	check(int(committed.get("cache_tiles", 999)) <= 144,
		"committed view keeps 144-texture cache limit")
	var revision: int = doc.revision
	var draft: DrawingEditSession = doc.begin_edit(layer, revision).value as DrawingEditSession
	check(draft.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]),
		0xffee5520, 12.0).ok, "stage preview-only blue pixel")
	canvas.session = draft
	canvas.queue_redraw()
	await frames(4)
	var first: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(first.get("preview_index_built", 0)) == 1 and
		int(first.get("preview_index_keys", 0)) > 0,
		"live preview supplies a complete display index")
	check(int(first.get("tiles_visible", 0)) > 144,
		"native viewport exceeds retained texture capacity")
	check(int(first.get("focal_plan_tiles", 0)) == 144,
		"complete over-budget preview uses 144-entry focal retention plan")
	check(int(first.get("cache_tiles", 999)) <= 144 and
		int(first.get("cache_bytes_estimate", 999999999)) <= int(first.get("cache_limit_bytes", -1)),
		"preview cache and bytes remain bounded")
	check(int(first.get("cold_budgeted", -1)) == 0 and
		int(first.get("cold_tiles_deferred", -1)) == 0,
		"over-budget preview continues rendering without deferred gaps")
	check(canvas._display_tiles.has("0,0"),
		"near-focus preview-only display texture is retained")
	check(pixel(canvas, Vector2(0.5, 0.5)).b > 0.6,
		"blue detached pixel appears in real framebuffer")
	check(pixel(canvas, Vector2(-64.5, -64.5)).r > 0.14,
		"committed signed source remains in framebuffer")
	check(doc.revision == revision and int(doc.read_pixel(layer, 0, 0).value) == 0,
		"preview remains detached from committed source and history")
	canvas.camera = Vector2(128, 0)
	canvas.queue_redraw()
	await frames(3)
	var shifted: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(shifted.get("focal_plan_tiles", 0)) == 144,
		"panning with complete preview continues focal preselection")
	check(int(shifted.get("cache_tiles", 999)) <= 144 and
		int(shifted.get("cold_tiles_deferred", -1)) == 0,
		"panned preview respects cache bound and full-frame fallback")
	draft.cancel()
	canvas.session = null
	canvas.camera = Vector2.ZERO
	canvas.queue_redraw()
	await frames(4)
	check(pixel(canvas, Vector2(0.5, 0.5)).b < 0.4 and
		pixel(canvas, Vector2(-64.5, -64.5)).r > 0.14,
		"cancellation clears draft while keeping committed signed source")
	var permanent: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(permanent.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]),
		0xffee5520, 12.0).ok and permanent.commit().ok,
		"same pixel can be published as a separate edit")
	canvas.queue_redraw()
	await frames(4)
	check(pixel(canvas, Vector2(0.5, 0.5)).b > 0.6,
		"committed blue pixel appears after preview cancellation")
	check(doc.undo().ok, "Undo committed edit")
	canvas.queue_redraw()
	await frames(4)
	check(pixel(canvas, Vector2(0.5, 0.5)).b < 0.4,
		"Undo restores exact empty center")
	check(doc.redo().ok, "Redo committed edit")
	canvas.queue_redraw()
	await frames(4)
	check(pixel(canvas, Vector2(0.5, 0.5)).b > 0.6,
		"Redo restores center source pixel")
	print("T138_NATIVE_METRICS " + JSON.stringify({"committed": committed,
		"preview": first, "shifted": shifted}))
	print("T138_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
