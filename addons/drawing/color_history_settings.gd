class_name DrawingColorHistorySettings
extends RefCounted
## Bounded application-only pigment state; independent of DrawingDocument history.
## Strict canonical RGBA8 strings preserve RGB under zero alpha.

const VERSION: int = 1
const MAX_BYTES: int = 512
const MAX_RECENTS: int = 6


static func _parse_rgba(value: Variant) -> Dictionary:
	if not value is String or value.length() != 9 or not value.begins_with("#"):
		return {}
	for index: int in range(1, value.length()):
		if "0123456789ABCDEF".find(value.substr(index, 1)) < 0:
			return {}
	return {"color": Color.html(value)}


static func decode(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.get("schema") != VERSION or not raw.get("editing_background") is bool:
		return {}
	var foreground: Dictionary = _parse_rgba(raw.get("foreground"))
	var background: Dictionary = _parse_rgba(raw.get("background"))
	if foreground.is_empty() or background.is_empty() or not raw.get("recent") is Array:
		return {}
	var entries: Array = raw["recent"]
	if entries.size() > MAX_RECENTS:
		return {}
	var recent: Array[Color] = []
	var keys: Dictionary = {}
	for entry: Variant in entries:
		var parsed: Dictionary = _parse_rgba(entry)
		if parsed.is_empty():
			return {}
		var key: String = entry
		if keys.has(key):
			return {}
		keys[key] = true
		recent.append(parsed["color"])
	return {"foreground": foreground["color"], "background": background["color"],
		"editing_background": raw["editing_background"], "recent": recent}


static func read_file(path: String) -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var source: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if source == null:
			continue
		if source.get_length() > MAX_BYTES:
			source.close()
			continue
		var decoded: Dictionary = decode(JSON.parse_string(source.get_as_text()))
		source.close()
		if not decoded.is_empty():
			return decoded
	return {}


static func save_file(path: String, foreground: Color, background: Color,
		editing_background: bool, recent: Array[Color]) -> bool:
	if recent.size() > MAX_RECENTS:
		return false
	var encoded: Array[String] = []
	for item: Color in recent:
		encoded.append("#" + item.to_html(true).to_upper())
	var raw: Dictionary = {"schema": VERSION, "foreground": "#" + foreground.to_html(true).to_upper(),
		"background": "#" + background.to_html(true).to_upper(),
		"editing_background": editing_background, "recent": encoded}
	if decode(raw).is_empty():
		return false
	var destination: String = ProjectSettings.globalize_path(path)
	var temporary: String = destination + ".tmp"
	var backup: String = destination + ".bak"
	var source: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if source == null:
		return false
	source.store_string(JSON.stringify(raw))
	source.flush()
	source.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(destination, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(backup, destination)
		return false
	DirAccess.remove_absolute(backup)
	return true
