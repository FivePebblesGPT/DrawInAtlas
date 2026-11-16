extends SceneTree
## A rejected native park/retire must never erase a Godot raster subtree.

const STRIDE: int = 64
const INK: int = 0xff4268ac
const HIDDEN: int = 0x00112233
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T168_SUBTREE_FAILED: " + label)


func stroke(doc: DrawingDocument, layer: String, position: Vector2) -> DrawingResult:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not opened.ok:
		return opened
	var edit: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var began: DrawingResult = edit.begin_native_stroke(brush, preset,
		8.0, INK, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not began.ok:
		edit.cancel()
		return began
	var painted: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[position, position + Vector2(9, 0)]), INK, false, null)
	if not painted.ok:
		edit.cancel()
		return painted
	return edit.commit()


func native_bytes(store: Object, layer: String) -> PackedByteArray:
	return store.call("read_tile", layer, 0, 0, false).get("bytes", PackedByteArray())


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required native extension loaded")
	var doc: DrawingDocument = DrawingDocument.new("t168-structure", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	var group: String = str(doc.create_layer(DrawingLayerNode.GROUP,
		"To remove", "root", "group").value)
	var leaf: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Painted", group, "leaf").value)
	var ink_stroke: DrawingResult = stroke(doc, ink, Vector2(6, 8))
	var leaf_stroke: DrawingResult = stroke(doc, leaf, Vector2(15, 15))
	check(ink_stroke.ok and leaf_stroke.ok, "two native strokes committed")
	if not ink_stroke.ok or not leaf_stroke.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var original_ink: PackedByteArray = native_bytes(store, ink)
	var original_leaf: PackedByteArray = native_bytes(store, leaf)
	var token: int = leaf_stroke.delta.native_history_token
	var base: int = doc.revision
	var before_history: int = doc.history_length()
	var before_cursor: int = doc.history_position()
	var before_children: Array[String] = doc.list_children("root")
	var leaf_tile: DrawingRasterTile = doc._nodes[leaf].tiles.get("0,0")
	check(leaf_tile != null and leaf_tile.get_rgba(49, 49) == 0,
		"resident painted tile has transparent test pixel")
	check(leaf_tile.set_rgba(49, 49, HIDDEN), "tamper with alpha-zero RGB")
	var invalid_source: DrawingResult = doc.remove_subtree(group, true)
	check(not invalid_source.ok and invalid_source.code == "STALE_SOURCE",
		"tampered native subtree refuses recorded removal")
	check(doc.has_node(group) and doc.has_node(leaf) and
		doc.list_children("root") == before_children and doc.revision == base,
		"rejected removal preserves complete Godot structure and revision")
	check(doc.history_length() == before_history and doc.history_position() == before_cursor,
		"rejected removal preserves local history timeline")
	check(int(store.call("stats").get("revision", -1)) == base and
		native_bytes(store, leaf) == original_leaf and native_bytes(store, ink) == original_ink and
		store.call("has_history_token", token, base, true),
		"rejected removal preserves both native tiles and unrelated token")
	check(leaf_tile.set_rgba(49, 49, 0), "restore original Godot projection")
	var held: Dictionary = store.call("begin_edit", ink, base, false)
	check(bool(held.get("ok", false)), "native transaction blocks structural removal")
	var during_edit: DrawingResult = doc.remove_subtree(group, true)
	check(not during_edit.ok and during_edit.code == "NATIVE_STRUCTURE",
		"busy native store rejects recorded removal")
	check(doc.has_node(leaf) and doc.revision == base and
		int(store.call("stats").get("revision", -1)) == base and
		doc.history_position() == before_cursor,
		"busy rejection leaves Godot and native revisions/history unchanged")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"cancel blocking native transaction")
	var removed: DrawingResult = doc.remove_subtree(group, true)
	check(removed.ok and not doc.has_node(group) and not doc.has_node(leaf),
		"valid recorded group removal succeeds")
	check(doc.revision == base + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		bool(store.call("is_layer_parked", leaf)),
		"recorded removal parks native subtree in matching revision")
	check(doc.undo().ok and doc.has_node(leaf) and
		doc._nodes[leaf].tiles["0,0"].to_rgba8() == original_leaf and
		native_bytes(store, leaf) == original_leaf,
		"Undo restores exact raster bytes from Rust")
	check(doc.redo().ok and not doc.has_node(group) and
		bool(store.call("is_layer_parked", leaf)),
		"Redo re-parks the same native source")
	check(doc.undo().ok and doc.has_node(leaf),
		"repeated Undo un-parks group for later editing")
	check(native_bytes(store, ink) == original_ink and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"unrelated native source and revision remain authoritative")
	# An unrecorded removal must be equally failure-atomic.
	var second_group: String = str(doc.create_layer(DrawingLayerNode.GROUP,
		"Disposable", "root", "other-group").value)
	var second: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Disposable Ink", second_group, "other-ink").value)
	check(stroke(doc, second, Vector2(19, 20)).ok, "prepare second native subtree")
	var second_bytes: PackedByteArray = native_bytes(store, second)
	var second_base: int = doc.revision
	var unrecorded_held: Dictionary = store.call("begin_edit", ink, second_base, false)
	check(bool(unrecorded_held.get("ok", false)), "begin second active native edit")
	var unrecorded_reject: DrawingResult = doc.remove_subtree(second_group, false)
	check(not unrecorded_reject.ok and unrecorded_reject.code == "NATIVE_STRUCTURE" and
		doc.has_node(second) and doc.revision == second_base,
		"busy native store rejects unrecorded removal without erasing layer")
	check(native_bytes(store, second) == second_bytes and
		int(store.call("stats").get("revision", -1)) == second_base,
		"unrecorded rejection retains native source and revision")
	check(store.call("discard_edit", int(unrecorded_held.get("transaction", 0))),
		"discard second blocking transaction")
	var retired: DrawingResult = doc.remove_subtree(second_group, false)
	check(retired.ok and not doc.has_node(second) and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		native_bytes(store, ink) == original_ink,
		"valid unrecorded retirement keeps unrelated native source")
	# A never-authorized raster can advance Rust metadata without parking.
	var unused: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Unused", "root", "unused").value)
	var unref_base: int = doc.revision
	check(doc.remove_subtree(unused, true).ok and not doc.has_node(unused) and
		int(store.call("stats").get("revision", -1)) == unref_base + 1,
		"unreferenced raster removal advances native and Godot together")
	check(doc.undo().ok and doc.has_node(unused) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"unreferenced raster Undo retains synchronized revisions")
	# Attached native-ahead authority also rejects removal without mutation.
	var ahead: int = doc.revision
	check(store.call("advance_metadata_revision", ahead, false),
		"inject independent native revision advance")
	var native_ahead: DrawingResult = doc.remove_subtree(group, false)
	check(not native_ahead.ok and native_ahead.code == "STALE_REVISION" and
		doc.has_node(group) and doc.has_node(leaf) and doc.revision == ahead and
		int(store.call("stats").get("revision", -1)) == ahead + 1,
		"native-ahead subtree removal rejected without Godot mutation")
	var historical: DrawingDocument = DrawingDocument.new("t168-historical", STRIDE)
	var historical_layer: String = str(historical.create_layer(
		DrawingLayerNode.RASTER, "Old", "root", "old").value)
	check(historical._native_raster_store == null and
		historical.remove_subtree(historical_layer, false).ok and
		not historical.has_node(historical_layer),
		"native-absent historical removal remains supported until T-150")
	print("T168_SUBTREE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0 and checks >= 25:
		print("T168_SUBTREE_PASSED (%d checks; 0 failed)" % checks)
	quit(0 if failures == 0 else 1)
