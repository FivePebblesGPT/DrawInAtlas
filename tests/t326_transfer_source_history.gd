extends "res://tests/t325_transfer_redo_ownership.gd"
## A transferred layer retains its own native paint history in each document.

func make_transfer(timeline: AtlasEditHistory, source: DrawingDocument, target: DrawingDocument,
		layer: String, copy: bool) -> AtlasDrawingTransfer:
	var command: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, target, layer, "root", copy,
		context(source, layer), context(target, layer))
	check(timeline.execute_drawing_transfer(command), "transfer layer")
	return command

func exercise_source_history(copy: bool) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var source: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	var target: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	check(source.create_layer(DrawingLayerNode.RASTER, "Travel", "root", "travel").ok, "source raster")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "host owners")
	var original: int = paint(source, timeline, "travel", -1)
	var initial_bytes: int = int(source._native_raster_store.call("stats")["bytes_used"])
	var first: AtlasDrawingTransfer = make_transfer(timeline, source, target, "travel", copy)
	if not first._applied:
		return
	var destination: String = first.target_node_id
	check(retained(source, original), "original token survives transfer")
	if not copy:
		var rev: int = source.revision
		var store: Object = source._native_raster_store
		check(int(store.call("stats")["tiles"]) == 0 and int(store.call("stats")["bytes_used"]) < initial_bytes,
			"departing live sources released, not parked")
		check(not bool(store.call("has_history_token", original, rev, true)), "absent layer token cannot replay")
		check(not source.create_layer(DrawingLayerNode.RASTER, "Unrelated", "root", "travel").ok and
			source.revision == rev, "ordinary layer creation cannot reuse retained identity")
		check(not source.import_subtree(first._snapshot, "root", true).ok and source.revision == rev,
			"ordinary import cannot reuse retained identity")
		var empty: Array[Dictionary] = []
		check(not bool(store.call("publish_transfer_subtree_revision", rev, PackedStringArray(["travel"]), empty)),
			"missing native history coordinates reject atomic re-admission")
		check(source.revision == rev and int(store.call("stats")["revision"]) == rev and retained(source, original),
			"rejected import retains token and revision")
	var added: int = paint(target, timeline, destination, -65)
	check(timeline.undo(), "undo destination paint")
	check(timeline.undo(), "undo transfer")
	check(retained(target, added), "destination redo survives transfer Undo")
	check(int(target._native_raster_store.call("stats")["tiles"]) == 0, "undo transfer releases destination live sources")
	check(retained(source, original), "source undo survives transfer Undo")
	check(timeline.undo(), "undo original source paint")
	check(int(source.read_pixel("travel", -1, 1).value) == 0, "source pixel undone")
	check(timeline.redo(), "redo original source paint")
	check(timeline.redo(), "redo transfer")
	check(retained(target, added), "destination token survives transfer Redo")
	check(target._native_source_matches(destination, "-2,0", null), "blank history coordinate reauthorized")
	check(timeline.redo(), "redo destination paint on previously blank tile")
	check(int(target.read_pixel(destination, -65, 1).value) == INK and
		int(target.read_pixel(destination, -1, 1).value) == INK, "exact transferred and destination hidden RGB")
	check(source._native_save_projection_matches() and target._native_save_projection_matches(), "exact projections")
	check(timeline.undo() and timeline.undo(), "undo transfer again")
	var grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 4.0
	check(timeline.execute(AtlasGridEdit.new("world", grid, changed)), "branch abandons destination history")
	check(not retained(target, added) and retained(source, original), "branch releases only abandoned token")
	check(int(target._native_raster_store.call("stats")["bytes_used"]) == 0, "abandoned absent destination releases all native data")

func exercise_round_trip() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var a: DrawingDocument = DrawingDocument.new("t326-round-a", 64)
	var b: DrawingDocument = DrawingDocument.new("t326-round-b", 64)
	check(a.create_layer(DrawingLayerNode.RASTER, "Travel", "root", "travel").ok, "round raster")
	check(a.set_external_history(true).ok and b.set_external_history(true).ok, "round owners")
	var first: int = paint(a, timeline, "travel", -1)
	var outbound: AtlasDrawingTransfer = make_transfer(timeline, a, b, "travel", false)
	if not outbound._applied:
		return
	var second: int = paint(b, timeline, "travel", -65)
	var inbound: AtlasDrawingTransfer = make_transfer(timeline, b, a, "travel", false)
	if not inbound._applied:
		return
	var third: int = paint(a, timeline, "travel", 65)
	check(retained(a, first) and retained(b, second) and retained(a, third), "all visits retain native tokens")
	for i: int in range(5):
		check(timeline.undo(), "round trip undo %d" % i)
	check(a.has_node("travel") and not b.has_node("travel") and
		int(a.read_pixel("travel", -1, 1).value) == 0, "rewind both moves")
	for i: int in range(5):
		check(timeline.redo(), "round trip redo %d" % i)
	check(a.has_node("travel") and not b.has_node("travel"), "return to final owner")
	for x: int in [-1, -65, 65]:
		check(int(a.read_pixel("travel", x, 1).value) == INK, "round trip exact signed pixel")
	check(retained(a, first) and retained(b, second) and retained(a, third), "all original tokens remain")
	timeline.reset(campaign)
	check(not retained(a, first) and not retained(b, second) and not retained(a, third), "reset releases tokens across visits")
	check(a._native_save_projection_matches() and b._native_save_projection_matches(), "reset retains live bytes")
	check(int(b._native_raster_store.call("stats")["bytes_used"]) == 0 and
		b.create_layer(DrawingLayerNode.RASTER, "Reusable", "root", "travel").ok,
		"reset releases absent identity and all native data")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension present")
	exercise_source_history(false)
	exercise_source_history(true)
	exercise_round_trip()
	print("T326 checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T326_TRANSFER_SOURCE_HISTORY_PASSED")
	quit(1 if failures else 0)
