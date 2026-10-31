class_name AtlasNativeScene
extends RefCounted

## Snapshot, validate and reconstruct a single-file native campaign scene.
## The existing to_dict/from_dict validators are an in-memory validation and
## cloning seam only; the native file never stores JSON or a dictionary schema.

static func pack_campaign(source: AtlasCampaign) -> PackedScene:
	var snapshot: AtlasCampaign = _snapshot(source)
	if snapshot == null:
		return null
	var root: AtlasCampaignSaveRoot = AtlasCampaignSaveRoot.new()
	root.name = "Campaign"
	root.campaign = snapshot
	root.semantic_digest = _digest(snapshot)
	var ids: Array[String] = []
	for id: String in snapshot.maps:
		ids.append(id)
	ids.sort()
	for id: String in ids:
		var child: AtlasMapSaveNode = AtlasMapSaveNode.new()
		child.name = "Map" # Names and child order are not document identity.
		child.document = snapshot.get_map(id)
		root.add_child(child)
		child.owner = root
	var packed: PackedScene = PackedScene.new()
	var error: Error = packed.pack(root)
	root.free()
	return packed if error == OK else null


static func unpack_campaign(scene: PackedScene) -> AtlasCampaign:
	if scene == null:
		return null
	var instance: Node = scene.instantiate()
	if not instance is AtlasCampaignSaveRoot:
		if instance != null:
			instance.free()
		return null
	var root: AtlasCampaignSaveRoot = instance as AtlasCampaignSaveRoot
	var result: AtlasCampaign = null
	if root.native_version == AtlasCampaignSaveRoot.NATIVE_VERSION \
			and root.campaign != null:
		var candidate: AtlasCampaign = root.campaign
		candidate.maps.clear()
		var valid_nodes: bool = not root.get_children().is_empty()
		for child: Node in root.get_children():
			if not child is AtlasMapSaveNode:
				valid_nodes = false
				break
			var map: AtlasMapDocument = (child as AtlasMapSaveNode).document
			if map == null or map.id.is_empty() or candidate.maps.has(map.id):
				valid_nodes = false
				break
			candidate.maps[map.id] = map
		if valid_nodes and _validate_and_hydrate(candidate) \
				and root.semantic_digest == _digest(candidate):
			result = candidate
	root.free()
	return result


static func _snapshot(source: AtlasCampaign) -> AtlasCampaign:
	if not _valid_live_layer_types(source):
		return null
	var result: AtlasCampaign = AtlasCampaign.from_dict(source.to_dict())
	if result == null:
		return null
	for id: String in source.maps:
		var original_map: AtlasMapDocument = source.get_map(id)
		var copied_map: AtlasMapDocument = result.get_map(id)
		if copied_map == null:
			return null
		for floor: AtlasFloor in original_map.floors:
			var copied_floor: AtlasFloor = copied_map.floor_by_id(floor.id)
			if copied_floor == null:
				return null
			for layer: AtlasLayer in floor.layers:
				if not layer is AtlasRasterLayer:
					continue
				var copied_layer: AtlasRasterLayer = copied_floor.layer_by_id(layer.id) as AtlasRasterLayer
				if copied_layer == null:
					return null
				for key: String in (layer as AtlasRasterLayer).chunks:
					var original: AtlasRasterChunk = (layer as AtlasRasterLayer).chunks[key]
					var chunk: AtlasRasterChunk = copied_layer.chunks.get(key)
					if chunk == null or original.image == null or not original.is_valid(true):
						return null
					chunk.image = original.image.duplicate()
					chunk.encoded_webp = AtlasWebPStore.encode_lossless(chunk.image)
					if chunk.encoded_webp.is_empty() or not _verify_chunk(chunk):
						return null
	return result if _validate_and_hydrate(result) else null


static func _validate_and_hydrate(campaign: AtlasCampaign) -> bool:
	# Existing constructors implement strict geometry/ID/transform validation.
	# No untrusted candidate becomes visible before complete validation.
	if not _valid_live_layer_types(campaign):
		return false
	if AtlasCampaign.from_dict(campaign.to_dict()) == null:
		return false
	for map: AtlasMapDocument in campaign.maps.values():
		for floor: AtlasFloor in map.floors:
			for layer: AtlasLayer in floor.layers:
				if not layer is AtlasRasterLayer:
					continue
				for chunk: AtlasRasterChunk in (layer as AtlasRasterLayer).chunks.values():
					if not _verify_chunk(chunk):
						return false
	return true


## A native Resource's script is its live type authority. Validate its stored
## compatibility marker before to_dict() converts it to a canonical dictionary.
static func _valid_live_layer_types(campaign: AtlasCampaign) -> bool:
	if campaign == null:
		return false
	for value: Variant in campaign.maps.values():
		if not value is AtlasMapDocument:
			return false
		var document: AtlasMapDocument = value as AtlasMapDocument
		for floor: AtlasFloor in document.floors:
			if floor == null or not AtlasLayerCodec.valid_collection(floor.layers):
				return false
	return true


static func _verify_chunk(chunk: AtlasRasterChunk) -> bool:
	if chunk == null or not chunk.is_valid() or chunk.encoded_webp.is_empty():
		return false
	var decoded: Image = AtlasWebPStore.decode_lossless(chunk.encoded_webp, chunk.width, chunk.height)
	if decoded == null or AtlasRasterChunk.image_hash(decoded) != chunk.stored_asset_id:
		return false
	if chunk.image != null and chunk.image.get_data() != decoded.get_data():
		return false
	chunk.image = decoded
	return true


static func _digest(campaign: AtlasCampaign) -> String:
	# to_dict orders map IDs independently of registry/scene-child order.
	# Each verified raster hash commits to the exact width/height/RGBA8 bytes.
	var canonical: Dictionary = campaign.to_dict()
	var normalized: Variant = JSON.parse_string(JSON.stringify(canonical, "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()
