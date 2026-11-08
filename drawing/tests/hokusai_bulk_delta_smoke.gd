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
	# Deferred storage must not build one global string key for every repeated
	# native dab. Test no-op batches and a later mixed edit against the old oracle.
	var tiled: Dictionary = make_document("tile-local-deferred")
	var tiled_ref: Dictionary = make_document("tile-local-reference")
	var optimized_edit: DrawingEditSession = tiled["doc"].begin_edit(
		tiled["layer"], tiled["doc"].revision, Transform2D.IDENTITY,
		ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	var legacy_edit: DrawingEditSession = tiled_ref["doc"].begin_edit(
		tiled_ref["layer"], tiled_ref["doc"].revision, Transform2D.IDENTITY,
		ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	source.delta = PackedInt32Array([-7, -4, 0x60406080, -7, -4, 0x60406080,
		-4, 2, 0x70999010, -6, -4, 0x00303030])
	check(optimized_edit.paint_path_hokusai(path, TINT, mask, source, CLIP).ok,
		"tile-local staging accepts duplicate and transparent pigments")
	legacy_oracle(legacy_edit, source.delta, mask)
	check(optimized_edit._after.is_empty() and optimized_edit._before.is_empty() \
		and optimized_edit._hokusai_deferred and optimized_edit.change_count() == legacy_edit.change_count(),
		"native batches defer canonical global-key allocation while remaining countable")
	var unchanged_stamp: int = optimized_edit._preview_epoch
	source.delta = PackedInt32Array([-7, -4, 0x60406080, -4, 2, 0x70999010,
		-6, -4, 0x00303030])
	check(optimized_edit.paint_path_hokusai(path, TINT, mask, source, CLIP).ok,
		"repeated native quantization is accepted")
	legacy_oracle(legacy_edit, source.delta, mask)
	check(optimized_edit._preview_epoch == unchanged_stamp and
		optimized_edit.change_count() == legacy_edit.change_count(),
		"repeated equal pigment does not bump preview texture generations")
	check(preview(tiled["doc"], optimized_edit) == preview(tiled_ref["doc"], legacy_edit),
		"tile-local deferred output is byte-identical to the per-pixel oracle")
	var mixed_bytes: PackedByteArray = PackedByteArray([17, 39, 72, 141])
	check(optimized_edit.apply_region(Rect2i(-7, -4, 1, 1), mixed_bytes).ok and
		legacy_edit.apply_region(Rect2i(-7, -4, 1, 1), mixed_bytes).ok,
		"a canonical region edit can follow deferred native pigment")
	check(not optimized_edit._hokusai_deferred and optimized_edit.change_count() == legacy_edit.change_count() and
		preview(tiled["doc"], optimized_edit) == preview(tiled_ref["doc"], legacy_edit),
		"materialization before mixed edit preserves exact preview and history")
	source.delta = PackedInt32Array([-7, -4, 0x4540aaff, -12, -8, 0x6030ee77])
	check(optimized_edit.paint_path_hokusai(path, TINT, mask, source, CLIP).ok,
		"subsequent native batch uses canonical-key fallback in mixed session")
	legacy_oracle(legacy_edit, source.delta, mask)
	check(preview(tiled["doc"], optimized_edit) == preview(tiled_ref["doc"], legacy_edit),
		"mixed Hokusai-to-region-to-Hokusai preview agrees with old implementation")
	check(optimized_edit.commit().ok and legacy_edit.commit().ok,
		"mixed edit retains one atomic history transaction")
	check(DrawingRenderer.render(tiled["doc"], CANVAS, ORIGIN_X, ORIGIN_Y).value.get_data() ==
		DrawingRenderer.render(tiled_ref["doc"], CANVAS, ORIGIN_X, ORIGIN_Y).value.get_data(),
		"mixed committed pixels match reference")
	check(tiled["doc"].undo().ok and tiled["doc"].redo().ok,
		"mixed transaction still supports undo/redo")
	# A failing mixed region edit must restore the already staged native pixels.
	var failed_edit: DrawingEditSession = tiled["doc"].begin_edit(
		tiled["layer"], tiled["doc"].revision, Transform2D.IDENTITY,
		ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	var failed_reference: DrawingEditSession = tiled_ref["doc"].begin_edit(
		tiled_ref["layer"], tiled_ref["doc"].revision, Transform2D.IDENTITY,
		ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	source.delta = PackedInt32Array([-12, -9, 0x607733aa])
	check(failed_edit.paint_path_hokusai(path, TINT, mask, source, CLIP).ok,
		"native batch staged before invalid region request")
	legacy_oracle(failed_reference, source.delta, mask)
	var expected_mixed_preview: PackedByteArray = preview(tiled_ref["doc"], failed_reference)
	check(not failed_edit.apply_region(Rect2i(0, 0, 2, 2), PackedByteArray([1, 2])).ok,
		"malformed canonical region rejects without publishing native pixels")
	check(preview(tiled["doc"], failed_edit) == expected_mixed_preview and
		failed_edit.change_count() == failed_reference.change_count(),
		"failed region leaves deferred native preview intact")
	check(failed_edit.commit().ok and failed_reference.commit().ok and
		DrawingRenderer.render(tiled["doc"], CANVAS, ORIGIN_X, ORIGIN_Y).value.get_data() ==
		DrawingRenderer.render(tiled_ref["doc"], CANVAS, ORIGIN_X, ORIGIN_Y).value.get_data(),
		"successful commit after invalid mixed request remains exact")
	var mixed_fault_doc: ReadFaultDocument = ReadFaultDocument.new("mixed-source-read", 16)
	var mixed_fault_layer: String = String(mixed_fault_doc.create_layer(
		DrawingLayerNode.RASTER, "Faulty", "root").value)
	var mixed_fault: DrawingEditSession = mixed_fault_doc.begin_edit(mixed_fault_layer,
		mixed_fault_doc.revision, Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
	source.delta = PackedInt32Array([-12, -9, 0x60eeee33])
	check(mixed_fault.paint_path_hokusai(path, TINT, mask, source, CLIP).ok,
		"native edit begins deferred before a later source-read failure")
	var pre_failure: PackedByteArray = preview(mixed_fault_doc, mixed_fault)
	var pre_failure_count: int = mixed_fault.change_count()
	mixed_fault_doc.rejected_key = DrawingDocument.TILES.tile_key64(
		ORIGIN_X + 13, ORIGIN_Y - 9, mixed_fault_doc.tile_stride)
	var fail_across_tiles: DrawingResult = mixed_fault.apply_region(
		Rect2i(12, -9, 2, 1), PackedByteArray([20, 30, 40, 60, 60, 70, 80, 90]))
	check(not fail_across_tiles.ok and fail_across_tiles.code == "INJECTED_TILE",
		"late missing source rejects mixed batch after a successful first pixel")
	mixed_fault_doc.rejected_key = ""  # Disable the injected read fault for framebuffer verification.
	check(mixed_fault.change_count() == pre_failure_count and
		preview(mixed_fault_doc, mixed_fault) == pre_failure,
		"mixed batch rollback retains all earlier native pigment and exact preview")
	check(mixed_fault.commit().ok and
		mixed_fault_doc.read_pixel(mixed_fault_layer, ORIGIN_X - 12, ORIGIN_Y - 9).value != 0 and
		mixed_fault_doc.read_pixel(mixed_fault_layer, ORIGIN_X + 12, ORIGIN_Y - 9).value == 0,
		"native pigment commits after failed mixed API without leaking region pixels")
	# Changed-pixel streams from Hokusai arrive in spatially clustered runs.
	# Exercise the cached signed tile key across repeated/returning 32px tile
	# boundaries, preflight skips, hidden RGB and signed 64-bit origins. The
	# independent per-pixel _stage oracle deliberately does not use the fast path.
	var boundary_clip: Rect2i = Rect2i(-75, -74, 150, 148)
	var boundary_mask: DrawingSelection = DrawingSelection.new(
		Rect2i(-83, -83, 166, 166), true)
	check(boundary_mask.combine_rectangle(Rect2i(-11, -11, 22, 22), "Subtract"),
		"cross-tile stress selection has a hole")
	var boundary_documents: Array[DrawingDocument] = []
	var boundary_layers: Array[String] = []
	var boundary_sessions: Array[DrawingEditSession] = []
	for variant: int in range(2):
		var doc: DrawingDocument = DrawingDocument.new("boundary-%d" % variant, 32)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER,
			"Paint", "root").value)
		var seeded: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession
		var bytes: PackedByteArray = PackedByteArray()
		for pixel: int in range(24 * 24):
			bytes.append_array(PackedByteArray([255 - (pixel % 89),
				33 + (pixel % 133), pixel % 251, 0 if pixel % 7 == 0 else 117]))
		check(seeded.apply_region(Rect2i(-12, -12, 24, 24), bytes).ok and
			seeded.commit().ok, "stress source preserves transparent hidden RGB")
		boundary_documents.append(doc)
		boundary_layers.append(layer)
		boundary_sessions.append(doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession)
	var pigments: Array[int] = [0x00332211, 0x10ee11cc, 0x4080aacc,
		0x7f0accee, -1, 0x20406080, 0x00000000]
	var boundary_area: Rect2i = Rect2i(-84, -84, 168, 168)
	for batch: int in range(3):
		var samples: PackedInt32Array = PackedInt32Array()
		for y: int in range(-81, 82, 4):
			for x: int in range(-81, 82, 3):
				samples.push_back(x)
				samples.push_back(y)
				samples.push_back(pigments[posmod(x * 17 + y * 7 + batch * 11,
					pigments.size())])
		# Re-enter the first tile after a different tile and after a clipped
		# sample. The key cache may not attach that pixel to the latest tile.
		samples.append_array(PackedInt32Array([-100, 0, -1,
			-65, -65, 0x60998877, 75, 75, -1,
			-65, -65, 0x20335577]))
		source.delta = samples
		var batch_result: DrawingResult = boundary_sessions[0].paint_path_hokusai(
			path, TINT, boundary_mask, source, boundary_clip)
		check(batch_result.ok, "stress batch %d accepted" % batch)
		var reference_session: DrawingEditSession = boundary_sessions[1]
		var ok_reference: bool = true
		for i: int in range(0, samples.size(), 3):
			var at: Vector2i = Vector2i(samples[i], samples[i + 1])
			if not boundary_clip.has_point(at) or not boundary_mask.allows(at):
				continue
			var pigment: int = int(samples[i + 2]) & 0xffffffff
			var alpha: int = (((pigment >> 24) & 255) * ((TINT >> 24) & 255) + 127) / 255
			var canonical: int = (pigment & 0xffffff) | (alpha << 24)
			if not reference_session._stage(at.x, at.y, canonical, null, false, true).ok:
				ok_reference = false
				break
		check(ok_reference, "stress batch %d per-pixel oracle staged" % batch)
		var batch_actual: DrawingResult = DrawingRenderer.render(boundary_documents[0],
			boundary_area, ORIGIN_X, ORIGIN_Y, 1048576, boundary_sessions[0])
		var batch_expected: DrawingResult = DrawingRenderer.render(boundary_documents[1],
			boundary_area, ORIGIN_X, ORIGIN_Y, 1048576, boundary_sessions[1])
		check(batch_actual.ok and batch_expected.ok and
			batch_actual.value.get_data() == batch_expected.value.get_data(),
			"stress batch %d preview is byte-exact over signed tiles" % batch)
		check(boundary_sessions[0].change_count() == reference_session.change_count(),
			"stress batch %d changed-pixel count exact" % batch)
	check(boundary_sessions[0].commit().ok and boundary_sessions[1].commit().ok,
		"stress batch commits once in each independent document")
	var final_actual: DrawingResult = DrawingRenderer.render(boundary_documents[0],
		boundary_area, ORIGIN_X, ORIGIN_Y)
	var final_expected: DrawingResult = DrawingRenderer.render(boundary_documents[1],
		boundary_area, ORIGIN_X, ORIGIN_Y)
	check(final_actual.ok and final_expected.ok and
		final_actual.value.get_data() == final_expected.value.get_data(),
		"stress committed pixels byte-exact after signed tile key reuse")
	check(boundary_documents[0].undo().ok and boundary_documents[0].redo().ok and
		DrawingRenderer.render(boundary_documents[0], boundary_area,
			ORIGIN_X, ORIGIN_Y).value.get_data() == final_expected.value.get_data(),
		"stress undo/redo reconstructs identical published image")
	# A full 64x64 native run must not copy a growing PackedInt32Array
	# back into a Dictionary after every appended pixel. Then switch tiles,
	# revisit the first tile, and overwrite one of its existing pigments.
	# The independently staged reference proves the cached run is flushed
	# and reloaded without losing order or changing source-over semantics.
	var long_docs: Array[DrawingDocument] = []
	var long_layers: Array[String] = []
	var long_edits: Array[DrawingEditSession] = []
	for variant: int in range(2):
		var long_doc: DrawingDocument = DrawingDocument.new("long-run-%d" % variant, 64)
		var long_layer: String = String(long_doc.create_layer(
			DrawingLayerNode.RASTER, "Ink", "root").value)
		long_docs.append(long_doc)
		long_layers.append(long_layer)
		long_edits.append(long_doc.begin_edit(long_layer, long_doc.revision,
			Transform2D.IDENTITY, ORIGIN_X, ORIGIN_Y).value as DrawingEditSession)
	var long_deltas: PackedInt32Array = PackedInt32Array()
	for y: int in range(-41, 23):
		for x: int in range(-3, 61):
			long_deltas.push_back(x)
			long_deltas.push_back(y)
			long_deltas.push_back(0x30000000 | ((x + 3) << 8) | (y + 41))
	long_deltas.append_array(PackedInt32Array([61, 0, -1,
		-3, -41, 0x60a0b0c0, 61, 1, 0x40ff0000, -3, -41, 0x20001234]))
	source.delta = long_deltas
	var long_result: DrawingResult = long_edits[0].paint_path_hokusai(
		path, TINT, null, source)
	check(long_result.ok and long_edits[0].change_count() == 4098,
		"full 64px tile plus alternating tile revisits stages all distinct pixels")
	var long_reference_ok: bool = true
	for i: int in range(0, long_deltas.size(), 3):
		var pigment: int = int(long_deltas[i + 2]) & 0xffffffff
		var a: int = (((pigment >> 24) & 255) * ((TINT >> 24) & 255) + 127) / 255
		var rgba: int = (pigment & 0xffffff) | (a << 24)
		if not long_edits[1]._stage(long_deltas[i], long_deltas[i + 1],
				rgba, null, false, true).ok:
			long_reference_ok = false
			break
	check(long_reference_ok, "long-run oracle accepts every signed pigment")
	check(long_edits[0].change_count() == long_edits[1].change_count(),
		"full tile run preserves old-oracle changed-pixel count")
	var long_area: Rect2i = Rect2i(-4, -42, 68, 67)
	var long_preview: DrawingResult = DrawingRenderer.render(long_docs[0],
		long_area, ORIGIN_X, ORIGIN_Y, 1048576, long_edits[0])
	var long_expected: DrawingResult = DrawingRenderer.render(long_docs[1],
		long_area, ORIGIN_X, ORIGIN_Y, 1048576, long_edits[1])
	check(long_preview.ok and long_expected.ok and
		long_preview.value.get_data() == long_expected.value.get_data(),
		"full tile and revisit preview remains byte-exact")
	check(long_edits[0].commit().ok and long_edits[1].commit().ok,
		"full tile transaction commits atomically in both documents")
	check(DrawingRenderer.render(long_docs[0], long_area, ORIGIN_X, ORIGIN_Y).value.get_data() ==
		DrawingRenderer.render(long_docs[1], long_area, ORIGIN_X, ORIGIN_Y).value.get_data(),
		"full tile committed image remains byte-exact")
	check(long_docs[0].undo().ok and long_docs[0].redo().ok and
		DrawingRenderer.render(long_docs[0], long_area, ORIGIN_X, ORIGIN_Y).value.get_data() ==
		DrawingRenderer.render(long_docs[1], long_area, ORIGIN_X, ORIGIN_Y).value.get_data(),
		"long tile run retains one undoable history transaction")
	print("T095_BULK_DELTA_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
