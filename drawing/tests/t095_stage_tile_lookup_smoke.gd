extends SceneTree
## T-095: independent signed canonical source-pixel and history oracle for
## the shared _stage() storage lookup. This checks both the power-of-two
## shift/mask path and irregular stride fallback against read_pixel(), not
## another copy of the optimized tile-key calculation.

const ORIGIN_X: int = 1099511627931
const ORIGIN_Y: int = -1099511627951
const AREA: Rect2i = Rect2i(-38, -38, 76, 76)
const STRIDES: Array[int] = [1, 2, 3, 64, 255, 256, 2048]

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_STAGE_LOOKUP_FAILED: " + label)

func snapshot(doc: DrawingDocument, session: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(doc, AREA,
		ORIGIN_X, ORIGIN_Y, AREA.size.x * AREA.size.y, session)
	check(result.ok, "source/preview rendering")
	return result.value.get_data() if result.ok else PackedByteArray()

func run() -> void:
	for stride: int in STRIDES:
		var doc: DrawingDocument = DrawingDocument.new("tile-stage-%d" % stride, stride)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
		var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value
		var bytes: PackedByteArray = PackedByteArray()
		for i: int in range(12 * 12):
			bytes.append_array(PackedByteArray([i % 255, 73, 201,
				0 if i % 9 == 0 else 100]))
		check(seed.apply_region(Rect2i(-6, -6, 12, 12), bytes).ok and seed.commit().ok,
			"seed succeeds stride %d" % stride)
		var original: PackedByteArray = snapshot(doc)
		var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value
		var selection: DrawingSelection = DrawingSelection.new(Rect2i(-35, -35, 70, 70), true)
		check(selection.combine_rectangle(Rect2i(-3, -3, 7, 7), "Subtract"),
			"selection hole stride %d" % stride)
		var expected_before: Dictionary[String, int] = {}
		var expected_after: Dictionary[String, int] = {}
		for y: int in range(-22, 23, 3):
			for x: int in range(-24, 25, 4):
				var global_x: int = ORIGIN_X + x
				var global_y: int = ORIGIN_Y + y
				var source_result: DrawingResult = doc.read_pixel(layer, global_x, global_y)
				check(source_result.ok, "canonical source read stride %d" % stride)
				if not source_result.ok:
					continue
				var old: int = int(source_result.value)
				var rgba: int = 0x00dd2211 if x % 5 == 0 else 0x709ac4e3
				var erase: bool = x % 9 == 0
				var use_verified: bool = (x + y) % 3 == 0
				var expected_new: int = (0 if erase else DrawingEditSession._blend(rgba, old))
				# Independently compute canonical global keys from signed coordinates.
				var pixel_key: String = "%d,%d" % [global_x, global_y]
				var allowed: bool = selection.allows(Vector2i(x, y))
				var staged: DrawingResult = edit._stage(x, y, 0 if erase else rgba,
					selection, true, not erase, old if use_verified else -1)
				check(staged.ok, "pixel stages stride %d" % stride)
				if allowed:
					if expected_new != old:
						expected_before[pixel_key] = old
						expected_after[pixel_key] = expected_new
				# Once-per-stroke overlap must not overwrite the first source-over.
				if allowed:
					check(edit._stage(x, y, 0xff181818, null, true, true).ok,
						"second coverage call stride %d" % stride)
		check(edit._before == expected_before and edit._after == expected_after,
			"staged pixel/historical maps equal independent source reads at stride %d" % stride)
		check(edit.change_count() == expected_after.size(),
			"change count equals independent map stride %d" % stride)
		var preview: PackedByteArray = snapshot(doc, edit)
		check(snapshot(doc) == original, "source remains detached stride %d" % stride)
		var committed: DrawingResult = edit.commit()
		check(committed.ok, "commit succeeds stride %d" % stride)
		if committed.ok:
			check(committed.delta.before == expected_before and
				committed.delta.after == expected_after,
				"canonical history exactly matches original pixel reads stride %d" % stride)
		check(snapshot(doc) == preview, "preview matches commit stride %d" % stride)
		check(doc.undo().ok and snapshot(doc) == original,
			"Undo restores exact seeded bytes stride %d" % stride)
		check(doc.redo().ok and snapshot(doc) == preview,
			"Redo restores exact committed bytes stride %d" % stride)
	print("T095_STAGE_LOOKUP_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
