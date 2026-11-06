class_name AtlasFloor
extends Resource

@export_storage var id: String = "ground"
@export_storage var display_name: String = "Ground"
## Canonical back-to-front ordered layer resources. A detail level is a layer
## property, not a separate board or a child document.
@export_storage var layers: Array[AtlasLayer] = [AtlasRasterLayer.paint_layer(), AtlasObjectsLayer.new()]
## Optional GM-authored fog, stored once per floor and applied at every LOD.
## Existing saves retain unrestricted projection behavior until enabled.
@export_storage var fog_enabled: bool = false
@export_storage var fog_regions: Array[AtlasFogRegion] = []

const MAX_FOG_REGIONS: int = 256

## Legacy accessor for default Objects records; raster tools never write here.
var strokes: Array[AtlasStroke]:
	get:
		var layer: AtlasObjectsLayer = objects_layer()
		return layer.strokes if layer != null else []
	set(value):
		var layer: AtlasObjectsLayer = objects_layer()
		if layer != null:
			layer.strokes = value


func layer_by_id(layer_id: String) -> AtlasLayer:
	for layer: AtlasLayer in layers:
		if layer.id == layer_id:
			return layer
	return null


## Deprecated prototype accessor; current authoring uses objects_layer().
func ink_layer() -> AtlasObjectsLayer:
	return objects_layer()


func objects_layer() -> AtlasObjectsLayer:
	for layer: AtlasLayer in layers:
		if layer is AtlasObjectsLayer:
			return layer
	return null


func raster_layer() -> AtlasRasterLayer:
	for layer: AtlasLayer in layers:
		if layer is AtlasRasterLayer:
			return layer
	return null


## Deny by default when fog is enabled; last matching region wins.
func fog_allows(point: Vector2) -> bool:
	if not point.is_finite():
		return false
	if not fog_enabled:
		return true
	for index: int in range(fog_regions.size() - 1, -1, -1):
		if fog_regions[index].bounds.has_point(point):
			return fog_regions[index].reveal
	return false


func valid_fog() -> bool:
	if fog_regions.size() > MAX_FOG_REGIONS:
		return false
	for region: AtlasFogRegion in fog_regions:
		if region == null or not region.is_valid():
			return false
	return true


static func clone_fog(regions: Array[AtlasFogRegion]) -> Array[AtlasFogRegion]:
	var result: Array[AtlasFogRegion] = []
	for region: AtlasFogRegion in regions:
		result.append(region.copy())
	return result


static func same_fog(first: Array[AtlasFogRegion], second: Array[AtlasFogRegion]) -> bool:
	if first.size() != second.size():
		return false
	for index: int in range(first.size()):
		if first[index] == null or second[index] == null \
				or first[index].to_dict() != second[index].to_dict():
			return false
	return true


func to_dict() -> Dictionary:
	var saved: Array[Dictionary] = []
	for layer: AtlasLayer in layers:
		saved.append(layer.to_dict())
	var saved_fog: Array[Dictionary] = []
	for region: AtlasFogRegion in fog_regions:
		# Malformed live resources must be rejected at the dictionary/native
		# boundary, not crash the serializer before validation runs.
		saved_fog.append(region.to_dict() if region != null else {})
	var data: Dictionary = {"id": id, "name": display_name, "layers": saved}
	# Native saves sign the exact dictionary representation. Absence of these
	# optional fields MUST retain the pre-T-042 digest for existing .scn files.
	if fog_enabled or not fog_regions.is_empty():
		data["fog_enabled"] = fog_enabled
		data["fog_regions"] = saved_fog
	return data


static func from_dict(data: Dictionary) -> AtlasFloor:
	var floor: AtlasFloor = AtlasFloor.new()
	var floor_id: Variant = data.get("id", "ground")
	var floor_name: Variant = data.get("name", "Ground")
	if not AtlasData.text(floor_id) or not AtlasData.text(floor_name):
		return null
	floor.id = floor_id
	floor.display_name = floor_name
	var enabled: Variant = data.get("fog_enabled", false)
	var regions: Variant = data.get("fog_regions", [])
	if not enabled is bool or not regions is Array or regions.size() > MAX_FOG_REGIONS:
		return null
	floor.fog_enabled = enabled
	for raw: Variant in regions:
		if not raw is Dictionary:
			return null
		var region: AtlasFogRegion = AtlasFogRegion.from_dict(raw)
		if region == null:
			return null
		floor.fog_regions.append(region)
	if not data.has("layers") or not data["layers"] is Array \
			or data.has("terrain") or data.has("strokes"):
		return null
	floor.layers.clear()
	var ids: Dictionary[String, bool] = {}
	for raw: Variant in data["layers"]:
		if not raw is Dictionary:
			return null
		var layer: AtlasLayer = AtlasLayerCodec.from_dict(raw)
		if layer == null or ids.has(layer.id):
			return null
		ids[layer.id] = true
		floor.layers.append(layer)
	return floor
