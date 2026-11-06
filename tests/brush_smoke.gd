extends SceneTree
## T-020: RGBA brush compositing, boundary/mask behavior and one-stroke history.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("BRUSH FAILED: " + label)


func _pixel(layer: AtlasRasterLayer, point: Vector2i) -> Color:
	var chunk_coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
	var chunk: AtlasRasterChunk = layer.chunks.get("%d,%d" % [chunk_coord.x, chunk_coord.y])
	if chunk == null:
		return Color.TRANSPARENT
	var local: Vector2i = point - chunk_coord * AtlasRasterChunk.SIZE
	return chunk.image.get_pixelv(local)


func _raster_color() -> void:
	var path: PackedVector2Array = PackedVector2Array([
		Vector2(-1.5, 0.5), Vector2(0.5, 0.5), Vector2(1.5, 0.5)])
	var ink: Color = Color(1, 0, 0, 0.5)
	var empty: AtlasRasterLayer = AtlasRasterLayer.new()
	var first: AtlasFillResult = AtlasRasterBrush.paint(empty, path, ink, 1.0, false)
	_check(first.ok and first.layer != null, "semi-transparent brush accepts stroke across signed chunks")
	if first.layer == null:
		return
	_check(first.layer.chunks.has("-1,0") and first.layer.chunks.has("0,0"),
		"continuous stroke creates negative and positive raster chunks")
	for x: int in range(-2, 2):
		var pixel: Color = _pixel(first.layer, Vector2i(x, 0))
		_check(pixel.r > 0.99 and absf(pixel.a - 0.5) < 0.005,
			"each pixel receives exactly one half-opacity pass, regardless of sample overlap")
	_check(empty.chunks.is_empty(), "painting never mutates the input raster layer")
	var once: AtlasFillResult = AtlasRasterBrush.paint(empty,
		PackedVector2Array([Vector2(0.5, 0.5)]), ink, 1.0, false)
	_check(once.ok and _pixel(once.layer, Vector2i(0, 0)) == _pixel(first.layer, Vector2i(0, 0)),
		"sample density does not increase opacity inside a gesture")
	var second: AtlasFillResult = AtlasRasterBrush.paint(first.layer, path, ink, 1.0, false)
	_check(second.ok and absf(_pixel(second.layer, Vector2i(0, 0)).a - 0.75) < 0.005,
		"separate gestures composite instead of replacing previous alpha")
	_check(absf(_pixel(first.layer, Vector2i(0, 0)).a - 0.5) < 0.005,
		"the previous gesture remains an independent undo snapshot")
	var transparent: AtlasFillResult = AtlasRasterBrush.paint(first.layer, path, Color(1, 1, 1, 0), 1.0, false)
	_check(not transparent.ok, "zero-opacity brush is a true no-op")
	var blue: Image = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var painted: AtlasRasterLayer = AtlasRasterLayer.from_image(blue)
	var blend: AtlasFillResult = AtlasRasterBrush.paint(painted,
		PackedVector2Array([Vector2(0.5, 0.5)]), ink, 1.0, false)
	var mixed: Color = _pixel(blend.layer, Vector2i.ZERO) if blend.ok else Color.TRANSPARENT
	_check(blend.ok and mixed.a > 0.99 and absf(mixed.r - 0.5) < 0.01
		and absf(mixed.b - 0.5) < 0.01, "RGBA source-over blends red with opaque blue")
	_check(_pixel(painted, Vector2i.ZERO) == Color.BLUE,
		"source image is unchanged by the blended brush")
	var scope: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), true)
	var masked: AtlasFillResult = AtlasRasterBrush.paint(empty, path, ink, 1.0, false, scope)
	_check(masked.ok and _pixel(masked.layer, Vector2i.ZERO).a > 0.0
		and _pixel(masked.layer, Vector2i(-1, 0)).a == 0.0,
		"selection mask protects entire pixel quads across chunk boundary")
	var hidden: AtlasRasterLayer = AtlasRasterLayer.new()
	hidden.visible = false
	_check(not AtlasRasterBrush.paint(hidden, path, ink, 1.0, false).ok,
		"hidden raster layers refuse brush edits")
	hidden.visible = true
	hidden.locked = true
	_check(not AtlasRasterBrush.paint(hidden, path, ink, 1.0, false).ok,
		"locked raster layers refuse brush edits")


func _transformed_partial_chunk() -> void:
	# A rotated, half-density imported image has one stored blue pixel.
	# Brush may grow the chunk, but cannot edit the input image in place.
	var source: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	source.fill(Color.BLUE)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(source, 2.0)
	layer.transform = Transform2D(Vector2(0, 1), Vector2(-1, 0), Vector2(7, -5))
	var document_center: Vector2 = layer.transform * (Vector2(1.5, 0.5) / layer.pixels_per_unit)
	var path: PackedVector2Array = PackedVector2Array([document_center])
	var painted: AtlasFillResult = AtlasRasterBrush.paint(layer, path, Color(1, 0, 0, 0.5), 0.6, false)
	_check(painted.ok and painted.layer != null, "rotated partial raster accepts a pixel-center brush")
	if not painted.ok:
		return
	var expanded: AtlasRasterChunk = painted.layer.chunks.get("0,0")
	_check(expanded != null and expanded.width == AtlasRasterChunk.SIZE
		and expanded.height == AtlasRasterChunk.SIZE,
		"painting just beyond a partial image expands only the result chunk")
	_check(_pixel(painted.layer, Vector2i(1, 0)).a > 0.49,
		"document-space brush footprint maps to the intended local raster pixel")
	_check(layer.chunks["0,0"].width == 1 and layer.chunks["0,0"].height == 1
		and _pixel(layer, Vector2i.ZERO) == Color.BLUE,
		"the original partial image remains independently owned")
	var rejected: AtlasFillResult = AtlasRasterBrush.paint(layer, path, Color.RED, 20.0,
		false, null, 3)
	_check(not rejected.ok and rejected.message == "Brush exceeds the candidate pixel limit."
		and layer.chunks["0,0"].width == 1 and _pixel(layer, Vector2i.ZERO) == Color.BLUE,
		"candidate overflow rejects the entire transformed gesture atomically")


func _incremental_raster() -> void:
	var image: Image = Image.create_empty(7, 9, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8, 0.6))
	for erase: bool in [false, true]:
		for transformed: bool in [false, true]:
			var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
			if transformed:
				layer.transform = Transform2D(Vector2(0.8, 0.4), Vector2(-0.2, 1.2), Vector2(-3, 5))
			var scope: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
				Vector2(-20, -20), Vector2(25, -20), Vector2(25, 25), Vector2(-20, 25)]), true)
			var path: PackedVector2Array = PackedVector2Array([
				Vector2(-8, 2), Vector2(12, 2), Vector2(2, 12), Vector2(2, -8), Vector2(-8, 2)])
			var color: Color = Color(0.9, 0.2, 0.1, 0.4)
			# Reference: the old whole-path scan, including self-overlap and mask checks.
			var changes: Dictionary[Vector2i, Color] = {}
			var covered: Dictionary[Vector2i, bool] = {}
			AtlasRasterBrush._stage_pixel_changes(layer, path, 2.0,
				Color(0, 0, 0, 0) if erase else AtlasFill._canonical_color(color), erase, scope,
				Vector2i(-50, -50), Vector2i(50, 50), changes, covered)
			var expected: AtlasFillResult = AtlasFill._paint_pixel_colors(layer, changes)
			var session: AtlasRasterBrush = AtlasRasterBrush.new(layer, color, 4.0, erase, scope)
			var actual: AtlasFillResult
			for point: Vector2 in path:
				actual = session.append(PackedVector2Array([point]))
			var equal: bool = actual.ok and expected.ok and actual.layer.chunks.size() == expected.layer.chunks.size()
			if equal:
				for key: String in expected.layer.chunks:
					equal = equal and actual.layer.chunks.has(key) and actual.layer.chunks[key].asset_id == expected.layer.chunks[key].asset_id
			_check(equal, "incremental paint/erase is byte-exact to whole-path coverage (transformed=%s erase=%s)" % [transformed, erase])
			_check(layer.chunks["0,0"].image.get_data() == image.get_data(), "incremental preview never mutates its source")


func _sampled_path(waypoints: PackedVector2Array, step: float) -> PackedVector2Array:
	var dense: PackedVector2Array = PackedVector2Array([waypoints[0]])
	for corner: int in range(1, waypoints.size()):
		var from: Vector2 = dense[dense.size() - 1]
		var to: Vector2 = waypoints[corner]
		var span: float = from.distance_to(to)
		var pieces: int = maxi(1, ceili(span / step))
		for piece: int in range(1, pieces + 1):
			dense.append(from.lerp(to, float(piece) / float(pieces)))
	return dense


func _grand_freehand_loop() -> void:
	# A looped freehand gesture denser than one board quadrant must keep painting
	# and must commit, instead of vanishing when it closes at the start y level.
	var ink: Color = Color(0.1, 0.4, 0.9, 1.0)
	var loop: PackedVector2Array = _sampled_path(PackedVector2Array([
		Vector2(0, 0), Vector2(240, 0), Vector2(240, 220),
		Vector2(-240, 220), Vector2(-240, 12), Vector2(-120, 0)]), 20.0)
	var seam: int = 0
	for index: int in range(loop.size()):
		if loop[index].y >= 219.0:
			seam = index
			break
	var descent: PackedVector2Array = loop.slice(0, seam)
	var closure: PackedVector2Array = loop.slice(seam)
	var session: AtlasRasterBrush = AtlasRasterBrush.new(
		AtlasRasterLayer.paint_layer(), ink, 8.0, false)
	var walk: AtlasFillResult = session.append(descent)
	_check(walk.ok, "in-bounds descent batch keeps the brush session alive")
	if walk.ok and closure.size() > 0:
		var closure_result: AtlasFillResult = session.append(closure)
		_check(closure_result.ok and closure_result.layer != null,
			"looped closure reaching the start y level keeps painting")
		if closure_result.ok and closure_result.layer != null:
			_check(_pixel(closure_result.layer, Vector2i(-120, 0) * 4).a > 0.9,
				"the closing stroke reaches the same y level with pixels")
	var committed: AtlasFillResult = AtlasRasterBrush.paint(
		AtlasRasterLayer.paint_layer(), loop, ink, 8.0, false)
	_check(committed.ok and committed.layer != null,
		"commit re-paint of the complete looped gesture succeeds")
	if committed.ok and committed.layer != null:
		_check(_pixel(committed.layer, Vector2i(240, 220) * 4).a > 0.9,
			"committed loop keeps pixels at every waypoint")
	_check(AtlasRasterBrush.paint(AtlasRasterLayer.paint_layer(),
		PackedVector2Array([Vector2(0, 0), Vector2(10000, 0)]), ink, 8.0, false).ok,
		"a single straight sweep longer than one pixel window splits instead of failing")


func _editor_gesture() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = "user://validation/t020-editor.scn"
	root.add_child(scene)
	for i: int in range(7):
		await process_frame
	_check(editor.create_board("Brush workflow", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 36)),
		"isolated board created")
	var canvas: AtlasCanvas = editor.canvas
	var picker: ColorPickerButton = editor.inspector.brush_color_picker
	_check(picker.edit_alpha, "brush color editor exposes opacity")
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.PEN).tooltip_text.contains("Brush"),
		"tool palette advertises the familiar Brush interaction")
	var source: Color = Color(0.15, 0.8, 0.32, 0.35)
	picker.color = source
	picker.color_changed.emit(source)
	editor.inspector.brush_width_spinner.value = 16.0
	_check(canvas.brush_color.is_equal_approx(source) and canvas.brush_width == 16.0,
		"inspector RGBA and width update next gesture")
	var path: PackedVector2Array = PackedVector2Array([
		Vector2(-30, 0), Vector2(0, 0), Vector2(30, 0)])
	editor._on_stroke(AtlasStroke.new(path, canvas.brush_color, canvas.brush_width), false)
	_check(not canvas.floor.raster_layer().chunks.is_empty() and canvas.floor.objects_layer().strokes.is_empty(),
		"one brush gesture paints raster without creating vector objects")
	_check(absf(_pixel(canvas.floor.raster_layer(), Vector2i.ZERO).a - source.a) < 0.005,
		"raster brush retains selected alpha")
	editor._on_undo()
	_check(canvas.floor.raster_layer().chunks.is_empty(), "one undo removes the whole stroke")
	editor._on_redo()
	_check(absf(_pixel(canvas.floor.raster_layer(), Vector2i.ZERO).a - source.a) < 0.005,
		"redo restores raster RGBA")
	var old_pixels: Dictionary = canvas.floor.raster_layer().to_dict()
	canvas.camera_zoom = 2.5
	canvas.camera_center = Vector2(110, -80)
	_check(canvas.floor.raster_layer().to_dict() == old_pixels,
		"camera zoom and pan do not alter raster pixels or placement")
	var slot: String = "user://validation/t020-roundtrip.scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK, "native brush save succeeded")
	var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(slot)
	var restored: AtlasMapDocument = loaded.campaign.get_map(canvas.map.id) if loaded.campaign != null else null
	var floor: AtlasFloor = restored.floor_by_id(canvas.floor.id) if restored != null else null
	_check(floor != null and floor.raster_layer().to_dict() == old_pixels,
		"native save roundtrip preserves raster RGBA, density and placement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
	# A second, raster authoring target must use the same controls and history,
	# without replacing the vector stroke or altering the saved board grid.
	var extra: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	extra.append(AtlasRasterLayer.new("brush-raster", "Brush raster"))
	_check(editor.apply_layers(extra, "brush-raster"), "new raster layer can be selected")
	editor.select_layer("brush-raster")
	var raster_ink: Color = Color(1, 0, 0, 0.4)
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([
		Vector2(-1.5, 0.5), Vector2(1.5, 0.5)]), raster_ink, 1.0), false)
	var painted: AtlasRasterLayer = canvas.floor.layer_by_id("brush-raster") as AtlasRasterLayer
	_check(painted != null and painted.chunks.has("-1,0") and painted.chunks.has("0,0"),
		"editor raster brush paints continuously across signed chunk seam")
	_check(absf(_pixel(painted, Vector2i(-1, 0)).a - 0.4) < 0.005,
		"editor raster gesture uses selected alpha")
	editor._on_undo()
	painted = canvas.floor.layer_by_id("brush-raster") as AtlasRasterLayer
	_check(painted != null and painted.chunks.is_empty(), "one undo removes whole raster sweep")
	editor._on_redo()
	painted = canvas.floor.layer_by_id("brush-raster") as AtlasRasterLayer
	_check(painted != null and _pixel(painted, Vector2i(0, 0)).a > 0.39,
		"redo restores raster paint alpha")
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK,
		"combined vector and raster authoring save succeeds")
	loaded = AtlasCampaignStore.load_result(slot)
	restored = loaded.campaign.get_map(canvas.map.id) if loaded.campaign != null else null
	floor = restored.floor_by_id(canvas.floor.id) if restored != null else null
	var raster_saved: AtlasRasterLayer = floor.layer_by_id("brush-raster") as AtlasRasterLayer if floor != null else null
	_check(raster_saved != null and absf(_pixel(raster_saved, Vector2i(0, 0)).a - 0.4) < 0.005,
		"native save roundtrip retains raster brush alpha across chunks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
	root.remove_child(scene)
	scene.free()


func _run() -> void:
	_raster_color()
	_transformed_partial_chunk()
	_incremental_raster()
	_grand_freehand_loop()
	await _editor_gesture()
	print("ATLAS_BRUSH_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
