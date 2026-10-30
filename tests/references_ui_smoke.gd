extends SceneTree
## Real-renderer acceptance: full-artwork crops, transforms, freeze and isolation.

var checks: int = 0
var failures: int = 0
var editor: AtlasEditor
var canvas: AtlasCanvas
var campaign: AtlasCampaign
var placement: AtlasPlacement
var parent_raster: AtlasRasterLayer
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("REFERENCES UI FAILED: " + label)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires a native real renderer (use Xvfb/Mesa)")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	campaign = _fixture()
	_scene = load("res://main.tscn").instantiate()
	editor = _scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.campaign = campaign
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(_scene)
	await _frames(8)
	canvas = editor.canvas
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.reference_opacity = 1.0
	for phase: String in ["_spatial_parent", "_freeze_and_sources", "_child_previews", "_preview_budget", "_cancellation"]:
		_check(await call(phase) == true, phase + " completes")
	root.remove_child(_scene)
	_scene.free()
	print("ATLAS_REFERENCES_UI_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _fixture() -> AtlasCampaign:
	var result: AtlasCampaign = AtlasCampaign.new()
	result.root_map_id = "parent"
	var parent: AtlasMapDocument = AtlasMapDocument.new("parent", "City source")
	parent.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 40.0)
	parent.grid.visible = false
	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			parent.floors[0].paint(Vector2i(x, y), 4)
	parent_raster = _raster(Color.RED, Vector2(-80, -80), Vector2i(79, 160))
	parent.floors[0].layers.append(parent_raster)
	var ink: AtlasInkLayer = AtlasInkLayer.new("top-ink", "Top ink")
	ink.strokes.append(AtlasStroke.new(PackedVector2Array([Vector2(-10, -100), Vector2(-10, 100)]), Color.GREEN, 8.0))
	parent.floors[0].layers.append(ink)
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	upper.display_name = "Blue upper floor"
	upper.layers.append(_raster(Color.BLUE, Vector2(-96, -96), Vector2i(192, 192)))
	parent.floors.append(upper)
	var child: AtlasMapDocument = AtlasMapDocument.new("child", "Encounter")
	child.grid.visible = false
	var other: AtlasMapDocument = AtlasMapDocument.new("other", "Unregistered source")
	other.grid.visible = false
	other.floors[0].layers.append(_raster(Color.GREEN, Vector2.ZERO, Vector2i(64, 64)))
	result.add_map(parent)
	result.add_map(child)
	result.add_map(other)
	placement = AtlasPlacement.new()
	placement.id = "aligned"
	placement.parent_map_id = parent.id
	placement.child_map_id = child.id
	placement.origin = Vector2(-40, -30)
	placement.rotation = deg_to_rad(37.0)
	placement.columns = 4
	placement.rows = 3
	placement.parent_units_per_cell = 20.0
	placement.child_units_per_cell = 64.0
	result.placements.append(placement)
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = "spatial-door"
	link.source_map_id = parent.id
	link.target_map_id = child.id
	link.placement_id = placement.id
	link.target_focus = placement.child_bounds().get_center()
	result.links.append(link)
	var symbolic: AtlasPlacement = AtlasPlacement.from_dict(placement.to_dict())
	symbolic.id = "symbolic"
	symbolic.parent_map_id = other.id
	symbolic.origin = Vector2(3000, 3000)
	symbolic.rotation = 0
	symbolic.symbolic = true
	result.placements.append(symbolic)
	var portal: AtlasMapLink = AtlasMapLink.from_dict(link.to_dict())
	portal.id = "symbolic-door"
	portal.source_map_id = other.id
	portal.placement_id = symbolic.id
	result.links.append(portal)
	return result


func _raster(color: Color, origin: Vector2, size: Vector2i) -> AtlasRasterLayer:
	var pixels: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	layer.id = "raster-" + color.to_html()
	layer.transform = Transform2D(0.0, origin)
	return layer


func _spatial_parent() -> bool:
	_check(editor.navigator.enter_link(campaign.link_by_id("spatial-door")), "enter through a specific spatial entrance")
	await _frames(14)
	_check(editor.map_references.source_link_id == "spatial-door", "actual entrance disambiguates multiple parents")
	_check(_color_at(placement.parent_point_to_child(Vector2(-30, -10)), Color.RED), "rotated reference contains parent raster artwork")
	_check(_color_at(placement.parent_point_to_child(Vector2(-10, 10)), Color.GREEN), "reference contains top ink in canonical layer order")
	_check(_color_at(placement.parent_point_to_child(Vector2(10, 20)), AtlasCanvas.TERRAIN_COLORS[4]), "reference contains terrain using source content geometry")
	_check(_color_at(Vector2(-20, -10), AtlasCanvas.EMPTY_COLOR), "reference is cropped at the child footprint boundary")
	var before: Dictionary = campaign.get_map("parent").to_dict()
	var bytes: PackedByteArray = parent_raster.chunks["0,0"].image.get_data()
	var point: Vector2 = placement.parent_point_to_child(Vector2(-30, -10))
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([point]), Color.YELLOW, 12.0), false)
	await _frames(14)
	_check(_color_at(point, Color.YELLOW), "child painting draws above the read-only reference")
	_check(campaign.get_map("parent").to_dict() == before and parent_raster.chunks["0,0"].image.get_data() == bytes,
		"editing child leaves parent metadata and exact pixels unchanged")
	editor.inspector.reference_checkbox.button_pressed = false
	await _frames(8)
	_check(_color_at(point, Color.YELLOW), "hiding reference does not remove child artwork")
	_check(_color_at(placement.parent_point_to_child(Vector2(10, 20)), AtlasCanvas.EMPTY_COLOR), "hide removes only derived parent image")
	editor.inspector.reference_checkbox.button_pressed = true
	editor.inspector.opacity_slider.value = 0.5
	await _frames(14)
	_check(_color_at(placement.parent_point_to_child(Vector2(10, 20)), AtlasCanvas.EMPTY_COLOR.lerp(AtlasCanvas.TERRAIN_COLORS[4], 0.5)), "reference opacity composites once over board background")
	editor.inspector.opacity_slider.value = 1.0
	return true


func _freeze_and_sources() -> bool:
	await _frames(8)
	editor.edits.mark_saved()
	var before: Dictionary = campaign.to_dict()
	editor.inspector.freeze_checkbox.button_pressed = true
	await _frames(4)
	_check(campaign.to_dict() == before and not editor.edits.is_dirty(), "freeze is viewer state, never campaign data")
	editor.inspector.reference_checkbox.button_pressed = false
	await _frames(4)
	parent_raster.chunks["0,0"].image.fill(Color.MAGENTA)
	editor.edits.mark_external_change()
	await _frames(14)
	var point: Vector2 = placement.parent_point_to_child(Vector2(-30, 0))
	_check(_color_at(point, AtlasCanvas.EMPTY_COLOR), "hidden frozen reference does not draw during source updates")
	editor.inspector.reference_checkbox.button_pressed = true
	await _frames(14)
	_check(_color_at(point, Color.RED), "frozen snapshot ignores later source pixel changes")
	var original_origin: Vector2 = placement.origin
	placement.origin += Vector2(60, 0)
	editor.edits.mark_external_change()
	await _frames(14)
	_check(_color_at(point, Color.RED), "frozen reference retains its captured registration when the source footprint moves")
	placement.origin = original_origin
	editor.edits.mark_external_change()
	editor.inspector.freeze_checkbox.button_pressed = false
	await _frames(14)
	_check(_color_at(point, Color.MAGENTA), "unfreezing recaptures live artwork, invalidating old pixel hashes")
	editor.inspector.reference_floor_picker.select(1)
	editor.inspector.reference_floor_picker.item_selected.emit(1)
	await _frames(14)
	_check(_color_at(point, Color.BLUE), "source floor selection captures independent floor artwork")
	_check(campaign.link_by_id("spatial-door").source_floor_id == "ground", "reference floor preference never rewrites the entrance")
	before = campaign.to_dict()
	editor.inspector.reference_source_picker.select(2)
	editor.inspector.reference_source_picker.item_selected.emit(2)
	await _frames(14)
	_check(editor.map_references.source_link_id == "symbolic-door", "explicitly choose another parent entrance")
	_check(_color_at(point, AtlasCanvas.EMPTY_COLOR), "symbolic reference does not claim physical alignment")
	_check(not _screen_color(Vector2(84, 76), Color.GREEN), "symbolic source cannot float an unregistered picture on the editor")
	_check(campaign.to_dict() == before, "source/floor/opacity preferences do not edit documents")
	return true


func _child_previews() -> bool:
	var child: AtlasMapDocument = campaign.get_map("child")
	child.floors[0].layers.append(_raster(Color.BLUE, Vector2.ZERO, Vector2i(256, 192)))
	editor.edits.mark_external_change()
	editor.open_map("parent")
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 2.0
	editor.preview_picker.select(AtlasCanvas.Preview.OVERLAY)
	editor.preview_picker.item_selected.emit(AtlasCanvas.Preview.OVERLAY)
	await _frames(18)
	var source: Vector2 = Vector2(-30, -10)
	_check(_color_at(source, Color.MAGENTA.lerp(Color.BLUE, 0.7)), "spatial child overlay includes raster art with the exact rotated footprint mapping")
	var strong_color: Color = root.get_texture().get_image().get_pixelv(
		Vector2i(canvas.global_position + canvas.document_to_local(source)))
	editor.preview_picker.select(AtlasCanvas.Preview.THUMBNAILS)
	editor.preview_picker.item_selected.emit(AtlasCanvas.Preview.THUMBNAILS)
	await _frames(14)
	var faint_color: Color = root.get_texture().get_image().get_pixelv(
		Vector2i(canvas.global_position + canvas.document_to_local(source)))
	_check(faint_color.r > strong_color.r + 0.08 and faint_color.b > 0.90,
		"faint preview remains spatially aligned with reduced opacity")
	editor.open_map("other")
	canvas.camera_center = Vector2(3040, 3030)
	canvas.camera_zoom = 1.0
	editor.preview_picker.select(AtlasCanvas.Preview.OVERLAY)
	editor.preview_picker.item_selected.emit(AtlasCanvas.Preview.OVERLAY)
	await _frames(14)
	_check(_color_at(Vector2(3010, 3010), AtlasCanvas.EMPTY_COLOR.lerp(Color(0.24, 0.70, 0.82), 0.15)),
		"symbolic footprint shows its marker, not falsely aligned child pixels")
	var records: Dictionary = editor.map_references.get("_children")
	_check(not records.has("symbolic-door"),
		"symbolic link is marker-only: no fabricated registration or expensive capture")
	DirAccess.make_dir_recursive_absolute("user://validation")
	_check(root.get_texture().get_image().save_png("user://validation/linked-map-references.png") == OK, "save native milestone-6 preview evidence")
	return true


func _cancellation() -> bool:
	editor.open_map("child")
	editor.map_references.select_source("spatial-door", "ground")
	await _frames(1)
	editor.open_map("other")
	canvas.camera_center = Vector2.ZERO
	await _frames(14)
	_check((editor.map_references.get("_parent") as Dictionary).is_empty(), "navigation cancels old parent images before they can publish")
	var capture: AtlasMapCapture = editor.map_references.get("_capture")
	_check(capture.viewport == null or capture.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"completed/cancelled captures do not keep rendering")
	_check(capture.canvas == null or capture.canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"private reference renderer cannot receive editing input")
	return true


func _preview_budget() -> bool:
	editor.open_map("parent")
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	for index: int in range(9):
		var link: AtlasMapLink = AtlasMapLink.new()
		link.id = "budget-%d" % index
		link.source_map_id = "parent"
		link.target_map_id = "child"
		link.anchor = Vector2((index - 4) * 30, 220)
		_check(editor.edits.execute(AtlasLinkEdit.new("parent", null, link)), "visible marker setup %d" % index)
	await _frames(40)
	var records: Dictionary = editor.map_references.get("_children")
	_check(records.size() <= AtlasMapReferences.MAX_CHILD_PREVIEWS and editor.map_references.omitted_count == 0,
		"unplaced entrances stay markers and consume no preview capture budget")
	_check(editor.map_references.cache.entry_count() <= 16, "reference image cache stays bounded across crops, floors and links")
	return true


func _color_at(point: Vector2, expected: Color) -> bool:
	return _screen_color(canvas.document_to_local(point), expected)


func _screen_color(local: Vector2, expected: Color) -> bool:
	var pixels: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position + local)
	if not Rect2i(Vector2i.ZERO, pixels.get_size()).has_point(point):
		return false
	var color: Color = pixels.get_pixelv(point)
	return absf(color.r - expected.r) < 0.045 and absf(color.g - expected.g) < 0.045 and absf(color.b - expected.b) < 0.045


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw
