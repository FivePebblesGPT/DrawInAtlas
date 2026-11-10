extends SceneTree
## T-095: independently verify sparse detached-preview compositing and measure
## cold/warm source-tile raster work, without substituting a fill benchmark for
## the separate pointer-driven 60px latency witness.

const ANCHOR_X: int = 2147483651
const ANCHOR_Y: int = -2147483671
const VIEW: Rect2i = Rect2i(0, 0, 128, 128)

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_SPARSE_PREVIEW_FAILED: " + description)


func source_layer(document: DrawingDocument, layer: String,
		pixels: Dictionary[Vector2i, int]) -> void:
	var edit: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value as DrawingEditSession
	check(edit != null, "source edit created")
	if edit == null:
		return
	for point: Vector2i in pixels:
		check(edit._stage(point.x, point.y, pixels[point]).ok,
			"source pixel staged at %s" % point)
	check(edit.commit().ok, "source edit committed")


## Independent layer-order, transparent-erasure and alpha compositor oracle.
## No renderer chunk lookup, display planning, or preview-tile algorithm used.
func expected_bytes(area: Rect2i, bottom: Dictionary[Vector2i, int],
		top: Dictionary[Vector2i, int], patch: Dictionary[Vector2i, int]) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(area.size.x * area.size.y * 4)
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var point: Vector2i = Vector2i(x, y)
			var lower: int = bottom.get(point, 0)
			var upper: int = patch[point] if patch.has(point) else top.get(point, 0)
			var pixel: int = 0
			if (lower & 0xff000000) != 0:
				pixel = DrawingEditSession._blend(lower, pixel)
			if (upper & 0xff000000) != 0:
				pixel = DrawingEditSession._blend(upper, pixel)
			result.encode_u32(((y - area.position.y) * area.size.x + x - area.position.x) * 4, pixel)
	return result


func percentile(values: Array[int], percentage: float) -> int:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * percentage) - 1, 0, sorted.size() - 1)]


func run() -> void:
	var document: DrawingDocument = DrawingDocument.new("sparse-preview", 256)
	var bottom_layer: String = String(document.create_layer(
		DrawingLayerNode.RASTER, "Bottom", "root").value)
	var top_layer: String = String(document.create_layer(
		DrawingLayerNode.RASTER, "Top", "root").value)
	var bottom: Dictionary[Vector2i, int] = {
		Vector2i(5, 5): 0x90563315,
		Vector2i(9, 7): 0xff337799,
		Vector2i(121, 121): 0x800030e0,
		Vector2i(45, 49): 0x000c0b0a
	}
	var top: Dictionary[Vector2i, int] = {
		Vector2i(5, 5): 0xa0ce1100,
		Vector2i(12, 6): 0xff1122cc,
		Vector2i(22, 22): 0x70abcdef,
		Vector2i(40, 10): 0x00aabbcc
	}
	source_layer(document, bottom_layer, bottom)
	source_layer(document, top_layer, top)
	check(document.list_children("root") == [bottom_layer, top_layer],
		"raster layer order is bottom then top")
	var base_render: DrawingResult = DrawingRenderer.render(document, VIEW, ANCHOR_X, ANCHOR_Y)
	check(base_render.ok and base_render.value.get_data() == expected_bytes(VIEW, bottom, top, {}),
		"committed sparse layers match independently composited RGBA8 bytes")
	var edit: DrawingEditSession = document.begin_edit(top_layer, document.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value as DrawingEditSession
	var selection: DrawingSelection = DrawingSelection.new(VIEW, true)
	check(selection.combine_rectangle(Rect2i(20, 20, 5, 5), "Subtract"),
		"selection hole installed")
	var attempted: Dictionary[Vector2i, int] = {
		Vector2i(5, 5): 0,
		Vector2i(12, 6): 0x40eeddcc,
		Vector2i(22, 22): 0xff345678,
		Vector2i(56, 46): 0x805599aa,
		Vector2i(121, 121): 0xff1188ee,
		Vector2i(40, 10): 0x00ffffff
	}
	var preview_patch: Dictionary[Vector2i, int] = {}
	for point: Vector2i in attempted:
		check(edit._stage(point.x, point.y, attempted[point], selection).ok,
			"preview pixel staged at %s" % point)
		if selection.allows(point):
			preview_patch[point] = attempted[point]
	check(edit.change_count() == preview_patch.size(),
		"selection hole cannot produce a pending pixel")
	var preview_render: DrawingResult = DrawingRenderer.render(document,
		VIEW, ANCHOR_X, ANCHOR_Y, 1048576, edit)
	var expected: PackedByteArray = expected_bytes(VIEW, bottom, top, preview_patch)
	check(preview_render.ok and preview_render.value.get_data() == expected,
		"sparse preview erasures/additions match independent per-pixel layer oracle")
	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(document)
	var planned_render: DrawingResult = DrawingRenderer.render(document,
		VIEW, ANCHOR_X, ANCHOR_Y, 1048576, edit, plan)
	check(planned_render.ok and planned_render.value.get_data() == expected,
		"frame-cached plan and direct preview agree at signed 64-bit anchor")
	check(document.revision == edit.expected_revision and edit._after.size() == preview_patch.size(),
		"preview remains detached from committed document")
	var samples: Array[int] = []
	for sample: int in range(25):
		var started_us: int = Time.get_ticks_usec()
		var rendered: DrawingResult = DrawingRenderer.render(document,
			VIEW, ANCHOR_X, ANCHOR_Y, 1048576, edit)
		samples.append(Time.get_ticks_usec() - started_us)
		if sample == 0 or sample == 24:
			check(rendered.ok and rendered.value.get_data() == expected,
				"measured renderer stays byte-exact")
	print("T095_SPARSE_PREVIEW_PERF median_us=%d p95_us=%d samples=%d" % [
		percentile(samples, 0.5), percentile(samples, 0.95), samples.size()])
	check(edit.commit().ok, "one atomic preview commit succeeds")
	check(DrawingRenderer.render(document, VIEW, ANCHOR_X, ANCHOR_Y).value.get_data() == expected,
		"committed source matches detached sparse preview")
	check(document.undo().ok and DrawingRenderer.render(document,
		VIEW, ANCHOR_X, ANCHOR_Y).value.get_data() == base_render.value.get_data(),
		"Undo restores both sparse source layers")
	check(document.redo().ok and DrawingRenderer.render(document,
		VIEW, ANCHOR_X, ANCHOR_Y).value.get_data() == expected,
		"Redo restores byte-exact sparse paint")

	# Exceed the sparse threshold to check the dense fallback with the same
	# source snapshot and independent expected bytes.
	var dense_edit: DrawingEditSession = document.begin_edit(top_layer, document.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value as DrawingEditSession
	var dense_patch: Dictionary[Vector2i, int] = {}
	for y: int in range(10, 20):
		for x: int in range(60, 70):
			var point: Vector2i = Vector2i(x, y)
			var pigment: int = 0x904466aa if (x + y) % 2 == 0 else 0x00aabbcc
			check(dense_edit._stage(x, y, pigment).ok, "dense preview source staged")
			dense_patch[point] = pigment
	var dense_expected: PackedByteArray = expected_bytes(VIEW, bottom, top, preview_patch.merged(dense_patch, true))
	var dense_render: DrawingResult = DrawingRenderer.render(document,
		VIEW, ANCHOR_X, ANCHOR_Y, 1048576, dense_edit)
	check(dense_render.ok and dense_render.value.get_data() == dense_expected,
		"dense fallback composes mixed transparent/opaque pigments exactly")
	dense_edit.cancel()
	check(DrawingRenderer.render(document, VIEW, ANCHOR_X, ANCHOR_Y).value.get_data() == expected,
		"cancelling dense fallback leaves prior committed pixels unchanged")
	print("T095_SPARSE_PREVIEW_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
