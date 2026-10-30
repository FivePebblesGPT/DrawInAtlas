class_name AtlasEditor
extends Control
## Composes one workspace: session lifecycle, document commands and UI wiring.
## Panels own forms, ArtworkEditor owns gestures, MapNavigator owns view state.

const MIN_ZOOM: float = AtlasMapNavigator.MIN_ZOOM
const MAX_ZOOM: float = AtlasMapNavigator.MAX_ZOOM
const ZOOM_FACTOR: float = AtlasMapNavigator.ZOOM_FACTOR
const NATIVE_UNITS: Array[String] = ["mi", "km", "ft", "m", "tiles"]
const BROWSER_SCENE: PackedScene = preload("res://prefab/campaign_browser.tscn")
const LAYER_PANEL_SCENE: PackedScene = preload("res://prefab/layer_panel.tscn")
const OVERVIEW_PANEL_SCENE: PackedScene = preload("res://prefab/overview_panel.tscn")

@export var sidebar: Sidebar
@export var load_saved_on_startup: bool = true
@export var save_path: String = AtlasCampaignStore.DEFAULT_PATH
@export var title_label: Label

var campaign: AtlasCampaign
var edits: AtlasEditHistory = AtlasEditHistory.new()
var store_io: AtlasStoreIO
var browser: AtlasCampaignBrowser
var layer_panel: AtlasLayerPanel
var overview_panel: AtlasOverviewPanel

@onready var canvas: AtlasCanvas = $Shell/CanvasAndInspector/Canvas
@onready var inspector: AtlasInspector = $Shell/CanvasAndInspector/InspectorPanel
@onready var status_label: Label = $Shell/Status
@onready var board_dialog: AtlasBoardDialog = $BoardDialog
@onready var raster_importer: AtlasRasterImporter = $RasterImporter
@onready var navigator: AtlasMapNavigator = AtlasMapNavigator.new(canvas)
@onready var artwork: AtlasArtworkEditor = AtlasArtworkEditor.new(canvas, edits)
@onready var link_dialog: AtlasLinkDialog = $LinkDialog
@onready var linked_maps: AtlasLinkedMaps = AtlasLinkedMaps.new(canvas, edits, navigator, link_dialog)
@onready var map_references: AtlasMapReferences = $MapReferences
@onready var link_chooser: PopupMenu = $LinkChooser
var _link_choices: Array[String] = []

# Keep existing menu/test integrations pointing at the scene-owned controls.
# These references never own another copy of the form or its state.
@onready var tool_picker: OptionButton = inspector.tool_picker
@onready var preview_picker: OptionButton = inspector.preview_picker
@onready var angle_spinner: SpinBox = inspector.angle_spinner
@onready var lock_checkbox: CheckBox = inspector.lock_checkbox
@onready var reference_checkbox: CheckBox = inspector.reference_checkbox
@onready var opacity_slider: HSlider = inspector.opacity_slider
@onready var grid_controls: AtlasGridControls = inspector.grid_controls
@onready var distance_spinner: SpinBox = grid_controls.distance_spinner
@onready var unit_picker: OptionButton = grid_controls.unit_picker
@onready var brush_color_picker: ColorPickerButton = inspector.brush_color_picker
@onready var brush_width_spinner: SpinBox = inspector.brush_width_spinner
@onready var selection_label: Label = inspector.selection_label
@onready var move_x_spinner: SpinBox = inspector.move_x_spinner
@onready var move_y_spinner: SpinBox = inspector.move_y_spinner
@onready var scale_spinner: SpinBox = inspector.scale_spinner
@onready var artwork_rotation_spinner: SpinBox = inspector.artwork_rotation_spinner
@onready var floor_picker: OptionButton = inspector.floor_picker
@onready var floor_name_input: LineEdit = inspector.floor_name_input

var map_list: ItemList:
	get: return browser.map_list
var map_list_ids: Array[String]:
	get: return browser.map_list_ids
var search_list: ItemList:
	get: return overview_panel.result_list
var search_map_ids: Array[String]:
	get: return browser.search_map_ids
var map_name_input: LineEdit:
	get: return browser.map_name_input
var map_tags_input: LineEdit:
	get: return browser.map_tags_input
var map_preview: AtlasPreviewPanel:
	get: return browser.map_preview
var history: Array[Dictionary]:
	get: return navigator.history
var view_session: AtlasViewSession:
	get: return navigator.views
var zoom_gate: AtlasZoomGate:
	get: return navigator.zoom_gate
var _startup_scope_locked: bool = false
var _startup_clipboard: String = ""
var locked_to_cell: bool:
	get: return artwork.locked_to_cell if artwork != null else _startup_scope_locked
	set(value):
		if artwork == null:
			_startup_scope_locked = value
		else:
			artwork.locked_to_cell = value
var clipboard_text: String:
	get: return artwork.clipboard_text if artwork != null else _startup_clipboard
	set(value):
		if artwork == null:
			_startup_clipboard = value
		else:
			artwork.clipboard_text = value

# Startup options can be set before _ready (including by embedding scenes).
# Once composed, the corresponding module is the sole runtime state owner.
var use_system_clipboard: bool = true:
	set(value):
		use_system_clipboard = value
		if artwork != null:
			artwork.use_system_clipboard = value
var palette_id: int = 2:
	set(value):
		palette_id = value
		if artwork != null:
			artwork.palette_id = value
var automatic_artwork_lod: bool = true
var artwork_lod: AtlasArtworkLOD = AtlasArtworkLOD.new()
var _lod_refresh_queued: bool = false

var automatic_navigation: bool = false:
	set(value):
		automatic_navigation = value
		if navigator != null:
			navigator.automatic_navigation = value


func _ready() -> void:
	artwork.clipboard_text = _startup_clipboard
	artwork.locked_to_cell = _startup_scope_locked
	_startup_clipboard = ""
	artwork.use_system_clipboard = use_system_clipboard
	artwork.palette_id = palette_id
	navigator.automatic_navigation = automatic_navigation
	map_references.bind(canvas)
	canvas.references = map_references
	_mount_sidebar_views()
	_connect_workspace()
	_on_tool_changed(tool_picker.selected)
	var restored: AtlasStoreResult
	if load_saved_on_startup:
		restored = AtlasCampaignStore.load_result(save_path, store_io)
		campaign = restored.campaign
	var loaded: bool = campaign != null
	if campaign == null:
		campaign = AtlasCampaign.sample()
	navigator.reset(campaign)
	edits.changed.connect(_refresh_edit_state)
	edits.changed.connect(_on_documents_changed)
	edits.changed.connect(map_references.refresh)
	edits.reset(campaign, loaded and (restored == null or not restored.recovered))
	_show_map(campaign.get_map(campaign.root_map_id))
	_message("B pen · E eraser · V select · F fill · L/R/O outlines · Ctrl+Z undo · Middle-drag pan")
	if restored != null and restored.recovered:
		_message(restored.message + " Save to establish a fresh checkpoint.")
	elif restored != null and restored.error != OK and restored.error != ERR_FILE_NOT_FOUND:
		_message(restored.message + " A temporary sample is open; the save was not replaced.")


func _mount_sidebar_views() -> void:
	var maps_view: Control = sidebar.get_view_content(&"Maps")
	maps_view.get_node("Heading").text = "Campaign maps"
	maps_view.get_node("Description").text = "Double-click a map to open it."
	browser = BROWSER_SCENE.instantiate() as AtlasCampaignBrowser
	maps_view.add_child(browser)
	var search_view: Control = sidebar.get_view_content(&"Search")
	search_view.get_node("Description").text = "Name, floor, kind or #tag. Double-click to open."
	overview_panel = OVERVIEW_PANEL_SCENE.instantiate() as AtlasOverviewPanel
	search_view.add_child(overview_panel)
	browser.bind_context(sidebar, overview_panel, canvas, navigator.views)
	browser.map_requested.connect(open_map)
	browser.source_focus_requested.connect(_focus_overview_source)
	browser.metadata_requested.connect(update_map_metadata)
	var layers_view: Control = sidebar.get_view_content(&"Layers")
	layers_view.get_node("Heading").hide()
	layers_view.get_node("Description").hide()
	layer_panel = LAYER_PANEL_SCENE.instantiate() as AtlasLayerPanel
	layers_view.add_child(layer_panel)
	layer_panel.layer_selected.connect(select_layer)
	layer_panel.layers_changed.connect(apply_layers)
	layer_panel.presented_detail_selected.connect(_on_presented_detail_selected)
	layer_panel.automatic_detail_toggled.connect(_on_automatic_detail_toggled)
	layer_panel.show_editing_detail_requested.connect(_show_editing_detail)
	layer_panel.import_requested.connect(raster_importer.request_import)


func _connect_workspace() -> void:
	artwork.message.connect(_message)
	artwork.layers_changed.connect(_refresh_layers)
	artwork.tool_requested.connect(_choose_tool)
	navigator.message.connect(_message)
	navigator.view_changed.connect(_on_view_changed)
	navigator.candidates_requested.connect(_show_link_choices)
	linked_maps.message.connect(_message)
	linked_maps.changed.connect(_refresh_after_history)
	link_chooser.id_pressed.connect(_choose_link)
	board_dialog.theme = sidebar.theme
	board_dialog.board_requested.connect(_on_board_requested)
	raster_importer.image_ready.connect(import_raster)
	raster_importer.failed.connect(_message)
	canvas.paint_requested.connect(artwork.paint)
	canvas.stroke_requested.connect(artwork.stroke)
	canvas.transform_requested.connect(artwork.transform_selection)
	canvas.fill_requested.connect(artwork.fill_at)
	canvas.selection_requested.connect(_on_select)
	canvas.selection_changed.connect(_on_selection_changed)
	canvas.battlemap_requested.connect(_on_create_battlemap)
	canvas.wheel_step.connect(navigator.wheel_step)
	canvas.enter_requested.connect(navigator.enter_link)
	canvas.link_candidates_requested.connect(navigator.choose_links)
	canvas.magnify_requested.connect(navigator.magnify)
	canvas.link_move_requested.connect(linked_maps.move)
	canvas.zoom_interrupted.connect(navigator.zoom_gate.reset)
	canvas.pointer_moved.connect(navigator.pointer_moved)
	canvas.interaction_started.connect(navigator.zoom_gate.reset)
	canvas.mouse_exited.connect(navigator.zoom_gate.reset)
	canvas.interaction_started.connect(artwork.refresh_scope)
	canvas.interaction_finished.connect(_queue_lod_refresh)
	canvas.view_region_changed.connect(_queue_lod_refresh)
	edits.changed.connect(_rebuild_lod)
	inspector.tool_selected.connect(_on_tool_changed)
	inspector.floor_selected.connect(switch_floor)
	inspector.floor_created.connect(create_floor)
	inspector.floor_renamed.connect(rename_floor)
	inspector.floor_moved.connect(move_floor)
	inspector.floor_default_requested.connect(make_floor_default)
	inspector.floor_removed.connect(remove_floor)
	inspector.grid_changed.connect(apply_grid)
	inspector.scope_toggled.connect(_on_scope_toggled)
	inspector.selection_transform_requested.connect(_transform_from_inspector)
	inspector.brush_color_changed.connect(func(color: Color) -> void: canvas.brush_color = color)
	inspector.brush_width_changed.connect(func(width: float) -> void: canvas.brush_width = width)
	inspector.palette_selected.connect(func(index: int) -> void: palette_id = index)
	inspector.placement_rotation_changed.connect(func(radians: float) -> void:
		canvas.battle_rotation = radians
		canvas.queue_redraw())
	inspector.preview_changed.connect(func(index: int) -> void:
		canvas.preview = index as AtlasCanvas.Preview
		map_references.refresh()
		canvas.queue_redraw())
	inspector.reference_toggled.connect(func(enabled: bool) -> void:
		canvas.show_reference = enabled
		map_references.refresh()
		canvas.queue_redraw())
	inspector.reference_opacity_changed.connect(func(value: float) -> void:
		canvas.reference_opacity = value
		canvas.queue_redraw())
	inspector.automatic_navigation_toggled.connect(func(enabled: bool) -> void:
		automatic_navigation = enabled
		zoom_gate.reset())
	inspector.linked_maps_requested.connect(linked_maps.open)
	inspector.back_requested.connect(_on_back)
	inspector.reference_source_changed.connect(map_references.select_source)
	inspector.reference_freeze_toggled.connect(map_references.set_frozen)
	inspector.sync_brush(canvas.brush_color, canvas.brush_width)


func _on_view_changed() -> void:
	link_dialog.hide()
	link_chooser.hide()
	map_references.select_source(navigator.active_entrance_id)
	edits.active_map_id = canvas.map.id
	_rebuild_lod()
	_refresh_layers()
	_refresh_grid_controls()
	locked_to_cell = false
	lock_checkbox.button_pressed = false
	inspector.refresh_floors(canvas.map, canvas.floor)
	browser.refresh_metadata()
	_refresh_edit_state()
	browser.refresh(campaign)
	_refresh_reference_controls()


func _refresh_after_history() -> void:
	navigator.reconcile_floors()
	_rebuild_lod()
	_refresh_layers()
	inspector.refresh_floors(canvas.map, canvas.floor)
	browser.refresh_metadata()
	_refresh_grid_controls()
	browser.refresh(campaign)
	_refresh_edit_state()
	canvas.queue_redraw()
	linked_maps.refresh()
	_refresh_reference_controls()


func _refresh_layers(preferred_id: String = "") -> void:
	if not preferred_id.is_empty():
		canvas.active_layer_id = preferred_id
	if canvas.floor.layer_by_id(canvas.active_layer_id) == null:
		var ink: AtlasInkLayer = canvas.floor.ink_layer()
		canvas.active_layer_id = ink.id if ink != null else ""
		if ink == null and not canvas.floor.layers.is_empty():
			canvas.active_layer_id = canvas.floor.layers[-1].id
	layer_panel.set_floor(canvas.floor, canvas.active_layer_id, canvas.presented_detail_level, automatic_artwork_lod)


func _on_presented_detail_selected(level: int) -> void:
	automatic_artwork_lod = false
	if canvas.set_presented_detail_level(level):
		_refresh_layers()
		if not canvas.editing_target_is_presented():
			var target: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
			_message("Viewing detail D%d; editing target stays %s. Select its level before editing." % [
				level, "%s (D%d)" % [target.display_name, target.detail_level] if target != null else "none"])
	else:
		_refresh_layers()


func _on_automatic_detail_toggled(enabled: bool) -> void:
	automatic_artwork_lod = enabled
	if enabled:
		_queue_lod_refresh()
	_refresh_layers()


func _show_editing_detail() -> void:
	var target: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
	if target != null:
		_on_presented_detail_selected(target.detail_level)


func _rebuild_lod() -> void:
	if canvas.map == null or canvas.floor == null:
		return
	artwork_lod.rebuild(canvas.map, canvas.floor)
	_queue_lod_refresh()


func _queue_lod_refresh() -> void:
	if not automatic_artwork_lod or _lod_refresh_queued or canvas == null:
		return
	_lod_refresh_queued = true
	call_deferred("_refresh_automatic_detail")


func _refresh_automatic_detail() -> void:
	_lod_refresh_queued = false
	if not automatic_artwork_lod or canvas.map == null or canvas.floor == null:
		return
	if canvas.is_editing():
		return # interaction_finished schedules the deferred evaluation.
	var next: int = artwork_lod.choose(canvas.map, canvas.camera_center, canvas.camera_zoom,
		canvas.size, canvas.presented_detail_level)
	if next != canvas.presented_detail_level and canvas.set_presented_detail_level(next):
		_refresh_layers()


func _refresh_grid_controls() -> void:
	if not grid_controls.get_grid().same_geometry(canvas.map.grid):
		canvas.has_selected_cell = false
		locked_to_cell = false
		lock_checkbox.set_pressed_no_signal(false)
		canvas.clear_selection()
	grid_controls.set_grid(canvas.map.grid)
	lock_checkbox.disabled = canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS
	artwork.refresh_scope()


func _refresh_edit_state() -> void:
	if canvas.map != null and campaign != null:
		title_label.text = "%s%s — %s (%s)" % [
			"* " if edits.is_dirty() else "", campaign.display_name,
			canvas.map.display_name + " / " + canvas.floor.display_name, canvas.map.kind]


func _on_documents_changed() -> void:
	if campaign == null or canvas.map == null or canvas.floor == null:
		return
	if campaign.get_map(canvas.map.id) == canvas.map and canvas.map.floor_by_id(canvas.floor.id) != null:
		browser.refresh(campaign)
		linked_maps.refresh()


func _message(value: String) -> void:
	status_label.text = value


func _clone_floors() -> Array[AtlasFloor]:
	var result: Array[AtlasFloor] = []
	for floor: AtlasFloor in canvas.map.floors:
		var copy: AtlasFloor = AtlasFloor.new()
		copy.id = floor.id
		copy.display_name = floor.display_name
		copy.layers = AtlasLayerCodec.clone_all(floor.layers)
		result.append(copy)
	return result


func _apply_floors(after: Array[AtlasFloor], default_id: String) -> bool:
	canvas.cancel_edit()
	var command: AtlasFloorEdit = AtlasFloorEdit.new(canvas.map.id, canvas.map.floors, after,
		canvas.map.default_floor_id, default_id)
	if not edits.execute(command):
		_message("Floor edit rejected: invalid/stale data or protected/referenced floor.")
		return false
	_refresh_after_history()
	return true


func create_floor(name: String) -> bool:
	if name.strip_edges().is_empty():
		_message("Choose a floor name.")
		return false
	var floor: AtlasFloor = AtlasFloor.new()
	floor.id = "floor-" + Crypto.new().generate_random_bytes(16).hex_encode()
	floor.display_name = name.strip_edges()
	floor.terrain_layer().grid = canvas.map.grid.copy()
	var after: Array[AtlasFloor] = _clone_floors()
	after.append(floor)
	if not _apply_floors(after, canvas.map.default_floor_id):
		return false
	return switch_floor(floor.id)


func rename_floor(name: String) -> bool:
	if name.strip_edges().is_empty():
		_message("Choose a floor name.")
		return false
	var after: Array[AtlasFloor] = _clone_floors()
	after[canvas.map.floors.find(canvas.floor)].display_name = name.strip_edges()
	return _apply_floors(after, canvas.map.default_floor_id)


func move_floor(direction: int) -> bool:
	var index: int = canvas.map.floors.find(canvas.floor)
	var target: int = index + direction
	if target < 0 or target >= canvas.map.floors.size():
		return false
	var after: Array[AtlasFloor] = _clone_floors()
	var floor: AtlasFloor = after[index]
	after.remove_at(index)
	after.insert(target, floor)
	return _apply_floors(after, canvas.map.default_floor_id)


func make_floor_default() -> bool:
	return _apply_floors(_clone_floors(), canvas.floor.id)


func remove_floor() -> bool:
	if canvas.map.floors.size() <= 1:
		return false
	var after: Array[AtlasFloor] = _clone_floors()
	after.remove_at(canvas.map.floors.find(canvas.floor))
	var default_id: String = canvas.map.default_floor_id
	if default_id == canvas.floor.id:
		default_id = after[0].id
	return _apply_floors(after, default_id)


func apply_grid(candidate: AtlasGrid) -> void:
	canvas.cancel_edit()
	var command: AtlasGridEdit = AtlasGridEdit.new(canvas.map.id, canvas.map.grid, candidate)
	if edits.execute(command):
		zoom_gate.reset()
		_message("Grid settings changed. Artwork coordinates are unchanged.")
	_refresh_grid_controls()
	canvas.queue_redraw()


func set_grid_visible(visible: bool) -> void:
	var candidate: AtlasGrid = canvas.map.grid.copy()
	candidate.visible = visible
	apply_grid(candidate)


func open_board_dialog() -> void:
	canvas.cancel_edit()
	board_dialog.open()


func _on_board_requested(board_name: String, grid: AtlasGrid) -> void:
	if create_board(board_name, grid):
		board_dialog.hide()
		canvas.grab_focus()


func create_board(board_name: String, grid: AtlasGrid) -> bool:
	var name: String = board_name.strip_edges()
	if name.is_empty() or not grid.is_valid():
		_message("Choose a board name and valid grid settings.")
		return false
	var id: String = "board-" + Crypto.new().generate_random_bytes(16).hex_encode()
	var document: AtlasMapDocument = AtlasMapDocument.new(id, name)
	document.kind = "BOARD"
	document.grid = grid.copy()
	document.terrain_grid = grid.copy()
	var command: AtlasCreateMap = AtlasCreateMap.new(canvas.map.id, document)
	if not edits.execute(command):
		_message("Board creation failed; the campaign was not replaced.")
		return false
	navigator.push_history()
	_show_map(campaign.get_map(id))
	_choose_tool(AtlasCanvas.Tool.PEN)
	_message("Created an independent blank board. No artwork or links were copied.")
	return true


func update_map_metadata(name: String, tags: Array[String]) -> bool:
	var command: AtlasMapMetadataEdit = AtlasMapMetadataEdit.new(canvas.map.id, canvas.map.display_name,
		canvas.map.tags, name.strip_edges(), tags)
	if not edits.execute(command):
		_message("Board metadata was unchanged or invalid.")
		return false
	browser.refresh_metadata()
	browser.refresh(campaign)
	return true


func _on_sample() -> void:
	campaign = AtlasCampaign.sample()
	_reset_view_helpers()
	edits.reset(campaign, false)
	_show_map(campaign.get_map(campaign.root_map_id))
	_message("Sample campaign reset (not saved).")


func _on_save() -> void:
	canvas.commit_edit()
	var result: Error = AtlasCampaignStore.save_campaign(campaign, save_path, store_io)
	if result == OK:
		edits.mark_saved()
	_message("Saved to %s" % save_path if result == OK else "Save failed: %s" % result)


func _on_load() -> void:
	var result: AtlasStoreResult = AtlasCampaignStore.load_result(save_path, store_io)
	if result.campaign == null:
		_message(result.message)
		return
	campaign = result.campaign
	_reset_view_helpers()
	edits.reset(campaign, not result.recovered)
	_show_map(campaign.get_map(campaign.root_map_id))
	_message(result.message + " Save to repair the current checkpoint." if result.recovered else "Campaign loaded.")


func _reset_view_helpers() -> void:
	navigator.reset(campaign)
	browser.reset_previews()
	map_references.reset()
	link_dialog.hide()
	link_chooser.hide()


func _on_undo() -> void:
	canvas.cancel_edit()
	canvas.clear_selection()
	if edits.undo():
		if campaign.get_map(canvas.map.id) == null:
			_on_back()
			if campaign.get_map(canvas.map.id) == null:
				_show_map(campaign.get_map(campaign.root_map_id))
		_refresh_after_history()
		_message("Undo applied to its original board.")
	elif edits.can_undo():
		_message("Undo blocked: the target changed outside this history.")


func _on_redo() -> void:
	canvas.cancel_edit()
	canvas.clear_selection()
	var command: AtlasEditCommand = edits.get_redo_command()
	if edits.redo():
		if command is AtlasCreateMap:
			navigator.push_history()
			_show_map(campaign.get_map(command.new_map_id))
		_refresh_after_history()
		_message("Redo applied.")
	elif edits.can_redo():
		_message("Redo blocked: the target changed outside this history.")


func _on_create_battlemap(start: Vector2, finish: Vector2, radians: float) -> void:
	linked_maps.create_drag(start, finish, radians)


func _refresh_reference_controls() -> void:
	inspector.refresh_references(campaign, canvas.map, canvas.floor,
		map_references.source_link_id, map_references.source_floor_id, map_references.frozen, not history.is_empty())


func _show_link_choices(links: Array[AtlasMapLink]) -> void:
	link_chooser.clear()
	_link_choices.clear()
	for link: AtlasMapLink in links:
		var target: AtlasMapDocument = campaign.get_map(link.target_map_id)
		if target != null:
			_link_choices.append(link.id)
			link_chooser.add_item("%d · %s / %s · arrival %s" % [_link_choices.size(), target.display_name,
				link.target_floor_id, link.target_focus], _link_choices.size() - 1)
			link_chooser.set_item_tooltip(_link_choices.size() - 1, "Entrance " + link.id)
	if not _link_choices.is_empty():
		link_chooser.popup_centered_clamped(Vector2i(360, 0), 0.9)


func _choose_link(index: int) -> void:
	if index >= 0 and index < _link_choices.size():
		navigator.enter_link(campaign.link_by_id(_link_choices[index]))


func _choose_tool(tool: AtlasCanvas.Tool) -> void:
	tool_picker.select(tool)
	_on_tool_changed(tool)


func _on_tool_changed(index: int) -> void:
	artwork.choose_tool(index as AtlasCanvas.Tool)
	if index == AtlasCanvas.Tool.BATTLEMAP and campaign != null and canvas.map != null:
		linked_maps.prepare_drag()
	inspector.refresh_tool(canvas.tool, canvas.map != null and canvas.map.grid.kind != AtlasGrid.Kind.GRIDLESS)
	if not locked_to_cell:
		lock_checkbox.set_pressed_no_signal(false)
	zoom_gate.reset()
	_on_selection_changed()


func _on_selection_changed() -> void:
	inspector.refresh_selection(canvas.selection, can_modify_selection())


func _on_scope_toggled(enabled: bool) -> void:
	canvas.cancel_edit()
	locked_to_cell = enabled
	artwork.refresh_scope()
	_message("Selected-cell scope %s." % ("enabled" if enabled else "disabled"))


func _on_select(cell: Vector2i) -> void:
	if canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS:
		_message("This board has no grid cells to select.")
		return
	canvas.selected_cell = cell
	canvas.has_selected_cell = true
	artwork.refresh_scope()
	canvas.selection_changed.emit()
	canvas.queue_redraw()
	browser.refresh_search(sidebar.get_search_query())
	_message("Selected cell %s. Lock restricts mutations, not camera movement." % cell)


func _transform_from_inspector(offset: Vector2, factor: float, radians: float) -> void:
	transform_selection(canvas.selection, AtlasSelectionGeometry.about(canvas.selection.bounds.get_center(), offset, factor, radians))


func _focus_overview_source(entry: AtlasOverviewEntry) -> void:
	if entry.can_focus and open_map(entry.source_map_id, entry.source_floor_id):
		canvas.camera_center = entry.source_focus
		canvas.queue_redraw()
		navigator.remember_view()


# Public action facade: menus and existing integrations need not know how the
# workspace is composed. All state and implementation live in the modules.
func switch_floor(id: String) -> bool:
	return navigator.switch_floor(id)


func open_map(id: String, floor_id: String = "") -> bool:
	return navigator.open_map(id, floor_id)


func _show_map(map: AtlasMapDocument, focus: Vector2 = Vector2.ZERO, zoom_value: float = 1.0,
		floor_id: String = "", layer_id: String = "") -> bool:
	return navigator.show_map(map, focus, zoom_value, floor_id, layer_id)


func _enter_link(link: AtlasMapLink) -> void:
	navigator.enter_link(link)


func _on_back() -> void:
	navigator.back()


func _on_wheel_step(direction: int, local_position: Vector2) -> void:
	navigator.wheel_step(direction, local_position)


func _on_pointer_moved(local_position: Vector2) -> void:
	navigator.pointer_moved(local_position)


func select_layer(id: String) -> void:
	artwork.select_layer(id)


func apply_layers(layers: Array[AtlasLayer], selected_id: String) -> bool:
	return artwork.apply_layers(layers, selected_id)


func _on_stroke(stroke: AtlasStroke, erasing: bool) -> void:
	artwork.stroke(stroke, erasing)


func _on_paint(cell: Vector2i) -> void:
	artwork.paint(cell)


func fill_at(point: Vector2) -> bool:
	return artwork.fill_at(point)


func transform_selection(selection: AtlasSelection, delta: Transform2D) -> bool:
	return artwork.transform_selection(selection, delta)


func select_all_artwork() -> void:
	artwork.select_all_artwork()


func can_copy_selection() -> bool:
	return artwork.can_copy_selection()


func can_modify_selection() -> bool:
	return artwork.can_modify_selection()


func copy_selection() -> bool:
	return artwork.copy_selection()


func cut_selection() -> bool:
	return artwork.cut_selection()


func paste_selection() -> bool:
	return artwork.paste_selection()


func delete_selection() -> bool:
	return artwork.delete_selection()


func paste_payload(payload: AtlasClipboardData, anchor: Vector2) -> bool:
	return artwork.paste_payload(payload, anchor)


func import_raster(image: Image) -> bool:
	return artwork.import_raster(image)


func _refresh_search_list(query: String) -> void:
	browser.refresh_search(query)


func _on_search_activated(index: int) -> void:
	browser.activate_search(index)


func _on_map_activated(index: int) -> void:
	browser.activate_map(index)


func _on_distance_changed(value: float) -> void:
	if canvas.map != null and is_finite(value) and value > 0.0:
		var candidate: AtlasGrid = canvas.map.grid.copy()
		candidate.distance_per_cell = value
		apply_grid(candidate)


func _on_unit_changed(index: int) -> void:
	if canvas.map != null and index >= 0 and index < NATIVE_UNITS.size():
		var candidate: AtlasGrid = canvas.map.grid.copy()
		candidate.distance_unit = NATIVE_UNITS[index]
		apply_grid(candidate)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_command_or_control_pressed():
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					_on_redo()
				else:
					_on_undo()
			KEY_Y: _on_redo()
			KEY_S: _on_save()
			KEY_N: open_board_dialog()
			KEY_A: select_all_artwork()
			KEY_C: copy_selection()
			KEY_X: cut_selection()
			KEY_V: paste_selection()
			KEY_F: sidebar.select_view(&"Search")
			_: return
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		zoom_gate.reset()
		if canvas.is_editing():
			canvas.cancel_edit()
		else:
			canvas.clear_selection()
		get_viewport().set_input_as_handled()
	elif (event.keycode == KEY_Q or event.keycode == KEY_E) and canvas.tool == AtlasCanvas.Tool.BATTLEMAP:
		var sign: float = -1.0 if event.keycode == KEY_Q else 1.0
		angle_spinner.value = wrapf(angle_spinner.value + 15.0 * sign, -180.0, 180.0)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		delete_selection()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_B, KEY_E, KEY_V, KEY_F, KEY_L, KEY_R, KEY_O]:
		var tools: Dictionary[int, int] = {KEY_B: AtlasCanvas.Tool.PEN, KEY_E: AtlasCanvas.Tool.ERASER,
			KEY_V: AtlasCanvas.Tool.ART_SELECT, KEY_F: AtlasCanvas.Tool.FILL, KEY_L: AtlasCanvas.Tool.LINE,
			KEY_R: AtlasCanvas.Tool.RECTANGLE, KEY_O: AtlasCanvas.Tool.ELLIPSE}
		_choose_tool(tools[event.keycode] as AtlasCanvas.Tool)
		get_viewport().set_input_as_handled()
