extends SceneTree
## T-095: independent original-Geometry2D oracle for the optimized oblique
## swept hard Brush/Eraser, including source alpha, selection, cancellation and
## signed storage boundaries. Never use the optimized distance predicate here.

const VIEW: Rect2i = Rect2i(-82, -82, 164, 164)
const PAINT: int = 0x806c35e1
var CASES: Array[Dictionary] = [
	{"width": 60.0, "erase": false, "anchor": Vector2i(0, 0), "mask": true,
		"path": PackedVector2Array([Vector2(-33.5, -26.5), Vector2(28.25, 22.75),
			Vector2(-12.75, 31.25), Vector2(36.5, -20.5)])},
	{"width": 60.0, "erase": true, "anchor": Vector2i(2147483673, -2147483711),
		"mask": false, "path": PackedVector2Array([Vector2(-47.5, -45.5),
			Vector2(28.5, 36.5), Vector2(-31.5, 29.5)])},
	{"width": 7.0, "erase": false, "anchor": Vector2i(-2147483658, 2147483656),
		"mask": true, "path": PackedVector2Array([Vector2(-32.125, -30.25),
			Vector2(31.625, 33.75), Vector2(31.625, 33.75),
			Vector2(-24.25, 30.5)])},
	{"width": 29.0, "erase": false, "anchor": Vector2i(0, 0),
		"mask": false, "path": PackedVector2Array([Vector2(0.0, 0.0),
			Vector2(0.0, 0.0), Vector2(45.0, -41.25), Vector2(45.0, 30.25)])},
]

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_OBLIQUE_GEOMETRY_FAILED: " + label)

func make_document(label: String, origin: Vector2i) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, origin.x, origin.y).value
	var bytes: PackedByteArray = PackedByteArray()
	for i: int in range(12 * 12):
		bytes.append_array(PackedByteArray([i % 255, 83, 197,
			0 if i % 11 == 0 else 140]))
	check(seed.apply_region(Rect2i(-6, -6, 12, 12), bytes).ok and seed.commit().ok,
		label + " seeded with hidden RGB and alpha")
	return {"doc": doc, "layer": layer}

func snapshot(target: Dictionary, origin: Vector2i, edit: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(target["doc"], VIEW,
		origin.x, origin.y, VIEW.size.x * VIEW.size.y, edit)
	check(result.ok, "render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()

func original_sweep(edit: DrawingEditSession, path: PackedVector2Array,
		width: float, erase: bool, selection: DrawingSelection,
		clip: Rect2i) -> bool:
	var radius: float = width * 0.5
	for index: int in range(path.size()):
		var finish: Vector2 = path[index]
		var start: Vector2 = path[index - 1] if index > 0 else finish
		var left: int = maxi(floori(minf(start.x, finish.x) - radius - 0.5), clip.position.x)
		var right: int = mini(ceili(maxf(start.x, finish.x) + radius + 0.5), clip.end.x)
		var top: int = maxi(floori(minf(start.y, finish.y) - radius - 0.5), clip.position.y)
		var bottom: int = mini(ceili(maxf(start.y, finish.y) + radius + 0.5), clip.end.y)
		for y: int in range(top, bottom):
			for x: int in range(left, right):
				var point: Vector2 = Vector2(x + 0.5, y + 0.5)
				var nearest: Vector2 = start if start == finish else \
					Geometry2D.get_closest_point_to_segment(point, start, finish)
				if point.distance_squared_to(nearest) > radius * radius:
					continue
				if not edit._stage(x, y, 0 if erase else PAINT, selection, true, not erase).ok:
					return false
	return true

func run() -> void:
	var clip: Rect2i = Rect2i(-54, -55, 110, 109)
	for index: int in range(CASES.size()):
		var spec: Dictionary = CASES[index]
		var origin: Vector2i = spec["anchor"]
		var optimized: Dictionary = make_document("optimized-%d" % index, origin)
		var reference: Dictionary = make_document("original-%d" % index, origin)
		var doc: DrawingDocument = optimized["doc"]
		var reference_doc: DrawingDocument = reference["doc"]
		var edit: DrawingEditSession = doc.begin_edit(optimized["layer"],
			doc.revision, Transform2D.IDENTITY, origin.x, origin.y).value
		var oracle: DrawingEditSession = reference_doc.begin_edit(reference["layer"],
			reference_doc.revision, Transform2D.IDENTITY, origin.x, origin.y).value
		var selection: DrawingSelection = null
		if spec["mask"]:
			selection = DrawingSelection.new(Rect2i(-55, -55, 110, 110), true)
			check(selection.combine_rectangle(Rect2i(-7, -7, 14, 14), "Subtract"),
				"selection contains hole")
		var path: PackedVector2Array = spec["path"]
		check(edit.paint_path(path, PAINT, spec["width"], spec["erase"],
			selection, 1048576, clip).ok, "optimized stroke %d succeeds" % index)
		check(original_sweep(oracle, path, spec["width"], spec["erase"],
			selection, clip), "original Geometry2D reference %d succeeds" % index)
		check(edit._brush_deferred and edit._after.is_empty() and edit._before.is_empty()
			and edit._brush_change_count == oracle._after.size(),
			"deferred Brush retains exact changed-pixel count without global keys %d" % index)
		check(edit.change_count() == oracle.change_count(),
			"coverage size matches %d" % index)
		var preview: PackedByteArray = snapshot(optimized, origin, edit)
		check(preview == snapshot(reference, origin, oracle),
			"detached preview matches original Geometry2D %d" % index)
		var committed: DrawingResult = edit.commit()
		var expected: DrawingResult = oracle.commit()
		check(committed.ok and expected.ok, "commit succeeds %d" % index)
		if committed.ok and expected.ok:
			check(committed.delta.before == expected.delta.before and
				committed.delta.after == expected.delta.after,
				"history bytes match %d" % index)
		check(snapshot(optimized, origin) == preview and
			snapshot(optimized, origin) == snapshot(reference, origin),
			"source and committed pixels match preview %d" % index)
		check(doc.undo().ok and reference_doc.undo().ok and
			snapshot(optimized, origin) == snapshot(reference, origin),
			"Undo parity %d" % index)
		check(doc.redo().ok and reference_doc.redo().ok and
			snapshot(optimized, origin) == snapshot(reference, origin),
			"Redo parity %d" % index)
	print("T095_OBLIQUE_GEOMETRY_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
