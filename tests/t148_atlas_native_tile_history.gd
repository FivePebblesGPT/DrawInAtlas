extends SceneTree
## T-148: a real Rust-owned Brush gesture participates in Atlas's single
## chronological edit history without reducing RGBA8 tile deltas to pixel maps.

const STRIDE: int = 64
const INK: int = 0xff3456ab
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_ATLAS_NATIVE_FAILED: " + label)


func context(document: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.detail_group_id = "D1"
	result.document_id = document.id
	result.selected_layer_ids.append(layer)
	result.editor_mode = "surface_paint"
	result.has_focus = true
	return result


func packed(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = document.request_chunk(layer, key)
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func stroke(document: DrawingDocument, layer: String, timeline: AtlasEditHistory,
		from: Vector2) -> DrawingResult:
	var opened: DrawingResult = document.begin_edit(layer, document.revision)
	if not opened.ok:
		return opened
	var session: DrawingEditSession = opened.value as DrawingEditSession
	var native: Object = ClassDB.instantiate("DrawingNativeBrush")
	var started: DrawingResult = session.begin_native_stroke(native,
		"NativeHard", "", 8.0, INK, CLIP, true)
	if not started.ok:
		session.cancel()
		return started
	var sampled: DrawingResult = session.paint_path_native(
		PackedVector2Array([from, from + Vector2(8.0, 0.0)]), INK, false, null)
	if not sampled.ok:
		session.cancel()
		return sampled
	var pinned: DrawingHistoryContext = context(document, layer)
	return timeline.commit_drawing(session, pinned, pinned)


## Remove only the fresh, isolated campaign fixture directory.
func remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in directory.get_directories():
		remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real Rust native extension registered")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok, "Atlas registry attached to campaign")
	check(registry.ensure_detail("world", "ground", 1, 2, 1, STRIDE).ok,
		"Atlas registers D1 with independent 64px storage stride")
	var selected: DrawingResult = registry.document_at("world", "ground", 1, true)
	if not selected.ok:
		printerr("T148_ATLAS_NATIVE_FAILED: unable to create Drawing detail")
		quit(1)
		return
	var document: DrawingDocument = selected.value
	check(document.external_history and document.tile_stride == STRIDE,
		"Atlas owns document timeline, never a duplicate local cursor")
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Native Paint").value)
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	# Preserve transparent hidden RGB in an otherwise untouched source tile.
	var seeded: PackedByteArray = PackedByteArray()
	seeded.resize(STRIDE * STRIDE * 4)
	seeded.encode_u32(0, 0x00123456)
	document._nodes[layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, seeded)
	var first: DrawingResult = stroke(document, layer, timeline, Vector2(-20.5, 10.5))
	check(first.ok, "Atlas commits first real native Brush gesture")
	if not first.ok:
		print("T148_ATLAS_NATIVE_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var store: Object = document._native_raster_store
	var first_bytes: PackedByteArray = packed(document, layer, "-1,0")
	var command_first: AtlasDrawingEdit = timeline.get_undo_command() as AtlasDrawingEdit
	check(command_first != null and command_first.delta.tile_stride == STRIDE and
		command_first.delta.native_history_token == first.delta.native_history_token and
		command_first.delta.native_history_token > 0,
		"Atlas command keeps tile stride and opaque native Undo token")
	check(command_first.delta.before_tiles["-1,0"] == seeded and
		command_first.delta.after_tiles["-1,0"] == first_bytes and
		command_first.delta.before.is_empty() and command_first.delta.after.is_empty(),
		"Atlas stores signed full-tile snapshots, not empty pixel maps")
	# Command and caller must not share writable history buffers/dictionaries.
	first.delta.after_tiles["-1,0"] = PackedByteArray([1, 2, 3])
	check(command_first.delta.after_tiles["-1,0"] == first_bytes,
		"caller mutation cannot corrupt Atlas native history snapshot")
	var grid: AtlasGrid = campaign.get_map("world").grid
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 4.0
	check(timeline.execute(AtlasGridEdit.new("world", grid, changed)),
		"Atlas grid command interleaves with native Drawing history")
	var second: DrawingResult = stroke(document, layer, timeline, Vector2(13.5, 20.5))
	check(second.ok and second.delta.native_history_token > 0,
		"second native Brush command joins global Atlas order")
	if not second.ok:
		print("T148_ATLAS_NATIVE_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var right: PackedByteArray = packed(document, layer, "0,0")
	var command_second: AtlasDrawingEdit = timeline.get_undo_command() as AtlasDrawingEdit
	check(command_second.delta.after_tiles["0,0"] == right and
		int(store.call("stats").get("undo", -1)) == 2,
		"both native edits live in one Rust history and two Atlas commands")
	check(document.history_length() == 0 and document._native_raster_store == store,
		"no extra local history or replacement native store")
	var restored_main: PackedByteArray = right.duplicate()
	restored_main[0] = 255 - restored_main[0]
	document._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(STRIDE, restored_main)
	check(not timeline.undo() and timeline.get_undo_command() == command_second and
		int(store.call("stats").get("undo", -1)) == 2,
		"tampered source rejects global Undo without consuming Rust token/cursor")
	document._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(STRIDE, right)
	check(timeline.undo() and packed(document, layer, "0,0").is_empty(),
		"global Undo reverses second native tile transaction")
	check(int(store.call("stats").get("undo", -1)) == 1 and
		int(store.call("stats").get("redo", -1)) == 1 and
		int(store.call("stats").get("revision", -1)) == document.revision,
		"Rust and Godot revisions stay synchronized after global Undo")
	check(timeline.undo() and not campaign.get_map("world").grid.same_as(changed),
		"global Undo also reverses intervening Atlas command")
	check(timeline.undo() and packed(document, layer, "-1,0") == seeded,
		"global Undo restores exact hidden RGB and alpha after first native stroke")
	check(int(store.call("stats").get("undo", -1)) == 0 and
		int(store.call("stats").get("redo", -1)) == 2,
		"all Rust native history tokens moved to redo stack")
	check(timeline.redo() and packed(document, layer, "-1,0") == first_bytes,
		"global Redo restores first signed tile bytes")
	check(timeline.redo() and campaign.get_map("world").grid.same_as(changed),
		"Atlas grid Redo retains chronological ordering")
	check(timeline.redo() and packed(document, layer, "0,0") == right,
		"global Redo restores second native tile bytes")
	check(int(store.call("stats").get("undo", -1)) == 2 and
		int(store.call("stats").get("redo", -1)) == 0 and
		int(store.call("stats").get("revision", -1)) == document.revision,
		"global replay uses Rust token stack rather than detached-only fallback")
	# Atlas's generation store, not just isolated DrawingFileIO, must package
	# the native-authored signed tiles and restore them lazily by detail ID.
	var bundle_dir: String = ProjectSettings.globalize_path("user://t148-atlas-bundle-" +
		DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(bundle_dir) == OK,
		"create isolated Atlas campaign generation directory")
	var bundle_path: String = bundle_dir.path_join("Native.scn")
	var bundled: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, bundle_path)
	check(bundled.ok, "real Atlas generation stores native-authored Drawing detail")
	if bundled.ok:
		var decoded_bundle: AtlasStoreResult = AtlasCampaignBundle.load(bundle_path)
		check(decoded_bundle.error == OK and decoded_bundle.registry != null,
			"saved Atlas generation reloads with a valid registry")
		if decoded_bundle.error == OK:
			check(decoded_bundle.registry.document_count() == 0,
				"Atlas generation loads native-authored Drawing lazily")
			var lazy: DrawingResult = decoded_bundle.registry.document_at(
				"world", "ground", 1)
			check(lazy.ok and lazy.value != null and lazy.value.id == document.id,
				"native-authored D1 binds to its stable Atlas ID on demand")
			if lazy.ok and lazy.value != null:
				var bundled_doc: DrawingDocument = lazy.value
				check(packed(bundled_doc, layer, "-1,0") == first_bytes and
					packed(bundled_doc, layer, "0,0") == right,
					"Atlas generation roundtrips both native RGBA8 tiles")
				check(bundled_doc.external_history,
					"reloaded Atlas generation remains externally history-owned")
	remove_tree(bundle_dir)
	# Persist this actual native-authored document under the Atlas detail ID,
	# then re-open it through the registry's normal saved-document attachment.
	var path: String = ProjectSettings.globalize_path("user://t148-atlas-native-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(document, path).ok, "Atlas detail serializes real native-sourced .drawing")
	var reopened: DrawingResult = DrawingFileIO.open(path)
	check(reopened.ok and reopened.value.id == document.id,
		"real .drawing reopens with stable Atlas document ID")
	if reopened.ok:
		var loaded: DrawingDocument = reopened.value
		check(packed(loaded, layer, "-1,0") == first_bytes and
			packed(loaded, layer, "0,0") == right,
			"reopened Atlas source keeps both native-authored RGBA8 tiles")
		var rebuilt: DrawingResult = AtlasDrawingRegistry.from_index(
			registry.export_index(), campaign)
		check(rebuilt.ok, "Atlas detail index reconstructs for native-authored source")
		if rebuilt.ok:
			var other: AtlasDrawingRegistry = rebuilt.value
			check(other.attach_loaded_document("world", "ground", 1, loaded).ok,
				"reopened native-authored source binds to same Atlas D1 slot")
			check(other.document_at("world", "ground", 1).value == loaded and
				loaded.external_history, "reopened document is Atlas-owned")
			var fresh: AtlasEditHistory = AtlasEditHistory.new(campaign)
			fresh.active_map_id = "world"
			var next: DrawingResult = stroke(loaded, layer, fresh, Vector2(32.5, 32.5))
			check(next.ok and loaded._native_raster_store != null and
				packed(loaded, layer, "-1,0") == first_bytes,
				"next native gesture reauthorizes saved Atlas bytes without losing old pixels")
			check(fresh.undo() and packed(loaded, layer, "0,0") == right,
				"reloaded Atlas detail replays fresh native tile history")
	DirAccess.remove_absolute(path)
	# Native history is bounded and may be evicted or detached. Atlas keeps an
	# independently frozen whole-tile snapshot to replay an older global edit
	# without reintroducing per-pixel history maps or mutating stale Rust state.
	document._native_raster_store = null
	document._native_source_identities.clear()
	check(timeline.undo() and packed(document, layer, "0,0").is_empty(),
		"detached global Undo replays tile snapshot without a native owner")
	check(timeline.redo() and packed(document, layer, "0,0") == right,
		"detached global Redo restores byte-identical full tile")
	var continued: DrawingResult = stroke(document, layer, timeline, Vector2(32.5, 38.5))
	check(continued.ok and document._native_raster_store != null and
		int(document._native_raster_store.call("stats").get("revision", -1)) == document.revision,
		"new native gesture rebases from detached Atlas source")
	var continued_bytes: PackedByteArray = packed(document, layer, "0,0")
	check(continued_bytes != right and timeline.undo() and
		packed(document, layer, "0,0") == right,
		"rebased native token remains reversible on Atlas timeline")
	check(timeline.undo() and packed(document, layer, "0,0").is_empty(),
		"earlier global command still replays its detached RGBA8 snapshot")
	check(timeline.redo() and timeline.redo() and
		packed(document, layer, "0,0") == continued_bytes,
		"mixed detached/native Atlas redo restores latest canonical bytes")
	print("T148_ATLAS_NATIVE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
