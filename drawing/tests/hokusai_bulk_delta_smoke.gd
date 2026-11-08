extends SceneTree
## T-095: batch-native pigment deltas must preserve the original pixel-by-pixel
## transaction oracle, including signed 64-bit anchors and atomic failures.

const CANVAS: Rect2i = Rect2i(-20, -20, 40, 40)
const CLIP: Rect2i = Rect2i(-15, -15, 30, 30)
const TINT: int = 0x804060e0
const BASE: int = 0x704020e0
const ORIGIN_X: int = 2147483651
const ORIGIN_Y: int = -2147483671

class DeltaSource:
	extends RefCounted
	var delta: PackedInt32Array
	var calls: int = 0

	func preset_segments(_path: PackedVector2Array, _pressure: float) -> PackedInt32Array:
		calls += 1
		return delta

class ReadFaultDocument:
	extends DrawingDocument
	var rejected_key: String = ""

	func _resolve_chunk(target_layer: String, key: String) -> DrawingResult:
		if key == rejected_key:
			return DrawingResult.failure("INJECTED_TILE", "Simulated lazy source failure")
		return super._resolve_chunk(target_layer, key)


var checks: int = 0
var failures: int = 0


func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_BULK_DELTA_FAILED: " + name)


func make_document(name: String) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var edit: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	var source_bytes: PackedByteArray = PackedByteArray()
	for i: int in range(108):
		source_bytes.append_array(PackedByteArray([70, 30, 200, 112]))
	check(edit.apply_region(Rect2i(-6, -4, 12, 9), source_bytes).ok,
		"semi-transparent source region seeded")
	check(edit.commit().ok, "source region committed")
	return {"doc": document, "layer": layer}


func preview(document: DrawingDocument, session: DrawingEditSession) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(document, CANVAS,
		ORIGIN_X, ORIGIN_Y, 1048576, session)
	check(rendered.ok, "detached preview render succeeded")
	return rendered.value.get_data() if rendered.ok else PackedByteArray()


func legacy_oracle(session: DrawingEditSession, deltas: PackedInt32Array,
		mask: DrawingSelection) -> void:
	for index: int in range(0, deltas.size(), 3):
		var point: Vector2i = Vector2i(deltas[index], deltas[index + 1])
		if not CLIP.has_point(point) or not mask.allows(point):
			continue
		var pigment: int = int(deltas[index + 2]) & 0xffffffff
		var opacity: int = ((pigment >> 24) & 255) * ((TINT >> 24) & 255)
		var color: int = (pigment & 0xffffff) | (int((opacity + 127) / 255) << 24)
		check(session._stage(point.x, point.y, color, null, false, true).ok,
			"reference pixel staged")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var optimized: Dictionary = make_document("bulk-native")
	var reference: Dictionary = make_document("per-pixel-oracle")
	var optimized_doc: DrawingDocument = optimized["doc"]
	var reference_doc: DrawingDocument = reference["doc"]
	var stage: DrawingEditSession = optimized_doc.begin_edit(optimized["layer"], optimized_doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	var oracle: DrawingEditSession = reference_doc.begin_edit(reference["layer"], reference_doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-14, -14, 29, 29), true)
	check(mask.combine_rectangle(Rect2i(-3, -3, 7, 7), "Subtract"),
		"signed selection hole created")
	var source: DeltaSource = DeltaSource.new()
	var deltas: Array[PackedInt32Array] = [
		PackedInt32Array([-15, -15, 0x7044aacc, -10, -3, 0x503399ff,
			-4, 2, 0x7f1888ac, 0, 0, -1, 5, 3, 0x601010f0,
			14, 14, 0x50101011, 15, 15, 0x50101011]),
		PackedInt32Array([-10, -3, 0x9044aa11, -4, 2, 0x00303030,
			5, 3, 0x00556677, 6, 6, 0x7fffffff, -8, -6, -1]),
		PackedInt32Array([-10, -3, 0x10556677, 5, 3, 0x601010f0,
			6, 6, 0x40ffffff, -7, -4, 0x70909090])]
	var path: PackedVector2Array = PackedVector2Array([Vector2(-12.5, -3.5)])
	for batch: int in range(deltas.size()):
		source.delta = deltas[batch]
		var changed: DrawingResult = stage.paint_path_hokusai(path, TINT, mask, source, CLIP)
		check(changed.ok, "native batch %d accepted" % batch)
		legacy_oracle(oracle, source.delta, mask)
		check(preview(optimized_doc, stage) == preview(reference_doc, oracle),
			"batch %d preview byte-exact against original staging" % batch)
		check(stage.change_count() == oracle.change_count(),
			"batch %d changed-pixel count matches" % batch)
		check(optimized_doc.revision == 2 and reference_doc.revision == 2,
			"batch %d has no premature history" % batch)
	check(source.calls == deltas.size(), "one native call per batch")
	check(stage.hokusai_perf["pixels"] == 16 and stage.hokusai_perf["stage_us"] > 0,
		"native transfer and batch-stage counters retained")
	var stable_preview: PackedByteArray = preview(optimized_doc, stage)
	var stable_count: int = stage.change_count()
	source.delta = PackedInt32Array([3, 4, 0x60ffffff, 1073741824, 0, 0x70ffffff])
	var invalid: DrawingResult = stage.paint_path_hokusai(path, TINT, mask, source, CLIP)
	check(not invalid.ok and invalid.code == "COORD_RANGE" and stage.change_count() == stable_count,
		"invalid trailing coordinate rejects complete batch before mutation")
	check(preview(optimized_doc, stage) == stable_preview,
		"failed batch retains prior preview and tile stamps")
	source.delta = PackedInt32Array([0, 0])
	invalid = stage.paint_path_hokusai(path, TINT, mask, source, CLIP)
	check(not invalid.ok and invalid.code == "HOKUSAI_LIMIT" and stage.change_count() == stable_count,
		"malformed native transfer rejects before staging")
	source.delta = PackedInt32Array([12, -11, 0x5aff0000])
	check(stage.paint_path_hokusai(path, TINT, mask, source, CLIP).ok,
		"valid batch can follow a rejected batch")
	legacy_oracle(oracle, source.delta, mask)
	check(preview(optimized_doc, stage) == preview(reference_doc, oracle),
		"valid retry retains exact pigment and detached mask")
	var preview_bytes: PackedByteArray = preview(optimized_doc, stage)
	check(stage.commit().ok and oracle.commit().ok, "one commit per session succeeds")
	var actual: DrawingResult = DrawingRenderer.render(optimized_doc, CANVAS, ORIGIN_X, ORIGIN_Y)
	var expected: DrawingResult = DrawingRenderer.render(reference_doc, CANVAS, ORIGIN_X, ORIGIN_Y)
	check(actual.ok and expected.ok and actual.value.get_data() == expected.value.get_data() \
		and actual.value.get_data() == preview_bytes,
		"signed large-anchor committed image matches old pixel oracle and preview")
	check(optimized_doc.undo().ok and optimized_doc.redo().ok and
		DrawingRenderer.render(optimized_doc, CANVAS, ORIGIN_X, ORIGIN_Y).value.get_data() == expected.value.get_data(),
		"one undo/redo roundtrip restores identical signed pixels")
	var cancelled: DrawingEditSession = optimized_doc.begin_edit(optimized["layer"], optimized_doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	source.delta = PackedInt32Array([11, 11, 0x70abcdef])
	check(cancelled.paint_path_hokusai(path, TINT, mask, source, CLIP).ok and
		cancelled.change_count() > 0, "pending native pigment is staged before cancel")
	var prior_revision: int = optimized_doc.revision
	cancelled.cancel()
	check(optimized_doc.revision == prior_revision and cancelled.preview_tile("0,0").is_empty() \
		and DrawingRenderer.render(optimized_doc, CANVAS, ORIGIN_X, ORIGIN_Y).value.get_data() == expected.value.get_data(),
		"cancellation keeps committed bytes and history unchanged")
	# A late failed lazy-source read must not alter *earlier* native deltas.
	# This cannot be guaranteed by a journal-free loop without preflight.
	var faulty_doc: ReadFaultDocument = ReadFaultDocument.new("read-failure", 16)
	var faulty_layer: String = String(faulty_doc.create_layer(DrawingLayerNode.RASTER,
		"Faulty", "root").value)
	var faulty: DrawingEditSession = faulty_doc.begin_edit(faulty_layer, faulty_doc.revision,
		Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	source.delta = PackedInt32Array([-10, -10, 0x70abcdef, 14, 14, 0x70abcdef])
	faulty_doc.rejected_key = DrawingDocument.TILES.tile_key64(
		ORIGIN_X + 14, ORIGIN_Y + 14, faulty_doc.tile_stride)
	var rejected: DrawingResult = faulty.paint_path_hokusai(path, TINT, mask, source, CLIP)
	check(not rejected.ok and rejected.code == "INJECTED_TILE",
		"late failed source-tile resolution propagates")
	check(faulty.change_count() == 0 and faulty._preview_tiles.is_empty() and
		faulty_doc.read_pixel(faulty_layer, ORIGIN_X - 10, ORIGIN_Y - 10).value == 0,
		"failed source preflight leaves all detached pixels unmodified")
	faulty_doc.rejected_key = ""
	check(faulty.paint_path_hokusai(path, TINT, mask, source, CLIP).ok and
		faulty.change_count() == 2 and faulty.commit().ok,
		"retry after transient source load failure commits both pixels")
	print("T095_BULK_DELTA_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
