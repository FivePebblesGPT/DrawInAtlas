extends SceneTree
## T-012: local detail is authored and selected as layers, not child battlemaps.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var board_grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
	_check(editor.create_board("Shared detail witness", board_grid), "create one independent shared board")
	var canvas: AtlasCanvas = editor.canvas
	var board: AtlasMapDocument = canvas.map
	var floor: AtlasFloor = canvas.floor
	var overview: AtlasInkLayer = floor.ink_layer()
	var map_count: int = editor.campaign.maps.size()
	var link_count: int = editor.campaign.links.size()
	var placement_count: int = editor.campaign.placements.size()
	var center: Vector2 = board.grid.cell_to_document(Vector2i(2, -1))
	var faraway: Vector2 = board.grid.cell_to_document(Vector2i(-19, 13))
	var overview_count: int = overview.strokes.size()
	_check(editor.automatic_artwork_lod, "fresh editor defaults to automatic artwork presentation")

	# Author D1 even in an unpainted world hex; no child document or footprint.
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor.layer_panel.view_detail_spinner.value = 1
	_check(canvas.presented_detail_level == 1 and not editor.automatic_artwork_lod,
		"manual inspection can enter an empty local level without map navigation")
	editor.layer_panel._add_ink()
	var street_id: String = canvas.active_layer_id
	var streets: AtlasInkLayer = floor.layer_by_id(street_id) as AtlasInkLayer
	_check(streets != null and streets.detail_level == 1,
		"new ink is owned by D1 on the active board and selected for editing")
	if streets != null:
		editor.layer_panel._rename("Streets")
		editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([
			center + Vector2(-35, -5), center + Vector2(35, 5)]), Color.ORANGE, 3.0), false)
		streets = floor.layer_by_id(street_id) as AtlasInkLayer
		_check(streets != null and streets.strokes.size() == 1, "D1 accepts continuous authored ink")

	# Another detail level can independently describe the same place, including
	# drawing far from any registered map or previously painted world cell.
	editor.layer_panel.view_detail_spinner.value = 2
	editor.layer_panel._add_ink()
	var room_id: String = canvas.active_layer_id
	var rooms: AtlasInkLayer = floor.layer_by_id(room_id) as AtlasInkLayer
	_check(rooms != null and rooms.detail_level == 2 and room_id != street_id,
		"D2 is an independent layer, not nested in D1")
	if rooms != null:
		editor.layer_panel._rename("Rooms")
		editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([
			center + Vector2(-8, -7), center + Vector2(8, 7)]), Color.CYAN, 2.0), false)
		editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([
			faraway, faraway + Vector2(4, 6)]), Color.CYAN, 2.0), false)
		rooms = floor.layer_by_id(room_id) as AtlasInkLayer
		_check(rooms != null and rooms.strokes.size() == 2, "D2 can author near and distant content on one canvas")
	streets = floor.layer_by_id(street_id) as AtlasInkLayer
	_check(floor.ink_layer().strokes.size() == overview_count and streets != null and streets.strokes.size() == 1,
		"D2 edits do not rewrite D0 or D1")
	_check(editor.campaign.maps.size() == map_count and editor.campaign.links.size() == link_count
		and editor.campaign.placements.size() == placement_count,
		"local detail adds no documents, map links or battlemap placements")

	# Presenting another group must not secretly change where the pen edits.
	editor.layer_panel.view_detail_spinner.value = 0
	_check(canvas.active_layer_id == room_id and not canvas.editing_target_is_presented(),
		"manual presentation leaves the explicit D2 editing target hidden")
	var room_count: int = rooms.strokes.size() if rooms != null else 0
	editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([
		center, center + Vector2(2, 2)]), Color.WHITE, 2.0), false)
	_check(rooms != null and rooms.strokes.size() == room_count,
		"hidden D2 cannot be edited accidentally")
	editor.select_layer(street_id)
	_check(canvas.active_layer_id == street_id and canvas.presented_detail_level == 1,
		"explicit layer selection reveals D1 without entering a different document")
	editor.select_layer(room_id)
	_check(canvas.active_layer_id == room_id and canvas.presented_detail_level == 2,
		"explicit layer selection reveals D2 on the same board")
	_check(canvas.map == board and canvas.floor == floor,
		"authoring and changing levels preserves board and floor identity")

	# Automatic LOD may display a different group but never follows a child
	# document or changes the selected authoring destination.
	canvas.camera_center = center
	canvas.camera_zoom = 11.0
	editor.layer_panel.auto_detail_checkbox.button_pressed = true
	editor._rebuild_lod()
	await process_frame
	_check(editor.automatic_artwork_lod and canvas.map == board and canvas.active_layer_id == room_id
		and editor.campaign.maps.size() == map_count,
		"automatic detail presentation preserves board identity and editing target")
	editor.select_layer(room_id)

	# Presentation geometry and grid measurement are not child-map transforms.
	var detail_point: Vector2 = rooms.strokes[0].points[0] if rooms != null and not rooms.strokes.is_empty() else Vector2.ZERO
	var modified: AtlasGrid = board.grid.copy()
	modified.origin = Vector2(11, -19)
	modified.rotation = deg_to_rad(31.0)
	modified.distance_per_cell = 5.0
	modified.distance_unit = "km"
	editor.apply_grid(modified)
	_check(board.grid.same_geometry(modified) and board.grid.distance_unit == "km",
		"update the board overlay and native measurement")
	_check(rooms != null and not rooms.strokes.is_empty() and rooms.strokes[0].points[0] == detail_point,
		"grid and native distance changes never relocate local detail")

	# Undo/redo preserve layer ownership. Native save records all authored groups.
	_check(editor.edits.undo(), "undo board grid change")
	_check(editor.edits.redo(), "redo board grid change")
	var path: String = "user://t012-local-detail-%d.scn" % Time.get_ticks_usec()
	_check(AtlasCampaignStore.save_campaign(editor.campaign, path) == OK,
		"save local detail using normal native campaign format")
	var restored: AtlasCampaign = AtlasCampaignStore.load_campaign(path)
	_check(restored != null, "native campaign containing local detail loads")
	if restored != null:
		var restored_board: AtlasMapDocument = restored.get_map(board.id)
		var saved_floor: AtlasFloor = restored_board.floor_by_id(floor.id) if restored_board != null else null
		var saved_d1: AtlasInkLayer = saved_floor.layer_by_id(street_id) as AtlasInkLayer if saved_floor != null else null
		var saved_d2: AtlasInkLayer = saved_floor.layer_by_id(room_id) as AtlasInkLayer if saved_floor != null else null
		_check(saved_d1 != null and saved_d1.detail_level == 1 and saved_d1.strokes.size() == 1,
			"native save retains separately authored D1")
		_check(saved_d2 != null and saved_d2.detail_level == 2 and saved_d2.strokes.size() == 2,
			"native save retains D2 and distant board coordinates")
		_check(restored.maps.size() == map_count and restored.links.size() == link_count
			and restored.placements.size() == placement_count,
			"save creates no implicit detail map or footprint")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.remove_child(scene)
	scene.free()
	print("ATLAS_LOCAL_DETAIL_WORKFLOW_%s checks=%d failures=%d" % [
		"PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)
