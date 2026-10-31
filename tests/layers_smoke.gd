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
	for version: int in [1, 2, 3, 4, 5, 6]:
		var old: Dictionary = _campaign().to_dict()
		old.schema_version = version
		_check(AtlasCampaign.from_dict(old) == null, "retired prototype schema rejected v%d" % version)
	var canonical: Dictionary = _campaign().to_dict()
	_check(AtlasCampaign.from_dict(canonical) != null, "current schema accepted")

func _validation() -> void:
	var ink: Dictionary = AtlasInkLayer.new().to_dict()
	_check(AtlasLayerCodec.from_dict(ink) is AtlasInkLayer, "valid ink accepted")
	_reject(ink, [{"kind": "PAINT"}, {"kind": 1}, {"id": " "}, {"id": 1}, {"name": []}, {"name": ""}, {"opacity": -0.01}, {"opacity": 1.01}, {"opacity": INF}, {"opacity": NAN}, {"opacity": "0.5"}, {"opacity": true}, {"visible": 1}, {"locked": "false"}, {"strokes": {}}, {"strokes": [null]}], AtlasLayerCodec.from_dict, "layer metadata")
	for opacity: float in [0.0, 1.0]:
		var edge: Dictionary = ink.duplicate(true)
		edge.opacity = opacity
		_check(AtlasLayerCodec.from_dict(edge) != null, "opacity boundary accepted")
	_check(AtlasLayerCodec.from_dict({"id": "terrain", "name": "Old", "kind": "TILES", "terrain": {"0,0": 1}}) == null, "retired tile kind rejected")
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
	floor.layers[0].locked = true
	var snapshot: Dictionary = floor.to_dict()
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", floor.layers, floor.layers)) and floor.to_dict() == snapshot and not history.is_dirty(), "no-op transaction rejected")
	var next: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
	next[0].opacity = 0.7
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", [], next)) and floor.to_dict() == snapshot, "stale transaction atomic rejection")
	next.append(next[0])
	_check(not history.execute(AtlasLayerEdit.new("m", "ground", floor.layers, next)) and floor.to_dict() == snapshot, "invalid collection atomic rejection")
	var protected: Array[AtlasLayer] = AtlasLayerCodec.clone_all(floor.layers)
	if protected[0] is AtlasInkLayer:
		(protected[0] as AtlasInkLayer).strokes.append(_stroke())
	else:
		var image: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED)
		(protected[0] as AtlasRasterLayer).chunks["0,0"] = AtlasRasterChunk.new(Vector2i.ZERO, image)
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
	var layer: AtlasInkLayer = floor.layer_by_id("second") as AtlasInkLayer
	for guard: String in ["hidden", "locked", "wrong type", "missing", "wrong map"]:
		layer.visible = guard != "hidden"
		layer.locked = guard == "locked"
		var target: String = "raster" if guard == "wrong type" else "missing" if guard == "missing" else "second"
		history.active_map_id = "other" if guard == "wrong map" else "m"
		var command: AtlasStrokeEdit = AtlasStrokeEdit.new("m", "ground", [], [_stroke()], target)
		var saved: Dictionary = floor.to_dict()
		_check(not history.execute(command) and floor.to_dict() == saved and not history.can_undo(), "content guard " + guard)
	layer.visible = true
	layer.locked = false
	history.active_map_id = "m"
	var strokes: Array[AtlasStroke] = [_stroke()]
	var ink_edit: AtlasStrokeEdit = AtlasStrokeEdit.new("m", "ground", [], strokes, "second")
	strokes[0].points[0] = Vector2(999, 999)
	_check(history.execute(ink_edit) and (floor.layer_by_id("second") as AtlasInkLayer).strokes[0].to_dict() == _stroke().to_dict() and floor.ink_layer().strokes.is_empty(), "explicit ink target and input snapshot")
	_check(not history.execute(ink_edit), "stale ink content edit rejected")
	_check(not history.execute(AtlasStrokeEdit.new("m", "ground", [], [])), "ink no-op rejected")
	history.active_map_id = "other"
	floor.layers.reverse()
	for item: AtlasLayer in floor.layers:
		item.visible = false
		item.locked = true
	_check(history.undo() and (floor.layer_by_id("second") as AtlasInkLayer).strokes.is_empty(), "undo uses original layer ID despite selection and flags")
	_check(campaign.get_map("other").floors[0].strokes.is_empty() and campaign.get_map("m").floors[1].strokes.is_empty(), "other targets untouched")
	_check(AtlasStrokeEdit.new("m", "ground", [], [_stroke()]).layer_id == "ink", "default ink target remains explicit")

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
	copy.id = "imported"
	after.append(copy)
	var edit: AtlasLayerEdit = AtlasLayerEdit.new("m", "ground", floor.layers, after)
	copy.chunks["0,0"].image.fill(Color.GREEN)
	_check(edit.apply(campaign) and (floor.layer_by_id("imported") as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED, "raster command snapshots caller images")
	copy.chunks["0,0"].image.fill(Color.BLUE)
	_check((floor.layer_by_id("imported") as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED, "post-apply caller edits remain isolated")
	(floor.layer_by_id("imported") as AtlasRasterLayer).chunks["0,0"].image.fill(Color.BLUE)
	_check(not edit.revert(campaign), "raster stale pixel data rejected")
	(floor.layer_by_id("imported") as AtlasRasterLayer).chunks["0,0"].image.fill(Color.RED)
	_check(edit.revert(campaign) and edit.apply(campaign) and (floor.layer_by_id("imported") as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED, "applied images do not alias command redo snapshot")
