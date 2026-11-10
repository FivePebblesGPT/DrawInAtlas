class_name DrawingAssetBrowserTransfer
extends RefCounted
## T-065: explicit portable file import/export, not Atlas source registration.
## Refuse ambiguous IDs, unsafe folders, overwrite, and concurrent byte changes.

const MAX_BYTES: int = DrawingAssetBrowserIndex.MAX_OBJECT_BYTES


static func import_file(index: DrawingAssetBrowserIndex, source_path: String) -> DrawingResult:
	if index == null or index.root_path.is_empty() or not index.warnings.is_empty() or \
			not DrawingAssetBrowserIndex.path_has_no_links(index.root_path):
		return DrawingResult.failure("INDEX", "Refresh and resolve Object source warnings before Import")
	if index.entries.size() >= DrawingAssetBrowserIndex.MAX_ASSETS:
		return DrawingResult.failure("LIMIT", "Object source folder is full")
	var source: String = source_path.simplify_path()
	if not _safe_source_file(source) or source.begins_with(index.root_path + "/"):
		return DrawingResult.failure("IMPORT_PATH", "Choose a separate absolute .drawing file")
	var read: DrawingResult = DrawingObjectEditorFile.open(source)
	if not read.ok:
		return read
	var source_id: String = String(read.value["source_id"])
	if not DrawingDocument.valid_identifier(source_id):
		return DrawingResult.failure("SOURCE_ID", "Object source has an unsafe identity")
	for entry: Dictionary in index.entries:
		if entry["id"] == source_id:
			return DrawingResult.failure("DUPLICATE_ID", "This stable Object source ID is already in Objects/")
	var parent: DirAccess = DirAccess.open(index.root_path.get_base_dir())
	var directory: DirAccess = DirAccess.open(index.root_path)
	if parent == null or parent.is_link("Objects") or directory == null or \
			directory.is_link(source_id):
		return DrawingResult.failure("IMPORT_PATH", "Unsafe Object source directory")
	# An old revision directory may exist even when its index entry was rejected.
	if directory.dir_exists(source_id):
		return DrawingResult.failure("DUPLICATE_ID", "This Object source has a reserved revision directory")
	# Atlas owns its own versioned registry and cannot adopt a loose file by
	# copying bytes. Fail closed rather than displaying a misleading import.
	for filename: String in directory.get_files():
		if filename.ends_with(".atlas-object-index.json"):
			return DrawingResult.failure("ATLAS_REGISTRY",
				"Atlas-managed source import requires a campaign registry transaction")
	var target: String = index.root_path.path_join(source_id + ".drawing")
	var copied: DrawingResult = _copy_to_new_file(source, target)
	if not copied.ok:
		return copied
	return DrawingResult.success(target)


static func export_file(index: DrawingAssetBrowserIndex, entry: Dictionary,
		destination_path: String) -> DrawingResult:
	if index == null or not index.safe_to_open(entry):
		return DrawingResult.failure("STALE_SOURCE", "Refresh before exporting a changed Object source")
	var destination: String = destination_path.simplify_path()
	if destination.begins_with(index.root_path + "/"):
		return DrawingResult.failure("EXPORT_PATH", "Export outside the current Objects/ folder")
	var result: DrawingResult = _copy_to_new_file(String(entry["path"]), destination)
	if result.ok and FileAccess.get_sha256(destination) != entry["sha256"]:
		# Another process might have changed the destination; never delete a
		# file after publication unless this process still owns its identity.
		return DrawingResult.failure("STALE_SOURCE", "Export destination changed after publication")
	return result


static func _safe_source_file(path: String) -> bool:
	if not path.is_absolute_path() or not path.ends_with(".drawing") or \
			path != path.simplify_path():
		return false
	return DrawingAssetBrowserIndex.path_has_no_links(path) and FileAccess.file_exists(path)


static func _copy_to_new_file(source: String, target: String) -> DrawingResult:
	if not _safe_source_file(source) or not DrawingAssetBrowserIndex.path_has_no_links(target) or \
			not target.ends_with(".drawing"):
		return DrawingResult.failure("FILE_PATH", "Unsafe Object source or destination")
	var target_directory: DirAccess = DirAccess.open(target.get_base_dir())
	if target_directory == null or target_directory.is_link(target.get_file()) or \
			FileAccess.file_exists(target):
		return DrawingResult.failure("EXISTS", "Destination exists or is not a safe directory")
	var reader: FileAccess = FileAccess.open(source, FileAccess.READ)
	if reader == null or reader.get_length() <= 0 or reader.get_length() > MAX_BYTES:
		return DrawingResult.failure("FILE_LIMIT", "Source is missing, empty or oversized")
	var before: String = FileAccess.get_sha256(source)
	var bytes: PackedByteArray = reader.get_buffer(reader.get_length())
	reader.close()
	if before.is_empty() or FileAccess.get_sha256(source) != before or bytes.is_empty():
		return DrawingResult.failure("STALE_SOURCE", "Source changed while copying")
	var staged: String = target + ".pending-" + DrawingDocument.new_id()
	var writer: FileAccess = FileAccess.open(staged, FileAccess.WRITE)
	if writer == null:
		return DrawingResult.failure("WRITE", "Cannot stage a portable source")
	writer.store_buffer(bytes)
	writer.flush()
	var status: Error = writer.get_error()
	writer.close()
	if status != OK or FileAccess.get_sha256(staged) != before or \
			FileAccess.get_sha256(source) != before or \
			not DrawingAssetBrowserIndex.path_has_no_links(target) or \
			FileAccess.file_exists(target) or target_directory.is_link(target.get_file()):
		DirAccess.remove_absolute(staged)
		return DrawingResult.failure("STALE_SOURCE", "Destination/source changed during staging")
	if DirAccess.rename_absolute(staged, target) != OK:
		DirAccess.remove_absolute(staged)
		return DrawingResult.failure("WRITE", "Cannot publish the portable source file")
	return DrawingResult.success(target)
