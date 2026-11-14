extends SceneTree
## T-095: independent full bounding-box Geometry2D oracle for clipped,
## stationary, horizontal and vertical hard Brush/Eraser candidate scans.
## Do not reuse the optimized scanline bounds in this reference.

const VIEW: Rect2i = Rect2i(-86, -83, 173, 167)
const COLOR: int = 0x8e3bcf57
var CASES: Array[Dictionary] = [
	{"path": PackedVector2Array([Vector2(-55.25, -20.5), Vector2(52.75, -20.5)]), "width": 60.0},
	{"path": PackedVector2Array([Vector2(38.25, 5.5), Vector2(-39.75, 5.5)]), "width": 60.0, "erase": true},
	{"path": PackedVector2Array([Vector2(-21.5, -49.75), Vector2(-21.5, 50.25)]), "width": 60.0},
	{"path": PackedVector2Array([Vector2(2.125, 51.75), Vector2(2.125, -58.5)]), "width": 60.0, "erase": true},
	{"path": PackedVector2Array([Vector2(-0.5, 0.5)]), "width": 60.0},
	{"path": PackedVector2Array([Vector2(0.125, -0.125), Vector2(0.125, -0.125)]), "width": 7.0, "erase": true},
	{"path": PackedVector2Array([Vector2(-62.5, 13.25), Vector2(60.5, 13.25)]), "width": 1.0},
	{"path": PackedVector2Array([Vector2(16.625, -55.125), Vector2(16.625, 61.875)]), "width": 31.3},
	{"path": PackedVector2Array([Vector2(-50.5, -19.5), Vector2(24.25, -19.5), Vector2(24.25, 39.75)]), "width": 61.0, "erase": true},
	{"path": PackedVector2Array([Vector2(-20.5, -5.5), Vector2(-20.5, 35.5), Vector2(35.5, 35.5), Vector2(35.5, -12.5)]), "width": 60.0},
	{"path": PackedVector2Array([Vector2(0.125, -1.875)]), "width": 2.0, "erase": true},
	{"path": PackedVector2Array([Vector2(10.75, 25.25), Vector2(10.75, -28.25)]), "width": 2.0},
]

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_AXIS_SCANLINE_FAILED: " + label)

func build_doc(label: String, anchor: Vector2i, stride: int) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var bytes: PackedByteArray = PackedByteArray()
	for index: int in range(14 * 14):
		bytes.append_array(PackedByteArray([index % 255, 97, 151,
			0 if index % 7 == 0 else (211 if index % 3 == 0 else 64)]))
	check(seed.apply_region(Rect2i(-7, -7, 14, 14), bytes).ok and seed.commit().ok,
		label + " seed RGBA8")
	return {"doc": doc, "layer": layer}

func snapshot(target: Dictionary, anchor: Vector2i, edit: DrawingEditSession = null) -> PackedByteArray:
	var raster: DrawingResult = DrawingRenderer.render(target["doc"], VIEW,
		anchor.x, anchor.y, VIEW.size.x * VIEW.size.y, edit)
	check(raster.ok, "render RGBA8")
	return raster.value.get_data() if raster.ok else PackedByteArray()

func brute_force(edit: DrawingEditSession, path: PackedVector2Array, width: float,
		erase: bool, selection: DrawingSelection, clip: Rect2i) -> bool:
	var radius: float = width * 0.5
	for index: int in range(path.size()):
		var finish: Vector2 = path[index]
		var start: Vector2 = path[index - 1] if index > 0 else finish
		var left: int = maxi(floori(minf(start.x, finish.x) - radius - 0.5), clip.position.x)
		var top: int = maxi(floori(minf(start.y, finish.y) - radius - 0.5), clip.position.y)
		var right: int = mini(ceili(maxf(start.x, finish.x) + radius + 0.5), clip.end.x)
		var bottom: int = mini(ceili(maxf(start.y, finish.y) + radius + 0.5), clip.end.y)
		for y: int in range(top, bottom):
			for x: int in range(left, right):
				var center: Vector2 = Vector2(x + 0.5, y + 0.5)
				var closest: Vector2 = start if start == finish else \
					Geometry2D.get_closest_point_to_segment(center, start, finish)
				if center.distance_squared_to(closest) > radius * radius:
					continue
				if not edit._stage(x, y, 0 if erase else COLOR, selection, true, not erase).ok:
					return false
	return true

## View-relative coordinates near 10 million force the conservative fallback.
## The signed document anchor still shifts these pixels outside 32-bit world
## coordinates, and the full-bounds oracle must agree byte-for-byte.
func large_view_fallback() -> void:
	var view: Rect2i = Rect2i(9999990, 9999990, 80, 80)
	var anchor: Vector2i = Vector2i(-2147483745, 2147483801)
	var paths: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(10000012.5, 10000023.25)]),
		PackedVector2Array([Vector2(10000000.5, 10000023.25),
			Vector2(10000048.5, 10000023.25)]),
		PackedVector2Array([Vector2(10000023.25, 10000001.5),
			Vector2(10000023.25, 10000049.5)])
	]
	for index: int in range(paths.size()):
		var fast: Dictionary = build_doc("high-coordinate-fast-%d" % index, anchor, 30)
		var baseline: Dictionary = build_doc("high-coordinate-reference-%d" % index, anchor, 30)
		var doc: DrawingDocument = fast["doc"]
		var reference: DrawingDocument = baseline["doc"]
		var edit: DrawingEditSession = doc.begin_edit(fast["layer"], doc.revision,
			Transform2D.IDENTITY, anchor.x, anchor.y).value
		var oracle: DrawingEditSession = reference.begin_edit(baseline["layer"],
			reference.revision, Transform2D.IDENTITY, anchor.x, anchor.y).value
		var path: PackedVector2Array = paths[index]
		check(edit.paint_path(path, COLOR, 7.0, false, null, 5000, view).ok,
			"large view optimized %d" % index)
		check(brute_force(oracle, path, 7.0, false, null, view),
			"large view original %d" % index)
		var fast_preview: DrawingResult = DrawingRenderer.render(doc, view,
			anchor.x, anchor.y, view.size.x * view.size.y, edit)
		var oracle_preview: DrawingResult = DrawingRenderer.render(reference, view,
			anchor.x, anchor.y, view.size.x * view.size.y, oracle)
		check(fast_preview.ok and oracle_preview.ok and
			fast_preview.value.get_data() == oracle_preview.value.get_data(),
			"large view detached preview %d" % index)
		var fast_delta: DrawingResult = edit.commit()
		var oracle_delta: DrawingResult = oracle.commit()
		check(fast_delta.ok and oracle_delta.ok and fast_delta.delta.before == oracle_delta.delta.before
			and fast_delta.delta.after == oracle_delta.delta.after,
			"large view exact history %d" % index)
		check(doc.undo().ok and reference.undo().ok and doc.redo().ok
			and reference.redo().ok, "large view Undo/Redo %d" % index)


func run() -> void:
	for index: int in range(CASES.size()):
		var spec: Dictionary = CASES[index]
		var anchor: Vector2i = Vector2i(2147483789, -2147483721) if index % 2 == 1 \
			else Vector2i(-2147483745, 2147483801)
		var stride: int = 30 if index % 3 == 0 else 64
		var fast: Dictionary = build_doc("scan-fast-%d" % index, anchor, stride)
		var baseline: Dictionary = build_doc("scan-oracle-%d" % index, anchor, stride)
		var doc: DrawingDocument = fast["doc"]
		var reference: DrawingDocument = baseline["doc"]
		var edit: DrawingEditSession = doc.begin_edit(fast["layer"], doc.revision,
			Transform2D.IDENTITY, anchor.x, anchor.y).value
		var oracle: DrawingEditSession = reference.begin_edit(baseline["layer"], reference.revision,
			Transform2D.IDENTITY, anchor.x, anchor.y).value
		var selection: DrawingSelection = null
		if index % 3 != 2 and not bool(spec.get("erase", false)):
			selection = DrawingSelection.new(Rect2i(-70, -67, 141, 135), true)
			check(selection.combine_rectangle(Rect2i(-13, -9, 26, 18), "Subtract"),
				"selection hole %d" % index)
		var clip: Rect2i = Rect2i(-67, -65, 135, 130)
		var path: PackedVector2Array = spec["path"]
		var width: float = spec["width"]
		var erase: bool = bool(spec.get("erase", false))
		# Some long 60px spans exceed a 5000-candidate cap and must split;
		# the geometric oracle intentionally computes their whole footprint.
		check(edit.paint_path(path, COLOR, width, erase, selection, 5000, clip).ok,
			"optimized clipped/split stroke %d" % index)
		check(brute_force(oracle, path, width, erase, selection, clip),
			"original full rectangle sweep %d" % index)
		check(edit.change_count() == oracle.change_count(),
			"exact changed pixel count %d" % index)
		var preview: PackedByteArray = snapshot(fast, anchor, edit)
		check(preview == snapshot(baseline, anchor, oracle),
			"independent preview parity %d" % index)
		var fast_commit: DrawingResult = edit.commit()
		var slow_commit: DrawingResult = oracle.commit()
		check(fast_commit.ok and slow_commit.ok,
			"both commits %d" % index)
		if fast_commit.ok and slow_commit.ok:
			check(fast_commit.delta.before == slow_commit.delta.before and
				fast_commit.delta.after == slow_commit.delta.after,
				"canonical RGBA8 history parity %d" % index)
		check(snapshot(fast, anchor) == preview and
			snapshot(fast, anchor) == snapshot(baseline, anchor),
			"published source equals preview and reference %d" % index)
		check(doc.undo().ok and reference.undo().ok and
			snapshot(fast, anchor) == snapshot(baseline, anchor),
			"Undo bytes %d" % index)
		check(doc.redo().ok and reference.redo().ok and
			snapshot(fast, anchor) == preview and
			snapshot(fast, anchor) == snapshot(baseline, anchor),
			"Redo bytes %d" % index)
	large_view_fallback()
	print("T095_AXIS_SCANLINE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_AXIS_SCANLINE_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
