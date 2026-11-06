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
		await process_frame
		_check(editor.canvas.active_layer_id == "raster" and panel.name_input.visible,
			"inline layer-settings action selects correct editing target")
		panel.layer_settings_button.pressed.emit()
	var map_count: int = editor.campaign.maps.size()
	var link_count: int = editor.campaign.links.size()
	var ink_id: String = editor.canvas.active_layer_id
	var ink: AtlasObjectsLayer = editor.canvas.floor.layer_by_id(ink_id) as AtlasObjectsLayer
	if ink == null:
		editor.layer_panel._add_objects()
		ink_id = editor.canvas.active_layer_id
		ink = editor.canvas.floor.layer_by_id(ink_id) as AtlasObjectsLayer
	var before_strokes: int = ink.strokes.size()
	var position: Vector2 = Vector2(-30, 55)
	editor.artwork.edit_path(-1, null, AtlasEditablePath.make(PackedVector2Array([position, position + Vector2(60, 0)]), Color.WHITE, 2.0, false))
	var stroke: TreeItem = _find(panel.hierarchy.get_root(), "stroke", ink_id)
	_check(stroke != null and ink.strokes.size() == before_strokes + 1, "new editable object is listed under layer")
	if stroke != null:
		stroke.select(0)
		panel._on_hierarchy_selected()
		await process_frame
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
	_test_large_object_layer(editor, panel)
	await _test_stale_link_rows(editor, panel)
	root.remove_child(scene)
	scene.free()
	print("ATLAS_LAYER_HIERARCHY_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)


## A large Objects layer should still show its newest items. Canvas selections in
## the omitted middle must surface a transient row without expanding the whole list.
func _test_large_object_layer(editor: AtlasEditor, panel: AtlasLayerPanel) -> void:
	var before_maps: int = editor.campaign.maps.size()
	panel._add_objects()
	var layer_id: String = editor.canvas.active_layer_id
	var layer: AtlasObjectsLayer = editor.canvas.floor.layer_by_id(layer_id) as AtlasObjectsLayer
	_check(layer != null, "large-object witness has a live Objects layer")
	if layer == null:
		return
	for index: int in range(110):
		var x: float = float(index) * 4.0
		layer.strokes.append(AtlasStroke.new(PackedVector2Array([
			Vector2(x, 200.0), Vector2(x + 2.0, 200.0)]), Color.WHITE, 1.0))
	editor._refresh_layers()
	var first_key: String = "%s:0" % layer_id
	var last_key: String = "%s:109" % layer_id
	var middle_key: String = "%s:55" % layer_id
	_check(panel._stroke_rows.has(first_key) and panel._stroke_rows.has(last_key),
		"oldest and newly added objects both appear beyond the row limit")
	_check(_count_layer_strokes(panel, layer_id) == AtlasLayerPanel.MAX_STROKE_ROWS and
		not panel._stroke_rows.has(middle_key), "large layer stays bounded with a middle gap")
	var layer_row: TreeItem = panel._layer_rows[layer_id]
	var child: TreeItem = layer_row.get_first_child()
	var omitted: int = 0
	while child != null:
		var data: Variant = child.get_metadata(0)
		if data is Dictionary and data.get("kind") == "summary":
			omitted += 1
		child = child.get_next()
	_check(omitted == 1, "omitted objects are explained by a nonselectable gap row")

	editor.canvas.selection = AtlasSelectionGeometry.select_indices(layer, [55])
	editor.canvas.selection_changed.emit()
	var selected: TreeItem = panel.hierarchy.get_selected()
	_check(panel._stroke_rows.has(middle_key) and _count_layer_strokes(panel, layer_id) == 81,
		"a canvas-selected middle object gets one temporary row")
	_check(selected != null and selected.get_metadata(0).get("kind") == "stroke"
		and selected.get_metadata(0).get("index") == 55,
		"middle object is highlighted with its canonical stroke index")
	_check(editor.canvas.active_layer_id == layer_id and editor.campaign.maps.size() == before_maps,
		"showing the middle row never changes the editing target or map registry")
	editor._refresh_layers()
	selected = panel.hierarchy.get_selected()
	_check(selected != null and selected.get_metadata(0).get("index") == 55,
		"selected middle object survives an ordinary hierarchy redraw")

	editor.canvas.clear_selection()
	selected = panel.hierarchy.get_selected()
	_check(not panel._stroke_rows.has(middle_key) and _count_layer_strokes(panel, layer_id) == 80,
		"deselection removes the temporary row and restores the bound")
	_check(selected != null and selected.get_metadata(0).get("kind") == "layer",
		"clearing the canvas selection highlights the editing layer")

	editor.canvas.selection = AtlasSelectionGeometry.select_indices(layer, [55])
	editor.canvas.selection_changed.emit()
	layer.strokes[55].width = 3.0
	panel.sync_object_selection(editor.canvas.selection)
	selected = panel.hierarchy.get_selected()
	_check(not panel._stroke_rows.has(middle_key) and selected != null
		and selected.get_metadata(0).get("kind") == "layer",
		"stale object snapshots do not leave a misleading hierarchy selection")
	editor.canvas.clear_selection()


func _count_layer_strokes(panel: AtlasLayerPanel, layer_id: String) -> int:
	var count: int = 0
	for key: String in panel._stroke_rows:
		if key.begins_with(layer_id + ":"):
			count += 1
	return count


## A hierarchy row can outlive an edited entrance. No button may act on the
## new link/placement/target using the old row, even if the IDs are unchanged.
func _test_stale_link_rows(editor: AtlasEditor, panel: AtlasLayerPanel) -> void:
	var link: AtlasMapLink = editor.campaign.links[0] if not editor.campaign.links.is_empty() else null
	_check(link != null and link.source_map_id == editor.canvas.map.id,
		"stale-link witness has an entrance on the active map")
	if link == null or link.source_map_id != editor.canvas.map.id:
		return
	var actions: Array[StringName] = []
	panel.link_action_requested.connect(func(_id: String, action: StringName) -> void:
		actions.append(action))
	panel.set_navigation_context(editor.campaign, editor.canvas.map)
	var row: TreeItem = _find(panel.hierarchy.get_root(), "link", link.id)
	_check(row != null, "entrance has an actionable hierarchy row")
	if row == null:
		return
	var before_camera: Vector2 = editor.canvas.camera_center
	var original_anchor: Vector2 = link.anchor
	link.anchor += Vector2(187.0, -53.0)
	panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_FOCUS, 1)
	_check(actions.is_empty() and editor.canvas.camera_center == before_camera,
		"old entrance row cannot focus a moved anchor")
	await process_frame
	row = _find(panel.hierarchy.get_root(), "link", link.id)
	_check(row != null and str(row.get_tooltip_text(0)).contains(str(link.anchor)),
		"rejected action refreshes the row to show the new anchor")
	panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_FOCUS, 1)
	_check(actions.size() == 1 and actions[0] == &"focus",
		"fresh entrance row can focus after explicit retry")
	link.anchor = original_anchor
	panel.set_navigation_context(editor.campaign, editor.canvas.map)

	row = _find(panel.hierarchy.get_root(), "link", link.id)
	var target: AtlasMapDocument = editor.campaign.get_map(link.target_map_id)
	_check(target != null, "link has a destination for stale-label test")
	if target != null:
		var original_name: String = target.display_name
		target.display_name += " (changed)"
		panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_EDIT, 1)
		_check(actions.size() == 1 and not editor.link_dialog.visible,
			"stale destination label cannot open an outdated edit dialog")
		await process_frame
		var refreshed: TreeItem = _find(panel.hierarchy.get_root(), "link", link.id)
		_check(refreshed != null and refreshed.get_text(0).contains("(changed)"),
			"destination label refreshes before another action")
		target.display_name = original_name
		panel.set_navigation_context(editor.campaign, editor.canvas.map)

	# A legacy footprint can change without changing the link resource itself.
	var original_placement_id: String = link.placement_id
	var placement: AtlasPlacement = editor.campaign.placement_by_id(link.placement_id)
	var temporary_placement: bool = placement == null
	if temporary_placement:
		placement = AtlasPlacement.new()
		placement.id = "hierarchy-stale-footprint"
		placement.parent_map_id = link.source_map_id
		placement.child_map_id = link.target_map_id
		link.placement_id = placement.id
		editor.campaign.placements.append(placement)
	panel.set_navigation_context(editor.campaign, editor.canvas.map)
	row = _find(panel.hierarchy.get_root(), "link", link.id)
	var original_origin: Vector2 = placement.origin
	placement.origin += Vector2(25, 75)
	panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_ENTER, 1)
	_check(actions.size() == 1 and editor.canvas.map.id == link.source_map_id,
		"old entrance row cannot enter after its footprint changes")
	await process_frame
	placement.origin = original_origin
	if temporary_placement:
		editor.campaign.placements.erase(placement)
		link.placement_id = original_placement_id
	panel.set_navigation_context(editor.campaign, editor.canvas.map)

	row = _find(panel.hierarchy.get_root(), "link", link.id)
	var original_focus: Vector2 = link.target_focus
	link.target_focus += Vector2(8.0, 21.0)
	panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_ENTER, 1)
	_check(actions.size() == 1 and editor.canvas.map.id == link.source_map_id,
		"old entrance row cannot enter after its arrival camera changes")
	await process_frame
	link.target_focus = original_focus
	panel.set_navigation_context(editor.campaign, editor.canvas.map)

	row = _find(panel.hierarchy.get_root(), "link", link.id)
	var link_index: int = editor.campaign.links.find(link)
	_check(link_index >= 0, "current link is still registered for stale-ID checks")
	if link_index >= 0:
		var replacement: AtlasMapLink = AtlasMapLink.from_dict(link.to_dict())
		editor.campaign.links[link_index] = replacement
		panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_EDIT, 1)
		_check(actions.size() == 1 and not editor.link_dialog.visible,
			"replacing an entrance with the same ID cannot activate its old row")
		await process_frame
		row = _find(panel.hierarchy.get_root(), "link", link.id)
		editor.campaign.links.remove_at(link_index)
		panel._on_hierarchy_button(row, 0, AtlasLayerPanel.LINK_FOCUS, 1)
		_check(actions.size() == 1 and editor.canvas.map.id == link.source_map_id,
			"deleted entrance cannot navigate from a leftover row")
		await process_frame
		editor.campaign.links.insert(link_index, link)
		panel.set_navigation_context(editor.campaign, editor.canvas.map)
