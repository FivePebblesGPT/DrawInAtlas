extends SceneTree
## T-095: exact comparison of Legacy Brush tile-publication against the
## original pixel-key publisher, including mixed APIs and fail-closed commits.

const COLOR: int = 0x9050c4a1
const AREA: Rect2i = Rect2i(-72, -72, 144, 144)
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_LEGACY_TILE_COMMIT_FAILED: " + label)

func create_target(label: String, stride: int, origin: Vector2i) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, origin.x, origin.y).value
	var bytes: PackedByteArray = PackedByteArray()
	for i: int in range(17 * 17):
		bytes.append_array(PackedByteArray([i % 255, 43, 228,
			0 if i % 7 == 0 else 140]))
	check(seed.apply_region(Rect2i(-8, -8, 17, 17), bytes).ok and seed.commit().ok,
		label + " source seeded with hidden RGB")
	return {"doc": doc, "layer": layer, "origin": origin}

func begin(target: Dictionary) -> DrawingEditSession:
	var doc: DrawingDocument = target["doc"]
	var origin: Vector2i = target["origin"]
	return doc.begin_edit(target["layer"], doc.revision,
		Transform2D.IDENTITY, origin.x, origin.y).value

func snapshot(target: Dictionary, edit: DrawingEditSession = null) -> PackedByteArray:
	var origin: Vector2i = target["origin"]
	var result: DrawingResult = DrawingRenderer.render(target["doc"], AREA,
		origin.x, origin.y, AREA.size.x * AREA.size.y, edit)
	check(result.ok, "render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()

func compare_case(stride: int, origin: Vector2i, erase: bool, mix: bool) -> void:
	var label: String = "%d/%s/%s" % [stride, erase, mix]
	var direct: Dictionary = create_target("direct-" + label, stride, origin)
	var old: Dictionary = create_target("reference-" + label, stride, origin)
	var fast: DrawingEditSession = begin(direct)
	var reference: DrawingEditSession = begin(old)
	reference._brush_tile_publish = false
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-67, -65, 133, 131), true)
	check(mask.combine_rectangle(Rect2i(-2, -2, 5, 5), "Subtract"), label + " mask hole")
	var batches: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-42.5, -39.5), Vector2(-9.125, 2.875)]),
		PackedVector2Array([Vector2(28.25, 31.5), Vector2(-26.25, 38.25)]),
		PackedVector2Array([Vector2(38.5, -39.5), Vector2(8.25, -21.5)]),
	]
	var clip: Rect2i = Rect2i(-66, -67, 130, 130)
	for batch: PackedVector2Array in batches:
		check(fast.paint_path(batch, COLOR, 60.0, erase, mask, 1048576, clip).ok and
			reference.paint_path(batch, COLOR, 60.0, erase, mask, 1048576, clip).ok,
			label + " overlapping 60px path accepted")
	if mix:
		check(fast.fill_rect(Rect2i(23, -11, 3, 3), 0x408812ff).ok and
			reference.fill_rect(Rect2i(23, -11, 3, 3), 0x408812ff).ok,
			label + " ordinary API mixes with stroke")
	check(fast._brush_tile_publish == not mix,
		label + " uses tile-only publisher iff paint-only")
	check(fast.change_count() == reference.change_count() and
		fast._before == reference._before and fast._after == reference._after,
		label + " source and canonical pixel-delta maps agree")
	var preview: PackedByteArray = snapshot(direct, fast)
	check(preview == snapshot(old, reference), label + " detached preview parity")
	var baseline: int = direct["doc"].revision
	var fast_result: DrawingResult = fast.commit()
	var ref_result: DrawingResult = reference.commit()
	check(fast_result.ok and ref_result.ok and
		direct["doc"].revision == baseline + 1, label + " one atomic history commit")
	if fast_result.ok and ref_result.ok:
		check(fast_result.delta.before == ref_result.delta.before and
			fast_result.delta.after == ref_result.delta.after,
			label + " byte-for-byte canonical history maps")
		var regions: Dictionary[String, bool] = {}
		for region: DrawingDirtyRegion in ref_result.regions:
			regions["%d,%d,%d,%d" % [region.x, region.y, region.width, region.height]] = true
		check(fast_result.regions.size() == ref_result.regions.size(),
			label + " same dirty-region count")
		for region: DrawingDirtyRegion in fast_result.regions:
			check(regions.has("%d,%d,%d,%d" % [region.x, region.y,
				region.width, region.height]), label + " same dirty region")
	var final_bytes: PackedByteArray = snapshot(direct)
	check(final_bytes == snapshot(old) and final_bytes == preview,
		label + " exact committed pixels and preview parity")
	check(direct["doc"].undo().ok and old["doc"].undo().ok and
		snapshot(direct) == snapshot(old), label + " one Undo")
	check(direct["doc"].redo().ok and old["doc"].redo().ok and
		snapshot(direct) == final_bytes, label + " one Redo")

func reject_partial_commit() -> void:
	var origin: Vector2i = Vector2i(2147483673, -2147483711)
	var target: Dictionary = create_target("bad-last-tile", 64, origin)
	var edit: DrawingEditSession = begin(target)
	check(edit.paint_path(PackedVector2Array([Vector2(-55.5, -55.5),
		Vector2(55.5, 55.5)]), COLOR, 60.0).ok, "multi-tile stroke prepared")
	var revision: int = target["doc"].revision
	var before: PackedByteArray = snapshot(target)
	var tile_key: String = DrawingDocument.TILES.tile_key64(origin.x + 55,
		origin.y + 55, target["doc"].tile_stride)
	var patch: Dictionary = edit._preview_tiles[tile_key]
	patch[-4] = COLOR
	edit._preview_tiles[tile_key] = patch
	var result: DrawingResult = edit.commit()
	check(not result.ok and result.code == "COORD", "invalid late storage offset rejects transaction")
	check(target["doc"].revision == revision and snapshot(target) == before,
		"late failure publishes neither tiles nor history")

	var stale: DrawingEditSession = begin(target)
	check(stale.paint_path(PackedVector2Array([Vector2(40.5, 40.5)]),
		COLOR, 60.0).ok, "stale brush staged")
	var concurrent: DrawingEditSession = begin(target)
	check(concurrent.fill_rect(Rect2i(-60, -60, 1, 1), 0x80ffffff).ok and
		concurrent.commit().ok, "concurrent edit commits")
	var unchanged: PackedByteArray = snapshot(target)
	var current_revision: int = target["doc"].revision
	result = stale.commit()
	check(not result.ok and result.code == "STALE_REVISION" and
		target["doc"].revision == current_revision and snapshot(target) == unchanged,
		"stale revision cannot publish")

	# A reentrant loader or other code can replace a resident tile without
	# publishing a revision. The verified source identity must still match.
	var replaced: DrawingEditSession = begin(target)
	check(replaced.paint_path(PackedVector2Array([Vector2(37.5, 37.5)]),
		COLOR, 60.0).ok, "replacement-test brush staged")
	var tile_key_replaced: String = DrawingDocument.TILES.tile_key64(
		origin.x + 37, origin.y + 37, target["doc"].tile_stride)
	var doc: DrawingDocument = target["doc"]
	var original: DrawingRasterTile = doc._nodes[target["layer"]].tiles.get(tile_key_replaced)
	if original == null:
		doc._nodes[target["layer"]].tiles[tile_key_replaced] = DrawingRasterTile.new(64)
	else:
		doc._nodes[target["layer"]].tiles[tile_key_replaced] = original.detached_copy()
	var replaced_bytes: PackedByteArray = snapshot(target)
	var before_replaced_revision: int = doc.revision
	result = replaced.commit()
	check(not result.ok and result.code == "STALE_PIXEL",
		"replaced resident tile rejected even if its bytes match")
	check(doc.revision == before_replaced_revision and snapshot(target) == replaced_bytes,
		"replaced-tile failure publishes no edits")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for stride: int in [16, 30, 64, 256]:
		for erase: bool in [false, true]:
			compare_case(stride, Vector2i(2147483663, -2147483711), erase, false)
		compare_case(stride, Vector2i(-2147483663, 2147483711), false, true)
	reject_partial_commit()
	if failures == 0:
		print("T095_LEGACY_TILE_COMMIT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T095_LEGACY_TILE_COMMIT_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
