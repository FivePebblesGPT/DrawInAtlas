class_name DrawingDockPersistence
extends RefCounted
## T-083: versioned workspace-only state, never Drawing document or Object Asset data.
## The dock model remains the sole owner of all panel/group membership.

const VERSION: int = 1
const MAX_BYTES: int = 262144
const MAX_HOSTS: int = 32
const MAX_GROUPS: int = 128
const MAX_PANELS: int = 128


static func capture(layout: DrawingDockLayout, hosts: Dictionary, dock_width: int,
		dock_scroll: int, client_size: Vector2) -> Dictionary:
	var frames: Array[Dictionary] = []
	# The child order, not the Dictionary iteration order, establishes host z-order.
	var ordered: Array[DrawingFloatingHost] = []
	for host: DrawingFloatingHost in hosts.values():
		ordered.append(host)
	ordered.sort_custom(func(a: DrawingFloatingHost, b: DrawingFloatingHost) -> bool:
		return a.get_index() < b.get_index())
	for host: DrawingFloatingHost in ordered:
		frames.append({"id": host.host_id, "visible": host.visible,
			"rect": [host.position.x, host.position.y, host.size.x, host.size.y],
			"client": [client_size.x, client_size.y]})
	return {"schema": VERSION, "layout": layout.snapshot(),
		"dock_width": dock_width, "dock_scroll": dock_scroll, "hosts": frames}


## Only registered panel IDs are restored. Unknown saved panels are discarded,
## and new registered panels are appended as their own dock groups.
## Structural corruption rejects the entire snapshot rather than partially
## moving panels; this keeps owner/active-tab uniqueness deterministic.
static func recover(raw: Variant, live: DrawingDockLayout, aliases: Dictionary = {}) -> Dictionary:
	if not raw is Dictionary or raw.get("schema") != VERSION:
		return {}
	var source: Variant = raw.get("layout")
	if not source is Dictionary or source.get("version") != DrawingDockLayout.FORMAT_VERSION or not source.get("containers") is Array or not source.get("panels") is Array:
		return {}
	var baseline: Dictionary = live.snapshot()
	var registered: Dictionary = {}
	for item: Dictionary in baseline["panels"]:
		registered[item["id"]] = item["visible"]
	if registered.size() > MAX_PANELS:
		return {}
	var visibility: Dictionary = {}
	var changed: bool = false
	for entry: Variant in source["panels"]:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("visible") is bool:
			return {}
		var id: String = _resolve_id(entry["id"], registered, aliases)
		if id.is_empty():
			changed = true
			continue
		if visibility.has(id):
			return {}
		visibility[id] = entry["visible"]
	var result_panels: Array[Dictionary] = []
	for panel_id: String in registered:
		if not visibility.has(panel_id):
			changed = true
		result_panels.append({"id": panel_id, "visible": visibility.get(panel_id, registered[panel_id])})
	result_panels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	var containers: Array[Dictionary] = []
	var occupied: Dictionary = {}
	var groups_seen: Dictionary = {}
	var container_seen: Dictionary = {}
	var group_count: int = 0
	var saved_containers: Array = source["containers"]
	if saved_containers.size() > MAX_HOSTS + 1:
		return {}
	for entry: Variant in saved_containers:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("kind") is String or not entry.get("groups") is Array or not entry.get("minimized") is bool or not entry.get("flyout_group") is String:
			return {}
		var cid: String = entry["id"]
		var kind: String = entry["kind"]
		if cid.is_empty() or cid.length() > 80 or container_seen.has(cid) or (cid == "right" and kind != DrawingDockLayout.DOCK) or (cid != "right" and kind != DrawingDockLayout.FLOATING):
			return {}
		container_seen[cid] = true
		var groups: Array[Dictionary] = []
		for group: Variant in entry["groups"]:
			group_count += 1
			if group_count > MAX_GROUPS or not group is Dictionary or not group.get("id") is String or not group.get("panels") is Array or not group.get("active") is String or not group.get("collapsed") is bool:
				return {}
			var gid: String = group["id"]
			if gid.is_empty() or gid.length() > 80 or groups_seen.has(gid):
				return {}
			groups_seen[gid] = true
			var members: Array[String] = []
			if group["panels"].size() > MAX_PANELS:
				return {}
			for item: Variant in group["panels"]:
				if not item is String:
					return {}
				var pid: String = _resolve_id(item, registered, aliases)
				if pid.is_empty():
					changed = true
					continue
				if occupied.has(pid):
					return {}
				occupied[pid] = true
				members.append(pid)
			if members.is_empty():
				changed = true
				continue
			var active: String = _resolve_id(group["active"], registered, aliases)
			if not members.has(active):
				active = members[0]
				changed = true
			groups.append({"id": gid, "panels": members, "active": active, "collapsed": group["collapsed"]})
		var flyout: String = entry["flyout_group"]
		if not bool(entry["minimized"]) or not groups.any(func(g: Dictionary) -> bool: return g["id"] == flyout):
			if not flyout.is_empty():
				changed = true
			flyout = ""
		if kind == DrawingDockLayout.FLOATING and groups.is_empty():
			changed = true
			continue
		containers.append({"id": cid, "kind": kind, "minimized": entry["minimized"] if kind == DrawingDockLayout.DOCK else false,
			"flyout_group": flyout if kind == DrawingDockLayout.DOCK else "", "groups": groups})
	if not container_seen.has("right"):
		return {}
	var dock: Dictionary = {}
	for entry: Dictionary in containers:
		if entry["id"] == "right":
			dock = entry
			break
	for pid: String in registered:
		if occupied.has(pid):
			continue
		changed = true
		var gid: String = pid
		var suffix: int = 0
		while groups_seen.has(gid):
			suffix += 1
			gid = "%s-restored-%d" % [pid, suffix]
		groups_seen[gid] = true
		dock["groups"].append({"id": gid, "panels": [pid], "active": pid, "collapsed": false})
	var normalized: Dictionary = {"version": DrawingDockLayout.FORMAT_VERSION,
		"panels": result_panels, "containers": containers}
	# Full validation is delegated to the existing single ownership model.
	var witness: DrawingDockLayout = DrawingDockLayout.new()
	for panel_id: String in registered:
		witness.register_panel(panel_id)
	if not witness.restore(normalized):
		return {}
	var hosts: Array[Dictionary] = []
	var host_ids: Dictionary = {}
	if not raw.get("hosts") is Array or raw["hosts"].size() > MAX_HOSTS:
		return {}
	for entry: Variant in raw["hosts"]:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("visible") is bool or not _safe_rect(entry.get("rect")) or not _safe_client(entry.get("client")):
			changed = true
			continue
		var cid: String = entry["id"]
		if host_ids.has(cid):
			changed = true
			continue
		host_ids[cid] = true
		if not containers.any(func(c: Dictionary) -> bool: return c["id"] == cid and c["kind"] == DrawingDockLayout.FLOATING):
			changed = true
			continue
		hosts.append({"id": cid, "visible": entry["visible"], "rect": entry["rect"], "client": entry["client"]})
	for entry: Dictionary in containers:
		if entry["kind"] == DrawingDockLayout.FLOATING and not host_ids.has(entry["id"]):
			# Unknown host geometry gets a safe, visible default.
			hosts.append({"id": entry["id"], "visible": true,
				"rect": [60.0, 65.0, 310.0, 350.0], "client": [1280.0, 760.0]})
			changed = true
	var width: int = 270
	var scroll: int = 0
	if raw.get("dock_width") is int or raw.get("dock_width") is float:
		width = clampi(int(raw["dock_width"]), 160, 800) if _finite_number(raw["dock_width"]) else 270
	else:
		changed = true
	if raw.get("dock_scroll") is int or raw.get("dock_scroll") is float:
		scroll = clampi(int(raw["dock_scroll"]), 0, 100000) if _finite_number(raw["dock_scroll"]) else 0
	else:
		changed = true
	return {"layout": normalized, "hosts": hosts, "dock_width": width, "dock_scroll": scroll,
		"recovered": changed}


static func restore_rect(entry: Dictionary, client: Vector2) -> Rect2:
	var saved: Array = entry["rect"]
	var reference: Array = entry["client"]
	var scale: Vector2 = Vector2(client.x / float(reference[0]), client.y / float(reference[1]))
	return Rect2(Vector2(float(saved[0]) * scale.x, float(saved[1]) * scale.y),
		Vector2(float(saved[2]) * scale.x, float(saved[3]) * scale.y))


static func read_file(path: String) -> Dictionary:
	# An interrupted replacement may leave the last committed settings at .bak.
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var source: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if source == null or source.get_length() > MAX_BYTES:
			continue
		var parser: JSON = JSON.new()
		if parser.parse(source.get_as_text()) == OK and parser.data is Dictionary:
			return parser.data
	return {}

## Write-and-rename with backup/rollback. Never touch Drawing document paths.
static func save_file(path: String, state: Dictionary) -> bool:
	var encoded: String = JSON.stringify(state)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return false
	var full: String = ProjectSettings.globalize_path(path)
	var parent: String = full.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent) != OK:
		return false
	var tmp: String = full + ".tmp"
	var backup: String = full + ".bak"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	var write_ok: bool = file.get_error() == OK
	file.close()
	if not write_ok:
		DirAccess.remove_absolute(tmp)
		return false
	var had_old: bool = FileAccess.file_exists(full)
	if had_old:
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(full, backup) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	if DirAccess.rename_absolute(tmp, full) != OK:
		if had_old:
			DirAccess.rename_absolute(backup, full)
		DirAccess.remove_absolute(tmp)
		return false
	DirAccess.remove_absolute(backup)
	return true


static func _resolve_id(id: String, registered: Dictionary, aliases: Dictionary) -> String:
	var resolved: String = String(aliases.get(id, id))
	return resolved if registered.has(resolved) else ""


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and not is_nan(float(value)) and not is_inf(float(value))


static func _safe_rect(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for number: Variant in value:
		if not _finite_number(number) or absf(float(number)) > 100000.0:
			return false
	return float(value[2]) > 0.0 and float(value[3]) > 0.0


static func _safe_client(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	return _finite_number(value[0]) and _finite_number(value[1]) and float(value[0]) > 0.0 and float(value[1]) > 0.0
