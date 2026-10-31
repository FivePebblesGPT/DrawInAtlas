extends SceneTree
## T-010: round brush geometry, edit-mask invariants and native save/history roundtrips.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PEN TURNS FAILED: " + label)


func _geometry() -> void:
	var paths: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, -90)]),
		PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(40, 0),
			Vector2(60, 0), Vector2(80, 0), Vector2(100, 0), Vector2(100, -90)]),
		PackedVector2Array([Vector2(0, 0), Vector2(140, 0), Vector2(143, -10)]),
		PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 8), Vector2(10, 8)]),
		PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 0), Vector2(0, 0)])
	]
	for index: int in range(paths.size()):
		var polygons: Array[PackedVector2Array] = AtlasStrokeGeometry.outline(paths[index], 24.0)
		_check(polygons.size() == 1, "case %d produces one unified silhouette" % index)
		if polygons.is_empty():
			continue
		var polygon: PackedVector2Array = polygons[0]
		_check(polygon.size() > 6 and Geometry2D.triangulate_polygon(polygon).size() > 0,
			"case %d has a round, triangulable outline" % index)
		_check(Geometry2D.is_point_in_polygon(paths[index][0], polygon),
			"case %d covers the starting cap" % index)
		_check(Geometry2D.is_point_in_polygon(paths[index][-1], polygon),
			"case %d covers the ending cap" % index)
	var flat: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	for width: float in [2.0, 8.0, 24.0, 45.0]:
		var polygon: PackedVector2Array = AtlasStrokeGeometry.outline(flat, width)[0]
		var bounds: Rect2 = _bounds(polygon)
		_check(absf(bounds.size.y - width) <= 0.05, "visible diameter remains %.1f" % width)
		_check(absf(bounds.size.x - (100.0 + width)) <= 0.5, "round caps add one diameter")
		_check(not Geometry2D.is_point_in_polygon(Vector2(50, width * 0.6), polygon),
			"stroke does not exceed its intended radius")
	_check(AtlasStrokeGeometry.centers(PackedVector2Array([
		Vector2(5, 5), Vector2(5, 5), Vector2(5.00001, 5), Vector2(10, 10)])).size() == 2,
		"duplicate/tiny pointer movement does not create degenerate corners")
	_check(AtlasStrokeGeometry.outline(PackedVector2Array([Vector2(5, 5)]), 20.0).is_empty(),
		"single taps are rendered as one round dot")


func _bounds(points: PackedVector2Array) -> Rect2:
	var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _roundtrip(editor: AtlasEditor) -> void:
	var canvas: AtlasCanvas = editor.canvas
	var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
	grid.distance_unit = "tiles"
	_check(editor.create_board("Pen turns roundtrip", grid), "isolated test board created")
	canvas.brush_width = 24.0
	var ink: Color = Color(0.15, 0.55, 0.95, 0.45)
	var path: PackedVector2Array = PackedVector2Array([
		Vector2(-100, 0), Vector2(-50, 0), Vector2(0, 0), Vector2(0, -60)])
	var stroke: AtlasStroke = AtlasStroke.new(path, ink, canvas.brush_width)
	editor._on_stroke(stroke, false)
	_check(canvas.floor.strokes.size() == 1, "one complete gesture creates one stroke")
	_check(canvas.floor.strokes[0].points == path and canvas.floor.strokes[0].color == ink
		and canvas.floor.strokes[0].width == 24.0, "drawing preserves exact path/color/width")
	var retained: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
	editor._on_undo()
	_check(canvas.floor.strokes.is_empty(), "one undo removes entire joined stroke")
	editor._on_redo()
	_check(AtlasStroke.same_artwork(canvas.floor.strokes, retained), "redo restores untouched path and alpha")
	var slot: String = "user://validation/t010-roundtrip.scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK, "native scene save")
	var result: AtlasStoreResult = AtlasCampaignStore.load_result(slot)
	_check(result.campaign != null and not result.recovered, "saved scene reloads directly")
	if result.campaign != null:
		var restored: AtlasMapDocument = result.campaign.get_map(canvas.map.id)
		var restored_floor: AtlasFloor = restored.floor_by_id(canvas.floor.id) if restored != null else null
		var restored_ink: AtlasInkLayer = restored_floor.layer_by_id("ink") as AtlasInkLayer if restored_floor != null else null
		_check(restored_ink != null and AtlasStroke.same_artwork(restored_ink.strokes, retained),
			"save roundtrip retains point data, width and alpha")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))


func _mask() -> void:
	var bounds: PackedVector2Array = PackedVector2Array([
		Vector2(-70, -70), Vector2(70, -70), Vector2(70, 70), Vector2(-70, 70)])
	var mask: AtlasEditScope = AtlasEditScope.new(bounds, true)
	var path: PackedVector2Array = PackedVector2Array([
		Vector2(-120, 0), Vector2(-30, 0), Vector2(20, 0), Vector2(120, 0)])
	var original: AtlasStroke = AtlasStroke.new(path, Color(1, 0, 0, 0.3), 24.0)
	var clipped: Array[AtlasStroke] = mask.clip_strokes([original])
	_check(not clipped.is_empty(), "selection mask keeps inside portion")
	for stroke: AtlasStroke in clipped:
		_check(stroke.width == 24.0 and stroke.color == original.color,
			"mask retains source width, color and transparency")
		for point: Vector2 in stroke.points:
			_check(absf(point.x) <= 58.1, "mask insets centerline by brush radius")
	_check(original.points == path, "clipping and geometry do not rewrite original samples")


func _run() -> void:
	_geometry()
	_mask()
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = "user://validation/t010-editor.scn"
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_roundtrip(editor)
	root.remove_child(scene)
	scene.free()
	print("ATLAS_PEN_TURNS_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
