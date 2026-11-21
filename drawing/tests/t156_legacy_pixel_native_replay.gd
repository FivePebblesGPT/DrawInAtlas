extends SceneTree
## T-156: legacy per-pixel history must be committed to Rust after a native
## Brush takes ownership. Detached byte snapshots remain the host timeline.

const STRIDE: int = 64
const COLOR_A: int = 0x00123456  # alpha-zero hidden RGB
const COLOR_B: int = 0xff563412
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T156_LEGACY_NATIVE_FAILED: " + label)


func read_tile(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk(layer, key)
	if not result.ok or result.value == null:
		return PackedByteArray()
	return (result.value as DrawingRasterTile).to_rgba8()


func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var edit: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var began: DrawingResult = edit.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, 0xff3366aa, Rect2i(-64, -64, 128, 128), true)
	if not began.ok:
		edit.cancel()
		return began
	var drew: DrawingResult = edit.paint_path_native(PackedVector2Array([
		Vector2(-9.0, 15.5), Vector2(9.0, 15.5)]), 0xff3366aa, false, null)
	if not drew.ok:
		edit.cancel()
		return drew
	return edit.commit()


func make_document() -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("t156-history", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"History", "root", "history").value)
	var initial: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"-2,50": 0, "2,50": 0}, {"-2,50": COLOR_A, "2,50": COLOR_B})
	check(initial.ok and initial.delta.tile_stride == 0,
		"older host event stores historical pixel dictionaries")
	return {"doc": doc, "layer": layer}


func external_timeline() -> void:
	# Atlas owns the chronological history outside DrawingDocument. Its older
	# pixel command and newer native command must replay through one Rust owner.
	var doc: DrawingDocument = DrawingDocument.new("t156-atlas-style", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"External", "root", "external").value)
	check(doc.set_external_history(true).ok, "external host timeline enabled")
	var legacy: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"-2,50": 0, "2,50": 0}, {"-2,50": COLOR_A, "2,50": COLOR_B})
	check(legacy.ok and legacy.delta.tile_stride == 0,
		"external host captures detached historical pixel event")
	var before_brush: PackedByteArray = read_tile(doc, layer, "-1,0")
	var newer: DrawingResult = paint(doc, layer)
	check(newer.ok and newer.delta.native_history_token > 0,
		"external host captures newer Hokusai native event")
	var store: Object = doc._native_raster_store
	var committed: PackedByteArray = read_tile(doc, layer, "0,0")
	check(doc.replay_delta(newer.delta.detached_copy(), true).ok,
		"host native Brush Undo consumes real Rust token")
	check(doc.replay_delta(legacy.delta.detached_copy(), true).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(doc.read_pixel(layer, -2, 50).value) == 0,
		"host old pixel Undo remains native-authoritative")
	check(doc.replay_delta(legacy.delta.detached_copy(), false).ok and
		read_tile(doc, layer, "-1,0") == before_brush and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"host old pixel Redo restores exact hidden RGB")
	check(doc.replay_delta(newer.delta.detached_copy(), false).ok and
		read_tile(doc, layer, "0,0") == committed and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"host native Brush Redo works after detached older replay")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "real Rust Hokusai extension loaded")
	var fixture: Dictionary = make_document()
	var doc: DrawingDocument = fixture["doc"]
	var layer: String = fixture["layer"]
	check(paint(doc, layer).ok, "native Brush takes ownership of both source tiles")
	var store: Object = doc._native_raster_store
	var painted_positive: PackedByteArray = read_tile(doc, layer, "0,0")
	var painted_negative: PackedByteArray = read_tile(doc, layer, "-1,0")
	check(store != null and int(store.call("stats").get("undo", -1)) == 1,
		"native history token is held in persistent store")
	check(doc.undo().ok, "native Brush Undo completes before older pixel event")
	var pre_legacy_revision: int = doc.revision
	var original_negative: PackedByteArray = read_tile(doc, layer, "-1,0")
	var event: DrawingDelta = doc._events[0]["delta"] as DrawingDelta
	var real_after: int = event.after["-2,50"]
	event.after["-2,50"] = COLOR_B
	check(not doc.undo().ok and doc.revision == pre_legacy_revision and
		doc.history_position() == 1 and
		int(store.call("stats").get("revision", -1)) == pre_legacy_revision and
		read_tile(doc, layer, "-1,0") == original_negative,
		"corrupt old pixel history is rejected without consuming native revision")
	event.after["-2,50"] = real_after
	# This used to update only DrawingRasterTile in GDScript. The Rust store
	# stayed behind, silently losing retained history on the next Brush.
	var old_undo: DrawingResult = doc.undo()
	check(old_undo.ok and doc.history_position() == 0,
		"valid older pixel history Undo accepts a retry")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		doc.revision == pre_legacy_revision + 1,
		"legacy replay advances the identical native store revision atomically")
	check(int(doc.read_pixel(layer, -2, 50).value) == 0 and
		int(doc.read_pixel(layer, 2, 50).value) == 0,
		"Undo clears original hidden-RGB and signed pixels")
	for key: String in ["-1,0", "0,0"]:
		var parts: PackedStringArray = key.split(",")
		var native: Dictionary = store.call("read_tile", layer,
			int(parts[0]), int(parts[1]), false)
		var projected: PackedByteArray = read_tile(doc, layer, key)
		if projected.is_empty():
			projected.resize(STRIDE * STRIDE * 4)
		check(bool(native.get("ok", false)) and
			native.get("bytes", PackedByteArray()) == projected,
			"canonical Rust and Godot RGBA8 match after Undo at " + key)
	var old_redo: DrawingResult = doc.redo()
	check(old_redo.ok and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"old pixel Redo also uses same Rust authority")
	check(int(doc.read_pixel(layer, -2, 50).value) == COLOR_A and
		int(doc.read_pixel(layer, 2, 50).value) == COLOR_B,
		"Redo restores transparent hidden RGB and exact RGBA8")
	check(doc.redo().ok and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"detached native Brush Redo also remains replayable without rebase")
	check(read_tile(doc, layer, "0,0") == painted_positive and
		read_tile(doc, layer, "-1,0") == painted_negative,
		"complete pixel-then-Brush Redo returns exact same-backend bytes")
	check(paint(doc, layer).ok and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"fresh Hokusai Brush continues on the same native source")
	var save_path: String = ProjectSettings.globalize_path("user://t156-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "mixed native and older raster history saves")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok and read_tile(reopened.value as DrawingDocument, layer, "0,0") ==
		read_tile(doc, layer, "0,0") and
		read_tile(reopened.value as DrawingDocument, layer, "-1,0") ==
		read_tile(doc, layer, "-1,0"), "Save/Open retains canonical bytes")
	DirAccess.remove_absolute(save_path)

	# Replayed detached maps are not trusted just because they came from a
	# history event; validate tile budget and canonical signed coordinates.
	var revision_before: int = doc.revision
	var malformed: DrawingDelta = DrawingDelta.new(layer,
		{"01,0": 0}, {"01,0": COLOR_A})
	check(not doc.replay_delta(malformed, false).ok and
		doc.revision == revision_before and
		int(store.call("stats").get("revision", -1)) == revision_before,
		"noncanonical coordinate fails before any Rust mutation")
	var overflow: DrawingDelta = DrawingDelta.new(layer,
		{"4503599627370497,0": 0}, {"4503599627370497,0": COLOR_A})
	check(not doc.replay_delta(overflow, false).ok and doc.revision == revision_before,
		"unsafe signed coordinate rejects")
	var before_many: Dictionary[String, int] = {}
	var after_many: Dictionary[String, int] = {}
	for x: int in range(129):
		var key: String = "%d,0" % (x * STRIDE)
		before_many[key] = 0
		after_many[key] = COLOR_B
	check(not doc.replay_delta(DrawingDelta.new(layer, before_many, after_many), false).ok and
		doc.revision == revision_before,
		"129 distinct signed tiles reject without allocating an unbounded replay")
	var next: DrawingDelta = DrawingDelta.new(layer, {"-2,50": COLOR_A},
		{"-2,50": COLOR_B})
	var held: Dictionary = store.call("begin_edit", layer, doc.revision, false)
	check(bool(held.get("ok", false)), "hold native transaction for atomic failure control")
	var held_revision: int = doc.revision
	check(not doc.replay_delta(next, false).ok and
		doc.revision == held_revision and
		int(store.call("stats").get("revision", -1)) == held_revision and
		int(doc.read_pixel(layer, -2, 50).value) == COLOR_A,
		"active Rust transaction rejects old pixel replay atomically")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"active transaction cancelled after rejection")
	check(doc.replay_delta(next, false).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(doc.read_pixel(layer, -2, 50).value) == COLOR_B,
		"identical pixel event retries successfully after cancellation")
	var reverse: DrawingDelta = DrawingDelta.new(layer, {"-2,50": COLOR_B},
		{"-2,50": COLOR_A})
	check(doc.replay_delta(reverse, false).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"checked inverse restores source for native-ahead test")
	var ahead: int = doc.revision
	check(store.call("advance_metadata_revision", ahead, false),
		"inject native-ahead revision for guarded legacy replay")
	check(not doc.replay_delta(next, false).ok and
		doc.revision == ahead and
		int(store.call("stats").get("revision", -1)) == ahead + 1 and
		int(doc.read_pixel(layer, -2, 50).value) == COLOR_A,
		"native-ahead rejection preserves both owners and original pixel")
	# T-230 also routes the first historical Undo through Rust. A previously
	# unattached document must not publish a Godot-only pixel history revision.
	var old_only: Dictionary = make_document()
	var old_doc: DrawingDocument = old_only["doc"]
	check(old_doc._native_raster_store == null and old_doc.undo().ok and
		old_doc._native_raster_store != null,
		"never-native historical Undo bootstraps Rust authority")
	var newly_attached: Object = old_doc._native_raster_store
	check(old_doc.redo().ok and old_doc._native_raster_store == newly_attached and
		int(newly_attached.call("stats").get("revision", -1)) == old_doc.revision and
		int(old_doc.read_pixel("history", -2, 50).value) == COLOR_A,
		"historical Redo keeps one canonical native revision and hidden RGB")
	external_timeline()
	print("T156_LEGACY_NATIVE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
