extends SceneTree
## T-148: live native Brush history through Object Editor drafts, immutable
## source publication, instance rebinding and portable Object Save/Open.

const STRIDE: int = 64
const INK: int = 0xff3467ab
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_OBJECT_NATIVE_FAILED: " + description)


func erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in directory.get_directories():
		erase_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


func packed(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var source: DrawingResult = document.request_chunk(layer, key)
	if not source.ok or source.value == null:
		return PackedByteArray()
	return (source.value as DrawingRasterTile).to_rgba8()


func stroke(document: DrawingDocument, layer: String, point: Vector2) -> DrawingResult:
	var begun: DrawingResult = document.begin_edit(layer, document.revision)
	if not begun.ok:
		return begun
	var edit: DrawingEditSession = begun.value
	var native: Object = ClassDB.instantiate("DrawingNativeBrush")
	var started: DrawingResult = edit.begin_native_stroke(native,
		"NativeHard", "", 8.0, INK, CLIP, true)
	if not started.ok:
		edit.cancel()
		return started
	var sampled: DrawingResult = edit.paint_path_native(
		PackedVector2Array([point, point + Vector2(8.0, 0.0)]), INK, false, null)
	if not sampled.ok:
		edit.cancel()
		return sampled
	return edit.commit()


func context(instance_id: String, asset_id: String) -> DrawingHistoryContext:
	var value: DrawingHistoryContext = DrawingHistoryContext.new()
	value.map_id = "world"
	value.floor_group_id = "ground"
	value.detail_group_id = "D0"
	value.selected_instance_id = instance_id
	value.asset_id = asset_id
	value.editor_mode = "ObjectSelection"
	return value


func visible(library: AtlasObjectLibrary, instance_id: String, point: Vector2i) -> int:
	var rendered: DrawingResult = library.render_instance(instance_id,
		Rect2i(point, Vector2i.ONE))
	if not rendered.ok or rendered.value.get("status") != "linked":
		return -1
	return (rendered.value["image"] as Image).get_data().decode_u32(0)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "compiled Rust extension is registered")
	var directory: String = ProjectSettings.globalize_path("user://t148-object-native-" +
		DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(directory.path_join("Campaign.scn"))
	var original: DrawingDocument = DrawingDocument.new("Native Object", STRIDE)
	var original_layer: String = String(original.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var hidden: PackedByteArray = PackedByteArray()
	hidden.resize(STRIDE * STRIDE * 4)
	hidden.encode_u32(0, 0x00123456)
	original._nodes[original_layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, hidden)
	var created: DrawingResult = library.create_asset(original, "Stone")
	check(created.ok, "Object library publishes baseline Drawing source")
	if not created.ok:
		quit(1)
		return
	var asset_id: String = String(created.value)
	var placed_a: DrawingResult = library.place(asset_id, "world", "ground", "D0")
	var placed_b: DrawingResult = library.place(asset_id, "world", "ground", "D0",
		Transform2D(1.0, Vector2(100, 100)))
	check(placed_a.ok and placed_b.ok, "two placements share immutable source")
	if not placed_a.ok or not placed_b.ok:
		quit(1)
		return
	var a: String = String(placed_a.value)
	var b: String = String(placed_b.value)
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var state: Dictionary = {"context": context(a, asset_id)}
	var bridge: AtlasObjectEditorBridge = AtlasObjectEditorBridge.new(library, history,
		func() -> DrawingHistoryContext: return state["context"])
	var opened: DrawingResult = bridge.open_from_instance(a)
	check(opened.ok, "Object Editor opens independent private source draft")
	if not opened.ok:
		quit(1)
		return
	var tab: DrawingObjectEditorSession = opened.value
	var layer: String = String(tab.document.list_children()[0])
	check(packed(tab.document, layer, "-1,0") == hidden and not tab.document.external_history,
		"Object draft preserves signed hidden RGB and owns local timeline")
	var first: DrawingResult = stroke(tab.document, layer, Vector2(-20.5, 10.5))
	check(first.ok and first.delta.native_history_token > 0,
		"actual native Brush commits tile history inside Object draft")
	if not first.ok:
		quit(1)
		return
	var left: PackedByteArray = packed(tab.document, layer, "-1,0")
	check(left != hidden and tab.document._native_raster_store != null,
		"canonical Rust tile differs from transparent source")
	var store: Object = tab.document._native_raster_store
	check(int(store.call("stats").get("undo", -1)) == 1,
		"native Object brush history retained by draft document")
	check(tab.document.undo().ok and packed(tab.document, layer, "-1,0") == hidden,
		"local Object Undo restores exact hidden RGB source")
	check(tab.document.redo().ok and packed(tab.document, layer, "-1,0") == left and
		int(store.call("stats").get("revision", -1)) == tab.document.revision,
		"local Object Redo replays native token with shared revision")
	check(tab.is_dirty() and visible(library, a, Vector2i(-16, 10)) == 0 and
		visible(library, b, Vector2i(-16, 10)) == 0,
		"unpublished native ink remains private to Object draft")
	var saved: DrawingResult = tab.save()
	check(saved.ok and tab.source_revision == 2 and not tab.is_dirty(),
		"Object Save creates immutable revision 2 and resets private savepoint")
	check(visible(library, a, Vector2i(-16, 10)) != 0 and
		visible(library, b, Vector2i(-16, 10)) != 0,
		"both linked placements refresh after native Object Save")
	var published: DrawingResult = library.begin_draft(asset_id)
	check(published.ok and packed(published.value.document, layer, "-1,0") == left,
		"new Object source draft reads exact native-authored tile bytes")
	check(packed(tab.document, layer, "-1,0") == left and
		tab.document._native_raster_store == null,
		"published Object snapshot is detached from old native history")
	var second: DrawingResult = stroke(tab.document, layer, Vector2(12.5, 20.5))
	check(second.ok and second.delta.native_history_token > 0,
		"fresh native Brush stroke reauthorizes the saved Object draft")
	if not second.ok:
		quit(1)
		return
	var right: PackedByteArray = packed(tab.document, layer, "0,0")
	check(not right.is_empty() and visible(library, a, Vector2i(16, 20)) == 0,
		"second native stroke remains private until Save As")
	tab.variant_name = "Stone with highlight"
	var variant: DrawingResult = tab.save_as()
	check(variant.ok and tab.source_id != asset_id and tab.origin_instance_id.is_empty(),
		"Object Save As creates independent variant and releases captured origin")
	if not variant.ok:
		quit(1)
		return
	var variant_id: String = tab.source_id
	check(library.instance_info(a)["source_id"] == variant_id and
		library.instance_info(b)["source_id"] == asset_id,
		"Save As retargets only selected instance")
	check(visible(library, a, Vector2i(16, 20)) != 0 and
		visible(library, b, Vector2i(16, 20)) == 0,
		"variant pixels appear only on retargeted Object instance")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(directory.path_join("Campaign.scn"))
	check(reloaded.load().ok, "Object registry reloads native-authored immutable source versions")
	check(reloaded.asset_info(asset_id)["revision"] == 2 and
		reloaded.asset_info(variant_id)["revision"] == 1,
		"registry retains original and independent variant revisions")
	var reloaded_variant: DrawingResult = reloaded.begin_draft(variant_id)
	var variant_layer: String = String(reloaded_variant.value.document.list_children()[0]) if reloaded_variant.ok else ""
	check(variant_layer != layer, "Save As gives the variant fresh layer identities")
	check(reloaded_variant.ok and packed(reloaded_variant.value.document, variant_layer, "-1,0") == left and
		packed(reloaded_variant.value.document, variant_layer, "0,0") == right,
		"disk-backed variant roundtrips both signed and positive native tiles")
	var reloaded_original: DrawingResult = reloaded.begin_draft(asset_id)
	check(reloaded_original.ok and
		packed(reloaded_original.value.document, layer, "-1,0") == left and
		packed(reloaded_original.value.document, layer, "0,0").is_empty(),
		"original revision never acquires unpublished variant ink")
	var portable_path: String = ProjectSettings.globalize_path("user://t148-native-object-export-" +
		DrawingDocument.new_id() + ".drawing")
	check(not reloaded.export_portable_source(variant_id, portable_path, 2).ok and
		not FileAccess.file_exists(portable_path),
		"stale Object export revision cannot publish source bytes")
	check(reloaded.export_portable_source(variant_id, portable_path, 1).ok,
		"portable Object exporter writes native-authored variant")
	var portable: DrawingResult = DrawingObjectEditorFile.open(portable_path)
	check(portable.ok and portable.value["source_revision"] == 1 and
		portable.value["name"] == "Stone with highlight",
		"portable Object source reloads its immutable metadata")
	if portable.ok:
		var exported_document: DrawingDocument = portable.value["document"]
		check(packed(exported_document, variant_layer, "-1,0") == left and
			packed(exported_document, variant_layer, "0,0") == right,
			"portable Object source retains exact signed native RGBA8")
		var exported_stroke: DrawingResult = stroke(exported_document, variant_layer,
			Vector2(34.5, 40.5))
		check(exported_stroke.ok and exported_stroke.delta.native_history_token > 0 and
			exported_document.undo().ok and
			packed(exported_document, variant_layer, "0,0") == right,
			"portable Object source reauthorizes native painting and Undo")
	DirAccess.remove_absolute(portable_path)
	check(history.undo() and library.instance_info(a)["source_id"] == asset_id,
		"Atlas global Undo reverses the Save As binding, not the source bytes")
	check(history.redo() and library.instance_info(a)["source_id"] == variant_id,
		"Atlas global Redo restores the same immutable variant binding")
	var next: DrawingResult = stroke(reloaded_variant.value.document, variant_layer, Vector2(32.5, 32.5))
	check(next.ok and next.delta.native_history_token > 0,
		"native Brush reauthorizes disk-reloaded Object variant")
	check(reloaded_variant.value.document.undo().ok and
		packed(reloaded_variant.value.document, variant_layer, "0,0") == right,
		"reloaded Object native Undo restores exact published variant tile")
	var draft_stroke: DrawingResult = stroke(tab.document, String(tab.document.list_children()[0]),
		Vector2(32.5, 32.5))
	check(draft_stroke.ok and tab.is_dirty(),
		"Object Editor can keep editing the newly saved native variant")
	var competing: DrawingResult = library.begin_draft(variant_id)
	check(competing.ok and library.save_draft(competing.value).ok,
		"independent publication advances the variant source revision")
	var before_failed_save: PackedByteArray = packed(tab.document,
		String(tab.document.list_children()[0]), "0,0")
	var refused: DrawingResult = tab.save()
	check(not refused.ok and refused.code == "STALE_SOURCE" and tab.is_dirty() and
		packed(tab.document, String(tab.document.list_children()[0]), "0,0") == before_failed_save,
		"rejected stale Object Save keeps private native pixels and history intact")
	check(tab.document.undo().ok and tab.document.redo().ok and
		packed(tab.document, String(tab.document.list_children()[0]), "0,0") == before_failed_save,
		"failed publication retains reversible native Object draft")
	bridge.release(tab)
	erase_tree(directory)
	print("T148_OBJECT_NATIVE_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
