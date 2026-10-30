extends SceneTree
## T-021: eraser geometry, transparent pixels, isolation, masks, undo and persistence.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ERASER FAILED: " + description)


func _pixel(layer: AtlasRasterLayer, point: Vector2i) -> Color:
	var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
	var chunk: AtlasRasterChunk = layer.chunks.get("%d,%d" % [coord.x, coord.y])
	if chunk == null:
		return Color.TRANSPARENT
	return chunk.image.get_pixelv(point - coord * AtlasRasterChunk.SIZE)


func _stroke(points: PackedVector2Array, width: float = 4.0) -> AtlasStroke:
	return AtlasStroke.new(points, Color(0.1, 0.4, 0.8, 0.35), width)


func _vector_geometry() -> void:
	var original: Array[AtlasStroke] = [
		_stroke(PackedVector2Array([Vector2(-35, 0), Vector2(0, 0), Vector2(35, 0)])),
		_stroke(PackedVector2Array([Vector2(-35, 50), Vector2(35, 50)]))
	]
	var before: Array[AtlasStroke] = AtlasStroke.clone_all(original)
	var sweep: PackedVector2Array = PackedVector2Array([Vector2(0, -15), Vector2(0, 15)])
	var result: Array[AtlasStroke] = AtlasStrokeEraser.erase(original, sweep, 8.0)
	_check(result.size() == 3, "swept round eraser splits only crossed vector centerline")
	var crossing_gap: bool = true
	var survivors: int = 0
	for stroke: AtlasStroke in result:
		_check(stroke.color.is_equal_approx(original[0].color) and stroke.width == 4.0,
			"vector fragments retain their exact style/alpha/width")
		if stroke.points[0].y == 50.0:
			continue
		survivors += 1
		for point: Vector2 in stroke.points:
			if absf(point.x) < 4.0 and absf(point.y) < 0.1:
				crossing_gap = false
	_check(survivors == 2 and crossing_gap, "cut leaves a genuine gap, not background paint")
	_check(AtlasStroke.same_artwork(before, original) and sweep.size() == 2,
		"geometry erase never mutates input strokes or pointer path")
	var distant: Array[AtlasStroke] = AtlasStrokeEraser.erase(original,
		PackedVector2Array([Vector2(300, 300)]), 8.0)
	_check(AtlasStroke.same_artwork(distant, original), "far eraser is a value no-op")
	var dot: Array[AtlasStroke] = [_stroke(PackedVector2Array([Vector2.ZERO]), 2.0)]
	_check(AtlasStrokeEraser.erase(dot, PackedVector2Array([Vector2(0, 0)]), 1.0).is_empty(),
		"a tap removes a vector dot with its round cap")
	var elbow: PackedVector2Array = PackedVector2Array([
		Vector2(-25, -25), Vector2(0, -25), Vector2(0, 20)])
	var turned: Array[AtlasStroke] = AtlasStrokeEraser.erase([_stroke(elbow)],
		PackedVector2Array([Vector2(-6, -35), Vector2(-6, -15), Vector2(8, -15)]), 6.0)
	_check(not turned.is_empty() and not AtlasStroke.same_artwork(turned, [_stroke(elbow)]),
		"a multi-segment turn erases the swept path rather than sample dots")
	var locked_scope: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)]), true)
	var clipped: Array[AtlasStroke] = locked_scope.erase(original, sweep, 8.0)
	_check(AtlasStroke.same_artwork(original, clipped),
		"cell mask protects crossing objects not wholly inside its boundary")
	_check(AtlasStroke.same_artwork(original, AtlasEditScope.new(PackedVector2Array(), true).erase(original, sweep, 8.0)),
		"invalid/empty active mask cannot remove ink")


## T-036: the readability split must preserve geometric edge cases, semantic
## objects and detached results, not just the common straight-line gesture.
func _vector_readability_edges() -> void:
	var color: Color = Color(0.3, 0.6, 0.9, 0.45)
	var line: AtlasStroke = AtlasStroke.new(PackedVector2Array([
		Vector2(-55, 0), Vector2(55, 0)]), color, 6.0)
	var two_cuts: Array[AtlasStroke] = AtlasStrokeEraser.erase([line], PackedVector2Array([
		Vector2(-20, -20), Vector2(-20, 20), Vector2(20, 20),
		Vector2(20, -20)]), 2.0)
	_check(two_cuts.size() == 3, "ordered multi-segment sweep retains three separate centerline parts")
	var source_untouched: bool = line.points == PackedVector2Array([Vector2(-55, 0), Vector2(55, 0)])
	for fragment: AtlasStroke in two_cuts:
		source_untouched = source_untouched and fragment != line and fragment.width == line.width \
			and fragment.color == line.color and not fragment.filled
	_check(source_untouched, "split fragments keep alpha/diameter without aliasing source")

	var filled: AtlasStroke = AtlasShapes.polygon(PackedVector2Array([
		Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)]),
		color, 4.0, true)
	var wall: AtlasStroke = AtlasEditablePath.make(PackedVector2Array([
		Vector2(50, 50), Vector2(110, 50), Vector2(110, 110)]), color, 3.0, true)
	var label: AtlasStroke = AtlasTextLayout.make(Vector2(100, -70), "Gate", "Serif", 18.0,
		color, true, false)
	_check(filled != null and wall != null and label != null, "semantic eraser fixtures are valid")
	if filled == null or wall == null or label == null:
		return
	var semantic: Array[AtlasStroke] = [filled, wall, label]
	var untouched: Array[AtlasStroke] = AtlasStroke.clone_all(semantic)
	var missed: Array[AtlasStroke] = AtlasStrokeEraser.erase(semantic,
		PackedVector2Array([Vector2(300, 300)]), 8.0)
	_check(AtlasStroke.same_artwork(missed, semantic) and missed.size() == 3
		and missed[0] != filled and missed[1] != wall and missed[2] != label,
		"missed filled, wall and text objects retain their own metadata and copy ownership")
	_check(AtlasStrokeEraser.erase([filled], PackedVector2Array([Vector2.ZERO]), 1.0).is_empty(),
		"eraser tap inside a solid polygon removes the whole filled shape")
	_check(AtlasStrokeEraser.erase([wall], PackedVector2Array([Vector2(80, 80)]), 8.0).is_empty(),
		"eraser at rendered closed wall edge removes whole editable object")
	var label_bounds: Rect2 = AtlasTextLayout.bounds(label)
	_check(AtlasStrokeEraser.erase([label], PackedVector2Array([
			label_bounds.position - Vector2(30, 0),
			Vector2(label_bounds.end.x + 30, label_bounds.position.y + label_bounds.size.y * 0.5)]),
		8.0).is_empty(), "text eraser segment crossing glyph box removes whole label")

	for invalid: PackedVector2Array in [PackedVector2Array(), PackedVector2Array([Vector2.INF]),
			PackedVector2Array([Vector2(NAN, 0)])]:
		var no_op: Array[AtlasStroke] = AtlasStrokeEraser.erase(semantic, invalid, 5.0)
		_check(AtlasStroke.same_artwork(no_op, semantic) and no_op[0] != semantic[0],
			"empty/nonfinite sweep is a detached value no-op")
	for invalid_width: float in [0.0, -1.0, NAN, INF]:
		var no_op: Array[AtlasStroke] = AtlasStrokeEraser.erase(semantic,
			PackedVector2Array([Vector2.ZERO]), invalid_width)
		_check(AtlasStroke.same_artwork(no_op, semantic) and no_op[0] != semantic[0],
			"nonpositive/nonfinite eraser width is a detached value no-op")
	missed[0].color = Color.RED
	missed[1].points[0] = Vector2(999, 999)
	_check(AtlasStroke.same_artwork(semantic, untouched),
		"mutating detached results cannot change source objects or undo snapshots")


func _raster_pixels() -> void:
	var image: Image = Image.create_empty(4, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.2, 0.3, 0.4))
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	var before: PackedByteArray = raster.chunks["0,0"].image.get_data()
	var path: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.5), Vector2(2.5, 0.5)])
	var result: AtlasFillResult = AtlasRasterBrush.paint(raster, path, Color(1, 1, 1, 0.15), 1.0, true)
	_check(result.ok and result.layer != null, "raster eraser makes a detached alpha-clearing snapshot")
	if result.layer == null:
		return
	for x: int in range(3):
		_check(_pixel(result.layer, Vector2i(x, 0)) == Color(0, 0, 0, 0),
			"raster swept pixel is fully transparent regardless of brush-color alpha")
	_check(absf(_pixel(result.layer, Vector2i(3, 0)).a - 0.4) < 0.005,
		"non-erased alpha and RGB remain intact")
	_check(raster.chunks["0,0"].image.get_data() == before,
		"source raster is untouched for exact undo")
	var no_change: AtlasFillResult = AtlasRasterBrush.paint(result.layer,
		PackedVector2Array([Vector2(300, 300)]), Color.WHITE, 1.0, true)
	_check(not no_change.ok, "eraser on absent raster pixels is a no-op")
	var empty: AtlasRasterLayer = AtlasRasterLayer.new()
	_check(empty.chunks.is_empty() and not AtlasRasterBrush.paint(empty, path,
		Color.WHITE, 1.0, true).ok and empty.chunks.is_empty(),
		"erasing never allocates new empty raster chunks")
	var seam: AtlasRasterLayer = AtlasRasterLayer.new()
	var ink: AtlasFillResult = AtlasRasterBrush.paint(seam, PackedVector2Array([
		Vector2(-1.5, 0.5), Vector2(1.5, 0.5)]), Color(1, 0, 0, 0.5), 1.0, false)
	_check(ink.ok and ink.layer.chunks.has("-1,0") and ink.layer.chunks.has("0,0"),
		"raster source spans negative/positive chunk seam")
	var erased: AtlasFillResult = AtlasRasterBrush.paint(ink.layer, PackedVector2Array([
		Vector2(-1.5, 0.5), Vector2(1.5, 0.5)]), Color.WHITE, 1.0, true)
	_check(erased.ok and erased.layer != null, "raster eraser crosses signed chunk seam")
	if erased.layer != null:
		for x: int in range(-2, 2):
			_check(_pixel(erased.layer, Vector2i(x, 0)) == Color(0, 0, 0, 0),
				"seam pixel %d cleared, no opaque background replacement" % x)
	var mask: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)]), true)
	var masked: AtlasFillResult = AtlasRasterBrush.paint(raster, path, Color.WHITE, 1.0, true, mask)
	_check(masked.ok and _pixel(masked.layer, Vector2i.ZERO) == Color(0, 0, 0, 0)
		and _pixel(masked.layer, Vector2i(2, 0)).a > 0.39,
		"raster mask clips the full pixel quad at the cell boundary")
	var hidden: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	hidden.visible = false
	_check(not AtlasRasterBrush.paint(hidden, path, Color.WHITE, 1.0, true).ok,
		"hidden raster rejects erasure")
	hidden.visible = true
	hidden.locked = true
	_check(not AtlasRasterBrush.paint(hidden, path, Color.WHITE, 1.0, true).ok,
		"locked raster rejects erasure")


func _editor_contract() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Eraser workflow", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 48)),
		"isolated board created")
	var canvas: AtlasCanvas = editor.canvas
	editor._choose_tool(AtlasCanvas.Tool.ERASER)
	_check(editor.inspector.brush_width_spinner.editable and editor.inspector._eraser_hint.visible
		and editor.inspector._ink_heading.text == "ERASER",
		"eraser displays scope and uses the same width field as brush")
	_check(not editor.inspector.brush_color_picker.visible,
		"eraser does not misleadingly offer a color or partial-opacity setting")
	var path: PackedVector2Array = PackedVector2Array([Vector2(-35, 0), Vector2(35, 0)])
	var color: Color = Color(0.8, 0.1, 0.5, 0.4)
	editor._on_stroke(AtlasStroke.new(path, color, 5.0), false)
	var saved: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
	var independent: AtlasMapDocument = AtlasMapDocument.new("eraser-destination", "Protected destination")
	editor.campaign.add_map(independent)
	_check(editor.campaign.get_map(independent.id) != null, "created independent reference destination")
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = "protected-link"
	link.source_map_id = canvas.map.id
	link.target_map_id = independent.id
	link.anchor = Vector2(0, 0)
	_check(AtlasLinkEdit.new(canvas.map.id, null, link).apply(editor.campaign),
		"created a link directly under the vector eraser sweep")
	var terrain_before: Dictionary = canvas.floor.terrain.duplicate()
	var link_before: Dictionary = editor.campaign.link_by_id(link.id).to_dict()
	var previous: AtlasEditCommand = editor.edits.get_undo_command()
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(300, 300)]), color, 8.0), true)
	_check(editor.edits.get_undo_command() == previous,
		"distant vector erase does not create a history entry")
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([
		Vector2(0, -15), Vector2(0, 15)]), color, 8.0), true)
	_check(canvas.floor.strokes.size() == 2, "editor erases vector geometry in one gesture")
	var after: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
	editor._on_undo()
	_check(AtlasStroke.same_artwork(canvas.floor.strokes, saved),
		"undo restores full vector geometry and original alpha")
	editor._on_redo()
	_check(AtlasStroke.same_artwork(canvas.floor.strokes, after),
		"redo restores exact split geometry")
	var slot: String = "user://validation/t021-roundtrip.scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK,
		"native save of erased vector succeeded")
	var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(slot)
	var restored: AtlasMapDocument = loaded.campaign.get_map(canvas.map.id) if loaded.campaign != null else null
	var floor: AtlasFloor = restored.floor_by_id(canvas.floor.id) if restored != null else null
	_check(floor != null and AtlasStroke.same_artwork(floor.strokes, after),
		"native load retains erased vector segments and RGBA")
	var layer: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	layer.locked = true
	previous = editor.edits.get_undo_command()
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), color, 60.0), true)
	_check(editor.edits.get_undo_command() == previous and AtlasStroke.same_artwork(canvas.floor.strokes, after),
		"locked ink refuses erasure and preserves history")
	layer.locked = false
	layer.visible = false
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), color, 60.0), true)
	_check(editor.edits.get_undo_command() == previous and AtlasStroke.same_artwork(canvas.floor.strokes, after),
		"hidden ink refuses erasure and preserves history")
	layer.visible = true
	canvas.set_presented_detail_level(1)
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), color, 60.0), true)
	_check(editor.edits.get_undo_command() == previous and AtlasStroke.same_artwork(canvas.floor.strokes, after),
		"non-presented detail refuses erasure")
	canvas.set_presented_detail_level(0)
	_check(canvas.floor.terrain == terrain_before
		and editor.campaign.link_by_id(link.id).to_dict() == link_before
		and editor.campaign.get_map(independent.id) != null,
		"eraser cannot create/remove terrain, links or referenced documents")
	# Exercise raster edits through the same editor command boundary, not only the brush service.
	var next_layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	next_layers.append(AtlasRasterLayer.new("eraser-raster", "Eraser raster"))
	_check(editor.apply_layers(next_layers, "eraser-raster"), "new raster editing target created")
	editor.select_layer("eraser-raster")
	var raster_path: PackedVector2Array = PackedVector2Array([
		Vector2(-1.5, 0.5), Vector2(1.5, 0.5)])
	editor._on_stroke(AtlasStroke.new(raster_path, Color(0.2, 0.8, 0.7, 0.6), 1.0), false)
	var before_raster: AtlasRasterLayer = canvas.floor.layer_by_id("eraser-raster") as AtlasRasterLayer
	_check(before_raster != null and absf(_pixel(before_raster, Vector2i(-1, 0)).a - 0.6) < 0.005,
		"new raster paint creates half-opaque pixels in signed chunks")
	var raster_before: Dictionary = before_raster.to_dict()
	editor._on_stroke(AtlasStroke.new(raster_path, Color.WHITE, 1.0), true)
	var after_raster: AtlasRasterLayer = canvas.floor.layer_by_id("eraser-raster") as AtlasRasterLayer
	_check(after_raster != null and _pixel(after_raster, Vector2i(-1, 0)) == Color(0, 0, 0, 0)
		and _pixel(after_raster, Vector2i(0, 0)) == Color(0, 0, 0, 0),
		"editor eraser clears raster alpha across chunk seam")
	var raster_after: Dictionary = after_raster.to_dict()
	editor._on_undo()
	_check((canvas.floor.layer_by_id("eraser-raster") as AtlasRasterLayer).to_dict() == raster_before,
		"raster undo restores identical chunk bytes and layer metadata")
	editor._on_redo()
	_check((canvas.floor.layer_by_id("eraser-raster") as AtlasRasterLayer).to_dict() == raster_after,
		"raster redo restores identical transparent chunk bytes")
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK,
		"native save after raster erase succeeded")
	loaded = AtlasCampaignStore.load_result(slot)
	restored = loaded.campaign.get_map(canvas.map.id) if loaded.campaign != null else null
	floor = restored.floor_by_id(canvas.floor.id) if restored != null else null
	var persisted: AtlasRasterLayer = floor.layer_by_id("eraser-raster") as AtlasRasterLayer if floor != null else null
	_check(persisted != null and persisted.to_dict() == raster_after,
		"native save roundtrip retains erased raster chunks")
	_check(loaded.campaign.link_by_id(link.id) != null
		and loaded.campaign.link_by_id(link.id).to_dict() == link_before,
		"native save retains untouched map reference under erased ink")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
	root.remove_child(scene)
	scene.free()


func _run() -> void:
	_vector_geometry()
	_vector_readability_edges()
	_raster_pixels()
	await _editor_contract()
	print("ATLAS_ERASER_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
