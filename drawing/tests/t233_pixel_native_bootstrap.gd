extends SceneTree
## First direct pixel-map publication must acquire Rust tile authority atomically.

const HIDDEN: int = 0x00335577
const VISIBLE: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(_layer_id: String, _key: String) -> DrawingResult:
		reads += 1
		return DrawingResult.failure("LAZY_TOUCHED", "Preflight reached a lazy source")


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T233_PIXEL_BOOTSTRAP_FAILED: " + description)


func make_document(tag: String, host: bool = false) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(tag, 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	if host:
		check(doc.set_external_history(true).ok, "external history activated")
	return {"doc": doc, "layer": layer}


func native_matches(doc: DrawingDocument, layer: String, key: String) -> bool:
	var owner: Object = doc._native_raster_store
	if owner == null:
		return false
	var parts: PackedStringArray = key.split(",")
	var fetched: Dictionary = owner.call("read_tile", layer, int(parts[0]), int(parts[1]), false)
	var source: DrawingResult = doc.request_chunk(layer, key)
	if not bool(fetched.get("ok", false)) or not source.ok:
		return false
	var bytes: PackedByteArray = PackedByteArray()
	if source.value != null:
		bytes = (source.value as DrawingRasterTile).to_rgba8()
	if bytes.is_empty():
		bytes.resize(doc.tile_stride * doc.tile_stride * 4)
	return fetched.get("bytes", PackedByteArray()) == bytes


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "actual native extension is present")
	var pair: Dictionary = make_document("t233-local")
	var doc: DrawingDocument = pair.doc
	var layer: String = pair.layer
	var start: int = doc.revision
	check(doc._native_raster_store == null, "first pixel map starts native-detached")
	var first: DrawingResult = doc._publish_edit(layer, start,
		{"-1,4": 0, "65,0": 0}, {"-1,4": HIDDEN, "65,0": VISIBLE})
	check(first.ok, "first signed pixel-map publication succeeds")
	check(first.ok and first.delta.tile_stride == 64 and first.delta.native_history_token > 0,
		"first pixel-map publication emits native reversible tile history")
	check(doc._native_raster_store != null, "first pixel-map publication attaches Rust")
	var owner: Object = doc._native_raster_store
	if owner != null:
		check(int(owner.call("stats").get("revision", -1)) == doc.revision and
			doc.revision == start + 1, "native/document revision aligned")
		check(native_matches(doc, layer, "-1,0") and native_matches(doc, layer, "1,0"),
			"signed native tile sources are byte-identical to Godot")
	check(int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"transparent hidden RGB remains intact")
	check(doc.undo().ok and int(doc.read_pixel(layer, -1, 4).value) == 0,
		"local Undo restores original pixel")
	check(doc.redo().ok and int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"local Redo restores hidden-RGB value")
	check(doc._native_raster_store == owner, "native owner persists through history")
	var second: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"0,0": 0}, {"0,0": VISIBLE})
	check(second.ok and second.delta.tile_stride == 64 and doc._native_raster_store == owner,
		"later pixel-map publication retains native ownership")
	check(native_matches(doc, layer, "0,0"), "follow-up pixel edit remains canonical in Rust")

	# Exercise the public mixed/fill session rather than only the document seam.
	var session_pair: Dictionary = make_document("t233-session")
	var session_doc: DrawingDocument = session_pair.doc
	var session_layer: String = session_pair.layer
	var opened_session: DrawingResult = session_doc.begin_edit(session_layer,
		session_doc.revision)
	check(opened_session.ok, "mixed public session opens before Rust ownership")
	if opened_session.ok:
		var session: DrawingEditSession = opened_session.value
		check(session.fill_rect(Rect2i(-2, -2, 3, 2), HIDDEN).ok,
			"mixed fill stages signed alpha-zero pixels")
		var via_session: DrawingResult = session.commit()
		check(via_session.ok and via_session.delta.tile_stride == 64 and
			session_doc._native_raster_store != null,
			"mixed session commit acquires Rust authority")
		check(native_matches(session_doc, session_layer, "-1,-1") and
			int(session_doc.read_pixel(session_layer, -2, -2).value) == HIDDEN,
			"mixed fill has native byte-identical signed source")
		check(session_doc.undo().ok and session_doc.redo().ok and
			int(session_doc.read_pixel(session_layer, -2, -2).value) == HIDDEN,
			"mixed fill remains reversible across canonical native history")

	var host_pair: Dictionary = make_document("t233-host", true)
	var host: DrawingDocument = host_pair.doc
	var host_layer: String = host_pair.layer
	var hosted: DrawingResult = host._publish_edit(host_layer, host.revision,
		{"-1,0": 0}, {"-1,0": HIDDEN})
	check(hosted.ok and hosted.delta.tile_stride == 64 and host._native_raster_store != null,
		"Atlas-style first pixel-map edit emits detached native delta")
	if hosted.ok:
		var delta: DrawingDelta = hosted.delta.detached_copy()
		check(host.replay_delta(delta, true).ok and int(host.read_pixel(host_layer, -1, 0).value) == 0,
			"host-owned Undo replays native tile history")
		check(host.replay_delta(delta, false).ok and
			int(host.read_pixel(host_layer, -1, 0).value) == HIDDEN,
			"host-owned Redo restores exact hidden RGB")
		check(host.history_length() == 0, "host history never invents local steps")
		var path: String = ProjectSettings.globalize_path("user://t233-" +
			DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(host, path).ok, "native pixel-map source saves")
		var reopened: DrawingResult = DrawingFileIO.open(path)
		check(reopened.ok and reopened.value != null, "native pixel-map source reopens")
		if reopened.ok:
			var fresh: DrawingDocument = reopened.value
			check(fresh._native_raster_store == null, "portable reopen starts detached")
			var original: DrawingResult = fresh.read_pixel(host_layer, -1, 0)
			var retry: DrawingResult = fresh._publish_edit(host_layer, fresh.revision,
				{"-1,0": HIDDEN}, {"-1,0": VISIBLE})
			check(original.ok and retry.ok and fresh._native_raster_store != null and
				native_matches(fresh, host_layer, "-1,0"),
				"post-open direct edit bootstraps from loaded RGBA8 source")
		DirAccess.remove_absolute(path)

	var free_pair: Dictionary = make_document("t233-untracked")
	var free_doc: DrawingDocument = free_pair.doc
	var free_layer: String = free_pair.layer
	var untracked: DrawingResult = free_doc._publish_edit(free_layer, free_doc.revision,
		{"0,0": 0}, {"0,0": HIDDEN}, false)
	check(untracked.ok and free_doc._native_raster_store != null and
		untracked.delta.native_history_token == 0 and free_doc.history_length() == 0,
		"untracked first pixel-map edit establishes Rust without fabricating history")
	check(native_matches(free_doc, free_layer, "0,0") and
		int(free_doc.read_pixel(free_layer, 0, 0).value) == HIDDEN,
		"untracked native source retains hidden RGB")
	var recorded: DrawingResult = free_doc._publish_edit(free_layer, free_doc.revision,
		{"1,0": 0}, {"1,0": VISIBLE})
	check(recorded.ok and recorded.delta.native_history_token > 0 and
		free_doc.history_length() == 1,
		"recorded edit after untracked bootstrap owns native history")
	check(free_doc.undo().ok and int(free_doc.read_pixel(free_layer, 0, 0).value) == HIDDEN and
		int(free_doc.read_pixel(free_layer, 1, 0).value) == 0,
		"native Undo preserves earlier untracked pixels")

	var invalid_pair: Dictionary = make_document("t233-invalid")
	var invalid: DrawingDocument = invalid_pair.doc
	var invalid_layer: String = invalid_pair.layer
	var fail: DrawingResult = invalid._publish_edit(invalid_layer, invalid.revision,
		{"0,0": VISIBLE}, {"0,0": HIDDEN})
	check(not fail.ok and invalid._native_raster_store == null and
		invalid._nodes[invalid_layer].tiles.is_empty(),
		"stale source cannot attach partial Rust authority")
	fail = invalid._publish_edit(invalid_layer, invalid.revision,
		{"9223372036854775807,0": 0}, {"9223372036854775807,0": VISIBLE})
	check(not fail.ok and fail.code == "COORD" and invalid._native_raster_store == null,
		"out-of-projection signed edit fails before native attachment")
	var large: CountingDocument = CountingDocument.new("t233-large", 2048)
	var big_layer: String = str(large.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var before: Dictionary[String, int] = {}
	var after: Dictionary[String, int] = {}
	for index: int in range(6):
		before["%d,0" % (index * 2048)] = 0
		after["%d,0" % (index * 2048)] = VISIBLE
	fail = large._publish_edit(big_layer, large.revision, before, after)
	check(not fail.ok and fail.code == "NATIVE_TILES" and large.reads == 0,
		"unattached six 2048px tiles reject before lazy source callbacks")
	check(large._native_raster_store == null and large._nodes[big_layer].tiles.is_empty(),
		"oversized rejection leaves no attached owner or pixels")
	var crowded: CountingDocument = CountingDocument.new("t233-count", 64)
	var many_layer: String = str(crowded.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var many_before: Dictionary[String, int] = {}
	var many_after: Dictionary[String, int] = {}
	for index: int in range(129):
		many_before["%d,0" % (index * 64)] = 0
		many_after["%d,0" % (index * 64)] = VISIBLE
	fail = crowded._publish_edit(many_layer, crowded.revision, many_before, many_after)
	check(not fail.ok and fail.code == "NATIVE_TILES" and crowded.reads == 0,
		"unattached 129-tile pixel-map rejects before source reads")
	check(crowded._native_raster_store == null and crowded._nodes[many_layer].tiles.is_empty(),
		"tile-count rejection leaves ownership and raster unchanged")

	if failures == 0:
		print("T233_PIXEL_BOOTSTRAP_PASSED checks=%d failures=0" % checks)
	else:
		print("T233_PIXEL_BOOTSTRAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
