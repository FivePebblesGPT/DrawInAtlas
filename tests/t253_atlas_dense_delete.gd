extends SceneTree
## T-253: Atlas history consumes a 2-tile dense Delete as a single native
## whole-tile delta, with exact signed RGBA8 and persisted campaign bytes.

const STRIDE: int = 64
const RED: int = 0xff0000ff
const HIDDEN: int = 0x00665544
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T253_ATLAS_FAILED: " + label)

func context(doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.detail_group_id = "D1"
	result.document_id = doc.id
	result.selected_layer_ids.append(layer)
	result.editor_mode = "surface_paint"
	result.has_focus = true
	return result

func tile_bytes(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = doc.request_chunk(layer, key)
	return (resolved.value as DrawingRasterTile).to_rgba8() if resolved.ok and resolved.value != null else PackedByteArray()

func erase_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in dir.get_directories():
		erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)

func run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, STRIDE).ok,
		"real Atlas campaign D1 Drawing created")
	var doc: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Dense").value)
	check(doc.external_history, "Atlas owns the chronological timeline")
	var sample: PackedByteArray = PackedByteArray()
	sample.resize(STRIDE * STRIDE * 4)
	for index: int in range(STRIDE * STRIDE):
		sample.encode_u32(index * 4, RED)
	sample.encode_u32(0, HIDDEN)
	var signed: PackedByteArray = sample.duplicate()
	doc._nodes[layer].tiles["-1,-1"] = DrawingRasterTile.from_rgba8(STRIDE, signed)
	doc._nodes[layer].tiles["0,-1"] = DrawingRasterTile.from_rgba8(STRIDE, sample)
	var selected: DrawingSelection = DrawingSelection.new(Rect2i(-64, -64, 128, 64), true)
	check(selected.combine_rectangle(Rect2i(-64, -64, 1, 1), "Subtract"),
		"mask hole preserves negative source tile's hidden RGB")
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var original_left: PackedByteArray = tile_bytes(doc, layer, "-1,-1")
	var original_right: PackedByteArray = tile_bytes(doc, layer, "0,-1")
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "fresh Atlas Drawing edit starts")
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var clear: DrawingResult = edit.clear_rect(selected.bounds, selected)
	check(clear.ok and edit.change_count() == 8191 and edit._clear_deferred,
		"Atlas stages 8191 selected pixels using two tile envelopes")
	var ctx: DrawingHistoryContext = context(doc, layer)
	ctx.selection_mask = selected
	var committed: DrawingResult = history.commit_drawing(edit, ctx, ctx)
	check(committed.ok and doc._native_raster_store != null,
		"Atlas accepts native-first dense Delete")
	check(committed.delta != null and committed.delta.tile_stride == STRIDE and
		committed.delta.before_tiles.size() == 2 and
		committed.delta.after_tiles.size() == 2,
		"Atlas global event carries both native whole-tile images")
	check(history.can_undo() and doc.history_length() == 0,
		"Atlas uses exactly one external history command, no local shadow")
	var cleared_left: PackedByteArray = tile_bytes(doc, layer, "-1,-1")
	var cleared_right: PackedByteArray = tile_bytes(doc, layer, "0,-1")
	check(cleared_left.decode_u32(0) == HIDDEN and
		cleared_left.decode_u32(4) == 0 and cleared_right.count(0) == cleared_right.size(),
		"native Delete clears 8191 pixels, preserves protected hidden RGB")
	check(history.undo() and tile_bytes(doc, layer, "-1,-1") == original_left and
		tile_bytes(doc, layer, "0,-1") == original_right,
		"Atlas Undo restores exact original source and identity")
	check(history.redo() and tile_bytes(doc, layer, "-1,-1") == cleared_left and
		tile_bytes(doc, layer, "0,-1") == cleared_right,
		"Atlas Redo restores exact cleared source bytes")
	var folder: String = ProjectSettings.globalize_path("user://t253-atlas-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(folder) == OK,
		"create isolated bundle save directory")
	var path: String = folder.path_join("Native.scn")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, path)
	check(saved.ok, "save exact native Atlas generation")
	if saved.ok:
		var opened: AtlasStoreResult = AtlasCampaignBundle.load(path)
		check(opened.error == OK and opened.registry != null,
			"reopen saved Atlas generation")
		if opened.error == OK:
			var recovered: DrawingResult = opened.registry.document_at("world", "ground", 1)
			check(recovered.ok and tile_bytes(recovered.value, layer, "-1,-1") == cleared_left and
				tile_bytes(recovered.value, layer, "0,-1") == cleared_right,
				"Atlas Save/Open preserves byte-exact cleared native images")
	erase_tree(folder)
	print("T253_ATLAS: %d checks; %d failures" % [checks, failures])
	if failures == 0 and checks >= 14:
		print("T253_ATLAS_PASSED")
	quit(1 if failures else 0)
