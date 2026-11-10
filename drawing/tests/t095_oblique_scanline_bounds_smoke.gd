extends SceneTree
## Independent T-095 full-rectangle Geometry2D oracle for conservative
## oblique scanline bounds. Never use the optimized x-range formula here.
const COLOR: int = 0x91b5496c
const FRAME: Rect2i = Rect2i(-95, -93, 190, 186)

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_OBLIQUE_SCANLINE_FAILED: " + label)

func make_document(label: String, anchor: Vector2i, stride: int) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var bytes := PackedByteArray()
	for i: int in range(14 * 14):
		bytes.append_array(PackedByteArray([i % 256, (i * 37) % 256,
			(i * 19 + 3) % 256, 0 if i % 7 == 0 else (255 if i % 3 == 0 else 77)]))
	check(seed.apply_region(Rect2i(-7, -7, 14, 14), bytes).ok and seed.commit().ok,
		label + " seed RGBA8/hidden RGB")
	return {"doc": doc, "layer": layer}

func snapshot(model: Dictionary, anchor: Vector2i, frame: Rect2i,
		edit: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(model["doc"], frame,
		anchor.x, anchor.y, frame.size.x * frame.size.y, edit)
	check(result.ok, "render bytes")
	return result.value.get_data() if result.ok else PackedByteArray()

func reference_paint(edit: DrawingEditSession, path: PackedVector2Array, width: float,
		erase: bool, selection: DrawingSelection, clip: Rect2i) -> bool:
	var radius: float = width * 0.5
	for i: int in range(path.size()):
		var finish: Vector2 = path[i]
		var start: Vector2 = path[i - 1] if i > 0 else finish
		var left: int = maxi(floori(minf(start.x, finish.x) - radius - 0.5), clip.position.x)
		var top: int = maxi(floori(minf(start.y, finish.y) - radius - 0.5), clip.position.y)
		var right: int = mini(ceili(maxf(start.x, finish.x) + radius + 0.5), clip.end.x)
		var bottom: int = mini(ceili(maxf(start.y, finish.y) + radius + 0.5), clip.end.y)
		for y: int in range(top, bottom):
			for x: int in range(left, right):
				var center: Vector2 = Vector2(x + 0.5, y + 0.5)
				var nearest: Vector2 = start if start == finish else \
					Geometry2D.get_closest_point_to_segment(center, start, finish)
				if center.distance_squared_to(nearest) > radius * radius:
					continue
				var staged: DrawingResult = edit._stage(x, y, 0 if erase else COLOR,
					selection, true, not erase)
				if not staged.ok:
					return false
	return true

func one_case(i: int, path: PackedVector2Array, width: float,
		erase: bool = false, split: bool = false, large: bool = false) -> void:
	var anchor: Vector2i = Vector2i(-2147483941, 2147483997) if i % 2 == 0 else \
		Vector2i(2147483941, -2147483997)
	var stride: int = 30 if i % 3 == 0 else (7 if i % 3 == 1 else 64)
	var label: String = "diagonal-%d" % i
	var fast: Dictionary = make_document(label + "-fast", anchor, stride)
	var reference: Dictionary = make_document(label + "-reference", anchor, stride)
	var doc: DrawingDocument = fast["doc"]
	var original: DrawingDocument = reference["doc"]
	var edit: DrawingEditSession = doc.begin_edit(fast["layer"], doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var oracle: DrawingEditSession = original.begin_edit(reference["layer"],
		original.revision, Transform2D.IDENTITY, anchor.x, anchor.y).value
	var frame: Rect2i = Rect2i(10000010, -10000090, 65, 65) if large else FRAME
	var clip: Rect2i = frame if i % 2 == 0 else \
		Rect2i(frame.position.x + 9, frame.position.y + 13,
			frame.size.x - 17, frame.size.y - 27)
	var selection: DrawingSelection = null
	if not large and i % 3 != 2:
		selection = DrawingSelection.new(Rect2i(-87, -86, 175, 172), true)
		check(selection.combine_rectangle(Rect2i(-13, -11, 26, 22), "Subtract"),
			label + " selection island/hole")
	var max_candidates: int = 5000 if split else 1048576
	var staged: DrawingResult = edit.paint_path(path, COLOR, width, erase,
		selection, max_candidates, clip)
	check(staged.ok, label + " optimized geometry")
	check(reference_paint(oracle, path, width, erase, selection, clip),
		label + " full-rectangle reference")
	if not staged.ok:
		return
	check(edit.change_count() == oracle.change_count(), label + " changed-pixel count")
	var preview: PackedByteArray = snapshot(fast, anchor, frame, edit)
	check(preview == snapshot(reference, anchor, frame, oracle), label + " preview parity")
	var result: DrawingResult = edit.commit()
	var expected: DrawingResult = oracle.commit()
	# Erasing blank pixels is a legal no-op, not a commit failure.
	check((result.ok and expected.ok) or
		(result.code == "NO_CHANGE" and expected.code == "NO_CHANGE"),
		label + " matching commits/no-change")
	if result.ok and expected.ok:
		check(result.delta.before == expected.delta.before and
			result.delta.after == expected.delta.after, label + " before/after history")
	check(snapshot(fast, anchor, frame) == preview and
		snapshot(fast, anchor, frame) == snapshot(reference, anchor, frame),
		label + " committed bytes")
	check(doc.undo().ok and original.undo().ok, label + " undo")
	check(snapshot(fast, anchor, frame) == snapshot(reference, anchor, frame),
		label + " undo bytes")
	check(doc.redo().ok and original.redo().ok, label + " redo")
	check(snapshot(fast, anchor, frame) == preview and
		snapshot(fast, anchor, frame) == snapshot(reference, anchor, frame),
		label + " redo bytes")

func run() -> void:
	var cases: Array[Dictionary] = [
		{"p": [Vector2(-76.125, -75.375), Vector2(79.25, 73.625)], "w": 60.0},
		{"p": [Vector2(80.125, 74.875), Vector2(-77.75, -76.125)], "w": 60.0, "e": true},
		{"p": [Vector2(-75.5, 78.75), Vector2(76.625, -76.875)], "w": 60.0},
		{"p": [Vector2(76.75, -77.375), Vector2(-76.125, 76.125)], "w": 60.0, "e": true},
		{"p": [Vector2(-73.75, -7.25), Vector2(74.875, 11.125)], "w": 60.0},
		{"p": [Vector2(73.625, 11.125), Vector2(-74.75, -7.375)], "w": 1.0},
		{"p": [Vector2(-6.5, -81.875), Vector2(8.125, 82.375)], "w": 60.0},
		{"p": [Vector2(8.25, 83.75), Vector2(-7.5, -84.25)], "w": 1.25, "e": true},
		{"p": [Vector2(-84.75, 26.375), Vector2(84.625, -21.125)], "w": 31.3},
		{"p": [Vector2(84.375, -21.125), Vector2(-84.875, 26.375)], "w": 31.3, "e": true},
		{"p": [Vector2(-57.125, -67.375), Vector2(36.75, 78.125)], "w": 0.75},
		{"p": [Vector2(36.75, 78.125), Vector2(-57.125, -67.375)], "w": 0.75, "e": true},
		{"p": [Vector2(-82.25, -76.75), Vector2(79.25, 73.5)], "w": 17.0, "split": true},
		{"p": [Vector2(80.25, -76.5), Vector2(-78.125, 77.5)], "w": 60.0, "split": true},
		{"p": [Vector2(-72.125, 12.875), Vector2(34.625, -71.125),
			Vector2(74.375, 63.125)], "w": 60.0, "split": true},
		{"p": [Vector2(68.125, 68.625), Vector2(-72.375, -51.125),
			Vector2(70.125, -73.625)], "w": 8.0},
		{"p": [Vector2(-0.375, -0.875), Vector2(0.125, 0.125)], "w": 60.0},
		{"p": [Vector2(0.375, 0.625), Vector2(-0.125, -0.125)], "w": 0.75, "e": true},
		{"p": [Vector2(-75.125, 0.125), Vector2(76.625, 0.12505)], "w": 60.0},
		{"p": [Vector2(76.625, 0.12505), Vector2(-75.125, 0.125)], "w": 1.0, "e": true},
		{"p": [Vector2(10000015.0, -10000073.0),
			Vector2(10000060.0, -10000035.0)], "w": 7.0, "large": true},
		{"p": [Vector2(10000055.0, -10000036.0),
			Vector2(10000015.0, -10000075.0)], "w": 7.0, "e": true, "large": true},
	]
	for i: int in range(cases.size()):
		var spec: Dictionary = cases[i]
		var path := PackedVector2Array(spec["p"])
		one_case(i, path, spec["w"], bool(spec.get("e", false)),
			bool(spec.get("split", false)), bool(spec.get("large", false)))
	print("T095_OBLIQUE_SCANLINE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_OBLIQUE_SCANLINE_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
