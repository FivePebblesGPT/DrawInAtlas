extends SceneTree

const G = preload("res://scripts/editing/selection_geometry.gd")
const Shapes = preload("res://scripts/artwork/shape_tools.gd")
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_shapes()
	_selection()
	_combination()
	_guards()
	_ink_transforms()
	_raster_transforms()
	_scopes()
	_store()
	print("ATLAS_SELECTION_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("SELECTION FAILED: " + label)

func _ink() -> AtlasInkLayer:
	var layer: AtlasInkLayer = AtlasInkLayer.new()
	layer.strokes = [Shapes.stroke("LINE", Vector2(-1.75, -0.75), Vector2(-0.25, -0.75), Color(0.25, 0.5, 0.75, 0.5), 0.5),
		Shapes.stroke("LINE", Vector2(-1, -0.75), Vector2(-1, -0.75), Color.BLUE, 0.25)]
	return layer

func _raster() -> AtlasRasterLayer:
	var layer: AtlasRasterLayer = AtlasRasterLayer.new()
	var image: Image = Image.create_from_data(3, 2, false, Image.FORMAT_RGBA8,
		PackedByteArray([203, 17, 91, 0, 5, 101, 239, 127, 255, 1, 2, 255, 12, 34, 56, 1, 87, 65, 43, 254, 9, 19, 29, 0]))
	layer.chunks["-1,0"] = AtlasRasterChunk.new(Vector2i(-1, 0), image)
	layer.pixels_per_unit = 2.0
	layer.transform = Transform2D(Vector2(1, 1), Vector2(-0.5, 1.5), Vector2(3.125, -2.25))
	return layer

func _scope(rect: Rect2) -> AtlasEditScope:
	return AtlasEditScope.new(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)]), true)

func _shapes() -> void:
	var start: Vector2 = Vector2(0.25, -0.5)
	var finish: Vector2 = Vector2(-1.75, -1.5)
	for kind: String in ["LINE", "RECTANGLE", "ELLIPSE"]:
		var stroke: AtlasStroke = Shapes.stroke(kind, start, finish, Color(0.25, 0.5, 0.75, 0.5), 0.25)
		_check(stroke != null and stroke.is_valid(), kind + " negative/subcell geometry")
		if stroke == null:
			continue
		_check(stroke.width == 0.25 and stroke.color == Color(0.25, 0.5, 0.75, 0.5), kind + " preserves RGBA and width")
		_check(G.stroke_bounds(stroke).is_equal_approx(Rect2(-1.875, -1.625, 2.25, 1.25)), kind + " padded extrema")
		if kind == "LINE":
			_check(stroke.points == PackedVector2Array([start, finish]), "line preserves endpoint order")
		else:
			_check(stroke.points[0].is_equal_approx(stroke.points[-1]), kind + " closes outline")
			var layer: AtlasInkLayer = AtlasInkLayer.new()
			layer.strokes = [stroke]
			_check(G.select_point(layer, Vector2(-0.75, -1), 0).is_empty(), kind + " has no filled interior")
			_check(not G.select_point(layer, stroke.points[1], 0).is_empty(), kind + " outline is hittable")
			if kind == "RECTANGLE":
				_check(stroke.points == PackedVector2Array([finish, Vector2(0.25, -1.5), start, Vector2(-1.75, -0.5), finish]), "rectangle corners normalized")
			else:
				for point: Vector2 in stroke.points:
					var unit: Vector2 = (point - Vector2(-0.75, -1)) / Vector2(1, 0.5)
					_check(is_equal_approx(unit.length_squared(), 1.0), "ellipse follows analytic perimeter")
	_check(_ink().strokes[1].points.size() == 1, "zero-length line is a dot")
	for kind: String in ["RECTANGLE", "ELLIPSE"]:
		for end: Vector2 in [start, start + Vector2(1, 0), start + Vector2(0, 1)]:
			_check(Shapes.stroke(kind, start, end, Color.RED, 1) == null, kind + " rejects degenerate box")
	_check(Shapes.stroke("UNKNOWN", start, finish, Color.RED, 1) == null, "unknown shape rejected")
	for bad: float in [0.0, -1.0, INF, NAN]:
		_check(Shapes.stroke("LINE", start, finish, Color.RED, bad) == null, "invalid width rejected")
	_check(Shapes.stroke("LINE", Vector2(INF, 0), finish, Color.RED, 1) == null, "nonfinite endpoint rejected")

func _selection() -> void:
	var layer: AtlasInkLayer = _ink()
	var selection: AtlasSelection = G.select_indices(layer, [0])
	_check(selection.layer_id == layer.id and selection.source == layer.to_dict() and selection.matches(layer), "selection captures source identity/content")
	_check(selection.bounds == Rect2(-2, -1, 2, 0.5) and not selection.raster_selected, "ink padded bounds")
	_check(G.select_all(layer).stroke_indices == [0, 1], "all preserves painter order")
	_check(G.select_indices(layer, [1, 0]).stroke_indices == [1, 0], "explicit indices preserve order")
	_check(G.select_rect(layer, selection.bounds).stroke_indices == [0, 1], "marquee encloses whole padded bounds including boundary")
	_check(G.select_rect(layer, Rect2(-1.75, -0.75, 1.5, 0.01)).is_empty(), "centerline-only marquee excludes padding")
	_check(G.select_rect(layer, Rect2(-2, -1, 0.6, 0.5)).is_empty(), "partial overlap cannot select a stroke")
	_check(G.select_rect(layer, Rect2(-1.125, -0.875, 0.25, 0.25)).stroke_indices == [1], "marquee can isolate a padded dot")
	_check(G.select_point(layer, Vector2(-1, -0.75), 0).stroke_indices == [1], "last overlapping stroke wins")
	_check(G.select_point(layer, Vector2(-1.5, -0.5), 0).stroke_indices == [0], "segment halfwidth boundary hits")
	_check(G.select_point(layer, Vector2(-2.125, -0.75), 0.125).stroke_indices == [0], "round cap plus tolerance hits")
	_check(G.select_point(layer, Vector2(-2.126, -0.75), 0.125).is_empty(), "outside cap tolerance misses")
	for raw: Array in [[-1], [2], [0, 0], [0, 2], [1, -1]]:
		var indices: Array[int] = []
		indices.assign(raw)
		_check(G.select_indices(layer, indices).is_empty(), "invalid index selection rejects atomically: " + str(raw))
	_check(G.select_indices(layer, []).is_empty() and G.select_all(AtlasInkLayer.new()).is_empty(), "empty ink selection")
	_check(G.select_all(null).is_empty() and G.select_all(AtlasTerrainLayer.new()).is_empty(), "null/tiles have no artwork selection")
	layer.strokes[0].points[0] = Vector2(9, 9)
	_check(selection.source.strokes[0].points[0] == [-1.75, -0.75] and not selection.matches(layer), "snapshot is detached and detects stale geometry")
	_check(G.transformed(layer, selection, Transform2D.IDENTITY) == null, "stale transform rejected")

func _guards() -> void:
	for layer: AtlasLayer in [_ink(), _raster()]:
		layer.locked = true
		var selection: AtlasSelection = G.select_all(layer)
		_check(not selection.is_empty() and selection.matches(layer), "locked visible artwork remains selectable for copying")
		var text: String = AtlasClipboard.encode_ink(layer.strokes, selection.stroke_indices, selection.bounds.position) if layer is AtlasInkLayer else AtlasClipboard.encode_raster(layer, selection.bounds.position)
		_check(AtlasClipboard.decode(text) != null, "locked selection can be copied")
		_check(G.transformed(layer, selection, Transform2D.IDENTITY) == null, "locked transform denied with current snapshot")
		layer.locked = false
		layer.visible = false
		_check(G.select_all(layer).is_empty() and G.select_point(layer, selection.bounds.get_center(), 0).is_empty() and G.select_rect(layer, Rect2(-1000, -1000, 2000, 2000)).is_empty(), "hidden artwork cannot be selected/copied")
		selection.source = layer.to_dict().duplicate(true)
		_check(selection.matches(layer) and G.transformed(layer, selection, Transform2D.IDENTITY) == null, "hidden transform denied even with matching snapshot")
		layer.visible = true
		selection = G.select_all(layer)
		layer.id += "-other"
		_check(not selection.matches(layer) and G.transformed(layer, selection, Transform2D.IDENTITY) == null, "wrong layer identity rejected")
	_check(G.transformed(_ink(), AtlasSelection.new(), Transform2D.IDENTITY) == null, "empty transform selection denied")


func _combination() -> void:
	var layer: AtlasInkLayer = _ink()
	var a: AtlasSelection = G.select_indices(layer, [0])
	var b: AtlasSelection = G.select_indices(layer, [1])
	var add: AtlasSelection = G.combined(layer, a, b, G.CombineMode.ADD)
	_check(add.stroke_indices == [0, 1], "add selection preserves original painter order")
	_check(G.combined(layer, add, b, G.CombineMode.ADD).stroke_indices == [0, 1], "add ignores duplicate objects")
	_check(G.combined(layer, add, a, G.CombineMode.SUBTRACT).stroke_indices == [1], "subtract removes selected stroke")
	_check(G.combined(layer, add, b, G.CombineMode.SUBTRACT).stroke_indices == [0], "subtract keeps unrelated stroke")
	_check(G.combined(layer, a, AtlasSelection.new(), G.CombineMode.SUBTRACT).stroke_indices == [0], "subtract missed hit is no-op")
	_check(G.combined(layer, a, AtlasSelection.new(), G.CombineMode.ADD).stroke_indices == [0], "add missed hit is no-op")
	_check(G.combined(layer, add, AtlasSelection.new(), G.CombineMode.REPLACE).is_empty(), "replace missed hit deselects")
	var other: AtlasInkLayer = _ink()
	other.id = "other"
	_check(G.combined(other, a, G.select_indices(other, [1]), G.CombineMode.ADD).stroke_indices == [1], "selection cannot leak between layers")
	layer.strokes[0].width += 0.125
	_check(G.combined(layer, a, b, G.CombineMode.ADD).is_empty(), "stale original and incoming cannot select changed layer")
	var refreshed: AtlasSelection = G.select_indices(layer, [1])
	_check(G.combined(layer, a, refreshed, G.CombineMode.ADD).stroke_indices == [1], "stale original is discarded")
	var raster: AtlasRasterLayer = _raster()
	var raster_all: AtlasSelection = G.select_all(raster)
	_check(G.combined(raster, raster_all, raster_all, G.CombineMode.SUBTRACT).is_empty(), "raster whole-layer subtract")
	_check(G.combined(raster, raster_all, AtlasSelection.new(), G.CombineMode.SUBTRACT).raster_selected, "raster subtract miss preserves selection")
	_check(G.combined(raster, AtlasSelection.new(), raster_all, G.CombineMode.ADD).raster_selected, "raster add selects complete layer")

func _ink_transforms() -> void:
	var layer: AtlasInkLayer = _ink()
	var before: Dictionary = layer.to_dict().duplicate(true)
	var pivot: Vector2 = Vector2(-1, -0.75)
	for spec: Vector2 in [Vector2(1, 0), Vector2(2, 0), Vector2(1, PI / 2), Vector2(1.5, -0.4)]:
		var delta: Transform2D = G.about(pivot, Vector2(0.125, -0.375), spec.x, spec.y)
		_check((delta * pivot).is_equal_approx(pivot + Vector2(0.125, -0.375)), "about maps pivot to pivot plus offset")
		var result: AtlasInkLayer = G.transformed(layer, G.select_indices(layer, [0]), delta) as AtlasInkLayer
		_check(result != null, "uniform move/scale/rotation accepted")
		if result == null:
			continue
		for index: int in range(2):
			var expected: Vector2 = pivot + Vector2(0.125, -0.375) + (layer.strokes[0].points[index] - pivot).rotated(spec.y) * spec.x
			_check(result.strokes[0].points[index].is_equal_approx(expected), "continuous pivot transform retains subcells")
		_check(is_equal_approx(result.strokes[0].width, 0.5 * spec.x) and result.strokes[0].color == layer.strokes[0].color, "width scales; RGBA preserved")
		_check(result.strokes[1].to_dict() == layer.strokes[1].to_dict(), "unselected dot untouched")
		result.strokes[1].points[0] = Vector2(99, 99)
		_check(layer.to_dict() == before, "all result strokes detached; source untouched")
	for delta: Transform2D in [Transform2D(Vector2(2, 0), Vector2(0, 1), Vector2.ZERO), Transform2D(Vector2(1, 0), Vector2(0.6, 0.8), Vector2.ZERO)]:
		_check(G.transformed(layer, G.select_all(layer), delta) == null, "nonuniform/equal-length nonorthogonal ink rejected")
	for delta: Transform2D in [Transform2D(Vector2.ZERO, Vector2.DOWN, Vector2.ZERO), Transform2D(Vector2.RIGHT, Vector2.RIGHT, Vector2.ZERO), Transform2D(Vector2(INF, 0), Vector2.DOWN, Vector2.ZERO), Transform2D(Vector2.RIGHT, Vector2(0, NAN), Vector2.ZERO), Transform2D(0, Vector2(-INF, 0))]:
		for source: AtlasLayer in [layer, _raster()]:
			_check(G.transformed(source, G.select_all(source), delta) == null, "singular/nonfinite transform rejected for " + source.kind)
	_check(layer.to_dict() == before, "rejected transforms leave source untouched")

func _raster_transforms() -> void:
	var layer: AtlasRasterLayer = _raster()
	var before: Dictionary = layer.to_dict().duplicate(true)
	var pixels: PackedByteArray = layer.chunks["-1,0"].image.get_data()
	var selection: AtlasSelection = G.select_all(layer)
	_check(selection.raster_selected and selection.stroke_indices.is_empty() and selection.matches(layer), "raster selects whole layer")
	_check(selection.bounds == Rect2(-125.375, -130.25, 2, 3), "negative chunk/ppu affine AABB")
	_check(G.select_point(layer, layer.transform * Vector2(-127.5, 0.5), 0).raster_selected, "inverse affine raster hit")
	_check(G.select_point(layer, Vector2(-123.475, -130.15), 0).is_empty(), "inside AABB but outside affine quad misses")
	_check(G.select_rect(layer, selection.bounds).raster_selected and G.select_rect(layer, selection.bounds.grow(-0.01)).is_empty(), "raster marquee requires whole AABB")
	var delta: Transform2D = Transform2D(Vector2(0, 2), Vector2(-3, 0.5), Vector2(0.125, -0.375))
	var result: AtlasRasterLayer = G.transformed(layer, selection, delta) as AtlasRasterLayer
	_check(result != null, "raster accepts nonuniform rotated/sheared affine transform")
	if result == null:
		return
	_check(result.transform.is_equal_approx(delta * layer.transform) and result.pixels_per_unit == 2, "raster placement left-multiplies without resampling")
	_check(result.chunks["-1,0"].asset_id == layer.chunks["-1,0"].asset_id and result.chunks["-1,0"].image.get_data() == pixels, "affine placement preserves pixel hash and RGBA bytes")
	result.chunks["-1,0"].image.fill(Color.WHITE)
	_check(layer.to_dict() == before and layer.chunks["-1,0"].image.get_data() == pixels, "raster clone owns pixels; source untouched")
	layer.chunks["-1,0"].image.set_pixel(0, 0, Color.BLACK)
	_check(not selection.matches(layer) and G.transformed(layer, selection, delta) == null, "pixel hash change invalidates raster snapshot")
	_check(G.select_all(AtlasRasterLayer.new()).is_empty(), "empty raster has no selection")

func _scopes() -> void:
	for layer: AtlasLayer in [_ink(), _raster()]:
		var selection: AtlasSelection = G.select_all(layer)
		var delta: Transform2D = Transform2D(0, Vector2(10, 0))
		var destination: Rect2 = Rect2(selection.bounds.position + Vector2(10, 0), selection.bounds.size)
		var before: Dictionary = layer.to_dict().duplicate(true)
		_check(G.transformed(layer, selection, delta, _scope(selection.bounds.merge(destination))) != null, "scope accepts complete old/new footprints: " + layer.kind)
		_check(G.transformed(layer, selection, delta, _scope(selection.bounds)) == null, "scope denies destination outside: " + layer.kind)
		_check(G.transformed(layer, selection, delta, _scope(destination)) == null, "scope denies old footprint even when destination fits: " + layer.kind)
		_check(G.transformed(layer, selection, Transform2D.IDENTITY, _scope(selection.bounds.grow(-0.01))) == null, "scope denies padded/affine bounding footprint crossing: " + layer.kind)
		_check(G.transformed(layer, selection, delta, AtlasEditScope.new(PackedVector2Array(), true)) == null, "enabled empty scope denies transform")
		_check(G.transformed(layer, selection, delta, AtlasEditScope.new()) != null and layer.to_dict() == before, "disabled scope passes; scope operations preserve source")

func _store() -> void:
	var ink: AtlasInkLayer = _ink()
	for kind: String in ["RECTANGLE", "ELLIPSE"]:
		ink.strokes.append(Shapes.stroke(kind, Vector2(-2.125, -1.75), Vector2(0.375, 0.25), Color(0.25, 0.5, 0.75, 0.5), 0.375))
	var raster: AtlasRasterLayer = _raster()
	var moved: AtlasInkLayer = G.transformed(ink, G.select_all(ink), G.about(Vector2(-1, -0.75), Vector2(0.125, -0.375), 1.5, 0.4)) as AtlasInkLayer
	var placed: AtlasRasterLayer = G.transformed(raster, G.select_all(raster), Transform2D(Vector2(0, 2), Vector2(-3, 0.5), Vector2(0.125, -0.375))) as AtlasRasterLayer
	_check(moved != null and placed != null, "persistence transform fixtures")
	if moved == null or placed == null:
		return
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.add_map(AtlasMapDocument.new("world", "Selection persistence"))
	campaign.get_map("world").floors[0].layers = [moved, placed]
	var path: String = "user://selection_smoke_%d_%d.scn" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(AtlasCampaign.SCHEMA_VERSION == 6 and placed.to_dict().transform.size() == 6, "schema6 serializes six affine floats")
	_check(AtlasCampaignStore.save_campaign(campaign, path) == OK, "real store saves shapes/transforms/WebP")
	var loaded: AtlasCampaign = AtlasCampaignStore.load_campaign(path)
	_check(loaded != null and loaded.to_dict() == campaign.to_dict(), "real store roundtrips geometry, style, order, placement")
	if loaded != null:
		var restored: AtlasRasterLayer = loaded.get_map("world").floors[0].layer_by_id(placed.id) as AtlasRasterLayer
		_check(restored != null and restored.chunks["-1,0"].image.get_data() == raster.chunks["-1,0"].image.get_data(), "real WebP hydration preserves exact pixels and content hash")
	# Legacy JSON checkpoints are no longer accepted as user campaign files.
	for old_path: String in [path, path.trim_suffix(".scn") + ".bak.scn",
			path.trim_suffix(".scn") + ".pending.scn",
			path.trim_suffix(".scn") + ".bak.pending.scn"]:
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(old_path)
