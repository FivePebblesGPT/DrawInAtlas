extends SceneTree

var _checks: int = 0
var _failures: int = 0
const SIZE: Vector2i = Vector2i(192, 128)


func _initialize() -> void:
	_signatures()
	_isolation()
	_copies_and_lru()
	_invalid_inputs()
	print("ATLAS_PREVIEW_CACHE_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _image(size: Vector2i = SIZE, color: Color = Color.RED) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _signatures() -> void:
	var cache: AtlasPreviewCache = AtlasPreviewCache.new()
	var map: AtlasMapDocument = AtlasMapDocument.new("map", "Map")
	var floor: AtlasFloor = map.floors[0]
	var stroke: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2.ZERO, Vector2(10, 20)]))
	floor.strokes.append(stroke)
	floor.paint(Vector2i.ZERO, 1)
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(Vector2i(2, 3)))
	floor.layers.append(raster)
	var baseline: Dictionary = map.to_dict().duplicate(true)
	var original_pixels: PackedByteArray = raster.chunks["0,0"].image.get_data()
	var initial: String = cache.signature(map, floor.id)
	cache.put_image(map, floor.id, SIZE, _image())
	_check(cache.get_image(map, floor.id) != null, "unchanged content hits")
	_check(map.to_dict() == baseline and raster.chunks["0,0"].image.get_data() == original_pixels,
		"signature, put and get never mutate canonical content or fallback grid")
	_check(floor.terrain_layer().grid == null and map.terrain_grid == null,
		"signature does not materialize fallback grids")
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	map.floors.append(upper)
	upper.paint(Vector2i.ZERO, 5)
	_check(cache.signature(map, floor.id) == initial, "unselected floor edits do not invalidate")
	_check(cache.signature(map, upper.id) != initial, "floors have distinct signatures")
	var changes: Array[Callable] = [
		func() -> void: stroke.points[0] = Vector2(5, 6),
		func() -> void: floor.paint(Vector2i(2, 3), 4),
		func() -> void: map.grid.cell_size += 1,
		func() -> void: map.terrain_grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 31),
		func() -> void: floor.terrain_layer().grid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 22),
		func() -> void: floor.terrain_layer().grid.origin += Vector2.ONE,
		func() -> void: raster.chunks["0,0"].image.set_pixel(0, 0, Color.BLUE),
		func() -> void: raster.chunks["0,0"].coord += Vector2i.ONE,
		func() -> void: raster.transform.origin += Vector2(4, 9),
		func() -> void: raster.pixels_per_unit = 2,
		func() -> void: raster.opacity = 0.5,
		func() -> void: raster.visible = false,
		func() -> void: floor.ink_layer().opacity = 0,
		func() -> void: floor.display_name = "Renamed"]
	for index: int in range(changes.size()):
		cache.put_image(map, floor.id, SIZE, _image())
		var before: String = cache.signature(map, floor.id)
		changes[index].call()
		_check(cache.signature(map, floor.id) != before and cache.get_image(map, floor.id) == null,
			"content/grid/image/placement/opacity/visibility/name mutation %d misses" % index)
	var hidden: String = cache.signature(map, floor.id)
	stroke.width += 1
	raster.chunks["0,0"].image.fill(Color.GREEN)
	_check(cache.signature(map, floor.id) == hidden, "hidden artwork edits do not invalidate")
	upper.terrain_layer().grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 7)
	var fallback: AtlasTerrainLayer = AtlasTerrainLayer.new("extra", "Extra")
	fallback.terrain["0,0"] = 1
	upper.layers.append(fallback)
	var before: String = cache.signature(map, upper.id)
	upper.terrain_layer().grid.rotation = 0.7
	_check(cache.signature(map, upper.id) != before, "selected floor effective fallback grid is hashed")


func _isolation() -> void:
	var cache: AtlasPreviewCache = AtlasPreviewCache.new()
	var first: AtlasMapDocument = AtlasMapDocument.new("世界\na", "First")
	var second: AtlasMapDocument = AtlasMapDocument.new("世界", "Second")
	first.floors[0].id = "階"
	second.floors[0].id = "a\n階"
	cache.put_image(first, "階", SIZE, _image())
	cache.put_image(second, "a\n階", SIZE, _image(SIZE, Color.BLUE))
	_check(cache.entry_count() == 2, "Unicode/newline tuple keys do not collide")
	_check(cache.get_image(first, "階").get_pixel(0, 0) == Color.RED, "first collision candidate retained")
	_check(cache.get_image(second, "a\n階").get_pixel(0, 0) == Color.BLUE, "second collision candidate retained")
	second.floors[0].id = "階"
	cache.put_image(second, "階", SIZE, _image(SIZE, Color.BLUE))
	_check(cache.get_image(first, "階").get_pixel(0, 0) == Color.RED, "same floor IDs across maps independent")
	_check(cache.get_image(second, "階").get_pixel(0, 0) == Color.BLUE, "second map same floor ID independent")
	second.floors[0].paint(Vector2i.ZERO, 3)
	_check(cache.get_image(second, "階") == null and cache.get_image(first, "階") != null,
		"second map edit invalidates only that map")
	cache.put_image(second, "階", SIZE, _image(SIZE, Color.BLUE))
	cache.put_image(first, "階", Vector2i(4, 5), _image(Vector2i(4, 5)))
	cache.put_image(first, "階", SIZE, _image(SIZE, Color.GREEN), "projector")
	_check(cache.get_image(first, "階", Vector2i(4, 5)).get_size() == Vector2i(4, 5), "size partitions entries")
	_check(cache.get_image(first, "階").get_pixel(0, 0) == Color.RED, "editor audience retained")
	_check(cache.get_image(first, "階", SIZE, "projector").get_pixel(0, 0) == Color.GREEN, "audience partitions entries")
	_check(cache.get_image(first, "階", SIZE, "other") == null, "unpopulated audience misses")
	cache.invalidate(second.id)
	_check(cache.entry_count() == 3 and cache.get_image(first, "階") != null, "map invalidation uses exact ID")


func _copies_and_lru() -> void:
	var cache: AtlasPreviewCache = AtlasPreviewCache.new(2)
	var map: AtlasMapDocument = AtlasMapDocument.new("m", "Map")
	var image: Image = _image()
	cache.put_image(map, "ground", SIZE, image)
	image.fill(Color.BLUE)
	var fetched: Image = cache.get_image(map, "ground")
	_check(fetched.get_pixel(0, 0) == Color.RED, "put copies caller image")
	fetched.fill(Color.GREEN)
	_check(cache.get_image(map, "ground").get_pixel(0, 0) == Color.RED, "get copies cached image")
	cache.put_image(map, "ground", SIZE, image, "b")
	cache.get_image(map, "ground")
	cache.put_image(map, "ground", SIZE, image, "c")
	_check(cache.entry_count() == 2 and cache.get_image(map, "ground", SIZE, "b") == null, "LRU evicts least recently read")
	_check(cache.get_image(map, "ground") != null, "LRU preserves recently read")
	cache.put_image(map, "ground", SIZE, image)
	cache.put_image(map, "ground", SIZE, image, "d")
	_check(cache.entry_count() == 2 and cache.get_image(map, "ground", SIZE, "c") == null, "replacement refreshes LRU without count growth")
	cache.invalidate()
	_check(cache.entry_count() == 0, "invalidate clears all")
	for capacity: int in [0, -1]:
		var disabled: AtlasPreviewCache = AtlasPreviewCache.new(capacity)
		disabled.put_image(map, "ground", SIZE, image)
		_check(disabled.entry_count() == 0, "nonpositive capacity disables writes")


func _invalid_inputs() -> void:
	var cache: AtlasPreviewCache = AtlasPreviewCache.new()
	var map: AtlasMapDocument = AtlasMapDocument.new("m", "Map")
	for size: Vector2i in [Vector2i.ZERO, Vector2i(-1, 128), Vector2i(192, -1)]:
		cache.put_image(map, "ground", size, _image())
		_check(cache.get_image(map, "ground", size) == null, "invalid dimensions miss")
	cache.put_image(null, "ground", SIZE, _image())
	cache.put_image(map, "missing", SIZE, _image())
	cache.put_image(map, "ground", SIZE, null)
	cache.put_image(map, "ground", SIZE, Image.new())
	cache.put_image(map, "ground", SIZE, _image(Vector2i(2, 3)))
	_check(cache.entry_count() == 0, "invalid documents/floors/images/sizes never write")
	_check(cache.get_image(null, "ground") == null and cache.get_image(map, "missing") == null, "invalid document/floor reads miss")
	_check(cache.signature(null, "ground").is_empty() and cache.signature(map, "missing").is_empty(), "invalid signatures are empty")
