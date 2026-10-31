extends SceneTree
## T-050: raster/ink artwork is independent of grid geometry and cell scopes.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RASTER/INK MODEL FAILED: " + label)


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "board"
	var board: AtlasMapDocument = AtlasMapDocument.new("board", "Board")
	board.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 32.0)
	campaign.add_map(board)
	var floor: AtlasFloor = board.floors[0]
	_check(floor.layers.size() == 2 and floor.layers[0] is AtlasRasterLayer
		and floor.layers[1] is AtlasInkLayer, "new floors contain raster and editable ink")
	var ink: AtlasInkLayer = floor.ink_layer()
	ink.strokes.append(AtlasStroke.new(PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])))
	var ink_before: Dictionary = ink.to_dict()
	var raster: AtlasRasterLayer = floor.layer_by_id("raster") as AtlasRasterLayer
	var original_grid: AtlasGrid = board.grid.copy()
	var scope: AtlasEditScope = AtlasEditScope.new(board.grid.cell_polygon(Vector2i.ZERO), true)
	var center: Vector2 = board.grid.cell_to_document(Vector2i.ZERO) + Vector2(0.5, 0.5)
	var stroke: PackedVector2Array = PackedVector2Array([center])
	var painted: AtlasFillResult = AtlasRasterBrush.paint(raster, stroke, Color.RED, 1.0, false, scope)
	_check(painted.ok and painted.layer != null and raster.chunks.is_empty(),
		"cell-scoped brush stages raster bytes without mutating source")
	if painted.layer == null:
		quit(1)
		return
	var before: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
	var after: Array[AtlasLayer] = AtlasLayerCodec.clone_all(before)
	after[0] = painted.layer
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = board.id
	_check(history.execute(AtlasLayerEdit.new(board.id, floor.id, before, after)),
		"raster chunk commit is one undoable layer transaction")
	var current: AtlasRasterLayer = floor.layer_by_id("raster") as AtlasRasterLayer
	var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(Vector2i(center))
	var key: String = "%d,%d" % [coord.x, coord.y]
	_check(current.chunks.has(key), "raster stroke allocates signed chunk at document pixel")
	var snapshot: PackedByteArray = current.chunks[key].image.get_data().duplicate()
	var refused: AtlasFillResult = AtlasRasterBrush.paint(current,
		PackedVector2Array([center + Vector2(200, 200)]), Color.BLUE, 1.0, false, scope)
	_check(not refused.ok and current.chunks[key].image.get_data() == snapshot,
		"out-of-cell brush attempt preserves source bytes atomically")
	board.grid.origin = Vector2(-19.5, 4.25)
	board.grid.rotation = 0.25
	_check(current.chunks[key].image.get_data() == snapshot and ink.to_dict() == ink_before,
		"grid geometry changes never rebase or rewrite authored pixels/ink")
	_check(history.undo() and (floor.layer_by_id("raster") as AtlasRasterLayer).chunks.is_empty(),
		"undo restores original empty raster without touching ink")
	_check(history.redo() and (floor.layer_by_id("raster") as AtlasRasterLayer).chunks[key].image.get_data() == snapshot,
		"redo restores exact RGBA8 bytes after independent grid changes")
	var encoded: Dictionary = campaign.to_dict()
	_check(encoded.schema_version == 7 and not encoded.maps[0].has("terrain_grid")
		and not encoded.maps[0].floors[0].has("terrain"),
		"current schema has no palette-cell artwork or frozen terrain grid")
	_check(AtlasCampaign.from_dict(encoded) != null, "current dictionary validates raster and ink")
	var obsolete: Dictionary = encoded.duplicate(true)
	obsolete.schema_version = 6
	_check(AtlasCampaign.from_dict(obsolete) == null, "prototype schema v6 is deliberately unsupported")
	obsolete = encoded.duplicate(true)
	obsolete.maps[0].terrain_grid = original_grid.to_dict()
	_check(AtlasCampaign.from_dict(obsolete) == null, "retired terrain-grid field rejected")
	obsolete = encoded.duplicate(true)
	obsolete.maps[0].floors[0].layers.append({"id": "terrain", "name": "Terrain", "kind": "TILES", "terrain": {"0,0": 2}})
	_check(AtlasCampaign.from_dict(obsolete) == null, "retired TILES layer cannot enter a current campaign")
	_check(not AtlasCanvas.Tool.has("PAINT"), "palette painting tool has no runtime route")
	var saved: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	var loaded: AtlasCampaign = AtlasNativeScene.unpack_campaign(saved)
	_check(loaded != null, "current native scene roundtrip works")
	if loaded != null:
		var floor_copy: AtlasFloor = loaded.get_map("board").floors[0]
		var pixels_copy: AtlasRasterLayer = floor_copy.layer_by_id("raster") as AtlasRasterLayer
		_check(pixels_copy != null and pixels_copy.chunks[key].image.get_data() == snapshot
			and floor_copy.ink_layer().to_dict() == ink_before,
			"native scene preserves independent raster bytes and semantic ink")
	print("ATLAS_RASTER_INK_MODEL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
