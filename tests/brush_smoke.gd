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
	_check(canvas.floor.strokes.size() == 1 and canvas.floor.strokes[0].points == path,
		"one vector brush gesture stores the complete continuous path")
	_check(canvas.floor.strokes[0].color.is_equal_approx(source)
		and canvas.floor.strokes[0].width == 16.0,
		"vector stroke retains exact RGBA and board-unit diameter")
	editor._on_undo()
	_check(canvas.floor.strokes.is_empty(), "one undo removes the whole stroke")
	editor._on_redo()
	_check(canvas.floor.strokes.size() == 1 and canvas.floor.strokes[0].color.is_equal_approx(source),
		"redo restores the RGBA stroke")
	var old_points: PackedVector2Array = canvas.floor.strokes[0].points.duplicate()
	canvas.camera_zoom = 2.5
	canvas.camera_center = Vector2(110, -80)
	_check(canvas.floor.strokes[0].points == old_points,
		"camera zoom and pan do not alter stored stroke coordinates")
	var slot: String = "user://validation/t020-roundtrip.scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK, "native brush save succeeded")
	var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(slot)
	var restored: AtlasMapDocument = loaded.campaign.get_map(canvas.map.id) if loaded.campaign != null else null
	var floor: AtlasFloor = restored.floor_by_id(canvas.floor.id) if restored != null else null
	var ink: AtlasInkLayer = floor.layer_by_id("ink") as AtlasInkLayer if floor != null else null
	_check(ink != null and ink.strokes.size() == 1 and ink.strokes[0].color.is_equal_approx(source)
		and ink.strokes[0].width == 16.0 and ink.strokes[0].points == old_points,
		"native save roundtrip preserves source RGBA, width and geometry")
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
	await _editor_gesture()
	print("ATLAS_BRUSH_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
