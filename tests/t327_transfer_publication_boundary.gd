extends "res://tests/t325_transfer_redo_ownership.gd"
## Host transfer failures must not publish one document before the other refuses.

class RejectLiveExportDocument extends DrawingDocument:
	var export_attempts: int = 0
	func export_subtree(_node_id: String) -> DrawingResult:
		export_attempts += 1
		return DrawingResult.failure("INJECTED", "Live export cannot run after publication")

const MAX_REVISION: int = 9223372036854775807
var callback_target: DrawingDocument
var callback_bytes: PackedByteArray
var callback_count: int = 0

func owner() -> AtlasEditHistory:
	var timeline: AtlasEditHistory = AtlasEditHistory.new(AtlasCampaign.sample())
	timeline.active_map_id = "world"
	return timeline

func transfer(source: DrawingDocument, target: DrawingDocument, layer: String, copied: bool) -> AtlasDrawingTransfer:
	return AtlasDrawingTransfer.new(source, target, layer, "root", copied, context(source, layer), context(target, layer))

func copy_inaccessible(hidden: bool) -> void:
	var timeline: AtlasEditHistory = owner()
	var source: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	var target: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	check(source.create_layer(DrawingLayerNode.RASTER, "Source", "root", "ink").ok, "copy source")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "copy owners")
	check(paint(source, timeline, "ink", -1) > 0, "paint copy source")
	check((source.set_visibility("ink", false) if hidden else source.set_locked("ink", true)).ok, "protect source")
	# Metadata changes in this fixture are outside the timeline; start a fresh owner.
	timeline.reset(AtlasCampaign.sample())
	var command: AtlasDrawingTransfer = transfer(source, target, "ink", true)
	check(timeline.execute_drawing_transfer(command), "copy protected source")
	if not command._applied:
		return
	var dest: String = command.target_node_id
	var before: int = target.revision
	check(not target.remove_subtree(dest).ok and target.revision == before, "ordinary removal still respects protection")
	check(timeline.undo() and not target.has_node(dest) and source.has_node("ink"), "verified Copy Undo removes protected imported root")
	check(timeline.redo() and target.has_node(dest), "Copy Redo restores protected root")
	if target.has_node(dest):
		var node: DrawingLayerNode = target.inspect_node(dest)
		check(node.visible == not hidden and node.locked == not hidden and node.tiles["-1,0"].get_rgba(63, 1) == INK,
			"Copy replay preserves properties and exact hidden RGB")

func ordered_move() -> void:
	var timeline: AtlasEditHistory = owner()
	var source: DrawingDocument = DrawingDocument.new("ordered-source", 64)
	var target: DrawingDocument = DrawingDocument.new("ordered-target", 64)
	check(source.create_layer(DrawingLayerNode.RASTER, "Moving", "root", "moving").ok and
		source.create_layer(DrawingLayerNode.GROUP, "After", "root", "after").ok, "ordered source")
	check(target.create_layer(DrawingLayerNode.GROUP, "Destination", "root", "dest").ok, "different parent identity")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "ordered owners")
	var token: int = paint(source, timeline, "moving", -1)
	var command: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, target, "moving", "dest", false, context(source, "moving"), context(target, "moving"))
	check(timeline.execute_drawing_transfer(command) and target.list_children("dest") == ["moving"], "ordered Move")
	var before: int = source.revision
	check(timeline.undo(), "ordered Undo")
	check(source.list_children("root") == ["moving", "after"] and source.revision == before + 1,
		"restore original sibling order in one revision")
	check(retained(source, token) and timeline.undo() and timeline.redo() and timeline.redo(), "retained source paint replay")

func exhausted_semantic_source() -> void:
	var timeline: AtlasEditHistory = owner()
	var source: DrawingDocument = DrawingDocument.new("ceiling-source", 64)
	var target: DrawingDocument = DrawingDocument.new("ceiling-target", 64)
	check(source.create_layer(DrawingLayerNode.GROUP, "Semantic", "root", "group").ok, "semantic source")
	source.revision = MAX_REVISION
	source._native_raster_store = ClassDB.instantiate("DrawingNativeTiles")
	check(bool(source._native_raster_store.call("configure", 64, MAX_REVISION)), "source revision ceiling")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "ceiling owners")
	var command: AtlasDrawingTransfer = transfer(source, target, "group", false)
	var target_rev: int = target.revision
	check(not timeline.execute_drawing_transfer(command), "exhausted source refuses Move")
	check(source.revision == MAX_REVISION and target.revision == target_rev and source.has_node("group") and
		target.layer_count() == 0 and not target.is_dirty() and not timeline.can_undo(), "no compensating destination publication")

func lazy_target_change(_ref: Variant) -> PackedByteArray:
	callback_count += 1
	callback_target.create_layer(DrawingLayerNode.GROUP, "Changed by loader", "root", "callback")
	return callback_bytes

func late_source_and_callback() -> void:
	var timeline: AtlasEditHistory = owner()
	var source: DrawingDocument = DrawingDocument.new("lazy-source", 64)
	var target: DrawingDocument = DrawingDocument.new("lazy-target", 64)
	check(source.create_layer(DrawingLayerNode.RASTER, "Source", "root", "ink").ok, "lazy source")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "lazy owners")
	callback_target = target
	callback_bytes.resize(64 * 64 * 4)
	callback_bytes.fill(0)
	callback_bytes[0] = 19
	var digest: String = DrawingRasterTile.digest_rgba8(callback_bytes, 64)
	check(source.register_lazy_chunk("ink", -1, 0, "lazy", digest, Callable(self, "lazy_target_change")).ok, "lazy chunk")
	var command: AtlasDrawingTransfer = transfer(source, target, "ink", false)
	check(callback_count == 1 and target.has_node("callback"), "provider changes target during snapshot")
	var rev_s: int = source.revision
	var rev_t: int = target.revision
	check(not timeline.execute_drawing_transfer(command) and source.revision == rev_s and target.revision == rev_t and
		source.has_node("ink") and not target.has_node("ink"), "reject target change during capture")
	if not source.has_node("ink"):
		return
	command = transfer(source, target, "ink", false)
	check(source.register_lazy_chunk("ink", -2, 0, "late", digest, Callable(self, "lazy_target_change")).ok, "late unresolved source without revision")
	check(not timeline.execute_drawing_transfer(command) and source.has_node("ink") and source.revision == rev_s and
		target.revision == rev_t and callback_count == 1, "late source cannot be silently dropped or fetched during publication")

func ceiling_ordered_undo() -> void:
	var timeline: AtlasEditHistory = owner()
	var source: DrawingDocument = DrawingDocument.new("ceiling-ordered-source", 64)
	var target: DrawingDocument = DrawingDocument.new("ceiling-ordered-target", 64)
	check(source.create_layer(DrawingLayerNode.GROUP, "First", "root", "first").ok and
		source.create_layer(DrawingLayerNode.GROUP, "Second", "root", "second").ok, "ceiling ordered tree")
	source.revision = MAX_REVISION - 2
	source._native_raster_store = ClassDB.instantiate("DrawingNativeTiles")
	check(bool(source._native_raster_store.call("configure", 64, source.revision)), "native ordered ceiling")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "ceiling ordered owners")
	var command: AtlasDrawingTransfer = transfer(source, target, "first", false)
	check(timeline.execute_drawing_transfer(command) and source.revision == MAX_REVISION - 1, "Move with two remaining revisions")
	check(timeline.undo() and source.revision == MAX_REVISION and source.list_children("root") == ["first", "second"],
		"ordered Undo uses final available revision")
	var target_rev: int = target.revision
	check(not timeline.redo() and source.revision == MAX_REVISION and target.revision == target_rev and
		source.has_node("first") and not target.has_node("first") and timeline.can_redo(), "exhausted replay rejects without branching")

func rejected_outgoing_snapshot() -> void:
	for copied: bool in [true, false]:
		var timeline: AtlasEditHistory = owner()
		var source: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
		var target: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
		check(source.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok and
			source.set_external_history(true).ok and target.set_external_history(true).ok, "snapshot owners")
		var token: int = paint(source, timeline, "ink", -1)
		var command: AtlasDrawingTransfer = transfer(source, target, "ink", copied)
		var expected: DrawingLayerNode = command._snapshot["nodes"]["ink"]
		var rev_s: int = source.revision
		var rev_t: int = target.revision
		check(expected.tiles["-1,0"].set_rgba(63, 1, 0x00fedcba), "corrupt retained source snapshot")
		check(not timeline.execute_drawing_transfer(command) and source.revision == rev_s and target.revision == rev_t and
			target.layer_count() == 0 and retained(source, token), "changed detached source rejects before import")
		check(expected.tiles["-1,0"].set_rgba(63, 1, INK) and timeline.execute_drawing_transfer(command), "retry exact snapshot")
		if not command._applied:
			continue
		var inserted: DrawingLayerNode = command._inserted_snapshot["nodes"][command.target_node_id] if copied else expected
		check(copied or command._inserted_snapshot.is_empty(), "Move retains one snapshot")
		check(inserted.tiles["-1,0"].set_rgba(63, 1, 0x00abcdef), "corrupt inserted snapshot")
		check(int(target.read_pixel(command.target_node_id, -1, 1).value) == INK, "retained snapshot does not alias live projection")
		rev_s = source.revision
		rev_t = target.revision
		check(not timeline.undo() and source.revision == rev_s and target.revision == rev_t and command._applied and
			target.has_node(command.target_node_id) and retained(source, token), "changed imported snapshot rejects Undo before restore")
		check(inserted.tiles["-1,0"].set_rgba(63, 1, INK) and timeline.undo() and timeline.redo(), "retry exact imported snapshot")

func no_post_publication_export() -> void:
	for copied: bool in [true, false]:
		var timeline: AtlasEditHistory = owner()
		var source: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
		var target: RejectLiveExportDocument = RejectLiveExportDocument.new(DrawingDocument.new_id(), 64)
		check(source.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok and
			source.set_external_history(true).ok and target.set_external_history(true).ok, "no export owners")
		check(paint(source, timeline, "ink", -1) > 0, "native source")
		var command: AtlasDrawingTransfer = transfer(source, target, "ink", copied)
		check(timeline.execute_drawing_transfer(command) and target.export_attempts == 0, "no fallible live export after import")
		check(timeline.undo() and timeline.redo() and target.export_attempts == 0 and
			int(target.read_pixel(command.target_node_id, -1, 1).value) == INK, "replay uses retained bytes only")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension present")
	copy_inaccessible(false)
	copy_inaccessible(true)
	ordered_move()
	exhausted_semantic_source()
	ceiling_ordered_undo()
	late_source_and_callback()
	rejected_outgoing_snapshot()
	no_post_publication_export()
	print("T327 checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T327_TRANSFER_PUBLICATION_BOUNDARY_PASSED")
	quit(1 if failures else 0)
