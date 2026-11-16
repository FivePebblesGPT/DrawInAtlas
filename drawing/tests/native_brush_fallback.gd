extends SceneTree
## T-153: unavailable native engine and missing preset fail closed, never paint through Legacy.

var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T095_NATIVE_REQUIRED_FAILED " + label)

func run() -> void:
	var available: bool = ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles")
	var doc: DrawingDocument = DrawingDocument.new("native-required")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(420, 360)
	canvas.zoom = 7.86
	canvas.document = doc
	canvas.layer_id = layer
	canvas.brush_width = 60.0
	canvas.color_rgba = 0xff547aa5
	root.add_child(canvas)
	await process_frame
	var errors: Array[String] = []
	canvas.canvas_error.connect(func(message: String) -> void: errors.append(message))
	var original_revision: int = doc.revision
	canvas.brush_preset = "nonexistent-preset"
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	check(canvas.session == null and doc.revision == original_revision,
		"unknown preset is rejected without touching source")
	check(errors.size() > 0 and ("preset" in errors[-1].to_lower() or "native" in errors[-1].to_lower()),
		"failure is visible to caller")
	canvas.brush_preset = "hard"
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-10.5, -10.5)))
	if not available:
		check(canvas.session == null and doc.revision == original_revision,
			"native unavailable: no legacy fallback")
		check(errors.size() > 0 and "native" in errors[-1].to_lower(),
			"native missing error exposed")
	else:
		check(canvas.session != null and canvas._active_brush_backend == "Hokusai",
			"required native Hokusai path engaged")
		canvas.cancel_gesture()
		check(canvas.session == null and doc.revision == original_revision,
			"cancellation releases transaction without mutation")
	canvas.queue_free()
	print("T095_NATIVE_REQUIRED_RESULT checks=%d failures=%d present=%s" % [
		checks, failures, str(available)])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
