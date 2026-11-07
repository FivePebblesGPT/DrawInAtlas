extends SceneTree
## Real mouse Brush/Eraser paths: sharp single-pixel edges and dirty-display refresh.

var checks: int = 0
var failures: int = 0

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PR14_PIXEL_FAILED: " + label)

func frames(count: int = 5) -> void:
	for _n in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func pointer(canvas: Control, point: Vector2, down: bool) -> void:
	var at: Vector2 = canvas.global_position + canvas.pixel_to_position(point)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func motion(canvas: Control, point: Vector2) -> void:
	var at: Vector2 = canvas.global_position + canvas.pixel_to_position(point)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func draw_stroke(canvas: Control, from: Vector2, to: Vector2) -> void:
	pointer(canvas, from, true)
	for index in range(1, 13):
		motion(canvas, from.lerp(to, float(index) / 12.0))
	pointer(canvas, to, false)
	var remaining: int = 300
	while canvas.session != null and remaining > 0:
		await process_frame
		remaining -= 1
	verify(canvas.session == null, "live pointer stroke drains and commits")
	await frames(3)

func sample(canvas: Control, point: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	return image.get_pixelv(Vector2i(canvas.global_position + canvas.pixel_to_position(point)))

func same_rgb(a: Color, b: Color, tolerance: float = 0.035) -> bool:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)) < tolerance

func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("PR14_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	verify(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK,
		"capture " + name)

func test_sharp_edge(canvas: Control, label: String) -> void:
	# Red one-source-pixel line at x=0 against opaque blue source pixels.
	# An unfiltered boundary has only these two colors, no interpolated colors.
	var image: Image = root.get_texture().get_image()
	var edge: float = canvas.global_position.x + canvas.pixel_to_position(Vector2.ZERO).x
	var y: int = roundi(canvas.global_position.y + canvas.pixel_to_position(Vector2(0, 0.5)).y)
	var red_count: int = 0
	var blue_count: int = 0
	var intermediate_count: int = 0
	for x in range(floori(edge) - 12, ceili(edge) + 22):
		var color: Color = image.get_pixel(x, y)
		if same_rgb(color, Color8(255, 48, 48)):
			red_count += 1
		elif same_rgb(color, Color8(31, 51, 89)):
			blue_count += 1
		else:
			intermediate_count += 1
	verify(red_count >= 6 and blue_count >= 12 and intermediate_count == 0,
		"pixel-sharp red/blue edge after " + label + " (red=%d blue=%d mixed=%d)" %
		[red_count, blue_count, intermediate_count])

## Sample every framebuffer pixel around the intersection of four separately
## composited display tiles. A center-only check misses 1px checkerboard gaps.
func verify_opaque_cross(canvas: Control, label: String) -> void:
	var image: Image = root.get_texture().get_image()
	var center: Vector2 = canvas.global_position + canvas.pixel_to_position(Vector2.ZERO)
	var errors: int = 0
	for y: int in range(roundi(center.y) - 12, roundi(center.y) + 13):
		for x: int in range(roundi(center.x) - 12, roundi(center.x) + 13):
			if not same_rgb(image.get_pixel(x, y), Color8(31, 51, 89)):
				errors += 1
	verify(errors == 0, "opaque Brush pixels show no display-tile seam " + label + " (%d mixed)" % errors)


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(10)
	var canvas: Control = app.canvas
	canvas.zoom = 7.86
	canvas.camera = Vector2.ZERO
	canvas.snap_to_grid = false
	canvas.show_grid = false
	canvas.show_pixel_grid = false # Disable guides to isolate filtering.
	app._change_tool("Brush")
	app.width_spin.value = 60.0
	canvas.color_rgba = 0xff59331f # Opaque blue: R31 G51 B89 A255.
	await frames(3)
	verify(canvas.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"raster canvas explicitly uses nearest-neighbor filtering")
	verify(canvas.brush_width == 60.0, "Brush control sets the 60px width")
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	# Just two actual wide mouse strokes cover the same ~132x84 visible area
	# the user had to laboriously cover without a bucket tool.
	for yy in [-28.0, 28.0]:
		await draw_stroke(canvas, Vector2(-65, yy), Vector2(65, yy))
	verify(doc.read_pixel(layer, -1, 0).value == 0xff59331f and
		doc.read_pixel(layer, 0, 0).value == 0xff59331f,
		"60px Brush paints matching source colors across negative/positive tile boundary")
	verify(same_rgb(sample(canvas, Vector2(-0.5, 0.5)), sample(canvas, Vector2(0.5, 0.5))),
		"framebuffer does not show a central Brush-painted tile seam")
	canvas.pointer_known = false
	canvas.queue_redraw()
	await frames()
	verify_opaque_cross(canvas, "at integer camera")
	canvas.camera = Vector2(0.17, 0.21)
	canvas.queue_redraw()
	await frames()
	verify_opaque_cross(canvas, "at fractional camera")
	canvas.camera = Vector2.ZERO
	canvas.queue_redraw()
	await frames()
	screenshot("pr14-brush60-covered")
	# Paint a single-pixel high-contrast stripe on top. Sampling only pixel
	# centers misses bilinear interpolation, so inspect *every screen pixel*.
	app.width_spin.value = 1.0
	canvas.color_rgba = 0xff3030ff # Opaque red.
	await draw_stroke(canvas, Vector2(0.5, -15.5), Vector2(0.5, 15.5))
	canvas.pointer_known = false
	canvas.queue_redraw()
	await frames()
	verify(doc.read_pixel(layer, 0, 0).value == 0xff3030ff and
		doc.read_pixel(layer, -1, 0).value == 0xff59331f,
		"1px Brush produces adjacent, exact, contrasting source colors")
	test_sharp_edge(canvas, "unshifted viewport")
	screenshot("pr14-brush1-edge")
	canvas.camera = Vector2(0.17, 0.21)
	canvas.queue_redraw()
	await frames()
	test_sharp_edge(canvas, "fractional pan")
	# Erase through the display tile intersection. Verify actual saved pixels,
	# not a direct fill_rect / clear_rect mutation or cache-only change.
	app._change_tool("Eraser")
	app.width_spin.value = 4.0
	await draw_stroke(canvas, Vector2(-2.5, 0.5), Vector2(2.5, 0.5))
	canvas.pointer_known = false
	canvas.queue_redraw()
	await frames()
	verify(doc.read_pixel(layer, -1, 0).value == 0 and
		doc.read_pixel(layer, 0, 0).value == 0 and
		doc.read_pixel(layer, 1, 0).value == 0,
		"real Eraser clears source pixels on both sides of tile boundary")
	var after: Color = sample(canvas, Vector2(0.5, 0.5))
	verify(not same_rgb(after, Color8(255, 48, 48)) and
		not same_rgb(after, Color8(31, 51, 89)),
		"framebuffer removes erased painted pixels instead of displaying stale tile")
	screenshot("pr14-brush-erased")
	# The same public UI Delete command must retire painted source bytes and
	# refresh the display even if a neighboring painted chunk stays resident.
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-10, 4, 21, 14), true)
	canvas.set_selection_mask(selection)
	app._delete_selection()
	canvas.clear_selection()
	canvas.queue_redraw()
	await frames()
	verify(doc.read_pixel(layer, -4, 8).value == 0 and
		doc.read_pixel(layer, 4, 8).value == 0,
		"Selection Delete removes Brush pixels in both adjacent storage chunks")
	verify(not same_rgb(sample(canvas, Vector2(-3.5, 8.5)), Color8(31, 51, 89)) and
		not same_rgb(sample(canvas, Vector2(4.5, 8.5)), Color8(31, 51, 89)),
		"Selection Delete does not leave phantom pixels on either display tile")
	print("PR14_BRUSH_PIXEL: %d checks; %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
