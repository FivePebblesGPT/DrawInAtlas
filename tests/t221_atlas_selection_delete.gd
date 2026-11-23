extends SceneTree
## T-221: the shared clear path remains correct for Atlas's single external
## history and Rust-owned native source, including signed RGBA8/hidden RGB.

const STRIDE: int = 64
const INK: int = 0xff395a8b
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T221_ATLAS_FAILED: " + message)


func context(doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var ctx: DrawingHistoryContext = DrawingHistoryContext.new()
	ctx.map_id = "world"
	ctx.floor_group_id = "ground"
	ctx.detail_group_id = "D1"
	ctx.document_id = doc.id
	ctx.selected_layer_ids.append(layer)
	ctx.editor_mode = "surface_paint"
	ctx.has_focus = true
	return ctx


func tile_bytes(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk(layer, key)
	return (result.value as DrawingRasterTile).to_rgba8() if result.ok and result.value != null else PackedByteArray()


## Recursively remove only the unique user:// generation created by this test.
func remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for subdir: String in directory.get_directories():
		remove_tree(path.path_join(subdir))
	DirAccess.remove_absolute(path)


func run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, STRIDE).ok,
		"real Atlas campaign and D1 detail created")
	var doc: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc.external_history, "Atlas owns chronological history")
	var seed_bytes: PackedByteArray = PackedByteArray()
	seed_bytes.resize(STRIDE * STRIDE * 4)
	seed_bytes.encode_u32(0, 0x00aabbcc)
	doc._nodes[layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, seed_bytes)
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var native: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var begun: DrawingResult = native.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, INK, Rect2i(-64, 0, 128, 64), true)
	check(begun.ok, "Rust-backed Atlas stroke begins")
	if not begun.ok:
		native.cancel()
		quit(1)
		return
	check(native.paint_path_native(PackedVector2Array([
		Vector2(-20.5, 10.5), Vector2(-13.5, 10.5)]), INK, false, null).ok,
		"native Hokusai paints signed tile")
	var initial: DrawingResult = history.commit_drawing(native, context(doc, layer), context(doc, layer))
	check(initial.ok and doc._native_raster_store != null,
		"first native gesture commits through Atlas external history")
	if not initial.ok:
		quit(1)
		return
	var original: PackedByteArray = tile_bytes(doc, layer, "-1,0")
	check(original != seed_bytes and original.decode_u32(0) == 0x00aabbcc,
		"native RGBA8 source has painted pixels and untouched hidden RGB")
	var selected: DrawingSelection = DrawingSelection.new(Rect2i(-64, 0, 128, 64), true)
	check(selected.combine_rectangle(Rect2i(-64, 0, 1, 1), "Subtract"),
		"mask hole protects hidden RGBA8 pixel")
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var cleared: DrawingResult = edit.clear_rect(selected.bounds, selected)
	check(cleared.ok and edit.change_count() > 0,
		"selection clear stages real native-produced pixels")
	if not cleared.ok:
		edit.cancel()
		quit(1)
		return
	var next: DrawingHistoryContext = context(doc, layer)
	next.selection_mask = selected
	var result: DrawingResult = history.commit_drawing(edit, next, next)
	check(result.ok, "content Delete is one Atlas history command")
	if not result.ok:
		print("T221_ATLAS_RESULT checks=%d failed=%d code=%s message=%s" % [
			checks, failures, result.code, result.message])
		quit(1)
		return
	var cleared_bytes: PackedByteArray = tile_bytes(doc, layer, "-1,0")
	check(cleared_bytes != original and cleared_bytes.decode_u32(0) == 0x00aabbcc,
		"Delete clears native source but preserves masked hidden RGB")
	var original_sha256: String = DrawingRasterTile.digest_rgba8(original, STRIDE)
	var cleared_sha256: String = DrawingRasterTile.digest_rgba8(cleared_bytes, STRIDE)
	check(not original_sha256.is_empty() and not cleared_sha256.is_empty() and
		original_sha256 != cleared_sha256, "native RGBA8 digest changes on Delete")
	print("T221_ATLAS_SHA256: before=%s after=%s" % [original_sha256, cleared_sha256])
	check(doc.history_length() == 0 and history.can_undo(),
		"external Atlas timeline has no shadow document Undo")
	check(history.undo() and tile_bytes(doc, layer, "-1,0") == original,
		"Atlas Undo restores native-authored exact tile bytes")
	check(history.redo() and tile_bytes(doc, layer, "-1,0") == cleared_bytes,
		"Atlas Redo replays exact cleared bytes")
	var saved_dir: String = ProjectSettings.globalize_path("user://t221-atlas-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(saved_dir) == OK,
		"create isolated Atlas generation directory")
	var path: String = saved_dir.path_join("Native.scn")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, path)
	check(saved.ok, "Atlas generation with cleared native source saves")
	if saved.ok:
		var opened: AtlasStoreResult = AtlasCampaignBundle.load(path)
		check(opened.error == OK and opened.registry != null,
			"Atlas generation reloads its Drawing registry")
		if opened.error == OK:
			var recovered: DrawingResult = opened.registry.document_at("world", "ground", 1)
			check(recovered.ok and tile_bytes(recovered.value, layer, "-1,0") == cleared_bytes,
				"Atlas Save/Open retains exact cleared RGBA8 bytes")
			if recovered.ok:
				check(DrawingRasterTile.digest_rgba8(
					tile_bytes(recovered.value, layer, "-1,0"), STRIDE) == cleared_sha256,
					"Atlas Save/Open native RGBA8 SHA-256 parity")
	# No generated campaign history or chunk files remain after the test.
	remove_tree(saved_dir)
	print("T221_ATLAS: %d checks; %d failures" % [checks, failures])
	if failures == 0 and checks >= 15:
		print("T221_ATLAS_PASSED")
	quit(1 if failures else 0)
