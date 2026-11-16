extends SceneTree
## T-172: Atlas Undo must preflight destination-native retirement before
## restoring a moved source subtree; refusal cannot partially replay history.

const STRIDE: int = 64
const INK: int = 0xff4278af
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T172_UNDO_FAILED: " + label)


func stroke(document: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = document.begin_edit(layer, document.revision)
	if not started.ok:
		return started
	var edit: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var begun: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		INK, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not begun.ok:
		edit.cancel()
		return begun
	var painted: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(8, 8), Vector2(20, 8)]), INK, false, null)
	if not painted.ok:
		edit.cancel()
		return painted
	return edit.commit()


func context(map: String, doc: DrawingDocument, selected: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = map
	result.floor_group_id = "floor-1"
	result.detail_group_id = "D0"
	result.document_id = doc.id
	result.selected_layer_ids.append(selected)
	return result


func native_bytes(store: Object, layer: String) -> PackedByteArray:
	return store.call("read_tile", layer, 0, 0, false).get("bytes", PackedByteArray())


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "actual Rust native classes available")
	var source: DrawingDocument = DrawingDocument.new("undo-source", STRIDE)
	var dest: DrawingDocument = DrawingDocument.new("undo-target", STRIDE)
	var group: String = str(source.create_layer(DrawingLayerNode.GROUP,
		"Moving group", "root", "moving-group").value)
	var moving: String = str(source.create_layer(DrawingLayerNode.RASTER,
		"Moved", group, "moved").value)
	var keeper: String = str(source.create_layer(DrawingLayerNode.RASTER,
		"Retained", "root", "keeper").value)
	var dest_ink: String = str(dest.create_layer(DrawingLayerNode.RASTER,
		"Target resident", "root", "dest-ink").value)
	check(source.set_external_history(true).ok and dest.set_external_history(true).ok,
		"one Atlas timeline owns both documents")
	check(stroke(source, moving).ok and stroke(source, keeper).ok and
		stroke(dest, dest_ink).ok, "Hokusai sources and native history resident")
	var source_store: Object = source._native_raster_store
	var dest_store: Object = dest._native_raster_store
	if source_store == null or dest_store == null:
		printerr("T172_UNDO_FAILED: native stores missing")
		quit(1)
		return
	var original_moving: PackedByteArray = native_bytes(source_store, moving)
	var original_keeper: PackedByteArray = native_bytes(source_store, keeper)
	var original_dest: PackedByteArray = native_bytes(dest_store, dest_ink)
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var transfer: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, dest,
		group, "root", false, context("world", source, moving),
		context("greyhaven", dest, moving))
	check(history.execute_drawing_transfer(transfer) and
		transfer.target_node_id == group and not source.has_node(group) and
		dest.has_node(group), "Atlas move applies with stable group identity")
	check(int(source_store.call("stats").get("revision", -1)) == source.revision and
		int(dest_store.call("stats").get("revision", -1)) == dest.revision,
		"native revisions match both documents after move")
	var src_rev: int = source.revision
	var dst_rev: int = dest.revision
	var src_children: Array[String] = source.list_children("root")
	var dst_children: Array[String] = dest.list_children("root")
	var src_undo: int = int(source_store.call("stats").get("undo", -1))
	var dst_undo: int = int(dest_store.call("stats").get("undo", -1))
	var held: Dictionary = dest_store.call("begin_edit", dest_ink, dst_rev, false)
	check(bool(held.get("ok", false)), "target Rust store holds a live transaction")
	check(not dest.preflight_unrecorded_subtree_removal(group).ok,
		"read-only retirement gate refuses busy target")
	check(not history.undo(), "Atlas Undo refuses busy destination")
	check(not source.has_node(group) and dest.has_node(group) and
		source.list_children("root") == src_children and
		dest.list_children("root") == dst_children,
		"refused Undo cannot restore source or delete target nodes")
	check(source.revision == src_rev and dest.revision == dst_rev,
		"refused Undo cannot advance either document revision")
	check(int(source_store.call("stats").get("revision", -1)) == src_rev and
		int(dest_store.call("stats").get("revision", -1)) == dst_rev and
		int(source_store.call("stats").get("undo", -1)) == src_undo and
		int(dest_store.call("stats").get("undo", -1)) == dst_undo,
		"refused Undo keeps both Rust timelines and revisions unchanged")
	check(native_bytes(source_store, keeper) == original_keeper and
		native_bytes(dest_store, dest_ink) == original_dest,
		"refused Undo keeps unrelated native RGBA8 exact")
	check(transfer._applied and history.can_undo(),
		"rejected Undo retains applied command and Atlas cursor")
	check(dest_store.call("discard_edit", int(held.get("transaction", 0))),
		"discard busy target transaction")
	check(history.undo() and source.has_node(group) and not dest.has_node(group),
		"Atlas Undo succeeds when native retirement becomes eligible")
	check(history.redo() and not source.has_node(group) and dest.has_node(group),
		"Atlas Redo reuses the same transferred identity")
	check(native_bytes(source_store, keeper) == original_keeper and
		native_bytes(dest_store, dest_ink) == original_dest and
		(dest._nodes[moving] as DrawingLayerNode).tiles["0,0"].to_rgba8() == original_moving,
		"successful replay preserves resident and moved hidden RGBA8")

	# A copied subtree also lives in the target timeline: Undo must not remove
	# it when Rust has an active unrelated transaction. Source stays untouched.
	var copy_src: DrawingDocument = DrawingDocument.new("undo-copy-source", STRIDE)
	var copy_layer: String = str(copy_src.create_layer(DrawingLayerNode.RASTER,
		"Copy", "root", "copy-layer").value)
	check(copy_src.set_external_history(true).ok and stroke(copy_src, copy_layer).ok,
		"prepare independent native copy source")
	var copy: AtlasDrawingTransfer = AtlasDrawingTransfer.new(copy_src, dest,
		copy_layer, "root", true, context("world", copy_src, copy_layer),
		context("greyhaven", dest, copy_layer))
	check(history.execute_drawing_transfer(copy) and copy_src.has_node(copy_layer),
		"Atlas Copy appends another global command")
	var copy_dst_rev: int = dest.revision
	var copy_src_rev: int = copy_src.revision
	var copy_dst_children: Array[String] = dest.list_children("root")
	var copy_busy: Dictionary = dest_store.call("begin_edit", dest_ink,
		copy_dst_rev, false)
	check(bool(copy_busy.get("ok", false)), "hold target transaction during Copy Undo")
	check(not history.undo(), "Atlas Copy Undo rejects busy target")
	check(dest.revision == copy_dst_rev and copy_src.revision == copy_src_rev and
		dest.list_children("root") == copy_dst_children and
		copy_src.has_node(copy_layer),
		"rejected Copy Undo preserves both documents and copied subtree")
	check(dest_store.call("discard_edit", int(copy_busy.get("transaction", 0))),
		"discard Copy Undo held edit")
	check(history.undo() and not dest.has_node(copy.target_node_id) and
		copy_src.has_node(copy_layer), "Copy Undo succeeds after target is free")
	check(history.redo() and dest.has_node(copy.target_node_id) and
		copy_src.has_node(copy_layer), "Copy Redo restores target without source retirement")

	# Test an attached-native-ahead rejection on the move's Undo, separately
	# from the busy-transaction path. Deliberately leave it divergent: this
	# test must never silently rebase Rust to make host history advance.
	check(history.undo() and not dest.has_node(copy.target_node_id),
		"remove Copy step so moving command is next to undo")
	var ahead_from_revision: int = source.revision
	var ahead_to_revision: int = dest.revision
	var ahead_children: Array[String] = dest.list_children("root")
	check(bool(dest_store.call("advance_metadata_revision", ahead_to_revision, true)),
		"inject native-ahead target revision without changing Godot")
	check(not history.undo(), "Atlas Move Undo refuses native-ahead destination")
	check(source.revision == ahead_from_revision and dest.revision == ahead_to_revision and
		not source.has_node(group) and dest.has_node(group) and
		dest.list_children("root") == ahead_children,
		"native-ahead rejection preserves source and destination documents")
	check(transfer._applied and history.can_undo() and
		int(dest_store.call("stats").get("revision", -1)) == ahead_to_revision + 1,
		"rejected Undo preserves command cursor and divergent Rust authority")

	print("T172_UNDO_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T172_UNDO_PASSED")
	quit(0 if failures == 0 else 1)
