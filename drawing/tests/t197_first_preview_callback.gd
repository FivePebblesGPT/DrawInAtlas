extends SceneTree
## A renderer callback must not be credited as first stroke preview unless
## the submitted Canvas frame belongs to the still-live edit session.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T197_CALLBACK_FAILED: " + description)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var document: DrawingDocument = DrawingDocument.new("t197-callback", 256)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Paint").value)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(640, 480)
	canvas.document = document
	canvas.layer_id = layer
	canvas.brush_width = 40.0
	root.add_child(canvas)
	for _i in range(4):
		await process_frame
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-80, -80)))
	check(canvas.session != null and canvas._native_brush != null,
		"required native Hokusai stroke starts")
	if canvas.session == null:
		quit(1)
		return
	# Inject an unrelated callback after a first-submit time but without a
	# frame belonging to this gesture. It must not manufacture first-preview.
	var submitted_us: int = Time.get_ticks_usec() - 50
	canvas._metrics["first_preview_submit_us"] = submitted_us
	canvas._metrics["first_frame_post_draw_us"] = 0
	canvas._pending_frame_phase_sample = {}
	canvas._pending_frame_phase_session = null
	canvas._on_frame_post_draw()
	check(int(canvas._metrics["first_frame_post_draw_us"]) == 0,
		"unmatched callback cannot satisfy first-preview metric")
	# A matched but older Canvas frame before first preview submission is
	# equally invalid even when its edit session identity matches.
	canvas._pending_frame_phase_sample = {"frame_end_us": submitted_us - 10,
		"first_preview_frame": true}
	canvas._pending_frame_phase_session = canvas.session
	canvas._on_frame_post_draw()
	check(int(canvas._metrics["first_frame_post_draw_us"]) == 0,
		"pre-preview Canvas frame does not satisfy preview timing")
	canvas._pending_frame_phase_sample = {"frame_end_us": Time.get_ticks_usec(),
		"first_preview_frame": true}
	canvas._pending_frame_phase_session = DrawingEditSession.new(
		document, layer, document.revision, Transform2D.IDENTITY, 0, 0)
	canvas._on_frame_post_draw()
	check(int(canvas._metrics["first_frame_post_draw_us"]) == 0,
		"stale edit session callback cannot satisfy preview timing")
	# A matched submitted stroke frame is a valid renderer-side witness.
	var end_us: int = Time.get_ticks_usec()
	canvas._pending_frame_phase_sample = {"frame_end_us": end_us,
		"first_preview_frame": true}
	canvas._pending_frame_phase_session = canvas.session
	canvas._on_frame_post_draw()
	check(int(canvas._metrics["first_frame_post_draw_us"]) >= end_us,
		"first-preview completion uses matched frame callback")
	var first_us: int = int(canvas._metrics["first_frame_post_draw_us"])
	canvas._on_frame_post_draw()
	check(int(canvas._metrics["first_frame_post_draw_us"]) == first_us,
		"later callback cannot overwrite the first match")
	canvas.cancel_gesture()
	check(canvas.session == null and document.history_length() == 0,
		"diagnostic fixture cancels with no source publication")
	# Follow a real native brush from first changed pixel to its submitted
	# draw and renderer callback; a synthetic match alone proves too little.
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-80, -80)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(-60, -70)))
	var frames: int = 0
	while canvas.session != null and int(canvas._metrics.get(
			"first_frame_post_draw_us", 0)) == 0 and frames < 35:
		await process_frame
		frames += 1
	check(canvas.session != null and int(canvas._metrics.get(
			"first_preview_submit_us", 0)) > 0 and int(canvas._metrics.get(
			"first_frame_post_draw_us", 0)) >= int(canvas._metrics.get(
			"first_preview_submit_us", 0)),
		"real Hokusai first preview receives its matched renderer callback")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(-60, -70)))
	frames = 0
	while canvas.session != null and frames < 120:
		await process_frame
		frames += 1
	check(canvas.session == null and document.history_length() == 1,
		"real Brush still publishes one atomic native history event")
	print("T197_CALLBACK_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
