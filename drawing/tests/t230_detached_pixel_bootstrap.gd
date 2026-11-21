extends SceneTree
## Detached legacy-pixel history must bootstrap canonical Rust ownership even
## before a Brush gesture has ever attached a tile store.

const HIDDEN: int = 0x00335577
const OPAQUE: int = 0xff224466
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T230_BOOTSTRAP_FAILED: " + label)


func fixture(name: String, external: bool = false) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, 64)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER,
		"Raster", "root", "ink").value)
	if external:
		check(document.set_external_history(true).ok, "host history mode enabled")
	var result: DrawingResult = document._publish_edit(layer, document.revision,
		{"-1,2": 0, "65,0": 0}, {"-1,2": HIDDEN, "65,0": OPAQUE})
	check(result.ok and result.delta.tile_stride == 0,
		"historical pixel map captured without native Brush")
	return {"document": document, "layer": layer, "delta": result.delta.detached_copy()}


func canonical_matches(document: DrawingDocument, layer: String, key: String) -> bool:
	var coordinates: PackedStringArray = key.split(",")
	var store: Object = document._native_raster_store
	if store == null:
		return false
	var native: Dictionary = store.call("read_tile", layer,
		int(coordinates[0]), int(coordinates[1]), false)
	var projected: DrawingResult = document.request_chunk(layer, key)
	if not native.get("ok", false) or not projected.ok:
		return false
	var bytes: PackedByteArray = PackedByteArray()
	if projected.value != null:
		bytes = (projected.value as DrawingRasterTile).to_rgba8()
	if bytes.is_empty():
		bytes.resize(64 * 64 * 4)
	return native.get("bytes", PackedByteArray()) == bytes


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real Rust tile-store extension loaded")
	var local: Dictionary = fixture("t230-local")
	var doc: DrawingDocument = local.document
	var layer: String = local.layer
	check(doc._native_raster_store == null, "local history starts without native store")
	var before: int = doc.revision
	var undone: DrawingResult = doc.undo()
	check(undone.ok and doc.history_position() == 0, "local legacy Undo succeeds")
	check(doc._native_raster_store != null, "local Undo bootstraps native owner")
	var store: Object = doc._native_raster_store
	check(store != null and int(store.call("stats").get("revision", -1)) == before + 1,
		"Rust and document revisions advance together on local Undo")
	check(canonical_matches(doc, layer, "-1,0") and canonical_matches(doc, layer, "1,0"),
		"signed tile sources match canonical Rust bytes after Undo")
	check(doc.redo().ok and doc._native_raster_store == store and
		int(doc.read_pixel(layer, -1, 2).value) == HIDDEN and
		int(doc.read_pixel(layer, 65, 0).value) == OPAQUE,
		"local Redo restores exact RGBA8 and reuses native owner")
	check(canonical_matches(doc, layer, "-1,0") and canonical_matches(doc, layer, "1,0"),
		"local Redo publishes Rust-owned hidden RGB and visible pixels")
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "new native Brush edit can start after legacy bootstrap")
	if started.ok:
		var session: DrawingEditSession = started.value
		var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
		var began: DrawingResult = session.begin_native_stroke(brush,
			FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
			8.0, 0xff3366aa, Rect2i(-64, -64, 192, 128), true)
		check(began.ok, "Hokusai native batch accepts reauthorized pixel history")
		if began.ok:
			var painted: DrawingResult = session.paint_path_native(PackedVector2Array([
				Vector2(-4.0, 14.0), Vector2(8.0, 14.0)]), 0xff3366aa, false, null)
			check(painted.ok, "Hokusai stroke stages from bootstrapped source")
			if painted.ok:
				var committed: DrawingResult = session.commit()
				check(committed.ok and doc._native_raster_store == store and
					int(store.call("stats").get("revision", -1)) == doc.revision,
					"native gesture retains the same Rust store after history bootstrap")
			else:
				session.cancel()
		else:
			session.cancel()

	var external: Dictionary = fixture("t230-external", true)
	var host: DrawingDocument = external.document
	var host_layer: String = external.layer
	var delta: DrawingDelta = external.delta
	check(host._native_raster_store == null, "host timeline initially has no Rust store")
	check(host.replay_delta(delta, true).ok and host._native_raster_store != null,
		"host-owned detached pixel Undo bootstraps native history")
	var host_store: Object = host._native_raster_store
	check(canonical_matches(host, host_layer, "-1,0") and
		canonical_matches(host, host_layer, "1,0"),
		"detached host Undo preserves exact Rust source projection")
	check(host.replay_delta(delta, false).ok and host._native_raster_store == host_store and
		int(host.read_pixel(host_layer, -1, 2).value) == HIDDEN and
		canonical_matches(host, host_layer, "1,0"),
		"host Redo reuses canonical store and restores hidden RGB")
	var held: Dictionary = host_store.call("begin_edit", host_layer, host.revision, false)
	check(bool(held.get("ok", false)), "native transaction can hold detached owner busy")
	var held_revision: int = host.revision
	check(not host.replay_delta(delta, true).ok and host.revision == held_revision and
		int(host_store.call("stats").get("revision", -1)) == held_revision and
		int(host.read_pixel(host_layer, -1, 2).value) == HIDDEN,
		"busy native store rejects host Undo without consuming its source")
	check(host_store.call("discard_edit", int(held.get("transaction", 0))),
		"held native transaction can be discarded")
	check(host.replay_delta(delta, true).ok and host._native_raster_store == host_store and
		canonical_matches(host, host_layer, "-1,0"),
		"identical host Undo retries against the same Rust authority")
	check(host.replay_delta(delta, false).ok and host._native_raster_store == host_store,
		"host returns to original source before persistence")

	var path: String = ProjectSettings.globalize_path("user://t230-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(host, path).ok, "host-authorized source saves")
	var opened: DrawingResult = DrawingFileIO.open(path)
	check(opened.ok and opened.value != null, "saved source reopens")
	if opened.ok:
		var reopened: DrawingDocument = opened.value
		check(reopened._native_raster_store == null, "reloaded document starts detached")
		check(reopened.replay_delta(delta, true).ok and
			reopened._native_raster_store != null and
			canonical_matches(reopened, host_layer, "-1,0"),
			"host delta replays into fresh Rust store after portable Open")
	DirAccess.remove_absolute(path)

	var invalid: Dictionary = fixture("t230-invalid", true)
	var broken: DrawingDocument = invalid.document
	var baseline: int = broken.revision
	var malformed: DrawingDelta = DrawingDelta.new(invalid.layer,
		{"01,0": 0}, {"01,0": OPAQUE})
	check(not broken.replay_delta(malformed, false).ok and broken.revision == baseline and
		broken._native_raster_store == null,
		"invalid noncanonical pixel key never bootstraps native state")
	var wrong: DrawingDelta = DrawingDelta.new(invalid.layer,
		{"-1,2": OPAQUE}, {"-1,2": HIDDEN})
	check(not broken.replay_delta(wrong, false).ok and broken.revision == baseline and
		broken._native_raster_store == null,
		"source mismatch leaves canonical attachment absent and revision unchanged")
	var many_before: Dictionary[String, int] = {}
	var many_after: Dictionary[String, int] = {}
	for index: int in range(129):
		var key: String = "%d,0" % (index * 64)
		many_before[key] = 0
		many_after[key] = OPAQUE
	check(not broken.replay_delta(DrawingDelta.new(invalid.layer,
		many_before, many_after), false).ok and broken.revision == baseline and
		broken._native_raster_store == null,
		"over-budget historical source never attaches a partial native store")

	if failures == 0:
		print("T230_PIXEL_BOOTSTRAP_PASSED checks=%d failures=0" % checks)
	else:
		print("T230_PIXEL_BOOTSTRAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
