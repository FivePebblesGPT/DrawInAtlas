extends SceneTree

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_migration()
	_validation()
	_layer_edits()
	_content_edits()
	_raster()
	print("ATLAS_LAYERS_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)

func _stroke() -> AtlasStroke:
	return AtlasStroke.new(PackedVector2Array([Vector2(-3.5, 7), Vector2(19, 2.25)]), Color(0.2, 0.4, 0.6, 0.8), 3.5)

func _campaign() -> AtlasCampaign:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "m"
	campaign.add_map(AtlasMapDocument.new("m", "Map"))
	campaign.add_map(AtlasMapDocument.new("other", "Other"))
	return campaign

func _reject(base: Dictionary, patches: Array[Dictionary], decode: Callable, label: String) -> void:
	for patch: Dictionary in patches:
		var candidate: Dictionary = base.duplicate(true)
		candidate.merge(patch, true)
		_check(decode.call(candidate) == null, "%s rejects %s" % [label, str(patch)])

func _migration() -> void:
	for version: int in [1, 2, 3]:
		var board: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 31.0)
		board.origin = Vector2(8, -9)
		board.rotation = 0.3
		var frozen: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 17.0)
		frozen.origin = Vector2(-5, 13)
		var map_data: Dictionary = {"id": "m", "name": "Map", "grid": board.to_dict(), "default_floor_id": "up", "floors": [{"id": "up", "name": "Upper", "terrain": {"-2,3": 4}, "strokes": [_stroke().to_dict()]}]}
		if version == 3:
			map_data.terrain_grid = frozen.to_dict()
		var campaign: AtlasCampaign = AtlasCampaign.from_dict({"schema_version": version, "root_map_id": "m", "maps": [map_data]})
		_check(campaign != null, "v%d migrates" % version)
		if campaign == null:
			continue
		var document: AtlasMapDocument = campaign.get_map("m")
		var floor: AtlasFloor = document.floor_by_id("up")
		_check(document.id == "m" and floor != null and floor.display_name == "Upper", "migration retains map/floor identity")
		if floor == null:
			continue
		_check(floor.layers.size() == 2 and floor.layers[0] is AtlasTileLayer and floor.layers[1] is AtlasInkLayer, "ordered typed legacy layers")
		_check(floor.layers[0].id == "terrain" and floor.layers[1].id == "ink", "stable migration layer IDs")
		_check(floor.terrain == {"-2,3": 4} and floor.strokes[0].to_dict() == _stroke().to_dict(), "legacy content retained")
		var geometry: AtlasGrid = frozen if version == 3 else board
		_check(floor.terrain_layer().grid.same_as(geometry), "legacy tile geometry retained")
		document.grid.cell_size = 999.0
		_check(floor.terrain_layer().grid.same_as(geometry), "tile geometry independent of board edits")
		var saved: Dictionary = campaign.to_dict()
		var saved_floor: Dictionary = saved.maps[0].floors[0]
		_check(saved.schema_version == AtlasCampaign.SCHEMA_VERSION and saved_floor.has("layers") and not saved_floor.has("terrain") and not saved_floor.has("strokes"), "canonical floors serialize only layers")
		var loaded: AtlasCampaign = AtlasCampaign.from_dict(saved)
		_check(loaded != null and loaded.get_map("m").floor_by_id("up").to_dict() == floor.to_dict(), "canonical round trip")

func _validation() -> void:
	var ink: Dictionary = AtlasInkLayer.new().to_dict()
	_check(AtlasLayerCodec.from_dict(ink) is AtlasInkLayer, "valid ink accepted")
	_reject(ink, [{"kind": "PAINT"}, {"kind": 1}, {"id": " "}, {"id": 1}, {"name": []}, {"name": ""}, {"opacity": -0.01}, {"opacity": 1.01}, {"opacity": INF}, {"opacity": NAN}, {"opacity": "0.5"}, {"opacity": true}, {"visible": 1}, {"locked": "false"}, {"strokes": {}}, {"strokes": [null]}], AtlasLayerCodec.from_dict, "layer metadata")
	for opacity: float in [0.0, 1.0]:
		var edge: Dictionary = ink.duplicate(true)
		edge.opacity = opacity
		_check(AtlasLayerCodec.from_dict(edge) != null, "opacity boundary accepted")
	_reject(AtlasTileLayer.new().to_dict(), [{"terrain": {"x,y": 1}}, {"terrain": {"0,0": -1}}, {"terrain": {"0,0": 1.5}}, {"grid": []}], AtlasLayerCodec.from_dict, "tile payload")
	var ref_data: Dictionary = {"coord": [-1, 2], "width": 256, "height": 1, "asset": "a".repeat(64) + ".webp"}
	var raster: Dictionary = AtlasRasterLayer.new().to_dict()
	raster.chunks = [ref_data]
	_check(AtlasLayerCodec.from_dict(raster) is AtlasRasterLayer, "valid raster reference accepted")
	for patch: Dictionary in [{"asset": "../" + ref_data.asset}, {"asset": "/tmp/" + ref_data.asset}, {"asset": "g".repeat(64) + ".webp"}, {"asset": "A".repeat(64) + ".webp"}, {"asset": "abc.webp"}, {"asset": "a".repeat(64) + ".png"}, {"width": 0}, {"width": 257}, {"height": -1}, {"height": 257}, {"width": 1.5}, {"coord": [0.5, 0]}, {"coord": [INF, 0]}]:
		var bad: Dictionary = ref_data.duplicate(true)
		bad.merge(patch, true)
		_reject(raster, [{"chunks": [bad]}], AtlasLayerCodec.from_dict, "raster reference")
	_reject(raster, [{"chunks": [ref_data, ref_data]}, {"chunks": {}}, {"pixels_per_unit": 0}, {"pixels_per_unit": NAN}], AtlasLayerCodec.from_dict, "raster metadata")
	_reject({"layers": [ink]}, [{"layers": [ink, ink]}, {"layers": [null]}, {"layers": {}}, {"terrain": {}}, {"id": []}, {"name": 1}], AtlasFloor.from_dict, "floor")
	var campaign: Dictionary = _campaign().to_dict()
	_reject(campaign, [{"schema_version": "3"}, {"schema_version": INF}, {"maps": {}}, {"maps": [null]}, {"links": {}}, {"links": [null]}, {"placements": {}}, {"placements": [null]}, {"name": []}, {"root_map_id": []}], AtlasCampaign.from_dict, "campaign")
	_reject(campaign.maps[0], [{"floors": [null]}, {"floors": {}}, {"grid": []}, {"default_floor_id": []}], AtlasMapDocument.from_dict, "map/floor boundary")
	var link: Dictionary = {"id": "l", "source_map_id": "m", "target_map_id": "other"}
	_check(AtlasMapLink.from_dict(link) != null, "valid link accepted")
	_reject(link, [{"id": []}, {"anchor": [0]}, {"target_focus": [NAN, 0]}, {"target_zoom": "1"}, {"placement_id": {}}], AtlasMapLink.from_dict, "link")
	var placement: Dictionary = {"id": "p", "parent_map_id": "m", "child_map_id": "other"}
	_check(AtlasPlacement.from_dict(placement) != null, "valid placement accepted")
	_reject(placement, [{"id": []}, {"origin": {}}, {"columns": 1.5}, {"rows": 0}, {"rotation": INF}, {"symbolic": 1}], AtlasPlacement.from_dict, "placement")

func _layer_edits() -> void:
	var campaign: AtlasCampaign = _campaign()
	var floor: AtlasFloor = campaign.get_map("m").floors[0]
	floor.ink_layer().strokes.append(_stroke())
	floor.terrain_layer().terrain["1,2"] = 3
	floor.terrain_layer().grid = AtlasGrid.new()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "m"
	for operation: String in ["add", "reorder", "name", "opacity", "visibility", "lock"]:
		var original: Dictionary = floor.to_dict()
		var before: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
		var after: Array[AtlasLayer] = AtlasLayerCodec.clone_all(before)
		match operation:
			"add": after.append(AtlasInkLayer.new("extra", "Extra"))
			"reorder": after.reverse()
			"name": after[0].display_name = "Renamed"
			"opacity": after[0].opacity = 0.25
			"visibility": after[0].visible = false
			"lock": after[0].locked = true
		var expected: Array[AtlasLayer] = AtlasLayerCodec.clone_all(after)
		var command: AtlasLayerEdit = AtlasLayerEdit.new("m", "ground", before, after)
		for source: AtlasLayer in before + after:
			if source is AtlasInkLayer and not source.strokes.is_empty():
				source.strokes[0].points[0] = Vector2(888, 888)
			if source is AtlasTileLayer:
				source.terrain["1,2"] = 99
				source.grid.origin = Vector2(777, 777)
		before[0].display_name = "mutated input"
		after[0].display_name = "mutated input"
		history.mark_saved()
		_check(history.execute(command) and history.is_dirty() and AtlasLayerCodec.same_layers(floor.layers, expected), operation + " atomic snapshot apply")
		_check(history.undo() and not history.is_dirty() and floor.to_dict() == original, operation + " deep undo restores saved state")
		_check(history.redo() and history.is_dirty() and AtlasLayerCodec.same_layers(floor.layers, expected), operation + " redo")
		history.mark_saved()
		_check(history.undo() and history.is_dirty() and history.redo() and not history.is_dirty(), operation + " saved redo checkpoint")
	var canonical: AtlasFloor = AtlasFloor.from_dict(floor.to_dict())
	_check(canonical != null and canonical.to_dict() == floor.to_dict(), "canonical order, IDs, metadata and content round trip")
	var snapshot: Dictionary = floor.to_dict()
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", floor.layers, floor.layers)) and floor.to_dict() == snapshot and not history.is_dirty(), "no-op transaction rejected")
	var next: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
	next[0].opacity = 0.7
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", [], next)) and floor.to_dict() == snapshot, "stale transaction atomic rejection")
	next.append(next[0])
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", floor.layers, next)) and floor.to_dict() == snapshot, "invalid collection atomic rejection")
	var protected: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
	(protected[0] as AtlasInkLayer).strokes.append(_stroke())
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", floor.layers, protected))
		and floor.to_dict() == snapshot, "generic layer transaction cannot overwrite hidden/locked content")
	protected = AtlasLayerCodec.clone_all(floor.layers)
	protected.remove_at(0)
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", floor.layers, protected))
		and floor.to_dict() == snapshot, "generic layer transaction cannot remove hidden/locked content")

func _content_edits() -> void:
	var campaign: AtlasCampaign = _campaign()
	var floor: AtlasFloor = campaign.get_map("m").floors[0]
	floor.layers.append(AtlasInkLayer.new("second", "Second ink"))
	campaign.get_map("m").floors.append(AtlasFloor.new())
	campaign.get_map("m").floors[1].id = "upper"
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "m"
	for tiles: bool in [false, true]:
		var layer: AtlasLayer = floor.terrain_layer() if tiles else floor.layer_by_id("second")
		for guard: String in ["hidden", "locked", "wrong type", "missing", "wrong map"]:
			layer.visible = guard != "hidden"
			layer.locked = guard == "locked"
			var target: String = layer.id
			if guard == "wrong type":
				target = "second" if tiles else "terrain"
			elif guard == "missing":
				target = "missing"
			history.active_map_id = "other" if guard == "wrong map" else "m"
			var command: AtlasEditCommand = AtlasTileEdit.new("m", "ground", target, {}, {"-1,2": 4}) if tiles else AtlasStrokeEdit.new("m", "ground", [], [_stroke()], target)
			var saved: Dictionary = floor.to_dict()
			_check(not history.execute(command) and floor.to_dict() == saved and not history.can_undo(), "content guard %s tiles=%s" % [guard, tiles])
		layer.visible = true
		layer.locked = false
	history.active_map_id = "m"
	var strokes: Array[AtlasStroke] = [_stroke()]
	var ink_edit: AtlasStrokeEdit = AtlasStrokeEdit.new("m", "ground", [], strokes, "second")
	strokes[0].points[0] = Vector2(999, 999)
	_check(history.execute(ink_edit) and (floor.layer_by_id("second") as AtlasInkLayer).strokes[0].to_dict() == _stroke().to_dict() and floor.ink_layer().strokes.is_empty(), "explicit ink target and input snapshot")
	var terrain: Dictionary = {"-1,2": 4}
	var tile_edit: AtlasTileEdit = AtlasTileEdit.new("m", "ground", "terrain", {}, terrain)
	terrain["-1,2"] = 99
	_check(history.execute(tile_edit) and floor.terrain["-1,2"] == 4, "tile input snapshot")
	_check(not history.execute(tile_edit) and not history.execute(ink_edit), "stale content edits rejected")
	_check(not history.execute(AtlasTileEdit.new("m", "ground", "terrain", floor.terrain, floor.terrain)), "tile no-op rejected")
	_check(not history.execute(AtlasStrokeEdit.new("m", "ground", [], [])), "ink no-op rejected")
	_check(not history.execute(AtlasTileEdit.new("m", "ground", "terrain", floor.terrain, {"0,0": -1})) and floor.terrain == {"-1,2": 4}, "invalid tile edit atomic rejection")
	history.active_map_id = "other"
	floor.layers.reverse()
	for layer: AtlasLayer in floor.layers:
		layer.visible = false
		layer.locked = true
	_check(history.undo() and floor.terrain.is_empty() and history.undo() and (floor.layer_by_id("second") as AtlasInkLayer).strokes.is_empty(), "undo uses original map/floor/layer IDs despite selection and flags")
	_check(campaign.get_map("other").floors[0].strokes.is_empty() and campaign.get_map("m").floors[1].terrain.is_empty(), "other targets untouched")
	_check(AtlasStrokeEdit.new("m", "ground", [], [_stroke()]).layer_id == "ink", "four-argument ink compatibility")

func _raster() -> void:
	var image: Image = Image.create_empty(513, 257, true, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	image.set_pixel(512, 256, Color.BLUE)
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(image, 2.0)
	_check(raster != null and raster.chunks.size() == 6 and raster.pixels_per_unit == 2.0, "raster chunk count and scale")
	if raster == null:
		return
	for chunk: AtlasRasterChunk in raster.chunks.values():
		_check(chunk.is_valid(true) and chunk.width <= 256 and chunk.height <= 256 and chunk.image.get_format() == Image.FORMAT_RGBA8 and not chunk.image.has_mipmaps(), "bounded canonical RGBA8 chunk")
	_check(raster.chunks["2,1"].width == 1 and raster.chunks["2,1"].height == 1 and raster.chunks["2,1"].image.get_pixel(0, 0) == Color.BLUE, "partial chunk retains edge pixels")
	for point: Vector2i in [Vector2i(-1, -257), Vector2i(-256, 255), Vector2i(256, -256)]:
		_check(AtlasRasterLayer.pixel_to_chunk(point) == Vector2i(floori(float(point.x) / 256.0), floori(float(point.y) / 256.0)), "negative chunk coordinates use floor")
	var copy: AtlasRasterLayer = AtlasLayerCodec.clone(raster) as AtlasRasterLayer
	image.fill(Color.GREEN)
	raster.chunks["0,0"].image.fill(Color.BLUE)
	_check(copy != null and copy.chunks["0,0"].image.get_pixel(0, 0) == Color.RED and raster.chunks["2,1"].image.get_pixel(0, 0) == Color.BLUE, "clone and source image independently owned")
	if copy == null:
		return
	var campaign: AtlasCampaign = _campaign()
	var floor: AtlasFloor = campaign.get_map("m").floors[0]
	var after: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
	after.append(copy)
	var edit: AtlasLayerEdit = AtlasLayerEdit.new("m", "ground", floor.layers, after)
	copy.chunks["0,0"].image.fill(Color.GREEN)
	_check(edit.apply(campaign) and (floor.layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED, "raster command snapshots caller images")
	copy.chunks["0,0"].image.fill(Color.BLUE)
	_check((floor.layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED, "post-apply caller edits remain isolated")
	(floor.layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.fill(Color.BLUE)
	_check(not edit.revert(campaign), "raster stale pixel data rejected")
	(floor.layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.fill(Color.RED)
	_check(edit.revert(campaign) and edit.apply(campaign) and (floor.layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED, "applied images do not alias command redo snapshot")
