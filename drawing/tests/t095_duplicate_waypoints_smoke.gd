extends SceneTree
## A stationary Legacy Brush/Eraser path may consume repeated pointer samples
## without repeating its once-only dab rasterization. Compare against an
## independently de-duplicated reference and verify full history/source bytes.

const VIEW: Rect2i = Rect2i(-58, -58, 116, 116)
const INK: int = 0x8e49b3d7
var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_DUPLICATE_WAYPOINT_FAILED: " + description)


func make_document(name: String, stride: int, anchor: Vector2i) -> Dictionary:
	var doc := DrawingDocument.new(name, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var pixels: PackedByteArray = PackedByteArray()
	for i: int in range(24 * 24):
		pixels.append_array(PackedByteArray([i % 251, (i * 17) % 255,
			(i * 43) % 255, 0 if i % 9 == 0 else 191]))
	check(seed.apply_region(Rect2i(-12, -12, 24, 24), pixels).ok and seed.commit().ok,
		name + " seeded RGBA8")
	return {"document": doc, "layer": layer}


func image_bytes(target: Dictionary, anchor: Vector2i,
		preview: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(target["document"], VIEW,
		anchor.x, anchor.y, VIEW.size.x * VIEW.size.y, preview)
	check(result.ok, "render signed RGBA8 preview/source")
	return result.value.get_data() if result.ok else PackedByteArray()


func exercise_case(index: int, erase: bool, selection_enabled: bool, stride: int) -> void:
	var name: String = "case-%d" % index
	var anchor := Vector2i(-2147483761, 2147483823) if index % 2 == 0 \
		else Vector2i(2147483819, -2147483757)
	var actual: Dictionary = make_document(name + "-actual", stride, anchor)
	var baseline: Dictionary = make_document(name + "-baseline", stride, anchor)
	var doc: DrawingDocument = actual["document"]
	var oracle_doc: DrawingDocument = baseline["document"]
	var original: PackedByteArray = image_bytes(actual, anchor)
	check(original == image_bytes(baseline, anchor), name + " seed parity")
	var edit: DrawingEditSession = doc.begin_edit(actual["layer"], doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var oracle: DrawingEditSession = oracle_doc.begin_edit(baseline["layer"],
		oracle_doc.revision, Transform2D.IDENTITY, anchor.x, anchor.y).value
	var selection: DrawingSelection = null
	if selection_enabled:
		selection = DrawingSelection.new(Rect2i(-45, -48, 92, 95), true)
		check(selection.combine_rectangle(Rect2i(-8, -7, 16, 14), "Subtract"),
			name + " selection hole")
	var clip := Rect2i(-51, -50, 103, 101)
	var points := PackedVector2Array([Vector2(-19.5, -17.5),
		Vector2(12.5, 7.5), Vector2(20.5, 20.5), Vector2(-6.5, 22.5)])
	var width: float = 60.0 if index % 2 == 0 else 9.5
	var expected_skips: int = 0
	for p: int in range(points.size()):
		var waypoint: Vector2 = points[p]
		var repetitions: int = 60 if p % 2 == 0 else 23
		var repeat: PackedVector2Array = PackedVector2Array()
		for n: int in range(repetitions):
			repeat.append(waypoint)
		# Split across calls: each first point must be repainted because
		# callers can change brush parameters between batches.
		check(edit.paint_path(repeat, INK, width, erase, selection, 1048576, clip).ok,
			name + " repeat group %d" % p)
		expected_skips += repetitions - (1 if p == 0 else 1)
	check(oracle.paint_path(points, INK, width, erase, selection, 1048576, clip).ok,
		name + " independent unique-point reference")
	check(edit._duplicate_waypoints_skipped == expected_skips,
		name + " same-batch duplicate rasterizations skipped exactly")
	check(edit.change_count() == oracle.change_count(), name + " changed pixel count")
	var preview: PackedByteArray = image_bytes(actual, anchor, edit)
	check(preview == image_bytes(baseline, anchor, oracle),
		name + " detached preview RGBA8 parity")
	check(image_bytes(actual, anchor) == original, name + " source remains detached")
	var result: DrawingResult = edit.commit()
	var reference: DrawingResult = oracle.commit()
	check(result.ok and reference.ok, name + " both commits succeed")
	if result.ok and reference.ok:
		check(result.delta.before == reference.delta.before \
			and result.delta.after == reference.delta.after,
			name + " exact historical pixel delta")
	check(image_bytes(actual, anchor) == preview \
		and image_bytes(actual, anchor) == image_bytes(baseline, anchor),
		name + " source equals preview/reference")
	check(doc.undo().ok and oracle_doc.undo().ok \
		and image_bytes(actual, anchor) == original \
		and image_bytes(actual, anchor) == image_bytes(baseline, anchor),
		name + " Undo parity")
	check(doc.redo().ok and oracle_doc.redo().ok \
		and image_bytes(actual, anchor) == preview \
		and image_bytes(actual, anchor) == image_bytes(baseline, anchor),
		name + " Redo parity")


func failure_and_retry() -> void:
	var anchor := Vector2i(-2147483779, 2147483697)
	var target: Dictionary = make_document("invalid-retry", 30, anchor)
	var doc: DrawingDocument = target["document"]
	var edit: DrawingEditSession = doc.begin_edit(target["layer"], doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var initial: PackedByteArray = image_bytes(target, anchor)
	var point: Vector2 = Vector2(0.5, -0.5)
	var denied: DrawingResult = edit.paint_path(PackedVector2Array([point, point]),
		INK, 60.0, false, null, 100)
	check(not denied.ok and denied.code == "BRUSH_LIMIT", "too-small dab budget fails")
	check(edit.change_count() == 0 and edit._duplicate_waypoints_skipped == 0 \
		and not edit._has_last, "failed first dab cannot be silently elided on retry")
	var accepted: DrawingResult = edit.paint_path(PackedVector2Array([point, point, point]),
		INK, 60.0)
	check(accepted.ok and edit._duplicate_waypoints_skipped == 2,
		"valid retry stages initial dab and skips only follow-up repeats")
	var preview: PackedByteArray = image_bytes(target, anchor, edit)
	check(preview != initial, "retry produces genuine paint")
	check(edit.commit().ok and image_bytes(target, anchor) == preview,
		"retry commits exact preview bytes")
	check(doc.undo().ok and image_bytes(target, anchor) == initial \
		and doc.redo().ok and image_bytes(target, anchor) == preview,
		"failed first dab followed by retry retains one Undo/Redo step")



func changed_settings_between_batches() -> void:
	var anchor := Vector2i(2147483807, -2147483701)
	var a: Dictionary = make_document("settings-actual", 64, anchor)
	var b: Dictionary = make_document("settings-reference", 64, anchor)
	var first: DrawingEditSession = a["document"].begin_edit(a["layer"],
		a["document"].revision, Transform2D.IDENTITY, anchor.x, anchor.y).value
	var reference: DrawingEditSession = b["document"].begin_edit(b["layer"],
		b["document"].revision, Transform2D.IDENTITY, anchor.x, anchor.y).value
	var point := Vector2(3.5, 4.5)
	var tight_clip := Rect2i(0, 0, 8, 8)
	var broad_clip := Rect2i(-53, -51, 107, 104)
	var denied := DrawingSelection.new(Rect2i(-40, -40, 2, 2), true)
	check(first.paint_path(PackedVector2Array([point]), INK, 5.0,
		false, denied, 1048576, tight_clip).ok,
		"first batch selection excludes initial dab")
	check(reference.paint_path(PackedVector2Array([point]), INK, 5.0,
		false, denied, 1048576, tight_clip).ok,
		"reference first batch selection excludes dab")
	check(first.paint_path(PackedVector2Array([point, point]), INK, 60.0,
		false, null, 1048576, broad_clip).ok,
		"same position in next batch can expand coverage")
	check(reference.paint_path(PackedVector2Array([point]), INK, 60.0,
		false, null, 1048576, broad_clip).ok,
		"reference expands coverage with changed width/mask/clip")
	check(first._duplicate_waypoints_skipped == 1,
		"only second point in changed-settings batch is deduplicated")
	check(first.change_count() > 0 and first.change_count() == reference.change_count(),
		"newly authorized pixels are not lost across calls")
	check(image_bytes(a, anchor, first) == image_bytes(b, anchor, reference),
		"changed-settings exact preview parity")
	var actual_commit: DrawingResult = first.commit()
	var reference_commit: DrawingResult = reference.commit()
	check(actual_commit.ok and reference_commit.ok
		and actual_commit.delta.after == reference_commit.delta.after
		and actual_commit.delta.before == reference_commit.delta.before,
		"changed-settings history parity")


func run() -> void:
	for index: int in range(8):
		exercise_case(index, index % 3 == 1, index % 2 == 0,
			30 if index % 2 == 0 else 64)
	failure_and_retry()
	changed_settings_between_batches()
	print("T095_DUPLICATE_WAYPOINT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_DUPLICATE_WAYPOINT_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
