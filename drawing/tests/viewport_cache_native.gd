extends SceneTree
## T-086: actual X11/Vulkan-compatible Godot Control texture paths with
## framebuffer readback. Never substitute headless render-unit pixels.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_NATIVE_FAILED: " + label)


func frames(count: int = 3) -> void:
	for i: int in range(count):
		await process_frame


func sample(canvas: Control, point: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var pixel: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(point))
	if image == null or image.is_empty() or pixel.x < 0 or pixel.y < 0 \
			or pixel.x >= image.get_width() or pixel.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(pixel)


func mouse_button(canvas: Control, point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(point)
	event.global_position = event.position
	root.push_input(event, true)


func mouse_motion(canvas: Control, point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + canvas.pixel_to_position(point)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func patch(doc: DrawingDocument, layer: String, area: Rect2i, channels: PackedByteArray) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	for i: int in range(area.size.x * area.size.y):
		bytes.append_array(channels)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "begin seeded pixel edit")
	if not started.ok:
		return
	var edit: DrawingEditSession = started.value as DrawingEditSession
	check(edit.apply_region(area, bytes).ok and edit.commit().ok, "publish seeded pixels")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real framebuffer required")
		quit(1)
		return
	root.size = Vector2i(640, 460)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(30, 30)
	canvas.size = Vector2(212, 164)
	canvas.zoom = 1.0
	canvas.tool = "Pan"
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t086-native")
	var low: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Low").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	patch(doc, low, Rect2i(-8, -8, 18, 18), PackedByteArray([240, 45, 25, 255]))
	patch(doc, top, Rect2i(0, 0, 8, 8), PackedByteArray([40, 100, 240, 255]))
	patch(doc, top, Rect2i(20, 20, 12, 12), PackedByteArray([40, 100, 240, 255]))
	canvas.document = doc
	canvas.layer_id = low
	await frames(5)
	var first: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(first.get("textures_created", 0)) > 0 and
		int(first.get("source_pixels_rendered", 0)) > 0,
		"first paint allocates source-aligned tiles: %s" % first)
	check(canvas._display_tiles.size() <= canvas.MAX_DISPLAY_TILES,
		"initial cache respects hard texture count")
	check(int(first.get("visible_layer_plan_builds", -1)) <= 1,
		"cold frame compiles no more than one visible-layer plan")
	var red: Color = sample(canvas, Vector2(-3.5, -3.5))
	var blue: Color = sample(canvas, Vector2(4.5, 4.5))
	check(red.r > 0.8 and red.g < 0.35 and blue.b > 0.75,
		"signed seam and top-layer visibility reach framebuffer")

	canvas.queue_redraw()
	await frames()
	var cached: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(cached["tiles_composited"]) == 0 and int(cached["textures_created"]) == 0
		and int(cached["textures_updated"]) == 0 and int(cached["cache_hits"]) > 0
		and int(cached["visible_layer_plan_builds"]) == 0,
		"cursor/selection-only redraw makes no CPU composite or GPU uploads: %s" % cached)

	canvas.camera = Vector2(4, 6)
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics["tiles_composited"]) == 0,
		"pan preserving source-tile coverage is texture reuse")
	canvas.camera = Vector2.ZERO
	canvas.zoom = 0.5
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics["tiles_composited"]) > 0,
		"first zoom-out only populates newly exposed content tiles")
	canvas.zoom = 0.25
	canvas.queue_redraw()
	await frames()
	var quarter: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(quarter["empty_skipped"]) > 0 and
		int(quarter["cache_tiles"]) <= canvas.MAX_DISPLAY_TILES,
		"25%% sparse zoom skips empty display tiles within bounded memory: %s" % quarter)
	canvas.zoom = 1.0
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics["tiles_composited"]) == 0,
		"return to 100% reuses original pixel tiles without resampling")
	check(sample(canvas, Vector2(-3.5, -3.5)).r > 0.8,
		"negative tile seam remains visible after zoom cycle")
	# The real wheel and workspace zoom path now expose 25%, not only a
	# programmatic test override of the old 50% lower clamp.
	canvas.zoom = 0.5
	for i: int in range(6):
		var wheel: InputEventMouseButton = InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = canvas.global_position + canvas.size * 0.5
		wheel.global_position = wheel.position
		root.push_input(wheel, true)
	check(is_equal_approx(canvas.zoom, 0.25),
		"native wheel reaches safe 25% minimum without dropping below it")
	canvas.zoom = 1.0
	canvas.queue_redraw()
	await frames()

	var revision: int = doc.revision
	patch(doc, low, Rect2i(-3, -3, 1, 1), PackedByteArray([35, 245, 60, 255]))
	check(doc.revision == revision + 1, "small edit changes document exactly once")
	canvas.queue_redraw()
	await frames()
	var edited: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(edited["tiles_composited"]) == 1 and int(edited["textures_updated"]) == 1
		and int(edited["textures_created"]) == 0 and int(edited["bytes_uploaded"]) == 65536
		and int(edited["visible_layer_plan_builds"]) == 1,
		"one-pixel edit updates one complete 128px display texture: %s" % edited)
	check(sample(canvas, Vector2(-2.5, -2.5)).g > red.g,
		"native framebuffer includes edited green pixel")
	var before_undo: int = doc.revision
	check(doc.undo().ok and doc.revision == before_undo + 1, "undo is monotonic")
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics["textures_updated"]) == 1,
		"undo selectively refreshes one display tile")
	check(doc.redo().ok, "redo published one-pixel update")
	canvas.queue_redraw()
	await frames()
	check(int(canvas.last_frame_metrics["textures_updated"]) == 1,
		"redo selectively refreshes one display tile")

	canvas.tool = "Brush"
	canvas.color_rgba = 0xff40e0ff
	canvas.brush_width = 8.0
	var before_preview: int = doc.revision
	mouse_button(canvas, Vector2(30.5, 30.5), true)
	await frames(4)
	var held: Dictionary = canvas.last_frame_metrics.duplicate()
	check(canvas.session != null and doc.revision == before_preview,
		"held mouse stages detached pixels only")
	check(int(held["tiles_composited"]) > 0 and int(held["tiles_composited"]) <= 4
		and int(held["textures_created"]) == 0,
		"preview reuses nearby tiles, not a full viewport rebuild: %s" % held)
	check(int(held.get("preview_index_built", 0)) == 1
		and int(held.get("preview_index_keys", 0)) > 0
		and int(held.get("preview_index_keys", 0)) <= 4
		and int(held.get("preview_index_fallback", 0)) == 0,
		"held-button frame indexes just affected display tiles: %s" % held)
	var covered_by_top: Color = sample(canvas, Vector2(30.5, 30.5))
	check(covered_by_top.b > 0.75 and covered_by_top.r < 0.4,
		"low-layer preview stays occluded by top raster content")
	mouse_motion(canvas, Vector2(40.5, 40.5))
	await frames(4)
	var highlighted: Color = sample(canvas, Vector2(40.5, 40.5))
	check(highlighted.r > 0.8 and highlighted.g > 0.6,
		"uncommitted unobscured brush pixels visible in actual framebuffer: %s" % highlighted)
	canvas.cancel_gesture()
	await frames(4)
	check(doc.revision == before_preview and int(canvas.last_frame_metrics["tiles_composited"]) <= 4,
		"cancel removes preview and reuses unaffected tiles without revision")
	check(int(canvas.last_frame_metrics.get("preview_index_built", -1)) == 0,
		"cancel discards detached preview index from subsequent redraw")
	check(sample(canvas, Vector2(40.5, 40.5)).r < 0.5,
		"no ghost brush pixel survives cancel")

	# The live index must also reach newly exposed negative tiles at 25%,
	# not just the already-cached 100% view used by the earlier dab.
	canvas.zoom = 0.25
	canvas.queue_redraw()
	await frames(3)
	var prior_quarter: int = doc.revision
	mouse_button(canvas, Vector2(-120.5, -120.5), true)
	await frames(4)
	var quarter_held: Dictionary = canvas.last_frame_metrics.duplicate()
	check(canvas.session != null and doc.revision == prior_quarter,
		"25% held stroke remains a detached uncommitted preview")
	check(int(quarter_held.get("preview_index_built", 0)) == 1
		and int(quarter_held.get("preview_index_keys", 0)) > 0
		and int(quarter_held.get("preview_index_fallback", 0)) == 0,
		"25% signed preview builds bounded display stamp index: %s" % quarter_held)
	check(sample(canvas, Vector2(-120.5, -120.5)).r > 0.7,
		"25% negative signed source tile previews in native framebuffer")
	canvas.cancel_gesture()
	canvas.pointer_known = false # Cursor outline is UI-only; inspect the actual pixel.
	canvas.queue_redraw()
	await frames(3)
	var canceled_quarter: Color = sample(canvas, Vector2(-120.5, -120.5))
	check(doc.revision == prior_quarter and canceled_quarter.r < 0.5,
		"25% canceled preview leaves no ghost pixels or history: %s" % canceled_quarter)
	canvas.zoom = 1.0
	canvas.queue_redraw()
	await frames(3)

	var with_top: Color = sample(canvas, Vector2(25.5, 25.5))
	check(doc.set_visibility(top, false).ok, "hide top layer")
	canvas.queue_redraw()
	await frames()
	var without_top: Color = sample(canvas, Vector2(25.5, 25.5))
	check(with_top.b > 0.7 and without_top.b < 0.5,
		"visibility structural revision invalidates composition globally")
	check(doc.set_visibility(top, true).ok, "show top layer")
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(25.5, 25.5)).b > 0.7,
		"restore visible layer without stale cache")
	check(doc.reorder(top, DrawingDocument.ROOT_ID, 0).ok, "move top beneath low layer")
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(4.5, 4.5)).r > 0.75,
		"layer order change invalidates composite")

	check(doc.reorder(top, DrawingDocument.ROOT_ID, 1).ok,
		"restore top layer order for alpha parity")
	patch(doc, top, Rect2i(-8, -8, 8, 8), PackedByteArray([20, 220, 70, 128]))
	canvas.queue_redraw()
	await frames()
	var alpha_frame: Color = sample(canvas, Vector2(-4.5, -4.5))
	var alpha_expected: DrawingResult = DrawingRenderer.render(doc, Rect2i(-5, -5, 1, 1))
	var alpha_rgb: Color = (alpha_expected.value as Image).get_pixel(0, 0)
	check(alpha_expected.ok and Vector3(alpha_frame.r, alpha_frame.g, alpha_frame.b).distance_to(
		Vector3(alpha_rgb.r, alpha_rgb.g, alpha_rgb.b)) < 0.08,
		"semiopaque layer blending matches canonical CPU composite in actual frame")

	# Text is not a raster tile: its glyph bounds must still populate the
	# occupancy index, then invalidate on text-tree undo/redo.
	var glyph: DrawingTextElement = DrawingTextElement.new()
	glyph.content = "A"
	glyph.font_size = 32
	glyph.position = Vector2i(-60, 20)
	glyph.color_rgba = 0xff0000ff
	var added_text: DrawingResult = doc.commit_text("", glyph, doc.revision)
	check(added_text.ok, "create visible text layer with canonical font")
	var glyph_bounds: DrawingResult = DrawingTextRaster.bounds(glyph)
	check(glyph_bounds.ok and (glyph_bounds.value as Rect2i).has_area(),
		"font glyph returns bounded source pixels")
	canvas.queue_redraw()
	await frames(4)
	if glyph_bounds.ok and (glyph_bounds.value as Rect2i).has_area():
		var glyph_area: Rect2i = glyph_bounds.value as Rect2i
		var glyph_render: DrawingResult = DrawingRenderer.render(doc, glyph_area)
		var interior: Vector2i = Vector2i(-1, -1)
		if glyph_render.ok:
			var image: Image = glyph_render.value as Image
			for y: int in range(image.get_height()):
				for x: int in range(image.get_width()):
					if image.get_pixel(x, y).a > 0.95:
						interior = Vector2i(x, y)
						break
				if interior.x >= 0:
					break
		check(interior.x >= 0, "find opaque text glyph pixel in renderer")
		if interior.x >= 0:
			var glyph_point: Vector2 = Vector2(glyph_area.position + interior) + Vector2(0.5, 0.5)
			check(sample(canvas, glyph_point).r > 0.75,
				"text survives occupancy culling in native framebuffer")
			check(doc.undo().ok, "undo text-tree creation")
			canvas.queue_redraw()
			await frames()
			check(sample(canvas, glyph_point).r < 0.3,
				"text undo removes stale glyph texture")
			check(doc.redo().ok, "redo text-tree creation")
			canvas.queue_redraw()
			await frames()
			check(sample(canvas, glyph_point).r > 0.75,
				"text redo restores glyph texture")

	# Integer-aligned texture tile boundaries must not create visual seams.
	patch(doc, low, Rect2i(126, 40, 2, 8), PackedByteArray([250, 80, 40, 255]))
	patch(doc, low, Rect2i(128, 40, 2, 8), PackedByteArray([30, 240, 80, 255]))
	canvas.camera = Vector2(128, 0)
	canvas.queue_redraw()
	await frames(4)
	check(sample(canvas, Vector2(126.5, 44.5)).r > 0.85 and
		sample(canvas, Vector2(128.5, 44.5)).g > 0.8,
		"adjacent positive 128px tile seam has correct colors without gaps")
	canvas.camera = Vector2.ZERO
	canvas.queue_redraw()
	await frames()

	# Even with a larger screen showing thousands of empty source tiles,
	# transparent regions must be skipped before their raster/texture work.
	root.size = Vector2i(1080, 760)
	canvas.size = Vector2(1000, 680)
	canvas.zoom = 0.25
	canvas.queue_redraw()
	await frames(5)
	var large: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(large["tiles_visible"]) > 300 and int(large["empty_skipped"]) > 250,
		"sparse large 25% canvas avoids blank-region composition")
	check(int(large["cache_tiles"]) <= canvas.MAX_DISPLAY_TILES and
		int(large["cache_bytes_estimate"]) <= int(large["cache_limit_bytes"]),
		"bounded software texture-payload estimate: %s" % large)

	# Exercise conservative occupancy fallback. A dense viewport can exceed
	# the retained texture budget; its overflow must stay transient rather
	# than evicting the in-view cache entries on every subsequent redraw.
	canvas.zoom = 0.5
	canvas._occupancy_unknown = true
	canvas.queue_redraw()
	await frames(5)
	var overflow_first: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(overflow_first["tiles_visible"]) > canvas.MAX_DISPLAY_TILES and
		int(overflow_first["cache_tiles"]) == canvas.MAX_DISPLAY_TILES and
		int(overflow_first["textures_transient"]) > 0,
		"conservative dense viewport honors persistent limit: %s" % overflow_first)
	canvas.queue_redraw()
	await frames(5)
	var overflow_again: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(overflow_again["cache_hits"]) >= canvas.MAX_DISPLAY_TILES and
		int(overflow_again["textures_transient"]) > 0,
		"overflow does not churn the retained in-view texture set: %s" % overflow_again)
	check(int(overflow_again["cache_bytes_estimate"]) <= int(overflow_again["cache_limit_bytes"]) and
		int(overflow_again["frame_reference_bytes_upper_bound"]) >
		int(overflow_again["cache_bytes_estimate"]),
		"transient frame draw references are measured separately from retained cache")
	check(doc.set_visibility(top, false).ok, "post-overflow structural invalidation")
	canvas.queue_redraw()
	await frames(5)
	check(int(canvas.last_frame_metrics["empty_skipped"]) > 0,
		"structural invalidation restores sparse occupancy after conservative fallback")
	check(doc.set_visibility(top, true).ok, "restore layer after overflow")
	print("T086_NATIVE_OVERFLOW %s" % overflow_again)
	root.size = Vector2i(640, 460)
	root.content_scale_size = root.size
	# Attach a lazy source tile to an otherwise cached blank document. This
	# operation deliberately does not advance the document history revision.
	var lazy_doc: DrawingDocument = DrawingDocument.new("t086-native-lazy", 16)
	var lazy_layer: String = String(lazy_doc.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	canvas.document = lazy_doc
	canvas.layer_id = lazy_layer
	canvas.zoom = 1.0
	canvas.camera = Vector2.ZERO
	canvas.size = Vector2(212, 164)
	await frames(3)
	var blank_lazy: Color = sample(canvas, Vector2(19.5, 5.5))
	var lazy_pixels: PackedByteArray = PackedByteArray()
	for i: int in range(16 * 16):
		lazy_pixels.append_array(PackedByteArray([240, 210, 35, 255]))
	var lazy_fetch: Callable = func(_reference: String) -> PackedByteArray: return lazy_pixels
	var previous_revision: int = lazy_doc.revision
	check(lazy_doc.register_lazy_chunk(lazy_layer, 1, 0, "blob",
		DrawingRasterTile.digest_rgba8(lazy_pixels, 16), lazy_fetch).ok,
		"native lazy source registration succeeds")
	check(lazy_doc.revision == previous_revision,
		"lazy source attachment preserves canonical history revision")
	canvas.queue_redraw()
	await frames(4)
	var loaded_lazy: Color = sample(canvas, Vector2(19.5, 5.5))
	check(blank_lazy.r < 0.5 and loaded_lazy.r > 0.8 and loaded_lazy.g > 0.65,
		"registered source appears without stale blank cache or document revision: %s -> %s" % [blank_lazy, loaded_lazy])

	# A dense viewport larger than the retained budget must not evict all
	# currently visible entries every frame (the overflow is transient).
	canvas._display_tiles.clear()
	for i: int in range(canvas.MAX_DISPLAY_TILES):
		var x: int = i % 12
		var y: int = i / 12
		canvas._display_tiles["%d,%d" % [x, y]] = {"area": Rect2i(x * 128, y * 128, 128, 128),
			"last_used": i}
	check(not canvas._reserve_display_slot(Rect2i(0, 0, 12, 12)),
		"dense on-screen cache uses a transient tile instead of evicting a visible tile")
	check(canvas._display_tiles.size() == canvas.MAX_DISPLAY_TILES,
		"dense-screen overflow leaves retained memory bounded")
	check(canvas._reserve_display_slot(Rect2i(11, 11, 1, 1))
		and not canvas._display_tiles.has("0,0"),
		"pan evicts the oldest off-screen tile before touching in-view tiles")

	print("T086_NATIVE_METRICS %s" % large)

	print("T086_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T086_NATIVE_PASSED" if failures == 0 else "T086_NATIVE_FAILED")
	quit(0 if failures == 0 else 1)
