extends SceneTree
## Exercise authored forms, native GUI dispatch, history, navigation and saves.

var checks: int = 0
var failures: int = 0
var editor: AtlasEditor
var canvas: AtlasCanvas
var dialog: AtlasLinkDialog
var _scene: Node
var _upper_id: String
var _entrance_id: String
var _slot: String = "user://linked-maps-ui/campaign.scn"


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LINKED MAPS UI FAILED: " + label)


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	_scene = load("res://main.tscn").instantiate()
	editor = _scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	editor.save_path = _slot
	editor.campaign = AtlasCampaign.sample()
	var roof: AtlasFloor = AtlasFloor.new()
	roof.id = "roof"
	editor.campaign.get_map("greyhaven").floors.append(roof)
	root.add_child(_scene)
	for frame: int in range(5):
		await process_frame
	canvas = editor.canvas
	dialog = editor.link_dialog
	for phase: String in ["_forms_and_history", "_retired_creation", "_navigation"]:
		_check(await call(phase) == true, phase + " completes")
	root.remove_child(_scene)
	_scene.free()
	for suffix: String in [".scn", ".bak.scn", ".pending.scn", ".bak.pending.scn"]:
		DirAccess.remove_absolute(_slot.trim_suffix(".scn") + suffix)
	DirAccess.remove_absolute(_slot.get_base_dir())
	print("ATLAS_LINKED_MAPS_UI_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _forms_and_history() -> bool:
	_check(dialog == editor.get_node("LinkDialog") and dialog.origin_x == dialog.get_node("Scroll/Form/PositionRow/OriginX"),
		"linked-map controls belong to the authored reusable form")
	_check(editor.create_floor("Balcony"), "create source floor through ordinary history")
	_upper_id = canvas.floor.id
	editor.edits.mark_saved()
	var before: Dictionary = editor.campaign.to_dict()
	var target_before: Dictionary = editor.campaign.get_map("greyhaven").to_dict()
	editor.inspector.get_node("Scroll/Margin/Sections/ReferenceSection/ManageLinks").pressed.emit()
	_check(dialog.visible and dialog.source_label.text.contains("Balcony"), "native Linked maps button opens the active source floor")
	_target("greyhaven", "roof")
	dialog.mode_picker.select(2)
	dialog.mode_picker.item_selected.emit(2)
	dialog.origin_x.value = -30.0
	dialog.origin_y.value = 40.0
	dialog.radius.value = 8.0
	dialog.arrival_x.value = 123.5
	dialog.arrival_y.value = -77.25
	dialog.arrival_zoom.value = 2.5
	dialog.center_arrival.button_pressed = false
	if DisplayServer.get_name() != "headless":
		for frame: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation")
		_check(dialog.get_texture().get_image().save_png("user://validation/linked-map-editor.png") == OK, "capture authored native link form")
	dialog.confirmed.emit()
	_check(not dialog.visible and editor.edits.get_undo_command() is AtlasLinkEdit, "confirmed form submits one reversible entrance command")
	_entrance_id = canvas.selected_link_id
	var link: AtlasMapLink = editor.campaign.link_by_id(_entrance_id)
	_check(link != null and link.source_floor_id == _upper_id and link.target_floor_id == "roof", "source and target floors are explicit")
	if link == null:
		return false
	_check(link.target_focus == Vector2(123.5, -77.25) and link.target_zoom == 2.5, "arrival camera is stored in destination units")
	_check(editor.campaign.get_map("greyhaven").to_dict() == target_before, "linking does not change child artwork, grid or units")
	editor._on_undo()
	_check(editor.campaign.to_dict() == before and not editor.edits.is_dirty(), "undo returns to the exact saved graph")
	editor._on_redo()
	_check(editor.campaign.link_by_id(_entrance_id) != null, "redo preserves entrance identity")
	editor._choose_tool(AtlasCanvas.Tool.SELECT)
	var position: Vector2 = canvas.document_to_local(Vector2(-30, 40))
	_button(position, true)
	_motion(position + Vector2(25, -10) * canvas.camera_zoom)
	_button(position + Vector2(25, -10) * canvas.camera_zoom, false)
	_check(editor.campaign.link_by_id(_entrance_id).anchor == Vector2(-5, 30), "native Select drag moves one entrance in board units")
	editor._on_undo()
	_check(editor.campaign.link_by_id(_entrance_id).anchor == Vector2(-30, 40), "drag movement is undoable")
	# Marker-only links cannot be converted into new footprints via the form.
	editor.linked_maps.open()
	dialog.mode_picker.select(0)
	_check(dialog.draft().is_empty(), "marker cannot draft a new spatial footprint")
	var forbidden: AtlasPlacement = AtlasPlacement.new()
	forbidden.parent_map_id = canvas.map.id
	forbidden.child_map_id = "greyhaven"
	_check(not editor.linked_maps.submit(AtlasMapLink.from_dict(link.to_dict()), forbidden),
		"linked-map command facade refuses a new footprint")
	dialog.hide()
	# Simulate a previously saved placement to retain coverage for legacy editing.
	var legacy_link: AtlasMapLink = AtlasMapLink.from_dict(link.to_dict())
	var legacy_placement: AtlasPlacement = AtlasPlacement.new()
	legacy_placement.id = "legacy-fixture"
	legacy_placement.parent_map_id = canvas.map.id
	legacy_placement.child_map_id = "greyhaven"
	legacy_placement.origin = Vector2(-30, 40)
	legacy_link.placement_id = legacy_placement.id
	_check(editor.edits.execute(AtlasLinkEdit.new(canvas.map.id, link, legacy_link, null, legacy_placement)),
		"legacy placement fixture loads through existing edit command")
	editor.linked_maps.open()
	_check(not dialog.mode_picker.disabled, "existing legacy footprint can still be edited")
	dialog.columns.value = 20
	dialog.rows.value = 15
	dialog.parent_pitch.value = 3.0
	dialog.child_pitch.value = 64.0
	dialog.angle.value = 37.0
	dialog.confirmed.emit()
	link = editor.campaign.link_by_id(_entrance_id)
	var footprint: AtlasPlacement = editor.campaign.placement_by_id(link.placement_id)
	_check(footprint != null and footprint.columns == 20 and footprint.rows == 15
		and is_equal_approx(footprint.rotation, deg_to_rad(37.0)), "legacy footprint geometry remains editable")
	_check(editor.campaign.get_map("greyhaven").to_dict() == target_before,
		"legacy calibration never resamples independent art")
	var precise: AtlasMapLink = AtlasMapLink.from_dict(link.to_dict())
	precise.target_zoom = 1.2345678901234567
	precise.target_focus = Vector2(-4.123456, 12.34567)
	var calibrated: AtlasPlacement = AtlasPlacement.from_dict(footprint.to_dict())
	calibrated.parent_units_per_cell = 3.1234567890123456
	calibrated.rotation = 0.12345678901234567
	calibrated.origin = Vector2(-30.12345, 40.98765)
	_check(editor.linked_maps.submit(precise, calibrated), "precise native calibration setup")
	var precise_link: Dictionary = editor.campaign.link_by_id(_entrance_id).to_dict()
	var precise_placement: Dictionary = editor.campaign.placement_by_id(footprint.id).to_dict()
	editor.linked_maps.open()
	dialog.rows.value = 16
	dialog.confirmed.emit()
	precise_placement.rows = 16
	_check(editor.campaign.link_by_id(_entrance_id).to_dict() == precise_link
		and editor.campaign.placement_by_id(footprint.id).to_dict() == precise_placement,
		"Apply preserves untouched native precision despite display rounding")
	editor.linked_maps.open()
	var current: AtlasMapLink = editor.campaign.link_by_id(_entrance_id)
	var history_before: AtlasEditCommand = editor.edits.get_undo_command()
	current.hit_radius += 1.0
	dialog.arrival_x.value += 10
	dialog.confirmed.emit()
	_check(dialog.visible and not dialog.error_label.text.is_empty() and current.target_focus == Vector2(-4.123456, 12.34567)
		and editor.edits.get_undo_command() == history_before, "stale open form cannot overwrite externally changed entrance data")
	current.hit_radius -= 1.0
	dialog.hide()
	var wrong_floor: AtlasMapLink = AtlasMapLink.from_dict(current.to_dict())
	wrong_floor.source_floor_id = "ground"
	_check(not editor.linked_maps.submit(wrong_floor, calibrated), "active child/source-floor context cannot modify another floor's entrance")
	editor.linked_maps.open()
	dialog.remove_button.pressed.emit()
	_check(editor.campaign.link_by_id(_entrance_id) == null and editor.campaign.get_map("greyhaven") != null, "Unlink keeps the independently editable destination")
	editor._on_undo()
	_check(editor.campaign.link_by_id(_entrance_id).placement_id == footprint.id, "undo unlink restores footprint identity")
	return true


func _retired_creation() -> bool:
	var map_count: int = editor.campaign.maps.size()
	var placement_count: int = editor.campaign.placements.size()
	var link_count: int = editor.campaign.links.size()
	_check(not AtlasCanvas.Tool.keys().has("BATTLEMAP") and editor.tool_palette.button_for(999) == null,
		"retired battlemap tool is not offered in the palette or enum")
	_check(not canvas.has_signal("battlemap_requested") and not editor.has_method("_on_create_battlemap")
		and not editor.linked_maps.has_method("create_drag"),
		"gesture and facade creation routes were removed")
	editor.linked_maps.open()
	_check(dialog.target_picker.item_count == map_count and dialog.mode_picker.disabled,
		"new entrances choose only existing documents and disable footprint modes")
	_check(dialog.get_node_or_null("Scroll/Form/NewDocument") == null
		and editor.inspector.get_node_or_null("Scroll/Margin/Sections/PlacementSection") == null,
		"new child document and placement spinner are absent")
	_check(dialog.mode_picker.selected == AtlasLinkDialog.LinkMode.MARKER,
		"new links default to marker-only navigation")
	dialog.hide()
	var old_map: String = canvas.map.id
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	var start: Vector2 = canvas.document_to_local(Vector2(-20, -10))
	var finish: Vector2 = canvas.document_to_local(Vector2(30, 10))
	var original_count: int = canvas.floor.strokes.size()
	_button(start, true)
	_motion(finish)
	_button(finish, false)
	_check(canvas.floor.strokes.size() == original_count + 1,
		"pointer drag continues drawing on the same authored board")
	_check(canvas.map.id == old_map and editor.campaign.maps.size() == map_count
		and editor.campaign.placements.size() == placement_count and editor.campaign.links.size() == link_count,
		"ordinary drawing never creates nested maps or footprints")
	editor._on_undo()
	_check(canvas.floor.strokes.size() == original_count, "ordinary drawing remains undoable")
	return true


func _navigation() -> bool:
	var anchor: Vector2 = Vector2(-1000, -1000)
	var first: String = _marker(anchor, "ground")
	var second: String = _marker(anchor, "roof")
	editor.edits.mark_saved()
	var canonical: Dictionary = editor.campaign.to_dict()
	canvas.camera_center = anchor
	canvas.camera_zoom = AtlasEditor.MAX_ZOOM
	editor.automatic_navigation = true
	editor._on_tool_changed(AtlasCanvas.Tool.SELECT)
	_wheel(1, 20.0)
	_check(editor.link_chooser.visible and editor.zoom_gate.count == 0 and canvas.map.id == "world",
		"ambiguous automatic zoom opens a chooser without accumulating toward an arbitrary entrance")
	editor.link_chooser.id_pressed.emit(1)
	_check(canvas.map.id == "greyhaven" and canvas.floor.id == "roof"
		and editor.navigator.active_entrance_id == second, "explicit overlap choice uses that entrance's target floor")
	_check(not editor.link_chooser.visible, "successful navigation closes stale chooser")
	var history_size: int = editor.history.size()
	editor.link_chooser.id_pressed.emit(0)
	_check(editor.history.size() == history_size and canvas.floor.id == "roof", "a stale chooser cannot navigate from another source")
	canvas.camera_zoom = AtlasEditor.MIN_ZOOM
	_wheel(-1)
	_wheel(-1)
	_check(canvas.map.id == "greyhaven", "two extra outward wheel events do not navigate")
	_wheel(-1)
	_check(canvas.map.id == "world" and canvas.camera_center == anchor and canvas.camera_zoom == AtlasEditor.MAX_ZOOM,
		"third outward step restores exact source map, floor and camera")
	_check(editor.campaign.to_dict() == canonical and not editor.edits.is_dirty(), "chooser, history and viewer preferences do not dirty campaign data")
	_check(editor.linked_maps.remove(second), "remove overlapping entrance independently")
	editor._on_tool_changed(AtlasCanvas.Tool.SELECT)
	for event_index: int in range(3):
		_wheel(1, 0.25)
	_check(editor.zoom_gate.count == 0, "fractional wheel input is normalized before boundary counting")
	_wheel(1, 0.25)
	_check(editor.zoom_gate.count == 1, "four quarter detents count as one logical step")
	_wheel(-1, 0.25)
	_check(editor.zoom_gate.count == 0, "even a partial reverse detent interrupts the previous boundary gesture")
	_wheel(1, 0.25)
	_wheel(1, 0.75)
	_check(editor.zoom_gate.count == 1, "reversing back starts a fresh normalized boundary step")
	var clock: Array[int] = [editor.zoom_gate.last_step_ms + 1000]
	editor.navigator.now_msec = func() -> int: return clock[0]
	_wheel(1, 20.0)
	editor.navigator.now_msec = Time.get_ticks_msec
	_check(editor.zoom_gate.count == 1 and canvas.map.id == "world", "timeout resets the gate and a burst still counts at most once")
	_key(KEY_ESCAPE)
	_check(editor.zoom_gate.count == 0, "Escape cancels pending semantic navigation")
	var magnify: InputEventMagnifyGesture = InputEventMagnifyGesture.new()
	magnify.position = canvas.size * 0.5 + canvas.global_position
	magnify.factor = 2.0
	root.push_input(magnify, true)
	_check(editor.zoom_gate.count == 0 and canvas.map.id == "world", "pinch clamping never contributes semantic boundary steps")
	for event_index: int in range(2):
		var pan: InputEventPanGesture = InputEventPanGesture.new()
		pan.position = canvas.size * 0.5 + canvas.global_position
		pan.delta = Vector2(0, -8)
		root.push_input(pan, true)
	_check(editor.zoom_gate.count == 2 and canvas.map.id == "world", "trackpad bursts need separate dispatches")
	editor.automatic_navigation = false
	_check(editor.zoom_gate.count == 0, "disabling automatic navigation immediately cancels pending steps")
	editor.automatic_navigation = true
	editor._on_tool_changed(AtlasCanvas.Tool.PEN)
	_check(editor.zoom_gate.count == 0, "tool changes cancel a pending boundary gesture")
	editor._on_tool_changed(AtlasCanvas.Tool.SELECT)
	_wheel(1, 20)
	_wheel(1, 20)
	_wheel(1, 20)
	_check(canvas.map.id == "greyhaven" and editor.navigator.active_entrance_id == first, "three extra single-candidate dispatches enter exactly once")
	return true


func _marker(anchor: Vector2, floor_id: String) -> String:
	canvas.selected_link_id = ""
	editor.linked_maps.open()
	_target("greyhaven", floor_id)
	dialog.mode_picker.select(2)
	dialog.origin_x.value = anchor.x
	dialog.origin_y.value = anchor.y
	dialog.radius.value = 10
	dialog.center_arrival.button_pressed = false
	dialog.confirmed.emit()
	return canvas.selected_link_id


func _target(id: String, floor_id: String) -> void:
	var ids: Array = editor.campaign.maps.keys()
	ids.sort()
	var index: int = ids.find(id)
	dialog.target_picker.select(index)
	dialog.target_picker.item_selected.emit(index)
	var map: AtlasMapDocument = editor.campaign.get_map(id)
	for floor_index: int in range(map.floors.size()):
		if map.floors[floor_index].id == floor_id:
			dialog.target_floor_picker.select(floor_index)


func _button(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _motion(position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _wheel(direction: int, factor: float = 1.0) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = canvas.global_position + canvas.size * 0.5
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_WHEEL_UP if direction > 0 else MOUSE_BUTTON_WHEEL_DOWN
	event.factor = factor
	event.pressed = true
	root.push_input(event, true)


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)
