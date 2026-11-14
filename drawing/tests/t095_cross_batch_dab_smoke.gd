extends SceneTree
## Independent no-shortcut control for repeated *one-point calls*. Preserves
## source RGBA8, history, signed tiles and changed-settings failure gates.

const INK: int = 0x8e49b3d7
const VIEW: Rect2i = Rect2i(-62, -62, 124, 124)

class FaultDocument:
	extends DrawingDocument
	var reject_key: String = ""
	var fail_once: bool = true
	var rejected: int = 0
	func _resolve_chunk(layer: String, key: String) -> DrawingResult:
		if not reject_key.is_empty() and key == reject_key and fail_once:
			fail_once = false
			rejected += 1
			return DrawingResult.failure("INJECTED_TILE", "Deliberate late source read failure")
		return super._resolve_chunk(layer, key)
var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_CROSS_BATCH_DAB_FAILED: " + label)


func make_target(name: String, stride: int, faultable: bool = false) -> Dictionary:
	var anchor: Vector2i = Vector2i(-2147483779, 2147483701)
	var doc: DrawingDocument = FaultDocument.new(name, stride) if faultable \
		else DrawingDocument.new(name, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value
	var pixels: PackedByteArray = PackedByteArray()
	for i: int in range(26 * 26):
		pixels.append_array(PackedByteArray([i % 255, (i * 11) % 255,
			(i * 31) % 255, 0 if i % 8 == 0 else 179]))
	check(seed.apply_region(Rect2i(-13, -13, 26, 26), pixels).ok and seed.commit().ok,
		name + " RGBA8 seed")
	return {"doc": doc, "layer": layer, "anchor": anchor}


func begin(target: Dictionary) -> DrawingEditSession:
	var doc: DrawingDocument = target["doc"]
	var anchor: Vector2i = target["anchor"]
	return doc.begin_edit(target["layer"], doc.revision,
		Transform2D.IDENTITY, anchor.x, anchor.y).value


func snapshot(target: Dictionary, edit: DrawingEditSession = null) -> PackedByteArray:
	var doc: DrawingDocument = target["doc"]
	var anchor: Vector2i = target["anchor"]
	var result: DrawingResult = DrawingRenderer.render(doc, VIEW,
		anchor.x, anchor.y, VIEW.size.x * VIEW.size.y, edit)
	check(result.ok, "render exact signed source/preview")
	return result.value.get_data() if result.ok else PackedByteArray()


func compare_commit(a: Dictionary, b: Dictionary, edit: DrawingEditSession,
		control: DrawingEditSession, label: String) -> void:
	var initial_a: PackedByteArray = snapshot(a)
	var initial_b: PackedByteArray = snapshot(b)
	check(initial_a == initial_b, label + " original sources equal")
	var preview_a: PackedByteArray = snapshot(a, edit)
	var preview_b: PackedByteArray = snapshot(b, control)
	check(preview_a == preview_b, label + " byte-exact preview parity")
	check(snapshot(a) == initial_a, label + " detached source unchanged")
	var first: DrawingResult = edit.commit()
	var second: DrawingResult = control.commit()
	check(first.ok and second.ok, label + " both commits succeed")
	if first.ok and second.ok:
		check(first.delta.before == second.delta.before \
			and first.delta.after == second.delta.after, label + " history delta parity")
	check(snapshot(a) == preview_a and snapshot(b) == preview_b,
		label + " commit retains exact preview")
	var doc_a: DrawingDocument = a["doc"]
	var doc_b: DrawingDocument = b["doc"]
	check(doc_a.undo().ok and doc_b.undo().ok \
		and snapshot(a) == initial_a and snapshot(b) == initial_b,
		label + " Undo source parity")
	check(doc_a.redo().ok and doc_b.redo().ok \
		and snapshot(a) == preview_a and snapshot(b) == preview_b,
		label + " Redo source parity")


func repeat_single_point(name: String, erase: bool, stride: int) -> void:
	var a: Dictionary = make_target(name + "-fast", stride)
	var b: Dictionary = make_target(name + "-control", stride)
	var actual: DrawingEditSession = begin(a)
	var control: DrawingEditSession = begin(b)
	var point: PackedVector2Array = PackedVector2Array([Vector2(0.5, -0.5)])
	var clip: Rect2i = Rect2i(-53, -50, 106, 102)
	for i: int in range(121):
		check(actual.paint_path(point, INK, 60.0, erase, null, 1048576, clip).ok,
			name + " accepted batch %d" % i)
		# Force the previous full-dab path as an independent behavioral control.
		control._stationary_dab_valid = false
		check(control.paint_path(point, INK, 60.0, erase, null, 1048576, clip).ok,
			name + " complete-raster control batch %d" % i)
	check(actual._cross_batch_dabs_skipped == 120,
		name + " skips every repeated one-point batch")
	check(control._cross_batch_dabs_skipped == 0,
		name + " control continues to rasterize")
	check(actual.change_count() == control.change_count(), name + " changed pixel parity")
	compare_commit(a, b, actual, control, name)


func changed_context_and_budget() -> void:
	var a: Dictionary = make_target("context-fast", 30)
	var b: Dictionary = make_target("context-control", 30)
	var edit: DrawingEditSession = begin(a)
	var reference: DrawingEditSession = begin(b)
	var point: PackedVector2Array = PackedVector2Array([Vector2(3.5, -1.5)])
	var small: Rect2i = Rect2i(1, -3, 6, 6)
	var wide: Rect2i = Rect2i(-53, -51, 106, 102)
	check(edit.paint_path(point, INK, 5.0, false, null, 1048576, small).ok,
		"small first dab accepted")
	check(reference.paint_path(point, INK, 5.0, false, null, 1048576, small).ok,
		"small control dab accepted")
	# The previous dab used a different clip, width, and budget. None may
	# be suppressed even though the pointer coordinate is unchanged.
	var bad: DrawingResult = edit.paint_path(point, INK, 60.0, false, null, 1, wide)
	check(not bad.ok and bad.code == "BRUSH_LIMIT", "changed budget fails closed")
	check(edit._cross_batch_dabs_skipped == 0, "failed budget does not count a reuse")
	check(edit.paint_path(point, INK, 60.0, false, null, 1048576, wide).ok,
		"larger unmasked dab accepted after failed budget")
	check(reference.paint_path(point, INK, 60.0, false, null, 1048576, wide).ok,
		"larger reference dab accepted")
	check(edit._cross_batch_dabs_skipped == 0, "changed width and clip are rerasterized")
	# Changing the color, eraser mode, and selection must not reuse a dab.
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-40, -40, 90, 90), true)
	check(selection.combine_rectangle(Rect2i(-5, -5, 12, 12), "Subtract"),
		"selection mask hole established")
	for mode: int in range(3):
		var color: int = INK if mode != 0 else 0x49a152c3
		var eraser: bool = mode == 1
		var mask: DrawingSelection = selection if mode == 2 else null
		check(edit.paint_path(point, color, 60.0, eraser, mask, 1048576, wide).ok,
			"changed context accepted %d" % mode)
		reference._stationary_dab_valid = false
		check(reference.paint_path(point, color, 60.0, eraser, mask, 1048576, wide).ok,
			"changed context reference %d" % mode)
	check(edit._cross_batch_dabs_skipped == 0,
		"color/erase/selection changes invalidate reuse")
	# A different candidate budget must exercise the ordinary limit gate.
	check(edit.paint_path(point, INK, 60.0, false, null, 1048576, wide).ok,
		"restore unmasked context")
	reference._stationary_dab_valid = false
	check(reference.paint_path(point, INK, 60.0, false, null, 1048576, wide).ok,
		"restore unmasked reference")
	var limited: DrawingResult = edit.paint_path(point, INK, 60.0,
		false, null, 1, wide)
	check(not limited.ok and limited.code == "BRUSH_LIMIT",
		"narrow budget fails even after successful same-position dab")
	check(edit._cross_batch_dabs_skipped == 0, "budget failure never silently reused")
	compare_commit(a, b, edit, reference, "changed context")


func moving_endpoint_and_external_edit() -> void:
	var a: Dictionary = make_target("movement-fast", 64)
	var b: Dictionary = make_target("movement-control", 64)
	var edit: DrawingEditSession = begin(a)
	var reference: DrawingEditSession = begin(b)
	var clip: Rect2i = Rect2i(-52, -54, 104, 108)
	var p: PackedVector2Array = PackedVector2Array([Vector2(-14.5, 8.5)])
	var q: PackedVector2Array = PackedVector2Array([Vector2(14.5, 8.5)])
	for path: PackedVector2Array in [p, q, q, q]:
		check(edit.paint_path(path, INK, 37.5, false, null, 1048576, clip).ok,
			"movement step accepted")
		reference._stationary_dab_valid = false
		check(reference.paint_path(path, INK, 37.5, false, null, 1048576, clip).ok,
			"movement reference step")
	check(edit._cross_batch_dabs_skipped == 1,
		"first repeated endpoint rasterized; next stationary repeat reused")
	# Direct mixed API writes must invalidate the prior stationary witness.
	check(edit._stage(8, 8, 0x4910aa33).ok,
		"mixed direct stage succeeds")
	check(reference._stage(8, 8, 0x4910aa33).ok,
		"mixed direct control succeeds")
	check(edit.paint_path(q, INK, 37.5, false, null, 1048576, clip).ok,
		"post-mixed dab accepted")
	reference._stationary_dab_valid = false
	check(reference.paint_path(q, INK, 37.5, false, null, 1048576, clip).ok,
		"post-mixed control accepted")
	check(edit._cross_batch_dabs_skipped == 1,
		"mixed edit invalidates future short-circuit")
	compare_commit(a, b, edit, reference, "moving then mixed edit")


func coordinate_mapping_invalidation() -> void:
	var a: Dictionary = make_target("mapping-fast", 16)
	var b: Dictionary = make_target("mapping-reference", 16)
	var edit: DrawingEditSession = begin(a)
	var reference: DrawingEditSession = begin(b)
	var point: PackedVector2Array = PackedVector2Array([Vector2(4.5, 2.5)])
	var clip: Rect2i = Rect2i(-45, -42, 90, 84)
	check(edit.paint_path(point, INK, 8.0, false, null, 1048576, clip).ok and
		reference.paint_path(point, INK, 8.0, false, null, 1048576, clip).ok,
		"mapping baseline stationary dab")
	# A changed document-space origin exposes different signed source pixels
	# even though the view-relative pointer position remains identical.
	edit.anchor_x += 5
	reference.anchor_x += 5
	check(edit.paint_path(point, INK, 8.0, false, null, 1048576, clip).ok,
		"changed signed anchor accepted")
	reference._stationary_dab_valid = false
	check(reference.paint_path(point, INK, 8.0, false, null, 1048576, clip).ok,
		"changed signed anchor control")
	check(edit._cross_batch_dabs_skipped == 0,
		"changed global anchor cannot skip the repeated dab")
	# A new view transform can represent the same source-relative endpoint.
	# It must nevertheless invalidate the prior cross-call witness.
	var transform: Transform2D = Transform2D.IDENTITY.translated(Vector2(6.0, -3.0))
	edit.view_transform = transform
	reference.view_transform = transform
	var transformed: PackedVector2Array = PackedVector2Array([transform * point[0]])
	check(edit.paint_path(transformed, INK, 8.0, false, null, 1048576, clip).ok,
		"transformed repeated source position accepted")
	reference._stationary_dab_valid = false
	check(reference.paint_path(transformed, INK, 8.0, false, null, 1048576, clip).ok,
		"transformed source position control")
	check(edit._cross_batch_dabs_skipped == 0,
		"changed transform invalidates stationary reuse")
	compare_commit(a, b, edit, reference, "coordinate mapping")


func late_source_failure() -> void:
	var a: Dictionary = make_target("failed-fast", 16, true)
	var b: Dictionary = make_target("failed-control", 16)
	var edit: DrawingEditSession = begin(a)
	var reference: DrawingEditSession = begin(b)
	var first: PackedVector2Array = PackedVector2Array([Vector2(-20.5, -17.5)])
	var second: PackedVector2Array = PackedVector2Array([Vector2(30.5, 29.5)])
	var clip: Rect2i = Rect2i(-53, -52, 106, 104)
	check(edit.paint_path(first, INK, 3.0, false, null, 1048576, clip).ok and
		reference.paint_path(first, INK, 3.0, false, null, 1048576, clip).ok,
		"failure test baseline accepted")
	var preview_before: PackedByteArray = snapshot(a, edit)
	var changes_before: int = edit.change_count()
	var pointer_before: Vector2 = edit._last
	var doc: FaultDocument = a["doc"] as FaultDocument
	var anchor: Vector2i = a["anchor"]
	doc.reject_key = DrawingDocument.TILES.tile_key64(anchor.x + 30, anchor.y + 29, 16)
	var error: DrawingResult = edit.paint_path(second, INK, 3.0, false,
		null, 1048576, clip)
	check(not error.ok and error.code == "INJECTED_TILE" and doc.rejected == 1,
		"late source failure is observable")
	check(not edit._stationary_dab_valid and edit.change_count() == changes_before
		and edit._last == pointer_before and snapshot(a, edit) == preview_before,
		"failure restores previous accepted pixels/cursor and invalidates shortcut")
	check(edit.paint_path(second, INK, 3.0, false, null, 1048576, clip).ok and
		reference.paint_path(second, INK, 3.0, false, null, 1048576, clip).ok,
		"retry matches uninterrupted reference")
	check(edit.paint_path(second, INK, 3.0, false, null, 1048576, clip).ok and
		reference.paint_path(second, INK, 3.0, false, null, 1048576, clip).ok,
		"stationary retry endpoint accepted")
	compare_commit(a, b, edit, reference, "late source retry")


func run() -> void:
	coordinate_mapping_invalidation()
	late_source_failure()
	repeat_single_point("brush-stride30", false, 30)
	repeat_single_point("eraser-stride64", true, 64)
	changed_context_and_budget()
	moving_endpoint_and_external_edit()
	print("T095_CROSS_BATCH_DAB_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_CROSS_BATCH_DAB_PASSED")
	quit(1 if failures > 0 else 0)


func _initialize() -> void:
	call_deferred("run")
