class_name DrawingWorkspacePreferences
extends RefCounted
## App settings only: never stored in `.drawing` or used in content revision checks.

const VERSION: int = 1
const MAX_BYTES: int = 2048


static func decode(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("schema") != VERSION or \
			not value.get("record_selection_history") is bool:
		return {}
	return {"record_selection_history": value["record_selection_history"]}


static func read_file(path: String) -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var stream: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if stream == null or stream.get_length() > MAX_BYTES:
			continue
		var parsed: Variant = JSON.parse_string(stream.get_as_text())
		stream.close()
		var checked: Dictionary = decode(parsed)
		if not checked.is_empty():
			return checked
	return {}


static func save_file(path: String, enabled: bool) -> bool:
	var destination: String = ProjectSettings.globalize_path(path)
	var temporary: String = destination + ".tmp"
	var backup: String = destination + ".bak"
	var stream: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		return false
	stream.store_string(JSON.stringify({"schema": VERSION,
		"record_selection_history": enabled}))
	stream.flush()
	stream.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(destination, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(backup, destination)
		DirAccess.remove_absolute(temporary)
		return false
	DirAccess.remove_absolute(backup)
	return true
