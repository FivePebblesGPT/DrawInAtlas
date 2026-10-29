class_name AtlasStoreIO
extends RefCounted

## Injection boundary for checkpoint files. Scene encode/decode use isolated
## temporary paths because Godot does not load PackedScene from a byte buffer.
static var _temporary_counter: int = 0

func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


func write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written: bool = file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if not written and error == OK:
		return ERR_FILE_CANT_WRITE
	return error


func rename(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(from_path, to_path)


func make_dir(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(path)


func encode_scene(scene: PackedScene) -> PackedByteArray:
	var path: String = _temporary_path()
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return PackedByteArray()
	# Whole-scene compression also bounds metadata-heavy ink/layer saves.
	var error: Error = ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path) if error == OK else PackedByteArray()
	DirAccess.remove_absolute(path)
	return bytes


func decode_scene(bytes: PackedByteArray) -> PackedScene:
	if bytes.is_empty():
		return null
	var path: String = _temporary_path()
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return null
	var temp_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if temp_file == null:
		return null
	var written: bool = temp_file.store_buffer(bytes)
	temp_file.close()
	if not written:
		DirAccess.remove_absolute(path)
		return null
	# Only shipped application scripts may be referenced externally. Arbitrary
	# res:// assets or another campaign file must not become hidden sidecars.
	for dependency: String in ResourceLoader.get_dependencies(path):
		var parts: PackedStringArray = dependency.split("::")
		var reference: String = parts[parts.size() - 1]
		if not reference.begins_with("res://scripts/") or not reference.ends_with(".gd"):
			DirAccess.remove_absolute(path)
			return null
	var loaded: Resource = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(path)
	return loaded as PackedScene


static func _temporary_path() -> String:
	_temporary_counter += 1
	return "user://drawinatlas_native_io/%d_%d.scn" % [Time.get_ticks_usec(), _temporary_counter]
