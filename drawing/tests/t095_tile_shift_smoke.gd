extends SceneTree
## T-095: fast signed power-of-two native tile coordinates must be exact.
## The reference stages the same Hokusai deltas through independent _stage().

const ANCHOR_X: int = 1099511627893
const ANCHOR_Y: int = -1099511627907
const AREA: Rect2i = Rect2i(-36, -36, 72, 72)
const CLIP: Rect2i = Rect2i(-31, -30, 62, 60)
const TINT: int = 0x90a04371
const STRIDES: Array[int] = [1, 2, 3, 16, 30, 64, 128, 255, 256, 2048]

class DeltaSource:
	extends RefCounted
	var deltas: PackedInt32Array = PackedInt32Array()
	func preset_segments(_points: PackedVector2Array, _pressure: float) -> PackedInt32Array:
		return deltas

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_TILE_SHIFT_FAILED: " + label)

func make_document(stride: int) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new("shift-%d" % stride, stride)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root").value)
	var seed: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
	var bytes: PackedByteArray = PackedByteArray()
	for index: int in range(9 * 11):
		bytes.append_array(PackedByteArray([index % 255, 119, 73,
			0 if index % 6 == 0 else 114]))
	check(seed.apply_region(Rect2i(-4, -5, 9, 11), bytes).ok and seed.commit().ok,
		"seed committed at stride %d" % stride)
	return {"document": document, "layer": layer}

func snapshot(document: DrawingDocument, session: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, AREA,
		ANCHOR_X, ANCHOR_Y, 72 * 72, session)
	check(result.ok, "signed render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()

func test_signed_math() -> void:
	for stride: int in [1, 2, 4, 16, 64, 256, 2048]:
		var mask: int = stride - 1
		var shift: int = 0
		var size: int = stride
		while size > 1:
			shift += 1
			size >>= 1
		for coordinate: int in [-1099511627907, -2147483649, -stride - 1,
				-stride, -stride + 1, -1, 0, 1, stride - 1, stride,
				stride + 1, 2147483649, 1099511627893]:
			check((coordinate >> shift) == DrawingDocument.TILES.floor_div(coordinate, stride)
				and (coordinate & mask) == posmod(coordinate, stride),
				"stride %d at signed coordinate %d" % [stride, coordinate])

func run() -> void:
	test_signed_math()
	var pressure_path: PackedVector2Array = PackedVector2Array([Vector2(-3.5, 5.5)])
	var mask: DrawingSelection = DrawingSelection.new(AREA, true)
	check(mask.combine_rectangle(Rect2i(-6, -6, 13, 13), "Subtract"),
		"selection subtraction creates a hole")
	var colors: Array[int] = [0x00808080, 0x20aaffcc, 0x80eedd11,
		-1, 0x70102030, 0x00665544, 0x10ffffff]
	for stride: int in STRIDES:
		var optimized: Dictionary = make_document(stride)
		var reference: Dictionary = make_document(stride)
		var doc: DrawingDocument = optimized["document"]
		var oracle_doc: DrawingDocument = reference["document"]
		var edit: DrawingEditSession = doc.begin_edit(optimized["layer"], doc.revision,
			Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
		var oracle: DrawingEditSession = oracle_doc.begin_edit(reference["layer"],
			oracle_doc.revision, Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
		var native: DeltaSource = DeltaSource.new()
		for batch: int in range(3):
			var points: PackedInt32Array = PackedInt32Array()
			for row: int in range(-39, 40, 6):
				for column: int in range(-39, 40, 7):
					points.append(column)
					points.append(row)
					points.append(colors[posmod(column * 3 + row * 5 + batch, colors.size())])
			# Revisit tiles after a different tile and include outside-clip deltas.
			points.append_array(PackedInt32Array([-20, 17, 0x70804020,
				28, -19, -1, -20, 17, 0x60ffffff]))
			native.deltas = points
			check(edit.paint_path_hokusai(pressure_path, TINT, mask, native, CLIP).ok,
				"native preflight stride %d batch %d" % [stride, batch])
			var reference_ok: bool = true
			for index: int in range(0, points.size(), 3):
				var pixel: Vector2i = Vector2i(points[index], points[index + 1])
				if not CLIP.has_point(pixel) or not mask.allows(pixel):
					continue
				var pigment: int = int(points[index + 2]) & 0xffffffff
				var alpha: int = (((pigment >> 24) & 255) * ((TINT >> 24) & 255) + 127) / 255
				var rgba: int = (pigment & 0xffffff) | (alpha << 24)
				if not oracle._stage(pixel.x, pixel.y, rgba, null, false, true).ok:
					reference_ok = false
					break
			check(reference_ok, "per-pixel oracle stride %d batch %d" % [stride, batch])
			check(edit.change_count() == oracle.change_count(),
				"change count parity stride %d batch %d" % [stride, batch])
			check(snapshot(doc, edit) == snapshot(oracle_doc, oracle),
				"preview parity stride %d batch %d" % [stride, batch])
		var preview: PackedByteArray = snapshot(doc, edit)
		var result: DrawingResult = edit.commit()
		var expected: DrawingResult = oracle.commit()
		check(result.ok and expected.ok, "both commits succeed stride %d" % stride)
		if result.ok and expected.ok:
			check(result.delta.before == expected.delta.before and
				result.delta.after == expected.delta.after,
				"history contents match old path stride %d" % stride)
		check(snapshot(doc) == snapshot(oracle_doc) and snapshot(doc) == preview,
			"committed bytes equal source and preview stride %d" % stride)
		check(doc.undo().ok and oracle_doc.undo().ok and
			snapshot(doc) == snapshot(oracle_doc),
			"Undo parity stride %d" % stride)
		check(doc.redo().ok and oracle_doc.redo().ok and
			snapshot(doc) == snapshot(oracle_doc),
			"Redo parity stride %d" % stride)
	print("T095_TILE_SHIFT_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
