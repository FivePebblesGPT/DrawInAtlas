extends SceneTree
## T-170: an Atlas/native move must not publish a destination when Rust
## refuses to retire its source. Both transfer APIs share the same gate.

const STRIDE: int = 64
const HIDDEN: int = 0x00112233
const COLOR: int = 0xff4268ac
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T170_TRANSFER_FAILED: " + label)


func stroke(doc: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var edit: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var began: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		COLOR, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not began.ok:
		edit.cancel()
		return began
	var painted: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(9, 8), Vector2(19, 8)]), COLOR, false, null)
	if not painted.ok:
		edit.cancel()
		return painted
	return edit.commit()


func context(map_id: String, doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = map_id
	result.floor_group_id = "floor-1"
	result.detail_group_id = "D0"
	result.document_id = doc.id
	result.selected_layer_ids.append(layer)
	return result


func bytes(store: Object, layer: String) -> PackedByteArray:
	return store.call("read_tile", layer, 0, 0, false).get("bytes", PackedByteArray())


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required Hokusai/Rust native classes loaded")
	var source: DrawingDocument = DrawingDocument.new("transfer-source", STRIDE)
	var dest: DrawingDocument = DrawingDocument.new("transfer-dest", STRIDE)
	var group: String = str(source.create_layer(DrawingLayerNode.GROUP, "Group", "root", "group").value)
	var moving: String = str(source.create_layer(DrawingLayerNode.RASTER, "Moving", group, "moving").value)
	var keeper: String = str(source.create_layer(DrawingLayerNode.RASTER, "Keeper", "root", "keeper").value)
	var dest_ink: String = str(dest.create_layer(DrawingLayerNode.RASTER, "Destination", "root", "dest-ink").value)
	check(source.set_external_history(true).ok and dest.set_external_history(true).ok,
		"both documents use Atlas-owned history")
	check(stroke(source, moving).ok and stroke(source, keeper).ok and
		stroke(dest, dest_ink).ok, "independent native Brush sources and histories")
	var from_native: Object = source._native_raster_store
	var to_native: Object = dest._native_raster_store
	if from_native == null or to_native == null:
		quit(1)
		return
	var from_before: int = source.revision
	var to_before: int = dest.revision
	var moving_bytes: PackedByteArray = bytes(from_native, moving)
	var keeper_bytes: PackedByteArray = bytes(from_native, keeper)
	var dest_bytes: PackedByteArray = bytes(to_native, dest_ink)
	var keeper_token_count: int = int(from_native.call("stats").get("undo", -1))
	var dest_token_count: int = int(to_native.call("stats").get("undo", -1))
	var from_children: Array[String] = source.list_children("root")
	var to_children: Array[String] = dest.list_children("root")
	var held: Dictionary = from_native.call("begin_edit", keeper, from_before, false)
	check(bool(held.get("ok", false)), "hold active native source transaction")
	check(not source.preflight_unrecorded_subtree_removal(group).ok,
		"read-only Rust retirement gate refuses active source transaction")
	var refused: DrawingResult = DrawingDocument.transfer_subtree(source, dest, group,
		"root", from_before, to_before, true)
	check(not refused.ok and refused.code == "NATIVE_STRUCTURE",
		"static move rejects busy source before destination import")
	check(source.has_node(group) and source.has_node(moving) and
		source.list_children("root") == from_children and dest.list_children("root") == to_children and
		source.revision == from_before and dest.revision == to_before,
		"rejected static move leaves both trees and revisions unchanged")
	check(bytes(from_native, moving) == moving_bytes and
		bytes(from_native, keeper) == keeper_bytes and bytes(to_native, dest_ink) == dest_bytes and
		int(from_native.call("stats").get("undo", -1)) == keeper_token_count and
		int(to_native.call("stats").get("undo", -1)) == dest_token_count,
		"rejected move preserves source and destination native bytes/history")

	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var before: DrawingHistoryContext = context("world", source, moving)
	var after: DrawingHistoryContext = context("greyhaven", dest, moving)
	var atlas_move: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, dest, group,
		"root", false, before, after)
	check(not timeline.execute_drawing_transfer(atlas_move),
		"Atlas move also rejects busy source before target mutation")
	check(source.revision == from_before and dest.revision == to_before and
		source.list_children("root") == from_children and dest.list_children("root") == to_children,
		"rejected Atlas command preserves both revisions and tree layouts")
	check(from_native.call("discard_edit", int(held.get("transaction", 0))),
		"discard held Rust edit for retry")

	# In-place alpha-zero RGB tampering is not validated by mere node identity.
	var tile: DrawingRasterTile = source._nodes[moving].tiles["0,0"]
	var old_color: int = tile.get_rgba(48, 48)
	check(tile.set_rgba(48, 48, HIDDEN), "modify hidden RGB in source projection")
	var corrupted: DrawingResult = DrawingDocument.transfer_subtree(source, dest, group,
		"root", from_before, to_before, true)
	check(not corrupted.ok and corrupted.code == "STALE_SOURCE",
		"source-byte tampering rejects move before importing destination")
	check(dest.list_children("root") == to_children and dest.revision == to_before and
		bytes(from_native, moving) == moving_bytes,
		"tampered rejection preserves target state and native canonical source")
	check(tile.set_rgba(48, 48, old_color), "restore exact original source bytes")
	check(source.preflight_unrecorded_subtree_removal(group).ok,
		"fixed source passes read-only preflight")

	# The target native owner accepts the copied raster, then the source can
	# retire in the same synchronous move with no lazy-source callbacks.
	check(timeline.execute_drawing_transfer(atlas_move),
		"Atlas move succeeds after discarding transaction and restoring source")
	check(not source.has_node(group) and dest.has_node(group) and dest.has_node(moving) and
		source.revision == from_before + 1 and dest.revision == to_before + 1,
		"successful move changes both trees and revisions exactly once")
	check(int(from_native.call("stats").get("revision", -1)) == source.revision and
		int(to_native.call("stats").get("revision", -1)) == dest.revision and
		bytes(from_native, keeper) == keeper_bytes and bytes(to_native, dest_ink) == dest_bytes,
		"successful move keeps both Rust stores synchronized and unrelated sources intact")
	check(dest.has_node(moving) and
		(dest._nodes[moving] as DrawingLayerNode).tiles["0,0"].to_rgba8() == moving_bytes,
		"target receives byte-identical canonical raster, including hidden RGB")
	check(timeline.undo() and source.has_node(group) and not dest.has_node(group),
		"one Atlas Undo restores source tree and removes destination")
	check(timeline.redo() and not source.has_node(group) and dest.has_node(group),
		"one Atlas Redo restores destination with the same layer ID")
	check(bytes(from_native, keeper) == keeper_bytes and bytes(to_native, dest_ink) == dest_bytes,
		"cross-document Undo/Redo preserves unrelated native bytes")

	# An unrelated source-side busy edit must not block a copy, which does not
	# retire source pixels (tested on a fresh independent source).
	var copy_src: DrawingDocument = DrawingDocument.new("copy", STRIDE)
	var copy_layer: String = str(copy_src.create_layer(DrawingLayerNode.RASTER,
		"Copy", "root", "copy-layer").value)
	check(stroke(copy_src, copy_layer).ok, "native copy source exists")
	var copy_store: Object = copy_src._native_raster_store
	var copy_held: Dictionary = copy_store.call("begin_edit", copy_layer,
		copy_src.revision, false)
	check(bool(copy_held.get("ok", false)), "hold edit on copy-only source")
	var copied: DrawingResult = DrawingDocument.transfer_subtree(copy_src, dest,
		copy_layer, "root", copy_src.revision, dest.revision, false)
	check(copied.ok and copy_src.has_node(copy_layer) and dest.has_node(str(copied.value)),
		"copy leaves source untouched even while source Rust transaction is active")
	check(copy_store.call("discard_edit", int(copy_held.get("transaction", 0))),
		"discard copy transaction")
	var static_target: DrawingDocument = DrawingDocument.new("static-target", STRIDE)
	var static_revision: int = copy_src.revision
	var static_bytes: PackedByteArray = bytes(copy_store, copy_layer)
	var static_moved: DrawingResult = DrawingDocument.transfer_subtree(copy_src,
		static_target, copy_layer, "root", static_revision, static_target.revision, true)
	check(static_moved.ok and not copy_src.has_node(copy_layer) and
		static_target.has_node(copy_layer), "static move retires source and preserves stable layer ID")
	check(static_target.has_node(copy_layer) and
		(static_target._nodes[copy_layer] as DrawingLayerNode).tiles["0,0"].to_rgba8() == static_bytes,
		"static move retains full canonical source RGBA8")
	check(int(copy_store.call("stats").get("revision", -1)) == copy_src.revision and
		copy_src.revision == static_revision + 1,
		"static move advances source and native store together")

	print("T170_TRANSFER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T170_TRANSFER_PASSED")
	quit(0 if failures == 0 else 1)
