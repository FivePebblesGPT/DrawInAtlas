class_name AtlasCampaignCopy
extends RefCounted
## Copy one verified, published portable campaign into a fresh sibling project
## directory. The destination directory is the only publication boundary;
## neither source documents nor source Object Asset identities are rewritten.

const MAX_DEPTH: int = 32
const MAX_FILES: int = 200000
const MAX_BYTES: int = 17179869184 # 16 GiB total; reject unbounded directory walks.


static func _copy_file(source: String, target: String, counters: Dictionary,
		before_file: Callable) -> DrawingResult:
	if before_file.is_valid() and not bool(before_file.call(source, target)):
		return DrawingResult.failure("COPY_CANCELLED", "Project copy stopped before publication")
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null:
		return DrawingResult.failure("COPY_SOURCE", "Project component is unreadable")
	var length: int = file.get_length()
	file.close()
	if length < 0 or int(counters["files"]) >= MAX_FILES or \
			int(counters["bytes"]) > MAX_BYTES - length:
		return DrawingResult.failure("COPY_LIMIT", "Project component copy exceeds bounded limits")
	var observed_hash: String = FileAccess.get_sha256(source)
	if observed_hash.is_empty() or DirAccess.copy_absolute(source, target) != OK or \
			not FileAccess.file_exists(target) or FileAccess.get_sha256(source) != observed_hash or \
			FileAccess.get_sha256(target) != observed_hash:
		return DrawingResult.failure("COPY_BYTES", "Project component changed or failed verification")
	counters["files"] = int(counters["files"]) + 1
	counters["bytes"] = int(counters["bytes"]) + length
	return DrawingResult.success()


static func _copy_directory(source: String, target: String, counters: Dictionary,
		before_file: Callable, depth: int = 0) -> DrawingResult:
	if depth >= MAX_DEPTH:
		return DrawingResult.failure("COPY_DEPTH", "Project has excessively nested directories")
	var directory: DirAccess = DirAccess.open(source)
	if directory == null or DirAccess.make_dir_absolute(target) != OK:
		return DrawingResult.failure("COPY_DIRECTORY", "Cannot stage project directory")
	var directories: PackedStringArray = directory.get_directories()
	var files: PackedStringArray = directory.get_files()
	directories.sort()
	files.sort()
	for name: String in directories:
		if directory.is_link(name) or name == "." or name == "..":
			return DrawingResult.failure("COPY_LINK", "Linked or invalid project directory")
		var copied: DrawingResult = _copy_directory(source.path_join(name),
			target.path_join(name), counters, before_file, depth + 1)
		if not copied.ok:
			return copied
	for name: String in files:
		if directory.is_link(name) or name == "." or name == "..":
			return DrawingResult.failure("COPY_LINK", "Linked or invalid project file")
		var copied: DrawingResult = _copy_file(source.path_join(name),
			target.path_join(name), counters, before_file)
		if not copied.ok:
			return copied
	return DrawingResult.success()


static func _discard_directory(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in directory.get_directories():
		if directory.is_link(name):
			DirAccess.remove_absolute(path.path_join(name))
		else:
			_discard_directory(path.path_join(name))
	DirAccess.remove_absolute(path)


## Destination parent must already exist, and destination directory must not.
## Existing project data, including interrupted writes and unrelated files,
## is never replaced. Staging in the same parent permits one final rename.
static func copy_portable(source_path: String, destination_path: String,
		before_file: Callable = Callable()) -> DrawingResult:
	var source: String = source_path.simplify_path()
	var destination: String = destination_path.simplify_path()
	var source_dir: String = source.get_base_dir()
	var dest_dir: String = destination.get_base_dir()
	var dest_parent: String = dest_dir.get_base_dir()
	if source != source_path or destination != destination_path or \
			not source.is_absolute_path() or not destination.is_absolute_path() or \
			not source.ends_with(".scn") or not destination.ends_with(".scn") or \
			source_dir == dest_dir or dest_dir.begins_with(source_dir + "/") or \
			source_dir.begins_with(dest_dir + "/") or \
			not AtlasObjectLibrary._portable_path_has_no_links(source) or \
			not AtlasObjectLibrary._portable_path_has_no_links(dest_parent):
		return DrawingResult.failure("COPY_PATH", "Select two distinct nonlinked project folders")
	var destination_parent: DirAccess = DirAccess.open(dest_parent)
	if destination_parent == null or destination_parent.is_link(dest_dir.get_file()) or \
			DirAccess.dir_exists_absolute(dest_dir) or FileAccess.file_exists(dest_dir):
		return DrawingResult.failure("COPY_EXISTS", "Destination project folder must not exist")
	var source_root: String = AtlasCampaignBundle.root_path(source)
	if not FileAccess.file_exists(source_root) or \
			not AtlasObjectLibrary._portable_path_has_no_links(source_root):
		return DrawingResult.failure("COPY_SOURCE", "Source has no safe portable root")
	var original_hash: String = FileAccess.get_sha256(source_root)
	var loaded: AtlasStoreResult = AtlasCampaignBundle.load(source)
	if loaded.error != OK or loaded.recovered:
		return DrawingResult.failure("COPY_SOURCE", "Source's current generation is not fully valid")
	# A newer transitional Objects index represents unsaved campaign changes.
	# Do not ship it as if it belonged to the last authoritative generation.
	var object_index: String = source_dir.path_join("Objects").path_join(
		source.get_file() + ".atlas-object-index.json")
	if FileAccess.file_exists(object_index):
		if not AtlasObjectLibrary._portable_path_has_no_links(object_index):
			return DrawingResult.failure("COPY_LINK", "Source Object index is linked")
		var parsed_objects: Variant = JSON.parse_string(FileAccess.get_file_as_string(object_index))
		var current_objects: Variant = JSON.parse_string(JSON.stringify(loaded.library.export_index()))
		if not parsed_objects is Dictionary or parsed_objects != current_objects:
			return DrawingResult.failure("STALE_OBJECTS", "Save the modified Object registry into a campaign generation first")
	var source_backup: String = AtlasCampaignBundle.backup_path(source)
	if FileAccess.file_exists(source_backup):
		if not AtlasObjectLibrary._portable_path_has_no_links(source_backup) or \
				AtlasCampaignBundle._load_one(source, source_backup, AtlasStoreIO.new()).error != OK:
			return DrawingResult.failure("COPY_BACKUP", "Source's previous generation is incomplete")
	var stage: String = dest_parent.path_join(".atlas-copy-" + DrawingDocument.new_id())
	if DirAccess.dir_exists_absolute(stage) or DirAccess.make_dir_absolute(stage) != OK:
		return DrawingResult.failure("COPY_STAGE", "Cannot reserve a fresh project staging folder")
	var staged_path: String = stage.path_join(destination.get_file())
	var counters: Dictionary = {"files": 0, "bytes": 0}
	var copied: DrawingResult = DrawingResult.success()
	for component: String in ["Drawings", "Objects", "Fonts"]:
		if not copied.ok:
			break
		var component_source: String = source_dir.path_join(component)
		var source_parent: DirAccess = DirAccess.open(source_dir)
		if source_parent != null and source_parent.is_link(component):
			copied = DrawingResult.failure("COPY_LINK", "Source project component is a symlink")
		elif DirAccess.dir_exists_absolute(component_source):
			copied = _copy_directory(component_source, stage.path_join(component),
				counters, before_file)
	if copied.ok:
		var source_index: String = stage.path_join("Objects").path_join(
			source.get_file() + ".atlas-object-index.json")
		var destination_index: String = stage.path_join("Objects").path_join(
			destination.get_file() + ".atlas-object-index.json")
		if source_index != destination_index and FileAccess.file_exists(source_index):
			if FileAccess.file_exists(destination_index) or \
				DirAccess.rename_absolute(source_index, destination_index) != OK:
				copied = DrawingResult.failure("COPY_INDEX", "Cannot retarget the Objects registry filename")
	if copied.ok:
		copied = _copy_file(source_root, AtlasCampaignBundle.root_path(staged_path),
			counters, before_file)
	if copied.ok and FileAccess.file_exists(source_backup):
		copied = _copy_file(source_backup, AtlasCampaignBundle.backup_path(staged_path),
			counters, before_file)
	if copied.ok:
		var verified: AtlasStoreResult = AtlasCampaignBundle.load(staged_path)
		if verified.error != OK or verified.recovered or verified.generation != loaded.generation:
			copied = DrawingResult.failure("COPY_VERIFY", "Staged project generation did not validate")
		elif FileAccess.file_exists(source_backup) and \
				AtlasCampaignBundle._load_one(staged_path,
					AtlasCampaignBundle.backup_path(staged_path), AtlasStoreIO.new()).error != OK:
			copied = DrawingResult.failure("COPY_VERIFY", "Staged backup generation did not validate")
		elif FileAccess.get_sha256(source_root) != original_hash:
			copied = DrawingResult.failure("STALE_ROOT", "Source root changed during project copy")
		elif DirAccess.dir_exists_absolute(dest_dir) or FileAccess.file_exists(dest_dir) or \
				DirAccess.rename_absolute(stage, dest_dir) != OK:
			copied = DrawingResult.failure("COPY_PUBLISH", "Destination appeared or could not be published")
	if not copied.ok:
		_discard_directory(stage)
		return copied
	return DrawingResult.success({"generation": loaded.generation,
		"files": counters["files"], "bytes": counters["bytes"]})
