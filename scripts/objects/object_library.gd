class_name AtlasObjectLibrary
extends RefCounted
## T-060: Atlas-owned Object Asset registry. Drawing owns all editable content.
## Objects/<campaign-file>.atlas-object-index.json is a transitional portable
## root for this component; T-066 integrates it with the campaign generation root.

signal asset_published(asset_id: String, revision: int)
signal instances_changed(instance_ids: Array[String])
signal child_graph_changed(asset_id: String, dependent_source_ids: Array[String])

const SCHEMA: String = "atlas-objects-v1"
const INDEX_LIMIT: int = 16777216
const MAX_ENTRIES: int = 10000
const CHILD_GRAPH: Script = preload("res://scripts/objects/object_child_graph.gd")
const MAX_TREE_NODES: int = 2048
const MAX_TREE_RENDER_PIXELS: int = 4194304
const MAX_TREE_FRAME_PIXELS: int = 1048576

var campaign_path: String = ""
var root_path: String = ""
## Fault-injection gate invoked before replacing the registry root.
var publication_guard: Callable
var _assets: Dictionary[String, Dictionary] = {}
var _instances: Dictionary[String, AtlasObjectInstance] = {}
var _cache: Dictionary[String, DrawingDocument] = {}
## Optimistic guard for a second process/library handle. T-066 adds a lease.
var _index_hash: String = ""


func _init(path: String = "") -> void:
	campaign_path = path.simplify_path() if not path.is_empty() else ""
	if campaign_path.is_absolute_path():
		root_path = campaign_path.get_base_dir().path_join("Objects")


func _ready_path() -> bool:
	return not root_path.is_empty() and root_path.is_absolute_path()


static func _new_id(prefix: String) -> String:
	return prefix + "-" + Crypto.new().generate_random_bytes(16).hex_encode()


static func _id(value: Variant) -> bool:
	return value is String and DrawingDocument.valid_identifier(value) and value != "root"


static func _transform_valid(value: Transform2D) -> bool:
	return value.x.is_finite() and value.y.is_finite() and value.origin.is_finite() \
		and is_finite(value.determinant()) and absf(value.determinant()) > 0.00000001


static func _metadata_valid(metadata: Dictionary) -> bool:
	if metadata.size() > 128:
		return false
	for key: Variant in metadata:
		if not key is String or not (metadata[key] is bool or metadata[key] is String \
				or metadata[key] is int or metadata[key] is float) or \
				(metadata[key] is float and not is_finite(metadata[key])):
			return false
	return true


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and value >= 0 and value <= 2147483647 and floorf(float(value)) == float(value)


static func _valid_frame(record: Dictionary) -> bool:
	var origin: Variant = record.get("origin", [0, 0])
	var bounds: Variant = record.get("bounds", [0, 0, 0, 0])
	if not origin is Array or origin.size() != 2 or not bounds is Array or bounds.size() != 4:
		return false
	for value: Variant in origin:
		if not _signed_frame_integer(value):
			return false
	for index: int in range(4):
		if not _signed_frame_integer(bounds[index]) or (index >= 2 and bounds[index] < 0):
			return false
	return true


static func _signed_frame_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and \
		absf(float(value)) <= 1000000000.0 and floorf(float(value)) == float(value)


func _relative(asset_id: String, version: int) -> String:
	return "Objects/%s/v%06d.drawing" % [asset_id, version]


func _absolute(relative: String) -> String:
	return campaign_path.get_base_dir().path_join(relative)


func _index_path() -> String:
	return root_path.path_join(campaign_path.get_file() + ".atlas-object-index.json")


## Reject symlinks at the project/asset boundary: canonical relative
## strings alone do not prevent Objects/id from resolving outside the project.
func _linked_component(asset_id: String = "", version: int = 0) -> bool:
	if not _ready_path():
		return true
	var parent: DirAccess = DirAccess.open(campaign_path.get_base_dir())
	if parent != null and parent.is_link("Objects"):
		return true
	var object_dir: DirAccess = DirAccess.open(root_path)
	if object_dir == null:
		return false
	if object_dir.is_link(_index_path().get_file()):
		return true
	if asset_id.is_empty():
		return false
	if object_dir.is_link(asset_id):
		return true
	var asset_dir: DirAccess = DirAccess.open(root_path.path_join(asset_id))
	return asset_dir != null and version > 0 and asset_dir.is_link("v%06d.drawing" % version)


func _index_unchanged() -> bool:
	if _linked_component():
		return false
	if not FileAccess.file_exists(_index_path()):
		return _index_hash.is_empty()
	return not _index_hash.is_empty() and FileAccess.get_sha256(_index_path()) == _index_hash


func asset_ids() -> Array[String]:
	var keys: Array[String] = _assets.keys()
	keys.sort()
	return keys


func instance_ids() -> Array[String]:
	var keys: Array[String] = _instances.keys()
	keys.sort()
	return keys


func asset_handle(asset_id: String) -> AtlasObjectAsset:
	return AtlasObjectAsset.from_record(_assets[asset_id]) if _assets.has(asset_id) else null


func asset_info(asset_id: String) -> Dictionary:
	return _assets[asset_id].duplicate(true) if _assets.has(asset_id) else {}


func instance_info(instance_id: String) -> Dictionary:
	if not _instances.has(instance_id):
		return {}
	var record: Dictionary = _instances[instance_id].as_record()
	record["status"] = "NULL" if _instances[instance_id].placeholder or not _asset_available(record["source_id"]) else "linked"
	return record


## Child references are owned by the published parent source, never by its
## Atlas map placements. The returned records are detached from the registry.
func children_for_asset(asset_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _assets.has(asset_id):
		return result
	for child: Dictionary in _assets[asset_id].get("children", []):
		var item: Dictionary = child.duplicate(true)
		item["status"] = "NULL" if item["placeholder"] or not _asset_available(item["source_id"]) else "linked"
		result.append(item)
	return result


func children_revision(asset_id: String) -> int:
	return int(_assets[asset_id].get("children_revision", 0)) if _assets.has(asset_id) else -1


## A single index transaction changes the graph without altering immutable
## Drawing source bytes or silently publishing a new pixel revision.
func _replace_children(asset_id: String, expected_revision: int,
		children: Array) -> DrawingResult:
	if not _assets.has(asset_id) or children_revision(asset_id) != expected_revision:
		return DrawingResult.failure("STALE_CHILDREN", "Nested source changed; refresh before editing")
	var assets: Dictionary[String, Dictionary] = _assets_copy()
	assets[asset_id]["children"] = children.duplicate(true)
	assets[asset_id]["children_revision"] = expected_revision + 1
	var checked: DrawingResult = CHILD_GRAPH.validate(assets)
	if not checked.ok:
		return checked
	var saved: DrawingResult = _commit_index(assets, _instances_copy())
	if saved.ok:
		child_graph_changed.emit(asset_id, dependent_sources(asset_id))
	return saved


func attach_child(asset_id: String, expected_revision: int, child_source: String,
		placement: Transform2D = Transform2D.IDENTITY) -> DrawingResult:
	if not _asset_available(asset_id) or not _asset_available(child_source) 			or not _transform_valid(placement):
		return DrawingResult.failure("CHILD_SOURCE", "Both sources must be available and transform invertible")
	var children: Array = _assets[asset_id].get("children", []).duplicate(true)
	var child_id: String = _new_id("child")
	children.append({"id": child_id, "generation": _new_id("generation"),
		"source_id": child_source,
		"transform": [placement.x.x, placement.x.y, placement.y.x,
			placement.y.y, placement.origin.x, placement.origin.y],
		"visible": true, "placeholder": false, "revision": 0, "metadata": {}})
	var result: DrawingResult = _replace_children(asset_id, expected_revision, children)
	return DrawingResult.success(child_id) if result.ok else result


func transform_child(asset_id: String, child_id: String, expected_revision: int,
		placement: Transform2D) -> DrawingResult:
	if not _assets.has(asset_id) or not _transform_valid(placement):
		return DrawingResult.failure("CHILD", "Invalid parent or transform")
	var children: Array = _assets[asset_id].get("children", []).duplicate(true)
	for child: Dictionary in children:
		if child["id"] == child_id:
			child["transform"] = [placement.x.x, placement.x.y, placement.y.x,
				placement.y.y, placement.origin.x, placement.origin.y]
			child["revision"] = int(child["revision"]) + 1
			return _replace_children(asset_id, expected_revision, children)
	return DrawingResult.failure("CHILD", "Nested instance not found")


## Visibility is a parent-owned child layout edit, not a source pixel edit.
## Check both identities/revisions so a stale inspector cannot affect a
## different generation of the same instance or publish a partial layout.
func set_child_visibility(asset_id: String, child_id: String, expected_revision: int,
		expected_generation: String, expected_child_revision: int,
		visible: bool) -> DrawingResult:
	if not _assets.has(asset_id) or children_revision(asset_id) != expected_revision:
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before editing visibility")
	var children: Array = _assets[asset_id].get("children", []).duplicate(true)
	for child: Dictionary in children:
		if String(child["id"]) != child_id:
			continue
		if String(child["generation"]) != expected_generation or \
				int(child["revision"]) != expected_child_revision:
			return DrawingResult.failure("STALE_CHILDREN", "Child identity changed; reload before editing visibility")
		if bool(child["visible"]) == visible:
			return DrawingResult.success(false)
		child["visible"] = visible
		child["revision"] = int(child["revision"]) + 1
		var changed: DrawingResult = _replace_children(asset_id, expected_revision, children)
		return DrawingResult.success(true) if changed.ok else changed
	return DrawingResult.failure("CHILD", "Nested instance not found")


func detach_child(asset_id: String, child_id: String, expected_revision: int) -> DrawingResult:
	if not _assets.has(asset_id):
		return DrawingResult.failure("CHILD", "Parent source missing")
	var children: Array = _assets[asset_id].get("children", []).duplicate(true)
	for index: int in range(children.size()):
		if children[index]["id"] == child_id:
			children.remove_at(index)
			return _replace_children(asset_id, expected_revision, children)
	return DrawingResult.failure("CHILD", "Nested instance not found")


## Restore a detached child at its original sibling position for parent-local
## history. The caller supplies an exact saved identity; validation and optimistic
## publication are identical to ordinary insertion, including cycle detection.
func _restore_child_snapshot(asset_id: String, expected_revision: int,
		child_record: Dictionary, position: int) -> DrawingResult:
	if not _asset_available(asset_id) or not CHILD_GRAPH._child_valid(child_record) or 			child_record.has("status"):
		return DrawingResult.failure("CHILD", "Invalid saved nested child")
	if not bool(child_record["placeholder"]) and 			not _asset_available(String(child_record["source_id"])):
		return DrawingResult.failure("CHILD_SOURCE", "Child source is unavailable")
	var children: Array = _assets[asset_id].get("children", []).duplicate(true)
	if position < 0 or position > children.size():
		return DrawingResult.failure("CHILD", "Original child position is no longer valid")
	children.insert(position, child_record.duplicate(true))
	return _replace_children(asset_id, expected_revision, children)


## Rebind one child without changing its stable identity or local transform.
## History can restore a NULL link only through this checked private boundary;
## all callers share the same graph validation and atomic index publication.
func _set_child_binding(parent_id: String, child_id: String,
		expected_parent_revision: int, expected_generation: String,
		expected_child_revision: int, source_id: String, placeholder: bool,
		metadata: Dictionary) -> DrawingResult:
	if not _assets.has(parent_id) or children_revision(parent_id) != expected_parent_revision:
		return DrawingResult.failure("STALE_CHILDREN", "Parent source changed before child repair")
	if not placeholder and not _asset_available(source_id):
		return DrawingResult.failure("MISSING_SOURCE", "Choose an available published replacement source")
	var children: Array = _assets[parent_id].get("children", []).duplicate(true)
	for child: Dictionary in children:
		if child["id"] != child_id:
			continue
		if child["generation"] != expected_generation or int(child["revision"]) != expected_child_revision:
			return DrawingResult.failure("STALE_CHILDREN", "Child identity or revision has changed")
		child["source_id"] = source_id
		child["placeholder"] = placeholder
		child["metadata"] = metadata.duplicate(true)
		child["revision"] = expected_child_revision + 1
		return _replace_children(parent_id, expected_parent_revision, children)
	return DrawingResult.failure("CHILD", "Nested child no longer exists")


## Explicit NULL repair never guesses a replacement by name. The original
## source ID survives in metadata for forensic/UX inspection and undo.
func repair_child_placeholder(parent_id: String, child_id: String,
		expected_parent_revision: int, expected_generation: String,
		expected_child_revision: int, replacement_source_id: String) -> DrawingResult:
	if not _assets.has(parent_id) or children_revision(parent_id) != expected_parent_revision:
		return DrawingResult.failure("STALE_CHILDREN", "Reload parent before repairing a nested child")
	var children: Array = _assets[parent_id].get("children", [])
	for child: Dictionary in children:
		if child["id"] != child_id:
			continue
		if child["generation"] != expected_generation or int(child["revision"]) != expected_child_revision:
			return DrawingResult.failure("STALE_CHILDREN", "Nested child changed before repair")
		if not bool(child["placeholder"]) and _asset_available(String(child["source_id"])):
			return DrawingResult.failure("NOT_NULL", "Only missing nested sources can be repaired")
		if not _asset_available(replacement_source_id):
			return DrawingResult.failure("MISSING_SOURCE", "Replacement source is absent or unverified")
		var metadata: Dictionary = child.get("metadata", {}).duplicate(true)
		if not metadata.has("null_origin_source_id"):
			if metadata.size() >= 128:
				return DrawingResult.failure("METADATA_LIMIT", "Cannot preserve missing source identity")
			metadata["null_origin_source_id"] = child["source_id"]
		var repaired: DrawingResult = _set_child_binding(parent_id, child_id,
			expected_parent_revision, expected_generation, expected_child_revision,
			replacement_source_id, false, metadata)
		return DrawingResult.success(child_id) if repaired.ok else repaired
	return DrawingResult.failure("CHILD", "Nested child no longer exists")


func dependent_sources(asset_id: String) -> Array[String]:
	return CHILD_GRAPH.dependent_sources(_assets, asset_id)


func _asset_available(asset_id: String) -> bool:
	if not _assets.has(asset_id):
		return false
	var record: Dictionary = _assets[asset_id]
	if _linked_component(asset_id, record["revision"]):
		return false
	var path: String = _absolute(record["path"])
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == record["sha256"]


func asset_exists(asset_id: String) -> bool:
	return _asset_available(asset_id)


func instances_for_asset(asset_id: String) -> Array[String]:
	var keys: Array[String] = []
	for instance_id: String in _instances:
		if _instances[instance_id].source_id == asset_id:
			keys.append(instance_id)
	keys.sort()
	return keys


## Atlas-only usage information; the Drawing Asset Browser remains unaware of
## placement ownership. Unreferenced published sources remain in the registry.
func source_usage(asset_id: String) -> Dictionary:
	var linked: int = 0
	var placeholders: int = 0
	var available: bool = _asset_available(asset_id)
	for instance_id: String in _instances:
		var item: AtlasObjectInstance = _instances[instance_id]
		if item.source_id != asset_id:
			continue
		if item.placeholder or not available:
			placeholders += 1
		else:
			linked += 1
	return {"linked": linked, "null": placeholders, "total": linked + placeholders}


## A confirmation token for destructive source changes. It captures every
## binding, its generation and revision, and the complete registry digest.
## The UI must pass this token back, never just the selected source name.
func preview_delete_asset(asset_id: String) -> DrawingResult:
	if not _assets.has(asset_id):
		return DrawingResult.failure("SOURCE", "Object source is absent; refresh before deleting")
	var bindings: Array[Dictionary] = []
	for instance_id: String in instances_for_asset(asset_id):
		var item: AtlasObjectInstance = _instances[instance_id]
		bindings.append({"id": item.id, "generation": item.generation,
			"revision": item.revision, "source_id": item.source_id})
	var child_bindings: Array[Dictionary] = []
	for parent_id: String in asset_ids():
		var parent: Dictionary = _assets[parent_id]
		for child: Dictionary in parent.get("children", []):
			if child["source_id"] == asset_id:
				child_bindings.append({"parent_id": parent_id,
					"children_revision": parent.get("children_revision", 0),
					"id": child["id"], "generation": child["generation"],
					"revision": child["revision"], "source_id": child["source_id"]})
	return DrawingResult.success({"asset_id": asset_id,
		"revision": _assets[asset_id]["revision"],
		"registry_hash": _index_hash, "bindings": bindings,
		"child_bindings": child_bindings})


## Repair is an explicit, optimistic rebind. An absent source is never
## guessed from a display name; the caller supplies a published replacement ID.
## Preserve instance identity, generation, transform, map/floor/detail, visibility
## and user metadata, while retaining the first missing source ID for inspection.
func repair_placeholder(instance_id: String, expected_generation: String,
		expected_revision: int, replacement_id: String) -> DrawingResult:
	if not _instances.has(instance_id):
		return DrawingResult.failure("STALE_INSTANCE", "Missing NULL placement")
	var original: AtlasObjectInstance = _instances[instance_id]
	if original.generation != expected_generation or original.revision != expected_revision:
		return DrawingResult.failure("STALE_INSTANCE", "NULL placement changed; refresh before repairing")
	if not original.placeholder and _asset_available(original.source_id):
		return DrawingResult.failure("NOT_NULL", "Live instance does not require repair")
	if not _asset_available(replacement_id):
		return DrawingResult.failure("MISSING_SOURCE", "Choose a published, available replacement source")
	if original.metadata.size() >= 128 and not original.metadata.has("null_origin_source_id"):
		return DrawingResult.failure("METADATA_LIMIT", "Cannot retain the missing source identity in full metadata")
	var next: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	var repaired: AtlasObjectInstance = next[instance_id]
	if not repaired.metadata.has("null_origin_source_id"):
		repaired.metadata["null_origin_source_id"] = repaired.source_id
	repaired.source_id = replacement_id
	repaired.placeholder = false
	repaired.revision += 1
	var saved: DrawingResult = _commit_index(_assets_copy(), next)
	if not saved.ok:
		return saved
	instances_changed.emit([instance_id])
	return DrawingResult.success(instance_id)


func export_index() -> Dictionary:
	var assets: Array[Dictionary] = []
	var instances: Array[Dictionary] = []
	for asset_id: String in asset_ids():
		assets.append(_assets[asset_id].duplicate(true))
	for instance_id: String in instance_ids():
		instances.append(_instances[instance_id].as_record())
	return {"schema": SCHEMA, "assets": assets, "instances": instances}


## Copy the currently published Objects component to a different campaign
## directory, preserving source IDs, nested child links and map bindings.
## The destination campaign file itself is managed by the campaign saver.
## No unindexed revisions or live draft pixels are copied.
func copy_objects_to(destination_campaign_path: String) -> DrawingResult:
	var destination: String = destination_campaign_path.simplify_path()
	var source_directory: String = campaign_path.get_base_dir()
	var target_directory: String = destination.get_base_dir()
	if not _ready_path() or not FileAccess.file_exists(_index_path()) or \
			not _index_unchanged() or _linked_component():
		return DrawingResult.failure("STALE_INDEX", "Reload a valid source Object registry before copying")
	if not destination.is_absolute_path() or destination != destination_campaign_path or \
			not destination.ends_with(".scn") or target_directory == source_directory or \
			target_directory.begins_with(source_directory + "/") or \
			not _portable_path_has_no_links(destination):
		return DrawingResult.failure("COPY_PATH", "Choose another existing, nonlinked campaign directory")
	var parent: DirAccess = DirAccess.open(target_directory)
	if parent == null or parent.dir_exists("Objects") or parent.file_exists("Objects") or \
			parent.is_link("Objects"):
		return DrawingResult.failure("COPY_EXISTS", "Destination Objects directory must not exist")
	var snapshot: Dictionary = export_index()
	var checked: DrawingResult = CHILD_GRAPH.validate(_assets)
	if not checked.ok:
		return checked
	for source_id: String in asset_ids():
		if not _asset_available(source_id):
			return DrawingResult.failure("MISSING_SOURCE", "An indexed Object revision is unavailable")
	var stage: String = target_directory.path_join(".Objects-copy-" + DrawingDocument.new_id())
	if DirAccess.dir_exists_absolute(stage) or DirAccess.make_dir_absolute(stage) != OK:
		return DrawingResult.failure("COPY_STAGE", "Cannot reserve a new Objects staging directory")
	var copied_files: Array[String] = []
	var copied_dirs: Array[String] = []
	var copied_index: String = stage.path_join(destination.get_file() + ".atlas-object-index.json")
	var copy_error: String = ""
	for source_id: String in asset_ids():
		if not _index_unchanged() or not _asset_available(source_id):
			copy_error = "Source registry or revision changed while copying"
			break
		var revision: int = int(_assets[source_id]["revision"])
		var source_dir: String = stage.path_join(source_id)
		var output_path: String = source_dir.path_join("v%06d.drawing" % revision)
		if DirAccess.make_dir_absolute(source_dir) != OK:
			copy_error = "Cannot stage Object revision directory"
			break
		copied_dirs.append(source_dir)
		# Register the destination before the copy: a failed file copy can
		# leave partial bytes that must also be removed from the stage.
		copied_files.append(output_path)
		if DirAccess.copy_absolute(_absolute(_relative(source_id, revision)), output_path) != OK:
			copy_error = "Cannot copy indexed Object revision"
			break
		if FileAccess.get_sha256(output_path) != String(_assets[source_id]["sha256"]):
			copy_error = "Copied Object bytes failed the published checksum"
			break
	if copy_error.is_empty():
		if DirAccess.copy_absolute(_index_path(), copied_index) != OK:
			copy_error = "Cannot copy Object registry"
		elif not _index_unchanged() or FileAccess.get_sha256(copied_index) != _index_hash or \
				export_index() != snapshot:
			copy_error = "Source Object registry changed while copying"
		elif parent.dir_exists("Objects") or parent.file_exists("Objects") or \
				parent.is_link("Objects") or DirAccess.rename_absolute(stage, \
				target_directory.path_join("Objects")) != OK:
			copy_error = "Destination Objects directory appeared or cannot be published"
	if not copy_error.is_empty():
		DirAccess.remove_absolute(copied_index)
		for path: String in copied_files:
			DirAccess.remove_absolute(path)
		copied_dirs.reverse()
		for path: String in copied_dirs:
			DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(stage)
		return DrawingResult.failure("COPY_FAILED", copy_error)
	return DrawingResult.success({"sources": _assets.size(), "placements": _instances.size()})


## Only this root index is written atomically; campaign-wide publication is T-066.
func _commit_index(assets: Dictionary[String, Dictionary],
		instances: Dictionary[String, AtlasObjectInstance]) -> DrawingResult:
	if not _ready_path():
		return DrawingResult.failure("PATH", "Absolute campaign file path required")
	if not _index_unchanged():
		return DrawingResult.failure("STALE_INDEX", "Registry changed outside this library handle; reload first")
	var payload: Dictionary = {"schema": SCHEMA, "assets": [], "instances": []}
	var keys: Array[String] = assets.keys()
	keys.sort()
	for key: String in keys:
		payload["assets"].append(assets[key].duplicate(true))
	keys = instances.keys()
	keys.sort()
	for key: String in keys:
		payload["instances"].append(instances[key].as_record())
	var bytes: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	if bytes.size() > INDEX_LIMIT:
		return DrawingResult.failure("INDEX_LIMIT", "Object registry is too large")
	if publication_guard.is_valid() and not bool(publication_guard.call()):
		return DrawingResult.failure("PUBLISH", "Registry publication was rejected")
	if DirAccess.make_dir_recursive_absolute(root_path) != OK:
		return DrawingResult.failure("WRITE", "Cannot create Objects directory")
	var pending: String = _index_path() + ".pending-" + DrawingDocument.new_id()
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return DrawingResult.failure("WRITE", "Cannot stage object registry")
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(pending)
		return DrawingResult.failure("WRITE", "Cannot flush object registry")
	if not _index_unchanged():
		DirAccess.remove_absolute(pending)
		return DrawingResult.failure("STALE_INDEX", "Registry changed while staging")
	if DirAccess.rename_absolute(pending, _index_path()) != OK:
		DirAccess.remove_absolute(pending)
		return DrawingResult.failure("WRITE", "Cannot replace object registry")
	_assets = assets
	_instances = instances
	_index_hash = FileAccess.get_sha256(_index_path())
	return DrawingResult.success()


func _assets_copy() -> Dictionary[String, Dictionary]:
	var copy: Dictionary[String, Dictionary] = {}
	for key: String in _assets:
		copy[key] = _assets[key].duplicate(true)
	return copy


func _instances_copy() -> Dictionary[String, AtlasObjectInstance]:
	var copy: Dictionary[String, AtlasObjectInstance] = {}
	for key: String in _instances:
		copy[key] = AtlasObjectInstance.from_record(_instances[key].as_record())
	return copy


## Validate all paths by reconstructing the canonical relative path, never by
## joining untrusted index strings. A same-name replacement fails its checksum.
func load() -> DrawingResult:
	if not _ready_path() or _linked_component():
		return DrawingResult.failure("PATH", "Unsafe or absent campaign/Objects directory")
	var filename: String = _index_path()
	if not FileAccess.file_exists(filename):
		return DrawingResult.failure("MISSING_INDEX", "No Object registry for this campaign folder")
	var file: FileAccess = FileAccess.open(filename, FileAccess.READ)
	if file == null or file.get_length() > INDEX_LIMIT:
		return DrawingResult.failure("INDEX", "Object registry is unreadable or too large")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("schema") != SCHEMA \
		or not parsed.get("assets") is Array or not parsed.get("instances") is Array:
		return DrawingResult.failure("INDEX", "Unsupported object registry")
	return load_snapshot(parsed)


## Restore an immutable campaign generation independently of a later component index.
func load_snapshot(snapshot: Dictionary) -> DrawingResult:
	var parsed: Dictionary = snapshot
	if not _ready_path() or parsed.get("schema") != SCHEMA \
			or not parsed.get("assets") is Array or not parsed.get("instances") is Array:
		return DrawingResult.failure("INDEX", "Invalid frozen Object Asset index")
	var asset_records: Array = parsed["assets"]
	var instance_records: Array = parsed["instances"]
	if asset_records.size() > MAX_ENTRIES or instance_records.size() > MAX_ENTRIES:
		return DrawingResult.failure("INDEX_LIMIT", "Too many object entries")
	var assets: Dictionary[String, Dictionary] = {}
	var instances: Dictionary[String, AtlasObjectInstance] = {}
	for value: Variant in asset_records:
		if not value is Dictionary:
			return DrawingResult.failure("INDEX", "Malformed asset")
		var row: Dictionary = value
		var asset_id: Variant = row.get("id")
		var revision: Variant = row.get("revision")
		if not _id(asset_id) or not _integer(revision) or revision < 1 or assets.has(asset_id) \
				or not _valid_frame(row) \
				or not row.get("name") is String or not row.get("sha256") is String \
				or (row["sha256"] as String).length() != 64 or row.get("path") != _relative(asset_id, revision):
			return DrawingResult.failure("INDEX", "Invalid asset ID, revision or path")
		assets[asset_id] = row.duplicate(true)
		assets[asset_id]["origin"] = row.get("origin", [0, 0])
		assets[asset_id]["bounds"] = row.get("bounds", [0, 0, 0, 0])
		assets[asset_id]["revision"] = int(revision)
	for value: Variant in instance_records:
		if not value is Dictionary:
			return DrawingResult.failure("INDEX", "Malformed instance")
		var row: Dictionary = value
		if not _id(row.get("id")) or not _id(row.get("generation")) \
				or not _id(row.get("source_id")) or not _id(row.get("map_id")) \
				or not _id(row.get("floor_id")) or not _id(row.get("detail_id")) \
				or not row.get("visible") is bool or not row.get("placeholder") is bool \
				or not _integer(row.get("revision")) or not row.get("transform") is Array \
				or not row.get("metadata", {}) is Dictionary:
			return DrawingResult.failure("INDEX", "Invalid placement record")
		if not _metadata_valid(row.get("metadata", {})):
			return DrawingResult.failure("INDEX", "Invalid instance metadata")
		var elements: Array = row["transform"]
		if elements.size() != 6:
			return DrawingResult.failure("INDEX", "Invalid transform length")
		for number: Variant in elements:
			if not (number is float or number is int) or not is_finite(float(number)):
				return DrawingResult.failure("INDEX", "Non-finite placement")
		row["revision"] = int(row["revision"])
		var item: AtlasObjectInstance = AtlasObjectInstance.from_record(row)
		if not _transform_valid(item.transform) or instances.has(item.id):
			return DrawingResult.failure("INDEX", "Invalid or duplicate placement")
		instances[item.id] = item
	# Validate all nested-reference edges before replacing live registry state.
	# Old indexes without children remain valid and keep their original schema.
	var graph: DrawingResult = CHILD_GRAPH.validate(assets)
	if not graph.ok:
		return graph
	# Referenced missing/corrupt assets remain in the index as broken links.
	_assets = assets
	_instances = instances
	_cache.clear()
	_index_hash = FileAccess.get_sha256(_index_path()) if FileAccess.file_exists(_index_path()) else ""
	return DrawingResult.success({"assets": assets.size(), "instances": instances.size()})


func _clone_document(source: DrawingDocument, fresh_ids: bool) -> DrawingResult:
	if source == null:
		return DrawingResult.failure("DOCUMENT", "Missing Drawing source")
	if not fresh_ids:
		var encoded: DrawingResult = DrawingFileIO.encode(source)
		return DrawingFileIO.decode(encoded.value) if encoded.ok else encoded
	var cloned: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(),
		source.tile_stride, source.density_numerator, source.density_denominator)
	for child: String in source.list_children():
		var snapshot: DrawingResult = source.export_subtree(child)
		if not snapshot.ok:
			return snapshot
		var imported: DrawingResult = cloned.import_subtree(snapshot.value, DrawingDocument.ROOT_ID)
		if not imported.ok:
			return imported
	return DrawingResult.success(cloned)


## An unreachable staged revision can be removed after a rejected index commit.
## Never remove a version referenced by the currently published registry.
func _discard_staged(record: Dictionary) -> void:
	var id: String = record["id"]
	var relative: String = record["path"]
	if not _assets.has(id) or _assets[id]["path"] != relative:
		DirAccess.remove_absolute(_absolute(relative))


func _stage_asset(source: DrawingDocument, asset_id: String,
		version: int, label: String, origin: Vector2i = Vector2i.ZERO,
		bounds: Rect2i = Rect2i()) -> DrawingResult:
	var dir: String = root_path.path_join(asset_id)
	if _linked_component(asset_id, version):
		return DrawingResult.failure("PATH", "Object file or parent directory is a symlink")
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return DrawingResult.failure("WRITE", "Cannot stage asset directory")
	var relative: String = _relative(asset_id, version)
	var absolute: String = _absolute(relative)
	if FileAccess.file_exists(absolute):
		return DrawingResult.failure("COLLISION", "Immutable object revision exists")
	var written: DrawingResult = DrawingFileIO.save(source, absolute)
	if not written.ok:
		return written
	return DrawingResult.success({"id": asset_id, "name": label,
		"origin": [origin.x, origin.y], "bounds": [bounds.position.x,
			bounds.position.y, bounds.size.x, bounds.size.y],
		"revision": version, "path": relative,
		"sha256": FileAccess.get_sha256(absolute)})


func create_asset(document: DrawingDocument, label: String) -> DrawingResult:
	if not _ready_path() or document == null or document.external_history:
		return DrawingResult.failure("SOURCE", "Expected independent Drawing source and absolute campaign path")
	var copy: DrawingResult = _clone_document(document, true)
	if not copy.ok:
		return copy
	var asset_id: String = _new_id("asset")
	var staged: DrawingResult = _stage_asset(copy.value, asset_id, 1, label)
	if not staged.ok:
		return staged
	var next_assets: Dictionary[String, Dictionary] = _assets_copy()
	next_assets[asset_id] = staged.value
	var saved: DrawingResult = _commit_index(next_assets, _instances_copy())
	if not saved.ok:
		_discard_staged(staged.value)
		return saved
	_cache[asset_id] = copy.value
	asset_published.emit(asset_id, 1)
	return DrawingResult.success(asset_id)


## Check every existing ancestor, not only the selected leaf. A file dialog
## can return a path below a symlinked directory outside the campaign root.
static func _portable_path_has_no_links(path: String) -> bool:
	var current: String = path
	for i: int in range(64):
		var base: String = current.get_base_dir()
		if base == current:
			return true
		var parent: DirAccess = DirAccess.open(base)
		if parent == null or parent.is_link(current.get_file()):
			return false
		current = base
	return false


## Rejected imports may create a new revision directory before registry commit.
## Remove only our unpublished version and a now-empty directory, preserving
## anything another writer may have put there in the meantime.
func _discard_import_stage(record: Dictionary) -> void:
	_discard_staged(record)
	var directory: String = root_path.path_join(String(record["id"]))
	var dir: DirAccess = DirAccess.open(directory)
	if dir != null and dir.get_files().is_empty() and dir.get_directories().is_empty():
		DirAccess.remove_absolute(directory)


## Register an external portable Object source in one Atlas index transaction.
## Keep the original stable Drawing ID; campaign-local publication starts at v1.
## Never adopt an existing revision directory, even if its index was deleted.
func import_portable_source(source_path: String) -> DrawingResult:
	if not _ready_path() or not _index_unchanged():
		return DrawingResult.failure("STALE_INDEX", "Reload a valid campaign Object registry before import")
	var source: String = source_path.simplify_path()
	if not source.is_absolute_path() or not source.ends_with(".drawing") or \
			source != source_path or source.begins_with(root_path + "/"):
		return DrawingResult.failure("IMPORT_PATH", "Choose an external absolute portable .drawing source")
	var parent: DirAccess = DirAccess.open(source.get_base_dir())
	if parent == null or not _portable_path_has_no_links(source) or not FileAccess.file_exists(source):
		return DrawingResult.failure("IMPORT_PATH", "Source is missing or a symbolic link")
	var before: String = FileAccess.get_sha256(source)
	if before.is_empty():
		return DrawingResult.failure("IMPORT_PATH", "Cannot read portable source bytes")
	var opened: DrawingResult = DrawingObjectEditorFile.open(source)
	if not opened.ok:
		return opened
	var info: Dictionary = opened.value
	var asset_id: String = String(info["source_id"])
	var label: String = String(info["name"])
	var origin: Vector2i = info["origin"]
	var bounds: Rect2i = info["bounds"]
	if not _id(asset_id) or label.strip_edges().is_empty() or \
			label.length() > 128 or "\n" in label or "\r" in label or \
			not _valid_frame({"origin": [origin.x, origin.y], "bounds": \
			[bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]}):
		return DrawingResult.failure("SOURCE", "Invalid portable Object identity or local frame")
	if _assets.has(asset_id):
		return DrawingResult.failure("DUPLICATE_ID", "Stable Object source ID is already published")
	var objects: DirAccess = DirAccess.open(root_path)
	if objects != null and (objects.is_link(asset_id) or objects.dir_exists(asset_id)):
		return DrawingResult.failure("DUPLICATE_ID", "An existing Object revision directory reserves this source ID")
	if FileAccess.get_sha256(source) != before:
		return DrawingResult.failure("STALE_SOURCE", "Portable source changed during validation")
	var staged: DrawingResult = _stage_asset(info["document"], asset_id, 1, label, origin, bounds)
	if not staged.ok:
		return staged
	if FileAccess.get_sha256(source) != before:
		_discard_import_stage(staged.value)
		return DrawingResult.failure("STALE_SOURCE", "Portable source changed during publication")
	var next_assets: Dictionary[String, Dictionary] = _assets_copy()
	next_assets[asset_id] = staged.value
	var saved: DrawingResult = _commit_index(next_assets, _instances_copy())
	if not saved.ok:
		_discard_import_stage(staged.value)
		return saved
	asset_published.emit(asset_id, 1)
	return DrawingResult.success(asset_id)


## Export the exact published revision with portable name/frame metadata.
## An export is a new file, not a registry edit or source rebinding.
func export_portable_source(asset_id: String, destination_path: String,
		expected_revision: int = -1) -> DrawingResult:
	if not _assets.has(asset_id) or not _index_unchanged() or \
			(expected_revision >= 0 and _assets[asset_id]["revision"] != expected_revision):
		return DrawingResult.failure("STALE_SOURCE", "Refresh the selected published source")
	if not _asset_available(asset_id):
		return DrawingResult.failure("MISSING_SOURCE", "Published Object file is unavailable")
	if not _assets[asset_id].get("children", []).is_empty():
		return DrawingResult.failure("NESTED_EXPORT", "Nested links cannot yet be exported as a portable source")
	var target: String = destination_path.simplify_path()
	if not target.is_absolute_path() or not target.ends_with(".drawing") or \
			target != destination_path or target.begins_with(root_path + "/"):
		return DrawingResult.failure("EXPORT_PATH", "Choose a new .drawing file outside campaign Objects/")
	var parent: DirAccess = DirAccess.open(target.get_base_dir())
	if parent == null or not _portable_path_has_no_links(target) or FileAccess.file_exists(target):
		return DrawingResult.failure("EXISTS", "Export destination already exists or is unsafe")
	var doc: DrawingResult = _published_document(asset_id)
	if not doc.ok:
		return doc
	var record: Dictionary = _assets[asset_id]
	var origin: Array = record["origin"]
	var bounds: Array = record["bounds"]
	var pending: String = target + ".pending-" + DrawingDocument.new_id()
	var written: DrawingResult = DrawingObjectEditorFile.save(doc.value, pending,
		String(record["name"]), Vector2i(int(origin[0]), int(origin[1])),
		Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])),
		int(record["revision"]))
	if not written.ok:
		DirAccess.remove_absolute(pending)
		return written
	if not _asset_available(asset_id) or not _index_unchanged() or \
			FileAccess.file_exists(target) or not _portable_path_has_no_links(target):
		DirAccess.remove_absolute(pending)
		return DrawingResult.failure("STALE_SOURCE", "Published source or destination changed during export")
	if DirAccess.rename_absolute(pending, target) != OK:
		DirAccess.remove_absolute(pending)
		return DrawingResult.failure("WRITE", "Cannot publish portable Object export")
	return DrawingResult.success(target)


func _published_document(asset_id: String) -> DrawingResult:
	if not _asset_available(asset_id):
		_cache.erase(asset_id)
		return DrawingResult.failure("MISSING_SOURCE", "Object source file missing or replaced")
	if not _cache.has(asset_id):
		var opened: DrawingResult = DrawingFileIO.open(_absolute(_assets[asset_id]["path"]))
		if not opened.ok:
			return opened
		_cache[asset_id] = opened.value
	return DrawingResult.success(_cache[asset_id], _assets[asset_id]["revision"])


func begin_draft(asset_id: String, origin_instance_id: String = "") -> DrawingResult:
	var original: DrawingResult = _published_document(asset_id)
	if not original.ok:
		return original
	var copy: DrawingResult = _clone_document(original.value, false)
	if not copy.ok:
		return copy
	var draft: AtlasObjectDraft = AtlasObjectDraft.new(copy.value, asset_id,
		_assets[asset_id]["revision"], _assets[asset_id]["name"])
	var frame: Dictionary = _assets[asset_id]
	var frame_origin: Array = frame.get("origin", [0, 0])
	var frame_bounds: Array = frame.get("bounds", [0, 0, 0, 0])
	draft.origin = Vector2i(int(frame_origin[0]), int(frame_origin[1]))
	draft.bounds = Rect2i(int(frame_bounds[0]), int(frame_bounds[1]),
		int(frame_bounds[2]), int(frame_bounds[3]))
	if not origin_instance_id.is_empty():
		if not _instances.has(origin_instance_id):
			return DrawingResult.failure("INSTANCE", "Missing originating placement")
		var instance: AtlasObjectInstance = _instances[origin_instance_id]
		if instance.placeholder or instance.source_id != asset_id:
			return DrawingResult.failure("BINDING", "Origin no longer references this source")
		draft.origin_instance_id = origin_instance_id
		draft.origin_generation = instance.generation
		draft.origin_binding_revision = instance.revision
	return DrawingResult.success(draft)


## Private edits become visible to every linked instance only after publication.
func save_draft(draft: AtlasObjectDraft) -> DrawingResult:
	if draft == null or not _assets.has(draft.source_id) or \
		_assets[draft.source_id]["revision"] != draft.source_revision:
		return DrawingResult.failure("STALE_SOURCE", "Published source changed since draft opened")
	var detached: DrawingResult = _clone_document(draft.document, false)
	if not detached.ok:
		return detached
	var version: int = draft.source_revision + 1
	var staged: DrawingResult = _stage_asset(detached.value, draft.source_id, version,
		draft.name, draft.origin, draft.bounds)
	if not staged.ok:
		return staged
	var next_assets: Dictionary[String, Dictionary] = _assets_copy()
	# A pixel-only source Save must never discard the registry-owned child graph.
	# Use the latest graph, which may have changed independently of this draft.
	if next_assets[draft.source_id].has("children"):
		staged.value["children"] = next_assets[draft.source_id]["children"].duplicate(true)
		staged.value["children_revision"] = next_assets[draft.source_id].get("children_revision", 0)
	next_assets[draft.source_id] = staged.value
	var saved: DrawingResult = _commit_index(next_assets, _instances_copy())
	if not saved.ok:
		_discard_staged(staged.value)
		return saved
	_cache[draft.source_id] = detached.value
	draft.document = ( _clone_document(detached.value, false).value as DrawingDocument)
	draft.source_revision = version
	asset_published.emit(draft.source_id, version)
	instances_changed.emit(instances_for_asset(draft.source_id))
	return DrawingResult.success(version)


func _put_binding(instance_id: String, generation: String, original: String,
		updated: String, expected_revision: int) -> bool:
	if not _instances.has(instance_id) or not _assets.has(updated):
		return false
	var item: AtlasObjectInstance = _instances[instance_id]
	if item.generation != generation or item.source_id != original or item.revision != expected_revision:
		return false
	var next: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	next[instance_id].source_id = updated
	next[instance_id].revision += 1
	next[instance_id].placeholder = false
	if not _commit_index(_assets_copy(), next).ok:
		return false
	instances_changed.emit([instance_id])
	return true


func _publish_variant_and_bind(draft: AtlasObjectDraft, new_id: String,
		instance_id: String, generation: String, original: String,
		expected_revision: int, label: String) -> bool:
	if not _instances.has(instance_id) or _instances[instance_id].generation != generation \
		or _instances[instance_id].source_id != original \
		or _instances[instance_id].revision != expected_revision \
		or not _assets.has(original) or _assets[original]["revision"] != draft.source_revision:
		return false
	var copied: DrawingResult = _clone_document(draft.document, true)
	if not copied.ok:
		return false
	var staged: DrawingResult = _stage_asset(copied.value, new_id, 1,
		label, draft.origin, draft.bounds)
	if not staged.ok:
		return false
	var next_assets: Dictionary[String, Dictionary] = _assets_copy()
	next_assets[new_id] = staged.value
	var next_instances: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	next_instances[instance_id].source_id = new_id
	next_instances[instance_id].revision += 1
	if not _commit_index(next_assets, next_instances).ok:
		_discard_staged(staged.value)
		return false
	_cache[new_id] = copied.value
	asset_published.emit(new_id, 1)
	instances_changed.emit([instance_id])
	return true


func save_as(draft: AtlasObjectDraft, timeline: AtlasEditHistory = null,
		before: DrawingHistoryContext = null,
		after: DrawingHistoryContext = null, variant_name: String = "") -> DrawingResult:
	if draft == null or not _assets.has(draft.source_id) or \
		_assets[draft.source_id]["revision"] != draft.source_revision:
		return DrawingResult.failure("STALE_SOURCE", "Source changed since draft opened")
	# Child-copy ownership policy is still unresolved in T-064/T-051.
	# Refuse rather than silently drop or duplicate source-linked children.
	if not _assets[draft.source_id].get("children", []).is_empty():
		return DrawingResult.failure("NESTED_SAVE_AS", "Nested Save As needs an explicit child-copy policy")
	var label: String = variant_name.strip_edges() if not variant_name.is_empty() else draft.name + " copy"
	if label.is_empty() or label.length() > 128 or "\n" in label or "\r" in label:
		return DrawingResult.failure("NAME", "Invalid new Object Asset name")
	if draft.origin_instance_id.is_empty():
		var cloned: DrawingResult = _clone_document(draft.document, true)
		if not cloned.ok:
			return cloned
		var fresh_id: String = _new_id("asset")
		var staged: DrawingResult = _stage_asset(cloned.value, fresh_id, 1,
			label, draft.origin, draft.bounds)
		if not staged.ok:
			return staged
		var next_assets: Dictionary[String, Dictionary] = _assets_copy()
		next_assets[fresh_id] = staged.value
		var saved: DrawingResult = _commit_index(next_assets, _instances_copy())
		if not saved.ok:
			_discard_staged(staged.value)
			return saved
		_cache[fresh_id] = cloned.value
		draft.source_id = fresh_id
		draft.source_revision = 1
		draft.name = label
		# The editor must never receive the live published document itself.
		draft.document = (_clone_document(cloned.value, false).value as DrawingDocument)
		asset_published.emit(fresh_id, 1)
		return DrawingResult.success(fresh_id)
	if timeline == null or before == null or after == null or before.map_id.is_empty():
		return DrawingResult.failure("HISTORY", "Atlas Save As requires a global timeline and origin contexts")
	var origin_id: String = draft.origin_instance_id
	var generation: String = draft.origin_generation
	var original: String = draft.source_id
	if not _instances.has(origin_id) or _instances[origin_id].generation != generation \
		or _instances[origin_id].source_id != original or \
		_instances[origin_id].revision != draft.origin_binding_revision or \
		_instances[origin_id].map_id != before.map_id or \
		_instances[origin_id].floor_id != before.floor_group_id or \
		_instances[origin_id].detail_id != before.detail_group_id or \
		before.selected_instance_id != origin_id or before.asset_id != original or \
		after.selected_instance_id != origin_id or after.map_id != before.map_id:
		return DrawingResult.failure("STALE_INSTANCE", "Origin was moved, replaced or rebound")
	var variant: String = _new_id("asset")
	var expected: Dictionary = {"revision": draft.origin_binding_revision}
	var lookup: Callable = func(instance_id: String) -> Dictionary:
		return instance_info(instance_id)
	var exists: Callable = func(asset_id: String) -> bool:
		return asset_exists(asset_id)
	var publish: Callable = func(instance_id: String, gen: String, src: String, dst: String) -> bool:
		var ok: bool = _publish_variant_and_bind(draft, dst, instance_id, gen, src,
			expected["revision"], label)
		if ok:
			expected["revision"] = expected["revision"] + 1
		return ok
	var bind: Callable = func(instance_id: String, gen: String, src: String, dst: String) -> bool:
		var ok: bool = _put_binding(instance_id, gen, src, dst, expected["revision"])
		if ok:
			expected["revision"] = expected["revision"] + 1
		return ok
	# The new ID is allocated during this call, not in the UI's after-context.
	# History must restore the real retained asset identity on redo.
	var after_binding: DrawingHistoryContext = after.detached_copy()
	after_binding.asset_id = variant
	after_binding.selected_instance_id = origin_id
	var command: AtlasAssetRebind = AtlasAssetRebind.new(origin_id, generation,
		original, variant, before, after_binding, lookup, exists, publish, bind)
	if not timeline.execute_asset_rebind(command):
		return DrawingResult.failure("PUBLISH", "Failed atomic Save As and rebind")
	# B's saved revision and source file now exist; editor may switch tabs to B.
	var opened: DrawingResult = _published_document(variant)
	if not opened.ok:
		return opened
	draft.source_id = variant
	draft.source_revision = 1
	draft.name = label
	draft.document = (_clone_document(opened.value, false).value as DrawingDocument)
	draft.origin_instance_id = ""
	return DrawingResult.success(variant)


func place(asset_id: String, map_id: String, floor_id: String, detail_id: String,
		placement: Transform2D = Transform2D.IDENTITY) -> DrawingResult:
	if not _asset_available(asset_id) or not _id(map_id) or not _id(floor_id) \
		or not _id(detail_id) or not _transform_valid(placement):
		return DrawingResult.failure("PLACE", "Missing source, location or invertible placement")
	var item: AtlasObjectInstance = AtlasObjectInstance.new()
	item.id = _new_id("instance")
	item.generation = _new_id("generation")
	item.source_id = asset_id
	item.map_id = map_id
	item.floor_id = floor_id
	item.detail_id = detail_id
	item.transform = placement
	var next: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	next[item.id] = item
	var saved: DrawingResult = _commit_index(_assets_copy(), next)
	if not saved.ok:
		return saved
	instances_changed.emit([item.id])
	return DrawingResult.success(item.id)


func transform_instance(instance_id: String, expected_revision: int,
		placement: Transform2D) -> DrawingResult:
	if not _instances.has(instance_id) or _instances[instance_id].revision != expected_revision \
		or not _transform_valid(placement):
		return DrawingResult.failure("STALE_INSTANCE", "Missing, stale or invalid placement")
	var next: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	next[instance_id].transform = placement
	next[instance_id].revision += 1
	var saved: DrawingResult = _commit_index(_assets_copy(), next)
	if saved.ok:
		instances_changed.emit([instance_id])
	return saved


func set_instance_visibility(instance_id: String, expected_revision: int,
		visible: bool) -> DrawingResult:
	if not _instances.has(instance_id) or _instances[instance_id].revision != expected_revision:
		return DrawingResult.failure("STALE_INSTANCE", "Missing or stale placement")
	var next: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	next[instance_id].visible = visible
	next[instance_id].revision += 1
	var saved: DrawingResult = _commit_index(_assets_copy(), next)
	if saved.ok:
		instances_changed.emit([instance_id])
	return saved


func set_instance_metadata(instance_id: String, expected_revision: int,
		metadata: Dictionary) -> DrawingResult:
	if not _instances.has(instance_id) or _instances[instance_id].revision != expected_revision:
		return DrawingResult.failure("STALE_INSTANCE", "Missing or stale placement")
	# No per-instance artwork overrides; scalar metadata only.
	if not _metadata_valid(metadata):
		return DrawingResult.failure("METADATA", "Only finite primitive instance metadata is supported")
	var next: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	next[instance_id].metadata = metadata.duplicate(true)
	next[instance_id].revision += 1
	var saved: DrawingResult = _commit_index(_assets_copy(), next)
	if saved.ok:
		instances_changed.emit([instance_id])
	return saved


## Return deterministic IDs in this map/floor/detail whose current source has
## raster-alpha coverage; NULL placements have a bounded fallback marker.
func select_at(map_id: String, floor_id: String, detail_id: String,
		world_point: Vector2) -> DrawingResult:
	var hits: Array[String] = []
	for instance_id: String in instance_ids():
		var item: AtlasObjectInstance = _instances[instance_id]
		if item.map_id != map_id or item.floor_id != floor_id or item.detail_id != detail_id:
			continue
		var tested: DrawingResult = hit_test(instance_id, world_point)
		if not tested.ok:
			return tested
		if tested.value is bool and tested.value:
			hits.append(instance_id)
		elif tested.value is Dictionary and tested.value.get("selectable", false):
			hits.append(instance_id)
	return DrawingResult.success(hits)


## Read-only local-space render query, with an explicit NULL result for broken links.
## Find a bounded authored source frame when the user has not supplied an
## explicit Object Editor frame. Frame metadata remains authoritative when set;
## the fallback uses sparse tile extents, not an infinite/giant canvas.
func authored_bounds(asset_id: String) -> DrawingResult:
	if not asset_exists(asset_id):
		return DrawingResult.failure("MISSING_SOURCE", "Object source is unavailable")
	var stored: Dictionary = asset_info(asset_id)
	var frame: Array = stored.get("bounds", [0, 0, 0, 0])
	if frame.size() == 4 and int(frame[2]) > 0 and int(frame[3]) > 0:
		return DrawingResult.success(Rect2i(int(frame[0]), int(frame[1]),
			int(frame[2]), int(frame[3])))
	var fetched: DrawingResult = _published_document(asset_id)
	if not fetched.ok:
		return fetched
	var doc: DrawingDocument = fetched.value
	var manifest: DrawingResult = doc.export_manifest()
	if not manifest.ok:
		return manifest
	var area: Rect2i = Rect2i()
	var found: bool = false
	for layer: Dictionary in manifest.value["layers"]:
		if not layer["visible"]:
			continue
		for chunk: Dictionary in layer["chunks"]:
			var pos: Array = chunk["coord"]
			var piece: Rect2i = Rect2i(Vector2i(int(pos[0]), int(pos[1])) * doc.tile_stride,
				Vector2i.ONE * doc.tile_stride)
			area = area.merge(piece) if found else piece
			found = true
	if not found:
		# Text-only sources still need a small visible frame for composition.
		area = Rect2i(-64, -32, 128, 64)
	return DrawingResult.success(area)


## T-064: draw-order traversal of validated source-owned child references.
## Every item uses root-source coordinates, retaining the stable child path for
## future parent-vs-child selection. A second defensive path check prevents an
## externally corrupted graph from causing a recursive render loop.
func _tree_nodes(source_id: String) -> DrawingResult:
	var nodes: Array[Dictionary] = []
	var pending: Array[Dictionary] = [{"source_id": source_id,
		"transform": Transform2D.IDENTITY, "path": PackedStringArray(),
		"ancestors": [source_id], "depth": 0, "placeholder": false}]
	while not pending.is_empty():
		if nodes.size() >= MAX_TREE_NODES:
			return DrawingResult.failure("TREE_LIMIT", "Too many visible nested Object instances")
		var item: Dictionary = pending.pop_back()
		nodes.append(item)
		if item["placeholder"]:
			continue
		var parent_id: String = item["source_id"]
		var children: Array = _assets[parent_id].get("children", []) if _assets.has(parent_id) else []
		for index: int in range(children.size() - 1, -1, -1):
			var child: Dictionary = children[index]
			if not child["visible"]:
				continue
			var child_source: String = child["source_id"]
			var next_path: PackedStringArray = item["path"].duplicate()
			next_path.append(str(child["id"]))
			var next_ancestors: Array = item["ancestors"].duplicate()
			if child_source in next_ancestors or int(item["depth"]) >= CHILD_GRAPH.MAX_NESTING_DEPTH:
				return DrawingResult.failure("CHILD_CYCLE", "Unsafe nested Object source path")
			next_ancestors.append(child_source)
			var values: Array = child["transform"]
			var local_transform: Transform2D = Transform2D(
				Vector2(float(values[0]), float(values[1])),
				Vector2(float(values[2]), float(values[3])),
				Vector2(float(values[4]), float(values[5])))
			var composed: Transform2D = (item["transform"] as Transform2D) * local_transform
			if not _transform_valid(composed):
				return DrawingResult.failure("CHILD_TRANSFORM", "Nested Object transform exceeds safe range")
			pending.append({"source_id": child_source, "transform": composed,
				"path": next_path, "ancestors": next_ancestors,
				"depth": int(item["depth"]) + 1,
				"placeholder": child["placeholder"] or not _asset_available(child_source)})
	return DrawingResult.success(nodes)


static func _tree_region(region: Rect2i, inverted: Transform2D) -> DrawingResult:
	var corners: Array[Vector2] = [Vector2(region.position),
		Vector2(region.end.x, region.position.y), Vector2(region.end),
		Vector2(region.position.x, region.end.y)]
	var first: Vector2 = inverted * corners[0]
	var smallest: Vector2 = first
	var largest: Vector2 = first
	for corner: Vector2 in corners.slice(1):
		var mapped: Vector2 = inverted * corner
		smallest = smallest.min(mapped)
		largest = largest.max(mapped)
	if not smallest.is_finite() or not largest.is_finite() or 			absf(smallest.x) > 1000000000.0 or absf(smallest.y) > 1000000000.0 or 			absf(largest.x) > 1000000000.0 or absf(largest.y) > 1000000000.0:
		return DrawingResult.failure("TREE_LIMIT", "Nested Object sample coordinates exceed safe range")
	var mapped_region: Rect2i = Rect2i(floori(smallest.x), floori(smallest.y),
		maxi(1, ceili(largest.x) - floori(smallest.x)),
		maxi(1, ceili(largest.y) - floori(smallest.y)))
	if mapped_region.size.x > MAX_TREE_FRAME_PIXELS or 			mapped_region.size.y > MAX_TREE_FRAME_PIXELS / mapped_region.size.x:
		return DrawingResult.failure("TREE_LIMIT", "Nested Object sample exceeds pixel budget")
	return DrawingResult.success(mapped_region)


## Read-only, ordered recursive composition of published raster/text source
## images. Child art overlays parent art; sibling order follows registry order.
## The same affine local coordinates drive nested selection and Atlas placement.
func render_source_tree(source_id: String, region: Rect2i) -> DrawingResult:
	if not _asset_available(source_id):
		return DrawingResult.failure("MISSING_SOURCE", "Root Object source unavailable")
	if region.size.x <= 0 or region.size.y <= 0 or 			region.size.x > MAX_TREE_FRAME_PIXELS or 			region.size.y > MAX_TREE_FRAME_PIXELS / region.size.x:
		return DrawingResult.failure("TREE_LIMIT", "Invalid nested render viewport")
	var traversal: DrawingResult = _tree_nodes(source_id)
	if not traversal.ok:
		return traversal
	var nodes: Array = traversal.value
	var output: Image
	var remaining: int = MAX_TREE_RENDER_PIXELS
	for node: Dictionary in nodes:
		var local_to_root: Transform2D = node["transform"]
		var inverse: Transform2D = local_to_root.affine_inverse()
		var sample_bounds: DrawingResult = _tree_region(region, inverse)
		if not sample_bounds.ok:
			return sample_bounds
		var sample_region: Rect2i = sample_bounds.value
		var area: int = sample_region.size.x * sample_region.size.y
		remaining -= area + region.size.x * region.size.y
		if remaining < 0:
			return DrawingResult.failure("TREE_LIMIT", "Nested Object sampling budget exceeded")
		var tile: Image
		if node["placeholder"]:
			tile = Image.create_empty(sample_region.size.x, sample_region.size.y,
				false, Image.FORMAT_RGBA8)
			for y: int in range(sample_region.size.y):
				for x: int in range(sample_region.size.x):
					var point: Vector2i = sample_region.position + Vector2i(x, y)
					if Rect2i(-8, -8, 16, 16).has_point(point):
						tile.set_pixel(x, y, Color(1.0, 0.25, 0.3, 0.8))
		else:
			var source: DrawingResult = _published_document(node["source_id"])
			if not source.ok:
				return source
			var rendered: DrawingResult = DrawingRenderer.render(source.value, sample_region)
			if not rendered.ok:
				return rendered
			tile = rendered.value
		if output == null:
			output = tile
			continue
		for y: int in range(region.size.y):
			for x: int in range(region.size.x):
				var local: Vector2 = inverse * (Vector2(region.position) + Vector2(x + 0.5, y + 0.5))
				var sample: Vector2i = Vector2i(floori(local.x), floori(local.y)) - sample_region.position
				if sample.x < 0 or sample.y < 0 or sample.x >= tile.get_width() or 						sample.y >= tile.get_height():
					continue
				var color: Color = tile.get_pixelv(sample)
				if color.a > 0.0:
					output.set_pixel(x, y, output.get_pixel(x, y).blend(color))
	return DrawingResult.success(output)


## Includes transformed children beyond the parent's authoring guide, without
## treating that guide as a clip. Atlas uses this for preview/canvas framing.
func composed_bounds(source_id: String) -> DrawingResult:
	if not _asset_available(source_id):
		return DrawingResult.failure("MISSING_SOURCE", "Root Object source unavailable")
	var traversal: DrawingResult = _tree_nodes(source_id)
	if not traversal.ok:
		return traversal
	var combined: Rect2i = Rect2i()
	var found: bool = false
	for node: Dictionary in traversal.value:
		var piece: Rect2i
		if node["placeholder"]:
			piece = Rect2i(-8, -8, 16, 16)
		else:
			var available: DrawingResult = authored_bounds(node["source_id"])
			if not available.ok:
				return available
			piece = available.value
		if not piece.has_area():
			continue
		var transform: Transform2D = node["transform"]
		var corners: Array[Vector2] = [Vector2(piece.position),
			Vector2(piece.end.x, piece.position.y), Vector2(piece.end),
			Vector2(piece.position.x, piece.end.y)]
		var low: Vector2 = transform * corners[0]
		var high: Vector2 = low
		for corner: Vector2 in corners.slice(1):
			var mapped: Vector2 = transform * corner
			low = low.min(mapped)
			high = high.max(mapped)
		if not low.is_finite() or not high.is_finite() or 				absf(low.x) > 1000000000.0 or absf(low.y) > 1000000000.0 or 				absf(high.x) > 1000000000.0 or absf(high.y) > 1000000000.0:
			return DrawingResult.failure("TREE_LIMIT", "Nested Object bounds exceed safe range")
		var enclosed: Rect2i = Rect2i(floori(low.x), floori(low.y),
			maxi(1, ceili(high.x) - floori(low.x)),
			maxi(1, ceili(high.y) - floori(low.y)))
		combined = combined.merge(enclosed) if found else enclosed
		found = true
	return DrawingResult.success(combined)


## Deepest, topmost visible child wins; the path contains stable child IDs.
## Returns false for transparent points, without modifying parent selection.
func hit_test_path(instance_id: String, world_point: Vector2) -> DrawingResult:
	if not _instances.has(instance_id) or not world_point.is_finite():
		return DrawingResult.failure("HIT_TEST", "Invalid nested hit-test request")
	var instance: AtlasObjectInstance = _instances[instance_id]
	if not instance.visible:
		return DrawingResult.success(false)
	var root_local: Vector2 = instance.transform.affine_inverse() * world_point
	if not root_local.is_finite() or absf(root_local.x) > 1000000000.0 or 			absf(root_local.y) > 1000000000.0:
		return DrawingResult.failure("COORD_RANGE", "Nested hit test exceeds safe coordinates")
	if instance.placeholder or not _asset_available(instance.source_id):
		return DrawingResult.success({"status": "NULL", "path": PackedStringArray(),
			"source_id": instance.source_id}) if Rect2(-8, -8, 16, 16).has_point(root_local) 			else DrawingResult.success(false)
	var traversal: DrawingResult = _tree_nodes(instance.source_id)
	if not traversal.ok:
		return traversal
	var nodes: Array = traversal.value
	for index: int in range(nodes.size() - 1, -1, -1):
		var node: Dictionary = nodes[index]
		var local: Vector2 = (node["transform"] as Transform2D).affine_inverse() * root_local
		if not local.is_finite() or absf(local.x) > 1000000000.0 or absf(local.y) > 1000000000.0:
			return DrawingResult.failure("COORD_RANGE", "Nested hit outside coordinate range")
		var hit: bool = false
		if node["placeholder"]:
			hit = Rect2(-8, -8, 16, 16).has_point(local)
		else:
			var document: DrawingResult = _published_document(node["source_id"])
			if not document.ok:
				return document
			var point: Vector2i = Vector2i(floori(local.x), floori(local.y))
			var pixel: DrawingResult = DrawingRenderer.render(document.value,
				Rect2i(point, Vector2i.ONE))
			if not pixel.ok:
				return pixel
			hit = (pixel.value as Image).get_pixel(0, 0).a > 0.0
		if hit:
			return DrawingResult.success({"status": "NULL" if node["placeholder"] else "linked",
				"source_id": node["source_id"], "path": node["path"].duplicate(),
				"source_local": local})
	return DrawingResult.success(false)


func render_instance(instance_id: String, local_region: Rect2i) -> DrawingResult:
	if not _instances.has(instance_id):
		return DrawingResult.failure("INSTANCE", "Missing placement")
	var item: AtlasObjectInstance = _instances[instance_id]
	if not item.visible:
		return DrawingResult.success({"status": "hidden"})
	if item.placeholder or not _asset_available(item.source_id):
		return DrawingResult.success({"status": "NULL", "source_id": item.source_id,
			"transform": item.transform, "marker_local_bounds": Rect2i(-8, -8, 16, 16)})
	var source: DrawingResult = _published_document(item.source_id)
	if not source.ok:
		return source
	var rendered: DrawingResult = render_source_tree(item.source_id, local_region) \
		if not _assets[item.source_id].get("children", []).is_empty() \
		else DrawingRenderer.render(source.value, local_region)
	if not rendered.ok:
		return rendered
	return DrawingResult.success({"status": "linked", "source_id": item.source_id,
		"asset_revision": _assets[item.source_id]["revision"],
		"transform": item.transform, "image": rendered.value})


func hit_test(instance_id: String, world_point: Vector2) -> DrawingResult:
	if not _instances.has(instance_id) or not world_point.is_finite():
		return DrawingResult.failure("HIT_TEST", "Invalid point or placement")
	var item: AtlasObjectInstance = _instances[instance_id]
	if not item.visible:
		return DrawingResult.success(false)
	var local: Vector2 = item.transform.affine_inverse() * world_point
	if item.placeholder or not _asset_available(item.source_id):
		return DrawingResult.success({"status": "NULL",
			"selectable": Rect2(-8.0, -8.0, 16.0, 16.0).has_point(local)})
	if not local.is_finite() or absf(local.x) > 1000000000.0 or absf(local.y) > 1000000000.0:
		return DrawingResult.failure("COORD_RANGE", "Hit test outside supported local viewport")
	if not _assets[item.source_id].get("children", []).is_empty():
		var nested_hit: DrawingResult = hit_test_path(instance_id, world_point)
		if not nested_hit.ok:
			return nested_hit
		return DrawingResult.success(nested_hit.value is Dictionary)
	var output: DrawingResult = render_instance(instance_id,
		Rect2i(floori(local.x), floori(local.y), 1, 1))
	if not output.ok:
		return output
	return DrawingResult.success((output.value["image"] as Image).get_pixel(0, 0).a > 0.0)


## UI for the three deletion policies belongs to T-065. Source bytes are
## retained for history/backup; deletion removes the registry reference only.
func delete_asset(asset_id: String, policy: String,
		expected_preview: Dictionary = {}) -> DrawingResult:
	if policy == "cancel":
		return DrawingResult.success(false)
	if not _assets.has(asset_id) or policy not in ["remove", "null"]:
		return DrawingResult.failure("DELETE", "Unknown asset or deletion policy")
	if not expected_preview.is_empty():
		var current: DrawingResult = preview_delete_asset(asset_id)
		if not current.ok or JSON.stringify(current.value) != JSON.stringify(expected_preview):
			return DrawingResult.failure("STALE_SOURCE", "Source or bindings changed since confirmation opened")
	var next_assets: Dictionary[String, Dictionary] = _assets_copy()
	var next_instances: Dictionary[String, AtlasObjectInstance] = _instances_copy()
	var touched: Array[String] = []
	for instance_id: String in next_instances.keys():
		if next_instances[instance_id].source_id == asset_id:
			touched.append(instance_id)
			if policy == "remove":
				next_instances.erase(instance_id)
			else:
				next_instances[instance_id].placeholder = true
				next_instances[instance_id].revision += 1
	var touched_parents: Array[String] = []
	for parent_id: String in next_assets.keys():
		if parent_id == asset_id:
			continue
		var parent: Dictionary = next_assets[parent_id]
		var children: Array = parent.get("children", [])
		var retained: Array = []
		var changed: bool = false
		for child: Dictionary in children:
			if child["source_id"] != asset_id:
				retained.append(child)
				continue
			changed = true
			if policy == "null":
				var null_child: Dictionary = child.duplicate(true)
				null_child["placeholder"] = true
				null_child["revision"] = int(null_child["revision"]) + 1
				retained.append(null_child)
		if changed:
			parent["children"] = retained
			parent["children_revision"] = int(parent.get("children_revision", 0)) + 1
			touched_parents.append(parent_id)
	next_assets.erase(asset_id)
	var graph: DrawingResult = CHILD_GRAPH.validate(next_assets)
	if not graph.ok:
		return graph
	var saved: DrawingResult = _commit_index(next_assets, next_instances)
	if saved.ok:
		_cache.erase(asset_id)
		instances_changed.emit(touched)
		for parent_id: String in touched_parents:
			child_graph_changed.emit(parent_id, dependent_sources(parent_id))
	return saved
