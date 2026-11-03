class_name DrawingDockLayout
extends RefCounted
## UI-independent docking state shared by the Drawing workspace and future floating hosts.
## Mutations stage a deep copy and commit only when all ownership invariants hold.

const FORMAT_VERSION: int = 1
const DOCK: String = "dock"
const FLOATING: String = "floating"

var _panels: Dictionary = {} # Panel id -> {visible: bool}
var _factories: Dictionary = {} # Runtime-only view factories, deliberately not serialized.
var _containers: Array[Dictionary] = []


func register_panel(panel_id: String, factory: Callable = Callable()) -> bool:
	if panel_id.is_empty() or _panels.has(panel_id):
		return false
	_panels[panel_id] = {"visible": true}
	if factory.is_valid():
		_factories[panel_id] = factory
	return true


func view_factory(panel_id: String) -> Callable:
	return _factories.get(panel_id, Callable()) as Callable


func create_container(container_id: String, kind: String = DOCK) -> bool:
	if container_id.is_empty() or not [DOCK, FLOATING].has(kind) or _container_index(_containers, container_id) >= 0:
		return false
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	candidate.append({"id": container_id, "kind": kind, "minimized": false,
		"flyout_group": "", "groups": []})
	return _commit(candidate)


## A failed float transaction must not leave an orphaned empty container.
func remove_empty_container(container_id: String) -> bool:
	var index: int = _container_index(_containers, container_id)
	if index < 0 or _containers[index]["kind"] != FLOATING or not (_containers[index]["groups"] as Array).is_empty():
		return false
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	candidate.remove_at(index)
	return _commit(candidate)


func attach_panel(panel_id: String, container_id: String, group_id: String, group_index: int = -1) -> bool:
	if not _panels.has(panel_id) or not owner_of(panel_id).is_empty() or group_id.is_empty() or _group_exists(_containers, group_id):
		return false
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var container_idx: int = _container_index(candidate, container_id)
	if container_idx < 0:
		return false
	var groups: Array = candidate[container_idx]["groups"]
	if group_index < -1 or group_index > groups.size():
		return false
	groups.insert(groups.size() if group_index < 0 else group_index,
		{"id": group_id, "panels": [panel_id], "active": panel_id, "collapsed": false})
	return _commit(candidate)


func select_panel(panel_id: String) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var position: Dictionary = _find_panel(candidate, panel_id)
	if position.is_empty() or not bool(_panels[panel_id]["visible"]):
		return false
	var group: Dictionary = candidate[position["container"]]["groups"][position["group"]]
	group["active"] = panel_id
	return _commit(candidate)


func set_panel_visible(panel_id: String, visible: bool) -> bool:
	if not _panels.has(panel_id):
		return false
	_panels[panel_id]["visible"] = visible
	return true


func set_group_collapsed(group_id: String, collapsed: bool) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var position: Dictionary = _find_group(candidate, group_id)
	if position.is_empty():
		return false
	candidate[position["container"]]["groups"][position["group"]]["collapsed"] = collapsed
	return _commit(candidate)


func set_minimized(container_id: String, minimized: bool) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var index: int = _container_index(candidate, container_id)
	if index < 0 or candidate[index]["kind"] != DOCK:
		return false
	candidate[index]["minimized"] = minimized
	if not minimized:
		candidate[index]["flyout_group"] = ""
	return _commit(candidate)


func activate_from_rail(container_id: String, panel_id: String) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var position: Dictionary = _find_panel(candidate, panel_id)
	if position.is_empty() or candidate[position["container"]]["id"] != container_id or not bool(_panels[panel_id]["visible"]):
		return false
	var container: Dictionary = candidate[position["container"]]
	var group: Dictionary = container["groups"][position["group"]]
	if container["minimized"] and container["flyout_group"] == group["id"] and group["active"] == panel_id:
		container["flyout_group"] = ""
	else:
		group["active"] = panel_id
		container["flyout_group"] = group["id"] if container["minimized"] else ""
	return _commit(candidate)


func close_flyout(container_id: String) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var index: int = _container_index(candidate, container_id)
	if index < 0:
		return false
	candidate[index]["flyout_group"] = ""
	return _commit(candidate)


func move_panel(panel_id: String, target_group_id: String, index: int) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var source: Dictionary = _find_panel(candidate, panel_id)
	var target: Dictionary = _find_group(candidate, target_group_id)
	if source.is_empty() or target.is_empty():
		return false
	var origin_group: Dictionary = candidate[source["container"]]["groups"][source["group"]]
	var destination: Dictionary = candidate[target["container"]]["groups"][target["group"]]
	var members: Array = destination["panels"]
	if index < 0 or index > members.size():
		return false
	origin_group["panels"].erase(panel_id)
	if origin_group == destination and index > source["panel"]:
		index -= 1
	members.insert(index, panel_id)
	if origin_group["active"] == panel_id and origin_group != destination:
		origin_group["active"] = origin_group["panels"][0] if not origin_group["panels"].is_empty() else ""
	if origin_group["panels"].is_empty():
		_remove_group(candidate, String(origin_group["id"]))
	return _commit(candidate)


func split_panel(panel_id: String, new_group_id: String, target_container_id: String, group_index: int) -> bool:
	if new_group_id.is_empty() or _group_exists(_containers, new_group_id):
		return false
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var source: Dictionary = _find_panel(candidate, panel_id)
	var container_idx: int = _container_index(candidate, target_container_id)
	if source.is_empty() or container_idx < 0:
		return false
	var target_groups: Array = candidate[container_idx]["groups"]
	if group_index < 0 or group_index > target_groups.size():
		return false
	var source_group: Dictionary = candidate[source["container"]]["groups"][source["group"]]
	source_group["panels"].erase(panel_id)
	if source_group["active"] == panel_id:
		source_group["active"] = source_group["panels"][0] if not source_group["panels"].is_empty() else ""
	if source_group["panels"].is_empty():
		_remove_group(candidate, String(source_group["id"]))
		# Removing a group ahead of the target shifts the insertion index.
		if source["container"] == container_idx and source["group"] < group_index:
			group_index -= 1
	target_groups = candidate[container_idx]["groups"]
	target_groups.insert(group_index,
		{"id": new_group_id, "panels": [panel_id], "active": panel_id, "collapsed": false})
	return _commit(candidate)


func merge_groups(source_id: String, target_id: String, index: int) -> bool:
	if source_id == target_id:
		return false
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var source: Dictionary = _find_group(candidate, source_id)
	var target: Dictionary = _find_group(candidate, target_id)
	if source.is_empty() or target.is_empty():
		return false
	var origin: Dictionary = candidate[source["container"]]["groups"][source["group"]]
	var destination: Dictionary = candidate[target["container"]]["groups"][target["group"]]
	if index < 0 or index > destination["panels"].size():
		return false
	var offset: int = 0
	for panel_id: String in origin["panels"]:
		destination["panels"].insert(index + offset, panel_id)
		offset += 1
	_remove_group(candidate, source_id)
	return _commit(candidate)


func move_group(group_id: String, target_container_id: String, index: int) -> bool:
	var candidate: Array[Dictionary] = _containers.duplicate(true)
	var origin: Dictionary = _find_group(candidate, group_id)
	var destination_index: int = _container_index(candidate, target_container_id)
	if origin.is_empty() or destination_index < 0:
		return false
	var origin_groups: Array = candidate[origin["container"]]["groups"]
	var destination_groups: Array = candidate[destination_index]["groups"]
	if index < 0 or index > destination_groups.size():
		return false
	var group: Dictionary = origin_groups[origin["group"]]
	origin_groups.remove_at(origin["group"])
	if origin["container"] == destination_index and index > origin["group"]:
		index -= 1
	destination_groups.insert(index, group)
	if candidate[origin["container"]]["flyout_group"] == group_id:
		candidate[origin["container"]]["flyout_group"] = ""
	return _commit(candidate)


func owner_of(panel_id: String) -> String:
	var position: Dictionary = _find_panel(_containers, panel_id)
	return String(_containers[position["container"]]["id"]) if not position.is_empty() else ""


func group_of(panel_id: String) -> String:
	var position: Dictionary = _find_panel(_containers, panel_id)
	return String(_containers[position["container"]]["groups"][position["group"]]["id"]) if not position.is_empty() else ""


func container_info(container_id: String) -> Dictionary:
	var index: int = _container_index(_containers, container_id)
	return _containers[index].duplicate(true) if index >= 0 else {}


func group_info(group_id: String) -> Dictionary:
	var position: Dictionary = _find_group(_containers, group_id)
	return _containers[position["container"]]["groups"][position["group"]].duplicate(true) if not position.is_empty() else {}


func rail_icons(container_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var container: Dictionary = container_info(container_id)
	if container.is_empty():
		return output
	for group: Dictionary in container["groups"]:
		var first: bool = true
		for panel_id: String in group["panels"]:
			if not bool(_panels[panel_id]["visible"]):
				continue
			output.append({"panel": panel_id, "group": group["id"],
				"separator_before": not output.is_empty() and first})
			first = false
	return output


func snapshot() -> Dictionary:
	var panel_entries: Array[Dictionary] = []
	var sorted_ids: Array[String] = []
	for panel_id: String in _panels:
		sorted_ids.append(panel_id)
	sorted_ids.sort()
	for panel_id: String in sorted_ids:
		panel_entries.append({"id": panel_id, "visible": bool(_panels[panel_id]["visible"])})
	return {"version": FORMAT_VERSION, "panels": panel_entries,
		"containers": _containers.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if data.get("version") != FORMAT_VERSION or not data.get("panels") is Array or not data.get("containers") is Array:
		return false
	var panels: Dictionary = {}
	for item: Variant in data["panels"]:
		if not item is Dictionary or not item.get("id") is String or not item.get("visible") is bool:
			return false
		var panel_id: String = item["id"]
		if panels.has(panel_id) or not _panels.has(panel_id):
			return false
		panels[panel_id] = {"visible": item["visible"]}
	if panels.size() != _panels.size():
		return false
	var candidate: Array[Dictionary] = []
	for container: Variant in data["containers"]:
		if not container is Dictionary:
			return false
		candidate.append(container.duplicate(true))
	if not _valid(candidate, panels):
		return false
	_containers = candidate
	_panels = panels
	return true


func _container_index(containers: Array[Dictionary], container_id: String) -> int:
	for index: int in range(containers.size()):
		if containers[index].get("id") == container_id:
			return index
	return -1


func _find_group(containers: Array[Dictionary], group_id: String) -> Dictionary:
	for container_idx: int in range(containers.size()):
		for group_idx: int in range(containers[container_idx]["groups"].size()):
			if containers[container_idx]["groups"][group_idx]["id"] == group_id:
				return {"container": container_idx, "group": group_idx}
	return {}


func _group_exists(containers: Array[Dictionary], group_id: String) -> bool:
	return not _find_group(containers, group_id).is_empty()


func _find_panel(containers: Array[Dictionary], panel_id: String) -> Dictionary:
	for container_idx: int in range(containers.size()):
		for group_idx: int in range(containers[container_idx]["groups"].size()):
			var members: Array = containers[container_idx]["groups"][group_idx]["panels"]
			var panel_idx: int = members.find(panel_id)
			if panel_idx >= 0:
				return {"container": container_idx, "group": group_idx, "panel": panel_idx}
	return {}


func _remove_group(containers: Array[Dictionary], group_id: String) -> void:
	var position: Dictionary = _find_group(containers, group_id)
	if position.is_empty():
		return
	var container: Dictionary = containers[position["container"]]
	container["groups"].remove_at(position["group"])
	if container["flyout_group"] == group_id:
		container["flyout_group"] = ""


func _commit(candidate: Array[Dictionary]) -> bool:
	if not _valid(candidate, _panels):
		return false
	_containers = candidate
	return true


func _valid(containers: Array[Dictionary], panels: Dictionary) -> bool:
	var seen_containers: Dictionary = {}
	var seen_groups: Dictionary = {}
	var seen_panels: Dictionary = {}
	for container: Variant in containers:
		if not container is Dictionary or not container.get("id") is String or String(container["id"]).is_empty():
			return false
		if seen_containers.has(container["id"]):
			return false
		seen_containers[container["id"]] = true
		if not [DOCK, FLOATING].has(container.get("kind")) or not container.get("minimized") is bool or not container.get("flyout_group") is String or not container.get("groups") is Array:
			return false
		if container["kind"] == FLOATING and container["minimized"]:
			return false
		var local_groups: Dictionary = {}
		for group: Variant in container["groups"]:
			if not group is Dictionary or not group.get("id") is String or String(group["id"]).is_empty() or not group.get("panels") is Array or not group.get("collapsed") is bool:
				return false
			if seen_groups.has(group["id"]) or group["panels"].is_empty() or not group.get("active") is String:
				return false
			seen_groups[group["id"]] = true
			local_groups[group["id"]] = true
			if not group["panels"].has(group["active"]):
				return false
			for panel_id: Variant in group["panels"]:
				if not panel_id is String or not panels.has(panel_id) or seen_panels.has(panel_id):
					return false
				seen_panels[panel_id] = true
		if not String(container["flyout_group"]).is_empty() and (not container["minimized"] or not local_groups.has(container["flyout_group"])):
			return false
	return true
