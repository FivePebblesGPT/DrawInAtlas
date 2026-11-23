extends SceneTree
## T-253: full-tile deferred Delete, checked Rust adoption, mixed-operation
## fallback, selected mask holes, budget rejection and portable RGBA8.

const RED: int = 0xff1100ef
const HIDDEN: int = 0x00332211
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T253_MODEL_FAILED: " + label)

func pixel(doc: DrawingDocument, layer: String, p: Vector2i) -> int:
	var value: DrawingResult = doc.read_pixel(layer, p.x, p.y)
	return int(value.value) if value.ok else -1

func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t253-dense", 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var tile: DrawingRasterTile = DrawingRasterTile.new(64)
	var data: Dictionary[int, int] = tile.sparse_pixels()
	for y: int in range(64):
		for x: int in range(64):
			data[y * 64 + x] = RED
	data[0] = HIDDEN
	doc._nodes[layer].tiles["-1,-1"] = tile
	var original: PackedByteArray = tile.to_rgba8()
	var selected: DrawingSelection = DrawingSelection.new(Rect2i(-64, -64, 64, 64), true)
	check(selected.combine_rectangle(Rect2i(-64, -64, 1, 1), "Subtract"),
		"one selected-mask hole excludes zero-alpha hidden RGB")
	var revision: int = doc.revision
	var original_history: int = doc.history_length()
	var edit: DrawingEditSession = doc.begin_edit(layer, revision).value
	var staged: DrawingResult = edit.clear_rect(selected.bounds, selected)
	check(staged.ok and edit.change_count() == 4095 and edit._clear_deferred,
		"dense Delete defers 4095 selected pixels without global key staging")
	check(edit._before.is_empty() and edit._after.is_empty() and
		edit._preview_tiles["-1,-1"].size() == 4095 and
		edit._clear_images.size() == 1,
		"preview uses a single changed tile and exact RGBA8 snapshot")
	check(doc.revision == revision and tile.to_rgba8() == original,
		"precommit preview cannot change source or revision")
	var removed: DrawingResult = edit.commit()
	check(removed.ok and removed.delta != null and removed.delta.tile_stride == 64 and
		removed.delta.before_tiles.size() == 1 and removed.delta.after_tiles.size() == 1,
		"one atomic native whole-tile history delta")
	check(doc._native_raster_store != null and doc.revision == revision + 1 and
		doc.history_length() == original_history + 1,
		"Rust source owns first dense raster mutation and one history entry")
	check(pixel(doc, layer, Vector2i(-64, -64)) == HIDDEN and
		pixel(doc, layer, Vector2i(-63, -63)) == 0,
		"mask hole and signed hidden RGB survive Delete")
	check(doc.undo().ok and pixel(doc, layer, Vector2i(-63, -63)) == RED and
		pixel(doc, layer, Vector2i(-64, -64)) == HIDDEN,
		"Undo restores exact native original")
	check(doc.redo().ok and pixel(doc, layer, Vector2i(-63, -63)) == 0,
		"Redo restores cleared native content")
	var path: String = ProjectSettings.globalize_path("user://t253-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok, "standalone Drawing saves native Delete")
	var reopened: DrawingResult = DrawingFileIO.open(path)
	check(reopened.ok and pixel(reopened.value, layer, Vector2i(-64, -64)) == HIDDEN and
		pixel(reopened.value, layer, Vector2i(-63, -63)) == 0,
		"standalone Save/Open retains exact hidden RGB and cleared pixel")
	DirAccess.remove_absolute(path)

	# The old pixel-key API must remain correct for a session that mixes
	# direct shape staging with Delete (and in the reverse order).
	var mixed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(mixed._stage(3, 3, RED).ok, "stage pixel before Delete")
	check(mixed.clear_rect(Rect2i(2, 2, 3, 3)).ok and mixed.change_count() == 0,
		"mixed pre-staged pixel can be cleared without publishing an edit")
	mixed.cancel()
	check(doc.set_locked(layer, true).ok and not doc.begin_edit(layer, doc.revision).ok,
		"locked raster cannot be deleted")
	check(doc.set_locked(layer, false).ok, "unlock for mixed-operation test")
	check(doc.undo().ok, "undo dense Delete again for combined session")
	var after_clear: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(after_clear.clear_rect(Rect2i(-64, -64, 64, 64), selected).ok and
		after_clear._clear_deferred, "begin a deferred dense clear")
	check(after_clear._stage(50, 50, RED).ok and not after_clear._clear_deferred and
		after_clear._after.size() == 4096,
		"following public pixel edit materializes canonical pixel deltas")
	check(after_clear.commit().ok and pixel(doc, layer, Vector2i(50, 50)) == RED,
		"mixed clear plus another pixel mutation commits as one edit")
	check(doc.undo().ok and pixel(doc, layer, Vector2i(-63, -63)) == RED and
		pixel(doc, layer, Vector2i(50, 50)) == 0,
		"mixed Undo restores both raster changes")

	# Budget failure cannot modify source or leave any pending preview;
	# even the already native-owned document must remain on the same revision.
	var budget: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var start_revision: int = doc.revision
	var capped: DrawingResult = budget.clear_rect(selected.bounds, selected, 1)
	check(not capped.ok and capped.code == "REGION_LIMIT" and
		budget.change_count() == 0 and budget._preview_tiles.is_empty(),
		"whole-source budget rejects atomically with no live preview")
	budget.cancel()
	check(doc.revision == start_revision and pixel(doc, layer, Vector2i(-63, -63)) == RED,
		"failed bounded clear leaves canonical source untouched")
	print("T253_MODEL: %d checks, %d failures" % [checks, failures])
	if failures == 0 and checks >= 20:
		print("T253_MODEL_PASSED")
	quit(1 if failures else 0)
