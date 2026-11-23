extends SceneTree
## T-221: sparse content deletion must match a dense RGBA8 oracle without
## walking the enclosing marquee, including lazy and signed source tiles.

var checks: int = 0
var failures: int = 0
var fetches: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T221_DELETE_FAILED: " + label)


func pixel(doc: DrawingDocument, layer: String, p: Vector2i) -> int:
	var read: DrawingResult = doc.read_pixel(layer, p.x, p.y)
	return int(read.value) if read.ok else -1


func broken_fetch(_ref: String) -> PackedByteArray:
	fetches += 1
	return PackedByteArray([1, 2, 3])


func make_document(suffix: String) -> DrawingDocument:
	return DrawingDocument.new("t221-" + suffix, 32)


func run() -> void:
	var doc: DrawingDocument = make_document("sparse")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var originals: Dictionary[Vector2i, int] = {
		Vector2i(-33, -33): 0x00aabbcc, Vector2i(-32, -32): 0xff123456,
		Vector2i(-1, -1): 0x00abcdef, Vector2i(0, 0): 0xffaabbcc,
		Vector2i(31, 31): 0xff112233, Vector2i(32, 32): 0x00010203,
		Vector2i(511, 511): 0xff445566,
	}
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	for p: Vector2i in originals:
		check(seed._stage(p.x, p.y, originals[p]).ok, "seed signed/hidden RGBA %s" % p)
	check(seed.commit().ok, "seed content committed")
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-65536, -65536,
		131072, 131072), true)
	check(selection.combine_rectangle(Rect2i(-2, -2, 4, 4), "Subtract"),
		"mask hole excludes two occupied source pixels")
	var prior_revision: int = doc.revision
	var prior_history: int = doc.history_length()
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "large sparse edit starts")
	if started.ok:
		var edit: DrawingEditSession = started.value as DrawingEditSession
		var staged: DrawingResult = edit.clear_rect(selection.bounds, selection)
		check(staged.ok, "huge sparse bounds clear without dense region limit: " + staged.code)
		if staged.ok:
			check(edit.change_count() == originals.size() - 2,
				"only five authorized nonzero pixels stage")
			check(edit.commit().ok, "one atomic deletion commits")
			check(doc.history_length() == prior_history + 1 and doc.revision == prior_revision + 1,
				"one Undo step and one document revision")
			for p: Vector2i in originals:
				var expected: int = originals[p] if not selection.allows(p) else 0
				check(pixel(doc, layer, p) == expected,
					"byte-exact clear/preserve at %s" % p)
			check(doc.undo().ok, "Undo succeeds")
			for p: Vector2i in originals:
				check(pixel(doc, layer, p) == originals[p],
					"Undo restores source bytes at %s" % p)
			check(doc.redo().ok, "Redo succeeds")
			for p: Vector2i in originals:
				var expected: int = originals[p] if not selection.allows(p) else 0
				check(pixel(doc, layer, p) == expected,
					"Redo byte parity at %s" % p)
		else:
			edit.cancel()
			check(doc.revision == prior_revision and doc.history_length() == prior_history,
				"failure never publishes partial state")

	var active_empty: DrawingSelection = DrawingSelection.new(Rect2i(), true)
	var empty_edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(empty_edit.clear_rect(Rect2i(-65536, -65536, 131072, 131072), active_empty).ok and
		empty_edit.change_count() == 0, "enabled empty denies all without clear")
	empty_edit.cancel()

	var lazy: DrawingDocument = make_document("lazy")
	var lazy_layer: String = String(lazy.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	# A corrupt pending source is accepted at registration but cannot be resolved.
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(32 * 32 * 4)
	bytes[0] = 7
	var digest: String = DrawingRasterTile.digest_rgba8(bytes, 32)
	check(lazy.register_lazy_chunk(lazy_layer, -1, 0, "broken", digest,
		Callable(self, "broken_fetch")).ok, "register pending source")
	var exclude: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 32, 32), true)
	var skipped: DrawingEditSession = lazy.begin_edit(lazy_layer, lazy.revision).value
	check(skipped.clear_rect(Rect2i(-32, 0, 64, 32), exclude).ok and fetches == 0,
		"unselected corrupt lazy tile is never fetched")
	skipped.cancel()
	var include: DrawingSelection = DrawingSelection.new(Rect2i(-32, 0, 32, 32), true)
	var failed: DrawingEditSession = lazy.begin_edit(lazy_layer, lazy.revision).value
	var fetched: DrawingResult = failed.clear_rect(Rect2i(-32, 0, 32, 32), include)
	check(not fetched.ok and fetched.code == "CORRUPT_TILE" and fetches == 1,
		"selected corrupt source fails closed")
	failed.cancel()
	check(lazy.history_length() == 0, "failed source does not publish history")

	# Clear after staging must also discard uncommitted pixels that do not yet
	# exist in the document's occupied tile index.
	var mixed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(mixed._stage(555, 111, 0x00123456).ok and mixed.change_count() == 1,
		"stage new hidden-RGB pixel in previously empty source tile")
	check(mixed.clear_rect(Rect2i(554, 110, 3, 3)).ok and mixed.change_count() == 0,
		"sparse clear erases earlier staged-but-unpublished pixel")
	mixed.cancel()
	var budget: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(budget._stage(4, 4, 0xff334455).ok, "prepare pre-existing session preview")
	var previous: Dictionary[String, int] = budget._after.duplicate()
	var limited: DrawingResult = budget.clear_rect(Rect2i(-35, -35, 70, 70), null, 1)
	check(not limited.ok and limited.code == "REGION_LIMIT" and budget._after == previous,
		"occupied-pixel budget failure rolls back pre-existing staged preview")
	budget.cancel()
	# Atlas uses a signed 64-bit document origin while local selection/masks
	# remain Vector2i: never downcast the global tile coordinates.
	var distant: DrawingDocument = make_document("atlas-origin")
	var distant_layer: String = String(distant.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var ox: int = 5000000033
	var oy: int = -5000000097
	var original: DrawingEditSession = distant.begin_edit(distant_layer, distant.revision,
		Transform2D.IDENTITY, ox, oy).value as DrawingEditSession
	check(original._stage(-33, 33, 0x00abcdef).ok and original.commit().ok,
		"seed remote signed-64-bit source")
	var distant_clear: DrawingEditSession = distant.begin_edit(distant_layer,
		distant.revision, Transform2D.IDENTITY, ox, oy).value as DrawingEditSession
	check(distant_clear.clear_rect(Rect2i(-10000, -10000, 20000, 20000)).ok and
		distant_clear.change_count() == 1 and distant_clear.commit().ok,
		"sparse Atlas-origin clear applies exactly one source pixel")
	check(int(distant.read_pixel(distant_layer, ox - 33, oy + 33).value) == 0 and
		distant.undo().ok and int(distant.read_pixel(distant_layer, ox - 33,
		oy + 33).value) == 0x00abcdef,
		"signed-64-bit Undo restores hidden RGB")

	# Standalone persistence must retain protected zero-alpha RGB even after
	# the fast clear has removed other source pixels and replayed history.
	var save_path: String = ProjectSettings.globalize_path("user://t221-sparse-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "save sparse deletion as standalone .drawing")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok, "reopen standalone sparse source")
	if reopened.ok:
		var recovered: DrawingDocument = reopened.value as DrawingDocument
		for p: Vector2i in originals:
			var expected: int = originals[p] if not selection.allows(p) else 0
			check(pixel(recovered, layer, p) == expected,
				"standalone Save/Open exact RGBA8 at %s" % p)
	DirAccess.remove_absolute(save_path)

	check(doc.set_locked(layer, true).ok, "lock raster layer")
	check(not doc.begin_edit(layer, doc.revision).ok, "locked layer rejects edit")
	check(doc.set_locked(layer, false).ok and doc.set_visibility(layer, false).ok,
		"hide unlocked layer")
	check(not doc.begin_edit(layer, doc.revision).ok, "hidden layer rejects edit")
	print("T221_DELETE: %d checks; %d failures" % [checks, failures])
	if failures == 0 and checks >= 45:
		print("T221_DELETE_PASSED")
	quit(1 if failures else 0)
