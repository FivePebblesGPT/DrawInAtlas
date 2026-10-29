class_name AtlasLinkedMaps
extends RefCounted
## Parent-owned entrance/placement actions. The dialog owns draft controls; the
## command owns atomic validation/snapshots; the navigator owns view changes.

signal changed
signal message(text: String)

var _canvas: AtlasCanvas
var _history: AtlasEditHistory
var _navigator: AtlasMapNavigator
var dialog: AtlasLinkDialog


func _init(canvas: AtlasCanvas, history: AtlasEditHistory, navigator: AtlasMapNavigator, form: AtlasLinkDialog) -> void:
	_canvas = canvas
	_history = history
	_navigator = navigator
	dialog = form
	dialog.submitted.connect(submit)
	dialog.remove_requested.connect(remove)
	dialog.enter_requested.connect(enter)
	dialog.focus_requested.connect(focus)


func open() -> void:
	_canvas.cancel_edit()
	_navigator.zoom_gate.reset()
	dialog.open(_canvas.campaign, _canvas.map, _canvas.floor, _canvas.camera_center, _canvas.selected_link_id)


func refresh() -> void:
	if _canvas.campaign.link_by_id(_canvas.selected_link_id) == null:
		_canvas.selected_link_id = ""
	if dialog.visible:
		dialog.configure(_canvas.campaign, _canvas.map, _canvas.floor, _canvas.camera_center, dialog.selected_id)
	_canvas.queue_redraw()


func submit(link: AtlasMapLink, placement: AtlasPlacement, new_map: AtlasMapDocument = null) -> bool:
	if link == null or link.source_map_id != _canvas.map.id or link.source_floor_id != _canvas.floor.id:
		return false
	var before: AtlasMapLink = _canvas.campaign.link_by_id(link.id)
	var old: AtlasPlacement = _canvas.campaign.placement_by_id(before.placement_id) if before != null else null
	if dialog.visible and dialog.selected_id == link.id and not dialog.is_current(before, old):
		_rejected()
		return false
	var command := AtlasLinkEdit.new(_canvas.map.id, before, link, old, placement, new_map, _canvas.edit_scope)
	if not _history.execute(command):
		_rejected()
		return false
	_canvas.selected_link_id = link.id
	dialog.hide()
	changed.emit()
	message.emit("Entrance saved. Destination artwork, grid and native units are unchanged.")
	return true


func remove(id: String) -> bool:
	var link: AtlasMapLink = _canvas.campaign.link_by_id(id)
	if not _owns(link):
		return false
	var placement: AtlasPlacement = _canvas.campaign.placement_by_id(link.placement_id)
	if not _history.execute(AtlasLinkEdit.new(_canvas.map.id, link, null, placement, null, null, _canvas.edit_scope)):
		_rejected()
		return false
	_canvas.selected_link_id = ""
	dialog.hide()
	changed.emit()
	message.emit("Entrance removed; its independent destination document was kept.")
	return true


func enter(id: String) -> void:
	var link: AtlasMapLink = _canvas.campaign.link_by_id(id)
	if _owns(link) and _navigator.enter_link(link):
		dialog.hide()


func focus(id: String) -> void:
	var link: AtlasMapLink = _canvas.campaign.link_by_id(id)
	if not _owns(link):
		return
	var placement: AtlasPlacement = _canvas.campaign.placement_by_id(link.placement_id)
	_canvas.camera_center = placement.child_to_parent() * placement.child_bounds().get_center() if placement != null else link.anchor
	_canvas.selected_link_id = link.id
	_navigator.zoom_gate.reset()
	_canvas.queue_redraw()
	dialog.hide()


func create_drag(start: Vector2, finish: Vector2, radians: float) -> bool:
	dialog.prepare_new(_canvas.campaign, _canvas.map, _canvas.floor, start)
	if dialog.is_marker_mode():
		message.emit("Choose a spatial or symbolic footprint in Linked maps before dragging.")
		return false
	var drafts: Array[Resource] = dialog.draft("", start, finish, radians)
	if drafts.size() != 3:
		message.emit("Drag at least half a footprint cell; each dimension is quantized to one cell or more.")
		return false
	var link: AtlasMapLink = drafts[0] as AtlasMapLink
	var placement: AtlasPlacement = drafts[1] as AtlasPlacement
	var new_map: AtlasMapDocument = drafts[2] as AtlasMapDocument
	if not submit(link, placement, new_map):
		return false
	_navigator.enter_link(_canvas.campaign.link_by_id(link.id))
	# Success describes the graph submission, independently of the view transition.
	return true


func prepare_drag() -> void:
	dialog.prepare_new(_canvas.campaign, _canvas.map, _canvas.floor, _canvas.camera_center)
	_canvas.battle_pitch = dialog.get_parent_pitch()


func move(id: String, offset: Vector2) -> bool:
	var original: AtlasMapLink = _canvas.campaign.link_by_id(id)
	if not _owns(original) or not offset.is_finite():
		return false
	var link: AtlasMapLink = AtlasMapLink.from_dict(original.to_dict())
	link.anchor += offset
	var old: AtlasPlacement = _canvas.campaign.placement_by_id(link.placement_id)
	var placement: AtlasPlacement = AtlasPlacement.from_dict(old.to_dict()) if old != null else null
	if placement != null:
		placement.origin += offset
	return submit(link, placement)


func _owns(link: AtlasMapLink) -> bool:
	return link != null and link.source_map_id == _canvas.map.id and link.source_floor_id == _canvas.floor.id


func _rejected() -> void:
	var text: String = "Link unchanged or rejected: invalid/stale data, shared footprint, or outside selected-cell scope."
	dialog.show_error(text)
	message.emit(text)
