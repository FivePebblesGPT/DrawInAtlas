extends SceneTree
## T-018: shared-board hierarchy and independent navigation links.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("HIERARCHY FAILED: " + message)


func _find(item: TreeItem, kind: String, id: String = "") -> TreeItem:
	if item == null:
		return null
	var data: Variant = item.get_metadata(0)
	if data is Dictionary and data.get("kind") == kind and (id.is_empty() or data.get("id") == id):
		return item
	var child: TreeItem = item.get_first_child()
	while child != null:
		var match_item: TreeItem = _find(child, kind, id)
		if match_item != null:
			return match_item
		child = child.get_next()
	return null


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(7):
		await process_frame
	var panel: AtlasLayerPanel = editor.layer_panel
	editor.sidebar.select_view(&"Layers")
	_check(panel.hierarchy.visible and not panel.layer_list.visible, "hierarchy replaces visible flat list")
	_check(not panel.name_input.visible and not panel.opacity_spinner.visible, "layer form starts collapsed")
	_check(_find(panel.hierarchy.get_root(), "group") != null, "shared authored-detail group exists")
	var selected_row: TreeItem = _find(panel.hierarchy.get_root(), "layer", editor.canvas.active_layer_id)
	_check(selected_row != null, "explicit edit layer appears")
	_check(selected_row != null and selected_row.get_button_count(0) == 1,
		"layer row exposes its own settings action")
	_check(_find(panel.hierarchy.get_root(), "link") != null, "independent map navigation shown separately")
	_check(not editor.inspector.get_node("Scroll/Margin/Sections/ReferenceSection/ManageLinks").visible,
		"duplicated inspector linked-maps entry is hidden")
	panel.layer_settings_button.pressed.emit()
	_check(panel.name_input.visible and panel.opacity_spinner.visible and panel.layer_detail_spinner.visible,
		"selected layer settings are available in a compact disclosure")
	panel.layer_settings_button.pressed.emit()
	_check(not panel.name_input.visible, "layer disclosure closes without mutating data")
	var raster_row: TreeItem = _find(panel.hierarchy.get_root(), "layer", "raster")
	if raster_row != null:
		panel._on_hierarchy_button(raster_row, 0, AtlasLayerPanel.LAYER_SETTINGS, 1)
		_check(editor.canvas.active_layer_id == "raster" and panel.name_input.visible,
			"inline layer-settings action selects correct editing target")
		panel.layer_settings_button.pressed.emit()
	var map_count: int = editor.campaign.maps.size()
	var link_count: int = editor.campaign.links.size()
	var ink_id: String = editor.canvas.active_layer_id
	var ink: AtlasInkLayer = editor.canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	if ink == null:
		editor.layer_panel._add_ink()
		ink_id = editor.canvas.active_layer_id
		ink = editor.canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	var before_strokes: int = ink.strokes.size()
	var position: Vector2 = Vector2(-30, 55)
	editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([position, position + Vector2(60, 0)])), false)
	var stroke: TreeItem = _find(panel.hierarchy.get_root(), "stroke", ink_id)
	_check(stroke != null and ink.strokes.size() == before_strokes + 1, "new editable object is listed under layer")
	if stroke != null:
		stroke.select(0)
		panel._on_hierarchy_selected()
		_check(editor.canvas.selection.layer_id == ink_id and not editor.canvas.selection.stroke_indices.is_empty(),
			"choosing object selects only the current layer's ink")
	_check(editor.campaign.maps.size() == map_count and editor.campaign.links.size() == link_count,
		"authoring an object does not create a child map or link")
	editor.canvas.clear_selection()
	var current_row: TreeItem = panel.hierarchy.get_selected()
	var current_data: Variant = current_row.get_metadata(0) if current_row != null else null
	_check(current_data is Dictionary and current_data.get("kind") == "layer",
		"deselecting object returns highlight to explicit editing layer")
	panel.layer_detail_spinner.value = 1
	var d1: TreeItem = _find(panel.hierarchy.get_root(), "layer", ink_id)
	_check(d1 != null and d1.get_parent().get_text(0).begins_with("D1"),
		"moving authored layer detail only regroups hierarchy")
	_check(editor.campaign.maps.size() == map_count, "changing authored detail does not create documents")
	var existing_link: AtlasMapLink = editor.campaign.links[0] if not editor.campaign.links.is_empty() else null
	if existing_link != null and existing_link.source_map_id == editor.canvas.map.id:
		var link_row: TreeItem = _find(panel.hierarchy.get_root(), "link", existing_link.id)
		_check(link_row != null and link_row.get_button_count(0) == 3,
			"each map relationship exposes locate/edit/enter actions inline")
		if link_row != null:
			panel._on_hierarchy_button(link_row, 0, AtlasLayerPanel.LINK_FOCUS, 1)
			_check(editor.canvas.selected_link_id == existing_link.id and
				editor.canvas.camera_center.distance_to(existing_link.anchor) < 0.01,
				"locate link centers view without making it the edit target")
			panel._on_hierarchy_button(link_row, 0, AtlasLayerPanel.LINK_EDIT, 1)
			_check(editor.link_dialog.selected_id == existing_link.id,
				"edit opens the existing native-safe link form for this relationship")
			editor.link_dialog.hide()
	_check(editor.campaign.maps.size() == map_count, "link actions never synthesize map documents")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_LAYER_HIERARCHY_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
