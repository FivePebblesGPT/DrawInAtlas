class_name DrawingAssetBrowserIndex
extends RefCounted
## Read-only index of portable Objects/ sources. Does not mutate the campaign,
## publish sources, delete unreferenced assets, or interpret Atlas placements.

const MAX_ASSETS: int = 512
const MAX_CANDIDATES: int = 2048
const MAX_OBJECT_BYTES: int = 64 * 1024 * 1024

var root_path: String = ""
var entries: Array[Dictionary] = []
var warnings: Array[String] = []


## Reject links anywhere in an absolute filesystem path, not only its leaf.
## A renamed campaign parent can become a symlink after a successful scan;
## all subsequent Open/Export checks must revalidate that same boundary.
## This is a point-in-time check, not a cross-process filesystem lease.
static func path_has_no_links(path: String) -> bool:
	if not path.is_absolute_path() or path != path.simplify_path():
		return false
	var current: String = path
	for _part: int in range(128):
		var parent_path: String = current.get_base_dir()
		if parent_path == current:
			return true
		var parent: DirAccess = DirAccess.open(parent_path)
		if parent == null or parent.is_link(current.get_file()):
			return false
		current = parent_path
	return false


func scan(objects_path: String) -> DrawingResult:
	var base: String = objects_path.simplify_path()
	if not path_has_no_links(base) or base.get_file() != "Objects":
		return DrawingResult.failure("ASSET_PATH", "Choose an absolute Objects/ directory")
	var parent: DirAccess = DirAccess.open(base.get_base_dir())
	if parent == null or parent.is_link("Objects"):
		return DrawingResult.failure("ASSET_PATH", "Unsafe or missing Objects/ directory")
	var directory: DirAccess = DirAccess.open(base)
	if directory == null:
		return DrawingResult.failure("ASSET_PATH", "Objects/ directory is missing")
	var next: Array[Dictionary] = []
	var issues: Array[String] = []
	var seen: Dictionary = {}
	# Count *all* direct children, regardless of type or filename. get_files()
	# and get_directories() materialize unbounded arrays, and two separate
	# loops could return a partial, apparently valid index after truncation.
	# Refuse the entire over-budget snapshot before reading any source bytes.
	var child_names: PackedStringArray = []
	var standalone_files: PackedStringArray = []
	if directory.list_dir_begin() != OK:
		return DrawingResult.failure("ASSET_PATH", "Cannot enumerate Objects/ directory")
	var root_examined: int = 0
	var root_over_limit: bool = false
	while true:
		var name: String = directory.get_next()
		if name.is_empty():
			break
		root_examined += 1
		if root_examined > MAX_CANDIDATES:
			root_over_limit = true
			break
		if directory.current_is_dir():
			child_names.append(name)
		else:
			standalone_files.append(name)
	directory.list_dir_end()
	if root_over_limit:
		return DrawingResult.failure("ASSET_LIMIT", "Objects/ root exceeds candidate limit")
	child_names.sort()
	standalone_files.sort()
	for child_name: String in child_names:
		if next.size() >= MAX_ASSETS:
			issues.append("Asset index limit reached")
			break
		if not DrawingDocument.valid_identifier(child_name) or directory.is_link(child_name):
			issues.append("Skipped unsafe asset directory")
			continue
		var asset_directory: DirAccess = DirAccess.open(base.path_join(child_name))
		if asset_directory == null:
			continue
		# A revision folder is untrusted input. Enumerate it incrementally;
		# get_files() materializes an unbounded array before we can apply a cap.
		# Never publish an arbitrarily old revision from a truncated directory.
		if asset_directory.list_dir_begin() != OK:
			issues.append("Skipped unreadable asset revisions")
			continue
		var latest: int = 0
		var chosen: String = ""
		var examined: int = 0
		var over_limit: bool = false
		while true:
			var filename: String = asset_directory.get_next()
			if filename.is_empty():
				break
			examined += 1
			if examined > MAX_CANDIDATES:
				over_limit = true
				break
			if asset_directory.current_is_dir() or asset_directory.is_link(filename) or \
					not filename.begins_with("v") or not filename.ends_with(".drawing"):
				continue
			var digits: String = filename.substr(1, filename.length() - 9)
			if digits.length() != 6 or not digits.is_valid_int():
				continue
			var revision: int = int(digits)
			if revision > latest and revision <= 999999:
				latest = revision
				chosen = filename
		asset_directory.list_dir_end()
		if over_limit:
			issues.append("Skipped asset revision directory exceeding candidate limit")
			continue
		if chosen.is_empty():
			continue
		_read_source(base.path_join(child_name).path_join(chosen), seen, next, issues, child_name)
	# Standalone Drawing can publish individual Objects/*.drawing files, while
	# Atlas's immutable revisions live in Objects/<id>/vNNNNNN.drawing.
	for filename: String in standalone_files:
		if next.size() >= MAX_ASSETS:
			issues.append("Asset index limit reached")
			break
		if filename.ends_with(".drawing") and not directory.is_link(filename):
			_read_source(base.path_join(filename), seen, next, issues)
	next.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).nocasecmp_to(String(b["name"])) < 0 if a["name"] != b["name"] else String(a["id"]) < String(b["id"]))
	root_path = base
	entries = next
	warnings = issues
	return DrawingResult.success(entries.size())


func _read_source(path: String, seen: Dictionary, target: Array[Dictionary],
		issues: Array[String], directory_id: String = "") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_OBJECT_BYTES:
		issues.append("Skipped unreadable or oversized Object source")
		return
	file.close()
	var loaded: DrawingResult = DrawingObjectEditorFile.open(path)
	if not loaded.ok:
		issues.append("Skipped invalid Object source: " + path.get_file())
		return
	var data: Dictionary = loaded.value
	var source_id: String = String(data["source_id"])
	if not DrawingDocument.valid_identifier(source_id) or \
			(not directory_id.is_empty() and source_id != directory_id):
		issues.append("Skipped source with mismatched identity")
		return
	if not directory_id.is_empty() and int(path.get_file().substr(1, 6)) != int(data["source_revision"]):
		issues.append("Skipped versioned source with inconsistent revision")
		return
	if seen.has(source_id):
		issues.append("Duplicate Object source identity: " + source_id)
		# Do not silently choose a potentially incorrect source for Open.
		for index: int in range(target.size() - 1, -1, -1):
			if target[index]["id"] == source_id:
				target.remove_at(index)
		seen[source_id] = false
		return
	if seen.get(source_id, true) == false:
		return
	seen[source_id] = true
	target.append({"id": source_id, "name": String(data["name"]),
		"revision": int(data["source_revision"]), "path": path,
		"bounds": data["bounds"], "sha256": FileAccess.get_sha256(path)})


## Listings are not authority to open files after filesystem changes.
func safe_to_open(entry: Dictionary) -> bool:
	if root_path.is_empty() or not entry.get("path") is String or not entry.get("sha256") is String or \
			not path_has_no_links(root_path):
		return false
	# A correct hash/path by itself does not authorize opening or exporting a
	# source. Require the current index/page to contain that source identity.
	# Drag tokens are a *projection* of an indexed row (no bounds/usage), so
	# compare identity fields and any optional displayed metadata provided.
	var listed: bool = false
	for indexed: Dictionary in entries:
		if indexed.get("id") != entry.get("id") or \
				indexed.get("path") != entry.get("path") or \
				indexed.get("sha256") != entry.get("sha256") or \
				indexed.get("revision") != entry.get("revision"):
			continue
		var metadata_matches: bool = true
		for field: String in ["name", "bounds", "embedded_id", "embedded_revision", "usage"]:
			if entry.has(field) and indexed.get(field) != entry[field]:
				metadata_matches = false
				break
		if metadata_matches:
			listed = true
			break
	if not listed:
		return false
	var path: String = String(entry["path"])
	if not path.begins_with(root_path + "/") or not path_has_no_links(path):
		return false
	var relative: String = path.substr(root_path.length() + 1)
	var parts: PackedStringArray = relative.split("/")
	if parts.size() not in [1, 2] or not parts[-1].ends_with(".drawing"):
		return false
	if parts.size() == 2 and (parts[0] != entry.get("id") or not parts[1].begins_with("v")):
		return false
	var parent: DirAccess = DirAccess.open(root_path.get_base_dir())
	var directory: DirAccess = DirAccess.open(root_path)
	if parent == null or parent.is_link("Objects") or directory == null:
		return false
	if parts.size() == 2:
		if directory.is_link(parts[0]):
			return false
		directory = DirAccess.open(root_path.path_join(parts[0]))
	if directory == null or directory.is_link(parts[-1]):
		return false
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == entry["sha256"]


func filtered(query: String) -> Array[Dictionary]:
	var needle: String = query.strip_edges().to_lower()
	if needle.is_empty():
		return entries.duplicate(true)
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if needle in String(entry["name"]).to_lower() or needle in String(entry["id"]).to_lower():
			result.append(entry.duplicate(true))
	return result
