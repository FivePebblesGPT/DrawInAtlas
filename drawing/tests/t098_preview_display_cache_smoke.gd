extends SceneTree
## T-098: exact display-tile invalidation under detached raster previews.
## The old storage-chunk stamp dirties unrelated 128px texture quadrants.

var checks: int = 0
var failures: int = 0


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T098_PREVIEW_DISPLAY_FAILED: " + description)


func stamps(session: DrawingEditSession, area: Rect2i) -> Dictionary:
	var result: Dictionary = session.preview_display_stamps_for_canvas(area, 128)
	check(bool(result.get("indexed", false)), "exact display index available")
	return result.get("stamps", {}) as Dictionary


func redraw(canvas: Control) -> void:
	canvas.queue_redraw()
	for i: int in range(3):
		await process_frame


func run() -> void:
	root.size = Vector2i(640, 460)
	var doc: DrawingDocument = DrawingDocument.new("t098-exact-preview", 256)
	var base: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Base").value)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var seed: DrawingEditSession = doc.begin_edit(base, doc.revision).value
	check(seed._stage(32, 32, 0xffcc8844).ok and seed.commit().ok,
		"committed underlying layer is present")
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(16, 16)
	canvas.size = Vector2(280, 280)
	canvas.camera = Vector2(128, 128)
	canvas.zoom = 1.0
	canvas.document = doc
	canvas.layer_id = layer
	canvas.brush_width = 7.0
	canvas.color_rgba = 0x80ff0044
	root.add_child(canvas)
	await redraw(canvas)
	canvas.start_gesture(canvas.pixel_to_position(Vector2(32.5, 32.5)))
	canvas.set_process(false)
	var edit: DrawingEditSession = canvas.session
	check(edit != null and edit._preview_epoch > 0,
		"actual Canvas Brush pointer-down stages the initial transparent dab")
	if edit == null:
		quit(1)
		return

	# Both points share canonical 256px source chunk 0,0 but not a
	# 128px display tile. The old index recomposes 4 quadrants on step 2.
	var initial: Dictionary = stamps(edit, Rect2i(0, 0, 2, 2))
	check(initial.has("0,0") and initial.size() == 1,
		"first dab invalidates only one 128px display quadrant")
	await redraw(canvas)
	check(int(canvas.last_frame_metrics.get("tiles_composited", 0)) == 1,
		"actual Canvas composes first dirty quadrant only")
	var first_entry: Dictionary = canvas._display_tiles.get("0,0", {})
	var first_texture: ImageTexture = first_entry.get("texture") as ImageTexture
	check(first_texture != null, "first quadrant owns a cached texture")
	var first_stamp: int = int(initial.get("0,0", 0))
	var first_visible: Color = Color.TRANSPARENT
	var second_blank: Color = Color.TRANSPARENT
	var first_screen: Vector2i = Vector2i(canvas.global_position +
		canvas.pixel_to_position(Vector2(32.5, 32.5)))
	var second_screen: Vector2i = Vector2i(canvas.global_position +
		canvas.pixel_to_position(Vector2(201.5, 201.5)))
	if DisplayServer.get_name() != "headless":
		var image_before: Image = root.get_texture().get_image()
		first_visible = image_before.get_pixelv(first_screen)
		second_blank = image_before.get_pixelv(second_screen)

	check(edit._stage_brush_tile(201, 201, 0x80ff0044, null, true, true, -1).ok,
		"second detached Brush pixel in a different display quadrant")
	var second: Dictionary = stamps(edit, Rect2i(0, 0, 2, 2))
	check(second.size() == 2 and int(second.get("0,0", 0)) == first_stamp
		and int(second.get("1,1", 0)) > first_stamp,
		"second source-chunk edit leaves unrelated display stamp stable")
	await redraw(canvas)
	check(int(canvas.last_frame_metrics.get("tiles_composited", -1)) == 1,
		"new quadrant composes but unchanged quadrant stays cached")
	check(int(canvas.last_frame_metrics.get("cache_hits", 0)) >= 1,
		"actual Canvas reuses the first texture")
	check((canvas._display_tiles.get("0,0", {}) as Dictionary).get("texture") == first_texture,
		"first quadrant keeps its original GPU texture")
	check(canvas._display_tiles.size() <= canvas.MAX_DISPLAY_TILES,
		"Canvas image textures obey the retained cache limit")
	if DisplayServer.get_name() != "headless":
		var image_after: Image = root.get_texture().get_image()
		check(image_after.get_pixelv(first_screen) == first_visible,
			"unchanged alpha layer pixels remain identical in GPU framebuffer")
		check(image_after.get_pixelv(second_screen) != second_blank,
			"new quadrant is visible through actual GPU framebuffer")

	# Exact source & compositor equality across alpha, two layers, preview,
	# publication and one-step Undo/Redo. No color conversions in the cache.
	var area: Rect2i = Rect2i(0, 0, 256, 256)
	var preview: DrawingResult = DrawingRenderer.render(doc, area, 0, 0,
		256 * 256, edit)
	check(preview.ok, "detached multi-layer alpha preview renders")
	var preview_bytes: PackedByteArray = (preview.value as Image).get_data() \
		if preview.ok else PackedByteArray()
	check(edit.commit().ok, "one atomic transaction publishes both quadrants")
	var published: DrawingResult = DrawingRenderer.render(doc, area)
	check(published.ok and (published.value as Image).get_data() == preview_bytes,
		"complete straight-RGBA8 preview is byte-exact with published layers")
	check(doc.undo().ok and int(doc.read_pixel(layer, 32, 32).value) == 0,
		"Undo removes first preview dab")
	check(doc.redo().ok and int(doc.read_pixel(layer, 201, 201).value) != 0,
		"Redo restores second dab")
	canvas.cancel_gesture()
	await redraw(canvas)
	canvas.queue_free()

	# Negative signed tile boundaries and explicit erasure still index only
	# the touched display quadrant; cancel cannot resurrect draft bytes.
	var neg_doc: DrawingDocument = DrawingDocument.new("t098-signed-eraser", 256)
	var neg_layer: String = String(neg_doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var prep: DrawingEditSession = neg_doc.begin_edit(neg_layer, neg_doc.revision).value
	check(prep._stage(-150, -150, 0xff55cc77).ok and prep.commit().ok,
		"signed source pixel seeded")
	var erased: DrawingEditSession = neg_doc.begin_edit(neg_layer, neg_doc.revision).value
	check(erased.paint_path(PackedVector2Array([Vector2(-149.5, -149.5)]),
		0xff55cc77, 3.0, true).ok, "signed Eraser staged")
	var negative: Dictionary = stamps(erased, Rect2i(-2, -2, 3, 3))
	check(negative.size() == 1 and negative.has("-2,-2"),
		"negative 64-bit floor tile uses exact display coordinates")
	erased.cancel()
	check((erased.preview_display_stamps_for_canvas(Rect2i(-2, -2, 3, 3), 128)["stamps"] as Dictionary).is_empty()
		and int(neg_doc.read_pixel(neg_layer, -150, -150).value) == 0xff55cc77,
		"cancel clears draft and preserves signed source pixel")

	# A failed staging batch must disable optimistic stamps and use the
	# conservative storage index until the next edit session.
	var rollback: DrawingEditSession = neg_doc.begin_edit(neg_layer, neg_doc.revision).value
	check(rollback.paint_path(PackedVector2Array([Vector2(10.5, 10.5)]),
		0xff112233, 3.0).ok, "pre-error dab staged")
	var failed: DrawingResult = rollback.paint_path(PackedVector2Array([
		Vector2(12.5, 10.5), Vector2(200.5, 200.5)]),
		0xff112233, 96.0, false, null, 1)
	check(not failed.ok and not rollback._preview_display_exact,
		"failed batch disables incomplete exact-display index")
	var conservative: Dictionary = rollback.preview_display_stamps_for_canvas(
		Rect2i(0, 0, 2, 2), 128)
	check(bool(conservative.get("indexed", false)) and
		(conservative["stamps"] as Dictionary).size() == 4,
		"rollback falls back to conservative storage-footprint invalidation")
	rollback.cancel()

	# Prove the hard cap retains no unbounded per-display dictionary.
	var bounded: DrawingEditSession = neg_doc.begin_edit(neg_layer, neg_doc.revision).value
	for i: int in range(bounded.MAX_PREVIEW_DISPLAY_KEYS + 1):
		bounded._preview_epoch += 1
		bounded._preview_tile_versions["%d,0" % i] = bounded._preview_epoch
		bounded._mark_preview_display_pixel(i * 128, 0)
	check(not bounded._preview_display_exact and bounded._preview_display_versions.is_empty(),
		"oversized sparse preview index releases all retained exact keys")
	bounded.cancel()

	print("T098_PREVIEW_DISPLAY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T098_PREVIEW_DISPLAY_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
