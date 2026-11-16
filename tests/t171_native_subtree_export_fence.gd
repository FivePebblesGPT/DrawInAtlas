extends SceneTree
## T-171: exporting native-owned raster content (including Copy) must not
## accept bytes or a revision that Rust did not authorize.

const STRIDE: int = 64
const HIDDEN: int = 0x00112233
const COLOR: int = 0xff4268ac
var checks: int = 0
var failures: int = 0
var callback_tile: DrawingRasterTile
var callback_old_color: int = 0
var callback_bytes: PackedByteArray
var callback_count: int = 0

func mutate_other_layer(_ref: Variant) -> PackedByteArray:
	callback_count += 1
	callback_tile.set_rgba(48, 48, HIDDEN)
	return callback_bytes

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T171_EXPORT_FAILED: " + label)

func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var edit: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb")
	var begun: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		COLOR, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not begun.ok:
		edit.cancel()
		return begun
	var path: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(8, 8), Vector2(20, 8)]), COLOR, false, null)
	if not path.ok:
		edit.cancel()
		return path
	return edit.commit()

func native_bytes(store: Object, layer: String) -> PackedByteArray:
	return store.call("read_tile", layer, 0, 0, false).get("bytes", PackedByteArray())

func context(map_id: String, doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var ctx: DrawingHistoryContext = DrawingHistoryContext.new()
	ctx.map_id = map_id
	ctx.floor_group_id = "floor-1"
	ctx.detail_group_id = "D0"
	ctx.document_id = doc.id
	ctx.selected_layer_ids.append(layer)
	return ctx

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "native classes available")
	var source: DrawingDocument = DrawingDocument.new("t171-source", STRIDE)
	var target: DrawingDocument = DrawingDocument.new("t171-target", STRIDE)
	var group: String = str(source.create_layer(DrawingLayerNode.GROUP,
		"Group", "root", "group").value)
	var selected: String = str(source.create_layer(DrawingLayerNode.RASTER,
		"Selected", group, "selected").value)
	var keeper: String = str(source.create_layer(DrawingLayerNode.RASTER,
		"Keeper", "root", "keeper").value)
	check(source.set_external_history(true).ok and target.set_external_history(true).ok,
		"Atlas-owned histories configured")
	check(paint(source, selected).ok and paint(source, keeper).ok,
		"paint selected and unrelated native raster")
	var store: Object = source._native_raster_store
	if store == null:
		check(false, "real native store retained")
		quit(1)
		return
	var start_rev: int = source.revision
	var target_rev: int = target.revision
	var start_undo: int = int(store.call("stats").get("undo", -1))
	var before: PackedByteArray = native_bytes(store, selected)
	var unrelated: PackedByteArray = native_bytes(store, keeper)
	var target_children: Array[String] = target.list_children("root")
	check(before.size() == STRIDE * STRIDE * 4 and start_undo > 0,
		"native has canonical bytes and history")
	var snapshot: DrawingResult = source.export_subtree(group)
	check(snapshot.ok and snapshot.revision == start_rev,
		"valid native subtree export")
	check(snapshot.ok and (snapshot.value as Dictionary).has("nodes") and
		(snapshot.value["nodes"][selected] as DrawingLayerNode).tiles["0,0"].to_rgba8() == before,
		"detached source bytes match Rust exactly")
	var tile: DrawingRasterTile = source._nodes[selected].tiles["0,0"]
	var previous: int = tile.get_rgba(48, 48)
	check(tile.set_rgba(48, 48, HIDDEN), "inject unauthorized alpha-zero RGB mutation")
	var tampered: DrawingResult = source.export_subtree(group)
	check(not tampered.ok and tampered.code == "STALE_SOURCE",
		"reject mutated native-owned bytes from direct export")
	var static_copy: DrawingResult = DrawingDocument.transfer_subtree(source, target, group,
		"root", start_rev, target_rev, false)
	check(not static_copy.ok and static_copy.code == "STALE_SOURCE",
		"static Copy rejects unauthorized source projection")
	check(target.revision == target_rev and target.list_children("root") == target_children,
		"rejected Copy leaves destination entirely unchanged")
	var atlas: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, target, group,
		"root", true, context("world", source, selected),
		context("greyhaven", target, selected))
	var timeline: AtlasEditHistory = AtlasEditHistory.new(AtlasCampaign.sample())
	timeline.active_map_id = "world"
	check(not timeline.execute_drawing_transfer(atlas),
		"Atlas Copy cannot prepare and publish unauthorized snapshot")
	check(target.revision == target_rev and target.list_children("root") == target_children,
		"Atlas Copy rejection leaves destination unchanged")
	check(source.revision == start_rev and native_bytes(store, selected) == before and
		native_bytes(store, keeper) == unrelated and
		int(store.call("stats").get("undo", -1)) == start_undo,
		"all rejected exports preserve native bytes, history and revision")
	check(tile.set_rgba(48, 48, previous), "restore byte-exact source")
	check(source.export_subtree(group).ok, "restored source can export again")
	var copied: DrawingResult = DrawingDocument.transfer_subtree(source, target, group,
		"root", start_rev, target_rev, false)
	check(copied.ok and source.has_node(group) and target.has_node(str(copied.value)),
		"valid static copy preserves source and imports destination")
	var copied_id: String = str(copied.value)
	var copied_root: DrawingLayerNode = target.inspect_node(copied_id)
	check(copied_root != null and copied_root.children.size() == 1,
		"copied subtree contains selected raster")
	if copied_root != null and copied_root.children.size() == 1:
		var copied_layer: DrawingLayerNode = target.inspect_node(copied_root.children[0])
		check(copied_layer != null and copied_layer.tiles["0,0"].to_rgba8() == before,
			"copied raster is byte-for-byte canonical")
	check(source.revision == start_rev and native_bytes(store, keeper) == unrelated and
		int(store.call("stats").get("undo", -1)) == start_undo,
		"successful Copy does not retire or rewrite source native history")
	# A valid lazy fetch can reenter and mutate *another* native-owned tile.
	# The provider's own reference and SHA remain valid, so the loader guard
	# alone cannot catch this; export must check the selected tree afterward.
	var lazy_doc: DrawingDocument = DrawingDocument.new("reentrant", STRIDE)
	var lazy_group: String = str(lazy_doc.create_layer(DrawingLayerNode.GROUP,
		"Group", "root", "reentrant-group").value)
	var lazy_native: String = str(lazy_doc.create_layer(DrawingLayerNode.RASTER,
		"Native", lazy_group, "reentrant-native").value)
	check(paint(lazy_doc, lazy_native).ok, "paint reentrant test source")
	var lazy_raster: String = str(lazy_doc.create_layer(DrawingLayerNode.RASTER,
		"Deferred", lazy_group, "deferred").value)
	var lazy_store: Object = lazy_doc._native_raster_store
	var lazy_native_bytes: PackedByteArray = native_bytes(lazy_store, lazy_native)
	var lazy_rev: int = lazy_doc.revision
	var lazy_undo: int = int(lazy_store.call("stats").get("undo", -1))
	callback_tile = lazy_doc._nodes[lazy_native].tiles["0,0"]
	callback_old_color = callback_tile.get_rgba(48, 48)
	callback_bytes = PackedByteArray()
	callback_bytes.resize(STRIDE * STRIDE * 4)
	callback_bytes.fill(0)
	callback_count = 0
	var checksum: String = DrawingRasterTile.digest_rgba8(callback_bytes, STRIDE)
	check(lazy_doc.register_lazy_chunk(lazy_raster, 0, 0,
		"deferred-ref", checksum, Callable(self, "mutate_other_layer")).ok,
		"register deferred source without changing native revision")
	var lazy_export: DrawingResult = lazy_doc.export_subtree(lazy_group)
	check(callback_count == 1, "export resolves deferred source exactly once")
	check(not lazy_export.ok and lazy_export.code == "STALE_SOURCE",
		"post-loader native byte fence rejects unrelated resident tampering")
	check(lazy_doc.revision == lazy_rev and native_bytes(lazy_store, lazy_native) == lazy_native_bytes and
		int(lazy_store.call("stats").get("undo", -1)) == lazy_undo,
		"reentrant export rejection preserves Rust source and tokens")
	check(callback_tile.set_rgba(48, 48, callback_old_color),
		"restore exact native projection after callback")
	check(lazy_doc.export_subtree(lazy_group).ok,
		"fixed reentrant source can export without fetching same chunk again")

	# A live attached native store can independently advance and cause a
	# revision mismatch even though the Godot tree's bytes remain identical.
	var stale: DrawingDocument = DrawingDocument.new("stale", STRIDE)
	var stale_layer: String = str(stale.create_layer(DrawingLayerNode.RASTER,
		"Stale", "root", "stale-layer").value)
	check(paint(stale, stale_layer).ok, "create separate native revision test store")
	var stale_store: Object = stale._native_raster_store
	var stale_revision: int = stale.revision
	var stale_rgba: PackedByteArray = native_bytes(stale_store, stale_layer)
	check(bool(stale_store.call("advance_metadata_revision", stale_revision, false)),
		"advance Rust revision without changing Godot document")
	var wrong_revision: DrawingResult = stale.export_subtree(stale_layer)
	check(not wrong_revision.ok and wrong_revision.code == "STALE_REVISION",
		"reject direct export from divergent attached native revision")
	var stale_target: DrawingDocument = DrawingDocument.new("stale-target", STRIDE)
	var refused_copy: DrawingResult = DrawingDocument.transfer_subtree(stale, stale_target,
		stale_layer, "root", stale_revision, stale_target.revision, false)
	check(not refused_copy.ok and refused_copy.code == "STALE_REVISION",
		"reject copying divergent native revision")
	check(stale_target.list_children("root").is_empty() and
		stale_target.revision == 0 and stale.revision == stale_revision and
		native_bytes(stale_store, stale_layer) == stale_rgba,
		"revision-rejected copies leave both documents and canonical bytes intact")
	# Native-absent copies are still supported until T-150.
	var plain: DrawingDocument = DrawingDocument.new("plain", STRIDE)
	var plain_layer: String = str(plain.create_layer(DrawingLayerNode.RASTER,
		"Plain", "root", "plain-layer").value)
	var plain_target: DrawingDocument = DrawingDocument.new("plain-target", STRIDE)
	check(plain._native_raster_store == null and plain.export_subtree(plain_layer).ok,
		"native-absent detached source remains exportable")
	check(DrawingDocument.transfer_subtree(plain, plain_target, plain_layer,
		"root", plain.revision, plain_target.revision, false).ok,
		"native-absent Copy keeps the historical path")
	print("T171_EXPORT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T171_EXPORT_PASSED")
	quit(0 if failures == 0 else 1)
