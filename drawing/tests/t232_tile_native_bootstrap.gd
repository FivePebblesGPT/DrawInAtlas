extends SceneTree
## First non-Brush tile-local publication must attach an atomic Rust owner.

const HIDDEN: int = 0x00335577
const VISIBLE: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		reads += 1
		return DrawingResult.failure("LAZY_TOUCHED", "Budget check reached a source")


func _initialize() -> void:
	call_deferred("run")


func check(accepted: bool, label: String) -> void:
	checks += 1
	if not accepted:
		failures += 1
		printerr("T232_TILE_BOOTSTRAP_FAILED: " + label)


func make_doc(tag: String, host: bool = false) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(tag, 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	if host:
		check(doc.set_external_history(true).ok, "host timeline enabled")
	return {"doc": doc, "layer": layer}


func source_matches(doc: DrawingDocument, layer: String, key: String) -> bool:
	var native: Object = doc._native_raster_store
	if native == null:
		return false
	var parts: PackedStringArray = key.split(",")
	var result: Dictionary = native.call("read_tile", layer, int(parts[0]), int(parts[1]), false)
	var projection: DrawingResult = doc.request_chunk(layer, key)
	if not bool(result.get("ok", false)) or not projection.ok:
		return false
	var bytes: PackedByteArray = PackedByteArray()
	if projection.value != null:
		bytes = (projection.value as DrawingRasterTile).to_rgba8()
	if bytes.is_empty():
		bytes.resize(doc.tile_stride * doc.tile_stride * 4)
	return result.get("bytes", PackedByteArray()) == bytes


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real Rust GDExtension is loaded")
	var local: Dictionary = make_doc("t232-local")
	var doc: DrawingDocument = local.doc
	var layer: String = local.layer
	check(doc._native_raster_store == null, "first tile-local edit begins detached")
	var initial: int = doc.revision
	var result: DrawingResult = doc._publish_tile_edit(layer, initial,
		{"-1,0": {63 + 4 * 64: HIDDEN}, "1,0": {1: VISIBLE}},
		{"-1,0": null, "1,0": null})
	check(result.ok, "first signed tile-local edit succeeds")
	check(result.ok and result.delta.tile_stride == 64 and result.delta.native_history_token > 0,
		"first tile-local edit produces native reversible tile delta")
	check(doc._native_raster_store != null, "first tile-local edit attaches Rust store")
	var owner: Object = doc._native_raster_store
	if owner != null:
		check(int(owner.call("stats").get("revision", -1)) == doc.revision and
			doc.revision == initial + 1, "Rust and document revisions match")
		check(source_matches(doc, layer, "-1,0") and source_matches(doc, layer, "1,0"),
			"signed source bytes, including hidden RGB, match Rust")
	check(int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"alpha-zero hidden RGB is retained")
	check(doc.undo().ok and int(doc.read_pixel(layer, -1, 4).value) == 0,
		"native-backed tile-local Undo clears hidden RGBA8")
	check(doc.redo().ok and int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"native-backed tile-local Redo restores hidden RGBA8")
	check(doc._native_raster_store == owner and
		(owner == null or int(owner.call("stats").get("revision", -1)) == doc.revision),
		"Undo/Redo keep the same native owner")
	var followup: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"2,0": 0}, {"2,0": VISIBLE})
	check(followup.ok and followup.delta.tile_stride == 64 and
		doc._native_raster_store == owner,
		"subsequent direct pixel publication reuses native authority")
	check(source_matches(doc, layer, "0,0"),
		"later direct pixel edit is canonical in Rust")

	var host_data: Dictionary = make_doc("t232-host", true)
	var host: DrawingDocument = host_data.doc
	var host_layer: String = host_data.layer
	var host_edit: DrawingResult = host._publish_tile_edit(host_layer, host.revision,
		{"-1,0": {63: HIDDEN}}, {"-1,0": null})
	check(host_edit.ok and host_edit.delta.tile_stride == 64 and
		host._native_raster_store != null,
		"Atlas-style first tile-local edit emits native detached history")
	if host_edit.ok:
		var held: DrawingDelta = host_edit.delta.detached_copy()
		var host_owner: Object = host._native_raster_store
		check(host.replay_delta(held, true).ok and int(host.read_pixel(host_layer, -1, 0).value) == 0,
			"host-owned Undo uses native tile replay")
		check(host.replay_delta(held, false).ok and
			int(host.read_pixel(host_layer, -1, 0).value) == HIDDEN and
			host._native_raster_store == host_owner,
			"host-owned Redo restores exact native pixels with same store")
		check(host.history_length() == 0, "host timeline does not fabricate local steps")
		var save_path: String = ProjectSettings.globalize_path("user://t232-" +
			DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(host, save_path).ok, "native bootstrap source saves")
		var opened: DrawingResult = DrawingFileIO.open(save_path)
		check(opened.ok and opened.value != null, "saved source reopens")
		if opened.ok:
			var fresh: DrawingDocument = opened.value
			check(fresh._native_raster_store == null, "portable Open starts unattached")
			var before_revision: int = fresh.revision
			check(fresh.request_chunk(host_layer, "-1,0").ok,
				"portable source can be materialized before editing")
			var from_source: DrawingRasterTile = fresh._nodes[host_layer].tiles.get("-1,0")
			var second: DrawingResult = fresh._publish_tile_edit(host_layer, fresh.revision,
				{"-1,0": {62: VISIBLE}}, {"-1,0": from_source})
			check(second.ok and fresh._native_raster_store != null and
				fresh.revision == before_revision + 1 and source_matches(fresh, host_layer, "-1,0"),
				"post-Open tile-local edit bootstraps from loaded source bytes")
		DirAccess.remove_absolute(save_path)

	var untracked_data: Dictionary = make_doc("t232-untracked")
	var untracked: DrawingDocument = untracked_data.doc
	var untracked_layer: String = untracked_data.layer
	var free_edit: DrawingResult = untracked._publish_tile_edit(untracked_layer,
		untracked.revision, {"0,0": {0: HIDDEN}}, {"0,0": null}, false)
	check(free_edit.ok and untracked._native_raster_store != null,
		"first untracked tile-local commit also bootstraps Rust")
	check(free_edit.ok and free_edit.delta.native_history_token == 0 and
		untracked.history_length() == 0 and
		int(untracked._native_raster_store.call("stats").get("undo", -1)) == 0,
		"untracked native bootstrap never invents Undo history")
	check(source_matches(untracked, untracked_layer, "0,0") and
		int(untracked.read_pixel(untracked_layer, 0, 0).value) == HIDDEN,
		"untracked bootstrap owns hidden RGB")
	var untracked_source: DrawingRasterTile = untracked._nodes[untracked_layer].tiles.get("0,0")
	var recorded: DrawingResult = untracked._publish_tile_edit(untracked_layer,
		untracked.revision, {"0,0": {1: VISIBLE}}, {"0,0": untracked_source})
	check(recorded.ok and recorded.delta.native_history_token > 0 and
		untracked.history_length() == 1,
		"first recorded edit follows an untracked native bootstrap")
	check(untracked.undo().ok and
		int(untracked.read_pixel(untracked_layer, 0, 0).value) == HIDDEN and
		int(untracked.read_pixel(untracked_layer, 1, 0).value) == 0,
		"native Undo respects prior untracked source")

	var rejected: Dictionary = make_doc("t232-reject")
	var invalid: DrawingDocument = rejected.doc
	var fail: DrawingResult = invalid._publish_tile_edit(rejected.layer, invalid.revision,
		{"0,0": {-1: VISIBLE}}, {"0,0": null})
	check(not fail.ok and invalid._native_raster_store == null and
		invalid._nodes[rejected.layer].tiles.is_empty(),
		"invalid offset leaves detached authority and source untouched")
	fail = invalid._publish_tile_edit(rejected.layer, invalid.revision,
		{"0,0": {0: VISIBLE}}, {"0,0": DrawingRasterTile.new(64)})
	check(not fail.ok and invalid._native_raster_store == null,
		"stale source identity never leaves a provisional native owner")
	var large: CountingDocument = CountingDocument.new("t232-budget", 2048)
	var large_layer: String = str(large.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var patches: Dictionary[String, Dictionary] = {}
	var sources: Dictionary[String, Variant] = {}
	for index: int in range(6):
		patches["%d,0" % index] = {0: VISIBLE}
		sources["%d,0" % index] = null
	fail = large._publish_tile_edit(large_layer, large.revision, patches, sources)
	check(not fail.ok and fail.code == "NATIVE_TILES" and large.reads == 0,
		"unattached 2048px tile producer rejects over-budget before reads")
	check(large._native_raster_store == null and large._nodes[large_layer].tiles.is_empty(),
		"budget failure leaves native owner and Godot tiles untouched")
	var crowded: CountingDocument = CountingDocument.new("t232-count", 64)
	var crowded_layer: String = str(crowded.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var many: Dictionary[String, Dictionary] = {}
	var many_sources: Dictionary[String, Variant] = {}
	for index: int in range(129):
		var key: String = "%d,0" % index
		many[key] = {0: VISIBLE}
		many_sources[key] = null
	var cap: DrawingResult = crowded._publish_tile_edit(crowded_layer, crowded.revision,
		many, many_sources)
	check(not cap.ok and cap.code == "NATIVE_TILES" and crowded.reads == 0,
		"unattached 129-tile edit rejects before source resolution")
	check(crowded._native_raster_store == null and
		crowded._nodes[crowded_layer].tiles.is_empty(),
		"over-count source rejection leaves native owner detached")

	if failures == 0:
		print("T232_TILE_BOOTSTRAP_PASSED checks=%d failures=0" % checks)
	else:
		print("T232_TILE_BOOTSTRAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
