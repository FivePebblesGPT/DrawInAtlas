extends SceneTree
## T-268: large signed source mask/Move crosses native tile boundaries while
## Atlas owns the one chronological history and the persisted campaign bytes.

const STRIDE: int = 64
const INK: int = 0xff22aa44
const ISLAND: int = 0xff7766cc
const HIDDEN: int = 0x00445566
const HOLE: int = 0x00aabbcc
const GUARD: int = 0xffab2388
const SHIFT: Vector2i = Vector2i(128, 16)
const MAIN: Rect2i = Rect2i(-48, -42, 96, 70)
const CUTOUT: Rect2i = Rect2i(-8, -5, 14, 13)
const ISLAND_AREA: Rect2i = Rect2i(52, -2, 8, 8)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T268_ATLAS_FAILED: " + label)


func context(document: DrawingDocument, layer: String,
		selection: DrawingSelection) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.detail_group_id = "D1"
	result.document_id = document.id
	result.selected_layer_ids.append(layer)
	result.editor_mode = "surface_paint"
	result.selection_mask = selection
	result.has_focus = true
	return result


func pixel(document: DrawingDocument, layer: String, point: Vector2i) -> int:
	var result: DrawingResult = document.read_pixel(layer, point.x, point.y)
	return int(result.value) if result.ok else -1


func tile_bytes(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var result: DrawingResult = document.request_chunk(layer, key)
	return (result.value as DrawingRasterTile).to_rgba8() if result.ok and result.value != null else PackedByteArray()


func seed_tile(document: DrawingDocument, layer: String, cx: int, cy: int) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(STRIDE * STRIDE * 4)
	for y: int in range(STRIDE):
		for x: int in range(STRIDE):
			var point: Vector2i = Vector2i(cx * STRIDE + x, cy * STRIDE + y)
			var rgba: int = 0
			if MAIN.has_point(point):
				rgba = INK
			if ISLAND_AREA.has_point(point):
				rgba = ISLAND
			if point == Vector2i(-48, -42):
				rgba = HIDDEN
			elif point == Vector2i(-1, 0):
				rgba = HOLE
			elif point == Vector2i(-50, -44):
				rgba = GUARD
			bytes.encode_u32((y * STRIDE + x) * 4, rgba)
	document._nodes[layer].tiles["%d,%d" % [cx, cy]] = DrawingRasterTile.from_rgba8(STRIDE, bytes)


func erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories():
		erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, STRIDE).ok,
		"campaign and real Atlas Drawing detail are available")
	var document: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Large Mask").value)
	check(document.external_history and document.tile_stride == STRIDE,
		"Atlas owns history and signed native storage tile stride")
	for cy: int in [-1, 0]:
		for cx: int in [-1, 0]:
			seed_tile(document, layer, cx, cy)
	var selected: DrawingSelection = DrawingSelection.new(MAIN, true)
	check(selected.combine_rectangle(CUTOUT, "Subtract") and
		selected.combine_rectangle(ISLAND_AREA, "Add") and
		selected.bounds.size.x * selected.bounds.size.y > 4096,
		"large compound selection contains cutout and disjoint island")
	check(not selected.allows(Vector2i(-1, 0)) and
		selected.allows(Vector2i(-48, -42)) and
		selected.allows(Vector2i(54, 0)),
		"source mask preserves excluded hole and includes island/hidden RGB")
	var original: Dictionary[String, PackedByteArray] = {}
	for key: String in ["-1,-1", "0,-1", "-1,0", "0,0"]:
		original[key] = tile_bytes(document, layer, key)
	check(pixel(document, layer, Vector2i(-48, -42)) == HIDDEN and
		pixel(document, layer, Vector2i(-1, 0)) == HOLE and
		pixel(document, layer, Vector2i(-50, -44)) == GUARD,
		"signed source contains hidden RGBA, excluded hole and outside guard")
	var captured: DrawingResult = DrawingClipboard.capture(document, layer,
		selected.bounds, selected)
	check(captured.ok, "capture reads occupied source tiles under immutable selection")
	if not captured.ok:
		quit(1)
		return
	var payload: DrawingClipboard = captured.value as DrawingClipboard
	check(payload._pixels.size() == MAIN.size.x * MAIN.size.y -
		CUTOUT.size.x * CUTOUT.size.y + ISLAND_AREA.size.x * ISLAND_AREA.size.y,
		"large sparse capture has exact selected payload count")
	var before_revision: int = document.revision
	var begun: DrawingResult = document.begin_edit(layer, before_revision)
	check(begun.ok, "Atlas large Move starts from current native revision")
	if not begun.ok:
		quit(1)
		return
	var edit: DrawingEditSession = begun.value as DrawingEditSession
	var moved: DrawingResult = DrawingClipboard.move_captured(edit, payload, SHIFT)
	check(moved.ok and edit.change_count() >= 10000,
		"masked source clear and disjoint destination paste share one edit")
	if not moved.ok:
		edit.cancel()
		quit(1)
		return
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var ctx: DrawingHistoryContext = context(document, layer, selected)
	var committed: DrawingResult = history.commit_drawing(edit, ctx, ctx)
	check(committed.ok and document._native_raster_store != null,
		"Atlas commits large Move through mandatory native raster owner")
	if not committed.ok:
		quit(1)
		return
	var command: AtlasDrawingEdit = history.get_undo_command() as AtlasDrawingEdit
	check(command != null and command.delta.native_history_token > 0 and
		command.delta.before.is_empty() and command.delta.after.is_empty(),
		"global history carries native whole-tile delta, no pixel shadow")
	check(history.can_undo() and document.history_length() == 0 and
		document.revision > before_revision,
		"exactly one global command and no duplicate Drawing local timeline")
	check(pixel(document, layer, Vector2i(-48, -42)) == 0 and
		pixel(document, layer, Vector2i(-48, -42) + SHIFT) == HIDDEN and
		pixel(document, layer, Vector2i(54, 0)) == 0 and
		pixel(document, layer, Vector2i(54, 0) + SHIFT) == ISLAND,
		"native Move clears selected source and preserves hidden RGBA and island")
	check(pixel(document, layer, Vector2i(-1, 0)) == HOLE and
		pixel(document, layer, Vector2i(-1, 0) + SHIFT) == 0 and
		pixel(document, layer, Vector2i(-50, -44)) == GUARD,
		"mask hole and outside source guard never moved or erased")
	var after: Dictionary[String, PackedByteArray] = {}
	for key: String in ["-1,-1", "0,-1", "-1,0", "0,0", "1,-1", "2,-1", "1,0", "2,0"]:
		after[key] = tile_bytes(document, layer, key)
	check(history.undo(), "Atlas global Undo succeeds on native large Move")
	var restored: bool = true
	for key: String in original:
		if tile_bytes(document, layer, key) != original[key]:
			restored = false
	check(restored and pixel(document, layer, Vector2i(-48, -42) + SHIFT) == 0,
		"Undo restores source tiles byte-for-byte and removes destination")
	check(history.redo(), "Atlas global Redo succeeds on same native event")
	var replayed: bool = true
	for key: String in after:
		if tile_bytes(document, layer, key) != after[key]:
			replayed = false
	check(replayed and pixel(document, layer, Vector2i(-48, -42) + SHIFT) == HIDDEN,
		"Redo exactly replays source and destination tile bytes")
	var folder: String = ProjectSettings.globalize_path("user://t268-atlas-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "isolated save folder created")
	var path: String = folder.path_join("LargeMove.scn")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, path)
	check(saved.ok, "Atlas writes native large-Move generation")
	if saved.ok:
		var loaded: AtlasStoreResult = AtlasCampaignBundle.load(path)
		check(loaded.error == OK and loaded.registry != null,
			"Atlas reopens a saved native generation")
		if loaded.error == OK and loaded.registry != null:
			var restored_doc: DrawingResult = loaded.registry.document_at("world", "ground", 1)
			var persistence_ok: bool = restored_doc.ok
			if restored_doc.ok:
				for key: String in after:
					if tile_bytes(restored_doc.value as DrawingDocument, layer, key) != after[key]:
						persistence_ok = false
			check(persistence_ok, "Save/Open preserves every signed source/destination tile byte")
	erase_tree(folder)
	print("T268_ATLAS: %d checks; %d failures" % [checks, failures])
	if failures == 0 and checks >= 20:
		print("T268_ATLAS_PASSED")
	quit(1 if failures else 0)
