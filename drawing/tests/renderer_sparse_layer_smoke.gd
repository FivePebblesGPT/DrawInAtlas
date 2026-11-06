extends SceneTree
## T-086: exact pixel parity and bounded metadata-only culling on a sparse
## many-layer display. The regular (unplanned) renderer is the control path.

class CountingDocument:
	extends DrawingDocument
	var resolve_calls: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolve_calls += 1
		return super._resolve_chunk(layer_id, key)

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_SPARSE_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func seed_pixel(doc: DrawingDocument, layer: String, point: Vector2i, rgba: PackedByteArray) -> void:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "start seeded layer")
	if started.ok:
		var edit: DrawingEditSession = started.value as DrawingEditSession
		check(edit.apply_region(Rect2i(point, Vector2i.ONE), rgba).ok,
			"stage canonical source bytes")
		check(edit.commit().ok, "publish source bytes")


func broken_source(_ref: String) -> PackedByteArray:
	return PackedByteArray([1, 2, 3])


func run() -> void:
	var doc: CountingDocument = CountingDocument.new("sparse-display", 8)
	var layers: Array[String] = []
	for number: int in range(24):
		var result: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER,
			"Sparse %d" % number)
		check(result.ok, "create layer %d" % number)
		layers.append(String(result.value))
	seed_pixel(doc, layers[0], Vector2i(-1, -1), PackedByteArray([8, 98, 227, 127]))
	seed_pixel(doc, layers[12], Vector2i(0, 0), PackedByteArray([200, 40, 70, 255]))
	seed_pixel(doc, layers[23], Vector2i(160, 160), PackedByteArray([1, 2, 3, 255]))
	# A stored alpha-zero tile still exists even though its visible color is zero.
	seed_pixel(doc, layers[6], Vector2i(-2, 1), PackedByteArray([50, 100, 150, 0]))
	var view: Rect2i = Rect2i(-8, -8, 16, 16)
	doc.resolve_calls = 0
	var baseline: DrawingResult = DrawingRenderer.render(doc, view)
	var baseline_resolves: int = doc.resolve_calls
	check(baseline.ok and baseline_resolves == 24 * 4,
		"unplanned control resolves all 24 layers and four signed source chunks")
	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	doc.resolve_calls = 0
	var optimized: DrawingResult = DrawingRenderer.render(doc, view, 0, 0, 1048576, null, plan)
	check(optimized.ok and (optimized.value as Image).get_data() ==
		(baseline.value as Image).get_data(), "sparse planned render equals normal RGBA8 image")
	check(doc.resolve_calls == 12,
		"three overlapping stored layers only resolve 12 chunks, not 96: %d" % doc.resolve_calls)
	# Fair paired runs on the original *valid* sparse scene preserve sample
	# variation; neither loop records a real frame or physical GPU latency.
	var control_us: Array[int] = []
	var optimized_us: Array[int] = []
	var fair_plan: Dictionary = plan
	for iteration: int in range(9):
		var options: Array[bool] = [false, true]
		if iteration % 2 != 0:
			options.reverse()
		for planned: bool in options:
			var start_us: int = Time.get_ticks_usec()
			var output: DrawingResult = DrawingRenderer.render(doc, view, 0, 0,
				1048576, null, fair_plan if planned else {})
			var duration_us: int = Time.get_ticks_usec() - start_us
			check(output.ok, "timed control and sparse plans both complete")
			if planned:
				optimized_us.append(duration_us)
			else:
				control_us.append(duration_us)
	control_us.sort()
	optimized_us.sort()
	print("T086_SPARSE_BENCH_JSON " + JSON.stringify({
		"engine": Engine.get_version_info().get("string", "unknown"),
		"samples": control_us.size(), "view": "16x16", "visible_layers": 24,
		"baseline_us_median": control_us[4],
		"culled_us_median": optimized_us[4],
		"baseline_us_p95": control_us[8], "culled_us_p95": optimized_us[8]}))

	check(doc.raster_may_cover(layers[0], -8, -8, 16, 16),
		"negative-source chunk is retained")
	check(not doc.raster_may_cover(layers[23], -8, -8, 16, 16),
		"remote positive-source chunk can be skipped")
	check(doc.raster_may_cover(layers[23], 0, 0, 128, 128),
		"large footprint falls back conservatively")
	check(doc.raster_may_cover("missing-layer", -8, -8, 16, 16),
		"invalid source must be conservatively probed")
	# Detached changes may appear in an otherwise empty layer. They must not
	# be excluded by the committed occupancy test before mouse release.
	var started: DrawingResult = doc.begin_edit(layers[7], doc.revision)
	check(started.ok, "start empty-layer preview")
	if started.ok:
		var preview: DrawingEditSession = started.value as DrawingEditSession
		check(preview.apply_region(Rect2i(1, 1, 1, 1),
			PackedByteArray([17, 191, 57, 255])).ok, "stage detached dab")
		var ordinary_preview: DrawingResult = DrawingRenderer.render(doc,
			view, 0, 0, 1048576, preview)
		doc.resolve_calls = 0
		var optimized_preview: DrawingResult = DrawingRenderer.render(doc,
			view, 0, 0, 1048576, preview, plan)
		check(ordinary_preview.ok and optimized_preview.ok and
			(ordinary_preview.value as Image).get_data() ==
			(optimized_preview.value as Image).get_data(),
			"planned empty-layer detached preview equals direct composite")
		check(doc.resolve_calls == 16,
			"preview layer is never skipped just because committed source is absent")
		preview.cancel()
		check(doc.revision == int(plan["revision"]), "cancellation does not commit")
		check(doc.revision == int(plan["revision"]),
			"cancellation preserves committed generation")
	# Lazy source registration invalidates an old plan even without revision
	# increment. Corrupted lazy data must never be suppressed by footprint skip.
	var wrong_bytes: PackedByteArray = PackedByteArray()
	wrong_bytes.resize(8 * 8 * 4)
	var digest: String = DrawingRasterTile.digest_rgba8(wrong_bytes, 8)
	check(doc.register_lazy_chunk(layers[14], 0, 0, "corrupt", digest,
		Callable(self, "broken_source")).ok, "register lazy source in visible region")
	var stale: DrawingResult = DrawingRenderer.render(doc, view,
		0, 0, 1048576, null, plan)
	check(not stale.ok and stale.code == "RENDER_PLAN_STALE",
		"source epoch rejects plan created before lazy registration")
	var new_plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	var corrupt: DrawingResult = DrawingRenderer.render(doc, view,
		0, 0, 1048576, null, new_plan)
	check(not corrupt.ok and corrupt.code == "CORRUPT_TILE",
		"culling never hides a corrupt pending source chunk")
	# Use signed 64-bit world anchors: renderer must not cast through Vector2i.
	var far: CountingDocument = CountingDocument.new("far-sparse", 8)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	var anchor: int = 5000000000
	var far_started: DrawingResult = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, anchor, -anchor)
	check(far_started.ok, "64-bit source anchor edit begins")
	if far_started.ok:
		var far_edit: DrawingEditSession = far_started.value as DrawingEditSession
		check(far_edit.apply_region(Rect2i(-1, -1, 1, 1),
			PackedByteArray([190, 2, 57, 255])).ok and far_edit.commit().ok,
			"64-bit negative/positive source pixel published")
		var far_view: Rect2i = Rect2i(-2, -2, 4, 4)
		var far_plain: DrawingResult = DrawingRenderer.render(far,
			far_view, anchor, -anchor)
		var far_plan: Dictionary = DrawingRenderer.prepare_visible_layers(far)
		var far_optimized: DrawingResult = DrawingRenderer.render(far,
			far_view, anchor, -anchor, 1048576, null, far_plan)
		check(far_plain.ok and far_optimized.ok and
			(far_plain.value as Image).get_data() == (far_optimized.value as Image).get_data(),
			"64-bit anchored source matches unplanned render")
	# A tiny storage stride spanning >16 chunks must take the conservative
	# resolution path, not build an unbounded occupancy map.
	var tiny: CountingDocument = CountingDocument.new("tiny-sparse", 1)
	var tiny_layer: String = String(tiny.create_layer(DrawingLayerNode.RASTER, "Tiny").value)
	check(tiny.raster_may_cover(tiny_layer, -100, 0, 100, 1),
		"wide 1px-stride region conservatively renders")

	if failures == 0:
		print("T086_SPARSE_PASSED %d/%d" % [checks, checks])
	else:
		printerr("T086_SPARSE_FAILED %d/%d" % [failures, checks])
	quit(1 if failures else 0)
