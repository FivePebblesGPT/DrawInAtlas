class_name AtlasFloor
extends Resource

@export_storage var id: String = "ground"
@export_storage var display_name: String = "Ground"
## Canonical back-to-front ordered layer resources. A detail level is a layer
## property, not a separate board or a child document.
@export_storage var layers: Array[AtlasLayer] = [AtlasRasterLayer.paint_layer(), AtlasObjectsLayer.new()]

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


func to_dict() -> Dictionary:
	var saved: Array[Dictionary] = []
	for layer: AtlasLayer in layers:
		saved.append(layer.to_dict())
	return {"id": id, "name": display_name, "layers": saved}


static func from_dict(data: Dictionary) -> AtlasFloor:
	var floor: AtlasFloor = AtlasFloor.new()
	var floor_id: Variant = data.get("id", "ground")
	var floor_name: Variant = data.get("name", "Ground")
	if not AtlasData.text(floor_id) or not AtlasData.text(floor_name):
		return null
	floor.id = floor_id
	floor.display_name = floor_name
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
