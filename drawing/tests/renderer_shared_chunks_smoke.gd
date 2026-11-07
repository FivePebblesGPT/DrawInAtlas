extends SceneTree
## T-086: a pinned cold-frame plan may reuse canonical storage chunks across
## adjacent 128px display tiles. Direct renders remain independent.

class CountingDocument:
	extends DrawingDocument
	var resolves: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolves += 1
		return super._resolve_chunk(layer_id, key)

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T086_SHARED_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func seed_layer(doc: DrawingDocument, layer: String, point: Vector2i,
		color: PackedByteArray) -> void:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "open seed transaction")
	if started.ok:
		var edit: DrawingEditSession = started.value as DrawingEditSession
		check(edit.apply_region(Rect2i(point, Vector2i.ONE), color).ok,
			"stage source pixel")
		check(edit.commit().ok, "commit canonical seed")


func bad_blob(_ref: String) -> PackedByteArray:
	return PackedByteArray([9, 9, 9])


func run() -> void:
	var doc: CountingDocument = CountingDocument.new("shared-source-chunks", 256)
	var bottom: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Bottom").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	seed_layer(doc, bottom, Vector2i(1, 1), PackedByteArray([240, 30, 12, 255]))
	seed_layer(doc, top, Vector2i(130, 130), PackedByteArray([15, 110, 245, 128]))
	var tiles: Array[Rect2i] = [Rect2i(0, 0, 128, 128),
		Rect2i(128, 0, 128, 128), Rect2i(0, 128, 128, 128),
		Rect2i(128, 128, 128, 128)]
	var originals: Array[PackedByteArray] = []
	doc.resolves = 0
	for view: Rect2i in tiles:
		var output: DrawingResult = DrawingRenderer.render(doc, view)
		check(output.ok, "direct source tile renders")
		if output.ok:
			originals.append((output.value as Image).get_data())
	check(doc.resolves == 8, "direct renders fetch 2 chunks per display tile")

	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	doc.resolves = 0
	for i: int in range(tiles.size()):
		var output: DrawingResult = DrawingRenderer.render(doc, tiles[i],
			0, 0, 1048576, null, plan)
		check(output.ok and (output.value as Image).get_data() == originals[i],
			"planned chunk reuse has byte-exact image %d" % i)
	check(doc.resolves == 2, "same source chunks fetched once across four display tiles")
	check((plan["source_chunks"] as Dictionary).size() == 2,
		"only two canonical source references retained")

	# The plan is pinned to immutable published source, not mutable draft bytes.
	var begun: DrawingResult = doc.begin_edit(bottom, doc.revision)
	check(begun.ok, "open detached preview")
	if begun.ok:
		var preview: DrawingEditSession = begun.value as DrawingEditSession
		check(preview.apply_region(Rect2i(2, 2, 1, 1),
			PackedByteArray([6, 220, 40, 255])).ok, "stage first uncommitted dab")
		var with_plan: DrawingResult = DrawingRenderer.render(doc, tiles[0],
			0, 0, 1048576, preview, plan)
		var direct: DrawingResult = DrawingRenderer.render(doc, tiles[0],
			0, 0, 1048576, preview)
		check(with_plan.ok and direct.ok and (with_plan.value as Image).get_data() ==
			(direct.value as Image).get_data(), "cached source respects detached dab")
		check(preview.apply_region(Rect2i(3, 3, 1, 1),
			PackedByteArray([130, 7, 211, 255])).ok, "stage second uncommitted dab")
		with_plan = DrawingRenderer.render(doc, tiles[0], 0, 0, 1048576, preview, plan)
		direct = DrawingRenderer.render(doc, tiles[0], 0, 0, 1048576, preview)
		check(with_plan.ok and direct.ok and (with_plan.value as Image).get_data() ==
			(direct.value as Image).get_data(), "cached source never caches preview patches")
		preview.cancel()
		check(doc.revision == int(plan["revision"]), "cancel preserves committed revision")

	# A plan that cached a previous absent chunk must fail after an uncommitted
	# lazy source registration changes the epoch; corruption must stay visible.
	var absent: DrawingResult = DrawingRenderer.render(doc,
		Rect2i(512, 512, 1, 1), 0, 0, 1048576, null, plan)
	check(absent.ok, "pre-lazy absent render succeeds")
	var blank: PackedByteArray = PackedByteArray()
	blank.resize(256 * 256 * 4)
	check(doc.register_lazy_chunk(bottom, 2, 2, "missing-corrupt",
		DrawingRasterTile.digest_rgba8(blank, 256),
		Callable(self, "bad_blob")).ok, "register deliberately corrupted lazy tile")
	var stale: DrawingResult = DrawingRenderer.render(doc,
		Rect2i(512, 512, 1, 1), 0, 0, 1048576, null, plan)
	check(not stale.ok and stale.code == "RENDER_PLAN_STALE",
		"cache cannot bypass source epoch invalidation")
	var updated: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	var corrupt: DrawingResult = DrawingRenderer.render(doc,
		Rect2i(512, 512, 1, 1), 0, 0, 1048576, null, updated)
	check(not corrupt.ok and corrupt.code == "CORRUPT_TILE",
		"new plan still validates corrupt lazy bytes")

	# Small strides / wide view must never produce an unbounded shared cache.
	var many: CountingDocument = CountingDocument.new("many-chunks", 1)
	var layer: String = String(many.create_layer(DrawingLayerNode.RASTER, "Many").value)
	var refs: Dictionary = {}
	var empty: PackedByteArray = PackedByteArray()
	empty.resize(300 * 4)
	var first: DrawingResult = DrawingRenderer._composite_raster(many,
		layer, -150, 0, Vector2i(300, 1), empty, null, refs)
	check(first.ok and many.resolves == 300, "first wide read probes every chunk")
	check(refs.size() == 256, "frame source refs capped at 256 even for 1px strides")
	many.resolves = 0
	var second: DrawingResult = DrawingRenderer._composite_raster(many,
		layer, -150, 0, Vector2i(300, 1), empty, null, refs)
	check(second.ok and many.resolves == 44,
		"null chunks cached and overflow safely resolved without unbounded memory")

	# Source identity is part of the cache key; the same tile coordinate in
	# different raster layers must not accidentally reuse another layer's bytes.
	check(originals[0][(1 * 128 + 1) * 4] == 240 and
		originals[3][(2 * 128 + 2) * 4] == 15,
		"layer IDs stay separate despite identical signed source-chunk key")
	if failures == 0:
		print("T086_SHARED_PASSED %d/%d" % [checks, checks])
	else:
		printerr("T086_SHARED_FAILED %d/%d" % [failures, checks])
	quit(1 if failures else 0)
