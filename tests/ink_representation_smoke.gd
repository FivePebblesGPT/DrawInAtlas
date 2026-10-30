extends SceneTree
## T-028: evidence for existing vector-object and raster-pixel responsibilities.
## This is a contract audit, not a conversion or a performance benchmark.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("INK REPRESENTATION FAILED: " + reason)


func _pixel(layer: AtlasRasterLayer, point: Vector2i) -> Color:
	var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
	var chunk: AtlasRasterChunk = layer.chunks.get("%d,%d" % [coord.x, coord.y])
	if chunk == null:
		return Color.TRANSPARENT
	return chunk.image.get_pixelv(point - coord * AtlasRasterChunk.SIZE)


func _vector_contract() -> void:
	var line: AtlasStroke = AtlasStroke.new(PackedVector2Array([
		Vector2(-24.125, 0.5), Vector2(0.0, 0.5), Vector2(24.125, 0.5)]),
		Color(0.2, 0.5, 0.9, 0.35), 3.25)
	var label: AtlasStroke = AtlasTextLayout.make(Vector2(48.25, 12.5), "Editable label", "Sans", 18.0, Color.WHITE)
	var wall: AtlasStroke = AtlasStroke.new(PackedVector2Array([
		Vector2(12, 12), Vector2(18, 20)]), Color.WHITE, 2.0)
	wall.editable_path = true
	var ink: AtlasInkLayer = AtlasInkLayer.new()
	ink.strokes = [line, label, wall]
	_check(line.is_valid() and label.is_valid() and wall.is_valid(),
		"ink layer contains valid centerline, editable text and wall path objects")
	var object_selection: AtlasSelection = AtlasSelectionGeometry.select_indices(ink, [1])
	_check(object_selection.stroke_indices == [1] and not object_selection.raster_selected,
		"ink selection targets one editable object, not a rectangle of pixels")
	var before: Array[AtlasStroke] = AtlasStroke.clone_all(ink.strokes)
	var changed: Array[AtlasStroke] = AtlasStroke.clone_all(before)
	changed[0].points[0] = Vector2(-27.5, -3.0)
	_check(AtlasStroke.same_artwork(ink.strokes, before) and not AtlasStroke.same_artwork(before, changed),
		"whole-layer history snapshots isolate mutable stroke geometry")
	var cut: Array[AtlasStroke] = AtlasStrokeEraser.erase([line],
		PackedVector2Array([Vector2(0, -8), Vector2(0, 8)]), 7.0)
	_check(cut.size() == 2 and cut[0].color == line.color and cut[1].width == line.width,
		"vector erase splits geometry without touching original opacity/width")
	_check(ink.strokes.size() == 3 and ink.strokes[0].points[0] == Vector2(-24.125, 0.5),
		"geometry operations do not mutate source objects")
	var cloned: AtlasLayer = AtlasLayerCodec.clone(ink)
	_check(cloned is AtlasInkLayer and (cloned as AtlasInkLayer).strokes.size() == 3,
		"layer codec can clone object-backed ink")
	if cloned is AtlasInkLayer:
		(cloned as AtlasInkLayer).strokes[1].text = "Different"
		_check(label.text == "Editable label", "cloned editable text is independently mutable")
	var restored: AtlasLayer = AtlasLayerCodec.from_dict(ink.to_dict())
	_check(restored is AtlasInkLayer and AtlasStroke.same_artwork((restored as AtlasInkLayer).strokes, ink.strokes),
		"existing in-memory validation/dictionary seam preserves object metadata")


func _raster_contract() -> void:
	var source: Image = Image.create_empty(257, 2, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.1, 0.5, 0.2, 0.5))
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(source)
	_check(raster != null and raster.chunks.size() == 2 and raster.chunks.has("1,0"),
		"raster imports rectangular RGBA8 pixel chunks, including partial edges")
	if raster == null:
		return
	_check(raster.chunks["1,0"].width == 1 and raster.chunks["1,0"].height == 2,
		"partial final chunk stores only its real pixels")
	var initial: Color = _pixel(raster, Vector2i(256, 0))
	var paint: AtlasFillResult = AtlasRasterBrush.paint(raster,
		PackedVector2Array([Vector2(255.5, 0.5), Vector2(256.5, 0.5)]),
		Color(1, 0, 0, 0.5), 1.0, false)
	_check(paint.ok and paint.layer != null, "raster brush computes pixels in a detached replacement layer")
	if paint.layer == null:
		return
	_check(_pixel(raster, Vector2i(256, 0)) == initial,
		"source raster pixels remain unchanged for history")
	_check(_pixel(paint.layer, Vector2i(256, 0)).a > initial.a,
		"raster blending changes RGBA pixels, unlike vector object append")
	var erased: AtlasFillResult = AtlasRasterBrush.paint(paint.layer,
		PackedVector2Array([Vector2(256.5, 0.5)]), Color.WHITE, 1.0, true)
	_check(erased.ok and erased.layer != null, "raster erase produces a detached layer")
	if erased.layer != null:
		_check(_pixel(erased.layer, Vector2i(256, 0)).a == 0.0,
			"raster eraser clears alpha rather than splitting a vector centerline")
	var raster_selection: AtlasSelection = AtlasSelectionGeometry.select_indices(raster)
	_check(raster_selection.raster_selected and raster_selection.stroke_indices.is_empty(),
		"raster selection is whole-layer, not individual pixel objects")
	var raster_copy: AtlasLayer = AtlasLayerCodec.clone(raster)
	_check(raster_copy is AtlasRasterLayer and (raster_copy as AtlasRasterLayer).chunks.size() == 2,
		"raster cloning retains two chunk records")
	if raster_copy is AtlasRasterLayer:
		(raster_copy as AtlasRasterLayer).chunks["1,0"].image.set_pixel(0, 0, Color.RED)
		_check(_pixel(raster, Vector2i(256, 0)) == initial,
			"cloned chunk images have independent decoded pixel memory")


func _run() -> void:
	_vector_contract()
	_raster_contract()
	print("ATLAS_INK_REPRESENTATION_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
