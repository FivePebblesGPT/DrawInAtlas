extends SceneTree
## Run with --headless --path . --script res://tests/board_grid_smoke.gd

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	_creation()
	_creation_guards()
	_overlay()
	_validation()
	_persistence()
	if failures == 0:
		print("ATLAS_BOARD_GRID_PASSED (%d checks)" % checks)
	else:
		push_error("ATLAS_BOARD_GRID_FAILED: %d of %d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("BOARD GRID FAILED: " + description)


func _campaign() -> AtlasCampaign:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var map: AtlasMapDocument = campaign.get_map("world")
	map.grid.origin = Vector2(-3.125, 7.25)
	map.grid.rotation = 0.123456789012345
	map.floors.append(AtlasFloor.new())
	map.floors[1].id = "upper"
	for floor: AtlasFloor in map.floors:
		floor.paint(Vector2i(-2, 3), 7)
		floor.strokes.append(AtlasStroke.new(PackedVector2Array([
			Vector2(-12.875, 0.125), Vector2(0.375, -3.625), Vector2(55.25, 9.5)
		]), Color(0.125, 0.375, 0.625, 0.5), 2.123456789012345))
	return campaign


func _history(campaign: AtlasCampaign) -> AtlasEditHistory:
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	return history


func _creation() -> void:
	var campaign: AtlasCampaign = _campaign()
	var history: AtlasEditHistory = _history(campaign)
	var baseline: Dictionary = campaign.to_dict()
	for kind: int in AtlasGrid.Kind.values():
		for unit: String in ["mi", "km", "ft", "m", "tiles"]:
			var input: AtlasMapDocument = AtlasMapDocument.new("blank-%d-%s" % [kind, unit], "Blank")
			input.grid = AtlasGrid.new(kind, 37.5)
			input.grid.distance_per_cell = 2.5
			input.grid.distance_unit = unit
			var expected: Dictionary = input.to_dict()
			var command: AtlasCreateMap = AtlasCreateMap.new("world", input)
			input.grid.cell_size = 999.0
			input.floors[0].paint(Vector2i.ZERO, 99)
			input.display_name = "Caller mutation"
			_check(history.execute(command), "create kind %d / native %s" % [kind, unit])
			var created: AtlasMapDocument = campaign.get_map(command.new_map_id)
			_check(created != null and created.to_dict() == expected, "creation captures independent blank document")
			_check(campaign.links.size() == 1 and campaign.placements.is_empty(), "creation copies no links or placements")
			_check(history.is_dirty() and history.undo(), "creation is dirty and undoable")
			_check(campaign.to_dict() == baseline and not history.is_dirty(), "undo removes only new map")
			_check(history.redo() and campaign.get_map(command.new_map_id) != null, "redo retains stable map ID")
			_check(campaign.get_map(command.new_map_id).to_dict() == expected, "redo restores captured document")
			_check(history.undo(), "creation cleanup undo")


func _creation_guards() -> void:
	var campaign: AtlasCampaign = _campaign()
	var history: AtlasEditHistory = _history(campaign)
	var baseline: Dictionary = campaign.to_dict()
	var invalid: AtlasMapDocument = AtlasMapDocument.new("bad-grid", "Invalid")
	invalid.grid.distance_per_cell = 0.0
	for document: AtlasMapDocument in [AtlasMapDocument.new("world", "Duplicate"),
			AtlasMapDocument.new("blank-name", " \t"), AtlasMapDocument.new(" ", "Blank ID"), invalid]:
		_check(not history.execute(AtlasCreateMap.new("world", document)), "reject duplicate ID, blank name/ID or invalid grid")
	_check(campaign.to_dict() == baseline and not history.is_dirty() and not history.can_undo(), "rejections are atomic")
	_check(history.execute(AtlasCreateMap.new("world", AtlasMapDocument.new("new", "New"))), "stale-undo setup")
	campaign.get_map("new").floors[0].paint(Vector2i.ZERO, 4)
	_check(not history.undo() and campaign.get_map("new") != null, "changed created map prevents stale undo")
	campaign.get_map("new").floors[0].terrain.clear()
	var link: AtlasMapLink = AtlasMapLink.new()
	for outgoing: bool in [false, true]:
		link.source_map_id = "new" if outgoing else "world"
		link.target_map_id = "world" if outgoing else "new"
		campaign.links.append(link)
		_check(not history.undo() and campaign.get_map("new") != null, "incoming/outgoing link prevents creation undo")
		campaign.links.pop_back()
	_check(history.undo() and campaign.to_dict() == baseline, "failed stale undo preserves history cursor")


func _polygons(map: AtlasMapDocument) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for floor: AtlasFloor in map.floors:
		var keys: Array = floor.terrain.keys()
		keys.sort()
		for key: String in keys:
			var xy: PackedStringArray = key.split(",")
			result.append(map.get_terrain_grid().cell_polygon(Vector2i(int(xy[0]), int(xy[1]))))
	return result


func _overlay() -> void:
	var campaign: AtlasCampaign = _campaign()
	var map: AtlasMapDocument = campaign.get_map("world")
	var history: AtlasEditHistory = _history(campaign)
	var floors: Array = map.to_dict()["floors"]
	var polygons: Array[PackedVector2Array] = _polygons(map)
	var other: Dictionary = campaign.get_map("greyhaven").to_dict()
	var original: AtlasGrid = map.grid.copy()
	_check(map.terrain_grid == null and map.get_terrain_grid() == map.grid, "legacy terrain initially uses overlay basis")
	var changes: Dictionary = {"cell_size": 17.25, "kind": AtlasGrid.Kind.HEX_FLAT,
		"origin": Vector2(-29.5, 33.125), "rotation": -0.987654321098765,
		"distance_per_cell": 0.375, "distance_unit": "km", "visible": false}
	for field: String in changes:
		var before: AtlasGrid = map.grid.copy()
		var after: AtlasGrid = before.copy()
		after.set(field, changes[field])
		var expected: AtlasGrid = after.copy()
		var command: AtlasGridEdit = AtlasGridEdit.new("world", before, after)
		before.cell_size = 888.0
		after.cell_size = 999.0
		_check(history.execute(command) and map.grid.same_as(expected), "captured overlay edit: " + field)
		var detached: AtlasGrid = map.grid
		history.active_map_id = "greyhaven"
		_check(history.undo(), "overlay undo after navigation: " + field)
		detached.origin = Vector2(999.0, 999.0)
		_check(history.redo() and map.grid.same_as(expected), "redo independent of detached/caller grids: " + field)
		history.active_map_id = "world"
		_check(map.get_terrain_grid().same_as(original), "terrain basis remains frozen: " + field)
		_check(map.to_dict()["floors"] == floors and _polygons(map) == polygons, "exact strokes, terrain and polygon locations: " + field)
		_check(campaign.get_map("greyhaven").to_dict() == other, "other map artwork and native units unchanged: " + field)
	history.mark_saved()
	_check(not history.is_dirty() and history.undo() and history.is_dirty(), "undo away from saved grid is dirty")
	_check(history.redo() and not history.is_dirty(), "redo reaches clean saved grid")
	_check(history.undo(), "prepare divergent grid branch")
	var branch: AtlasGrid = map.grid.copy()
	branch.cell_size += 1.0
	_check(history.execute(AtlasGridEdit.new("world", map.grid, branch)) and history.is_dirty(), "same-length branch remains dirty")
	_check(not history.redo() and history.undo() and history.is_dirty(), "branch drops redo without reviving saved checkpoint")
	var unchanged: Dictionary = map.to_dict()
	var invalid: AtlasGrid = map.grid.copy()
	invalid.rotation = NAN
	_check(not history.execute(AtlasGridEdit.new("world", map.grid, invalid)), "invalid grid command rejected")
	_check(not history.execute(AtlasGridEdit.new("world", map.grid, map.grid)), "grid no-op rejected")
	_check(not history.execute(AtlasGridEdit.new("world", original, branch)), "stale before grid rejected")
	_check(map.to_dict() == unchanged and history.can_redo(), "rejected grid edits preserve document and redo")


func _validation() -> void:
	var valid: AtlasGrid = AtlasGrid.new()
	var copy: AtlasGrid = valid.copy()
	copy.visible = false
	copy.distance_unit = "tiles"
	copy.distance_per_cell = 1.0
	_check(copy.same_geometry(valid) and not copy.same_as(valid) and valid.visible and valid.distance_unit == "mi", "copy independence and geometry/native equality")
	var cases: Dictionary = {"kind": [-1, 4, 1.5, "1", true, null, INF, -INF, NAN],
		"cell_size": [0, -1, "48", true, null, INF, -INF, NAN],
		"origin": [[], [0], [0, 0, 0], "0,0", null, [true, 0], [0, "x"], [INF, 0], [0, -INF], [NAN, 0], [0, NAN]],
		"rotation": ["0", true, null, INF, -INF, NAN],
		"distance_per_cell": [0, -1, "6", false, null, INF, -INF, NAN],
		"distance_unit": ["", " \t", 1, false, null], "visible": [0, "false", null]}
	for field: String in cases:
		for value: Variant in cases[field]:
			var data: Dictionary = valid.to_dict()
			data[field] = value
			_check(AtlasGrid.from_dict(data) == null, "reject malformed grid %s=%s" % [field, str(value)])
			if field in ["cell_size", "rotation", "distance_per_cell"] and (value is int or value is float):
				var bad: AtlasGrid = valid.copy()
				bad.set(field, value)
				_check(not bad.is_valid(), "in-memory invalid " + field)


func _persistence() -> void:
	var defaults: AtlasGrid = AtlasGrid.from_dict({})
	_check(defaults != null and defaults.same_as(AtlasGrid.new()), "missing legacy grid fields default consistently")
	for version: int in [1, 2]:
		var legacy: Dictionary = {"schema_version": version, "root_map_id": "world",
			"maps": [{"id": "world", "name": "Legacy", "grid": {}, "floors": [{"terrain": {"-2,3": 7}}]}]}
		var loaded: AtlasCampaign = AtlasCampaign.from_dict(legacy)
		_check(loaded != null, "read legacy schema %d" % version)
		if loaded != null:
			var map: AtlasMapDocument = loaded.get_map("world")
			_check(map.grid.same_as(defaults) and map.get_terrain_grid().same_as(defaults)
				and map.floors[0].strokes.is_empty() and map.floors[0].get_terrain(Vector2i(-2, 3)) == 7, "legacy artwork and frozen basis defaults")
	var campaign: AtlasCampaign = _campaign()
	var map: AtlasMapDocument = campaign.get_map("world")
	var overlay: AtlasGrid = map.grid.copy()
	overlay.rotation = -0.987654321098765
	overlay.kind = AtlasGrid.Kind.SQUARE
	_check(_history(campaign).execute(AtlasGridEdit.new("world", map.grid, overlay)), "persistence freezes distinct terrain basis")
	var restored: AtlasCampaign = AtlasCampaign.from_dict(campaign.to_dict())
	_check(restored != null and restored.to_dict() == campaign.to_dict()
		and campaign.to_dict()["schema_version"] == AtlasCampaign.SCHEMA_VERSION, "current schema dictionary roundtrip")
	for field: String in ["grid", "terrain_grid"]:
		var bad: Dictionary = campaign.to_dict()
		bad["maps"][0][field] = {"rotation": NAN}
		_check(AtlasCampaign.from_dict(bad) == null, "campaign rejects invalid " + field)
	var path: String = "user://board_grid_smoke_%d_%d.scn" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(AtlasCampaignStore.save_campaign(campaign, path) == OK, "real store writes unique test file")
	restored = AtlasCampaignStore.load_campaign(path)
	_check(restored != null, "real store reloads schema 3 campaign")
	if restored != null:
		var loaded: AtlasMapDocument = restored.get_map("world")
		_check(loaded.grid.same_as(map.grid) and loaded.get_terrain_grid().same_as(map.get_terrain_grid()), "real store preserves exact full-precision overlay and terrain rotations")
		for index: int in range(map.floors.size()):
			_check(AtlasStroke.same_artwork(loaded.floors[index].strokes, map.floors[index].strokes), "real store preserves exact stroke points, width and color")
			# JSON numbers load as floats; compare palette values, not Variant types.
			_check(loaded.floors[index].terrain.size() == map.floors[index].terrain.size(), "real store preserves terrain count")
			for key: String in map.floors[index].terrain:
				_check(loaded.floors[index].terrain.has(key) and loaded.floors[index].terrain[key] == map.floors[index].terrain[key], "real store preserves terrain cell " + key)
		_check(_polygons(loaded) == _polygons(map), "real store preserves legacy polygon locations")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "remove unique persistence fixture")
