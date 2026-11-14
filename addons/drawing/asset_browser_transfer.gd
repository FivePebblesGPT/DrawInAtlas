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
	var selected_sha256: String = FileAccess.get_sha256(source)
	if selected_sha256.is_empty():
		return DrawingResult.failure("STALE_SOURCE", "Cannot pin incoming Object source bytes")
	var read: DrawingResult = DrawingObjectEditorFile.open(source)
	if not read.ok:
		return read
	if not _safe_source_file(source) or FileAccess.get_sha256(source) != selected_sha256:
		return DrawingResult.failure("STALE_SOURCE", "Incoming Object source changed during validation")
	var source_id: String = String(read.value["source_id"])
	if not DrawingDocument.valid_identifier(source_id):
		return DrawingResult.failure("SOURCE_ID", "Object source has an unsafe identity")
	# Import is an infrequent destructive-to-catalog operation: compare a fresh
	# bounded scan to the displayed authorization snapshot before adding a new
	# file. An unseen duplicate/513th source must not be silently accepted.
	var current: DrawingAssetBrowserIndex = DrawingAssetBrowserIndex.new()
	var scanned: DrawingResult = current.scan(index.root_path)
	if not scanned.ok or not current.warnings.is_empty() or current.entries != index.entries:
		return DrawingResult.failure("STALE_INDEX",
			"Objects/ changed since refresh; rescan before importing")
	for entry: Dictionary in current.entries:
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
	if directory.list_dir_begin() != OK:
		return DrawingResult.failure("IMPORT_PATH", "Cannot enumerate Objects/ safely")
	var examined: int = 0
	var atlas_registry: bool = false
	while true:
		var filename: String = directory.get_next()
		if filename.is_empty():
			break
		examined += 1
		if examined > DrawingAssetBrowserIndex.MAX_CANDIDATES:
			break
		if not directory.current_is_dir() and filename.ends_with(".atlas-object-index.json"):
			atlas_registry = true
	directory.list_dir_end()
	if examined > DrawingAssetBrowserIndex.MAX_CANDIDATES:
		return DrawingResult.failure("ASSET_LIMIT", "Objects/ changed during import preflight")
	if atlas_registry:
		return DrawingResult.failure("ATLAS_REGISTRY",
			"Atlas-managed source import requires a campaign registry transaction")
	var target: String = index.root_path.path_join(source_id + ".drawing")
	var copied: DrawingResult = _copy_to_new_file(source, target, selected_sha256)
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
	var result: DrawingResult = _copy_to_new_file(String(entry["path"]), destination,
		String(entry["sha256"]))
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


## An exported indexed source has a selected digest. Never publish newer bytes
## when an external writer swaps the source after safe_to_open() but before IO.
static func _copy_to_new_file(source: String, target: String,
		expected_sha256: String = "") -> DrawingResult:
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
	# An incoming .drawing can be valid JSON *after* Godot replaces malformed
	# UTF-8. Never publish bytes the portable index must later reject. Perform
	# this check on the captured copy, before creating a .pending file.
	if bytes.get_string_from_utf8().to_utf8_buffer() != bytes:
		return DrawingResult.failure("SOURCE_UTF8", "Portable Object source must be valid UTF-8")
	var hashed: HashingContext = HashingContext.new()
	hashed.start(HashingContext.HASH_SHA256)
	hashed.update(bytes)
	var captured_digest: String = hashed.finish().hex_encode()
	if before.is_empty() or (not expected_sha256.is_empty() and before != expected_sha256) or \
			captured_digest != before or FileAccess.get_sha256(source) != before or \
			not DrawingAssetBrowserIndex.path_has_no_links(source) or bytes.is_empty():
		return DrawingResult.failure("STALE_SOURCE", "Selected source changed while copying")
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
			not DrawingAssetBrowserIndex.path_has_no_links(source) or \
			not DrawingAssetBrowserIndex.path_has_no_links(target) or \
			FileAccess.file_exists(target) or target_directory.is_link(target.get_file()):
		DirAccess.remove_absolute(staged)
		return DrawingResult.failure("STALE_SOURCE", "Destination/source changed during staging")
	if DirAccess.rename_absolute(staged, target) != OK:
		DirAccess.remove_absolute(staged)
		return DrawingResult.failure("WRITE", "Cannot publish the portable source file")
	return DrawingResult.success(target)
