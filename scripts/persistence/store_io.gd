class_name AtlasStoreIO
extends RefCounted

## All checkpoint filesystem operations pass through these overridable methods.
## Renames must atomically replace the destination without first deleting it.

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
