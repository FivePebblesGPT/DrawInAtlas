extends SceneTree
## T-031: class-based layer typing, legacy native resources and wire discriminators.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LAYER TYPE FAILED: " + label)


func _typed_resources() -> void:
	var terrain: AtlasTerrainLayer = AtlasTerrainLayer.new("cells", "Terrain")
	terrain.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 24.0)
	terrain.terrain["-3,2"] = 11
	var ink: AtlasInkLayer = AtlasInkLayer.new("ink", "Ink")
	var raster: AtlasRasterLayer = AtlasRasterLayer.new("raster", "Raster")
	for layer: AtlasLayer in [terrain, ink, raster]:
		_check(layer.kind == layer.layer_kind(), "runtime class determines " + layer.kind)
		_check(layer.has_valid_type_marker(), "valid canonical type marker " + layer.kind)
		_check(AtlasLayerCodec.from_dict(layer.to_dict()) != null, "valid dictionary " + layer.kind)
		var clone: AtlasLayer = AtlasLayerCodec.clone(layer)
		_check(clone != null and clone.kind == layer.kind and clone.get_script() == layer.get_script(),
			"clone preserves concrete class " + layer.kind)
	_check(terrain.kind == "TILES" and terrain.to_dict().kind == "TILES",
		"historical TILES discriminator remains in dictionary payload")
	_check(terrain.grid.kind == AtlasGrid.Kind.HEX_FLAT and terrain.terrain["-3,2"] == 11,
		"terrain palette cells and authoritative cell grid remain separate")
	var old_alias: AtlasTileLayer = AtlasTileLayer.new("legacy", "Legacy")
	_check(old_alias is AtlasTerrainLayer and old_alias.kind == "TILES",
		"old AtlasTileLayer source name remains constructible")

	var malformed: Dictionary = terrain.to_dict()
	malformed.kind = "INK"
	_check(AtlasLayerCodec.from_dict(malformed) == null,
		"dictionary discriminator cannot reinterpret terrain payload as ink")
	malformed.kind = "UNKNOWN"
	_check(AtlasLayerCodec.from_dict(malformed) == null, "unknown discriminator rejected")

	# A serialized or runtime change to a derived marker cannot change the layer class.
	terrain.kind = "RASTER"
	_check(terrain.kind == "TILES" and not terrain.has_valid_type_marker(),
		"mismatched marker does not alter the runtime type")
	_check(not AtlasLayerCodec.valid_collection([terrain]) and AtlasLayerCodec.clone(terrain) == null,
		"cloning and layer validation reject contradictory native markers")
	var campaign: AtlasCampaign = AtlasCampaign.new()
	var document: AtlasMapDocument = AtlasMapDocument.new("world", "World")
	campaign.add_map(document)
	campaign.root_map_id = "world"
	document.floors[0].layers = [terrain, ink, raster]
	_check(AtlasNativeScene.pack_campaign(campaign) == null,
		"native snapshot rejects malformed live marker before canonicalization")
	terrain.kind = "TILES"
	_check(terrain.has_valid_type_marker() and AtlasNativeScene.pack_campaign(campaign) != null,
		"canonical marker allows saving without a schema change")


func _old_native_scenes() -> void:
	# Both fixtures were generated with the pre-T-031 engine/project and still
	# contain the old terrain_layer.gd script path and exported kind properties.
	for extension: String in ["scn", "tscn"]:
		var path: String = "res://tests/fixtures/t031_prechange_layer_kind." + extension
		var scene: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
		_check(scene != null, "legacy " + extension + " can load its script resources")
		if scene == null:
			continue
		var restored: AtlasCampaign = AtlasNativeScene.unpack_campaign(scene)
		_check(restored != null, "legacy " + extension + " passes integrity validation")
		if restored == null:
			continue
		var document: AtlasMapDocument = restored.get_map("test")
		var floor: AtlasFloor = document.floors[0]
		var terrain: AtlasTerrainLayer = floor.terrain_layer()
		_check(terrain != null and terrain.kind == "TILES" and terrain.terrain.get("-1,2") == 7,
			"legacy " + extension + " terrain contents preserved")
		_check(terrain != null and terrain.grid != null and terrain.grid.kind == AtlasGrid.Kind.SQUARE
			and terrain.grid.cell_size == 12.0, "legacy " + extension + " cell basis preserved")
		_check(floor.ink_layer() != null and floor.layer_by_id("raster") is AtlasRasterLayer,
			"legacy " + extension + " ink/raster type metadata preserved")
		var repacked: PackedScene = AtlasNativeScene.pack_campaign(restored)
		_check(repacked != null and AtlasNativeScene.unpack_campaign(repacked) != null,
			"legacy " + extension + " re-packs as a verified native save")

	# Change only the old native discriminator; its class and content stay terrain.
	# Loading must reject it, not rewrite corrupted metadata as valid artwork.
	var fixture: String = FileAccess.get_file_as_string(
		"res://tests/fixtures/t031_prechange_layer_kind.tscn")
	var altered: String = fixture.replace('kind = "TILES"', 'kind = "RASTER"')
	_check(altered != fixture, "corrupt fixture changed the native type marker")
	var bad_path: String = "user://t031_wrong_kind.tscn"
	var file: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
	_check(file != null, "isolated native fixture can be written")
	if file != null:
		file.store_string(altered)
		file.close()
		var wrong: PackedScene = ResourceLoader.load(bad_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		_check(wrong != null and AtlasNativeScene.unpack_campaign(wrong) == null,
			"native saved type mismatch is rejected before integrity validation")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))


func _run() -> void:
	_typed_resources()
	_old_native_scenes()
	print("ATLAS_LAYER_TYPE_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
