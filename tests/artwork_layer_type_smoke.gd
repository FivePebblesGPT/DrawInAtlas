extends SceneTree
## T-050: only raster/ink are valid artwork types in native and dictionary saves.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("ARTWORK TYPE FAILED: " + label)

func _run() -> void:
    var campaign: AtlasCampaign = AtlasCampaign.new()
    campaign.root_map_id = "m"
    var map: AtlasMapDocument = AtlasMapDocument.new("m", "Map")
    campaign.add_map(map)
    var floor: AtlasFloor = map.floors[0]
    _check(floor.layers.size() == 2 and floor.layers[0] is AtlasRasterLayer
        and floor.layers[1] is AtlasInkLayer, "new floors have raster and semantic ink")
    for layer: AtlasLayer in floor.layers:
        _check(layer.kind == layer.layer_kind() and layer.has_valid_type_marker(),
            "runtime class owns type marker " + layer.kind)
        _check(AtlasLayerCodec.from_dict(layer.to_dict()) != null, "type metadata loads")
        var clone: AtlasLayer = AtlasLayerCodec.clone(layer)
        _check(clone != null and clone.get_script() == layer.get_script(), "clone retains concrete class")
    var old: Dictionary = {"id": "old", "name": "Old cells", "kind": "TILES", "terrain": {"0,0": 3}}
    _check(AtlasLayerCodec.from_dict(old) == null, "retired terrain discriminator rejected")
    var fake: Dictionary = floor.to_dict()
    fake.layers.append(old)
    _check(AtlasFloor.from_dict(fake) == null, "retired layer cannot enter floor")
    var wrong_ink: Dictionary = floor.ink_layer().to_dict()
    wrong_ink["terrain"] = {"0,0": 2}
    _check(AtlasLayerCodec.from_dict(wrong_ink) == null, "terrain payload cannot impersonate ink")
    var wrong_raster: Dictionary = (floor.layers[0] as AtlasRasterLayer).to_dict()
    wrong_raster["grid"] = AtlasGrid.new().to_dict()
    _check(AtlasLayerCodec.from_dict(wrong_raster) == null, "cell grid cannot impersonate pixels")
    var bad_marker: AtlasRasterLayer = floor.layers[0] as AtlasRasterLayer
    bad_marker.kind = "TILES"
    _check(not bad_marker.has_valid_type_marker() and AtlasNativeScene.pack_campaign(campaign) == null,
        "native save rejects mismatched live type marker")
    bad_marker.kind = "RASTER"
    var packed: PackedScene = AtlasNativeScene.pack_campaign(campaign)
    _check(packed != null and AtlasNativeScene.unpack_campaign(packed) != null,
        "current raster/ink can roundtrip native save")
    if packed != null:
        var instance: AtlasCampaignSaveRoot = packed.instantiate() as AtlasCampaignSaveRoot
        instance.native_version = 1
        var old_scene: PackedScene = PackedScene.new()
        _check(old_scene.pack(instance) == OK and AtlasNativeScene.unpack_campaign(old_scene) == null,
            "old prototype native version rejected")
        instance.free()
    print("ATLAS_LAYER_TYPE_%s (%d checks, %d failures)" % [
        "PASSED" if failures == 0 else "FAILED", checks, failures])
    quit(0 if failures == 0 else 1)
