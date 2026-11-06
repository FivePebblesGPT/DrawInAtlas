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
	print("T085_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T085_MODEL_PASSED")
	quit(1 if failures else 0)
