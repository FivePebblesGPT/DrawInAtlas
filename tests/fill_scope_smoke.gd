extends SceneTree
## Run: godot --headless --path . --script res://tests/fill_scope_smoke.gd

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("_run_suite")


func _run_suite() -> void:
    _test_scope_geometry()
    _test_tile_fill()
    _test_hex_fill()
    _test_raster_fill_boundaries()
    _test_raster_transform_scope()
    _test_raster_brush()
    _test_transformed_brush()
    _test_raster_rejections()
    _test_ink_scope()
    if failures == 0:
        print("ATLAS_FILL_SCOPE_PASSED (%d checks)" % checks)
    else:
        push_error("ATLAS_FILL_SCOPE_FAILED: %d of %d checks failed" % [failures, checks])
    quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("FILL/SCOPE FAILED: " + description)


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
    return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
        rect.end, Vector2(rect.position.x, rect.end.y)])


func _rect_scope(rect: Rect2) -> AtlasEditScope:
    return AtlasEditScope.new(_rect_polygon(rect), true)


func _image(width: int, height: int, color: Color) -> Image:
    var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
    image.fill(color)
    return image


func _pixel(layer: AtlasRasterLayer, point: Vector2i) -> Color:
    var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
    var chunk: AtlasRasterChunk = layer.chunks.get("%d,%d" % [coord.x, coord.y])
    if chunk == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var local: Vector2i = point - coord * AtlasRasterChunk.SIZE
    if local.x >= chunk.width or local.y >= chunk.height:
        return Color(0.0, 0.0, 0.0, 0.0)
    return chunk.image.get_pixelv(local)


func _set_pixel(layer: AtlasRasterLayer, point: Vector2i, color: Color) -> void:
    var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
    var key: String = "%d,%d" % [coord.x, coord.y]
    if not layer.chunks.has(key):
        layer.chunks[key] = AtlasRasterChunk.new(coord,
            _image(AtlasRasterChunk.SIZE, AtlasRasterChunk.SIZE, Color.BLACK))
    layer.chunks[key].image.set_pixelv(point - coord * AtlasRasterChunk.SIZE, color)


func _document_pixel(layer: AtlasRasterLayer, pixel: Vector2) -> Vector2:
    return layer.transform * (pixel / layer.pixels_per_unit)


func _pixel_scope(layer: AtlasRasterLayer, rect: Rect2) -> AtlasEditScope:
    var points: PackedVector2Array = _rect_polygon(rect)
    for index: int in range(points.size()):
        points[index] = _document_pixel(layer, points[index])
    return AtlasEditScope.new(points, true)


func _rejected(result: AtlasFillResult, description: String) -> void:
    _check(not result.ok and not result.message.is_empty()
        and result.layer == null and result.terrain.is_empty(), description)


func _test_scope_geometry() -> void:
    var boundary: PackedVector2Array = _rect_polygon(Rect2(0.0, 0.0, 10.0, 10.0))
    var scope: AtlasEditScope = AtlasEditScope.new(boundary, true)
    boundary[0] = Vector2(500.0, 500.0)
    _check(scope.polygon[0] == Vector2.ZERO and scope.enabled, "scope owns its boundary")
    _check(scope.contains_rect(Rect2(0.0, 0.0, 10.0, 10.0)), "scope includes exact boundary")
    _check(not scope.contains_rect(Rect2(9.5, 2.0, 1.0, 1.0)), "scope rejects crossing rectangles")
    var reversed: PackedVector2Array = scope.polygon.duplicate()
    reversed.reverse()
    _check(AtlasEditScope.new(reversed, true).contains_rect(Rect2(1.0, 1.0, 8.0, 8.0)),
        "scope accepts either winding")
    var diamond: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
        Vector2(0.0, 5.0), Vector2(5.0, 0.0), Vector2(10.0, 5.0), Vector2(5.0, 10.0)
    ]), true)
    _check(not diamond.contains_rect(Rect2(1.0, 1.0, 2.0, 2.0)),
        "scope tests polygon rather than its bounding box")
    _check(not AtlasEditScope.new(PackedVector2Array(), true).contains_rect(Rect2()),
        "enabled empty scope rejects all")
    _check(AtlasEditScope.new().allows_polygon(PackedVector2Array()), "disabled scope passes all")
    var concave: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
        Vector2.ZERO, Vector2(10.0, 0.0), Vector2(3.0, 3.0), Vector2(0.0, 10.0)
    ]), true)
    _check(not concave.contains_rect(Rect2(0.5, 0.5, 1.0, 1.0)), "nonconvex boundary fails closed")


func _test_tile_fill() -> void:
    var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 1.0)
    var terrain: Dictionary = {"0,0": 2, "1,0": 2, "1,1": 2, "2,2": 2, "0,1": 3}
    var before: Dictionary = terrain.duplicate(true)
    var result: AtlasFillResult = AtlasFill.tiles(grid, terrain, Vector2i.ZERO, 7)
    _check(result.ok and result.terrain.get("0,0") == 7 and result.terrain.get("1,1") == 7,
        "square flood follows four-connected equal palettes")
    _check(result.terrain.get("2,2") == 2 and result.terrain.get("0,1") == 3,
        "square flood excludes diagonal and different palettes")
    _check(terrain == before, "tile fill never mutates source")
    result.terrain["0,0"] = 99
    _check(terrain == before, "tile snapshot is independent")
    result = AtlasFill.tiles(grid, terrain, Vector2i.ZERO, 0)
    _check(result.ok and not result.terrain.has("0,0") and result.terrain.size() == 2,
        "tile palette zero removes affected keys")
    _rejected(AtlasFill.tiles(grid, terrain, Vector2i.ZERO, 2), "same palette is a no-op")
    _rejected(AtlasFill.tiles(grid, terrain, Vector2i.ZERO, 7, null, 2),
        "tile overflow rejects the whole transaction")
    _check(terrain == before, "overflow leaves terrain untouched")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, 1), "unscoped background is unbounded")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, 1, AtlasEditScope.new()),
        "disabled scope cannot bound background")
    var scope: AtlasEditScope = _rect_scope(Rect2(0.0, 0.0, 3.0, 2.0))
    result = AtlasFill.tiles(grid, {}, Vector2i.ZERO, 4, scope, 6)
    _check(result.ok and result.terrain.size() == 6 and result.terrain.has("2,1"),
        "scoped background fills exactly the finite square region at the limit")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, 4, scope, 5),
        "scoped background overflow is atomic")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, 1, _rect_scope(Rect2(0.2, 0.0, 0.8, 1.0))),
        "cell center inside scope does not allow a crossing cell")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, 1,
        AtlasEditScope.new(PackedVector2Array(), true)), "empty selection rejects tile flood")
    _rejected(AtlasFill.tiles(AtlasGrid.new(AtlasGrid.Kind.GRIDLESS), {}, Vector2i.ZERO, 1),
        "gridless fill rejected")
    _rejected(AtlasFill.tiles(grid, {"bad": 1}, Vector2i.ZERO, 1), "malformed terrain rejected")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, -1, scope), "negative palette rejected")
    _rejected(AtlasFill.tiles(grid, {}, Vector2i.ZERO, 1, scope, 0), "invalid tile limit rejected")


func _test_hex_fill() -> void:
    for kind: AtlasGrid.Kind in [AtlasGrid.Kind.HEX_POINTY, AtlasGrid.Kind.HEX_FLAT]:
        var grid: AtlasGrid = AtlasGrid.new(kind, 5.0)
        grid.origin = Vector2(12.0, -9.0)
        grid.rotation = 0.31
        var terrain: Dictionary = {"0,0": 2, "1,-1": 2, "-1,1": 2, "3,3": 2}
        var result: AtlasFillResult = AtlasFill.tiles(grid, terrain, Vector2i.ZERO, 6)
        _check(result.ok and result.terrain.get("1,-1") == 6
            and result.terrain.get("-1,1") == 6 and result.terrain.get("3,3") == 2,
            "hex flood uses six axial neighbors for kind %d" % kind)
        var scope: AtlasEditScope = AtlasEditScope.new(grid.cell_polygon(Vector2i.ZERO), true)
        result = AtlasFill.tiles(grid, {}, Vector2i.ZERO, 3, scope)
        _check(result.ok and result.terrain.size() == 1 and result.terrain.get("0,0") == 3,
            "rotated hex scope bounds background to one complete cell for kind %d" % kind)


func _test_raster_fill_boundaries() -> void:
    var source: AtlasRasterLayer = AtlasRasterLayer.new()
    var connected: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]
    for point: Vector2i in connected:
        _set_pixel(source, point, Color.RED)
    _set_pixel(source, Vector2i(1, 1), Color.RED)
    var result: AtlasFillResult = AtlasFill.raster(source, Vector2(-0.5, -0.5), Color.BLUE, null, 4)
    _check(result.ok and result.layer != null, "raster flood crosses negative chunk boundaries at limit")
    if result.layer != null:
        for point: Vector2i in connected:
            _check(_pixel(result.layer, point) == Color.BLUE and _pixel(source, point) == Color.RED,
                "negative-boundary fill is complete and source-independent at %s" % point)
        _check(_pixel(result.layer, Vector2i(1, 1)) == Color.RED, "raster flood is four-connected")
        result.layer.chunks["-1,-1"].image.set_pixel(0, 0, Color.GREEN)
        _check(source.chunks["-1,-1"].image.get_pixel(0, 0) == Color.BLACK,
            "filled chunks are detached images")
    _rejected(AtlasFill.raster(source, Vector2(-0.5, -0.5), Color.BLUE, null, 3),
        "raster overflow rejects whole transaction")
    _check(_pixel(source, Vector2i(-1, -1)) == Color.RED, "raster overflow cannot leak writes")
    _rejected(AtlasFill.raster(source, Vector2(-0.5, -0.5), Color(1.0, 0.0001, 0.0, 1.0)),
        "RGBA8 quantization detects color no-op")
    var partial: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(259, 2, Color.WHITE))
    result = AtlasFill.raster(partial, Vector2(258.5, 1.5), Color.BLUE, null, 518)
    _check(result.ok and result.layer != null, "partial edge chunks participate across boundaries")
    if result.layer != null:
        _check(result.layer.chunks["1,0"].width == 3 and result.layer.chunks["1,0"].height == 2,
            "flood preserves partial image extent")
        _check(_pixel(result.layer, Vector2i.ZERO) == Color.BLUE
            and _pixel(result.layer, Vector2i(258, 1)) == Color.BLUE,
            "flood reaches both partial and full chunks")
    _rejected(AtlasFill.raster(partial, Vector2(259.1, 0.5), Color.RED),
        "partial chunk padding is not an existing pixel")
    var transparent: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(2, 2, Color(0.0, 0.0, 0.0, 0.0)))
    result = AtlasFill.raster(transparent, Vector2(0.5, 0.5), Color.RED, null, 4)
    _check(result.ok, "finite existing transparent raster pixels can be filled")
    var exact: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(3, 1, Color(0.0, 0.0, 0.0, 1.0)))
    exact.chunks["0,0"].image.set_pixel(1, 0, Color(0.0, 0.0, 1.0 / 255.0, 1.0))
    result = AtlasFill.raster(exact, Vector2(0.5, 0.5), Color.RED)
    _check(result.ok and _pixel(result.layer, Vector2i(1, 0)).b > 0.0
        and _pixel(result.layer, Vector2i(2, 0)) == Color.BLACK,
        "one-byte RGBA8 difference stops flood")


func _test_raster_transform_scope() -> void:
    var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(3, 2, Color.WHITE), 2.0)
    layer.transform = Transform2D(Vector2(0.0, 2.0), Vector2(-3.0, 0.5), Vector2(10.0, -7.0))
    var start: Vector2 = _document_pixel(layer, Vector2(1.5, 0.5))
    var scope: AtlasEditScope = _pixel_scope(layer, Rect2(1.0, 0.0, 1.0, 1.0))
    var result: AtlasFillResult = AtlasFill.raster(layer, start, Color.BLUE, scope)
    _check(result.ok and result.layer != null, "inverse transform and ppu locate scoped raster pixel")
    if result.layer != null:
        _check(_pixel(result.layer, Vector2i(1, 0)) == Color.BLUE
            and _pixel(result.layer, Vector2i(0, 0)) == Color.WHITE
            and _pixel(result.layer, Vector2i(1, 1)) == Color.WHITE,
            "raster scope tests full transformed quad and stops traversal")
        _check(result.layer.transform == layer.transform and result.layer.pixels_per_unit == 2.0,
            "raster snapshot retains placement and resolution")
    _rejected(AtlasFill.raster(layer, start, Color.BLUE,
        _pixel_scope(layer, Rect2(1.1, 0.1, 0.8, 0.8))),
        "pixel center inside selection is insufficient for raster fill")
    _check(_pixel(layer, Vector2i(1, 0)) == Color.WHITE, "scoped transformed source stays untouched")
    _rejected(AtlasFill.raster(layer, start, Color.RED, AtlasEditScope.new(PackedVector2Array(), true)),
        "empty active raster scope rejects fill")


func _test_raster_brush() -> void:
    var empty: AtlasRasterLayer = AtlasRasterLayer.new()
    var path: PackedVector2Array = PackedVector2Array([Vector2(-1.5, -0.5), Vector2(1.5, -0.5)])
    var path_before: PackedVector2Array = path.duplicate()
    var painted: AtlasFillResult = AtlasRasterBrush.paint(empty, path, Color.RED, 1.0, false)
    _check(painted.ok and painted.layer != null, "pen paints empty raster with a round sweep")
    _check(empty.chunks.is_empty() and path == path_before, "pen never mutates source or gesture")
    if painted.layer == null:
        return
    _check(painted.layer.chunks.has("-1,-1") and painted.layer.chunks.has("0,-1")
        and painted.layer.chunks.size() == 2, "pen lazily allocates negative and positive chunks")
    for x: int in range(-2, 2):
        _check(_pixel(painted.layer, Vector2i(x, -1)) == Color.RED, "swept pen covers intermediate centers")
    _check(_pixel(painted.layer, Vector2i(-3, -1)).a == 0.0
        and _pixel(painted.layer, Vector2i(0, 0)).a == 0.0, "round brush excludes outside centers")
    for chunk: AtlasRasterChunk in painted.layer.chunks.values():
        _check(chunk.is_valid(true) and chunk.width == 256 and chunk.height == 256,
            "new pen chunks are full canonical 256 RGBA8")
    var undo: AtlasRasterLayer = AtlasLayerCodec.clone(painted.layer) as AtlasRasterLayer
    var erased: AtlasFillResult = AtlasRasterBrush.paint(painted.layer,
        PackedVector2Array([Vector2(-0.5, -0.5)]), Color.GREEN, 1.0, true)
    _check(erased.ok and erased.layer != null, "dot eraser returns a new snapshot")
    if erased.layer != null:
        _check(_pixel(erased.layer, Vector2i(-1, -1)) == Color(0.0, 0.0, 0.0, 0.0),
            "eraser writes transparent RGBA zero")
        _check(_pixel(painted.layer, Vector2i(-1, -1)) == Color.RED
            and _pixel(undo, Vector2i(-1, -1)) == Color.RED, "eraser preserves original and undo snapshots")
        erased.layer.chunks["0,-1"].image.set_pixel(0, 255, Color.BLUE)
        _check(_pixel(painted.layer, Vector2i(0, -1)) == Color.RED
            and _pixel(undo, Vector2i(0, -1)) == Color.RED,
            "even untouched snapshot chunks are independent")
    var scope: AtlasEditScope = _rect_scope(Rect2(-1.0, -1.0, 1.0, 1.0))
    var scoped: AtlasFillResult = AtlasRasterBrush.paint(empty, path, Color.BLUE, 2.0, false, scope)
    _check(scoped.ok and scoped.layer != null and scoped.layer.chunks.size() == 1
        and _pixel(scoped.layer, Vector2i(-1, -1)) == Color.BLUE
        and _pixel(scoped.layer, Vector2i(-2, -1)).a == 0.0,
        "pen scope filters entire pixel quads")
    _rejected(AtlasRasterBrush.paint(empty, path, Color.RED, 1.0, false,
        _rect_scope(Rect2(-0.9, -0.9, 0.8, 0.8))), "scope containing center but not quad rejects brush")
    _rejected(AtlasRasterBrush.paint(empty, path, Color.RED, 1.0, false, null, 2),
        "large brush candidate area rejects atomically")
    _check(empty.chunks.is_empty(), "rejected brush allocates no source chunks")
    _rejected(AtlasRasterBrush.paint(empty, path, Color.RED, 1.0, true),
        "eraser on absent raster pixels is a no-op")
    _rejected(AtlasRasterBrush.paint(painted.layer, path, Color.RED, 1.0, false),
        "painting identical RGBA8 is a no-op")
    _rejected(AtlasRasterBrush.paint(empty, path, Color(0.0, 0.0, 0.0, 0.0), 1.0, false),
        "transparent pen on missing pixels allocates nothing")
    var partial: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(1, 1, Color.GREEN))
    var grown: AtlasFillResult = AtlasRasterBrush.paint(partial,
        PackedVector2Array([Vector2(2.5, 0.5)]), Color.BLUE, 1.0, false)
    _check(grown.ok and grown.layer != null and grown.layer.chunks["0,0"].width == 256
        and _pixel(grown.layer, Vector2i.ZERO) == Color.GREEN
        and _pixel(grown.layer, Vector2i(2, 0)) == Color.BLUE,
        "pen expands partial chunks and preserves existing pixels")
    _check(partial.chunks["0,0"].width == 1, "partial source extent stays intact")
    _rejected(AtlasRasterBrush.paint(partial, PackedVector2Array([Vector2(2.5, 0.5)]),
        Color.RED, 1.0, true), "eraser never allocates partial-chunk padding")


func _test_transformed_brush() -> void:
    var layer: AtlasRasterLayer = AtlasRasterLayer.new()
    layer.pixels_per_unit = 2.0
    layer.transform = Transform2D(Vector2(0.0, 4.0), Vector2(-1.0, 0.0), Vector2(8.0, -3.0))
    var center: Vector2 = _document_pixel(layer, Vector2(0.5, 0.5))
    var result: AtlasFillResult = AtlasRasterBrush.paint(layer, PackedVector2Array([center]),
        Color.BLUE, 1.2, false)
    _check(result.ok and result.layer != null, "transformed pen uses inverse candidate bounds")
    if result.layer != null:
        _check(_pixel(result.layer, Vector2i.ZERO) == Color.BLUE
            and _pixel(result.layer, Vector2i(0, 1)) == Color.BLUE
            and _pixel(result.layer, Vector2i(0, -1)) == Color.BLUE,
            "document-space circle spans compressed raster axis")
        _check(_pixel(result.layer, Vector2i(1, 0)).a == 0.0
            and _pixel(result.layer, Vector2i(-1, 0)).a == 0.0,
            "document-space circle excludes stretched raster axis")
    var scope: AtlasEditScope = _pixel_scope(layer, Rect2(0.0, 0.0, 1.0, 1.0))
    result = AtlasRasterBrush.paint(layer, PackedVector2Array([center]), Color.RED, 5.0, false, scope)
    _check(result.ok and result.layer != null and _pixel(result.layer, Vector2i.ZERO) == Color.RED
        and _pixel(result.layer, Vector2i(0, 1)).a == 0.0,
        "transformed brush scope admits only full quad")
    var reflected: AtlasRasterLayer = AtlasRasterLayer.new()
    reflected.transform = Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
    result = AtlasRasterBrush.paint(reflected, PackedVector2Array([Vector2(0.5, 0.5)]), Color.RED, 1.0, false)
    _check(result.ok and _pixel(result.layer, Vector2i(-1, 0)) == Color.RED,
        "invertible reflected transform paints correct negative pixel")


func _test_raster_rejections() -> void:
    var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(2, 2, Color.WHITE))
    var path: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.5)])
    layer.locked = true
    _rejected(AtlasFill.raster(layer, path[0], Color.RED), "locked raster fill rejected")
    _rejected(AtlasRasterBrush.paint(layer, path, Color.RED, 1.0, false), "locked pen rejected")
    layer.locked = false
    layer.visible = false
    _rejected(AtlasFill.raster(layer, path[0], Color.RED), "hidden fill rejected")
    _rejected(AtlasRasterBrush.paint(layer, path, Color.RED, 1.0, true), "hidden eraser rejected")
    layer.visible = true
    for placement: Transform2D in [Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO),
            Transform2D(Vector2(INF, 0.0), Vector2.DOWN, Vector2.ZERO)]:
        layer.transform = placement
        _rejected(AtlasFill.raster(layer, path[0], Color.RED), "invalid raster transform rejected by fill")
        _rejected(AtlasRasterBrush.paint(layer, path, Color.RED, 1.0, false),
            "invalid raster transform rejected by pen")
    layer.transform = Transform2D.IDENTITY
    for scale: float in [0.0, -1.0, INF, NAN]:
        layer.pixels_per_unit = scale
        _rejected(AtlasFill.raster(layer, path[0], Color.RED), "invalid raster ppu rejected")
    layer.pixels_per_unit = 1.0
    for width: float in [0.0, -1.0, INF, NAN]:
        _rejected(AtlasRasterBrush.paint(layer, path, Color.RED, width, false), "invalid brush width rejected")
    _rejected(AtlasRasterBrush.paint(layer, PackedVector2Array(), Color.RED, 1.0, false), "empty brush rejected")
    _rejected(AtlasRasterBrush.paint(layer, PackedVector2Array([Vector2(NAN, 0.0)]),
        Color.RED, 1.0, false), "nonfinite brush path rejected")
    _rejected(AtlasFill.raster(layer, Vector2(INF, 0.0), Color.RED), "nonfinite fill point rejected")
    _rejected(AtlasFill.raster(layer, path[0], Color(NAN, 0.0, 0.0)), "nonfinite fill color rejected")
    _rejected(AtlasRasterBrush.paint(layer, path, Color(0.0, INF, 0.0), 1.0, false),
        "nonfinite brush color rejected")
    _rejected(AtlasFill.raster(layer, path[0], Color.RED, null, 0), "invalid raster limit rejected")
    _rejected(AtlasRasterBrush.paint(layer, path, Color.RED, 1.0, false, null, 0), "invalid brush limit rejected")
    layer.chunks["0,0"].image.convert(Image.FORMAT_RGB8)
    _rejected(AtlasFill.raster(layer, path[0], Color.RED), "noncanonical chunk image rejected")
    _rejected(AtlasRasterBrush.paint(layer, path, Color.RED, 1.0, false), "pen rejects noncanonical image")
    layer.chunks["0,0"].image = _image(1, 1, Color.WHITE)
    _rejected(AtlasFill.raster(layer, path[0], Color.RED), "inconsistent chunk extent rejected")
    layer.chunks["0,0"].image = null
    _rejected(AtlasFill.raster(layer, path[0], Color.RED), "unhydrated chunk rejected")
    layer.chunks["0,0"] = AtlasRasterChunk.new(Vector2i(1, 0), _image(2, 2, Color.WHITE))
    _rejected(AtlasFill.raster(layer, path[0], Color.RED), "chunk coordinate/key mismatch rejected")


func _test_ink_scope() -> void:
    var scope: AtlasEditScope = _rect_scope(Rect2(0.0, 0.0, 10.0, 10.0))
    var crossing: AtlasStroke = AtlasStroke.new(PackedVector2Array([
        Vector2(-5.0, 5.0), Vector2(15.0, 5.0)
    ]), Color.RED, 2.0)
    var clipped: Array[AtlasStroke] = scope.clip_strokes([crossing])
    _check(clipped.size() == 1, "scope clips crossing centerline to one inset part")
    if clipped.size() == 1:
        var min_x: float = minf(clipped[0].points[0].x, clipped[0].points[-1].x)
        var max_x: float = maxf(clipped[0].points[0].x, clipped[0].points[-1].x)
        _check(is_equal_approx(min_x, 1.0) and is_equal_approx(max_x, 9.0),
            "ink clipping insets by halfwidth to contain round caps")
        _check(clipped[0].color == Color.RED and clipped[0].width == 2.0,
            "clipped stroke keeps style")
    _check(crossing.points[0] == Vector2(-5.0, 5.0), "ink clipping cannot mutate source")
    var dots: Array[AtlasStroke] = [
        AtlasStroke.new(PackedVector2Array([Vector2(1.0, 5.0)]), Color.BLUE, 2.0),
        AtlasStroke.new(PackedVector2Array([Vector2(0.5, 5.0)]), Color.BLUE, 2.0),
        AtlasStroke.new(PackedVector2Array([Vector2(5.0, 5.0)]), Color.BLUE, 12.0)
    ]
    clipped = scope.clip_strokes(dots)
    _check(clipped.size() == 1 and clipped[0].points[0] == Vector2(1.0, 5.0),
        "dot clipping accounts for full ink radius and vanished inset")
    var same_points: AtlasStroke = AtlasStroke.new(PackedVector2Array([
        Vector2(5.0, 5.0), Vector2(5.0, 5.0)
    ]), Color.RED, 2.0)
    clipped = scope.clip_strokes([same_points])
    _check(clipped.size() == 1, "repeated-point dot remains supported")
    var inside: AtlasStroke = AtlasStroke.new(PackedVector2Array([
        Vector2(2.0, 5.0), Vector2(8.0, 5.0)
    ]), Color.BLUE, 2.0)
    var source: Array[AtlasStroke] = [crossing, inside]
    var erased: Array[AtlasStroke] = scope.erase(source,
        PackedVector2Array([Vector2(5.0, -5.0), Vector2(5.0, 15.0)]), 1.0)
    _check(erased.size() == 3 and erased[0].points == crossing.points,
        "scope erases eligible ink but protects whole crossing strokes")
    _check(source.size() == 2 and inside.points.size() == 2, "scoped erase is source-independent")
    var padded_crossing: AtlasStroke = AtlasStroke.new(PackedVector2Array([
        Vector2(0.5, 4.0), Vector2(9.5, 4.0)
    ]), Color.RED, 2.0)
    erased = scope.erase([padded_crossing], PackedVector2Array([Vector2(5.0, 4.0)]), 20.0)
    _check(erased.size() == 1 and erased[0].points == padded_crossing.points,
        "erase eligibility tests padded bounds rather than centerline bounds")
    var disabled: AtlasEditScope = AtlasEditScope.new()
    var copied: Array[AtlasStroke] = disabled.clip_strokes(source)
    _check(copied.size() == 2 and copied[0] != crossing and copied[0].points == crossing.points,
        "disabled clipping returns independent full strokes")
    copied[0].points[0] = Vector2(999.0, 999.0)
    _check(crossing.points[0] == Vector2(-5.0, 5.0), "disabled pass-through owns copied points")
    erased = disabled.erase([inside], PackedVector2Array([Vector2(5.0, 5.0)]), 20.0)
    _check(erased.is_empty(), "disabled scope delegates unrestricted erase")
    var empty: AtlasEditScope = AtlasEditScope.new(PackedVector2Array(), true)
    _check(empty.clip_strokes(source).is_empty(), "empty active scope clips all ink")
    erased = empty.erase(source, PackedVector2Array([Vector2(5.0, 5.0)]), 100.0)
    _check(AtlasStroke.same_artwork(erased, source) and erased[0] != crossing,
        "empty active scope protects all existing ink with copies")
