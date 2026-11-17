extends SceneTree
## T-187: single-native-raster direct RGBA preview must match the fallback
## compositor exactly. Hidden RGB, multiple layers and signed tile origins
## must never escape that fallback. Exercise the real graphical native path.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T187_DIRECT_FAILED: " + description)


func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _initialize() -> void:
	call_deferred("run")


func trial(hidden_rgb: bool, extra_layer: bool) -> void:
	var doc: DrawingDocument = DrawingDocument.new("t187-preview-%s-%s" % [hidden_rgb, extra_layer], 256)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Native", "root").value)
	var source: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.1, 0.6, 0.3, 0.7))
	var rgba: PackedByteArray = source.get_data()
	if hidden_rgb:
		# The legacy renderer skips alpha-zero pixels; raw image blitting
		# would leak the deliberately retained hidden RGB into output bytes.
		rgba[0] = 0x58
		rgba[1] = 0xa3
		rgba[2] = 0xeb
		rgba[3] = 0
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(edit.apply_region(Rect2i(-256, 0, 256, 256), rgba).ok and edit.commit().ok,
		"seed source with straight alpha and optional hidden RGB")
	if extra_layer:
		var upper: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Upper", "root").value)
		var overlay: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		overlay.fill(Color(0.2, 0.1, 0.9, 0.5))
		var over_edit: DrawingEditSession = doc.begin_edit(upper, doc.revision).value
		check(over_edit.apply_region(Rect2i(-256, 0, 128, 128), overlay.get_data()).ok \
			and over_edit.commit().ok, "second composited layer")
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(12, 12)
	canvas.size = Vector2(860, 700)
	canvas.camera = Vector2(-128, 128)
	canvas.zoom = 1.0
	canvas.brush_width = 22
	canvas.brush_preset = "hard"
	canvas.color_rgba = 0xff2211ee
	canvas.document = doc
	canvas.layer_id = layer
	root.add_child(canvas)
	for i: int in range(7):
		await frame()
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-220, 35)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(-207, 42)))
	for i: int in range(9):
		await frame()
	var active: DrawingEditSession = canvas.session
	check(active != null and active._native_tiles != null,
		"real Rust-backed preview remains open")
	if active == null or active._native_tiles == null:
		canvas.queue_free()
		return
	# The Canvas already populated its preview during the nine warm frames.
	# Clear only detached *read* caches to measure each explicit render call.
	active._native_preview_cache.clear()
	active._native_preview_regions.clear()
	var before_stats: Dictionary = active._native_tiles.call("stats")
	var view: Rect2i = Rect2i(-256, 0, 128, 128)
	var optimized: DrawingResult = DrawingRenderer.render(doc, view, 0, 0, 1048576, active)
	check(optimized.ok, "direct candidate renderer returns complete image")
	var crop_count: int = active._native_preview_regions.size()
	var after_direct: Dictionary = active._native_tiles.call("stats")
	active._native_preview_cache.clear()
	OS.set_environment("DRAWING_T187_FULL_TILE_COUNTERFACTUAL", "1")
	var fallback: DrawingResult = DrawingRenderer.render(doc, view, 0, 0, 1048576, active)
	OS.unset_environment("DRAWING_T187_FULL_TILE_COUNTERFACTUAL")
	check(fallback.ok, "forced original per-pixel compositor returns image")
	if optimized.ok and fallback.ok:
		check((optimized.value as Image).get_data() == (fallback.value as Image).get_data(),
			"direct and original renderer match exact RGBA8, including source alpha")
		if hidden_rgb:
			check((optimized.value as Image).get_data().decode_u32(0) == 0,
				"hidden RGB at alpha zero is not displayed as source color")
	var after_fallback: Dictionary = active._native_tiles.call("stats")
	if hidden_rgb or extra_layer:
		check(crop_count == (0 if extra_layer else 1),
			"multilayer skips direct read; hidden case probes then falls back")
		check(int(after_direct["bytes_exported"]) - int(before_stats["bytes_exported"]) >= 262144,
			"fallback exports a complete tile")
	else:
		check(crop_count == 1, "fast path caches one signed 128px RGBA crop")
		check(int(after_direct["bytes_exported"]) - int(before_stats["bytes_exported"]) == 65536,
			"fast path exports only 128 x 128 RGBA8 pixels")
	check(int(after_fallback["bytes_exported"]) > int(after_direct["bytes_exported"]),
		"same-binary forced fallback reads native full tile")
	# Arbitrary repeated tile-local viewport crops must not accumulate an
	# unbounded per-tile detached RGBA cache during a long native gesture.
	var storage_key: String = DrawingDocument.TILES.tile_key64(-256, 0, doc.tile_stride)
	for i: int in range(20):
		var tiny: Dictionary = active.preview_rgba8_region(storage_key,
			Rect2i(i, 0, 1, 1))
		check((tiny.get("bytes", PackedByteArray()) as PackedByteArray).size() == 4,
			"bounded preview crop returns exact one-pixel RGBA8 data")
	check((active._native_preview_regions.get(storage_key, {}) as Dictionary).size() <= 8,
		"arbitrary render offsets cannot expand per-tile crop cache past eight")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(-207, 42)))
	for i: int in range(160):
		if canvas.session == null:
			break
		await frame()
	check(canvas.session == null, "native gesture commits after preview comparison")
	if canvas.session == null:
		var saved: DrawingResult = DrawingRenderer.render(doc, view)
		check(saved.ok and saved.value != null, "committed pixels still render")
		check(doc.undo().ok and doc.redo().ok, "native edit Undo/Redo survives fast path")
	canvas.queue_free()
	await process_frame


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "graphical native path required")
		quit(1)
		return
	root.size = Vector2i(920, 780)
	root.content_scale_size = root.size
	check(ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"native Brush and tile store loaded")
	await trial(false, false)
	await trial(true, false)
	await trial(false, true)
	print("T187_DIRECT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T187_DIRECT_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
