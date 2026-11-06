extends SceneTree
## T-029: validate dictionary seams without copying pixels during preflight.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DICTIONARY CONVERSION FAILED: " + label)


func _sample_raster() -> AtlasRasterLayer:
	var pixels: Image = Image.create(257, 2, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.7, 0.25, 0.4, 0.5))
	pixels.set_pixel(256, 1, Color(0.25, 0.75, 0.5, 0.0))
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	layer.id = "raster-test"
	return layer


func _raster_validation() -> void:
	var raster: AtlasRasterLayer = _sample_raster()
	var first: AtlasRasterChunk = raster.chunks["0,0"]
	var second: AtlasRasterChunk = raster.chunks["1,0"]
	var original_first: PackedByteArray = first.image.get_data()
	var original_second: PackedByteArray = second.image.get_data()
	_check(AtlasLayerCodec.valid_collection([raster]), "valid raster resource accepted")
	_check(first.image.get_data() == original_first and second.image.get_data() == original_second,
		"preflight does not alter pixels, including invisible RGB")
	var clone: AtlasRasterLayer = AtlasLayerCodec.clone(raster) as AtlasRasterLayer
	_check(clone != null and clone.chunks["1,0"].image.get_data() == original_second,
		"deep clone preserves exact RGBA8 bytes across chunk boundary")
	if clone != null:
		clone.chunks["1,0"].image.set_pixel(0, 1, Color.RED)
		_check(second.image.get_data() == original_second,
			"clone and source do not share decoded Image memory")
	_check(not AtlasLayerCodec.valid_collection([raster, raster]), "duplicate layer IDs rejected")
	# A typed Resource may be mutated directly; validators must check it too.
	first.width = 999
	_check(not AtlasLayerCodec.valid_collection([raster]) and AtlasLayerCodec.clone(raster) == null,
		"invalid live chunk dimensions rejected before copy")
	first.width = AtlasRasterChunk.SIZE
	var displaced: AtlasRasterChunk = raster.chunks["1,0"]
	raster.chunks.erase("1,0")
	raster.chunks["8,8"] = displaced
	_check(not AtlasLayerCodec.valid_collection([raster]) and AtlasLayerCodec.clone(raster) == null,
		"stale live chunk keys rejected before copy")
	raster.chunks["8,8"] = null
	_check(not AtlasLayerCodec.valid_collection([raster]) and AtlasLayerCodec.clone(raster) == null,
		"missing live chunk Resource rejected without runtime errors")
	raster.chunks.erase("8,8")
	raster.chunks["1,0"] = displaced
	_check(AtlasLayerCodec.valid_collection([raster]), "validity recovers after restoring chunk coordinates")


func _metadata_contract() -> void:
	var ink: AtlasInkLayer = AtlasInkLayer.new("ink-test", "Editable ink")
	var stroke: AtlasStroke = AtlasTextLayout.make(Vector2(14.25, -2.5), "Hello", "Sans", 15.0,
		Color(0.2, 0.4, 0.6, 0.8))
	ink.strokes = [stroke]
	var copy: AtlasInkLayer = AtlasLayerCodec.clone(ink) as AtlasInkLayer
	_check(copy != null and AtlasLayerCodec.same_layers([ink], [copy]),
		"dictionary metadata validation retains editable text styling")
	if copy != null:
		copy.strokes[0].text = "Changed"
		_check(stroke.text == "Hello", "metadata clone does not alias editable ink")
	ink.detail_level = 33
	_check(not AtlasLayerCodec.valid_collection([ink]), "out-of-range authored detail rejected")
	ink.detail_level = 0
	_check(AtlasLayerCodec.valid_collection([ink]), "valid vector resource accepted")


func _native_contract() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var map: AtlasMapDocument = campaign.get_map(campaign.root_map_id)
	map.floors[0].layers.append(_sample_raster())
	var before: Dictionary = campaign.to_dict()
	var packed: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	_check(packed != null and campaign.to_dict() == before, "native pack validates without mutating source")
	if packed == null:
		return
	var restored: AtlasCampaign = AtlasNativeScene.unpack_campaign(packed)
	_check(restored != null and restored.to_dict() == before,
		"native Resource graph round-trips semantic metadata through integrity digest")
	if restored != null:
		var source: AtlasRasterLayer = map.floors[0].layer_by_id("raster-test") as AtlasRasterLayer
		var target: AtlasRasterLayer = restored.get_map(campaign.root_map_id).floors[0].layer_by_id("raster-test") as AtlasRasterLayer
		_check(target != null and target.chunks["1,0"].image.get_data() == source.chunks["1,0"].image.get_data(),
			"native snapshot preserves exact partial-chunk RGBA8, including hidden RGB")
		if target != null:
			target.chunks["1,0"].image.set_pixel(0, 1, Color.WHITE)
			_check(source.chunks["1,0"].image.get_data() != target.chunks["1,0"].image.get_data(),
				"native unpack has independent decoded pixels")


func _run() -> void:
	_raster_validation()
	_metadata_contract()
	_native_contract()
	print("ATLAS_DICTIONARY_CONVERSION_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
