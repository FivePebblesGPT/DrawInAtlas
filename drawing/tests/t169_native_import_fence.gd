extends SceneTree
## T-169: an attached Rust store must accept raster import before Godot publishes it.

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
		printerr("T169_IMPORT_FAILED: " + label)


func stroke(doc: DrawingDocument, layer: String) -> DrawingResult:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not opened.ok:
		return opened
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var began: DrawingResult = session.begin_native_stroke(brush, preset,
		8.0, INK, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not began.ok:
		session.cancel()
		return began
	var painted: DrawingResult = session.paint_path_native(PackedVector2Array(
		[Vector2(9, 8), Vector2(19, 8)]), INK, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func native_bytes(store: Object, layer: String) -> PackedByteArray:
	return store.call("read_tile", layer, 0, 0, false).get("bytes", PackedByteArray())


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real Rust extension loaded")
	var donor: DrawingDocument = DrawingDocument.new("donor", STRIDE)
	var group: String = str(donor.create_layer(DrawingLayerNode.GROUP, "Bundle", "root", "bundle").value)
	var child: String = str(donor.create_layer(DrawingLayerNode.RASTER, "Texture", group, "texture").value)
	var image: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	check(image.set_rgba(7, 7, HIDDEN), "prepare hidden RGB source tile")
	donor._nodes[child].tiles["0,0"] = image
	var source: DrawingResult = donor.export_subtree(group)
	check(source.ok, "detached raster import snapshot available")

	var doc: DrawingDocument = DrawingDocument.new("recipient", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	var painted: DrawingResult = stroke(doc, ink)
	check(painted.ok, "native paint authorizes resident tile")
	if not painted.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var source_bytes: PackedByteArray = native_bytes(store, ink)
	var undo_count: int = int(store.call("stats").get("undo", -1))
	var baseline: int = doc.revision
	var children: Array[String] = doc.list_children("root")
	var history_count: int = doc.history_length()
	var history_cursor: int = doc.history_position()
	var was_dirty: bool = doc.is_dirty()
	var held: Dictionary = store.call("begin_edit", ink, baseline, false)
	check(bool(held.get("ok", false)), "hold native transaction against import")
	var refused: DrawingResult = doc.import_subtree(source.value, "root", true)
	check(not refused.ok and refused.code == "NATIVE_STRUCTURE",
		"active Rust transaction rejects raster import")
	check(doc.revision == baseline and not doc.has_node(group) and
		doc.list_children("root") == children,
		"rejected import leaves Godot tree and revision unchanged")
	check(doc.history_length() == history_count and
		doc.history_position() == history_cursor and doc.is_dirty() == was_dirty,
		"rejected import preserves existing dirty/history state")
	check(int(store.call("stats").get("revision", -1)) == baseline and
		int(store.call("stats").get("undo", -1)) == undo_count and
		native_bytes(store, ink) == source_bytes,
		"rejected import leaves Rust source and Undo untouched")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"discard native transaction for retry")
	var imported: DrawingResult = doc.import_subtree(source.value, "root", true)
	check(imported.ok and doc.has_node(group) and doc.has_node(child) and
		doc.revision == baseline + 1,
		"valid import publishes complete nested tree in one revision")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == undo_count and
		native_bytes(store, ink) == source_bytes,
		"native revision and unrelated history survive valid import")
	check(doc._nodes[child].tiles["0,0"].to_rgba8() == image.to_rgba8(),
		"import preserves hidden RGB without changing donor")
	check(doc.undo().ok and int(store.call("stats").get("revision", -1)) == doc.revision,
		"earlier native Undo remains usable after import")
	check(doc.redo().ok and native_bytes(store, ink) == source_bytes,
		"native Redo retains exact raster pixels")

	# Rust ahead of Godot must never be accepted as a silent import.
	var ahead_revision: int = doc.revision
	check(bool(store.call("advance_metadata_revision", ahead_revision, true)),
		"advance native revision independently for negative control")
	var ahead: DrawingResult = doc.import_subtree(source.value, "root", false)
	check(not ahead.ok and ahead.code == "STALE_REVISION",
		"native-ahead revision rejects raster import")
	check(doc.revision == ahead_revision and doc.list_children("root") ==
		Array([ink, group]) and
		int(store.call("stats").get("revision", -1)) == ahead_revision + 1,
		"native-ahead rejection does not commit Godot nodes")

	# A bounded 128-ID Rust bridge may not be bypassed by a large import.
	var bulk: DrawingDocument = DrawingDocument.new("bulk", STRIDE)
	var bulk_group: String = str(bulk.create_layer(DrawingLayerNode.GROUP, "Bulk", "root", "bulk").value)
	for index: int in range(129):
		bulk.create_layer(DrawingLayerNode.RASTER, "Tile", bulk_group, "r%d" % index)
	var bulk_source: DrawingResult = bulk.export_subtree(bulk_group)
	var bounded: DrawingDocument = DrawingDocument.new("bounded", STRIDE)
	var bounded_ink: String = str(bounded.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	check(stroke(bounded, bounded_ink).ok and bulk_source.ok,
		"bounded import has resident native source and 129 raster IDs")
	var bounded_store: Object = bounded._native_raster_store
	var bounded_revision: int = bounded.revision
	var bounded_bytes: PackedByteArray = native_bytes(bounded_store, bounded_ink)
	var oversized: DrawingResult = bounded.import_subtree(bulk_source.value, "root", true)
	check(not oversized.ok and oversized.code == "NATIVE_STRUCTURE",
		"over-limit native structural bridge rejects entire subtree")
	check(not bounded.has_node(bulk_group) and
		bounded.revision == bounded_revision and
		int(bounded_store.call("stats").get("revision", -1)) == bounded_revision and
		native_bytes(bounded_store, bounded_ink) == bounded_bytes,
		"over-limit rejection leaves both documents' sources unchanged")

	# Native-absent documents keep their former structural import semantics.
	var ordinary: DrawingDocument = DrawingDocument.new("ordinary", STRIDE)
	check(ordinary._native_raster_store == null, "plain document has no native store")
	var plain: DrawingResult = ordinary.import_subtree(source.value, "root", true)
	check(plain.ok and ordinary.has_node(child) and
		ordinary._nodes[child].tiles["0,0"].to_rgba8() == image.to_rgba8(),
		"native-absent import retains source bytes")

	print("T169_IMPORT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T169_IMPORT_PASSED")
	quit(0 if failures == 0 else 1)
