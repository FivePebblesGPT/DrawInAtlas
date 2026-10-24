extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ORGANIZATION UI FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	var directory: String = "user://organization-ui-%d" % Time.get_ticks_usec()
	editor.save_path = directory + "/campaign.json"
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var canvas: AtlasCanvas = editor.canvas
	canvas.camera_center = Vector2(-20.5, 14.25)
	canvas.camera_zoom = 1.7
	var overlay: AtlasGrid = canvas.map.grid.copy()
	overlay.kind = AtlasGrid.Kind.SQUARE
	overlay.cell_size = 80.0
	editor.apply_grid(overlay)
	_check(editor.create_floor("Upper"), "add creates an independent floor")
	var world: AtlasMapDocument = canvas.map
	var upper_id: String = canvas.floor.id
	_check(world.default_floor_id == "ground" and upper_id != "ground" and world.floors.size() == 2,
		"adding/activating floor does not change document default")
	_check(canvas.floor.strokes.is_empty() and canvas.floor.terrain.is_empty(), "new floor copies no artwork")
	_check(canvas.camera_center == Vector2(-20.5, 14.25) and canvas.camera_zoom == 1.7,
		"first visit inherits camera for aligned floors")
	canvas.camera_center = Vector2(140, -75)
	canvas.camera_zoom = 2.3
	editor.layer_panel._add_ink()
	var upper_layer: String = canvas.active_layer_id
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(-1.25, 0.5), Vector2(24.125, 12.75)])), false)
	editor.edits.mark_saved()
	var canonical: Dictionary = editor.campaign.to_dict()
	_check(editor.switch_floor("ground"), "existing floor activates")
	_check(canvas.floor.id == "ground" and canvas.camera_center == Vector2(-20.5, 14.25)
		and canvas.camera_zoom == 1.7, "ground camera is restored exactly")
	_check(editor.campaign.to_dict() == canonical and not editor.edits.is_dirty(), "floor navigation never dirties canonical data")
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), Color.RED), false)
	_check((world.floor_by_id(upper_id).layer_by_id(upper_layer) as AtlasInkLayer).strokes.size() == 1
		and world.floor_by_id("ground").strokes.size() == 1, "artwork edit targets only the active floor")
	_check(editor.switch_floor(upper_id) and canvas.camera_center == Vector2(140, -75)
		and canvas.camera_zoom == 2.3 and canvas.active_layer_id == upper_layer, "return restores floor camera and layer preference")
	editor.floor_name_input.text = "Tower top"
	editor.floor_name_input.text_submitted.emit(editor.floor_name_input.text)
	_check(canvas.floor.display_name == "Tower top", "floor rename is wired through UI")
	editor._on_undo()
	_check(canvas.floor.display_name == "Upper", "undo floor rename keeps its art and identity")
	editor._on_redo()
	_check(editor.move_floor(-1) and world.floors[0].id == upper_id and canvas.floor.id == upper_id,
		"floor reorder keeps the viewer on the same stable identity")
	_check(editor.make_floor_default() and world.default_floor_id == upper_id, "default floor changes only on explicit action")
	_check(world.get_terrain_grid("ground").kind == AtlasGrid.Kind.HEX_POINTY
		and world.get_terrain_grid("ground").cell_size == 45.0
		and world.get_terrain_grid(upper_id).cell_size == 80.0, "default/reorder never rebase legacy terrain geometry")
	_check(world.grid.cell_size == 80.0 and world.grid.distance_unit == "mi" and world.grid.distance_per_cell == 3.0,
		"floor controls never change board grid or exploration scale")
	_check(editor.open_map("greyhaven") and editor.create_floor("Roof"), "another board has its own floor set")
	var roof_id: String = canvas.floor.id
	var pixels: Image = Image.create(12, 10, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.2, 0.4, 0.6, 0.5))
	editor.import_raster(pixels)
	var roof_layer: String = canvas.active_layer_id
	_check(editor.update_map_metadata("Greyhaven tower", ["town", "tower"]), "board rename and tags are reversible metadata edits")
	editor._on_back()
	_check(canvas.map.id == "world" and canvas.floor.id == upper_id
		and canvas.camera_center == Vector2(140, -75) and canvas.camera_zoom == 2.3
		and canvas.active_layer_id == upper_layer, "Back restores source floor, exact camera and selected layer")
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = "upper-to-roof"
	link.source_map_id = "world"
	link.source_floor_id = upper_id
	link.target_map_id = "greyhaven"
	link.target_floor_id = roof_id
	link.anchor = Vector2(-200, -200)
	link.target_focus = Vector2(33.5, -11.25)
	link.target_zoom = 2.0
	editor.campaign.links.append(link)
	editor._enter_link(link)
	_check(canvas.map.id == "greyhaven" and canvas.floor.id == roof_id and canvas.camera_center == link.target_focus
		and canvas.camera_zoom == 2.0 and canvas.active_layer_id == roof_layer, "link arrives at its explicit floor/camera with valid layer preference")
	editor._on_back()
	var count: int = editor.history.size()
	var focus: Vector2 = canvas.camera_center
	var valid_floor: String = link.target_floor_id
	link.target_floor_id = "missing"
	editor._enter_link(link)
	_check(editor.history.size() == count and canvas.floor.id == upper_id and canvas.camera_center == focus,
		"failed floor arrival keeps source view and history untouched")
	link.target_floor_id = valid_floor
	editor.edits.mark_saved()
	canonical = editor.campaign.to_dict()
	editor.overview_panel.mode_picker.select(AtlasOverview.Filter.MAP)
	editor._refresh_search_list("")
	_check(editor.overview_panel.entries.size() == 1 and editor.overview_panel.entries[0].link_id == link.id,
		"current-floor overview excludes ground-floor entrances")
	_check(editor.campaign.find_links_at("world", link.anchor, "ground").is_empty()
		and editor.campaign.find_links_at("world", link.anchor, upper_id).size() == 1, "canvas hit tests honor source floor")
	editor.overview_panel.mode_picker.select(AtlasOverview.Filter.CAMPAIGN)
	editor._refresh_search_list("#tower")
	_check(editor.overview_panel.entries.size() == 2, "tag query finds both floors of the tagged board")
	editor._refresh_search_list("Roof")
	_check(editor.overview_panel.entries.size() == 1 and editor.overview_panel.entries[0].floor_id == roof_id,
		"floor-name search retains exact target floor metadata")
	editor.overview_panel.entry_activated.emit(editor.overview_panel.entries[0])
	_check(canvas.map.id == "greyhaven" and canvas.floor.id == roof_id, "overview Open activates the selected floor")
	_check(editor.campaign.to_dict() == canonical and not editor.edits.is_dirty(), "search/open/preview requests are read-only")
	_check(not editor.remove_floor() and canvas.map.floor_by_id(roof_id) != null, "referenced floor cannot be removed")
	_check(editor.create_floor("Spare"), "unreferenced floor create")
	var spare_id: String = canvas.floor.id
	_check(editor.remove_floor() and canvas.map.floor_by_id(canvas.floor.id) != null,
		"deleting active floor selects a valid fallback")
	editor._on_undo()
	_check(canvas.map.floor_by_id(spare_id) != null and editor.switch_floor(spare_id), "undo removal restores floor identity and contents")
	editor._on_save()
	var saved: Dictionary = editor.campaign.to_dict()
	editor._on_load()
	_check(editor.campaign.to_dict() == saved and canvas.map.id == "world" and canvas.floor.id == upper_id,
		"schema6 save/load preserves metadata/floors and uses persisted startup default")
	var city: AtlasMapDocument = editor.campaign.get_map("greyhaven")
	var raster: AtlasRasterLayer = city.floor_by_id(roof_id).layer_by_id(roof_layer) as AtlasRasterLayer
	_check(raster != null and raster.chunks["0,0"].image.get_data() == pixels.get_data(), "inactive floor raster data is fully persisted")
	root.remove_child(scene)
	scene.free()
	_remove(directory)
	_check(await _overview_ui(), "native overview integration completes without a runtime error")
	print("ATLAS_ORGANIZATION_UI_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


## Exercise the composed workspace, panel signals and viewport GUI dispatch.
## Preview pixels are covered by the separate real-renderer acceptance suite.
func _overview_ui() -> bool:
	var old_size: Vector2i = root.size
	var old_scale_size: Vector2i = root.content_scale_size
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 1200)
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "source"
	var source: AtlasMapDocument = AtlasMapDocument.new("source", "Source board")
	var balcony: AtlasFloor = AtlasFloor.new()
	balcony.id = "balcony"
	balcony.display_name = "Balcony"
	source.floors.append(balcony)
	source.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 80.0)
	source.grid.origin = Vector2(-1000, 200)
	source.grid.rotation = PI / 4.0
	var target: AtlasMapDocument = AtlasMapDocument.new("target", "Twin destination")
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	upper.display_name = "Upper destination"
	target.floors.append(upper)
	campaign.add_map(source)
	campaign.add_map(target)
	campaign.add_map(AtlasMapDocument.new("child", "Deep descendant"))
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	editor.campaign = campaign
	root.add_child(scene)
	editor.sidebar.select_view(&"Search")
	await _settle()
	var canvas: AtlasCanvas = editor.canvas
	var panel: AtlasOverviewPanel = editor.overview_panel
	var open_button: Button = panel.get_node("OpenButton")
	var focus_button: Button = panel.get_node("FocusButton")
	_check(panel.is_visible_in_tree() and canvas.size.x > 400 and canvas.size.y > 300,
		"Search view mounts the real overview beside a usable canvas")

	var cell: Vector2i = Vector2i(-2, 1)
	var center: Vector2 = source.grid.cell_to_document(cell)
	canvas.camera_center = center
	canvas.camera_zoom = 1.7
	var half_width: float = canvas.size.x / (2.0 * canvas.camera_zoom)
	var first: AtlasMapLink = _entrance(campaign, "01-door", center + Vector2(-10, 0))
	var second: AtlasMapLink = _entrance(campaign, "02-door", center + Vector2(10, 0))
	var edge: AtlasMapLink = _entrance(campaign, "03-edge", center + Vector2(half_width + 2, 0))
	edge.hit_radius = 4.0
	_entrance(campaign, "04-outside", center + Vector2(half_width + 100, 0))
	# In the rotated square's AABB, but outside its actual diamond polygon.
	_entrance(campaign, "05-cell-aabb-decoy", center + Vector2(-50, -50))
	_entrance(campaign, "06-local-pixel-decoy", canvas.size * 0.5)
	var inactive: AtlasMapLink = _entrance(campaign, "07-inactive-floor", center)
	inactive.source_floor_id = balcony.id
	var placed: AtlasMapLink = _entrance(campaign, "08-placed", center + Vector2(9999, 9999))
	var placement: AtlasPlacement = AtlasPlacement.new()
	placement.id = "rotated-room"
	placement.parent_map_id = source.id
	placement.child_map_id = target.id
	placement.origin = center + Vector2(15, 10)
	placement.rotation = 0.3
	placement.columns = 2
	placement.rows = 1
	placement.parent_units_per_cell = 12.0
	campaign.placements.append(placement)
	placed.placement_id = placement.id
	var descendant: AtlasMapLink = _entrance(campaign, "09-descendant", Vector2(99999, 99999))
	descendant.source_map_id = target.id
	descendant.target_map_id = "child"
	var canonical: Dictionary = campaign.to_dict()
	editor.edits.mark_saved()
	_check(canvas.local_to_document(canvas.size * 0.5).is_equal_approx(center)
		and canvas.local_to_document(Vector2.ZERO).is_equal_approx(center - canvas.size / 3.4),
		"translated negative document camera and nonunit zoom map viewport center/corner")
	_check(canvas.document_to_local(second.anchor).is_equal_approx(canvas.size * 0.5 + Vector2(17, 0)),
		"document marker maps to canvas-local pixels independently of sidebar offset")
	panel.recursive_checkbox.button_pressed = false
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	var visible_ids: Array[String] = ["01-door", "02-door", "03-edge", "05-cell-aabb-decoy", "08-placed"]
	_expect_ids(panel, visible_ids,
		"VISIBLE maps canvas corners to document units; includes circle overlap/placement, excludes pixels/offscreen/inactive floor")
	_check(not panel.recursive_checkbox.disabled and panel.result_list.item_count == visible_ids.size(),
		"VISIBLE enables recursion control and populates native ItemList")
	panel.recursive_checkbox.button_pressed = true
	_expect_ids(panel, visible_ids + ["09-descendant"],
		"VISIBLE recursion follows accepted entrances even when descendant anchor is outside source viewport")
	panel.recursive_checkbox.button_pressed = false

	# Each gesture starts with a fresh mode selection. There is deliberately no
	# query/mode change between the gesture and its live-result assertion.
	var shift: Vector2 = Vector2(half_width + 100, 0)
	_pan(canvas, -shift * canvas.camera_zoom)
	await _settle()
	_check(canvas.camera_center.is_equal_approx(center + shift),
		"native middle-drag pans by relative screen pixels divided by zoom")
	_expect_ids(panel, ["03-edge", "04-outside"], "VISIBLE refreshes automatically after user pans")
	_mode(panel, AtlasOverview.Filter.MAP)
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	_expect_ids(panel, ["03-edge", "04-outside"], "reselecting VISIBLE uses the panned document region")

	canvas.camera_center = center
	canvas.camera_zoom = 1.7
	_mode(panel, AtlasOverview.Filter.MAP)
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	_click(canvas, canvas.size * 0.5, MOUSE_BUTTON_WHEEL_UP)
	await _settle()
	_check(is_equal_approx(canvas.camera_zoom, 2.04) and canvas.camera_center.is_equal_approx(center),
		"native wheel dispatch reaches navigator and keeps center pointer anchored")
	var zoomed_ids: Array[String] = ["01-door", "02-door", "05-cell-aabb-decoy", "08-placed"]
	_expect_ids(panel, zoomed_ids, "VISIBLE refreshes automatically after user zooms")
	_mode(panel, AtlasOverview.Filter.MAP)
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	_expect_ids(panel, zoomed_ids, "reselecting VISIBLE uses the zoomed document region")
	var pointer: Vector2 = canvas.size * Vector2(0.3, 0.4)
	var under_pointer: Vector2 = canvas.local_to_document(pointer)
	_click(canvas, pointer, MOUSE_BUTTON_WHEEL_UP)
	_check(canvas.local_to_document(pointer).is_equal_approx(under_pointer),
		"off-center wheel preserves the document point beneath native pointer")

	canvas.camera_center = center
	canvas.camera_zoom = 1.7
	_mode(panel, AtlasOverview.Filter.MAP)
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	var old_canvas_size: Vector2 = canvas.size
	root.size += Vector2i(600, 0)
	await _settle()
	_check(canvas.size.x > old_canvas_size.x + 500 and canvas.camera_center.is_equal_approx(center),
		"native window resize expands the real canvas without moving document center")
	var resized_ids: Array[String] = ["01-door", "02-door", "03-edge", "04-outside", "05-cell-aabb-decoy", "08-placed"]
	_expect_ids(panel, resized_ids, "VISIBLE refreshes automatically after viewport resize")
	_mode(panel, AtlasOverview.Filter.MAP)
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	_expect_ids(panel, resized_ids, "reselecting VISIBLE uses the resized canvas extent")

	_mode(panel, AtlasOverview.Filter.CELL)
	_check(panel.entries.is_empty() and panel.summary.text.contains("Select a cell")
		and open_button.disabled and focus_button.disabled,
		"CELL without selection explains empty results and disables both actions")
	# Select through the real tool picker and viewport, not by setting cell state.
	editor.tool_picker.select(AtlasCanvas.Tool.SELECT)
	editor.tool_picker.item_selected.emit(AtlasCanvas.Tool.SELECT)
	_click(canvas, canvas.document_to_local(center))
	_check(canvas.has_selected_cell and canvas.selected_cell == cell,
		"native SELECT click converts camera pixels through rotated/translated board grid")
	var cell_ids: Array[String] = ["01-door", "02-door", "08-placed"]
	_expect_ids(panel, cell_ids, "CELL uses the selected rotated polygon, excluding its AABB decoy and distant entrances")
	panel.recursive_checkbox.button_pressed = true
	_expect_ids(panel, cell_ids + ["09-descendant"], "CELL checkbox refresh includes descendants outside the selected region")
	panel.recursive_checkbox.button_pressed = false
	var next_cell: Vector2i = cell + Vector2i.DOWN
	_click(canvas, canvas.document_to_local(source.grid.cell_to_document(next_cell)))
	_check(canvas.selected_cell == next_cell and panel.entries.is_empty(),
		"CELL immediately refreshes when native selection moves to an empty neighboring cell")
	_click(canvas, canvas.document_to_local(center))

	_select_entry(panel, second.id)
	_check(panel.selected_entry() != null and panel.selected_entry().link_id == second.id
		and panel.entries[0].map_id == panel.entries[1].map_id
		and panel.entries[0].floor_id == panel.entries[1].floor_id,
		"duplicate destination map/floor entrances remain separately selectable rows")
	_mode(panel, AtlasOverview.Filter.VISIBLE)
	_check(panel.selected_entry() != null and panel.selected_entry().link_id == second.id,
		"changing filters preserves selected entrance identity rather than first duplicate target")
	panel.recursive_checkbox.button_pressed = true
	_check(panel.selected_entry() != null and panel.selected_entry().link_id == second.id,
		"recursive result rebuild preserves the second entrance identity")
	panel.recursive_checkbox.button_pressed = false
	_click(focus_button, focus_button.size * 0.5)
	_check(canvas.map.id == source.id and canvas.floor.id == "ground"
		and canvas.camera_center.is_equal_approx(second.anchor) and editor.history.is_empty(),
		"native Focus uses the selected duplicate's source anchor without adding same-floor history")
	_select_entry(panel, first.id)
	_click(focus_button, focus_button.size * 0.5)
	_check(canvas.camera_center.is_equal_approx(first.anchor), "the other duplicate focuses its distinct source anchor")
	_select_entry(panel, placed.id)
	_click(focus_button, focus_button.size * 0.5)
	_check(canvas.camera_center.is_equal_approx(placement.local_to_parent() * Vector2(1, 0.5)),
		"placed entrance Focus uses transformed footprint center instead of remote anchor")
	_select_entry(panel, second.id)
	_click(open_button, open_button.size * 0.5)
	_check(canvas.map.id == target.id and canvas.floor.id == "ground" and editor.history.size() == 1,
		"native Open navigates selected entrance destination through browser and navigator")
	editor._on_back()
	_check(canvas.map.id == source.id and canvas.floor.id == "ground" and not canvas.has_selected_cell,
		"Back restores source identity and clears document-specific cell selection")
	_mode(panel, AtlasOverview.Filter.CELL)
	_check(panel.entries.is_empty() and panel.summary.text.contains("Select a cell"),
		"CELL does not reuse selected-cell geometry after document navigation")
	_check(campaign.to_dict() == canonical and not editor.edits.is_dirty(),
		"all spatial queries, camera gestures, selection and entrance navigation preserve canonical data")

	_check(await _broken_ui(editor, center), "broken-target integration completes without a runtime error")
	root.remove_child(scene)
	scene.free()
	root.content_scale_size = old_scale_size
	root.size = old_size
	return true


func _broken_ui(editor: AtlasEditor, center: Vector2) -> bool:
	var canvas: AtlasCanvas = editor.canvas
	var panel: AtlasOverviewPanel = editor.overview_panel
	var campaign: AtlasCampaign = editor.campaign
	var open_button: Button = panel.get_node("OpenButton")
	var focus_button: Button = panel.get_node("FocusButton")
	var missing_map: AtlasMapLink = _entrance(campaign, "broken-map", center + Vector2(0, 15))
	missing_map.target_map_id = "absent-board"
	var missing_floor: AtlasMapLink = _entrance(campaign, "broken-floor", center + Vector2(0, -15))
	missing_floor.target_floor_id = "absent-floor"
	var missing_placement: AtlasMapLink = _entrance(campaign, "broken-placement", center + Vector2(15, 0))
	missing_placement.placement_id = "absent-placement"
	# The broken edge is discovered recursively on another source floor, so
	# Focus must resolve both identities, not merely center the current board.
	var bridge: AtlasMapLink = _entrance(campaign, "10-upper-bridge", center)
	bridge.target_floor_id = "upper"
	var remote: AtlasMapLink = _entrance(campaign, "broken-remote", Vector2(-31.5, 44.25))
	remote.source_map_id = "target"
	remote.source_floor_id = "upper"
	remote.target_map_id = "absent-remote"
	var canonical: Dictionary = campaign.to_dict()
	editor.edits.mark_saved()
	_mode(panel, AtlasOverview.Filter.MAP)
	panel.recursive_checkbox.button_pressed = true
	for link: AtlasMapLink in [missing_map, missing_floor, missing_placement, remote]:
		# Return to the root before each case: remote Focus changes documents.
		editor.open_map("source", "ground")
		_select_entry(panel, link.id)
		var entry: AtlasOverviewEntry = panel.selected_entry()
		_check(entry != null and entry.link_id == link.id and not entry.broken_reason.is_empty()
			and open_button.disabled and not focus_button.disabled,
			"broken target disables Open but retains usable source Focus: " + link.id)
		var before_map: String = canvas.map.id
		var before_floor: String = canvas.floor.id
		var before_center: Vector2 = canvas.camera_center
		var before_zoom: float = canvas.camera_zoom
		var before_history: Array[Dictionary] = editor.history.duplicate(true)
		_click(open_button, open_button.size * 0.5)
		_check(canvas.map.id == before_map and canvas.floor.id == before_floor
			and canvas.camera_center == before_center and canvas.camera_zoom == before_zoom
			and editor.history == before_history, "disabled native Open leaves view/history intact: " + link.id)
		# ItemList activation is a separate route from the disabled button.
		var selected: PackedInt32Array = panel.result_list.get_selected_items()
		if not selected.is_empty():
			panel.result_list.item_activated.emit(selected[0])
		_check(canvas.map.id == before_map and canvas.floor.id == before_floor
			and canvas.camera_center == before_center and editor.history == before_history,
			"broken row activation also rejects navigation: " + link.id)
		_click(focus_button, focus_button.size * 0.5)
		_check(canvas.map.id == link.source_map_id and canvas.floor.id == link.source_floor_id
			and canvas.camera_center.is_equal_approx(link.anchor),
			"native Focus reaches exact valid source map/floor/anchor despite broken target: " + link.id)
	_check(editor.history.size() == 1 and editor.history[-1]["map_id"] == "source"
		and editor.history[-1]["floor_id"] == "ground", "cross-board broken-source Focus records the return view")
	editor._on_back()
	_check(canvas.map.id == "source" and canvas.floor.id == "ground", "Back returns from broken target's source Focus")
	_check(campaign.to_dict() == canonical and not editor.edits.is_dirty(),
		"broken Open/Focus actions do not repair or mutate canonical references")
	return true


func _entrance(campaign: AtlasCampaign, id: String, anchor: Vector2) -> AtlasMapLink:
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = id
	link.source_map_id = "source"
	link.source_floor_id = "ground"
	link.target_map_id = "target"
	link.target_floor_id = "ground"
	link.anchor = anchor
	link.hit_radius = 1.0
	campaign.links.append(link)
	return link


func _mode(panel: AtlasOverviewPanel, mode: AtlasOverview.Filter) -> void:
	panel.mode_picker.select(mode)
	panel.mode_picker.item_selected.emit(mode)


func _expect_ids(panel: AtlasOverviewPanel, expected: Array, label: String) -> void:
	var actual: Array[String] = []
	for entry: AtlasOverviewEntry in panel.entries:
		actual.append(entry.link_id)
	_check(actual == expected, "%s; expected %s, got %s" % [label, expected, actual])


func _select_entry(panel: AtlasOverviewPanel, link_id: String) -> void:
	for index: int in range(panel.entries.size()):
		if panel.entries[index].link_id == link_id:
			panel.result_list.select(index)
			panel.result_list.item_selected.emit(index)
			return
	_check(false, "required native result row exists: " + link_id)


func _mouse_button(control: Control, local: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = control.get_global_transform_with_canvas() * local
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	event.factor = 1.0
	root.push_input(event, true)


func _click(control: Control, local: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = control.get_global_transform_with_canvas() * local
	motion.global_position = motion.position
	root.push_input(motion, true)
	_mouse_button(control, local, button, true)
	_mouse_button(control, local, button, false)


func _pan(canvas: AtlasCanvas, relative: Vector2) -> void:
	var local: Vector2 = canvas.size * 0.5
	_mouse_button(canvas, local, MOUSE_BUTTON_MIDDLE, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = canvas.get_global_transform_with_canvas() * local
	motion.global_position = motion.position
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion, true)
	_mouse_button(canvas, local, MOUSE_BUTTON_MIDDLE, false)


func _settle() -> void:
	for frame: int in range(6):
		await process_frame


func _remove(path: String) -> void:
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(name))
	DirAccess.remove_absolute(path)
