class_name DrawingObjectRootHistory
extends RefCounted
## Last explicitly chosen portable Objects/ folder, never an Atlas binding.
## Remembering a path does not scan, open or register anything on next launch.

const SCHEMA: int = 1
const MAX_BYTES: int = 4096
const MAX_PATH: int = 2048


static func valid_path(path: String) -> bool:
	return not path.is_empty() and path.length() <= MAX_PATH and \
		path == path.simplify_path() and path.is_absolute_path() and \
		path.get_file() == "Objects" and not path.to_utf8_buffer().has(0)


static func read_file(path: String) -> String:
	for candidate: String in [path, path + ".bak"]:
		var file: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			if file != null:
				file.close()
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary and parsed.get("schema") == SCHEMA and \
				parsed.get("root") is String and valid_path(String(parsed["root"])):
			return String(parsed["root"])
	return ""


static func save_file(path: String, root: String) -> bool:
	if not valid_path(root):
		return false
	var destination: String = ProjectSettings.globalize_path(path)
	var temporary: String = destination + ".tmp"
	var backup: String = destination + ".bak"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"schema": SCHEMA, "root": root}))
	file.flush()
	file.close()
	if FileAccess.file_exists(destination):
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(destination, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, destination)
		DirAccess.remove_absolute(temporary)
		return false
	DirAccess.remove_absolute(backup)
	return true
