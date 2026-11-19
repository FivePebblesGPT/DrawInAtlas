extends SceneTree
## Reproducible PNG reference generation from the production native Canvas path.
## Requires both DrawingNativeBrush and DrawingNativeTiles; no icon synthesis.

const PRESETS: Array[String] = ["hard", "soft", "ink", "airbrush"]
const AREA: Rect2i = Rect2i(-62, -25, 124, 50)

func _initialize() -> void:
	call_deferred("run")


func alpha_sum(bytes: PackedByteArray) -> int:
	var total: int = 0
	for i: int in range(3, bytes.size(), 4):
		total += bytes[i]
	return total


func run() -> void:
	if not ClassDB.class_exists("DrawingNativeBrush") or not ClassDB.class_exists("DrawingNativeTiles"):
		printerr("T184_PREVIEW_FAILED: native backend not loaded")
		quit(1)
		return
	var output: String = OS.get_environment("T184_PREVIEW_OUTPUT")
	if output.is_empty():
		printerr("T184_PREVIEW_FAILED: set T184_PREVIEW_OUTPUT")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for preset: String in PRESETS:
		var workspace: Control = load("res://main.tscn").instantiate()
		workspace.layout_persistence_enabled = false
		workspace.preferences_persistence_enabled = false
		root.add_child(workspace)
		await process_frame
		await process_frame
		var canvas: Control = workspace.canvas
		var document: DrawingDocument = workspace.current_document()
		var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Preview").value)
		canvas.layer_id = layer
		canvas.tool = "Brush"
		canvas.brush_preset = preset
		canvas.brush_width = 18.0
		canvas.color_rgba = 0xff292929
		canvas.zoom = 1.0
		canvas.camera = Vector2.ZERO
		canvas.image_bounds = Rect2i(-128, -128, 256, 256)
		await process_frame
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(17):
			var x: float = -51.5 + float(i) * 6.0
			points.append(Vector2(x, 5.0 * sin(float(i) / 16.0 * PI) - 1.5))
		canvas.start_gesture(canvas.pixel_to_position(points[0]))
		for i: int in range(1, points.size() - 1):
			canvas.update_gesture(canvas.pixel_to_position(points[i]))
			await process_frame
		canvas.finish_gesture(canvas.pixel_to_position(points[-1]))
		for frame: int in range(360):
			if canvas.session == null:
				break
			await process_frame
		var result: DrawingResult = DrawingRenderer.render(document, AREA)
		if canvas.session != null or not result.ok:
			printerr("T184_PREVIEW_FAILED: native commit " + preset)
			quit(1)
			return
		var pigment_total: int = alpha_sum(result.value.get_data())
		if pigment_total <= 1000:
			printerr("T184_PREVIEW_FAILED: empty native pigment for " + preset)
			quit(1)
			return
		print("T184_NATIVE_STROKE ", preset, " rev=", document.revision,
			" alpha_sum=", pigment_total,
			" metrics=", canvas.last_gesture_metrics.get("samples_received", -1))
		var image: Image = result.value
		image.resize(92, 32, Image.INTERPOLATE_LANCZOS)
		var path: String = output.path_join(preset + ".png")
		if image.save_png(path) != OK:
			printerr("T184_PREVIEW_FAILED: save " + path)
			quit(1)
			return
		print("T184_PREVIEW " + preset + " " + FileAccess.get_sha256(path))
		workspace.queue_free()
		await process_frame
	print("T184_PREVIEWS_PASSED")
	quit(0)
