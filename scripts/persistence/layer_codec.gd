class_name AtlasLayerCodec
extends RefCounted


static func from_dict(data: Dictionary) -> AtlasLayer:
	if not AtlasData.text(data.get("id")) or not AtlasData.text(data.get("name")):
		return null
	var visible: Variant = data.get("visible", true)
	var locked: Variant = data.get("locked", false)
	var opacity: Variant = data.get("opacity", 1.0)
	if not visible is bool or not locked is bool or not AtlasData.number(opacity):
		return null
	if float(opacity) < 0.0 or float(opacity) > 1.0:
		return null
	var layer: AtlasLayer
	match data.get("kind"):
		"INK":
			var ink: AtlasInkLayer = AtlasInkLayer.new(data.id, data.name)
			var strokes: Variant = data.get("strokes", [])
			if not strokes is Array:
				return null
			for raw: Variant in strokes:
				if not raw is Dictionary:
					return null
				var stroke: AtlasStroke = AtlasStroke.from_dict(raw)
				if stroke == null:
					return null
				ink.strokes.append(stroke)
			layer = ink
		"TILES":
			var tiles: AtlasTileLayer = AtlasTileLayer.new(data.id, data.name)
			var cells: Variant = data.get("terrain", {})
			var grid: Variant = data.get("grid")
			if not cells is Dictionary or (grid != null and not grid is Dictionary):
				return null
			for key: Variant in cells:
				if not AtlasData.coordinate_key(key) or not AtlasData.integer(cells[key]) or int(cells[key]) < 0:
					return null
				tiles.terrain[key] = int(cells[key])
			if grid != null:
				tiles.grid = AtlasGrid.from_dict(grid)
				if tiles.grid == null:
					return null
			layer = tiles
		"RASTER":
			var raster: AtlasRasterLayer = AtlasRasterLayer.new(data.id, data.name)
			var scale: Variant = data.get("pixels_per_unit", 1.0)
			var chunks: Variant = data.get("chunks", [])
			if not AtlasData.number(scale) or float(scale) <= 0.0 or not chunks is Array:
				return null
			raster.pixels_per_unit = float(scale)
			var placement: Variant = data.get("transform", [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
			if not placement is Array or placement.size() != 6:
				return null
			for number: Variant in placement:
				if not AtlasData.number(number):
					return null
			raster.transform = Transform2D(Vector2(float(placement[0]), float(placement[1])),
				Vector2(float(placement[2]), float(placement[3])), Vector2(float(placement[4]), float(placement[5])))
			if not raster.transform.x.is_finite() or not raster.transform.y.is_finite() or not raster.transform.origin.is_finite():
				return null
			if not is_finite(raster.transform.determinant()) or absf(raster.transform.determinant()) < 0.00000001:
				return null
			for raw: Variant in chunks:
				if not raw is Dictionary:
					return null
				var chunk: AtlasRasterChunk = AtlasRasterChunk.from_dict(raw)
				if chunk == null:
					return null
				var key: String = "%d,%d" % [chunk.coord.x, chunk.coord.y]
				if raster.chunks.has(key):
					return null
				raster.chunks[key] = chunk
			layer = raster
		_:
			return null
	layer.visible = visible
	layer.locked = locked
	layer.opacity = float(opacity)
	return layer


static func clone(layer: AtlasLayer) -> AtlasLayer:
	if layer == null:
		return null
	var copy: AtlasLayer = from_dict(layer.to_dict())
	if copy is AtlasRasterLayer and layer is AtlasRasterLayer:
		for key: String in layer.chunks:
			if not layer.chunks[key].is_valid():
				return null
			if layer.chunks[key].image != null:
				copy.chunks[key].image = layer.chunks[key].image.duplicate()
	return copy


static func clone_all(layers: Array[AtlasLayer]) -> Array[AtlasLayer]:
	var result: Array[AtlasLayer] = []
	for layer: AtlasLayer in layers:
		var copy: AtlasLayer = clone(layer)
		if copy == null:
			return []
		result.append(copy)
	return result


static func valid_collection(layers: Array[AtlasLayer]) -> bool:
	var ids: Dictionary[String, bool] = {}
	for layer: AtlasLayer in layers:
		if layer == null or ids.has(layer.id) or clone(layer) == null:
			return false
		ids[layer.id] = true
	return true


static func same_layers(first: Array[AtlasLayer], second: Array[AtlasLayer]) -> bool:
	if first.size() != second.size():
		return false
	for index: int in range(first.size()):
		if first[index].to_dict() != second[index].to_dict():
			return false
	return true
