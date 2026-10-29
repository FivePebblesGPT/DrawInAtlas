class_name AtlasMapNavigator
extends RefCounted
## Per-workspace navigation owns cameras, floor/layer preferences and Back.
## A successful view change emits synchronously so the shell can refresh its
## edit target and panels before a subsequent gesture reaches the canvas.

signal view_changed
signal message(text: String)
signal candidates_requested(links: Array[AtlasMapLink])

const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 3.0
const ZOOM_FACTOR: float = 1.2

var views: AtlasViewSession = AtlasViewSession.new()
var zoom_gate: AtlasZoomGate = AtlasZoomGate.new()
var history: Array[Dictionary] = []
var automatic_navigation: bool = false:
	set(value):
		automatic_navigation = value
		zoom_gate.reset()
var now_msec: Callable = Time.get_ticks_msec
var active_entrance_id: String = "" # Traversal context, even if that link is later removed.
var _next_history_id: int = 0
var campaign: AtlasCampaign
var _canvas: AtlasCanvas


func _init(canvas: AtlasCanvas) -> void:
	_canvas = canvas


func reset(value: AtlasCampaign) -> void:
	campaign = value
	history.clear()
	active_entrance_id = ""
	_next_history_id = 0
	views.reset()
	zoom_gate.reset()


func remember_view() -> void:
	if _canvas.map != null and _canvas.floor != null:
		views.remember(AtlasViewState.new(_canvas.map.id, _canvas.floor.id,
			_canvas.camera_center, _canvas.camera_zoom, _canvas.active_layer_id))


func show_map(map: AtlasMapDocument, focus: Vector2 = Vector2.ZERO, zoom: float = 1.0,
		floor_id: String = "", layer_id: String = "", entrance_id: String = "") -> bool:
	if map == null or not _canvas.set_document(map, campaign, floor_id):
		message.emit("Map not found.")
		return false
	if not layer_id.is_empty():
		_canvas.active_layer_id = layer_id
	_canvas.camera_center = focus
	_canvas.camera_zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	active_entrance_id = entrance_id
	zoom_gate.reset()
	view_changed.emit()
	_canvas.queue_redraw()
	return true


func switch_floor(id: String) -> bool:
	if _canvas.map.floor_by_id(id) == null:
		message.emit("Floor not found; the current view was kept.")
		return false
	remember_view()
	var state: AtlasViewState = views.resolve(campaign, _canvas.map.id, id, _canvas.camera_center, _canvas.camera_zoom)
	if state == null:
		return false
	return show_map(_canvas.map, state.focus, state.zoom, state.floor_id, state.layer_id)


func open_map(id: String, floor_id: String = "") -> bool:
	remember_view()
	var state: AtlasViewState = views.resolve(campaign, id, floor_id)
	if state == null:
		message.emit("Map or floor unavailable; the current view and history were kept.")
		return false
	if _canvas.map.id != state.map_id or _canvas.floor.id != state.floor_id:
		push_history()
	return show_map(campaign.get_map(id), state.focus, state.zoom, state.floor_id, state.layer_id)


func push_history() -> void:
	if _canvas.map == null:
		return
	remember_view()
	_next_history_id += 1
	history.append({
		"history_id": _next_history_id, "entrance_id": active_entrance_id,
		"map_id": _canvas.map.id,
		"floor_id": _canvas.floor.id,
		"layer_id": _canvas.active_layer_id,
		"focus": _canvas.camera_center,
		"zoom": _canvas.camera_zoom
	})


func enter_link(link: AtlasMapLink) -> bool:
	zoom_gate.reset()
	if link == null or campaign.link_by_id(link.id) != link or link.source_map_id != _canvas.map.id or link.source_floor_id != _canvas.floor.id:
		return false
	var destination: AtlasMapDocument = campaign.get_map(link.target_map_id)
	if destination == null or destination.floor_by_id(link.target_floor_id) == null:
		message.emit("Broken map link: %s" % link.target_map_id)
		return false
	if not link.placement_id.is_empty():
		var placement: AtlasPlacement = campaign.placement_by_id(link.placement_id)
		if placement == null or placement.parent_map_id != link.source_map_id or placement.child_map_id != link.target_map_id:
			message.emit("Broken footprint; the current view and history were kept.")
			return false
	push_history()
	var destination_preferences: AtlasViewState = views.resolve(campaign, destination.id, link.target_floor_id, link.target_focus, link.target_zoom)
	show_map(destination, link.target_focus, link.target_zoom, link.target_floor_id, destination_preferences.layer_id, link.id)
	message.emit("Entered %s. Use Back%s." % [destination.display_name,
		" or 3 extra outward wheel steps" if automatic_navigation else ""])
	return true


func choose_links(links: Array[AtlasMapLink]) -> void:
	zoom_gate.reset()
	if links.size() == 1:
		enter_link(links[0])
	elif links.size() > 1:
		candidates_requested.emit(links)
		message.emit("Choose an entrance; overlapping links are never entered automatically.")


func back() -> void:
	while not history.is_empty():
		var snapshot: Dictionary = history.pop_back()
		var map: AtlasMapDocument = campaign.get_map(str(snapshot["map_id"]))
		var floor_id: String = str(snapshot.get("floor_id", map.default_floor_id if map != null else ""))
		if map != null and map.floor_by_id(floor_id) != null:
			remember_view()
			show_map(map, snapshot["focus"], float(snapshot["zoom"]), floor_id,
				str(snapshot.get("layer_id", "")), str(snapshot.get("entrance_id", "")))
			message.emit("Returned to %s." % map.display_name)
			return
	message.emit("No previous map.")


func reconcile_floors() -> void:
	views.prune(campaign)
	var current: AtlasFloor = _canvas.map.floor_by_id(_canvas.floor.id)
	if current == null:
		var fallback: AtlasViewState = views.resolve(campaign, _canvas.map.id, "", _canvas.camera_center, _canvas.camera_zoom)
		if fallback != null:
			show_map(_canvas.map, fallback.focus, fallback.zoom, fallback.floor_id, fallback.layer_id)
	elif current != _canvas.floor:
		_canvas.set_document(_canvas.map, campaign, current.id)


## Ordinary zoom never changes documents. Only further blocked steps reach the
## opt-in gate, whose candidate must remain unambiguous beneath the pointer.
func wheel_step(direction: int, local_position: Vector2) -> void:
	if _apply_geometric_wheel_step(direction, local_position):
		return
	if not automatic_navigation:
		zoom_gate.reset()
		message.emit("Zoom limit. Use Maps or double-click a marker to open another board.")
		return
	_consume_boundary_step(direction, local_position)


func _apply_geometric_wheel_step(direction: int, local_position: Vector2) -> bool:
	var old_zoom: float = _canvas.camera_zoom
	var new_zoom: float = clampf(old_zoom * (ZOOM_FACTOR if direction > 0 else 1.0 / ZOOM_FACTOR), MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return false
	var point_before: Vector2 = _canvas.local_to_document(local_position)
	_canvas.camera_zoom = new_zoom
	_canvas.camera_center = point_before - (local_position - _canvas.size * 0.5) / new_zoom
	zoom_gate.reset()
	_canvas.queue_redraw()
	return true


func _consume_boundary_step(direction: int, local_position: Vector2) -> void:
	var candidate: String = ""
	var target_link: AtlasMapLink
	if direction > 0:
		var possible: Array[AtlasMapLink] = campaign.find_links_at(_canvas.map.id, _canvas.local_to_document(local_position), _canvas.floor.id)
		if possible.size() == 1:
			target_link = possible[0]
			candidate = target_link.id
		elif possible.size() > 1:
			choose_links(possible)
			return
	elif not history.is_empty():
		candidate = _return_candidate_id(history[-1])
	if candidate.is_empty():
		zoom_gate.reset()
		message.emit("Zoom limit reached; no map available in that direction.")
		return
	if zoom_gate.accept_blocked_step(direction, candidate, int(now_msec.call())):
		if direction > 0:
			enter_link(target_link)
		else:
			back()
	else:
		message.emit("Semantic zoom buffer %d/3 — %s" % [zoom_gate.count, "enter" if direction > 0 else "return"])


func _return_candidate_id(snapshot: Dictionary) -> String:
	# Public history entries created before history IDs use their map ID instead.
	return "return:" + str(snapshot.get("history_id", snapshot["map_id"]))


func pointer_moved(local_position: Vector2) -> void:
	if zoom_gate.count == 0 or zoom_gate.direction < 0:
		return
	var links: Array[AtlasMapLink] = campaign.find_links_at(_canvas.map.id, _canvas.local_to_document(local_position), _canvas.floor.id)
	if links.size() != 1 or links[0].id != zoom_gate.candidate_id:
		zoom_gate.reset()


func magnify(factor: float, local_position: Vector2) -> void:
	zoom_gate.reset()
	if not is_finite(factor) or factor <= 0.0:
		return
	var point: Vector2 = _canvas.local_to_document(local_position)
	_canvas.camera_zoom = clampf(_canvas.camera_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_canvas.camera_center = point - (local_position - _canvas.size * 0.5) / _canvas.camera_zoom
	_canvas.queue_redraw()
