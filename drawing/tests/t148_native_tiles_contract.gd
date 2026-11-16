extends SceneTree
## T-148 direct native tile store integration. This deliberately bypasses the
## still-unmigrated DrawingCanvas and consumes no packed per-pixel FFI output.

const RED: int = 0xff0000ff
const SIDE: int = 512
var checks: int = 0
var failures: int = 0


func digest(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T148_NATIVE_TILES_FAILED: " + label)


func make_store(stride: int, layer: String = "ink") -> Object:
	var store: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(int(store.call("tile_abi_version")) == 1, "native tile ABI")
	check(store.call("configure", stride, 0), "configuration succeeds once")
	check(not store.call("configure", stride, 0), "cannot replace active store")
	check(store.call("set_layer_editable", layer, true), "editable layer authorization")
	return store


func make_brush(layer: String, width: float,
		clip: Rect2i = Rect2i(), revision: int = 0) -> Dictionary:
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var opened: Dictionary = brush.call("begin_stroke", layer, preset,
		width, RED, revision, clip)
	check(opened.get("ok", false), "Hokusai preset stroke started")
	return {"object": brush, "handle": int(opened.get("handle", 0))}


func append_and_stage(brush: Dictionary, store: Object, transaction: int,
		samples: PackedFloat32Array, anchor_x: int = 0, anchor_y: int = 0,
		erase: bool = false, expected_ok: bool = true,
		revision: int = 0) -> bool:
	var native: Object = brush["object"]
	var handle: int = brush["handle"]
	var appended: Dictionary = native.call("append_samples", handle, revision, samples)
	check(appended.get("ok", false), "packed native append")
	if not appended.get("ok", false):
		return false
	var needed: Dictionary = native.call("required_tiles", handle, revision,
		int((store.call("stats") as Dictionary).get("stride", 0)), anchor_x, anchor_y)
	check(needed.get("ok", false), "native batch tile discovery: " + str(needed))
	var staged: Dictionary = native.call("apply_tile_batch", store, handle, revision,
		transaction, anchor_x, anchor_y, erase)
	check(bool(staged.get("ok", false)) == expected_ok,
		"native tile staging status: " + str(staged))
	check(not native.call("acknowledge_batch", handle, revision, true),
		"tile batch is already acknowledged atomically")
	return bool(staged.get("ok", false))


func coverage_path() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for row: int in range(9):
		for col: int in range(11):
			var step: int = col if row % 2 == 0 else 10 - col
			points.append(Vector2(0.5 + 511.0 * float(step) / 10.0,
				minf(511.5, 0.5 + 64.0 * row)))
	return points


func read_bytes(store: Object, layer: String, tx: int, ty: int,
		preview: bool) -> PackedByteArray:
	var item: Dictionary = store.call("read_tile", layer, tx, ty, preview)
	check(item.get("ok", false), "RGBA tile is available " + str(Vector2i(tx, ty)))
	check(item.get("format", "") == "straight_rgba8", "tile remains straight RGBA8")
	return item.get("bytes", PackedByteArray())


func test_hokusai_512() -> void:
	var store: Object = make_store(256)
	for ty: int in range(2):
		for tx: int in range(2):
			check(store.call("import_source", "ink", tx, ty, 0, PackedByteArray()),
				"explicit blank source authorization")
	check(not store.call("import_source", "ink", 0, 0, 0, PackedByteArray()),
		"source identities cannot be overwritten")
	var transaction: int = int((store.call("begin_edit", "ink", 0, false) as Dictionary)
		.get("transaction", 0))
	check(transaction > 0, "tile transaction started")
	var brush: Dictionary = make_brush("ink", 96.0, Rect2i(0, 0, SIDE, SIDE))
	var points: PackedVector2Array = coverage_path()
	var start_us: int = Time.get_ticks_usec()
	for index: int in range(0, points.size(), 4):
		var packed: PackedFloat32Array = PackedFloat32Array()
		for j: int in range(index, mini(index + 4, points.size())):
			packed.append_array(PackedFloat32Array([points[j].x, points[j].y, 1.0, 0.01]))
		if not append_and_stage(brush, store, transaction, packed):
			break
	var stage_ms: float = float(Time.get_ticks_usec() - start_us) / 1000.0
	var dirty: Array = store.call("dirty_tiles", transaction)
	check(dirty.size() == 4, "four dirty storage tiles for one 512px gesture")
	for tile: Dictionary in dirty:
		var bounds: Rect2i = tile.get("dirty", Rect2i())
		check(bounds.position.x >= 0 and bounds.position.y >= 0
			and bounds.end.x <= 256 and bounds.end.y <= 256
			and bounds.has_area(), "dirty rectangle is nonempty and tile-local")
		check(tile.get("base_revision", -1) == 0
			and tile.get("generation", -1) == 1,
			"native preview descriptor pins source revision and new generation")
	var hashes: Dictionary = {}
	var covered: int = 0
	for ty: int in range(2):
		for tx: int in range(2):
			var source: PackedByteArray = read_bytes(store, "ink", tx, ty, true)
			check(source.size() == 256 * 256 * 4, "tile byte length")
			for index: int in range(0, source.size(), 4):
				if source[index + 3] > 0:
					covered += 1
			var key: String = "%d,%d" % [tx, ty]
			hashes[key] = digest(source)
	check(covered == SIDE * SIDE, "96px native source covers every one of 262144 pixels")
	var native: Object = brush["object"]
	check(store.call("set_layer_editable", "ink", false), "lock layer before atomic commit")
	check(not (native.call("commit_tiles", store, brush["handle"], 0, transaction)
		as Dictionary).get("ok", true), "locked layer blocks atomic commit")
	check((store.call("stats") as Dictionary).get("revision", -1) == 0,
		"failed commit cannot publish any tiles or advance revision")
	check(read_bytes(store, "ink", 0, 0, false)[3] == 0,
		"failed commit leaves canonical source untouched")
	check(store.call("set_layer_editable", "ink", true), "unlock layer for retry")
	var committed: Dictionary = native.call("commit_tiles", store,
		brush["handle"], 0, transaction)
	check(not native.call("commit_stroke", brush["handle"], 0),
		"atomic publication consumes source brush handle exactly once")
	check(committed.get("ok", false) and int(committed.get("dirty_tiles", 0)) == 4,
		"one atomic four-tile commit")
	var undone: Dictionary = store.call("undo_edit")
	check(undone.get("ok", false), "native undo")
	check(read_bytes(store, "ink", 0, 0, false)[3] == 0,
		"native undo restores pre-brush empty source")
	check((store.call("redo_edit") as Dictionary).get("ok", false), "native redo")
	for ty: int in range(2):
		for tx: int in range(2):
			check(digest(read_bytes(store, "ink", tx, ty, false))
				== hashes["%d,%d" % [tx, ty]], "redo restores exact full RGBA8 tile")
	var stats: Dictionary = store.call("stats")
	check(int(stats.get("pixel_stream_calls", -1)) == 0,
		"no per-pixel Godot boundary calls inside native store")
	check(int(stats.get("bytes_used", 0)) <= 256 * 1024 * 1024,
		"native store resident/draft/history memory budget")
	var first_page: Dictionary = store.call("list_tiles", 0, 2)
	check(first_page.get("ok", false) and first_page.get("next_offset", -1) == 2,
		"bounded native tile enumeration pages")
	check(not (store.call("list_tiles", 0, 129) as Dictionary).get("ok", true),
		"unbounded tile enumeration fails closed")
	var copied: Object = make_store(256)
	var offset: int = 0
	var copied_tiles: int = 0
	while offset >= 0:
		var page: Dictionary = store.call("list_tiles", offset, 2)
		check(page.get("ok", false) and page.get("revision", -1) == 3,
			"canonical snapshot enumerates a single current revision")
		for item: Dictionary in page.get("tiles", []):
			var tile_x: int = int(item.get("tile_x", -1))
			var tile_y: int = int(item.get("tile_y", -1))
			var resident: PackedByteArray = read_bytes(store, "ink", tile_x, tile_y, false)
			check(copied.call("import_source", "ink", tile_x, tile_y, 0, resident),
				"canonical native tile bulk-save / restore byte import")
			check(digest(read_bytes(copied, "ink", tile_x, tile_y, false)) == digest(resident),
				"saved/opened native RGBA8 tile is byte-identical")
			copied_tiles += 1
		offset = int(page.get("next_offset", -1))
	check(copied_tiles == 4, "bulk export/import restores all four signed tile IDs")
	print("T148_FULL_CANVAS side=512 width_px=96 covered=%d native_stage_ms=%.3f dirty=%d stats=%s" % [
		covered, stage_ms, dirty.size(), stats])


func test_cancel_retry_mask_and_hidden() -> void:
	var store: Object = make_store(16)
	for y: int in range(-1, 1):
		for x: int in range(-1, 1):
			if x != 0 or y != 0:
				continue
			check(store.call("import_source", "ink", x, y, 0, PackedByteArray()),
				"partial native source prepared")
	var transaction: int = int((store.call("begin_edit", "ink", 0, true) as Dictionary)
		.get("transaction", 0))
	var brush: Dictionary = make_brush("ink", 8.0, Rect2i(-8, -8, 16, 16))
	var samples: PackedFloat32Array = PackedFloat32Array([-1.5, -1.5, 1.0, 0.01,
		1.5, 1.5, 1.0, 0.01])
	append_and_stage(brush, store, transaction, samples, 0, 0, false, false)
	check((store.call("dirty_tiles", transaction) as Array).is_empty(),
		"missing lazy source leaves no partial tile preview")
	for y: int in range(-1, 1):
		for x: int in range(-1, 1):
			if x == 0 and y == 0:
				continue
			var source: PackedByteArray = PackedByteArray()
			if x == -1 and y == -1:
				source.resize(16 * 16 * 4)
				var offset: int = 255 * 4
				for i: int in range(4):
					source[offset + i] = [0x11, 0x22, 0x33, 0][i]
			check(store.call("import_source", "ink", x, y, 0, source),
				"retry source imported once")
	for y: int in range(-1, 1):
		for x: int in range(-1, 1):
			var mask: PackedByteArray = PackedByteArray()
			mask.resize(16 * 16)
			mask.fill(255)
			if x == -1 and y == -1:
				mask[255] = 0
			check(store.call("import_mask", transaction, "ink", x, y, mask),
				"selection mask tile imported")
	append_and_stage(brush, store, transaction, samples)
	var unchanged: PackedByteArray = read_bytes(store, "ink", -1, -1, true)
	check(unchanged.slice(255 * 4, 256 * 4) == PackedByteArray([0x11, 0x22, 0x33, 0]),
		"masked hidden RGB alpha-zero source survives paint")
	check(store.call("discard_edit", transaction), "cancel native tile draft")
	check((brush["object"] as Object).call("abort_stroke", brush["handle"]),
		"whole native gesture cancel")
	check(read_bytes(store, "ink", 0, 0, false)[3] == 0,
		"cancellation leaves underlying RGBA unmodified")
	check((store.call("stats") as Dictionary).get("revision", -1) == 0,
		"cancel never creates history or revision")


func test_pigment_and_eraser() -> void:
	var store: Object = make_store(32)
	check(store.call("set_layer_editable", "other", true), "second layer registered")
	check(store.call("import_source", "other", 0, 0, 0, PackedByteArray()),
		"other source imported")
	var transaction: int = int((store.call("begin_edit", "other", 0, false) as Dictionary)
		.get("transaction", 0))
	var pigment: Dictionary = make_brush("other", 14.0, Rect2i(0, 0, 32, 32))
	append_and_stage(pigment, store, transaction, PackedFloat32Array([
		13.5, 13.5, 0.5, 0.01, 15.5, 15.5, 1.0, 0.01]))
	var preview: PackedByteArray = read_bytes(store, "other", 0, 0, true)
	var covered: int = 0
	for index: int in range(3, preview.size(), 4):
		if preview[index] > 0:
			covered += 1
	check(covered > 0, "real Hokusai pressure paints native tile")
	var picked: int = -1
	var peak: int = 0
	for index: int in range(3, preview.size(), 4):
		if preview[index] > peak:
			peak = preview[index]
			picked = (index - 3) / 4
	check(picked >= 0, "Hokusai provides an eraser test pixel")
	check(((pigment["object"] as Object).call("commit_tiles", store,
		pigment["handle"], 0, transaction) as Dictionary).get("ok", false),
		"native pigment atomically finalized and published")
	check((store.call("stats") as Dictionary).get("revision", -1) == 1,
		"one canonical revision")
	check((store.call("undo_edit") as Dictionary).get("ok", false), "native pigment undo")
	check((store.call("redo_edit") as Dictionary).get("ok", false), "native pigment redo")
	check(read_bytes(store, "other", 0, 0, false) == preview,
		"native pigment committed and redone exactly")
	# Eraser targets a real pigmented pixel, preserves source history and clears
	# alpha in the Rust tile buffer without a GDScript per-pixel edit loop.
	var begin_erase: Dictionary = store.call("begin_edit", "other", 3, false)
	check(begin_erase.get("ok", false), "eraser starts at canonical post-redo revision")
	var eraser_tx: int = int(begin_erase.get("transaction", 0))
	var eraser: Dictionary = make_brush("other", 8.0, Rect2i(0, 0, 32, 32), 3)
	var ex: float = float(picked % 32) + 0.5
	var ey: float = float(picked / 32) + 0.5
	check(append_and_stage(eraser, store, eraser_tx,
		PackedFloat32Array([ex - 3.0, ey, 1.0, 0.01, ex, ey, 1.0, 0.01,
			ex + 3.0, ey, 1.0, 0.01]),
		0, 0, true, true, 3),
		"native eraser staged opaque pigment")
	var erased: PackedByteArray = read_bytes(store, "other", 0, 0, true)
	var decreased: int = 0
	var grown: int = 0
	for index: int in range(3, preview.size(), 4):
		if erased[index] < preview[index]:
			decreased += 1
		elif erased[index] > preview[index]:
			grown += 1
	check(decreased > 0 and grown == 0, "Hokusai eraser reduces painted alpha")
	check(((eraser["object"] as Object).call("commit_tiles", store,
		eraser["handle"], 3, eraser_tx) as Dictionary).get("ok", false),
		"native eraser atomically committed as one history entry")
	check((store.call("undo_edit") as Dictionary).get("ok", false), "native eraser undo")
	check(read_bytes(store, "other", 0, 0, false) == preview,
		"eraser undo restores exact Hokusai source RGBA")
	check((store.call("redo_edit") as Dictionary).get("ok", false), "native eraser redo")
	check(read_bytes(store, "other", 0, 0, false) == erased,
		"eraser redo restores exact erased RGBA")


func test_large_signed_tile_coordinates() -> void:
	var store: Object = make_store(16)
	var x: int = 1 << 42
	var y: int = -(1 << 42)
	check(store.call("import_source", "ink", x / 16, y / 16, 0,
		PackedByteArray()), "large positive and negative signed source tile")
	var begin: Dictionary = store.call("begin_edit", "ink", 0, false)
	check(begin.get("ok", false), "large signed native transaction")
	var tx: int = int(begin.get("transaction", -1))
	var brush: Dictionary = make_brush("ink", 4.0, Rect2i(0, 0, 16, 16))
	var appended: Dictionary = (brush["object"] as Object).call("append_samples",
		brush["handle"], 0, PackedFloat32Array([8.5, 8.5, 1.0, 0.01,
			9.0, 8.5, 1.0, 0.01]))
	check(appended.get("ok", false), "large signed native pointer accepted")
	var required: Dictionary = (brush["object"] as Object).call("required_tiles",
		brush["handle"], 0, 16, x, y)
	check(required.get("ok", false), "signed source discovery returns tiles")
	var tiles: Array = required.get("tiles", [])
	check(tiles.size() == 1 and tiles[0].get("tile_x", 0) == x / 16 		and tiles[0].get("tile_y", 0) == y / 16,
		"no i32 truncation of large signed native tile IDs")
	var staged: Dictionary = (brush["object"] as Object).call("apply_tile_batch",
		store, brush["handle"], 0, tx, x, y, false)
	check(staged.get("ok", false), "large signed native staging")
	check(not (brush["object"] as Object).call("acknowledge_batch", brush["handle"], 0, true),
		"large signed batch was acknowledged by native staging")
	check(((brush["object"] as Object).call("commit_tiles", store,
		brush["handle"], 0, tx) as Dictionary).get("ok", false),
		"large signed native stroke published atomically")
	check(read_bytes(store, "ink", x / 16, y / 16, false)[(8 * 16 + 8) * 4 + 3] > 0,
		"large signed native stroke changed correct RGBA8 byte")


func test_noop_edit_does_not_advance_revision() -> void:
	var store: Object = make_store(16)
	check(store.call("import_source", "ink", 0, 0, 0, PackedByteArray()),
		"no-op test source authorized")
	var begun: Dictionary = store.call("begin_edit", "ink", 0, false)
	check(begun.get("ok", false), "no-op native transaction opened")
	var brush: Dictionary = make_brush("ink", 4.0, Rect2i(0, 0, 16, 16))
	check(append_and_stage(brush, store, int(begun.get("transaction", 0)),
		PackedFloat32Array([8.5, 8.5, 1.0, 0.01]), 0, 0, true),
		"eraser on blank source stages without errors")
	var committed: Dictionary = (brush["object"] as Object).call("commit_tiles",
		store, brush["handle"], 0, int(begun.get("transaction", 0)))
	check(committed.get("ok", false) and committed.get("no_change", false),
		"empty native eraser gesture commits successfully without edit")
	var stats: Dictionary = store.call("stats")
	check(stats.get("revision", -1) == 0 and stats.get("undo", -1) == 0,
		"no-op cannot create revision or Undo history")


func test_reject_cross_layer_brush() -> void:
	var store: Object = make_store(16, "ink")
	check(store.call("import_source", "ink", 0, 0, 0, PackedByteArray()),
		"layer authority test source available")
	var begun: Dictionary = store.call("begin_edit", "ink", 0, false)
	check(begun.get("ok", false), "authorized ink native edit")
	var brush: Dictionary = make_brush("other", 4.0, Rect2i(0, 0, 16, 16))
	check(not append_and_stage(brush, store, int(begun.get("transaction", 0)),
		PackedFloat32Array([8.5, 8.5, 1.0, 0.01]), 0, 0, false, false),
		"brush from different layer rejected before tile mutation")
	check((store.call("dirty_tiles", int(begun.get("transaction", 0))) as Array)
		.is_empty(), "mismatched layer cannot stage dirty tiles")
	check(store.call("discard_edit", int(begun.get("transaction", 0))),
		"cross-layer transaction discarded")
	check((brush["object"] as Object).call("abort_stroke", brush["handle"]),
		"cross-layer brush cancelled")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"both native extension classes registered")
	if failures == 0:
		test_hokusai_512()
		test_cancel_retry_mask_and_hidden()
		test_pigment_and_eraser()
		test_large_signed_tile_coordinates()
		test_noop_edit_does_not_advance_revision()
		test_reject_cross_layer_brush()
	print("T148_NATIVE_TILES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T148_NATIVE_TILES_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)


func _initialize() -> void:
	call_deferred("run")
