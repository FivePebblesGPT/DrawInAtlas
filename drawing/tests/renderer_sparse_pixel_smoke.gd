extends SceneTree
## T-086: independent RGBA8 oracle for sparse-run compositing, signed seams,
## clipping, hidden RGB, dense fallback and detached previews.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_SPARSE_PIXEL_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func seed_source(doc: DrawingDocument, layer: String, points: Array[Vector2i],
		colors: Array[int]) -> void:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "seed session begins")
	if not started.ok:
		return
	var edit: DrawingEditSession = started.value as DrawingEditSession
	for i: int in range(points.size()):
		var color: int = colors[i % colors.size()]
		var pixels: PackedByteArray = PackedByteArray([
			color & 255, (color >> 8) & 255, (color >> 16) & 255,
			(color >> 24) & 255])
		check(edit.apply_region(Rect2i(points[i], Vector2i.ONE), pixels).ok,
			"stage seed %d" % i)
	check(edit.commit().ok, "publish all seed pixels")


func reference(doc: DrawingDocument, view: Rect2i, layers: Array[String],
		preview: DrawingEditSession = null) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(view.size.x * view.size.y * 4)
	for y: int in range(view.size.y):
		for x: int in range(view.size.x):
			var point: Vector2i = view.position + Vector2i(x, y)
			var rgba: int = 0
			for layer: String in layers:
				var read: DrawingResult = doc.read_pixel(layer, point.x, point.y)
				if not read.ok:
					return PackedByteArray()
				var source: int = int(read.value)
				if preview != null and preview.layer_id == layer:
					var key: String = DrawingDocument.TILES.tile_key64(
						point.x, point.y, doc.tile_stride)
					var patch: Dictionary = preview.preview_tile(key)
					var pixel_index: int = posmod(point.y, doc.tile_stride) * doc.tile_stride \
						+ posmod(point.x, doc.tile_stride)
					if patch.has(pixel_index):
						source = int(patch[pixel_index])
				if ((source >> 24) & 255) != 0:
					rgba = DrawingEditSession._blend(source, rgba)
			var byte_index: int = (y * view.size.x + x) * 4
			bytes[byte_index] = rgba & 255
			bytes[byte_index + 1] = (rgba >> 8) & 255
			bytes[byte_index + 2] = (rgba >> 16) & 255
			bytes[byte_index + 3] = (rgba >> 24) & 255
	return bytes


func verify_stride(stride: int) -> void:
	var doc: DrawingDocument = DrawingDocument.new("sparse-run-%d" % stride, stride)
	var low: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Low").value)
	var high: String = String(doc.create_layer(DrawingLayerNode.RASTER, "High").value)
	var layers: Array[String] = [low, high]
	var points: Array[Vector2i] = [Vector2i(-39, -32), Vector2i(-1, -1),
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(17, 13), Vector2i(41, 35)]
	var colors: Array[int] = [0xff030201, 0x00040302, 0x80070605,
		0xfe090807, 0xffdcba98, 0x01102030]
	seed_source(doc, low, points, colors)
	seed_source(doc, high, [Vector2i(-1, -1), Vector2i(0, 0), Vector2i(2, 0),
		Vector2i(17, 13), Vector2i(41, 35)],
		[0x80442211, 0xffecbd4a, 0x000010ff, 0x7f134acb, 0xfe0a1938])
	var view: Rect2i = Rect2i(-40, -33, 84, 72)
	var expected: PackedByteArray = reference(doc, view, layers)
	var output: DrawingResult = DrawingRenderer.render(doc, view)
	check(output.ok and (output.value as Image).get_data() == expected,
		"stride=%d cold direct RGBA8 matches public pixel oracle" % stride)
	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	output = DrawingRenderer.render(doc, view, 0, 0, 1048576, null, plan)
	check(output.ok and (output.value as Image).get_data() == expected,
		"stride=%d prepared render matches exact bytes" % stride)
	# Non-aligned intersections exercise partial scanline runs on both sides.
	var clipped: Rect2i = Rect2i(-5, -2, 35, 24)
	var clipped_render: DrawingResult = DrawingRenderer.render(doc, clipped)
	check(clipped_render.ok and (clipped_render.value as Image).get_data() ==
		reference(doc, clipped, layers),
		"stride=%d non-aligned view clipping and source-run endpoints" % stride)
	var started: DrawingResult = doc.begin_edit(high, doc.revision)
	check(started.ok, "stride=%d start detached preview" % stride)
	if started.ok:
		var preview: DrawingEditSession = started.value as DrawingEditSession
		var preview_points: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, 0),
			Vector2i(3, -1), Vector2i(20, 15)]
		seed_preview(preview, preview_points)
		var draft: DrawingResult = DrawingRenderer.render(doc, view,
			0, 0, 1048576, preview, plan)
		check(draft.ok and (draft.value as Image).get_data() ==
			reference(doc, view, layers, preview),
			"stride=%d source/preview overlays match pixel oracle" % stride)
		preview.cancel()
		check(DrawingRenderer.render(doc, view).value.get_data() == expected,
			"stride=%d cancel leaves committed display exact" % stride)
	# An occupied tile with >12 source entries exercises dense fallback.
	var filler: Array[Vector2i] = []
	for i: int in range(15):
		filler.append(Vector2i(4 + i, 23))
	seed_source(doc, low, filler, [0xffaabbcc])
	var after_dense: DrawingResult = DrawingRenderer.render(doc, view)
	check(after_dense.ok and (after_dense.value as Image).get_data() ==
		reference(doc, view, layers),
		"stride=%d dense fallback preserves exact pixels" % stride)
	check(int(doc.read_pixel(low, 0, 0).value) == 0x80070605,
		"stride=%d source pixel retains straight unblended RGBA8" % stride)
	check(int(doc.read_pixel(low, -1, -1).value) == 0x00040302,
		"stride=%d hidden RGB preserved in canonical source" % stride)


func seed_preview(preview: DrawingEditSession, points: Array[Vector2i]) -> void:
	var colors: Array[PackedByteArray] = [PackedByteArray([2, 4, 6, 0]),
		PackedByteArray([80, 90, 100, 128]),
		PackedByteArray([140, 180, 215, 255]),
		PackedByteArray([99, 13, 21, 254])]
	for i: int in range(points.size()):
		check(preview.apply_region(Rect2i(points[i], Vector2i.ONE), colors[i]).ok,
			"preview sparse pixel stage %d" % i)


func run() -> void:
	for stride: int in [1, 16, 64, 128, 256, 513]:
		verify_stride(stride)
	print("T086_SPARSE_PIXEL: %d checks; %d failed" % [checks, failures])
	print("T086_SPARSE_PIXEL_PASSED" if failures == 0 else "T086_SPARSE_PIXEL_FAILED")
	quit(0 if failures == 0 else 1)
