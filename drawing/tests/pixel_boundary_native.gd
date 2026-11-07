extends SceneTree
## Nearest-neighbor pixel presentation and erase-cache invalidation at signed boundaries.

var checks: int = 0
var failures: int = 0

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PR14_PIXEL_FAILED: " + label)

func frames(count: int = 6) -> void:
	for _i in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func sample(canvas: Control, pixel: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(pixel))
	return image.get_pixelv(point)

func capture_if_requested(name: String) -> void:
	var folder: String = OS.get_environment("PR14_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	verify(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK,
		"capture " + name)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	root.add_child(app)
	await frames(10)
	var canvas: Control = app.canvas
	canvas.zoom = 8.0
	canvas.camera = Vector2.ZERO
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	var ed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	var filled: DrawingResult = ed.fill_rect(Rect2i(-62, -36, 124, 72), 0xff59331f)
	verify(filled.ok and ed.commit().ok, "fill RGBA region spanning negative/positive source chunk")
	canvas.queue_redraw()
	canvas.view_changed.emit()
	await frames(10)
	verify(canvas.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "nearest-neighbor canvas filtering")
	verify(canvas.show_pixel_grid and canvas.zoom >= 6.0, "automatic pixel grid active at 800%")
	var expected: Color = sample(canvas, Vector2(-1.5, 0.5))
	var actual: Color = sample(canvas, Vector2(0.5, 0.5))
	verify(Vector3(expected.r, expected.g, expected.b).distance_to(Vector3(actual.r, actual.g, actual.b)) < 0.01, "no framebuffer seam at x=0 in painted pixels")
	verify(expected.b > 0.3 and expected.r < expected.b, "opaque blue pixel is visible")
	verify(doc.read_pixel(layer, -1, 0).value == 0xff59331f and doc.read_pixel(layer, 0, 0).value == 0xff59331f, "source colors exact at chunk boundary")
	capture_if_requested("pr14-painted-seam-grid")
	var clear: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	verify(clear.clear_rect(Rect2i(-2, -2, 5, 5)).ok and clear.commit().ok, "erase crossing source boundary")
	canvas.queue_redraw()
	await frames(10)
	verify(doc.read_pixel(layer, -1, 0).value == 0 and doc.read_pixel(layer, 0, 0).value == 0, "erase clears underlying storage")
	var transparent: Color = sample(canvas, Vector2(-1.5, 0.5))
	verify(Vector3(transparent.r, transparent.g, transparent.b).distance_to(Vector3(expected.r, expected.g, expected.b)) > 0.2, "framebuffer updates after erase")
	capture_if_requested("pr14-erased-seam-grid")
	print("PR14_PIXEL: %d checks; %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
