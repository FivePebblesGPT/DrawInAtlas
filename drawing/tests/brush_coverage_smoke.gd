extends SceneTree
## T-095: independent analytic swept-disc oracle, not paint_path/fill_rect as
## reference. Check true source RGBA8 across signed tiles, selection holes,
## preview/rollback, second gesture Eraser and one-step Undo/Redo.

const AREA: Rect2i = Rect2i(-75, -75, 150, 150)
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
const PAINT: int = 0x806c35e1
const BACK: int = 0xff563412

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_ORACLE_FAILED: " + label)


## Independent scalar projection, unlike the production Geometry2D query.
func disc_hits_segment(point: Vector2, start: Vector2, finish: Vector2, radius: float) -> bool:
	var edge: Vector2 = finish - start
	var length_squared: float = edge.length_squared()
	var fraction: float = clampf((point - start).dot(edge) / length_squared, 0.0, 1.0) \
		if length_squared > 0.0 else 0.0
	var difference: Vector2 = point - (start + fraction * edge)
	return difference.length_squared() <= radius * radius


func disc_hits_path(pixel: Vector2i, path: PackedVector2Array, width: float) -> bool:
	var center: Vector2 = Vector2(pixel) + Vector2(0.5, 0.5)
	if path.size() == 1:
		return disc_hits_segment(center, path[0], path[0], width * 0.5)
	for index: int in range(1, path.size()):
		if disc_hits_segment(center, path[index - 1], path[index], width * 0.5):
			return true
	return false


## Distinct from the application's source-over implementation: integer
## representation is assembled after independent straight-alpha math.
func source_over(foreground: int, background: int) -> int:
	var opacity: float = float((foreground >> 24) & 255) / 255.0
	if opacity == 0.0:
		return background
	var background_opacity: float = float((background >> 24) & 255) / 255.0
	var resulting_alpha: float = opacity + (1.0 - opacity) * background_opacity
	var result: int = roundi(resulting_alpha * 255.0) << 24
	for channel: int in range(3):
		var shift: int = channel * 8
		var fore: float = float((foreground >> shift) & 255)
		var back: float = float((background >> shift) & 255)
		result |= clampi(roundi((fore * opacity + back * background_opacity * (1.0 - opacity)) \
			/ resulting_alpha), 0, 255) << shift
	return result


func reference_stroke(values: Dictionary[Vector2i, int], paths: Array[PackedVector2Array],
		width: float, color: int, erase: bool, mask: DrawingSelection,
		clip: Rect2i) -> void:
	# Sweep coverage is a SET over the entire gesture, regardless of how many
	# paint_path calls the input queue split it into.
	for y: int in range(AREA.position.y, AREA.end.y):
		for x: int in range(AREA.position.x, AREA.end.x):
			var pixel: Vector2i = Vector2i(x, y)
			if clip.has_area() and not clip.has_point(pixel):
				continue
			if mask != null and not mask.allows(pixel):
				continue
			var covered: bool = false
			for path: PackedVector2Array in paths:
				if disc_hits_path(pixel, path, width):
					covered = true
					break
			if covered:
				values[pixel] = 0 if erase else source_over(color, values.get(pixel, 0))


func verify_pixels(doc: DrawingDocument, layer: String,
		values: Dictionary[Vector2i, int], label: String) -> void:
	var mismatches: int = 0
	var unavailable: int = 0
	for y: int in range(AREA.position.y, AREA.end.y):
		for x: int in range(AREA.position.x, AREA.end.x):
			var point: Vector2i = Vector2i(x, y)
			var actual: DrawingResult = doc.read_pixel(layer, x, y)
			if not actual.ok:
				unavailable += 1
			elif int(actual.value) != int(values.get(point, 0)):
				if mismatches < 4:
					printerr("T095_ORACLE_PIXEL label=%s point=%s actual=%08x expected=%08x" % [
						label, point, int(actual.value), int(values.get(point, 0))])
				mismatches += 1
	check(mismatches == 0 and unavailable == 0,
		"%s byte-exact 150x150 independent signed-chunk oracle (mismatch=%d errors=%d)" % [
			label, mismatches, unavailable])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var document: DrawingDocument = DrawingDocument.new("t095-oracle", 16)
	var bottom: String = String(document.create_layer(DrawingLayerNode.RASTER, "Backdrop", "root", "bottom").value)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "top").value)
	var seed: DrawingEditSession = document.begin_edit(bottom, document.revision).value as DrawingEditSession
	check(seed.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]), BACK, 60.0).ok and seed.commit().ok,
		"60px backdrop is also an actual Brush, not a fill")
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-70, -70, 140, 140), true)
	check(mask.combine_rectangle(Rect2i(-8, -8, 17, 17), "Subtract"), "selection with hole")
	var first_path: PackedVector2Array = PackedVector2Array([
		Vector2(-61.5, -21.5), Vector2(-31.5, -15.5), Vector2(-0.5, 0.5),
		Vector2(31.5, 21.5), Vector2(61.5, 29.5)])
	var second_path: PackedVector2Array = PackedVector2Array([
		Vector2(60.5, -27.5), Vector2(14.5, -1.5), Vector2(-28.5, 33.5),
		Vector2(-62.5, 36.5)])
	var paths: Array[PackedVector2Array] = [first_path, second_path]
	var reference: Dictionary[Vector2i, int] = {}
	reference_stroke(reference, paths, 60.0, PAINT, false, mask, CLIP)
	var baseline_revision: int = document.revision
	var session: DrawingEditSession = document.begin_edit(layer, baseline_revision).value as DrawingEditSession
	check(session.paint_path(first_path, PAINT, 60.0, false, mask, 1048576, CLIP).ok,
		"large diagonal brush crosses signed tiles")
	check(session.paint_path(second_path, PAINT, 60.0, false, mask, 1048576, CLIP).ok,
		"second input batch overlaps previous, exactly-once per gesture")
	check(session.change_count() == reference.size() and document.revision == baseline_revision,
		"every geometrically covered source pixel staged without premature publication")
	check(session.preview_stamp_for_area(Rect2i(-64, -64, 128, 128)) > 0,
		"detached compositor stamp exists while held")
	check(document.read_pixel(layer, -31, -15).value == 0,
		"staging leaves canonical source untouched")
	var preview: DrawingResult = DrawingRenderer.render(document, AREA, 0, 0, 1048576, session)
	check(preview.ok, "live preview can composite both layers")
	check(session.commit().ok and document.revision == baseline_revision + 1,
		"brush publishes once")
	verify_pixels(document, layer, reference, "brush 60 with selection/clip")
	check(DrawingRenderer.render(document, AREA).value.get_data() == preview.value.get_data(),
		"detached RGBA8 preview and committed layer composite identical")
	check(document.read_pixel(layer, 0, 0).value == 0 and
		document.read_pixel(bottom, 0, 0).value == BACK,
		"selection hole excludes top paint but shows opaque lower layer")
	check(document.undo().ok, "brush history can be undone in one operation")
	verify_pixels(document, layer, {}, "undo brush")
	check(document.redo().ok, "brush history can be redone in one operation")
	verify_pixels(document, layer, reference, "redo brush")

	var erase_path: PackedVector2Array = PackedVector2Array([
		Vector2(-59.5, 31.5), Vector2(-13.5, 10.5), Vector2(27.5, -15.5), Vector2(62.5, -33.5)])
	var before_erase: Dictionary[Vector2i, int] = reference.duplicate()
	reference_stroke(reference, [erase_path], 60.0, 0, true, mask, CLIP)
	var eraser: DrawingEditSession = document.begin_edit(layer, document.revision).value as DrawingEditSession
	check(eraser.paint_path(erase_path, 0, 60.0, true, mask, 1048576, CLIP).ok,
		"60px Eraser uses the same once-only coverage path")
	check(eraser.commit().ok, "Eraser publishes one edit")
	verify_pixels(document, layer, reference, "eraser 60 with selection/clip")
	check(document.undo().ok, "erase undone")
	verify_pixels(document, layer, before_erase, "undo Eraser")
	check(document.redo().ok, "erase redone")

	var stable_revision: int = document.revision
	var failed: DrawingEditSession = document.begin_edit(layer, stable_revision).value as DrawingEditSession
	var rejected: DrawingResult = failed.paint_path(PackedVector2Array([
		Vector2(67.5, 68.5), Vector2(2000000000.0, 0.5)]), PAINT, 60.0)
	check(not rejected.ok and rejected.code == "COORD_RANGE" and failed.change_count() == 0,
		"invalid point rolls back a fully staged 60px dab")
	check(failed._covered_rows.is_empty() and failed._preview_tiles.is_empty(),
		"rollback removes covered-row acceleration and detached preview state")
	check(failed.paint_path(PackedVector2Array([Vector2(67.5, 68.5)]), PAINT, 60.0).ok and
		failed.change_count() > 0, "retry following failed gesture paints previously rolled-back pixels")
	failed.cancel()
	check(document.revision == stable_revision and document.read_pixel(layer, 68, 68).value == 0,
		"Escape/cancel discards the retried uncommitted pixels")
	var retained: DrawingEditSession = document.begin_edit(layer, stable_revision).value as DrawingEditSession
	check(retained.paint_path(PackedVector2Array([Vector2(67.5, 68.5)]), PAINT, 60.0).ok,
		"first stroke batch establishes nonempty covered-row journal")
	var previous_changes: int = retained.change_count()
	var mixed_failure: DrawingResult = retained.paint_path(PackedVector2Array([
		Vector2(109.5, 68.5), Vector2(2000000000.0, 69.5)]), PAINT, 60.0)
	check(not mixed_failure.ok and retained.change_count() == previous_changes,
		"rollback preserves previously successful batches in the same gesture")
	check(retained._covered_rows.has(68) and
		(retained._covered_rows[68] as Dictionary).has(67) and
		not (retained._covered_rows[68] as Dictionary).has(109),
		"failure erases only newly covered pixels, not prior coverage")
	retained.cancel()
	check(document.revision == stable_revision,
		"rollback after a valid batch still leaves canonical source untouched")

	var signed_x: int = 2147483654
	var signed_y: int = -2147483660
	var signed_session: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, signed_x, signed_y).value as DrawingEditSession
	check(signed_session.paint_path(PackedVector2Array([
		Vector2(-1.5, -1.5), Vector2(1.5, 1.5)]), PAINT, 60.0).ok,
		"64-bit signed anchored brush stages without integer row-key collision")
	check(signed_session.commit().ok and
		document.read_pixel(layer, signed_x, signed_y).value == PAINT,
		"anchored source RGBA8 pixel survives exact signed coordinate publication")

	print("T095_ORACLE_RESULT checks=%d failures=%d union_pixels=%d engine=%s" % [
		checks, failures, before_erase.size(), Engine.get_version_info().get("string", "unknown")])
	if failures == 0:
		print("T095_ORACLE_PASSED")
	quit(1 if failures > 0 else 0)
