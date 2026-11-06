extends SceneTree
## T-061: Atlas-owned mapping, one generic document per floor/detail,
## signed ticks, blank authored LOD and independent overlays.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, why: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T061_FAILED: " + why)


func _paint(registry: AtlasDrawingRegistry, map_id: String, floor_id: String, level: int,
		layer: String, x_ticks: int, y_ticks: int, rgba: int) -> bool:
	var begun: DrawingResult = registry.begin_world_gesture(map_id, floor_id, level, layer, x_ticks, y_ticks)
	if not begun.ok:
		push_error("T061_GESTURE: " + begun.code + " " + begun.message)
		return false
	var session: DrawingEditSession = begun.value["session"]
	var painted: DrawingResult = session.apply_region(Rect2i(0, 0, 1, 1), PackedByteArray([
		rgba & 255, (rgba >> 8) & 255, (rgba >> 16) & 255, (rgba >> 24) & 255]))
	return painted.ok and session.commit().ok


func _pixel(registry: AtlasDrawingRegistry, level: int, layer: String, x_ticks: int,
		y_ticks: int) -> int:
	var doc: DrawingDocument = registry.document_at("world", "ground", level).value
	var pixel: DrawingResult = AtlasWorldSpace.point_to_pixels(x_ticks, y_ticks,
		doc.density_numerator, doc.density_denominator)
	if not pixel.ok:
		return -1
	return int(doc.read_pixel(layer, pixel.value["x"], pixel.value["y"]).value)


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	_check(campaign != null, "sample campaign available")
	if campaign == null:
		quit(1)
		return
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	_check(registry.attach_campaign(campaign).ok, "map/floor groups initialized from campaign")
	_check(registry.document_count() == 0, "mapping is lazy, zero materialized documents")
	var original: Array[Dictionary] = registry.projection("world")
	_check(not original.is_empty() and original[0]["id"] == "ground", "ground floor group projects in order")
	_check(original[0]["details"].size() == 1 and original[0]["details"][0]["id"] == "D0",
		"D0 logical group created without tiles")
	var d0: String = original[0]["details"][0]["document_id"]
	_check(DrawingDocument.valid_identifier(d0), "opaque stable internal document ID")
	_check(not registry.ensure_detail("world", "ground", 1).value == d0,
		"distinct D1 internal document identity")
	var d1: String = registry.ensure_detail("world", "ground", 1).value
	var d32: String = registry.ensure_detail("world", "ground", 32, 9, 4, 32).value
	_check(d1 != d32 and d1 != d0 and d32 != d0, "three distinct detail IDs")
	_check(registry.ensure_detail("world", "ground", 1).value == d1, "idempotent detail resolution")
	_check(registry.projection("world")[0]["details"][1]["density"] == [2, 1],
		"D1 default rational density is 2 px/world unit")
	_check(registry.projection("world")[0]["details"][2]["density"] == [9, 4],
		"D32 explicit rational density is retained")
	_check(registry.document_count() == 0, "enumerating D0 D1 D32 never allocates Drawing")
	_check(not registry.ensure_detail("world", "ground", -1).ok and
		not registry.ensure_detail("world", "ground", 33).ok, "D-level bounds enforced")
	_check(not registry.ensure_detail("missing", "ground", 1).ok, "foreign map rejected")
	_check(not registry.ensure_detail("world", "ground", 2, 3, 0).ok, "invalid density rejected")
	_check(not registry.ensure_detail("world", "ground", 2, 3, 1, 5000).ok, "invalid stride rejected")

	for pair: Array in [[-1025, -2, -3, -3], [-1024, -1, -2, -3], [-1, -1, -1, -1],
		[0, 0, 0, 0], [512, 0, 1, 1], [1024, 1, 2, 2], [1536, 1, 3, 3]]:
		_check(AtlasWorldSpace.world_to_pixel(pair[0], 1, 1).value == pair[1],
			"D0 signed half-open conversion @%d" % pair[0])
		_check(AtlasWorldSpace.world_to_pixel(pair[0], 2, 1).value == pair[2],
			"D1 signed half-open conversion @%d" % pair[0])
	_check(AtlasWorldSpace.world_to_pixel(-1, 9, 4).value == -1, "D32 negative fractional boundary")
	_check(AtlasWorldSpace.world_to_pixel(2048, 9, 4).value == 4, "D32 explicit fraction positive")
	_check(not AtlasWorldSpace.world_to_pixel(AtlasWorldSpace.MAX_TICKS + 1, 1, 1).ok,
		"unsafe world ticks rejected")
	_check(not AtlasWorldSpace.world_to_pixel(1, 0, 1).ok, "zero density rejected")
	_check(not AtlasWorldSpace.world_to_pixel(AtlasWorldSpace.MAX_TICKS, 1048576, 1).ok,
		"unsafe product rejected without overflow")
	_check(AtlasWorldSpace.default_density(32) == 1024, "bounded default D32 progression")
	_check(AtlasWorldSpace.snap_ticks(-1300, 1024).value == -1024, "negative world-grid snapping")
	_check(AtlasWorldSpace.snap_ticks(512, 1024).value == 1024, "grid half-step rounds up")
	_check(AtlasWorldSpace.snap_ticks(512, 1024, 256).value == 256, "grid origin offset")
	_check(not AtlasWorldSpace.snap_ticks(20, 0).ok, "invalid grid rejected")

	# One coordinate is shared between details, but pixel indices are independent.
	var anchor_x: int = 1024 * 37
	var anchor_y: int = -1024 * 13
	var p0: Dictionary = AtlasWorldSpace.point_to_pixels(anchor_x, anchor_y, 1, 1).value
	var p1: Dictionary = AtlasWorldSpace.point_to_pixels(anchor_x, anchor_y, 2, 1).value
	var p32: Dictionary = AtlasWorldSpace.point_to_pixels(anchor_x, anchor_y, 9, 4).value
	_check(p0 == {"x": 37, "y": -13}, "D0 consistent map coordinate")
	_check(p1 == {"x": 74, "y": -26}, "D1 same world position at doubled density")
	_check(p32 == {"x": 83, "y": -30}, "D32 same world at explicit density")
	var doc0: DrawingDocument = registry.document_at("world", "ground", 0, true).value
	var layer0: String = String(doc0.create_layer(DrawingLayerNode.RASTER, "Overview").value)
	_check(_paint(registry, "world", "ground", 0, layer0, anchor_x, anchor_y, 0xff332211),
		"paint at D0 through Atlas world-tick anchor")
	_check(registry.document_count() == 1, "authoring D0 materializes one document")
	_check(registry.projection("world")[0]["details"][0]["blank"] == false,
		"committed D0 is authored")
	_check(registry.projection("world")[0]["details"][1]["blank"] == true,
		"uncreated D1 explicitly reports empty")
	var blank: DrawingResult = registry.render_detail("world", "ground", 1, Rect2i(74, -26, 3, 3))
	_check(blank.ok and blank.value.get_data().count(0) == 3 * 3 * 4,
		"D1 is transparent with NO D0 underlay")
	_check(registry.document_count() == 1, "blank high detail rendering allocates no document or tile")
	_check(not registry.render_detail("world", "ground", 1, Rect2i(0, 0, 10000, 10000)).ok,
		"blank detail cannot bypass bounded render guard")
	var doc1: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var layer1: String = String(doc1.create_layer(DrawingLayerNode.RASTER, "Details").value)
	_check(registry.projection("world")[0]["details"][1]["blank"],
		"creating an unpainted layer does not author pixels")
	_check(_paint(registry, "world", "ground", 1, layer1, anchor_x, anchor_y, 0x00998877),
		"D1 keeps hidden RGB even with zero alpha")
	_check(_pixel(registry, 1, layer1, anchor_x, anchor_y) == 0x00998877,
		"D1 exact RGBA8 bytes remain independent")
	_check(_pixel(registry, 0, layer0, anchor_x, anchor_y) == 0xff332211,
		"D0 pixels unchanged by D1 edit")
	_check(not registry.set_density("world", "ground", 1, 3, 1).ok,
		"density frozen after authored gesture")
	_check(registry.set_density("world", "ground", 32, 5, 2).ok,
		"uncreated D32 density may be explicitly adjusted")
	_check(registry.projection("world")[0]["details"][2]["density"] == [5, 2],
		"density adjustment updates projection")
	_check(registry.set_visibility("world", "ground", 0, false).ok,
		"floor/detail group visibility editable")
	_check(registry.render_detail("world", "ground", 0, Rect2i(37, -13, 1, 1)).value.get_data()[3] == 0,
		"hidden detail suppresses its artwork")
	_check(registry.set_visibility("world", "ground", 0, true).ok,
		"detail visibility can restore authored artwork")
	_check(registry.render_detail("world", "ground", 0, Rect2i(37, -13, 1, 1)).value.get_data()[3] == 255,
		"visible D0 renders exact alpha")
	_check(registry.set_visibility("world", "ground", -1, false).ok,
		"floor group visibility gates all details")
	_check(not registry.projection("world")[0]["details"][0]["visible"], "floor hidden in projection")
	_check(registry.set_visibility("world", "ground", -1, true).ok, "floor restores visibility")

	# A pending D0 gesture remains owned by D0 even when a viewer switches to D32.
	var frozen: DrawingResult = registry.begin_world_gesture("world", "ground", 0, layer0, 0, 0)
	_check(frozen.ok and frozen.value["document_id"] == d0 and frozen.value["level"] == 0,
		"gesture captures D0 target identity")
	var future: DrawingResult = registry.ensure_detail("world", "ground", 32)
	_check(future.value == d32, "presented D32 switch changes no active gesture")
	_check(frozen.value["session"].apply_region(Rect2i(0, 0, 1, 1),
		PackedByteArray([1, 2, 3, 255])).ok and frozen.value["session"].commit().ok,
		"gesture commits to originally captured document")
	_check(doc0.read_pixel(layer0, 0, 0).value == 0xff030201,
		"D0 owns in-flight edit after view switch")
	_check(registry.projection("world")[0]["details"][2]["blank"] == true,
		"D32 still remains logically blank")

	# Huge signed positions use camera-relative tiles, not float32 world transforms.
	var far_x: int = 1000000000000000
	var far_y: int = -1000000000000000
	_check(AtlasWorldSpace.camera_relative(far_x + 1024, far_x, 3.0).value == 3.0,
		"camera rebase retains one-world-unit precision at distant anchor")
	_check(not AtlasWorldSpace.camera_relative(far_x + 2000000000000, far_x).ok,
		"out-of-viewport camera offsets rejected")
	_check(_paint(registry, "world", "ground", 0, layer0, far_x, far_y, 0xffabcdef),
		"distant mark is authored through 64-bit anchor + bounded local edit")
	_check(_pixel(registry, 0, layer0, far_x, far_y) == 0xffabcdef,
		"distant signed pixel read exact")
	_check(doc0.tile_keys(layer0).size() <= 3,
		"sparse far marks allocate bounded tile count")
	var far_pixel_x: int = AtlasWorldSpace.world_to_pixel(far_x, 1, 1).value
	var far_pixel_y: int = AtlasWorldSpace.world_to_pixel(far_y, 1, 1).value
	var far_render: DrawingResult = registry.render_detail_at("world", "ground", 0,
		Rect2i(0, 0, 1, 1), far_pixel_x, far_pixel_y)
	_check(far_render.ok and far_render.value.get_data() == PackedByteArray([239, 205, 171, 255]),
		"re-based far viewport renders correct exact raster pixel")
	_check(not registry.render_detail_at("world", "ground", 0, Rect2i(0, 0, 1, 1),
		AtlasWorldSpace.MAX_PIXELS + 1, 0).ok, "unsafe render anchor rejected")
	_check(registry.render_detail_at("world", "ground", 32, Rect2i(0, 0, 4, 4),
		far_pixel_x, far_pixel_y).value.get_data().count(0) == 4 * 4 * 4,
		"blank D32 at distant view consumes no D0 artwork")
	_check(not registry.begin_world_gesture("world", "ground", 0, layer0,
		AtlasWorldSpace.MAX_TICKS + 1, 0).ok, "out-of-bounds gesture rejected before mutation")
	_check(registry.set_visibility("world", "ground", 0, false).ok, "hide authored floor/detail")
	_check(not registry.begin_world_gesture("world", "ground", 0, layer0, 0, 0).ok,
		"cannot start edit on hidden detail")
	_check(registry.set_visibility("world", "ground", 0, true).ok, "restore editable detail")
	var turn: Transform2D = Transform2D(PI / 4.0, Vector2(3, 3), 0.0, Vector2(2, -5))
	var mapped: DrawingResult = AtlasWorldSpace.placed_asset_relative(Vector2(10, -3), turn,
		far_x + 2048, far_y - 1024, far_x, far_y)
	_check(mapped.ok and mapped.value.distance_to(turn * Vector2(10, -3) + Vector2(2, -1)) < 0.0001,
		"rotated scaled asset uses independent camera-relative placement")
	_check(not AtlasWorldSpace.placed_asset_relative(Vector2.ZERO, Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO),
		0, 0, 0, 0).ok, "singular instance transform rejected")

	# Round-trip registry metadata separately from portable Drawing payloads.
	var index: Dictionary = registry.export_index()
	var encoded: DrawingResult = DrawingFileIO.encode(doc0)
	_check(encoded.ok, "D0 exact authored data exported for combined project witness")
	var rebuilt: DrawingResult = AtlasDrawingRegistry.from_index(index, campaign)
	_check(rebuilt.ok, "stable map/floor/detail index reconstructed")
	if rebuilt.ok and encoded.ok:
		var restored: AtlasDrawingRegistry = rebuilt.value
		_check(restored.document_count() == 0, "restored registry lazy before document load")
		var decoded: DrawingResult = DrawingFileIO.decode(encoded.value)
		_check(decoded.ok, "reopen independent Drawing payload")
		if decoded.ok:
			_check(restored.attach_loaded_document("world", "ground", 0, decoded.value).ok,
				"rebind D0 document by saved opaque ID")
			_check(restored.document_at("world", "ground", 0).value.read_pixel(layer0,
				AtlasWorldSpace.world_to_pixel(far_x, 1, 1).value,
				AtlasWorldSpace.world_to_pixel(far_y, 1, 1).value).value == 0xffabcdef,
				"saved world/density mapping returns same distant pixel and stable layer ID")
		_check(restored.projection("world")[0]["details"][1]["blank"] == true,
			"reopened D1 still logically empty")
		var damaged: Dictionary = index.duplicate(true)
		for saved_map: Dictionary in damaged["maps"]:
			if saved_map["id"] == "world":
				for saved_floor: Dictionary in saved_map["floors"]:
					if saved_floor["id"] == "ground":
						saved_floor["details"][1]["document_id"] = d0
		_check(not AtlasDrawingRegistry.from_index(damaged, campaign).ok,
			"cross-detail duplicate document ID rejected")
		var incompatible: DrawingDocument = DrawingDocument.new("unrelated-id", 256)
		_check(not restored.attach_loaded_document("world", "ground", 0, incompatible).ok,
			"wrong reopened document rejected without substitution")

	var world: AtlasMapDocument = campaign.get_map("world")
	world.floors[0].display_name = "Renamed Ground"
	_check(registry.attach_campaign(campaign).ok and registry.projection("world")[0]["name"] == "Renamed Ground",
		"floor rename changes label, never Drawing identity")
	_check(registry.projection("world")[0]["details"][0]["document_id"] == d0,
		"floor rename retains opaque document ID")
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	upper.display_name = "Upper"
	world.floors.append(upper)
	_check(registry.attach_campaign(campaign).ok, "new floor group registered without painting")
	var upper_id: String = registry.projection("world")[1]["details"][0]["document_id"]
	_check(registry.projection("world").size() == 2 and upper_id != d0,
		"one floor group and one distinct D0 document per floor")
	_check(registry.document_count() == 2, "new upper floor has only logical ID")
	world.floors.reverse()
	_check(registry.attach_campaign(campaign).ok and registry.projection("world")[0]["id"] == "upper",
		"floor reorder changes projection order, not document identity")
	_check(registry.projection("world")[0]["details"][0]["document_id"] == upper_id and
		registry.projection("world")[1]["details"][0]["document_id"] == d0,
		"stable IDs survive floor reordering")
	_check(registry.document_at("world", "upper", 0).value == null,
		"collapsed floor resolves a logical document without materialization")
	world.floors.erase(upper)
	_check(registry.attach_campaign(campaign).ok and registry.projection("world").size() == 1,
		"deleting a floor removes its visible group without losing D0 identity in memory")
	world.floors.append(upper)
	_check(registry.attach_campaign(campaign).ok and
		registry.projection("world")[1]["details"][0]["document_id"] == upper_id,
		"undoing floor deletion reuses the same internal document identity")
	# Object instances reference an explicit D-level and never become background layers.
	var cache_path: String = OS.get_cache_dir().path_join("t061-objects-" + DrawingDocument.new_id())
	DirAccess.make_dir_recursive_absolute(cache_path)
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(cache_path.path_join("Campaign.scn"))
	var object_doc: DrawingDocument = DrawingDocument.new("fixture-asset", 32)
	var object_layer: String = String(object_doc.create_layer(DrawingLayerNode.RASTER, "Source art").value)
	var asset_id: String = String(library.create_asset(object_doc, "Stone").value)
	_check(not asset_id.is_empty(), "Object Asset created independently of background docs")
	var placed0: DrawingResult = library.place(asset_id, "world", "ground", "D0")
	var placed1: DrawingResult = library.place(asset_id, "world", "ground", "D1")
	_check(placed0.ok and placed1.ok, "object placements identify their D-level")
	if placed0.ok and placed1.ok:
		_check(registry.visible_placements(library, "world", "ground", 1) == [placed1.value],
			"D1 sees only explicitly scoped placements; no D0 fallback")
		_check(registry.visible_placements(library, "world", "ground", 32).is_empty(),
			"blank D32 has no implicit D0 Object Asset")
		_check(library.set_instance_visibility(placed1.value,
			library.instance_info(placed1.value)["revision"], false).ok,
			"hide D1 object independently")
		_check(registry.visible_placements(library, "world", "ground", 1).is_empty(),
			"hidden D1 instance excluded")
		_check(registry.visible_placements(library, "world", "ground", 0) == [placed0.value],
			"D0 placement remains separately visible")
	_check(registry.set_visibility("world", "ground", -1, false).ok,
		"hide floor without losing assets")
	_check(registry.visible_placements(library, "world", "ground", 0).is_empty(),
		"hidden floor masks its instances")
	_check(registry.set_visibility("world", "ground", -1, true).ok, "reopen floor")
	_check(registry.projection("world")[0]["details"][2]["blank"] == true,
		"no eager D32 artwork after rename")
	# Grid and entrance overlays are Atlas objects and remain usable at blank D32.
	_check(world.grid != null and campaign.outgoing_links("world", "ground").size() > 0,
		"grid/navigation overlays remain independent of blank detail document")

	# On-disk combined witness: legacy campaign, logical index, Drawing raster
	# and Objects/ records can be reopened together. T-066 will own the atomic
	# multi-file project generation (this is NOT its production save format).
	var campaign_path: String = cache_path.path_join("Campaign.scn")
	_check(AtlasCampaignStore.save_campaign(campaign, campaign_path) == OK,
		"native campaign save alongside Drawing and Object folders")
	var metadata_file: String = cache_path.path_join("DrawingIndex-fixture.json")
	var file: FileAccess = FileAccess.open(metadata_file, FileAccess.WRITE)
	_check(file != null, "write logical Drawing registry index")
	if file != null:
		file.store_string(JSON.stringify(registry.export_index()))
		file.close()
	var drawing_path: String = cache_path.path_join("D0-fixture.drawing")
	_check(DrawingFileIO.save(doc0, drawing_path).ok,
		"save authored D0 exact pixels next to campaign")
	var reloaded_campaign: AtlasCampaign = AtlasCampaignStore.load_campaign(campaign_path)
	_check(reloaded_campaign != null, "native campaign reopens from combined fixture")
	if reloaded_campaign != null:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_file))
		_check(parsed is Dictionary, "registry index JSON reopens")
		if parsed is Dictionary:
			var restored_index: DrawingResult = AtlasDrawingRegistry.from_index(parsed, reloaded_campaign)
			_check(restored_index.ok, "index accepts validated JSON integer numbers")
			if restored_index.ok:
				var restored_registry: AtlasDrawingRegistry = restored_index.value
				var restored_doc: DrawingResult = DrawingFileIO.open(drawing_path)
				_check(restored_doc.ok and restored_doc.value.id == d0,
					"Drawing payload reopens with same saved ID")
				if restored_doc.ok:
					_check(restored_registry.attach_loaded_document("world", "ground", 0,
						restored_doc.value).ok, "rejoin saved DrawingDocument to exact map/floor/D0")
					_check(restored_registry.document_at("world", "ground", 0).value.read_pixel(layer0,
						far_pixel_x, far_pixel_y).value == 0xffabcdef,
						"separately saved project files preserve distant pixels and layer IDs")
					_check(restored_registry.projection("world")[0]["id"] == "ground" and
							restored_registry.projection("world")[1]["id"] == "upper",
						"combined reload preserves floor order and hierarchy")
					_check(restored_registry.projection("world")[0]["details"][2]["blank"],
						"combined reload retains blank D32")
	print("T061_WORLD_MAPPING_PASSED checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
