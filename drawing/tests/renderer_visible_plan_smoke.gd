extends SceneTree
## T-086: one visible-tree traversal per cold display frame, with exact
## render parity and mandatory plan invalidation on source changes.

class TraversalDocument:
	extends DrawingDocument
	var traversal_calls: int = 0

	func list_children(parent_id: String = DrawingDocument.ROOT_ID) -> Array[String]:
		traversal_calls += 1
		return super.list_children(parent_id)

var checks: int = 0
var failures: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_PLAN_FAILED: " + message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var doc: TraversalDocument = TraversalDocument.new("t086-visible-plan", 8)
	var layers: Array[String] = []
	for number: int in range(24):
		var created: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER,
			"Sparse %d" % number)
		check(created.ok, "create source layer %d" % number)
		layers.append(String(created.value))
	# Use actual published pixels, including fractional alpha and negative
	# coordinates, so the two paths must agree on nontransparent output.
	for index: int in [0, 11, 23]:
		var edit: DrawingResult = doc.begin_edit(layers[index], doc.revision)
		check(edit.ok, "begin source edit %d" % index)
		if edit.ok:
			var session: DrawingEditSession = edit.value as DrawingEditSession
			var rgba: PackedByteArray = PackedByteArray()
			for pixel: int in range(25):
				rgba.append_array(PackedByteArray([20 + index, 70, 180, 127]))
			check(session.apply_region(Rect2i(-3 + index % 3, -2, 5, 5), rgba).ok,
				"seed signed pixels %d" % index)
			check(session.commit().ok, "publish source edit %d" % index)
	var tiles: Array[Rect2i] = []
	for y: int in range(-2, 2):
		for x: int in range(-2, 2):
			tiles.append(Rect2i(x * 8, y * 8, 8, 8))

	var unprepared: Array[PackedByteArray] = []
	doc.traversal_calls = 0
	for tile: Rect2i in tiles:
		var image: DrawingResult = DrawingRenderer.render(doc, tile)
		check(image.ok, "ordinary renderer handles bounded tile")
		if image.ok:
			unprepared.append((image.value as Image).get_data())
	var unprepared_walks: int = doc.traversal_calls
	check(unprepared_walks == tiles.size(),
		"ordinary tiled render traverses visible root each tile: %d" % unprepared_walks)

	doc.traversal_calls = 0
	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	check(doc.traversal_calls == 1 and (plan["layers"] as Array).size() == 24,
		"one plan retains exact ordered visible layer list")
	for i: int in range(tiles.size()):
		var image: DrawingResult = DrawingRenderer.render(doc, tiles[i],
			0, 0, 1048576, null, plan)
		check(image.ok and (image.value as Image).get_data() == unprepared[i],
			"planned layer rendering equals unplanned RGBA8 tile %d" % i)
	check(doc.traversal_calls == 1,
		"16 cold tiles reuse one source-tree walk, not one per tile")
	check(not DrawingRenderer.render(TraversalDocument.new("foreign", 8),
		tiles[0], 0, 0, 1048576, null, plan).ok,
		"cross-document plan is rejected")

	var preview_result: DrawingResult = doc.begin_edit(layers[11], doc.revision)
	check(preview_result.ok, "start detached preview with unchanged revision")
	if preview_result.ok:
		var preview: DrawingEditSession = preview_result.value as DrawingEditSession
		check(preview.apply_region(Rect2i(-1, 0, 1, 1),
			PackedByteArray([33, 200, 7, 255])).ok, "stage detached alpha pixel")
		var plain: DrawingResult = DrawingRenderer.render(doc, tiles[9],
			0, 0, 1048576, preview)
		var prepared: DrawingResult = DrawingRenderer.render(doc, tiles[9],
			0, 0, 1048576, preview, plan)
		check(plain.ok and prepared.ok and
			(plain.value as Image).get_data() == (prepared.value as Image).get_data(),
			"revision-stable plan respects layer-correct detached preview")
		preview.cancel()
		check(doc.revision == int(plan["revision"]),
			"cancellation does not invalidate committed source plan")

	check(doc.set_visibility(layers[23], false).ok, "hide source layer")
	var stale: DrawingResult = DrawingRenderer.render(doc, tiles[5],
		0, 0, 1048576, null, plan)
	check(not stale.ok and stale.code == "RENDER_PLAN_STALE",
		"structural visibility revision rejects stale plan")
	var fresh: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
	check((fresh["layers"] as Array).size() == 23,
		"new source plan excludes hidden layer")
	check(DrawingRenderer.render(doc, tiles[5], 0, 0, 1048576, null, fresh).ok,
		"fresh plan renders after visibility change")

	var lazy_bytes: PackedByteArray = PackedByteArray()
	lazy_bytes.resize(8 * 8 * 4)
	var loader: Callable = func(_ref: String) -> PackedByteArray: return lazy_bytes
	var epoch: int = doc.display_source_epoch
	check(doc.register_lazy_chunk(layers[0], 4, 4, "sample",
		DrawingRasterTile.digest_rgba8(lazy_bytes, 8), loader).ok,
		"register lazy tile with independent source epoch")
	check(doc.display_source_epoch > epoch and doc.revision == int(fresh["revision"]),
		"lazy registration updates epoch without content revision")
	stale = DrawingRenderer.render(doc, tiles[5], 0, 0, 1048576, null, fresh)
	check(not stale.ok and stale.code == "RENDER_PLAN_STALE",
		"source registration epoch rejects stale visible list")
	fresh = DrawingRenderer.prepare_visible_layers(doc)
	check(DrawingRenderer.render(doc, tiles[5], 0, 0, 1048576, null, fresh).ok,
		"fresh source plan survives registered lazy source")

	# Paired samples keep the exact same document/tiles in both paths.
	# These numbers diagnose tree-walk overhead on this *headless CPU* host;
	# they are not a full viewport or physical input-to-photon latency metric.
	var old_us: Array[int] = []
	var planned_us: Array[int] = []
	for trial: int in range(9):
		var orders: Array[bool] = [false, true]
		if trial % 2 == 1:
			orders.reverse()
		for planned: bool in orders:
			var before: int = Time.get_ticks_usec()
			for tile: Rect2i in tiles:
				var output: DrawingResult = DrawingRenderer.render(doc, tile,
					0, 0, 1048576, null, fresh if planned else {})
				if not output.ok:
					check(false, "paired cold tile render returned failure")
			var elapsed: int = Time.get_ticks_usec() - before
			if planned:
				planned_us.append(elapsed)
			else:
				old_us.append(elapsed)
	old_us.sort()
	planned_us.sort()
	print("T086_PLAN_BENCH_JSON " + JSON.stringify({
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display": DisplayServer.get_name(),
		"samples": old_us.size(), "source_layers": 23,
		"tile_count": tiles.size(), "tile_size": 8,
		"unplanned_us_median": old_us[4], "planned_us_median": planned_us[4],
		"unplanned_us_p95": old_us[8], "planned_us_p95": planned_us[8]}))

	var broken: Dictionary = fresh.duplicate()
	broken["layers"] = 42
	var malformed: DrawingResult = DrawingRenderer.render(doc, tiles[5],
		0, 0, 1048576, null, broken)
	check(not malformed.ok and malformed.code == "RENDER_PLAN_INVALID",
		"malformed visible-layer plan fails closed")

	if failures == 0:
		print("T086_PLAN_PASSED %d/%d" % [checks, checks])
	else:
		printerr("T086_PLAN_FAILED %d/%d" % [failures, checks])
	quit(1 if failures else 0)
