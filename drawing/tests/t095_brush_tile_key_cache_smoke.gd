extends SceneTree
## T-095: cache hits must not alias adjacent storage tiles, signed anchors,
## non-power-of-two strides, or a source-read failure and its retry.
## Pixel expectations use canonical read_pixel/tile_key64, not the cached key.

const ORIGIN_X: int = 1099511627941
const ORIGIN_Y: int = -1099511627959
const AREA: Rect2i = Rect2i(-36, -32, 73, 65)
const STRIDES: Array[int] = [1, 3, 16, 30, 64, 255, 256, 2048]
const COLOR: int = 0x8056a3d7

class FaultDocument:
	extends DrawingDocument
	var fail_next: bool = false
	func _resolve_chunk(layer: String, key: String) -> DrawingResult:
		if fail_next:
			fail_next = false
			return DrawingResult.failure("INJECTED_TILE", "Source tile unavailable")
		return super._resolve_chunk(layer, key)

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_BRUSH_TILE_KEY_CACHE_FAILED: " + label)

func snapshot(doc: DrawingDocument, edit: DrawingEditSession = null) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(doc, AREA,
		ORIGIN_X, ORIGIN_Y, AREA.size.x * AREA.size.y, edit)
	check(rendered.ok, "render source/preview")
	return rendered.value.get_data() if rendered.ok else PackedByteArray()

func case_stride(stride: int, erase: bool) -> void:
	var doc: DrawingDocument = FaultDocument.new("cache-%d" % stride, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value
	check(seed._stage(-20, -21, 0x0064e531).ok and
		seed._stage(0, 13, 0x7c27a15b).ok and
		seed._stage(20, 21, 0xffa32644).ok and seed.commit().ok,
		"seed opaque, partial alpha and hidden RGB")
	var original: PackedByteArray = snapshot(doc)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-34, -30, 69, 61), true)
	check(selection.combine_rectangle(Rect2i(-5, -4, 11, 9), "Subtract"),
		"selection with an excluded hole")
	var expected_before: Dictionary[String, int] = {}
	var expected_after: Dictionary[String, int] = {}
	var seen: Dictionary[String, bool] = {}
	var previous_tile: String = ""
	var tile_switches: int = 0
	var tile_reuse: int = 0
	# Reverse alternate rows and revisit earlier tiles to catch stale-key use.
	for row: int in range(-23, 24, 2):
		for col_index: int in range(29):
			var x: int = -28 + 2 * (28 - col_index if row % 4 == 1 else col_index)
			var y: int = row
			var world_x: int = ORIGIN_X + x
			var world_y: int = ORIGIN_Y + y
			var key: String = "%d,%d" % [world_x, world_y]
			var allowed: bool = selection.allows(Vector2i(x, y))
			if allowed and not seen.has(key):
				var source: DrawingResult = doc.read_pixel(layer, world_x, world_y)
				check(source.ok, "independent canonical pixel read")
				if source.ok:
					var before: int = int(source.value)
					var after: int = 0 if erase else DrawingEditSession._blend(COLOR, before)
					if after != before:
						expected_before[key] = before
						expected_after[key] = after
				seen[key] = true
			var result: DrawingResult = edit._stage(x, y, 0 if erase else COLOR,
				selection, true, not erase, -1, true)
			check(result.ok, "internal Brush pixel stages")
			if allowed and result.ok:
				var canonical_tile: String = DrawingDocument.TILES.tile_key64(world_x,
					world_y, stride)
				check(edit._brush_cached_tile_key == canonical_tile,
					"cached tile matches independent signed tile key")
				if canonical_tile == previous_tile:
					tile_reuse += 1
				else:
					tile_switches += 1
				previous_tile = canonical_tile
	check(tile_switches > 0 and (stride == 1 or tile_reuse > 0),
		"test exercises tile transitions and spatially adjacent cache hits")
	# Reverse-direction revisit must not change first hit's paint value.
	check(edit._after.is_empty() and edit.change_count() == expected_after.size(),
		"tile-only Brush retains exact changed-pixel count")
	var preview: PackedByteArray = snapshot(doc, edit)
	check(snapshot(doc) == original, "source remains unchanged during preview")
	var committed: DrawingResult = edit.commit()
	check(committed.ok, "tile-local commit succeeds stride=%d erase=%s code=%s msg=%s" % [stride, erase, committed.code, committed.message])
	if committed.ok:
		check(committed.delta.before == expected_before and
			committed.delta.after == expected_after, "history matches canonical pixel reads")
	check(snapshot(doc) == preview, "preview and commit are byte-identical")
	check(doc.undo().ok and snapshot(doc) == original, "Undo restores source RGBA8")
	check(doc.redo().ok and snapshot(doc) == preview, "Redo restores exact brush pixels")

func case_failed_tile_retry() -> void:
	var doc: FaultDocument = FaultDocument.new("cache-failed-read", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value
	check(edit._stage(-20, -20, COLOR, null, true, true, -1, true).ok,
		"first source tile is cached")
	var first: PackedByteArray = snapshot(doc, edit)
	doc.fail_next = true
	var rejected: DrawingResult = edit._stage(20, 20, COLOR, null, true, true, -1, true)
	check(not rejected.ok and rejected.code == "INJECTED_TILE",
		"new tile resolution fails before pixel staging")
	check(edit._brush_cached_tile_key == DrawingDocument.TILES.tile_key64(
		ORIGIN_X + 20, ORIGIN_Y + 20, 16), "cache can move on a rejected resolution")
	check(snapshot(doc, edit) == first and edit.change_count() == 1,
		"failed source tile did not change existing detached preview")
	check(edit._stage(20, 20, COLOR, null, true, true, -1, true).ok and
		edit.change_count() == 2, "retry succeeds with the cached tile key")
	check(edit._stage(-19, -19, COLOR, null, true, true, -1, true).ok and
		edit.change_count() == 3, "return to the previous tile after retry")
	var preview: PackedByteArray = snapshot(doc, edit)
	check(edit.commit().ok and snapshot(doc) == preview,
		"successful retry publishes exact preview")
	check(doc.undo().ok and doc.redo().ok and snapshot(doc) == preview,
		"retry retains correct Undo/Redo history")

func run() -> void:
	for stride: int in STRIDES:
		for erase: bool in [false, true]:
			case_stride(stride, erase)
	case_failed_tile_retry()
	print("T095_BRUSH_TILE_KEY_CACHE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_BRUSH_TILE_KEY_CACHE_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
