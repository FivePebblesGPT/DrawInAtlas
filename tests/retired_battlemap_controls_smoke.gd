extends SceneTree
## T-014: old battlemat creation paths are unavailable at every authored level.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RETIRED BATTLEMAP FAILED: " + name)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var canvas: AtlasCanvas = editor.canvas
	var maps_before: int = editor.campaign.maps.size()
	var links_before: int = editor.campaign.links.size()
	var placements_before: int = editor.campaign.placements.size()
	var board: AtlasMapDocument = canvas.map
	_check(not AtlasCanvas.Tool.keys().has("BATTLEMAP") and not canvas.has_signal("battlemap_requested"),
		"no drag-creation enum or signal survives")
	_check(not editor.has_method("_on_create_battlemap") and not editor.linked_maps.has_method("create_drag")
		and not editor.linked_maps.has_method("prepare_drag"), "editor and linked-map facades cannot start draft")
	_check(editor.inspector.find_child("PlacementSection", true, false) == null,
		"inspector has no separate placement rotation affordance")
	for category: Dictionary in AtlasToolPalette.CATEGORIES:
		for item: Dictionary in category["tools"]:
			_check(not String(item["name"]).to_lower().contains("battle")
				and not String(item["hint"]).to_lower().contains("linked local map"),
				"no palette category contains a renamed battlemat creator")

	# Use the existing D0, then add new D1 and D2 ink layers from the UI.
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	for level: int in [0, 1, 2]:
		editor.layer_panel.view_detail_spinner.value = level
		if level > 0:
			editor.layer_panel._add_ink()
		var layer: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
		_check(layer != null and layer.detail_level == level, "editing target belongs to D%d" % level)
		editor._choose_tool(AtlasCanvas.Tool.PEN)
		var before_strokes: int = layer.strokes.size() if layer != null else 0
		var down: InputEventMouseButton = InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = canvas.document_to_local(Vector2(-70 + level * 20, -15))
		canvas._gui_input(down)
		var move: InputEventMouseMotion = InputEventMouseMotion.new()
		move.position = canvas.document_to_local(Vector2(70 + level * 20, 15))
		canvas._gui_input(move)
		var up: InputEventMouseButton = InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.position = move.position
		canvas._gui_input(up)
		_check(layer != null and layer.strokes.size() == before_strokes + 1,
			"D%d pointer drag draws ordinary ink" % level)
		_check(canvas.map == board and editor.campaign.maps.size() == maps_before
			and editor.campaign.links.size() == links_before and editor.campaign.placements.size() == placements_before,
			"D%d gesture introduces no new map, link, or footprint" % level)
		if layer != null:
			editor._on_undo()
			_check(layer.strokes.size() == before_strokes, "D%d stroke undo is unchanged" % level)

	editor.linked_maps.open()
	var dialog: AtlasLinkDialog = editor.link_dialog
	_check(dialog.target_picker.item_count == maps_before and dialog.mode_picker.disabled
		and dialog.mode_picker.selected == AtlasLinkDialog.LinkMode.MARKER,
		"new links can only target existing maps using marker mode")
	_check(dialog.get_node_or_null("Scroll/Form/NewDocument") == null,
		"linked-map dialog cannot create another document")
	dialog.mode_picker.select(AtlasLinkDialog.LinkMode.SPATIAL)
	_check(dialog.draft().is_empty(), "forcing disabled spatial mode still produces no new placement")
	dialog.hide()
	var snapshot: Dictionary = editor.campaign.to_dict()
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = "forbidden"
	link.source_map_id = board.id
	link.source_floor_id = canvas.floor.id
	link.target_map_id = "greyhaven"
	link.target_floor_id = "ground"
	var footprint: AtlasPlacement = AtlasPlacement.new()
	footprint.parent_map_id = board.id
	footprint.child_map_id = "greyhaven"
	_check(not editor.linked_maps.submit(link, footprint)
		and editor.campaign.to_dict() == snapshot,
		"facade rejects forged new spatial placement without modifying campaign")
	var imported: AtlasMapDocument = AtlasMapDocument.new("forbidden-new", "Forbidden")
	_check(not editor.linked_maps.submit(link, null, imported)
		and editor.campaign.to_dict() == snapshot,
		"facade rejects forged nested-document creation")

	root.remove_child(scene)
	scene.free()
	print("ATLAS_RETIRED_BATTLEMAP_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
