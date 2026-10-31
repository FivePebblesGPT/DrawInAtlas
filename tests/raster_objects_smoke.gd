extends SceneTree
## Raster tools own pixels; semantic tools and image props own Objects.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("RASTER/OBJECTS FAILED: " + label)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Raster and Objects", AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 64)), "create hex board")
	var canvas: AtlasCanvas = editor.canvas
	_check(canvas.active_layer_id == "raster" and canvas.tool == AtlasCanvas.Tool.PEN, "new boards start painting raster")
	_check(canvas.floor.raster_layer().pixels_per_unit == 4.0, "painting resolution is quadrupled on both axes")
	_check(canvas.floor.layer_by_id("objects") is AtlasObjectsLayer and canvas.floor.objects_layer().kind == "OBJECTS",
		"designated Objects replaces the authored Ink layer")
	for tool: AtlasCanvas.Tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER, AtlasCanvas.Tool.FILL,
			AtlasCanvas.Tool.LINE, AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.POLYGON]:
		canvas.active_layer_id = "objects"
		editor._choose_tool(tool)
		_check(canvas.active_layer_id == "raster" and canvas.tool == tool, "raster tool routes automatically: %s" % tool)
	for tool: AtlasCanvas.Tool in [AtlasCanvas.Tool.WALL_PATH, AtlasCanvas.Tool.TEXT, AtlasCanvas.Tool.ART_SELECT, AtlasCanvas.Tool.MOVE]:
		canvas.active_layer_id = "raster"
		editor._choose_tool(tool)
		_check(canvas.active_layer_id == "objects" and canvas.tool == tool, "object tool routes automatically: %s" % tool)
	for tool: AtlasCanvas.Tool in [AtlasCanvas.Tool.LINE, AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE]:
		editor._choose_tool(tool)
		var before: Dictionary = canvas.floor.raster_layer().to_dict()
		var press: InputEventMouseButton = InputEventMouseButton.new()
		press.position = canvas.document_to_local(Vector2(-4, -3))
		canvas._begin_left_press(press)
		canvas._append_stroke_point(canvas.document_to_local(Vector2(4, 3)))
		canvas.commit_edit()
		_check(canvas.floor.raster_layer().to_dict() != before and canvas.floor.objects_layer().strokes.is_empty(),
			"shape commits pixels and creates no vector object: %s" % tool)
		editor._on_undo()
		_check(canvas.floor.raster_layer().to_dict() == before, "shape undo restores exact raster")
	editor._choose_tool(AtlasCanvas.Tool.POLYGON)
	canvas.polygon_solid_fill = true
	for point: Vector2 in [Vector2(-4, -3), Vector2(4, -3), Vector2(0, 4)]:
		var press: InputEventMouseButton = InputEventMouseButton.new()
		canvas._begin_polygon_vertex(press, point)
	canvas.commit_edit()
	_check(not canvas.floor.raster_layer().chunks.is_empty() and canvas.floor.objects_layer().strokes.is_empty(),
		"solid polygon fills raster pixels")
	editor._choose_tool(AtlasCanvas.Tool.WALL_PATH)
	var wall: AtlasStroke = AtlasEditablePath.make(PackedVector2Array([Vector2(-8, 8), Vector2(8, 8)]), Color.WHITE, 2.0, false)
	editor.artwork.edit_path(-1, null, wall)
	_check(canvas.floor.objects_layer().strokes.size() == 1 and canvas.floor.objects_layer().strokes[0].editable_path,
		"wall remains independently editable on Objects")
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	editor.artwork.edit_text(-1, null, AtlasTextLayout.make(Vector2.ZERO, "Object text", "Sans", 16, Color.WHITE))
	_check(canvas.floor.objects_layer().strokes.size() == 2 and canvas.floor.objects_layer().strokes[1].is_text(), "text lives on Objects")
	var image: Image = Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8, 0.5))
	var raster_before: Dictionary = canvas.floor.raster_layer().to_dict()
	_check(editor.artwork.import_prop(image), "image import creates a placed object")
	var object: AtlasStroke = canvas.floor.objects_layer().strokes[-1]
	_check(object.is_prop() and object.prop_dimensions() == Vector2(4, 2), "prop uses 4px/unit and retains original image dimensions")
	_check(editor.artwork.transform_selection(canvas.selection, Transform2D(0.0, Vector2(3, 2))), "prop can be moved independently")
	_check(canvas.floor.raster_layer().to_dict() == raster_before, "object placement never transforms raster artwork")
	editor.artwork.use_system_clipboard = false
	var prop_count: int = canvas.floor.objects_layer().strokes.size()
	_check(editor.artwork.copy_selection() and editor.artwork.paste_selection(), "image props copy/paste through the typed object clipboard")
	_check(canvas.floor.objects_layer().strokes.size() == prop_count + 1
		and canvas.floor.objects_layer().strokes[-1].prop_webp == object.prop_webp, "prop paste preserves exact encoded pixels")
	var restored: AtlasLayer = AtlasLayerCodec.clone(canvas.floor.objects_layer())
	_check(restored is AtlasObjectsLayer and (restored as AtlasObjectsLayer).strokes[-1].prop_webp == object.prop_webp,
		"Objects clone preserves lossless prop data")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	var slot: String = "user://validation/raster-objects-regression.scn"
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK, "save raster plus semantic objects")
	var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(slot)
	_check(loaded.campaign != null and loaded.campaign.to_dict() == editor.campaign.to_dict(), "native roundtrip preserves all object types and raster pixels")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
	var source: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	var bounds: Rect2 = AtlasSelectionGeometry.raster_local_bounds(source)
	var dense: AtlasRasterLayer = source.at_paint_density()
	_check(dense.pixels_per_unit == 4 and dense.chunks["0,0"].width == 64 and dense.chunks["0,0"].height == 32,
		"existing raster content is quadrupled per dimension")
	_check(AtlasSelectionGeometry.raster_local_bounds(dense) == bounds and source.chunks["0,0"].width == 16,
		"density upgrade preserves document size and source snapshot")
	var chunk: AtlasRasterChunk = source.chunks["0,0"]
	source.chunks.clear()
	chunk.coord = Vector2i(-1, -1)
	source.chunks["-1,-1"] = chunk
	source.transform = Transform2D(0.3, Vector2(7, -3))
	dense = source.at_paint_density()
	_check(dense.chunks.has("-4,-4") and dense.transform == source.transform
		and AtlasSelectionGeometry.raster_local_bounds(dense) == AtlasSelectionGeometry.raster_local_bounds(source),
		"density upgrade preserves signed chunk placement and affine transforms")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_RASTER_OBJECTS_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
