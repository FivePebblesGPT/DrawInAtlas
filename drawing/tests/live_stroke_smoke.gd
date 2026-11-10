extends SceneTree
## T-085: canonical document stays unchanged until publication; preview respects
## layer order, erase, cancellation, rollback, RGBA8 and one-step history.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T085_MODEL_FAILED: " + label)


func rgba(image: Image, position: Vector2i) -> Color:
	return image.get_pixelv(position)


func paint(document: DrawingDocument, layer: String, area: Rect2i, bytes: PackedByteArray) -> void:
	var started: DrawingResult = document.begin_edit(layer, document.revision)
	check(started.ok, "begin seed layer edit")
	if not started.ok:
		return
	var edit: DrawingEditSession = started.value as DrawingEditSession
	check(edit.apply_region(area, bytes).ok, "stage seed bytes")
	check(edit.commit().ok, "publish seed layer edit")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var document: DrawingDocument = DrawingDocument.new("t085-model", 16)
	var bottom: String = String(document.create_layer(DrawingLayerNode.RASTER, "Bottom", "root", "bottom").value)
	var top: String = String(document.create_layer(DrawingLayerNode.RASTER, "Top", "root", "top").value)
	paint(document, bottom, Rect2i(0, 0, 1, 1), PackedByteArray([230, 20, 20, 255]))
	paint(document, top, Rect2i(0, 0, 1, 1), PackedByteArray([20, 220, 20, 255]))
	var base: DrawingResult = DrawingRenderer.render(document, Rect2i(-3, -3, 9, 9))
	check(base.ok, "render base with overlapping layers")
	var committed_revision: int = document.revision
	var begun: DrawingResult = document.begin_edit(bottom, document.revision)
	check(begun.ok, "begin bottom-layer live preview")
	var session: DrawingEditSession = begun.value as DrawingEditSession
	check(session.paint_path(PackedVector2Array([Vector2(0.5, 0.5), Vector2(2.5, 0.5)]),
		0xffffa030, 1.0).ok, "stage low-layer segment with two exact float samples")
	var preview: DrawingResult = DrawingRenderer.render(document, Rect2i(-3, -3, 9, 9), 0, 0, 1048576, session)
	check(preview.ok and document.revision == committed_revision, "preview does not publish revision")
	check(document.read_pixel(bottom, 2, 0).value == 0, "preview does not alter canonical tile")
	check(rgba(preview.value, Vector2i(3, 3)).is_equal_approx(rgba(base.value, Vector2i(3, 3))),
		"top layer occludes lower-layer draft exactly")
	check(rgba(preview.value, Vector2i(5, 3)).a > 0.9, "unoccluded low-layer paint visible")
	check(session.commit().ok, "single publication of preview")
	var published: DrawingResult = DrawingRenderer.render(document, Rect2i(-3, -3, 9, 9))
	check(preview.value.get_data() == published.value.get_data(), "preview bytes equal committed render")
	check(document.undo().ok and document.read_pixel(bottom, 2, 0).value == 0,
		"one undo reverses entire multi-point stroke")
	check(document.redo().ok, "single redo restores stroke")

	var erase_started: DrawingResult = document.begin_edit(top, document.revision)
	var eraser: DrawingEditSession = erase_started.value as DrawingEditSession
	check(eraser.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]), 0, 1.0, true).ok,
		"stage top layer eraser")
	var erased: DrawingResult = DrawingRenderer.render(document, Rect2i(-3, -3, 9, 9), 0, 0, 1048576, eraser)
	check(document.read_pixel(top, 0, 0).value != 0, "eraser does not edit committed source before release")
	check(rgba(erased.value, Vector2i(3, 3)).b > 0.9 and rgba(erased.value, Vector2i(3, 3)).g > 0.55,
		"eraser draft exposes modified lower-layer content, not a transparent overlay")
	check(eraser.commit().ok and DrawingRenderer.render(document, Rect2i(-3, -3, 9, 9)).value.get_data() == erased.value.get_data(),
		"eraser draft equals final layer-order result")

	var cancelled: DrawingEditSession = document.begin_edit(bottom, document.revision).value as DrawingEditSession
	var before_cancel: int = document.revision
	check(cancelled.paint_path(PackedVector2Array([Vector2(4.5, 4.5)]), 0xff20ffff, 2.0).ok,
		"stage cancel target")
	check(cancelled.change_count() > 0, "cancel test actually staged pixels")
	cancelled.cancel()
	check(cancelled.preview_tile("0,0").is_empty() and document.revision == before_cancel and
		document.read_pixel(bottom, 4, 4).value == 0, "cancel removes preview and preserves revision")

	var rejected: DrawingEditSession = document.begin_edit(bottom, document.revision).value as DrawingEditSession
	var rejected_path: PackedVector2Array = PackedVector2Array([Vector2(6.5, 6.5), Vector2(2000000000.0, 6.5)])
	var failure: DrawingResult = rejected.paint_path(rejected_path, 0xff202020, 2.0)
	check(not failure.ok and failure.code == "COORD_RANGE", "invalid second sample rejected")
	check(rejected.change_count() == 0 and rejected.preview_tile("0,0").is_empty(),
		"failed stroke rolls back previous samples without leaking draft pixels")
	check(rejected.paint_path(PackedVector2Array([Vector2(7.5, 7.5)]), 0xff101010, 1.0).ok,
		"failed stroke does not corrupt next valid paint path")
	rejected.cancel()

	var crossing: DrawingEditSession = document.begin_edit(bottom, document.revision).value as DrawingEditSession
	var loop: PackedVector2Array = PackedVector2Array([Vector2(10.5, 10.5),
		Vector2(14.5, 14.5), Vector2(10.5, 14.5), Vector2(14.5, 10.5)])
	check(crossing.paint_path(loop, 0x80443322, 2.0).ok,
		"self-crossing semiopaque brush path staged")
	check(crossing.change_count() > 0 and document.read_pixel(bottom, 12, 12).value == 0,
		"crossing remains uncommitted")
	check(crossing.commit().ok, "crossing publishes as one gesture")
	var intersection: int = int(document.read_pixel(bottom, 12, 12).value)
	check((intersection >> 24) & 255 == 128,
		"crossing obeys exactly-once coverage rather than applying alpha twice")
	check(document.undo().ok and document.read_pixel(bottom, 12, 12).value == 0,
		"crossing can be undone atomically")

	# Long signed anchors must not be truncated by the viewport preview path.
	var signed: DrawingDocument = DrawingDocument.new("t085-signed", 16)
	var signed_layer: String = String(signed.create_layer(DrawingLayerNode.RASTER, "Signed", "root").value)
	var big_x: int = 2147483654
	var big_y: int = -2147483660
	var signed_edit: DrawingEditSession = signed.begin_edit(signed_layer, signed.revision,
		Transform2D.IDENTITY, big_x, big_y).value as DrawingEditSession
	check(signed_edit.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]), 0xffaa5522, 1.0).ok,
		"signed 64-bit relative preview pixel staged")
	var signed_preview: DrawingResult = DrawingRenderer.render(signed, Rect2i(0, 0, 1, 1),
		big_x, big_y, 1048576, signed_edit)
	check(signed_preview.ok and signed_preview.value.get_pixel(0, 0).a > 0.99 and
		signed.read_pixel(signed_layer, big_x, big_y).value == 0,
		"large signed anchor preview renders before source publication")
	check(signed_edit.commit().ok and signed.read_pixel(signed_layer, big_x, big_y).value == 0xffaa5522,
		"signed preview commits exact RGBA8 without truncation")

	var conflicting: DrawingEditSession = document.begin_edit(bottom, document.revision).value as DrawingEditSession
	check(conflicting.paint_path(PackedVector2Array([Vector2(-1.5, -1.5)]), 0xff030201).ok,
		"stage preview before external revision")
	check(document.set_visibility(top, false).ok and
		not DrawingRenderer.render(document, Rect2i(-3, -3, 9, 9), 0, 0, 1048576, conflicting).ok,
		"stale preview fails closed when another action changes revision")
	check(not conflicting.commit().ok and document.read_pixel(bottom, -2, -2).value == 0,
		"stale revision publication rejects uncommitted changes atomically")
	check(document.set_visibility(top, true).ok, "restore layer visibility after conflict probe")

	var wrong: DrawingDocument = DrawingDocument.new("different")
	var stale_session: DrawingEditSession = document.begin_edit(bottom, document.revision).value as DrawingEditSession
	check(not DrawingRenderer.render(wrong, Rect2i(0, 0, 3, 3), 0, 0, 1048576, stale_session).ok,
		"unrelated document preview rejected")
	stale_session.cancel()

	# Exercise the actual canvas queue in fast headless CI, not just the edit
	# session. Each zoom maps source floats through the same view transform
	# as a delivered motion; a single-call reference is the pixel oracle.
	var queued_canvas: Control = Control.new()
	queued_canvas.set_script(load("res://addons/drawing/canvas.gd"))
	queued_canvas.size = Vector2(270, 230)
	queued_canvas.brush_width = 2.0
	queued_canvas.color_rgba = 0x8044d9ff
	root.add_child(queued_canvas)
	for zoom_value: float in [1.0, 0.5, 0.25]:
		queued_canvas.zoom = zoom_value
		var queued_doc: DrawingDocument = DrawingDocument.new("t085-queue")
		var queued_layer: String = String(queued_doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
		queued_canvas.document = queued_doc
		queued_canvas.layer_id = queued_layer
		var original_revision: int = queued_doc.revision
		var first: Vector2 = Vector2(12.5, 12.5)
		var path: PackedVector2Array = PackedVector2Array()
		path.append(queued_canvas.source_position(queued_canvas.pixel_to_position(first)))
		queued_canvas.start_gesture(queued_canvas.pixel_to_position(first))
		for i: int in range(600):
			var t: float = float(i) / 599.0
			var point: Vector2 = Vector2(35.5 + 21.0 * cos(t * TAU * 9.0),
				27.5 + 12.0 * sin(t * TAU * 13.0))
			path.append(queued_canvas.source_position(queued_canvas.pixel_to_position(point)))
			queued_canvas.update_gesture(queued_canvas.pixel_to_position(point))
		var finish: Vector2 = Vector2(59.5, 23.5)
		path.append(queued_canvas.source_position(queued_canvas.pixel_to_position(finish)))
		check(queued_doc.revision == original_revision and queued_canvas.session != null and
			int(queued_canvas._metrics["samples_received"]) == 601,
			"zoom %s queue accepts entire 600-point stroke without early publication" % zoom_value)
		queued_canvas.finish_gesture(queued_canvas.pixel_to_position(finish))
		for drain: int in range(80):
			if queued_canvas.session == null:
				break
			queued_canvas._drain_segments(queued_canvas.MAX_SEGMENTS_PER_FRAME)
		var stats: Dictionary = queued_canvas.last_gesture_metrics
		check(queued_canvas.session == null and queued_doc.revision == original_revision + 1,
			"zoom %s bounded drains publish exactly once" % zoom_value)
		check(int(stats.get("samples_received", 0)) == 602 and
			(stats.get("sample_to_stage_us", []) as Array).size() == 602 and
			int(stats.get("drain_calls", 100)) < 50,
			"zoom %s bulk stage retains all arrivals and avoids fixed-cap backlog" % zoom_value)
		var reference: DrawingDocument = DrawingDocument.new("t085-queue-reference")
		var reference_layer: String = String(reference.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
		var ref_session: DrawingEditSession = reference.begin_edit(reference_layer, reference.revision).value as DrawingEditSession
		check(ref_session.paint_path(path, queued_canvas.color_rgba, queued_canvas.brush_width).ok and
			ref_session.commit().ok, "zoom %s single-path oracle paints" % zoom_value)
		var region: Rect2i = Rect2i(10, 9, 55, 38)
		var staged_image: DrawingResult = DrawingRenderer.render(queued_doc, region)
		var oracle_image: DrawingResult = DrawingRenderer.render(reference, region)
		check(staged_image.ok and oracle_image.ok and staged_image.value.get_data() == oracle_image.value.get_data(),
			"zoom %s batched queue exactly matches full source path bytes" % zoom_value)
		check(queued_doc.undo().ok and queued_doc.read_pixel(queued_layer, 59, 23).value == 0,
			"zoom %s one Undo reverses completed long queue" % zoom_value)
	# Selection is an edit-authorization boundary. A long queued stroke must
	# never combine source pixels from two masks if a host/shortcut changes it.
	queued_canvas.zoom = 1.0
	queued_canvas.brush_width = 1.0
	queued_canvas.tool = "Brush"
	var guarded: DrawingDocument = DrawingDocument.new("t085-selection-authorization")
	var guarded_layer: String = String(guarded.create_layer(DrawingLayerNode.RASTER, "Masked", "root").value)
	queued_canvas.document = guarded
	queued_canvas.layer_id = guarded_layer
	var original_mask: DrawingSelection = DrawingSelection.new()
	original_mask.set_rectangle(Rect2i(3, 3, 24, 24))
	check(original_mask.combine_rectangle(Rect2i(10, 10, 6, 6), "Subtract"),
		"mask with a hole assembled for queued stroke")
	queued_canvas.set_selection_mask(original_mask)
	var original_revision: int = guarded.revision
	var old_global_accumulation: bool = Input.use_accumulated_input
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(5.5, 5.5)))
	for i: int in range(120):
		queued_canvas.paint_to(Vector2i(6 + (i % 18), 7 + (i % 16)))
	check(queued_canvas.session != null and queued_canvas.session.change_count() > 0 and
		int(queued_canvas._metrics["samples_received"]) == 121,
		"complex-mask Brush has a staged dab and a long pending sample backlog")
	var same_mask: DrawingSelection = original_mask.detached_copy()
	queued_canvas.set_selection_mask(same_mask)
	check(queued_canvas.session != null and queued_canvas.dragging,
		"republishing equivalent island/hole selection does not cancel live Brush")
	var changed_mask: DrawingSelection = DrawingSelection.new()
	changed_mask.set_rectangle(Rect2i(20, 20, 18, 18))
	queued_canvas.set_selection_mask(changed_mask)
	queued_canvas.finish_gesture(queued_canvas.pixel_to_position(Vector2(25.5, 25.5)))
	queued_canvas._process(0.0)
	check(queued_canvas.session == null and not queued_canvas.dragging and
		queued_canvas._samples.is_empty() and guarded.revision == original_revision and
		guarded.history_length() == 0 and Input.use_accumulated_input == old_global_accumulation,
		"changed selection cancels queued stroke, restores input, and publishes no history")
	check(guarded.read_pixel(guarded_layer, 5, 5).value == 0 and
		guarded.read_pixel(guarded_layer, 25, 25).value == 0 and
		queued_canvas.selection_mask.same_as(changed_mask),
		"neither old nor new selection leaks content after cancellation")

	# The public legacy selected rectangle setter must obey the same guard,
	# even if it replaces a nonrectangular expression with equal outer bounds.
	queued_canvas.set_selection_mask(original_mask)
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(5.5, 5.5)))
	queued_canvas.selected = original_mask.bounds
	check(queued_canvas.session == null and guarded.revision == original_revision and
		queued_canvas.selection_mask._operations.is_empty(),
		"collapsing a hole into an equal-bounds rectangle cancels the Brush")

	# Direct mutation is unsupported as an API, but the final publication
	# guard still fails closed instead of applying a mixed authorization region.
	queued_canvas.set_selection_mask(original_mask)
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(5.5, 5.5)))
	queued_canvas.paint_to(Vector2i(24, 24))
	queued_canvas.selection_mask.set_rectangle(Rect2i(21, 21, 4, 4))
	queued_canvas.finish_gesture(queued_canvas.pixel_to_position(Vector2(24.5, 24.5)))
	check(queued_canvas.session == null and guarded.revision == original_revision and
		guarded.history_length() == 0 and guarded.read_pixel(guarded_layer, 5, 5).value == 0,
		"direct in-place mask mutation cannot publish already-staged pixels")

	# An unchanged complex mask must still finish and paint only its actual
	# allowed pixels, not the conservative rectangular bounds.
	queued_canvas.set_selection_mask(original_mask)
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(5.5, 5.5)))
	queued_canvas.paint_to(Vector2i(12, 12))
	queued_canvas.paint_to(Vector2i(20, 20))
	queued_canvas.finish_gesture(queued_canvas.pixel_to_position(Vector2(24.5, 24.5)))
	for drain: int in range(50):
		if queued_canvas.session == null:
			break
		queued_canvas._drain_segments(queued_canvas.MAX_SEGMENTS_PER_FRAME)
	check(guarded.revision == original_revision + 1 and guarded.history_length() == 1 and
		guarded.read_pixel(guarded_layer, 5, 5).value != 0 and
		guarded.read_pixel(guarded_layer, 12, 12).value == 0 and
		guarded.read_pixel(guarded_layer, 24, 24).value != 0,
		"unchanged hole mask commits in one history step with precise clipping")
	check(guarded.undo().ok and guarded.read_pixel(guarded_layer, 5, 5).value == 0 and
		guarded.read_pixel(guarded_layer, 24, 24).value == 0,
		"one Undo reverses every allowed pixel after a complex-mask stroke")

	# A selection change during Eraser also leaves the original source intact.
	var erase_setup: DrawingEditSession = guarded.begin_edit(guarded_layer, guarded.revision).value
	check(erase_setup.paint_path(PackedVector2Array([Vector2(5.5, 5.5)]), 0xff0044ff, 1.0).ok and
		erase_setup.commit().ok, "prepare committed source for guarded Eraser")
	var erase_revision: int = guarded.revision
	queued_canvas.tool = "Eraser"
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(5.5, 5.5)))
	check(queued_canvas.session != null and queued_canvas.session.change_count() > 0,
		"masked Eraser stages real source deletion")
	queued_canvas.clear_selection()
	queued_canvas.finish_gesture(queued_canvas.pixel_to_position(Vector2(8.5, 8.5)))
	check(guarded.revision == erase_revision and guarded.read_pixel(guarded_layer, 5, 5).value == 0xff0044ff and
		queued_canvas.session == null and not queued_canvas.selection_mask.enabled,
		"unselecting mid-Eraser cancels draft and preserves source and revision")
	queued_canvas.tool = "Brush"

	# Atlas can enable an empty selection as a deny-all edit boundary;
	# clearing it while a Brush is active must not promote queued pixels to
	# unrestricted paint. An inverted mask must also preserve that polarity.
	var empty_mask: DrawingSelection = DrawingSelection.new(Rect2i(), true)
	queued_canvas.set_selection_mask(empty_mask)
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(5.5, 5.5)))
	queued_canvas.paint_to(Vector2i(10, 10))
	check(queued_canvas.session != null and queued_canvas.session.change_count() == 0 and
		queued_canvas._stroke_selection.enabled and not queued_canvas._stroke_selection.allows(Vector2i(5, 5)),
		"enabled-empty selection remains deny-all inside queued Brush")
	queued_canvas.clear_selection()
	queued_canvas.finish_gesture(queued_canvas.pixel_to_position(Vector2(10.5, 10.5)))
	check(queued_canvas.session == null and guarded.history_length() == 1 and
		guarded.read_pixel(guarded_layer, 10, 10).value == 0,
		"clearing enabled-empty selection cannot publish previously forbidden pixels")
	var inverted_mask: DrawingSelection = DrawingSelection.new()
	inverted_mask.set_rectangle(Rect2i(11, 11, 4, 4))
	inverted_mask.inverted = true
	queued_canvas.set_selection_mask(inverted_mask)
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(6.5, 6.5)))
	queued_canvas.paint_to(Vector2i(12, 12))
	queued_canvas.finish_gesture(queued_canvas.pixel_to_position(Vector2(18.5, 18.5)))
	for drain: int in range(50):
		if queued_canvas.session == null:
			break
		queued_canvas._drain_segments(queued_canvas.MAX_SEGMENTS_PER_FRAME)
	check(guarded.read_pixel(guarded_layer, 6, 6).value != 0 and
		guarded.read_pixel(guarded_layer, 12, 12).value == 0 and
		guarded.read_pixel(guarded_layer, 18, 18).value != 0,
		"inverted selection permits only outside pixels throughout queued path")
	check(guarded.undo().ok and guarded.read_pixel(guarded_layer, 6, 6).value == 0,
		"inverted mask's permitted region remains one Undo operation")
	queued_canvas.set_selection_mask(null)

	# A queued press interrupted before draining must leave no ghost pixels,
	# history, or captured process-wide input configuration behind.
	var abandoned: DrawingDocument = DrawingDocument.new("t085-abandon")
	var abandoned_layer: String = String(abandoned.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	queued_canvas.document = abandoned
	queued_canvas.layer_id = abandoned_layer
	var previous_accumulation: bool = Input.use_accumulated_input
	queued_canvas.start_gesture(queued_canvas.pixel_to_position(Vector2(2.5, 2.5)))
	for i: int in range(300):
		queued_canvas.paint_to(Vector2i(i, i % 21))
	check(queued_canvas.session != null and int(queued_canvas._metrics["samples_received"]) == 301,
		"pending cancellation witness has a queued path")
	queued_canvas.cancel_gesture()
	queued_canvas._process(0.0)
	check(queued_canvas.session == null and queued_canvas._samples.is_empty() and
		abandoned.read_pixel(abandoned_layer, 2, 2).value == 0 and abandoned.history_length() == 0,
		"abandoned queue never paints or publishes after cancellation")
	check(Input.use_accumulated_input == previous_accumulation,
		"pending cancellation restores global input accumulation")
	queued_canvas.queue_free()

	print("T085_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T085_MODEL_PASSED")
	quit(1 if failures else 0)
