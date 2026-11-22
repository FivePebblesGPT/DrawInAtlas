class_name DrawingDocument
extends RefCounted
## Generic sparse Drawing source, with stable nested groups and transactional edits.
## Atlas chooses which document is active; this type knows no Atlas concepts.

const TILES: Script = preload("res://addons/drawing/signed_tiles.gd")
const ROOT_ID: String = "root"
## Native store cap; three full spans per touched tile cover source and replay buffers.
const MAX_NATIVE_HISTORY_TRANSFER_BYTES: int = 256 * 1024 * 1024
## Also bound direct external tile publication before lazy source resolution.
## This is a conservative source/before/after envelope, not resident RSS.
func _native_direct_transfer_within_budget(count: int) -> bool:
	return count > 0 and count <= 128 and \
		count * tile_stride * tile_stride * 4 * 3 <= MAX_NATIVE_HISTORY_TRANSFER_BYTES


var id: String = ""
var tile_stride: int = 256
var density_numerator: int = 1
var density_denominator: int = 1
var revision: int = 0
var published_revision: int = 0
var _content_committed: bool = false
var _nodes: Dictionary[String, DrawingLayerNode] = {}
var _pending_tiles: Dictionary[String, Dictionary] = {}
var _known_refs: Dictionary[String, Dictionary] = {}
var _dirty_tiles: Dictionary[String, bool] = {}
## Short-lived display invalidations, independent of save/publish dirty tiles.
## Missing revisions (layer tree, visibility, text, import) force a full redraw.
const DISPLAY_CHANGE_LIMIT: int = 64
var _display_changes: Array[Dictionary] = []
## Lazy source registration can change visible content without a document
## revision (the caller is attaching a previously published tile).
var display_source_epoch: int = 0
## One local ordered timeline. A selection step carries the current content token.
## External Atlas-owned documents use the host timeline instead of this one.
var external_history: bool = false
var record_selection_history: bool = false
var _events: Array[Dictionary] = []
var _cursor: int = 0
var _content_states: Array[int] = [0]
var _next_content_state: int = 0
var _saved_content_state: int = 0
var _untracked_revision: int = 0
var _saved_untracked_revision: int = 0
## Per-document native authority survives gestures. The GDScript tiles are
## published consumer snapshots for display/save and legacy non-brush edits.
## External document revisions invalidate native source authorization and
## history in one checked rebase before the next native brush transaction.
var _native_raster_store: Object
var _native_source_identities: Dictionary[String, Variant] = {}
## Reentrant lazy providers must never resolve the same key recursively.
var _resolving_chunks: Dictionary[String, bool] = {}


## Once Rust is attached, no direct raster publisher may fall back to a
## Godot-only commit just because its native revision is stale. A deliberate
## checked rebase is a separate recovery boundary, never an implicit write.
func _attached_native_revision_matches(expected: int) -> bool:
	return _native_raster_store == null or \
		int(_native_raster_store.call("stats").get("revision", -1)) == expected


func _native_store_for_edit(expected: int) -> Object:
	if revision != expected or not ClassDB.class_exists("DrawingNativeTiles"):
		return null
	if _native_raster_store == null:
		_native_raster_store = ClassDB.instantiate("DrawingNativeTiles")
		if int(_native_raster_store.call("tile_abi_version")) != 1 \
				or not _native_raster_store.call("configure", tile_stride, revision):
			_native_raster_store = null
			return null
	else:
		var native_revision: int = int(_native_raster_store.call("stats").get("revision", -1))
		if native_revision > revision:
			return null
		if native_revision < revision:
			if not _native_raster_store.call("rebase_external_revision", native_revision, revision):
				return null
			_native_source_identities.clear()
	return _native_raster_store


## Metadata-only mutation: preserve native raster ownership and Undo tokens
## across a document revision that leaves all raster source bytes unchanged.
## Native refuses active/stale transitions. If a reentrant caller has already
## invalidated the bridge, drop its attachment instead of retaining a silently
## divergent authority; detached history snapshots remain replayable.
func _advance_nonraster_revision(discard_redo: bool = true) -> void:
	var previous: int = revision
	revision += 1
	if _native_raster_store == null:
		return
	if not _native_raster_store.call("advance_metadata_revision", previous, discard_redo):
		_native_raster_store = null
		_native_source_identities.clear()


## Public metadata and semantic operations acquire the native revision *before*
## mutating Godot's tree or objects. The older post-mutation bridge remains
## for internal structural-history paths; public and detached-import
## failure must never detach canonical Rust source. No callbacks occur
## between the checked native step and the deterministic live-state write.
func _advance_checked_layer_metadata(discard_redo: bool = true) -> DrawingResult:
	if _native_raster_store != null:
		if not _attached_native_revision_matches(revision):
			return DrawingResult.failure("STALE_REVISION", "Native metadata revision diverged")
		if not bool(_native_raster_store.call("advance_metadata_revision", revision, discard_redo)):
			return DrawingResult.failure("NATIVE_METADATA", "Native metadata revision rejected")
	revision += 1
	return DrawingResult.success(null, revision)


## A structural edit may mention raster layers without modifying any Rust-
## owned bytes: e.g. a newly created, never-authorized raster child. Ask Rust
## to prove that none of the affected IDs has source or Undo/Redo state. A
## rejection leaves its old revision untouched and takes the existing checked
## source-rebase path on the next native gesture.
func _advance_raster_structure_revision(layers: Array[String],
		discard_redo: bool = true) -> void:
	var previous: int = revision
	revision += 1
	if _native_raster_store == null:
		return
	var ids: PackedStringArray = PackedStringArray(layers)
	if _native_raster_store.call("advance_unreferenced_layers_revision",
			previous, ids, discard_redo):
		for layer_id: String in layers:
			for key: String in _native_source_identities.keys():
				if key.begins_with(layer_id + ":"):
					_native_source_identities.erase(key)


## Check all resident source identities without invoking lazy providers. On
## removal, object identity must still match the authorized source. History
## restoration creates detached tile objects, so compare their exact RGBA8
## instead; never blindly trust an edited history snapshot.
func _native_tree_sources_match(nodes: Dictionary, restore: bool) -> bool:
	for identity: String in _native_source_identities:
		var layer_id: String = identity.get_slice(":", 0)
		if not nodes.has(layer_id):
			continue
		var key: String = identity.substr(layer_id.length() + 1)
		var source: Variant = _native_source_identities[identity]
		var current: Variant = (nodes[layer_id] as DrawingLayerNode).tiles.get(key)
		if restore:
			var old_bytes: PackedByteArray = source.to_rgba8() if source != null else PackedByteArray()
			var new_bytes: PackedByteArray = current.to_rgba8() if current != null else PackedByteArray()
			if old_bytes != new_bytes:
				return false
		elif not is_same(source, current):
			return false
		# Object identity alone does not prove in-place RGBA8 mutations are
		# absent. Structural work is cold: compare each imported full tile to
		# Rust's canonical bytes before changing either revision.
		var coordinates: PackedStringArray = key.split(",")
		if _native_raster_store == null or coordinates.size() != 2 or \
				not coordinates[0].is_valid_int() or not coordinates[1].is_valid_int():
			return false
		var resident: Dictionary = _native_raster_store.call("read_tile", layer_id,
			int(coordinates[0]), int(coordinates[1]), false)
		if not bool(resident.get("ok", false)):
			return false
		var bytes: PackedByteArray = current.to_rgba8() if current != null else PackedByteArray()
		var native_bytes: PackedByteArray = resident.get("bytes", PackedByteArray())
		if bytes.is_empty():
			bytes.resize(tile_stride * tile_stride * 4)
		if bytes != native_bytes:
			return false
	return true


## Save is a cold authority boundary: Godot tiles are only a projection of
## Rust-authorized bytes. Detect in-place mutation (which object identity alone
## misses) and attached revision drift before exporting or acknowledging blobs.
## Pending, never-authorized lazy sources are still valid existing content.
func _native_save_projection_matches() -> bool:
	return _native_raster_store == null or \
		(_attached_native_revision_matches(revision) and
		_native_tree_sources_match(_nodes, false))


## A recorded structural removal can temporarily park native-owned raster
## layers without forfeiting their RGBA8 or history tokens. This call is made
## after Godot preflight and before the deterministic tree mutation; no lazy
## source callbacks or allocations occur between Rust commit and tree change.
func _advance_parked_structure_revision(layers: Array[String], restore: bool,
		discard_redo: bool) -> bool:
	if _native_raster_store == null or layers.is_empty():
		return false
	if not bool(_native_raster_store.call("advance_parked_layers_revision",
			revision, PackedStringArray(layers), restore, discard_redo)):
		return false
	revision += 1
	return true


## A direct, unrecorded removal has no structural Undo to restore its raster
## children. Preflight their resident source identity/bytes before Rust drops
## only those layers; unrelated canonical tiles and tokens remain live.
## Rejecting retirement leaves both stores untouched and uses the ordinary
## later checked rebase. This is deliberately not the recorded park path.
func _retire_unrecorded_raster_layers(layers: Array[String], nodes: Dictionary) -> bool:
	if _native_raster_store == null or layers.is_empty() \
			or not _native_tree_sources_match(nodes, false):
		return false
	var previous: int = revision
	if not bool(_native_raster_store.call("retire_layers_revision",
			previous, PackedStringArray(layers), true)):
		return false
	for layer_id: String in layers:
		for identity: String in _native_source_identities.keys():
			if identity.begins_with(layer_id + ":"):
				_native_source_identities.erase(identity)
	revision += 1
	return true


## Prebuild the local history projection *before* Rust retires the layers.
## Permanently deleted nodes must not leave Undo entries blocking unrelated
## native history, but host-owned history is never rewritten here. Surviving
## cursor order/content tokens are retained. Installing this detached result
## after the native commit does not allocate or invoke external providers.
func _prepare_retired_local_history(removed_ids: Array[String]) -> Dictionary:
	if external_history or _events.is_empty():
		return {}
	var removed: Dictionary[String, bool] = {}
	for layer_id: String in removed_ids:
		removed[layer_id] = true
	var retained: Array[Dictionary] = []
	var states: Array[int] = [_content_states[0]]
	var cursor: int = 0
	for index: int in range(_events.size()):
		var event: Dictionary = _events[index]
		var affected: bool = false
		match String(event.get("kind", "")):
			"content":
				affected = removed.has((event["delta"] as DrawingDelta).layer_id)
			"text_tree":
				affected = removed.has(String(event["layer"]))
			"structure":
				affected = removed.has(String(event["id"]))
		if affected:
			continue
		retained.append(event)
		states.append(_content_states[index + 1])
		if index < _cursor:
			cursor += 1
	return {"events": retained, "states": states, "cursor": cursor}


func _native_source_matches(layer_id: String, key: String, tile: Variant) -> bool:
	var identity: String = layer_id + ":" + key
	return _native_source_identities.has(identity) \
		and is_same(_native_source_identities[identity], tile)


func _remember_native_source(layer_id: String, key: String, tile: Variant) -> void:
	_native_source_identities[layer_id + ":" + key] = tile



func _init(document_id: String = "", stride: int = 256,
		density_num: int = 1, density_den: int = 1) -> void:
	assert(stride > 0 and stride <= 2048 and density_num > 0 and density_den > 0)
	id = document_id if not document_id.is_empty() else new_id()
	tile_stride = stride
	density_numerator = density_num
	density_denominator = density_den
	_nodes[ROOT_ID] = DrawingLayerNode.new(ROOT_ID, DrawingLayerNode.GROUP, "Root")


static func new_id() -> String:
	return "drawing-" + Crypto.new().generate_random_bytes(16).hex_encode()


static func valid_identifier(identifier: String) -> bool:
	if identifier.is_empty() or identifier.length() > 128:
		return false
	for index: int in range(identifier.length()):
		var ascii: int = identifier.unicode_at(index)
		if not ((ascii >= 48 and ascii <= 57) or (ascii >= 65 and ascii <= 90)
				or (ascii >= 97 and ascii <= 122) or ascii == 45 or ascii == 95):
			return false
	return true


func is_dirty() -> bool:
	return _content_states[_cursor] != _saved_content_state or _untracked_revision != _saved_untracked_revision


func layer_count() -> int:
	return _nodes.size() - 1


func list_children(parent_id: String = ROOT_ID) -> Array[String]:
	if not _nodes.has(parent_id):
		return []
	return _nodes[parent_id].children.duplicate()


## Return detached metadata/content. No public accessor leaks mutable owned tiles.
func inspect_node(node_id: String) -> DrawingLayerNode:
	return _nodes[node_id].detached_copy() if _nodes.has(node_id) else null


## Lightweight metadata is preferable to duplicating all owned tiles for rendering.
func node_metadata(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	var node: DrawingLayerNode = _nodes[node_id]
	return {"id": node.id, "parent": node.parent_id, "kind": node.kind,
		"name": node.name, "visible": node.visible, "locked": node.locked}


func has_node(node_id: String) -> bool:
	return _nodes.has(node_id)


func create_layer(kind: String, name: String, parent_id: String = ROOT_ID,
		requested_id: String = "", insertion_index: int = -1,
		record_history: bool = false) -> DrawingResult:
	if kind not in [DrawingLayerNode.GROUP, DrawingLayerNode.RASTER,
			DrawingLayerNode.TEXT, DrawingLayerNode.OBJECTS]:
		return DrawingResult.failure("LAYER_KIND", "Unknown generic layer type")
	if not _nodes.has(parent_id) or _nodes[parent_id].kind != DrawingLayerNode.GROUP:
		return DrawingResult.failure("PARENT", "Target is not a group")
	if not _editable(parent_id):
		return DrawingResult.failure("LOCKED", "Parent group is hidden or locked")
	var new_identifier: String = requested_id if not requested_id.is_empty() else new_id()
	if not valid_identifier(new_identifier):
		return DrawingResult.failure("LAYER_ID", "Layer IDs contain only ASCII letters, digits, _ and -")
	if new_identifier == ROOT_ID or _nodes.has(new_identifier):
		return DrawingResult.failure("DUPLICATE_ID", "Layer/group identity already exists")
	if _native_raster_store != null and bool(_native_raster_store.call("is_layer_parked", new_identifier)):
		return DrawingResult.failure("LAYER_ID", "Raster ID is reserved by native structural history")
	var advanced: DrawingResult = _advance_checked_layer_metadata()
	if not advanced.ok:
		return advanced
	_nodes[new_identifier] = DrawingLayerNode.new(new_identifier, kind, name, parent_id)
	var siblings: Array[String] = _nodes[parent_id].children
	var index: int = siblings.size() if insertion_index < 0 else clampi(insertion_index, 0, siblings.size())
	siblings.insert(index, new_identifier)
	_finish_structure(record_history, {"kind": "structure", "op": "create",
		"id": new_identifier, "parent": parent_id, "index": index,
		"node": _nodes[new_identifier].detached_copy()})
	return DrawingResult.success(new_identifier, revision)


func rename_layer(node_id: String, name: String, record_history: bool = false) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID:
		return DrawingResult.failure("LAYER", "Cannot rename missing/root layer")
	if not _editable(node_id):
		return DrawingResult.failure("LOCKED", "Layer or ancestor is hidden or locked")
	if _nodes[node_id].name != name:
		var advanced: DrawingResult = _advance_checked_layer_metadata()
		if not advanced.ok:
			return advanced
		var before: String = _nodes[node_id].name
		_nodes[node_id].name = name
		_finish_structure(record_history, {"kind": "structure", "op": "property",
			"id": node_id, "field": "name", "before": before, "after": name})
	return DrawingResult.success(null, revision)


func set_visibility(node_id: String, visible: bool, record_history: bool = false) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID:
		return DrawingResult.failure("LAYER", "Cannot change missing/root layer")
	if _nodes[node_id].visible != visible:
		var advanced: DrawingResult = _advance_checked_layer_metadata()
		if not advanced.ok:
			return advanced
		var before: bool = _nodes[node_id].visible
		_nodes[node_id].visible = visible
		_finish_structure(record_history, {"kind": "structure", "op": "property",
			"id": node_id, "field": "visible", "before": before, "after": visible})
	return DrawingResult.success(null, revision)


func set_locked(node_id: String, locked: bool, record_history: bool = false) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID:
		return DrawingResult.failure("LAYER", "Cannot change missing/root layer")
	if _nodes[node_id].locked != locked:
		var advanced: DrawingResult = _advance_checked_layer_metadata()
		if not advanced.ok:
			return advanced
		var before: bool = _nodes[node_id].locked
		_nodes[node_id].locked = locked
		_finish_structure(record_history, {"kind": "structure", "op": "property",
			"id": node_id, "field": "locked", "before": before, "after": locked})
	return DrawingResult.success(null, revision)


func _editable(node_id: String) -> bool:
	var current: String = node_id
	while _nodes.has(current):
		var node: DrawingLayerNode = _nodes[current]
		if node.locked or not node.visible:
			return false
		current = node.parent_id
	return true


func reorder(node_id: String, new_parent: String, new_index: int,
		record_history: bool = false) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID or not _nodes.has(new_parent):
		return DrawingResult.failure("LAYER", "Missing layer or group")
	if _nodes[new_parent].kind != DrawingLayerNode.GROUP or not _editable(node_id) or not _editable(new_parent):
		return DrawingResult.failure("PARENT", "Target group unavailable or locked")
	var ancestor: String = new_parent
	while not ancestor.is_empty():
		if ancestor == node_id:
			return DrawingResult.failure("CYCLE", "Cannot move a group into its descendant")
		ancestor = _nodes[ancestor].parent_id
	var current_parent: String = _nodes[node_id].parent_id
	var original: Array[String] = _nodes[current_parent].children
	var old_index: int = original.find(node_id)
	var target_index: int = clampi(new_index, 0, _nodes[new_parent].children.size() -
		(1 if current_parent == new_parent else 0))
	if current_parent == new_parent and target_index == old_index:
		return DrawingResult.success(null, revision)
	var advanced: DrawingResult = _advance_checked_layer_metadata()
	if not advanced.ok:
		return advanced
	original.erase(node_id)
	var destination: Array[String] = _nodes[new_parent].children
	destination.insert(target_index, node_id)
	_nodes[node_id].parent_id = new_parent
	_finish_structure(record_history, {"kind": "structure", "op": "reorder",
		"id": node_id, "old_parent": current_parent, "old_index": old_index,
		"new_parent": new_parent, "new_index": target_index})
	return DrawingResult.success(null, revision)


## Preflight for atomic cross-document transfers; never mutate on rejection.
func can_remove_subtree(node_id: String) -> bool:
	return node_id != ROOT_ID and _nodes.has(node_id) and _editable(node_id)


## Read-only source-side gate for cross-document moves. A destination must
## never publish imported tiles before the source proves that its native
## raster ownership can be retired. No lazy provider is called by this gate.
## Keep this paired with remove_subtree's unrecorded retirement checks.
func preflight_unrecorded_subtree_removal(node_id: String) -> DrawingResult:
	if not can_remove_subtree(node_id):
		return DrawingResult.failure("LAYER", "Missing, root or inaccessible layer")
	var rasters: Array[String] = []
	_subtree_raster_ids(node_id, rasters)
	if _native_raster_store == null or rasters.is_empty():
		return DrawingResult.success(null, revision)
	if not _attached_native_revision_matches(revision):
		return DrawingResult.failure("STALE_REVISION", "Native source revision diverged before transfer")
	var ids: Array[String] = []
	_gather_ids(node_id, ids)
	var nodes: Dictionary = {}
	for identifier: String in ids:
		nodes[identifier] = _nodes[identifier]
	if not _native_tree_sources_match(nodes, false):
		return DrawingResult.failure("STALE_SOURCE", "Native subtree bytes differ before transfer")
	if not bool(_native_raster_store.call("can_retire_layers_revision",
			revision, PackedStringArray(rasters))):
		return DrawingResult.failure("NATIVE_STRUCTURE", "Native source retirement refused before transfer")
	return DrawingResult.success(null, revision)


func remove_subtree(node_id: String, record_history: bool = false) -> DrawingResult:
	if not can_remove_subtree(node_id):
		return DrawingResult.failure("LAYER", "Missing, root or inaccessible layer")
	# The local editor cannot delete locked/hidden descendants indirectly via
	# an editable ancestor. Legacy API callers keep their historical semantics.
	var ids: Array[String] = []
	if record_history and not external_history:
		_gather_ids(node_id, ids)
		for identifier: String in ids:
			if not _editable(identifier):
				return DrawingResult.failure("LOCKED", "Subtree contains a locked or hidden row")
	# Preserve full RGBA8 and unresolved lazy references for structural undo.
	# Only the removed subtree is copied; other raster layers are never cloned.
	var before: Dictionary = {}
	if record_history and not external_history:
		var snapshots: Dictionary = {}
		var pending: Dictionary = {}
		var known: Dictionary = {}
		var dirty: Dictionary = {}
		for identifier: String in ids:
			snapshots[identifier] = _nodes[identifier].detached_copy()
		for key: String in _pending_tiles:
			if ids.has(key.get_slice(":", 0)):
				pending[key] = _pending_tiles[key].duplicate(true)
		for key: String in _known_refs:
			if ids.has(key.get_slice(":", 0)):
				known[key] = _known_refs[key].duplicate(true)
		for key: String in _dirty_tiles:
			if ids.has(key.get_slice(":", 0)):
				dirty[key] = _dirty_tiles[key]
		var parent_id: String = _nodes[node_id].parent_id
		before = {"kind": "structure", "op": "remove", "id": node_id,
			"parent": parent_id, "index": _nodes[parent_id].children.find(node_id),
			"nodes": snapshots, "pending": pending, "known": known, "dirty": dirty}
	# Even a raster-bearing tree is metadata-only *to Rust* if none of its
	# raster layers was ever imported or retained in native history. Otherwise
	# preserve the conservative rebase boundary.
	var raster_layers: Array[String] = []
	_subtree_raster_ids(node_id, raster_layers)
	var resident_nodes: Dictionary = {}
	if _native_raster_store != null and not raster_layers.is_empty():
		# An attached Rust store must authorize the deletion before the Godot
		# tree changes. A rejected park/retire may not degrade into a silent
		# revision-only edit that strands canonical tiles and Undo tokens.
		if not _attached_native_revision_matches(revision):
			return DrawingResult.failure("STALE_REVISION", "Native raster revision diverged before removal")
		var resident_ids: Array[String] = []
		_gather_ids(node_id, resident_ids)
		for identifier: String in resident_ids:
			resident_nodes[identifier] = _nodes[identifier]
		if not _native_tree_sources_match(resident_nodes, false):
			return DrawingResult.failure("STALE_SOURCE", "Native raster subtree source changed")
	var parked: bool = false
	if not raster_layers.is_empty() and record_history and not external_history:
		parked = _advance_parked_structure_revision(raster_layers, false, true)
	if parked:
		before["native_parked"] = true
	var retired: bool = false
	var removed_ids: Array[String] = []
	var retained_history: Dictionary = {}
	if not parked and not raster_layers.is_empty() and (not record_history or external_history):
		# External/transfer callers do not create a reversible tree event.
		# Verify canonical source before permanently retiring these IDs.
		_gather_ids(node_id, removed_ids)
		if _native_raster_store != null:
			retained_history = _prepare_retired_local_history(removed_ids)
		retired = _retire_unrecorded_raster_layers(raster_layers, resident_nodes)
	# Semantic-only subtree deletion must acquire Rust metadata authority
	# before erasing even one Godot node. The old post-mutation bridge could
	# detach a busy/stale native store while leaving the local tree deleted.
	var metadata_advanced: bool = false
	if raster_layers.is_empty() and _native_raster_store != null:
		var advanced: DrawingResult = _advance_checked_layer_metadata()
		if not advanced.ok:
			return advanced
		metadata_advanced = true
	var unreferenced: bool = false
	if not raster_layers.is_empty() and _native_raster_store != null and not parked and not retired:
		# A never-authorized raster may be removed without parking any bytes,
		# but Rust must prove it has neither source nor history references.
		# This is the last fallible step before deterministic Godot erasure.
		unreferenced = bool(_native_raster_store.call("advance_unreferenced_layers_revision",
			revision, PackedStringArray(raster_layers), true))
		if not unreferenced:
			return DrawingResult.failure("NATIVE_STRUCTURE", "Native raster subtree removal rejected")
		revision += 1
	_erase_subtree(node_id)
	if retired and not retained_history.is_empty():
		_events = retained_history["events"]
		_content_states = retained_history["states"]
		_cursor = int(retained_history["cursor"])
	if parked or retired or unreferenced or metadata_advanced:
		pass # Rust and document revisions advanced before the deterministic erase.
	elif not raster_layers.is_empty():
		_advance_raster_structure_revision(raster_layers)
	else:
		_advance_nonraster_revision()
	_finish_structure(record_history, before)
	return DrawingResult.success(null, revision)


func _subtree_raster_ids(node_id: String, output: Array[String]) -> void:
	if _nodes[node_id].kind == DrawingLayerNode.RASTER:
		output.append(node_id)
	for child_id: String in _nodes[node_id].children:
		_subtree_raster_ids(child_id, output)


func _erase_subtree(node_id: String) -> void:
	var node: DrawingLayerNode = _nodes[node_id]
	for child: String in node.children.duplicate():
		_erase_subtree(child)
	_nodes[node.parent_id].children.erase(node_id)
	_nodes.erase(node_id)
	for suffix: String in _pending_tiles.keys():
		if suffix.begins_with(node_id + ":"):
			_pending_tiles.erase(suffix)
	for suffix: String in _known_refs.keys():
		if suffix.begins_with(node_id + ":"):
			_known_refs.erase(suffix)
	for suffix: String in _dirty_tiles.keys():
		if suffix.begins_with(node_id + ":"):
			_dirty_tiles.erase(suffix)


func set_density(numerator: int, denominator: int) -> DrawingResult:
	if numerator <= 0 or denominator <= 0:
		return DrawingResult.failure("DENSITY", "Density requires positive rational factors")
	if _content_committed and (numerator != density_numerator or denominator != density_denominator):
		return DrawingResult.failure("RESAMPLE_REQUIRED", "Density is frozen after the first content commit")
	if numerator != density_numerator or denominator != density_denominator:
		var advanced: DrawingResult = _advance_checked_layer_metadata()
		if not advanced.ok:
			return advanced
		density_numerator = numerator
		density_denominator = denominator
		_mark_untracked_change()
	return DrawingResult.success(null, revision)


func begin_edit(layer_id: String, expected_revision: int,
		view_transform: Transform2D = Transform2D.IDENTITY,
		anchor_x: int = 0, anchor_y: int = 0) -> DrawingResult:
	if expected_revision != revision:
		return DrawingResult.failure("STALE_REVISION", "Document revision changed before gesture")
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.RASTER:
		return DrawingResult.failure("LAYER", "Target is not a raster layer")
	if not _editable(layer_id):
		return DrawingResult.failure("LOCKED", "Layer or ancestor is hidden or locked")
	if not view_transform.x.is_finite() or not view_transform.y.is_finite() or not view_transform.origin.is_finite():
		return DrawingResult.failure("TRANSFORM", "Gesture transform is not finite")
	if not TILES.document_anchor_in_range(anchor_x, anchor_y):
		return DrawingResult.failure("COORD_RANGE", "Signed pixel anchor is outside safe 64-bit bounds")
	if not is_finite(view_transform.determinant()) or absf(view_transform.determinant()) < 0.00000001:
		return DrawingResult.failure("TRANSFORM", "Gesture transform is not invertible")
	return DrawingResult.success(DrawingEditSession.new(self, layer_id, revision,
		view_transform, anchor_x, anchor_y), revision)


func read_pixel(layer_id: String, x: int, y: int) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.RASTER:
		return DrawingResult.failure("LAYER", "Target is not a raster layer")
	var tile_key: String = TILES.tile_key64(x, y, tile_stride)
	var tile_result: DrawingResult = _resolve_chunk(layer_id, tile_key)
	if not tile_result.ok:
		return tile_result
	var tile: DrawingRasterTile = _nodes[layer_id].tiles.get(tile_key)
	if tile == null:
		return DrawingResult.success(0, revision)
	var point: Vector2i = TILES.local_offset64(x, y, tile_stride)
	return DrawingResult.success(tile.get_rgba(point.x, point.y), revision)


func has_stored_pixel(layer_id: String, x: int, y: int) -> bool:
	if not _nodes.has(layer_id):
		return false
	var key: String = TILES.tile_key64(x, y, tile_stride)
	var tile: DrawingRasterTile = _nodes[layer_id].tiles.get(key)
	if tile == null:
		return false
	var point: Vector2i = TILES.local_offset64(x, y, tile_stride)
	return tile.get_rgba(point.x, point.y) != 0


## Every public request returns an independent copy, never an owned mutable tile.
func request_chunk(layer_id: String, key: String) -> DrawingResult:
	var resolved: DrawingResult = _resolve_chunk(layer_id, key)
	if not resolved.ok:
		return resolved
	var tile: DrawingRasterTile = resolved.value as DrawingRasterTile
	return DrawingResult.success(tile.detached_copy() if tile != null else null, revision)


func request_chunk_at(layer_id: String, cx: int, cy: int) -> DrawingResult:
	return request_chunk(layer_id, "%d,%d" % [cx, cy])


func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.RASTER:
		return DrawingResult.failure("LAYER", "Missing raster layer")
	var lookup: String = layer_id + ":" + key
	if _pending_tiles.has(lookup):
		if _resolving_chunks.has(lookup):
			return DrawingResult.failure("SOURCE_BUSY", "Recursive lazy chunk resolution " + lookup)
		var pending: Dictionary = _pending_tiles[lookup]
		var provider: Callable = pending["fetch"] as Callable
		if not provider.is_valid():
			return DrawingResult.failure("MISSING_TILE", "No provider for referenced chunk " + lookup)
		# A loader is arbitrary external code. It can mutate the document, swap
		# the pending reference, or remove/recreate the layer before returning.
		# Capture its authority before entering the callback; never install a
		# decoded tile from an obsolete pending reference.
		var source_node: DrawingLayerNode = _nodes[layer_id]
		var source_revision: int = revision
		var source_epoch: int = display_source_epoch
		var source_ref: Variant = pending.get("ref")
		var source_digest: Variant = pending.get("sha256")
		var known_ref: Dictionary = (_known_refs.get(lookup, {}) as Dictionary).duplicate(true)
		_resolving_chunks[lookup] = true
		var content: Variant = provider.call(source_ref)
		_resolving_chunks.erase(lookup)
		if revision != source_revision or display_source_epoch != source_epoch:
			return DrawingResult.failure("STALE_REVISION", "Lazy source changed document revision or epoch")
		if not _nodes.has(layer_id) or _nodes[layer_id] != source_node 				or not _pending_tiles.has(lookup) or _nodes[layer_id].tiles.has(key):
			return DrawingResult.failure("STALE_SOURCE", "Lazy source layer or pending tile was replaced")
		var current: Dictionary = _pending_tiles[lookup]
		if current.get("ref") != source_ref or current.get("sha256") != source_digest 				or current.get("fetch") != provider or _known_refs.get(lookup) != known_ref:
			return DrawingResult.failure("STALE_SOURCE", "Lazy source reference changed during fetch")
		if not content is PackedByteArray:
			return DrawingResult.failure("MISSING_TILE", "Referenced chunk is missing " + lookup)
		var bytes: PackedByteArray = content
		if bytes.size() != tile_stride * tile_stride * 4 or DrawingRasterTile.digest_rgba8(bytes, tile_stride) != source_digest:
			return DrawingResult.failure("CORRUPT_TILE", "Referenced chunk is corrupt " + lookup)
		var decoded: DrawingRasterTile = DrawingRasterTile.from_rgba8(tile_stride, bytes)
		if decoded == null:
			return DrawingResult.failure("CORRUPT_TILE", "Invalid RGBA8 chunk " + lookup)
		_nodes[layer_id].tiles[key] = decoded
		_pending_tiles.erase(lookup)
	var resident: DrawingRasterTile = _nodes[layer_id].tiles.get(key)
	return DrawingResult.success(resident, revision)


func register_lazy_chunk(layer_id: String, cx: int, cy: int,
		blob_ref: String, canonical_sha256: String, loader: Callable) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.RASTER:
		return DrawingResult.failure("LAYER", "Missing raster layer")
	if canonical_sha256.length() != 64 or not canonical_sha256.is_valid_hex_number(false) or canonical_sha256 != canonical_sha256.to_lower():
		return DrawingResult.failure("DIGEST", "Expected lowercase 64-character SHA-256")
	if not TILES.tile_coordinates_in_projection_range(cx, cy, tile_stride):
		return DrawingResult.failure("COORD_RANGE", "Lazy tile is outside safe signed projection bounds")
	var key: String = "%d,%d" % [cx, cy]
	if _nodes[layer_id].tiles.has(key) or _pending_tiles.has(layer_id + ":" + key):
		return DrawingResult.failure("DUPLICATE_TILE", "Chunk already registered")
	_pending_tiles[layer_id + ":" + key] = {"ref": blob_ref, "sha256": canonical_sha256, "fetch": loader}
	_known_refs[layer_id + ":" + key] = {"ref": blob_ref, "sha256": canonical_sha256}
	display_source_epoch += 1
	_content_committed = true
	return DrawingResult.success(null, revision)


func tile_keys(layer_id: String) -> Array[String]:
	if not _nodes.has(layer_id):
		return []
	var keys: Array[String] = _nodes[layer_id].tiles.keys()
	for joined: String in _pending_tiles:
		if joined.begins_with(layer_id + ":"):
			keys.append(joined.substr(layer_id.length() + 1))
	keys.sort()
	return keys


## Conservative constant-work source-footprint check for display-tile renders.
## A missing resident/pending chunk cannot contribute a pixel. Large regions,
## invalid layers and unknown shapes fall back to rendering (never false-cull).
## This probes metadata only: lazy data and its integrity are still validated
## by _resolve_chunk() when a stored source overlaps the requested rectangle.
func raster_may_cover(layer_id: String, left: int, top: int,
		width: int, height: int) -> bool:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.RASTER \
			or width <= 0 or height <= 0:
		return true
	var first_x: int = TILES.floor_div(left, tile_stride)
	var first_y: int = TILES.floor_div(top, tile_stride)
	var last_x: int = TILES.floor_div(left + width - 1, tile_stride)
	var last_y: int = TILES.floor_div(top + height - 1, tile_stride)
	const MAX_FOOTPRINT_CHECKS: int = 16
	var horizontal: int = last_x - first_x + 1
	var vertical: int = last_y - first_y + 1
	if horizontal <= 0 or vertical <= 0 or horizontal > MAX_FOOTPRINT_CHECKS \
			or vertical > MAX_FOOTPRINT_CHECKS \
			or horizontal * vertical > MAX_FOOTPRINT_CHECKS:
		return true
	var resident: Dictionary = _nodes[layer_id].tiles
	var prefix: String = layer_id + ":"
	for cy: int in range(first_y, last_y + 1):
		for cx: int in range(first_x, last_x + 1):
			var key: String = "%d,%d" % [cx, cy]
			if resident.has(key) or _pending_tiles.has(prefix + key):
				return true
	return false


## Native Hokusai and ordinary Brush-only sessions already stage by signed
## storage tile and integer local offset. Retain those coordinates through publication; history
## still receives the exact canonical before/after pixel maps. No live tile or
## revision changes until every source and patch is validated. Mixed edit APIs
## continue through _publish_edit() and its independent source-pixel oracle.
func _publish_tile_edit(layer_id: String, expected: int,
		patches: Dictionary[String, Dictionary],
		session_sources: Dictionary[String, Variant],
		record_history: bool = true) -> DrawingResult:
	if revision != expected:
		return DrawingResult.failure("STALE_REVISION", "Concurrent edit invalidated the gesture")
	if not _attached_native_revision_matches(expected):
		return DrawingResult.failure("STALE_REVISION", "Attached native raster revision diverged")
	if not _nodes.has(layer_id) or not _editable(layer_id):
		return DrawingResult.failure("LOCKED", "Edited layer became unavailable")
	if patches.is_empty():
		return DrawingResult.failure("NO_CHANGE", "Gesture made no content changes")
	# Fail before resolving a single pending/lazy source or copying full tiles.
	var native_tile_publisher: bool = _native_raster_store != null \
		or ClassDB.class_exists("DrawingNativeTiles")
	if native_tile_publisher and not _native_direct_transfer_within_budget(patches.size()):
		return DrawingResult.failure("NATIVE_TILES", "Direct tile edit exceeds native transfer budget")

	# Validate and freeze the *entire* tile-local descriptor set before any
	# lazy source callback. Otherwise an invalid later patch can run an earlier
	# provider, and a reentrant provider can change the patch we eventually
	# publish without changing the document revision.
	var validated_patches: Dictionary[String, Dictionary] = {}
	var validated_sources: Dictionary[String, Variant] = {}
	# Sessions may hold verified but unchanged sources besides patched tiles.
	# Preserve those entries while still detecting reentrant map mutations.
	var frozen_session_sources: Dictionary[String, Variant] = session_sources.duplicate()
	for tile_key: String in patches:
		var components: PackedStringArray = tile_key.split(",")
		if components.size() != 2 or not components[0].is_valid_int() \
				or not components[1].is_valid_int():
			return DrawingResult.failure("COORD", "Invalid storage tile coordinate")
		var tile_x: int = int(components[0])
		var tile_y: int = int(components[1])
		if tile_key != "%d,%d" % [tile_x, tile_y]:
			return DrawingResult.failure("COORD", "Noncanonical storage tile coordinate")
		if native_tile_publisher \
				and not TILES.tile_coordinates_in_projection_range(tile_x, tile_y, tile_stride):
			return DrawingResult.failure("COORD", "Storage tile outside safe signed projection bounds")
		if not session_sources.has(tile_key):
			return DrawingResult.failure("STALE_PIXEL", "Gesture lacks its verified source tile")
		var patch: Dictionary = patches[tile_key]
		for local_index: int in patch:
			if local_index < 0 or local_index >= tile_stride * tile_stride:
				return DrawingResult.failure("COORD", "Invalid storage tile offset")
			var replacement: int = int(patch[local_index])
			if replacement < 0 or replacement > 0xffffffff:
				return DrawingResult.failure("RGBA", "Invalid storage tile RGBA8")
		validated_patches[tile_key] = patch.duplicate(true)
		validated_sources[tile_key] = session_sources[tile_key]

	var detached: Dictionary[String, DrawingRasterTile] = {}
	var bounds: Dictionary[String, Array] = {}
	var before: Dictionary[String, int] = {}
	var after: Dictionary[String, int] = {}
	var source_digests: Dictionary[String, String] = {}
	for tile_key: String in validated_patches:
		var components: PackedStringArray = tile_key.split(",")
		var tile_x: int = int(components[0])
		var tile_y: int = int(components[1])
		var resolved: DrawingResult = _resolve_chunk(layer_id, tile_key)
		if not resolved.ok:
			return resolved
		var original: DrawingRasterTile = resolved.value as DrawingRasterTile
		if original != validated_sources[tile_key]:
			return DrawingResult.failure("STALE_PIXEL", "Source tile changed during gesture")
		var source_pixels: Dictionary[int, int] = {}
		if original != null:
			source_pixels = original.sparse_pixels()
			# Only retain a canonical SHA-256 fingerprint. Holding a second
			# sparse Dictionary per tile could exceed the transfer budget for
			# many dense tiles, even though the RGBA8 envelope is bounded.
			source_digests[tile_key] = DrawingRasterTile.digest_rgba8(
				original.to_rgba8(), tile_stride)
		var patch: Dictionary = validated_patches[tile_key]
		var has_zero_replacements: bool = false
		for local_index: int in patch:
			var replacement: int = int(patch[local_index])
			var local_x: int = local_index % tile_stride
			var local_y: int = local_index / tile_stride
			var x: int = tile_x * tile_stride + local_x
			var y: int = tile_y * tile_stride + local_y
			var pixel_key: String = "%d,%d" % [x, y]
			var old: int = int(source_pixels.get(local_index, 0))
			if replacement == old:
				return DrawingResult.failure("STALE_PIXEL", "Native patch contains an unchanged pixel")
			before[pixel_key] = old
			after[pixel_key] = replacement
			if replacement == 0:
				has_zero_replacements = true
			if not bounds.has(tile_key):
				bounds[tile_key] = [x, y, x, y]
			else:
				var rect: Array = bounds[tile_key]
				rect[0] = mini(int(rect[0]), x)
				rect[1] = mini(int(rect[1]), y)
				rect[2] = maxi(int(rect[2]), x)
				rect[3] = maxi(int(rect[3]), y)
		if not patch.is_empty():
			var candidate: DrawingRasterTile = original.detached_copy() if original != null \
				else DrawingRasterTile.new(tile_stride)
			if not has_zero_replacements:
				candidate.sparse_pixels().merge(patch, true)
			else:
				for local_index: int in patch:
					var replacement: int = int(patch[local_index])
					if replacement == 0:
						candidate.sparse_pixels().erase(local_index)
					else:
						candidate.sparse_pixels()[local_index] = replacement
			detached[tile_key] = candidate
	if after.is_empty():
		return DrawingResult.failure("NO_CHANGE", "Gesture made no content changes")
	# The only reentrant boundary above is source resolution. A provider may
	# change input maps or modify an already-authorized tile *in place*, which
	# preserves its identity. Revalidate both before Rust commits any bytes.
	if patches.size() != validated_patches.size() \
			or session_sources != frozen_session_sources:
		return DrawingResult.failure("STALE_PIXEL", "Tile patch descriptors changed during preflight")
	for tile_key: String in validated_patches:
		if not patches.has(tile_key) or patches[tile_key] != validated_patches[tile_key] \
				or not session_sources.has(tile_key) \
				or session_sources[tile_key] != validated_sources[tile_key]:
			return DrawingResult.failure("STALE_PIXEL", "Tile patch descriptors changed during preflight")
		var source: DrawingRasterTile = validated_sources[tile_key] as DrawingRasterTile
		if source != null and (not source_digests.has(tile_key) \
				or DrawingRasterTile.digest_rgba8(
					source.to_rgba8(), tile_stride) != source_digests[tile_key]):
			return DrawingResult.failure("STALE_PIXEL", "Tile source bytes changed during preflight")
	return _install_prepared_edit(layer_id, expected, before, after,
		detached, bounds, record_history, true, validated_sources, true, true)


## Publish detached whole-tile snapshots from a native brush transaction.
## This preparatory document seam never constructs per-pixel String history
## maps. Callers must preflight the Rust transaction before committing it;
## all validation and allocation here finish before any document mutation.
func _publish_native_tile_edit(layer_id: String, expected: int,
		native_revision: int, images: Dictionary[String, PackedByteArray],
		sources: Dictionary[String, Variant], bounds: Dictionary[String, Rect2i],
		record_history: bool = true, dry_run: bool = false,
		history_token: int = 0) -> DrawingResult:
	if revision != expected or native_revision != expected + 1:
		return DrawingResult.failure("STALE_REVISION", "Native and document revisions disagree")
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.RASTER \
			or not _editable(layer_id):
		return DrawingResult.failure("LOCKED", "Edited raster layer became unavailable")
	if images.is_empty() or bounds.size() != images.size() \
			or not _native_direct_transfer_within_budget(images.size()):
		return DrawingResult.failure("NATIVE_TILES", "Native tile publication exceeds transfer bounds")
	# Validate and freeze *every* caller-owned descriptor before resolving a
	# lazy source. A later malformed tile must not execute an earlier source's
	# callback; a reentrant callback must not replace a validated RGBA8 buffer.
	var validated_images: Dictionary[String, PackedByteArray] = {}
	var validated_bounds: Dictionary[String, Rect2i] = {}
	var validated_sources: Dictionary[String, Variant] = {}
	for key: String in images:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() \
				or not parts[1].is_valid_int():
			return DrawingResult.failure("COORD", "Invalid native tile key")
		var tx: int = int(parts[0])
		var ty: int = int(parts[1])
		if key != "%d,%d" % [tx, ty] \
				or not TILES.tile_coordinates_in_projection_range(tx, ty, tile_stride):
			return DrawingResult.failure("COORD", "Native tile coordinate outside safe bounds")
		if not sources.has(key) or not bounds.has(key):
			return DrawingResult.failure("STALE_PIXEL", "Native tile lacks verified source or dirty bounds")
		var dirty: Rect2i = bounds[key]
		if not dirty.has_area() or dirty.position.x < 0 or dirty.position.y < 0 \
				or dirty.end.x > tile_stride or dirty.end.y > tile_stride:
			return DrawingResult.failure("COORD", "Native tile dirty bounds invalid")
		var bytes: PackedByteArray = images[key]
		if bytes.size() != tile_stride * tile_stride * 4:
			return DrawingResult.failure("RGBA", "Native RGBA8 tile length mismatch")
		validated_images[key] = bytes.duplicate()
		validated_bounds[key] = dirty
		validated_sources[key] = sources[key]
	var prepared: Dictionary[String, DrawingRasterTile] = {}
	var before_bytes: Dictionary[String, PackedByteArray] = {}
	var after_bytes: Dictionary[String, PackedByteArray] = {}
	var regions: Array[DrawingDirtyRegion] = []
	for key: String in validated_images:
		var components: PackedStringArray = key.split(",")
		var cx: int = int(components[0])
		var cy: int = int(components[1])
		var dirty: Rect2i = validated_bounds[key]
		var resolved: DrawingResult = _resolve_chunk(layer_id, key)
		if not resolved.ok:
			return resolved
		var original: DrawingRasterTile = resolved.value as DrawingRasterTile
		if original != validated_sources[key]:
			return DrawingResult.failure("STALE_PIXEL", "Native source identity changed")
		var bytes: PackedByteArray = validated_images[key]
		var candidate: DrawingRasterTile = DrawingRasterTile.from_rgba8(tile_stride, bytes)
		var previous: PackedByteArray = original.to_rgba8() if original != null \
			else PackedByteArray()
		if previous == bytes:
			return DrawingResult.failure("NATIVE_TILES", "Native dirty tile did not change")
		before_bytes[key] = previous
		after_bytes[key] = candidate.to_rgba8()
		prepared[key] = candidate
		regions.append(DrawingDirtyRegion.new(layer_id,
			cx * tile_stride + dirty.position.x, cy * tile_stride + dirty.position.y,
			dirty.size.x, dirty.size.y))
	# A lazy provider may reenter *during* the preflight loop. Revalidate all
	# sources and the authority stamp without invoking another provider: this
	# is the last point at which a full rejection can leave Rust untouched.
	if revision != expected or not _nodes.has(layer_id) or not _editable(layer_id):
		return DrawingResult.failure("STALE_REVISION", "Preflight source changed document authority")
	if images.size() != validated_images.size() or bounds.size() != validated_bounds.size() \
			or sources.size() != validated_sources.size():
		return DrawingResult.failure("STALE_PIXEL", "Native publication inputs changed during preflight")
	for key: String in prepared:
		if not images.has(key) or images[key] != validated_images[key] \
				or not bounds.has(key) or bounds[key] != validated_bounds[key] \
				or not sources.has(key) or sources[key] != validated_sources[key] \
				or _pending_tiles.has(layer_id + ":" + key) \
				or _nodes[layer_id].tiles.get(key) != validated_sources[key]:
			return DrawingResult.failure("STALE_PIXEL", "Native publication source or descriptor changed")
		# A later source callback may mutate an earlier tile in place while
		# preserving object identity and document revision. The previously
		# snapshotted original must still match before the Rust commit.
		var resident: DrawingRasterTile = _nodes[layer_id].tiles.get(key)
		var resident_bytes: PackedByteArray = resident.to_rgba8() if resident != null \
			else PackedByteArray()
		if resident_bytes != before_bytes[key]:
			return DrawingResult.failure("STALE_PIXEL", "Native publication source bytes changed")
	var result: DrawingResult = DrawingResult.success(null, native_revision)
	result.regions = regions
	result.delta = DrawingDelta.from_owned_tile_bytes(layer_id, tile_stride,
		before_bytes, after_bytes)
	# Preflight constructs every future raster tile without mutating source.
	# The paired Rust commit must not be followed by another lazy provider
	# callback: reentrant source/permission changes could otherwise reject the
	# *document* half after the native history has already been committed.
	result.value = {"prepared": prepared, "document_id": id,
		"layer_id": layer_id, "expected": expected, "native_revision": native_revision}
	if dry_run:
		return result
	return _install_prepared_native_tile_edit(layer_id, expected, native_revision,
		result, record_history, history_token)


## This only installs a previously verified, detached preflight result; it
## invokes no providers and makes no further Godot-to-Rust painting calls.
func _install_prepared_native_tile_edit(layer_id: String, expected: int,
		native_revision: int, checked: DrawingResult,
		record_history: bool = true, history_token: int = 0) -> DrawingResult:
	if checked == null or not checked.ok or checked.delta == null \
			or revision != expected or native_revision != expected + 1 \
			or not _nodes.has(layer_id) or not _editable(layer_id):
		return DrawingResult.failure("STALE_REVISION", "Preflighted native edit lost its authority")
	var bundle: Dictionary = checked.value as Dictionary
	if bundle.is_empty() or bundle.get("document_id", "") != id \
			or bundle.get("layer_id", "") != layer_id \
			or int(bundle.get("expected", -1)) != expected \
			or int(bundle.get("native_revision", -1)) != native_revision:
		return DrawingResult.failure("NATIVE_TILES", "Native preflight result belongs to another edit")
	var prepared: Dictionary = bundle["prepared"]
	if prepared.is_empty():
		return DrawingResult.failure("NATIVE_TILES", "Native preflight has no changed tiles")
	for key: String in prepared:
		var candidate: DrawingRasterTile = prepared[key]
		if candidate.is_empty():
			_nodes[layer_id].tiles.erase(key)
		else:
			_nodes[layer_id].tiles[key] = candidate
		_dirty_tiles[layer_id + ":" + key] = true
		_known_refs.erase(layer_id + ":" + key)
		if _native_raster_store != null \
				and int(_native_raster_store.call("stats").get("revision", -1)) == native_revision:
			_remember_native_source(layer_id, key, _nodes[layer_id].tiles.get(key))
	revision = native_revision
	_content_committed = true
	checked.delta.native_history_token = history_token
	if record_history:
		if external_history:
			_mark_untracked_change()
		else:
			_append_event({"kind": "content", "delta": checked.delta}, true)
	_display_changes.append({"revision": revision, "regions": checked.regions.duplicate()})
	if _display_changes.size() > DISPLAY_CHANGE_LIMIT:
		_display_changes.pop_front()
	checked.value = null
	return checked


## Replay a native tile delta as one atomic history operation. No sparse
## pixel maps are materialized; each source is verified before replacement.
func _replay_native_tile_delta(delta: DrawingDelta, undo_action: bool) -> DrawingResult:
	if delta.tile_stride != tile_stride or not _nodes.has(delta.layer_id) \
			or not _editable(delta.layer_id):
		return DrawingResult.failure("HISTORY_TARGET", "Native history target unavailable")
	var expected: Dictionary[String, PackedByteArray] = delta.after_tiles \
		if undo_action else delta.before_tiles
	var replacement: Dictionary[String, PackedByteArray] = delta.before_tiles \
		if undo_action else delta.after_tiles
	if expected.is_empty() or expected.size() != replacement.size() or expected.size() > 128:
		return DrawingResult.failure("HISTORY_TARGET", "Invalid native history tile count")
	# Reject an oversized history envelope *before* lazy source resolution and
	# whole-tile snapshots. The same conservative bound applies in the Rust ABI.
	if expected.size() * tile_stride * tile_stride * 4 * 3 > MAX_NATIVE_HISTORY_TRANSFER_BYTES:
		return DrawingResult.failure("HISTORY_TARGET", "Native history exceeds tile memory budget")
	# Validate and detach the whole history payload before resolving any lazy
	# source. Otherwise a bad later tile can invoke an earlier provider, or a
	# provider can rewrite a later buffer before it is snapshotted.
	var source_layer: String = delta.layer_id
	var source_stride: int = delta.tile_stride
	var source_token: int = delta.native_history_token
	var frozen_keys: Array[String] = replacement.keys()
	var original_bytes: Dictionary[String, PackedByteArray] = {}
	var replacement_bytes: Dictionary[String, PackedByteArray] = {}
	var coordinates_by_key: Dictionary[String, Vector2i] = {}
	var full_length: int = tile_stride * tile_stride * 4
	for key: String in frozen_keys:
		if not expected.has(key):
			return DrawingResult.failure("HISTORY_TARGET", "Native history snapshot missing")
		var coordinates: PackedStringArray = key.split(",")
		if coordinates.size() != 2 or not coordinates[0].is_valid_int() \
				or not coordinates[1].is_valid_int():
			return DrawingResult.failure("COORD", "Invalid native history key")
		var cx: int = int(coordinates[0])
		var cy: int = int(coordinates[1])
		if key != "%d,%d" % [cx, cy] \
				or not TILES.tile_coordinates_in_projection_range(cx, cy, tile_stride):
			return DrawingResult.failure("COORD", "Native history tile outside safe bounds")
		var before: PackedByteArray = expected[key].duplicate()
		var after: PackedByteArray = replacement[key].duplicate()
		if (not before.is_empty() and before.size() != full_length) \
				or (not after.is_empty() and after.size() != full_length):
			return DrawingResult.failure("RGBA", "Native history buffer malformed")
		original_bytes[key] = before
		replacement_bytes[key] = after
		coordinates_by_key[key] = Vector2i(cx, cy)
	# Fail before any lazy provider is invoked. Even a byte-identical out-of-
	# order replay must not invalidate newer retained native history entries.
	if source_token > 0 and _native_raster_store != null \
			and _attached_native_revision_matches(revision) \
			and not _native_raster_store.call("has_history_token", source_token,
				revision, undo_action) \
			and _native_raster_store.call("has_retained_history_token", source_token):
		return DrawingResult.failure("HISTORY_ORDER", "Native history token is retained out of order")
	var base_revision: int = revision
	var source_node: DrawingLayerNode = _nodes[source_layer]
	var detached: Dictionary[String, DrawingRasterTile] = {}
	var sources: Dictionary[String, Variant] = {}
	var regions: Array[DrawingDirtyRegion] = []
	for key: String in frozen_keys:
		var before: PackedByteArray = original_bytes[key]
		var after: PackedByteArray = replacement_bytes[key]
		var resolved: DrawingResult = _resolve_chunk(source_layer, key)
		if not resolved.ok:
			return resolved
		if revision != base_revision or not _nodes.has(source_layer) \
				or not is_same(_nodes[source_layer], source_node) \
				or not _editable(source_layer):
			return DrawingResult.failure("STALE_REVISION", "History source changed during lazy load")
		var source: DrawingRasterTile = resolved.value as DrawingRasterTile
		var source_bytes: PackedByteArray = source.to_rgba8() if source != null \
			else PackedByteArray()
		if source_bytes != before and not (source_bytes.is_empty() and \
				before.count(0) == before.size()):
			return DrawingResult.failure("STALE_PIXEL", "Native history source differs")
		sources[key] = source
		if not after.is_empty():
			detached[key] = DrawingRasterTile.from_rgba8(tile_stride, after)
		var tile: Vector2i = coordinates_by_key[key]
		regions.append(DrawingDirtyRegion.new(source_layer,
			tile.x * tile_stride, tile.y * tile_stride, tile_stride, tile_stride))
	# All lazy callbacks have returned. Recheck the full source set before
	# consuming an irreversible Rust history token or installing any tiles.
	if revision != base_revision or not _nodes.has(source_layer) \
			or not is_same(_nodes[source_layer], source_node) \
			or not _editable(source_layer):
		return DrawingResult.failure("STALE_REVISION", "History replay lost document authority")
	# Compare the *live* delta fields, not only the aliases retained above.
	# The owner may replace a dictionary or change its layer/stride/token from
	# inside a lazy callback, even when the frozen tile buffers remain valid.
	var live_expected: Dictionary[String, PackedByteArray] = delta.after_tiles \
		if undo_action else delta.before_tiles
	var live_replacement: Dictionary[String, PackedByteArray] = delta.before_tiles \
		if undo_action else delta.after_tiles
	if delta.layer_id != source_layer or delta.tile_stride != source_stride \
			or delta.native_history_token != source_token \
			or live_expected.size() != original_bytes.size() \
			or live_replacement.size() != replacement_bytes.size():
		return DrawingResult.failure("STALE_PIXEL", "History descriptor changed during source loading")
	for key: String in sources:
		if _pending_tiles.has(source_layer + ":" + key) \
				or not is_same(_nodes[source_layer].tiles.get(key), sources[key]) \
				or not live_expected.has(key) or not live_replacement.has(key) \
				or live_expected[key] != original_bytes[key] \
				or live_replacement[key] != replacement_bytes[key]:
			return DrawingResult.failure("STALE_PIXEL", "History source identity or snapshot changed")
		var resident: DrawingRasterTile = _nodes[source_layer].tiles.get(key)
		var current: PackedByteArray = resident.to_rgba8() if resident != null \
			else PackedByteArray()
		var before: PackedByteArray = original_bytes[key]
		if current != before and not (current.is_empty() and \
				before.count(0) == before.size()):
			return DrawingResult.failure("STALE_PIXEL", "History source bytes changed during preflight")
	# All lazy source callbacks are finished. Replay must always happen in
	# Rust, including after loading a document or rebasing a stale store.
	# Prepare a provisional store for absent/stale authority: importing only
	# these preflighted source tiles is bounded and cannot mutate the attached
	# store or document if native validation later rejects the transaction.
	var native_tiles: Array[Dictionary] = []
	for key: String in original_bytes:
		var coords: PackedStringArray = key.split(",")
		native_tiles.append({"tile_x": int(coords[0]), "tile_y": int(coords[1]),
			"expected": original_bytes[key], "replacement": replacement_bytes[key]})
	var attached_revision: int = int(_native_raster_store.call("stats").get(
		"revision", -1)) if _native_raster_store != null else -1
	# An attached store ahead of the document may own a newer transaction;
	# never replace it with an older detached snapshot during recovery.
	if attached_revision > base_revision:
		return DrawingResult.failure("STALE_REVISION", "Native history is ahead of document")
	var current_store: bool = attached_revision == base_revision
	var replay_store: Object = _native_raster_store if current_store else null
	if replay_store == null:
		if not ClassDB.class_exists("DrawingNativeTiles"):
			return DrawingResult.failure("NATIVE_HISTORY", "Native tile store unavailable")
		replay_store = ClassDB.instantiate("DrawingNativeTiles")
		if replay_store == null or int(replay_store.call("tile_abi_version")) != 1 \
				or not replay_store.call("configure", tile_stride, base_revision):
			return DrawingResult.failure("NATIVE_HISTORY", "Native history bootstrap rejected")
		for key: String in original_bytes:
			var coords: PackedStringArray = key.split(",")
			if not replay_store.call("import_source", delta.layer_id,
					int(coords[0]), int(coords[1]), base_revision, original_bytes[key]):
				return DrawingResult.failure("NATIVE_HISTORY", "Native history source import rejected")
	if not replay_store.call("set_layer_editable", delta.layer_id, true):
		return DrawingResult.failure("NATIVE_HISTORY", "Detached replay layer rejected")
	var live_token: bool = current_store and source_token > 0 and \
		replay_store.call("has_history_token", source_token,
			base_revision, undo_action)
	# Detached replay invalidates Rust Undo/Redo. A retained token that is not
	# the next event belongs to the live timeline and must fail without a
	# fallback, even when the requested tiles are disjoint from newer edits.
	if current_store and source_token > 0 and not live_token \
			and replay_store.call("has_retained_history_token", source_token):
		return DrawingResult.failure("HISTORY_ORDER", "Native history token is retained out of order")
	var native_replay: Dictionary
	if live_token:
		native_replay = replay_store.call("replay_history_token",
			delta.native_history_token, base_revision, undo_action,
			delta.layer_id, native_tiles)
	else:
		native_replay = replay_store.call("replay_detached_history",
			delta.layer_id, base_revision, native_tiles)
	if not bool(native_replay.get("ok", false)) \
			or int(native_replay.get("revision", -1)) != base_revision + 1:
		return DrawingResult.failure("NATIVE_HISTORY",
			str(native_replay.get("error", "Native history replay rejected")))
	# Success makes Rust authoritative before installing prepared Godot tiles.
	# A rebuilt store has no authority for unrelated old identities; their
	# sources will be imported on demand by the next native gesture.
	if not current_store:
		_native_raster_store = replay_store
		_native_source_identities.clear()
	for key: String in replacement_bytes:
		if detached.has(key) and not detached[key].is_empty():
			_nodes[delta.layer_id].tiles[key] = detached[key]
		else:
			_nodes[delta.layer_id].tiles.erase(key)
		_dirty_tiles[delta.layer_id + ":" + key] = true
		_known_refs.erase(delta.layer_id + ":" + key)
		if _native_raster_store != null and int(_native_raster_store.call("stats").get("revision", -1)) == base_revision + 1:
			_remember_native_source(delta.layer_id, key, _nodes[delta.layer_id].tiles.get(key))
	revision = base_revision + 1
	_content_committed = true
	_display_changes.append({"revision": revision, "regions": regions.duplicate()})
	if _display_changes.size() > DISPLAY_CHANGE_LIMIT:
		_display_changes.pop_front()
	var result: DrawingResult = DrawingResult.success(null, revision)
	result.regions = regions
	return result


## Read and compare originals before publication, then detach only touched tiles.
func _publish_edit(layer_id: String, expected: int,
		before: Dictionary[String, int], after: Dictionary[String, int],
		record_history: bool = true, track_unrecorded: bool = true) -> DrawingResult:
	if revision != expected:
		return DrawingResult.failure("STALE_REVISION", "Concurrent edit invalidated the gesture")
	if not _attached_native_revision_matches(expected):
		return DrawingResult.failure("STALE_REVISION", "Attached native raster revision diverged")
	if not _nodes.has(layer_id) or not _editable(layer_id):
		return DrawingResult.failure("LOCKED", "Edited layer became unavailable")
	if after.is_empty():
		return DrawingResult.failure("NO_CHANGE", "Gesture made no content changes")
	# Validate and freeze the complete pixel-map request before any lazy source
	# callback. In particular, a malformed *later* original/replacement cannot
	# run an earlier provider, and reentrant providers cannot change the staged
	# values or the eventual history delta without changing document revision.
	var native_pixel_publisher: bool = _native_raster_store != null \
		or (tile_stride >= 16 and tile_stride <= 2048 \
		and ClassDB.class_exists("DrawingNativeTiles"))
	var frozen_before: Dictionary[String, int] = before.duplicate()
	var frozen_after: Dictionary[String, int] = after.duplicate()
	var touched: Dictionary[String, bool] = {}
	for coordinate: String in frozen_after:
		var parts: PackedStringArray = coordinate.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() \
				or not parts[1].is_valid_int():
			return DrawingResult.failure("COORD", "Invalid pixel coordinate")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		if coordinate != TILES.pixel_key64(x, y) \
				or (native_pixel_publisher \
				and not TILES.pixel_coordinates_in_projection_range(x, y)):
			return DrawingResult.failure("COORD", "Invalid signed native pixel coordinate")
		if not frozen_before.has(coordinate):
			return DrawingResult.failure("STALE_PIXEL", "Gesture lacks original pixel")
		if frozen_before[coordinate] < 0 or frozen_before[coordinate] > 0xffffffff \
				or frozen_after[coordinate] < 0 or frozen_after[coordinate] > 0xffffffff:
			return DrawingResult.failure("RGBA", "Invalid pixel-map RGBA8 value")
		if native_pixel_publisher:
			touched[TILES.tile_key64(x, y, tile_stride)] = true
			if not _native_direct_transfer_within_budget(touched.size()):
				return DrawingResult.failure("NATIVE_TILES", "Direct pixel edit exceeds native transfer budget")

	var detached: Dictionary[String, DrawingRasterTile] = {}
	var bounds: Dictionary[String, Array] = {}
	var sources: Dictionary[String, Variant] = {}
	var source_digests: Dictionary[String, String] = {}
	# Resolve each tile only once. Fingerprint canonical source bytes as soon
	# as they are verified: object identity alone cannot detect in-place changes
	# made to an earlier tile by a later provider.
	for coordinate: String in frozen_after:
		var components: PackedStringArray = coordinate.split(",")
		var x: int = int(components[0])
		var y: int = int(components[1])
		var tile_key: String = TILES.tile_key64(x, y, tile_stride)
		if not sources.has(tile_key):
			var resolved: DrawingResult = _resolve_chunk(layer_id, tile_key)
			if not resolved.ok:
				return resolved
			sources[tile_key] = resolved.value
			var source: DrawingRasterTile = resolved.value as DrawingRasterTile
			if source != null:
				source_digests[tile_key] = DrawingRasterTile.digest_rgba8(
					source.to_rgba8(), tile_stride)
		var existing: DrawingRasterTile = sources[tile_key] as DrawingRasterTile
		var point: Vector2i = TILES.local_offset64(x, y, tile_stride)
		var original: int = existing.get_rgba(point.x, point.y) if existing != null else 0
		if original != frozen_before[coordinate]:
			return DrawingResult.failure("STALE_PIXEL", "Source pixel changed during gesture")
		if not detached.has(tile_key):
			detached[tile_key] = existing.detached_copy() if existing != null else DrawingRasterTile.new(tile_stride)
		detached[tile_key].set_rgba(point.x, point.y, frozen_after[coordinate])
		if not bounds.has(tile_key):
			bounds[tile_key] = [x, y, x, y]
		else:
			var rect: Array = bounds[tile_key]
			rect[0] = mini(int(rect[0]), x)
			rect[1] = mini(int(rect[1]), y)
			rect[2] = maxi(int(rect[2]), x)
			rect[3] = maxi(int(rect[3]), y)

	if before != frozen_before or after != frozen_after:
		return DrawingResult.failure("STALE_PIXEL", "Pixel-map inputs changed during preflight")
	for tile_key: String in source_digests:
		var source: DrawingRasterTile = sources[tile_key] as DrawingRasterTile
		if DrawingRasterTile.digest_rgba8(source.to_rgba8(), tile_stride) != source_digests[tile_key]:
			return DrawingResult.failure("STALE_PIXEL", "Tile source bytes changed during preflight")
	return _install_prepared_edit(layer_id, expected, frozen_before, frozen_after,
		detached, bounds, record_history, false, sources, track_unrecorded,
		native_pixel_publisher)


## Shared atomic installation, history and dirty-region publication for both
## global-pixel and native tile-local edit preparation paths.
func _install_prepared_edit(layer_id: String, expected: int,
		before: Dictionary[String, int], after: Dictionary[String, int],
		detached: Dictionary[String, DrawingRasterTile],
		bounds: Dictionary[String, Array], record_history: bool,
		owned_history_maps: bool = false,
		sources: Dictionary[String, Variant] = {},
		track_unrecorded: bool = true,
		bootstrap_native: bool = false) -> DrawingResult:
	# All source resolution must have finished before the native commit. Do not
	# call a lazy provider after Rust accepts an external tile transaction.
	if revision != expected or not _nodes.has(layer_id) or not _editable(layer_id) \
			or not _attached_native_revision_matches(expected):
		return DrawingResult.failure("STALE_REVISION", "Concurrent edit invalidated native raster authority")
	for key: String in detached:
		if not sources.has(key) or _pending_tiles.has(layer_id + ":" + key) \
				or _nodes[layer_id].tiles.get(key) != sources[key]:
			return DrawingResult.failure("STALE_PIXEL", "External raster source identity changed")
	var result: DrawingResult = DrawingResult.success(null, expected + 1)
	for key: String in detached:
		var rect: Array = bounds[key]
		result.regions.append(DrawingDirtyRegion.new(layer_id, int(rect[0]), int(rect[1]),
			int(rect[2]) - int(rect[0]) + 1, int(rect[3]) - int(rect[1]) + 1))
	# Once Rust owns this document, even a non-historical direct raster edit
	# must advance its canonical tiles in the same revision. Untracked edits
	# invalidate native Undo tokens; they never invent a history event.
	# First tile-local edits may attach a provisional native owner. It is never
	# published to the document unless the Rust adoption succeeds; failed
	# imports or edits leave canonical authority and history unchanged. Both
	# direct pixel-map and tile-local publishers acquire Rust on first use.
	var native_store: Object = _native_raster_store
	var provisional_store: bool = false
	if native_store == null and bootstrap_native and ClassDB.class_exists("DrawingNativeTiles"):
		native_store = ClassDB.instantiate("DrawingNativeTiles")
		if native_store == null or int(native_store.call("tile_abi_version")) != 1 \
				or not native_store.call("configure", tile_stride, expected):
			return DrawingResult.failure("NATIVE_TILES", "Native tile bootstrap rejected")
		provisional_store = true
	var adopt: bool = native_store != null
	var originals: Dictionary[String, PackedByteArray] = {}
	var replacements: Dictionary[String, PackedByteArray] = {}
	var descriptors: Array[Dictionary] = []
	if adopt:
		if not _native_direct_transfer_within_budget(detached.size()):
			return DrawingResult.failure("NATIVE_TILES", "External raster transaction exceeds native transfer budget")
		for key: String in detached:
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
					or key != "%d,%d" % [int(parts[0]), int(parts[1])]:
				return DrawingResult.failure("COORD", "Invalid native external tile key")
			var source: DrawingRasterTile = sources[key] as DrawingRasterTile
			var has_native: bool = bool(native_store.call("has_source", layer_id,
				int(parts[0]), int(parts[1]), expected))
			if has_native and not provisional_store \
					and not _native_source_matches(layer_id, key, source):
				return DrawingResult.failure("STALE_PIXEL", "External tile lost native source identity")
			var from_bytes: PackedByteArray = source.to_rgba8() if source != null else PackedByteArray()
			var to_bytes: PackedByteArray = detached[key].to_rgba8()
			originals[key] = from_bytes
			replacements[key] = to_bytes
			descriptors.append({"tile_x": int(parts[0]), "tile_y": int(parts[1]),
				"before": from_bytes, "after": to_bytes})
		# Construct the reversible document envelope before Rust commits.
		# After its commit there must be no provider call or allocation-dependent
		# validation that could reject the paired Godot projection.
		result.delta = DrawingDelta.from_owned_tile_bytes(layer_id, tile_stride,
			originals, replacements)
		if not native_store.call("set_layer_editable", layer_id, true):
			return DrawingResult.failure("NATIVE_TILES", "Native raster layer rejected")
		if provisional_store:
			# A previously loaded or unmodified tile already has source bytes in
			# Godot. The fresh Rust store must authorize those *exact* originals
			# before adopting their replacements; no live store is mutated here.
			for descriptor: Dictionary in descriptors:
				if not native_store.call("import_source", layer_id,
						int(descriptor["tile_x"]), int(descriptor["tile_y"]),
						expected, descriptor["before"]):
					return DrawingResult.failure("NATIVE_TILES", "Native bootstrap source rejected")
		# The call is failure-atomic on the Rust side. The document projection
		# then installs only detached tiles, with no fallible source lookups.
		var native_method: String = "adopt_external_edit" if record_history else "adopt_untracked_edit"
		var accepted: Dictionary = native_store.call(native_method,
			layer_id, expected, descriptors)
		if not bool(accepted.get("ok", false)) or int(accepted.get("revision", -1)) != expected + 1:
			return DrawingResult.failure("NATIVE_TILES", str(accepted.get("error", "Native adoption failed")))
		if record_history:
			result.delta.native_history_token = int(accepted.get("history_token", 0))
		if provisional_store:
			_native_raster_store = native_store
			_native_source_identities.clear()
	else:
		result.delta = DrawingDelta.from_owned_maps(layer_id, before, after) if owned_history_maps \
			else DrawingDelta.new(layer_id, before, after)
	for key: String in detached:
		if detached[key].is_empty():
			_nodes[layer_id].tiles.erase(key)
		else:
			_nodes[layer_id].tiles[key] = detached[key]
		_dirty_tiles[layer_id + ":" + key] = true
		_known_refs.erase(layer_id + ":" + key)
		if adopt:
			_remember_native_source(layer_id, key, _nodes[layer_id].tiles.get(key))
	revision += 1
	_content_committed = true
	if record_history:
		if external_history:
			_mark_untracked_change()
		else:
			_append_event({"kind": "content", "delta": result.delta}, true)
	elif track_unrecorded:
		# A new no-history raster edit is still unsaved document content and
		# must invalidate a branched Redo timeline. Detached Undo/Redo replay
		# passes track_unrecorded=false to retain the existing history cursor.
		_mark_untracked_change()
	_display_changes.append({"revision": revision, "regions": result.regions.duplicate()})
	if _display_changes.size() > DISPLAY_CHANGE_LIMIT:
		_display_changes.pop_front()
	return result


## Cached views consume monotonic changes without touching persistence state.
## Any untracked revision (including text, layer structure or visibility)
## invalidates all cached composites; dirty save tiles are not a change log.
func display_changes_since(old_revision: int) -> Dictionary:
	if old_revision == revision:
		return {"full": false, "regions": []}
	if old_revision < 0 or old_revision > revision:
		return {"full": true, "regions": []}
	var next_revision: int = old_revision + 1
	var regions: Array[DrawingDirtyRegion] = []
	for record: Dictionary in _display_changes:
		var changed_revision: int = int(record["revision"])
		if changed_revision < next_revision:
			continue
		if changed_revision != next_revision:
			return {"full": true, "regions": []}
		regions.append_array(record["regions"] as Array[DrawingDirtyRegion])
		next_revision += 1
	if next_revision != revision + 1:
		return {"full": true, "regions": []}
	return {"full": false, "regions": regions}


## A host must select external ownership *before* it begins committing edits.
## Switching a document with existing local entries would silently split history.
func set_external_history(enabled: bool) -> DrawingResult:
	if enabled != external_history and not _events.is_empty():
		return DrawingResult.failure("HISTORY_OWNED", "Cannot migrate an existing local history implicitly")
	external_history = enabled
	return DrawingResult.success()


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _events.size()


func history_length() -> int:
	return _events.size()


## Public, bounded, read-only history description for the shared editor shell.
## Never return event dictionaries: these hold mutable tile deltas and snapshots.
func history_position() -> int:
	return _cursor


func history_summaries(start: int = 0, count: int = 128) -> Array[String]:
	var summaries: Array[String] = []
	for index: int in range(clampi(start, 0, _events.size()),
		mini(_events.size(), maxi(0, start) + clampi(count, 0, 256))):
		var event: Dictionary = _events[index]
		var kind: String = String(event.get("kind", ""))
		var label: String = "Edit"
		if kind == "selection":
			label = "Selection"
		elif kind == "content":
			label = "Raster edit · " + _history_node_name((event["delta"] as DrawingDelta).layer_id)
		elif kind == "text_tree":
			label = "Text edit · " + _history_node_name(String(event["layer"]))
		elif kind == "structure":
			var op: String = String(event.get("op", ""))
			var node_name: String = _history_node_name(String(event.get("id", "")))
			if op == "create":
				node_name = (event["node"] as DrawingLayerNode).name
			elif op == "remove":
				node_name = (event["nodes"][event["id"]] as DrawingLayerNode).name
			if op == "property":
				var field: String = String(event.get("field", ""))
				label = ("Rename" if field == "name" else "Visibility" if field == "visible"
					else "Lock" if field == "locked" else "Change") + " · " + node_name
			else:
				label = {"create": "Add", "remove": "Remove", "reorder": "Move"}.get(op, "Change") + " · " + node_name
		summaries.append(label)
	return summaries


func _history_node_name(node_id: String) -> String:
	if _nodes.has(node_id):
		return (_nodes[node_id] as DrawingLayerNode).name
	return node_id.left(24) if not node_id.is_empty() else "layer"


## Structural operations are opt-in for local editor history. Legacy/Atlas API
## callers keep their original untracked/external ownership semantics.
func _finish_structure(record_history: bool, event: Dictionary) -> void:
	if record_history and not external_history:
		_append_event(event, true)
	else:
		_mark_untracked_change()


## Structural replay is failure-atomic: all preconditions are checked before
## modifying the tree. Content events are undone first in chronological order.
func _replay_structure(event: Dictionary, undo_action: bool) -> DrawingResult:
	var parked_replay: bool = false
	var metadata_advanced: bool = false
	var raster_advanced: bool = false
	var node_id: String = event["id"]
	var op: String = event["op"]
	if op == "property":
		if not _nodes.has(node_id):
			return DrawingResult.failure("HISTORY_TARGET", "Structural node disappeared")
		var field: String = event["field"]
		var expected: Variant = event["after"] if undo_action else event["before"]
		var target: Variant = event["before"] if undo_action else event["after"]
		if _nodes[node_id].get(field) != expected:
			return DrawingResult.failure("HISTORY_TARGET", "Structural property diverged")
		# History replay must acquire Rust's metadata revision before touching
		# the node, without invalidating the native redo timeline.
		var metadata: DrawingResult = _advance_checked_layer_metadata(false)
		if not metadata.ok:
			return metadata
		metadata_advanced = true
		_nodes[node_id].set(field, target)
	elif op == "reorder":
		var source: String = event["new_parent"] if undo_action else event["old_parent"]
		var dest: String = event["old_parent"] if undo_action else event["new_parent"]
		var source_index: int = event["new_index"] if undo_action else event["old_index"]
		var dest_index: int = event["old_index"] if undo_action else event["new_index"]
		if not _nodes.has(node_id) or not _nodes.has(source) or not _nodes.has(dest) or \
			_nodes[node_id].parent_id != source or _nodes[source].children.find(node_id) != source_index:
			return DrawingResult.failure("HISTORY_TARGET", "Structural order diverged")
		var metadata: DrawingResult = _advance_checked_layer_metadata(false)
		if not metadata.ok:
			return metadata
		metadata_advanced = true
		_nodes[source].children.erase(node_id)
		_nodes[dest].children.insert(dest_index, node_id)
		_nodes[node_id].parent_id = dest
	elif op in ["create", "remove"]:
		var restore: bool = (op == "create") != undo_action
		var parent_id: String = event["parent"]
		if not _nodes.has(parent_id) or _nodes[parent_id].kind != DrawingLayerNode.GROUP:
			return DrawingResult.failure("HISTORY_TARGET", "Structural parent disappeared")
		var affected_raster: Array[String] = []
		if op == "remove":
			for snapshot: DrawingLayerNode in (event["nodes"] as Dictionary).values():
				if snapshot.kind == DrawingLayerNode.RASTER:
					affected_raster.append(snapshot.id)
		var restored: Dictionary = event["nodes"] if op == "remove" else {node_id: event["node"]}
		var raster_layers: Array[String] = affected_raster.duplicate()
		if op == "create" and (event["node"] as DrawingLayerNode).kind == DrawingLayerNode.RASTER:
			raster_layers.append(node_id)
		# All tree preconditions precede the Rust revision update; rejected
		# structural replays must leave both histories and trees unchanged.
		if restore:
			for identifier: String in restored:
				if _nodes.has(identifier):
					return DrawingResult.failure("HISTORY_TARGET", "Structural ID was reused")
		elif not _nodes.has(node_id) or _nodes[node_id].parent_id != parent_id or \
				_nodes[parent_id].children.find(node_id) != int(event["index"]):
			return DrawingResult.failure("HISTORY_TARGET", "Removed subtree diverged")
		# A semantic-only tree replay is another checked Rust revision boundary.
		# The detached nodes and parent slot are validated above, so a rejected
		# native transition cannot publish even a partial subtree.
		if affected_raster.is_empty() and (op != "create" or
				(event["node"] as DrawingLayerNode).kind != DrawingLayerNode.RASTER):
			var metadata: DrawingResult = _advance_checked_layer_metadata(false)
			if not metadata.ok:
				return metadata
			metadata_advanced = true
		# Raster-bearing replay must acquire the exact Rust revision *before*
		# touching Godot's hierarchy. A failed park/unpark or unreferenced-ID
		# bridge cannot degrade into an unchecked local-only history step.
		if not raster_layers.is_empty() and _native_raster_store != null:
			if not _attached_native_revision_matches(revision):
				return DrawingResult.failure("STALE_REVISION", "Raster history native revision diverged")
			if bool(event.get("native_parked", false)):
				if restore and not _native_tree_sources_match(restored, true):
					return DrawingResult.failure("STALE_PIXEL", "Structural snapshot differs from native source")
				if not restore:
					var live_nodes: Dictionary = {}
					for identifier: String in restored:
						live_nodes[identifier] = _nodes[identifier]
					if not _native_tree_sources_match(live_nodes, false):
						return DrawingResult.failure("STALE_PIXEL", "Structural source identity changed")
				if not _advance_parked_structure_revision(raster_layers, restore, false):
					return DrawingResult.failure("NATIVE_STRUCTURE", "Native parked raster history rejected")
				parked_replay = true
			else:
				if not bool(_native_raster_store.call("advance_unreferenced_layers_revision",
						revision, PackedStringArray(raster_layers), false)):
					return DrawingResult.failure("NATIVE_STRUCTURE", "Native unreferenced raster history rejected")
				revision += 1
			raster_advanced = true
		if restore:
			for identifier: String in restored:
				_nodes[identifier] = (restored[identifier] as DrawingLayerNode).detached_copy()
			_nodes[parent_id].children.insert(mini(int(event["index"]), _nodes[parent_id].children.size()), node_id)
			if parked_replay:
				for identity: String in _native_source_identities.keys():
					var owner: String = identity.get_slice(":", 0)
					if not restored.has(owner):
						continue
					var key: String = identity.substr(owner.length() + 1)
					_native_source_identities[identity] = _nodes[owner].tiles.get(key)
			if op == "remove":
				for key: String in event["pending"]:
					_pending_tiles[key] = event["pending"][key].duplicate(true)
				for key: String in event["known"]:
					_known_refs[key] = event["known"][key].duplicate(true)
				for key: String in event["dirty"]:
					_dirty_tiles[key] = event["dirty"][key]
		else:
			_erase_subtree(node_id)
	else:
		return DrawingResult.failure("HISTORY_KIND", "Unknown structural operation")
	# Metadata and raster-bearing paths already advanced Rust before the tree
	# change. Only native-absent raster history needs its local revision bump.
	if not metadata_advanced and not raster_advanced:
		_advance_nonraster_revision(false)
	return DrawingResult.success(null, revision)


func _mark_untracked_change() -> void:
	_untracked_revision += 1
	# Untracked changes invalidate future redo without changing prior undo steps.
	_drop_history_redo()


func _drop_history_redo() -> void:
	_events.resize(_cursor)
	_content_states.resize(_cursor + 1)


func _append_event(event: Dictionary, content_change: bool) -> void:
	_drop_history_redo()
	_events.append(event)
	_cursor += 1
	if content_change:
		_next_content_state += 1
		_content_states.append(_next_content_state)
	else:
		_content_states.append(_content_states[_cursor - 1])


## Attach UI context to exactly the just-committed gesture, never to a sample.
func annotate_latest_gesture(before: DrawingHistoryContext,
		after: DrawingHistoryContext) -> bool:
	if external_history or _cursor != _events.size() or _cursor == 0 			or _events[_cursor - 1]["kind"] not in ["content", "text_tree", "structure"] or before == null or after == null:
		return false
	_events[_cursor - 1]["context_before"] = before.detached_copy()
	_events[_cursor - 1]["context_after"] = after.detached_copy()
	return true


func record_selection_change(before: DrawingHistoryContext,
		after: DrawingHistoryContext) -> bool:
	if external_history or not record_selection_history or before == null or after == null 			or before.same_selection(after):
		return false
	_append_event({"kind": "selection", "before": before.detached_copy(),
		"after": after.detached_copy()}, false)
	return true


## Historical local/Atlas events may hold per-pixel deltas from before a
## native Brush attached its tile store. Convert those cold history entries
## into checked whole-tile replay once Rust owns the document revision;
## publishing only the Godot pixels would silently leave Rust one step behind.
func _replay_pixel_delta_native(delta: DrawingDelta, undo_action: bool) -> DrawingResult:
	if not _nodes.has(delta.layer_id) or not _editable(delta.layer_id):
		return DrawingResult.failure("HISTORY_TARGET", "Legacy history layer unavailable")
	var expected: Dictionary[String, int] = (delta.after if undo_action else delta.before).duplicate()
	var replacement: Dictionary[String, int] = (delta.before if undo_action else delta.after).duplicate()
	var source_layer: String = delta.layer_id
	if expected.is_empty() or expected.size() != replacement.size():
		return DrawingResult.failure("HISTORY_TARGET", "Invalid legacy pixel history")
	var grouped: Dictionary[String, Array] = {}
	# Bound the detached bytes prepared in Godot *before* entering Rust. Three
	# full spans per tile cover source, replacement and temporary native replay.
	var bytes_per_tile: int = tile_stride * tile_stride * 4
	var max_tiles: int = mini(128, MAX_NATIVE_HISTORY_TRANSFER_BYTES / (3 * bytes_per_tile))
	for coordinate: String in replacement:
		if not expected.has(coordinate):
			return DrawingResult.failure("HISTORY_TARGET", "Legacy pixel history is incomplete")
		var parts: PackedStringArray = coordinate.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return DrawingResult.failure("COORD", "Malformed legacy pixel coordinate")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		if coordinate != TILES.pixel_key64(x, y) \
				or not TILES.pixel_coordinates_in_projection_range(x, y):
			return DrawingResult.failure("COORD", "Unsafe legacy history coordinate")
		var tile_key: String = TILES.tile_key64(x, y, tile_stride)
		if not grouped.has(tile_key):
			if grouped.size() >= max_tiles:
				return DrawingResult.failure("HISTORY_TARGET", "Legacy history exceeds native tile budget")
			grouped[tile_key] = []
		var from_rgba: int = int(expected[coordinate])
		var to_rgba: int = int(replacement[coordinate])
		if from_rgba < 0 or from_rgba > 4294967295 \
				or to_rgba < 0 or to_rgba > 4294967295:
			return DrawingResult.failure("RGBA", "Legacy history has invalid RGBA8")
		var offset: Vector2i = TILES.local_offset64(x, y, tile_stride)
		grouped[tile_key].append([offset.y * tile_stride + offset.x, from_rgba, to_rgba])
	var originals: Dictionary[String, PackedByteArray] = {}
	var changed: Dictionary[String, PackedByteArray] = {}
	var base_revision: int = revision
	for key: String in grouped:
		var source: DrawingResult = _resolve_chunk(source_layer, key)
		if not source.ok:
			return source
		if revision != base_revision or not _nodes.has(source_layer) \
				or not _editable(source_layer):
			return DrawingResult.failure("STALE_REVISION", "History source changed during load")
		var tile: DrawingRasterTile = source.value as DrawingRasterTile
		var old_bytes: PackedByteArray = tile.to_rgba8() if tile != null else PackedByteArray()
		var updated: PackedByteArray = old_bytes.duplicate()
		if updated.is_empty():
			updated.resize(tile_stride * tile_stride * 4)
		for change: Array in grouped[key]:
			var offset: int = int(change[0]) * 4
			if updated.decode_u32(offset) != int(change[1]):
				return DrawingResult.failure("STALE_PIXEL", "Legacy history source RGBA8 differs")
			updated.encode_u32(offset, int(change[2]))
		originals[key] = old_bytes
		changed[key] = PackedByteArray() if updated.count(0) == updated.size() else updated
	if delta.layer_id != source_layer or delta.before != (replacement if undo_action else expected) \
			or delta.after != (expected if undo_action else replacement):
		return DrawingResult.failure("STALE_PIXEL", "Legacy history changed during source loading")
	# Canonical native replay resolves sources again, rechecking identities and
	# bytes after every lazy callback and inside the atomic Rust transaction.
	var native_delta: DrawingDelta = DrawingDelta.from_owned_tile_bytes(
		source_layer, tile_stride, originals, changed)
	return _replay_native_tile_delta(native_delta, false)


## Replays a detached delta without creating a second history entry.
## The caller must validate the stable document identity before invoking it.
func replay_delta(delta: DrawingDelta, undo_action: bool) -> DrawingResult:
	if delta == null:
		return DrawingResult.failure("DELTA", "Missing drawing delta")
	var result: DrawingResult
	if delta.tile_stride > 0:
		result = _replay_native_tile_delta(delta, undo_action)
	elif _native_raster_store != null or (tile_stride >= 16 and tile_stride <= 2048
			and ClassDB.class_exists("DrawingNativeTiles")):
		# Even a detached legacy/Atlas pixel event must acquire Rust ownership
		# when its storage stride is supported by the native tile ABI.
		# Otherwise it advances Godot alone and the next native gesture has to
		# invalidate the host timeline at a checked rebase boundary.
		result = _replay_pixel_delta_native(delta, undo_action)
	else:
		result = _publish_edit(delta.layer_id, revision,
			delta.after if undo_action else delta.before,
			delta.before if undo_action else delta.after, false, false)
	if result.ok and external_history:
		_mark_untracked_change()
	return result


func undo() -> DrawingResult:
	if not can_undo() or external_history:
		return DrawingResult.failure("EMPTY_HISTORY", "No locally owned undo step")
	var event: Dictionary = _events[_cursor - 1]
	var result: DrawingResult
	if event["kind"] == "content":
		result = replay_delta(event["delta"] as DrawingDelta, true)
	elif event["kind"] == "text_tree":
		result = _replay_text_tree(event, true)
	elif event["kind"] == "structure":
		result = _replay_structure(event, true)
	else:
		result = DrawingResult.success((event["before"] as DrawingHistoryContext).detached_copy(), revision)
	if result.ok:
		_cursor -= 1
		if event["kind"] in ["content", "text_tree", "structure"] and event.has("context_before"):
			result.value = (event["context_before"] as DrawingHistoryContext).detached_copy()
	return result


func redo() -> DrawingResult:
	if not can_redo() or external_history:
		return DrawingResult.failure("EMPTY_HISTORY", "No locally owned redo step")
	var event: Dictionary = _events[_cursor]
	var result: DrawingResult
	if event["kind"] == "content":
		result = replay_delta(event["delta"] as DrawingDelta, false)
	elif event["kind"] == "text_tree":
		result = _replay_text_tree(event, false)
	elif event["kind"] == "structure":
		result = _replay_structure(event, false)
	else:
		result = DrawingResult.success((event["after"] as DrawingHistoryContext).detached_copy(), revision)
	if result.ok:
		_cursor += 1
		if event["kind"] in ["content", "text_tree", "structure"] and event.has("context_after"):
			result.value = (event["context_after"] as DrawingHistoryContext).detached_copy()
	return result


func add_object(layer_id: String, data: Dictionary, requested_id: String = "") -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.OBJECTS or not _editable(layer_id):
		return DrawingResult.failure("LAYER", "Unavailable semantic-object layer")
	var object_id: String = requested_id if not requested_id.is_empty() else new_id()
	if _nodes[layer_id].objects.has(object_id):
		return DrawingResult.failure("DUPLICATE_ID", "Object ID already exists")
	var copied: Dictionary = data.duplicate(true)
	var advanced: DrawingResult = _advance_checked_layer_metadata()
	if not advanced.ok:
		return advanced
	_nodes[layer_id].objects[object_id] = copied
	_mark_untracked_change()
	_content_committed = true
	return DrawingResult.success(object_id, revision)


func move_object(layer_id: String, object_id: String, position: Vector2) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.OBJECTS or not _editable(layer_id):
		return DrawingResult.failure("LAYER", "Unavailable semantic-object layer")
	if not _nodes[layer_id].objects.has(object_id) or not position.is_finite():
		return DrawingResult.failure("OBJECT", "Missing object or invalid position")
	var updated: Dictionary = _nodes[layer_id].objects[object_id].duplicate(true)
	updated["position"] = position
	var advanced: DrawingResult = _advance_checked_layer_metadata()
	if not advanced.ok:
		return advanced
	_nodes[layer_id].objects[object_id] = updated
	_mark_untracked_change()
	return DrawingResult.success(null, revision)


## Text is committed as ONE semantic element. The first commit atomically creates
## the text layer and one undo event; opening/cancelling the UI never calls this.
func commit_text(layer_id: String, draft: DrawingTextElement,
		expected_revision: int, parent_id: String = ROOT_ID,
		requested_id: String = "") -> DrawingResult:
	if revision != expected_revision:
		return DrawingResult.failure("STALE_REVISION", "Text draft has a stale revision")
	if draft == null:
		return DrawingResult.failure("TEXT", "Missing text draft")
	var valid: DrawingResult = draft.validated()
	if not valid.ok:
		return valid
	var supported: DrawingResult = DrawingTextRaster.font_status(draft.font_id)
	if not supported.ok:
		return supported
	var created: bool = layer_id.is_empty()
	var node: DrawingLayerNode
	if created:
		if not _nodes.has(parent_id) or _nodes[parent_id].kind != DrawingLayerNode.GROUP or not _editable(parent_id):
			return DrawingResult.failure("PARENT", "Unavailable text group")
		layer_id = requested_id if not requested_id.is_empty() else new_id()
		if not valid_identifier(layer_id) or layer_id == ROOT_ID or _nodes.has(layer_id):
			return DrawingResult.failure("LAYER_ID", "Invalid or duplicate text layer identity")
		if _native_raster_store != null and bool(_native_raster_store.call(
				"is_layer_parked", layer_id)):
			return DrawingResult.failure("LAYER_ID", "Text ID is reserved by native structural history")
		node = DrawingLayerNode.new(layer_id, DrawingLayerNode.TEXT, "Text: " + draft.content.split("\n")[0].left(36), parent_id)
	else:
		if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.TEXT or not _editable(layer_id):
			return DrawingResult.failure("LAYER", "Unavailable text layer")
		node = _nodes[layer_id]
	var before: DrawingLayerNode = null if created else node.detached_copy()
	var after: DrawingLayerNode = node.detached_copy()
	after.text_element = draft.detached_copy()
	after.text_value = draft.content
	if not created and before.text_element != null and before.text_element.to_record() == draft.to_record():
		return DrawingResult.success(layer_id, revision)
	# The entire semantic tree projection is detached and validated. Acquire
	# the native metadata revision before touching live nodes or local history.
	var advanced: DrawingResult = _advance_checked_layer_metadata()
	if not advanced.ok:
		return advanced
	if created:
		_nodes[node.id] = after
		_nodes[parent_id].children.append(layer_id)
	else:
		_nodes[layer_id] = after
	_content_committed = true
	if external_history:
		_mark_untracked_change()
	else:
		_append_event({"kind": "text_tree", "layer": layer_id,
			"parent": after.parent_id, "index": _nodes[after.parent_id].children.find(layer_id),
			"before": before, "after": after.detached_copy()}, true)
	return DrawingResult.success(layer_id, revision)


## Compatibility entrypoint for existing semantic asset sources.
func set_text(layer_id: String, content: String) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.TEXT:
		return DrawingResult.failure("LAYER", "Unavailable text layer")
	var existing: DrawingTextElement = _nodes[layer_id].text_element
	var draft: DrawingTextElement = existing.detached_copy() if existing != null else DrawingTextElement.new()
	draft.content = content
	return commit_text(layer_id, draft, revision)


func rasterize_text(layer_id: String, expected_revision: int) -> DrawingResult:
	if revision != expected_revision:
		return DrawingResult.failure("STALE_REVISION", "Text changed before rasterization")
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.TEXT or not _editable(layer_id):
		return DrawingResult.failure("LAYER", "Unavailable editable text layer")
	var before: DrawingLayerNode = _nodes[layer_id].detached_copy()
	if before.text_element == null:
		return DrawingResult.failure("TEXT", "Text layer has no committed element")
	var measured: DrawingResult = DrawingTextRaster.bounds(before.text_element)
	if not measured.ok:
		return measured
	var area: Rect2i = measured.value
	if not area.has_area() or area.size.x > 1048576 or area.size.y > 1048576 / area.size.x:
		return DrawingResult.failure("RASTER_LIMIT", "Text exceeds the bounded rasterization budget")
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(area.size.x * area.size.y * 4)
	var rendered: DrawingResult = DrawingTextRaster.composite(before.text_element, area, bytes)
	if not rendered.ok:
		return rendered
	var after: DrawingLayerNode = before.detached_copy()
	after.kind = DrawingLayerNode.RASTER
	after.text_value = ""
	after.text_element = null
	for y: int in range(area.size.y):
		for x: int in range(area.size.x):
			var offset: int = (y * area.size.x + x) * 4
			if bytes[offset + 3] == 0:
				continue
			var world_x: int = area.position.x + x
			var world_y: int = area.position.y + y
			var tile_key: String = TILES.tile_key64(world_x, world_y, tile_stride)
			if not after.tiles.has(tile_key):
				after.tiles[tile_key] = DrawingRasterTile.new(tile_stride)
			var local: Vector2i = TILES.local_offset64(world_x, world_y, tile_stride)
			var rgba: int = 0
			for channel: int in range(4):
				rgba |= int(bytes[offset + channel]) << (channel * 8)
			after.tiles[tile_key].set_rgba(local.x, local.y, rgba)
	# A new semantic glyph source may reuse an ID that Rust parked when the
	# *previous* text-to-raster conversion was undone. Its old canonical tiles
	# and redo tokens no longer describe this source. Retire only that parked ID
	# at one checked native revision boundary; preserve all other raster tokens.
	# A current non-parked ID must still be provably unreferenced in Rust.
	if _native_raster_store != null:
		var native_revision: int = int(_native_raster_store.call("stats").get("revision", -1))
		if native_revision > revision:
			return DrawingResult.failure("STALE_REVISION", "Text conversion native store is ahead")
		if native_revision == revision:
			var ids: PackedStringArray = PackedStringArray([layer_id])
			if bool(_native_raster_store.call("is_layer_parked", layer_id)):
				if not bool(_native_raster_store.call(
						"replace_parked_layers_revision", revision, ids)):
					return DrawingResult.failure("NATIVE_STRUCTURE", "Parked text source could not be replaced")
				for identity: String in _native_source_identities.keys():
					if identity.begins_with(layer_id + ":"):
						_native_source_identities.erase(identity)
			else:
				if not bool(_native_raster_store.call(
						"advance_unreferenced_layers_revision", revision, ids, true)):
					return DrawingResult.failure("NATIVE_STRUCTURE", "Text ID has live native ownership")
			revision += 1
		else:
			# An already-behind store is reauthorized on the next native edit.
			_advance_raster_structure_revision([layer_id])
	else:
		_advance_raster_structure_revision([layer_id])
	_nodes[layer_id] = after
	for tile_key: String in after.tiles:
		_dirty_tiles[layer_id + ":" + tile_key] = true
		_known_refs.erase(layer_id + ":" + tile_key)
	if external_history:
		_mark_untracked_change()
	else:
		_append_event({"kind": "text_tree", "layer": layer_id,
			"parent": after.parent_id, "index": _nodes[after.parent_id].children.find(layer_id),
			"before": before, "after": after.detached_copy()}, true)
	return DrawingResult.success(layer_id, revision)


## Text-to-raster Undo/Redo can temporarily hide a layer that Rust already
## owns. Park its canonical source/history rather than invalidating every
## native token. Validate caller-owned tree snapshots before touching Rust;
## an unowned text layer still takes the no-source structural revision bridge.
func _replay_text_raster_native(layer_id: String, expected: DrawingLayerNode,
		target: DrawingLayerNode) -> DrawingResult:
	if _native_raster_store == null:
		return DrawingResult.success(false, revision)
	var native_revision: int = int(_native_raster_store.call("stats").get("revision", -1))
	if native_revision != revision:
		return DrawingResult.failure("STALE_REVISION", "Text history native revision diverged")
	var restore: bool = target.kind == DrawingLayerNode.RASTER
	var source_nodes: Dictionary = {layer_id: target if restore else _nodes[layer_id]}
	if not _native_tree_sources_match(source_nodes, restore):
		return DrawingResult.failure("STALE_PIXEL", "Text history native RGBA8 source diverged")
	var ids: PackedStringArray = PackedStringArray([layer_id])
	if _native_raster_store.call("advance_parked_layers_revision", revision,
			ids, restore, false):
		return DrawingResult.success(true, revision + 1)
	if _native_raster_store.call("advance_unreferenced_layers_revision", revision,
			ids, false):
		return DrawingResult.success(false, revision + 1)
	return DrawingResult.failure("NATIVE_STRUCTURE", "Text history native layer transition rejected")


func _replay_text_tree(event: Dictionary, undo_action: bool) -> DrawingResult:
	var target: DrawingLayerNode = event["before"] if undo_action else event["after"]
	var expected: DrawingLayerNode = event["after"] if undo_action else event["before"]
	var layer_id: String = event["layer"]
	var parent_id: String = event["parent"]
	if not _nodes.has(parent_id) or _nodes[parent_id].kind != DrawingLayerNode.GROUP:
		return DrawingResult.failure("HISTORY_TARGET", "Text group disappeared")
	if expected == null:
		if _nodes.has(layer_id):
			return DrawingResult.failure("HISTORY_TARGET", "Created text ID was reused")
	elif not _nodes.has(layer_id) or _nodes[layer_id].kind != expected.kind:
		return DrawingResult.failure("HISTORY_TARGET", "Text layer changed outside history")
	var kind_transition: bool = expected != null and target != null and \
		(expected.kind == DrawingLayerNode.RASTER) != (target.kind == DrawingLayerNode.RASTER)
	var native_bridged: bool = false
	var metadata_advanced: bool = false
	var parked: bool = false
	# Semantic-only text creation/edit replay must acquire Rust's revision
	# before modifying the Godot tree or history cursor. The previous
	# post-mutation bridge detached a busy/stale native store on rejection.
	var semantic_only: bool = (target == null or target.kind == DrawingLayerNode.TEXT) and \
		(expected == null or expected.kind == DrawingLayerNode.TEXT)
	if semantic_only:
		var metadata: DrawingResult = _advance_checked_layer_metadata(false)
		if not metadata.ok:
			return metadata
		metadata_advanced = true
	if kind_transition and _native_raster_store != null:
		var native_revision: int = int(_native_raster_store.call("stats").get("revision", -1))
		if native_revision > revision:
			return DrawingResult.failure("STALE_REVISION", "Text history native store is ahead")
		if native_revision == revision:
			var bridge: DrawingResult = _replay_text_raster_native(layer_id, expected, target)
			if not bridge.ok:
				return bridge
			native_bridged = true
			parked = bool(bridge.value)
		# Older previously-rebased consumers may already be behind the host
		# revision. They cannot preserve an obsolete native timeline; leave
		# that store untouched and let the normal checked rebase reauthorize it.
	if target == null:
		_nodes.erase(layer_id)
		_nodes[parent_id].children.erase(layer_id)
	else:
		_nodes[layer_id] = target.detached_copy()
		if expected == null:
			_nodes[parent_id].children.insert(mini(int(event["index"]), _nodes[parent_id].children.size()), layer_id)
	# A restored native source has new Godot tile object identities. Rebind only
	# after Rust accepted the exact snapshot, without any lazy provider calls.
	if native_bridged and parked and target.kind == DrawingLayerNode.RASTER:
		for identity: String in _native_source_identities.keys():
			if identity.begins_with(layer_id + ":"):
				var key: String = identity.substr(layer_id.length() + 1)
				_native_source_identities[identity] = _nodes[layer_id].tiles.get(key)
	# Rasterized tiles are invalidated when conversion is undone/redone.
	for key: String in _dirty_tiles.keys():
		if key.begins_with(layer_id + ":"):
			_dirty_tiles.erase(key)
	for key: String in _known_refs.keys():
		if key.begins_with(layer_id + ":"):
			_known_refs.erase(key)
	if target != null and target.kind == DrawingLayerNode.RASTER:
		for tile_key: String in target.tiles:
			_dirty_tiles[layer_id + ":" + tile_key] = true
	if native_bridged:
		revision += 1
	elif not metadata_advanced:
		_advance_raster_structure_revision([layer_id], false)
	return DrawingResult.success(null, revision)


## A detached subtree is another raster-publication boundary: Copy/Atlas
## consumers must not receive Godot projection bytes that Rust never owned.
## Check only the selected tree so unrelated non-selected raster state cannot
## make a valid Copy fail. No lazy provider or native transaction runs here.
func _preflight_native_subtree_export(ids: Array[String]) -> DrawingResult:
	if _native_raster_store == null:
		return DrawingResult.success(null, revision)
	if not _attached_native_revision_matches(revision):
		return DrawingResult.failure("STALE_REVISION", "Native raster revision diverged before export")
	var selected: Dictionary = {}
	for identifier: String in ids:
		selected[identifier] = _nodes[identifier]
	if not _native_tree_sources_match(selected, false):
		return DrawingResult.failure("STALE_SOURCE", "Native raster bytes differ before export")
	return DrawingResult.success(null, revision)


## Caller gets a detached hierarchical snapshot. Import cannot alias tile dictionaries.
func export_subtree(node_id: String) -> DrawingResult:
	if node_id == ROOT_ID or not _nodes.has(node_id):
		return DrawingResult.failure("LAYER", "Cannot export missing/root layer")
	# A detached transfer cannot drop unresolved tile references. Resolve or fail.
	var ids: Array[String] = []
	_gather_ids(node_id, ids)
	var initial_revision: int = revision
	var authorized: DrawingResult = _preflight_native_subtree_export(ids)
	if not authorized.ok:
		return authorized
	for child_id: String in ids:
		if _nodes[child_id].kind != DrawingLayerNode.RASTER:
			continue
		for tile_id: String in tile_keys(child_id):
			var loaded: DrawingResult = _resolve_chunk(child_id, tile_id)
			if not loaded.ok:
				return loaded
			if revision != initial_revision:
				return DrawingResult.failure("STALE_REVISION", "Subtree changed during lazy export")
	# A lazy provider may mutate resident bytes without advancing revision;
	# recheck full RGBA8 (including hidden RGB) before detaching the tree.
	authorized = _preflight_native_subtree_export(ids)
	if not authorized.ok:
		return authorized
	var exported: Dictionary[String, DrawingLayerNode] = {}
	_collect_subtree(node_id, exported)
	return DrawingResult.success({"root": node_id, "nodes": exported}, revision)


func _gather_ids(node_id: String, ids: Array[String]) -> void:
	ids.append(node_id)
	for child: String in _nodes[node_id].children:
		_gather_ids(child, ids)


func _collect_subtree(node_id: String, nodes: Dictionary[String, DrawingLayerNode]) -> void:
	var node: DrawingLayerNode = _nodes[node_id]
	nodes[node_id] = node.detached_copy()
	for child: String in node.children:
		_collect_subtree(child, nodes)


## Validate connectivity and forbid descendant cycles before mutating the target.
func _validate_snapshot_tree(node_id: String, nodes: Dictionary,
		visited: Dictionary[String, bool]) -> bool:
	if visited.has(node_id) or not nodes.has(node_id) or not nodes[node_id] is DrawingLayerNode:
		return false
	visited[node_id] = true
	var node: DrawingLayerNode = nodes[node_id]
	if node.id != node_id or (not node.children.is_empty() and node.kind != DrawingLayerNode.GROUP):
		return false
	for child: String in node.children:
		if not nodes.has(child) or not nodes[child] is DrawingLayerNode:
			return false
		if nodes[child].parent_id != node_id or not _validate_snapshot_tree(child, nodes, visited):
			return false
	return true


func import_subtree(snapshot: Dictionary, parent_id: String, preserve_ids: bool = false) -> DrawingResult:
	if not _nodes.has(parent_id) or _nodes[parent_id].kind != DrawingLayerNode.GROUP or not _editable(parent_id):
		return DrawingResult.failure("PARENT", "Missing or inaccessible destination group")
	var original_nodes: Variant = snapshot.get("nodes")
	var original_root: Variant = snapshot.get("root")
	if not original_nodes is Dictionary or not original_root is String:
		return DrawingResult.failure("SNAPSHOT", "Malformed detached subtree")
	var nodes: Dictionary = original_nodes
	if not nodes.has(original_root) or original_root == ROOT_ID:
		return DrawingResult.failure("SNAPSHOT", "Missing source root")
	var visited: Dictionary[String, bool] = {}
	if not _validate_snapshot_tree(String(original_root), nodes, visited) or visited.size() != nodes.size():
		return DrawingResult.failure("SNAPSHOT", "Detached subtree has a cycle or unreachable nodes")
	var mapping: Dictionary[String, String] = {}
	for old_id: Variant in nodes:
		if not old_id is String or not nodes[old_id] is DrawingLayerNode or not valid_identifier(String(old_id)):
			return DrawingResult.failure("SNAPSHOT", "Invalid detached node")
		var next_id: String = String(old_id) if preserve_ids else new_id()
		if _nodes.has(next_id):
			return DrawingResult.failure("DUPLICATE_ID", "Imported layer ID already exists")
		mapping[String(old_id)] = next_id
	for old_id: Variant in nodes:
		var source: DrawingLayerNode = nodes[old_id]
		if source.id != old_id:
			return DrawingResult.failure("SNAPSHOT", "Inconsistent detached node ID")
		for child: String in source.children:
			if not nodes.has(child) or nodes[child].parent_id != old_id:
				return DrawingResult.failure("SNAPSHOT", "Broken nested group reference")
	# Prepare the entire detached projection before publishing. A failed copy
	# must not install a partial group, advance either revision or leave a
	# half-populated dirty map. Native parked IDs are reserved even while the
	# corresponding Godot layer is absent from the live tree.
	var prepared: Dictionary[String, DrawingLayerNode] = {}
	var imported_rasters: Array[String] = []
	for old_id: Variant in nodes:
		var imported: DrawingLayerNode = (nodes[old_id] as DrawingLayerNode).detached_copy()
		imported.id = mapping[String(old_id)]
		if _native_raster_store != null and bool(_native_raster_store.call(
				"is_layer_parked", imported.id)):
			return DrawingResult.failure("DUPLICATE_ID", "Imported layer ID is reserved by native history")
		imported.parent_id = parent_id if old_id == original_root else mapping[imported.parent_id]
		if not preserve_ids and not imported.objects.is_empty():
			var distinct_objects: Dictionary[String, Dictionary] = {}
			for object_id: String in imported.objects:
				distinct_objects[new_id()] = imported.objects[object_id].duplicate(true)
			imported.objects = distinct_objects
		var mapped_children: Array[String] = []
		for child: String in imported.children:
			mapped_children.append(mapping[child])
		imported.children = mapped_children
		prepared[imported.id] = imported
		if imported.kind == DrawingLayerNode.RASTER:
			imported_rasters.append(imported.id)
	# Prepare the full tree before a checked, single-step native revision.
	# The previous raster import used a bare increment and forced a rebase even when
	# every imported raster layer was new to Rust. The checked bridge keeps
	# unrelated native Brush history and source authorizations alive.
	if imported_rasters.is_empty():
		# Semantic-only detached imports must obey the same fail-closed native
		# revision boundary as public object/text edits. The old post-mutation
		# bridge advanced Godot and dropped the Rust attachment on rejection.
		var metadata: DrawingResult = _advance_checked_layer_metadata()
		if not metadata.ok:
			return metadata
	else:
		# A rejected native bridge is not permission to publish a Godot-only
		# subtree. Keep the detached projection uninstalled and allow retry.
		# Every imported ID is new to this document, so Rust may advance only
		# after proving that none is resident, parked or referenced in history.
		if _native_raster_store != null:
			if not _attached_native_revision_matches(revision):
				return DrawingResult.failure("STALE_REVISION", "Native raster revision diverged before import")
			if not bool(_native_raster_store.call("advance_unreferenced_layers_revision",
					revision, PackedStringArray(imported_rasters), true)):
				return DrawingResult.failure("NATIVE_STRUCTURE", "Native raster import was rejected")
		revision += 1
	for identifier: String in prepared:
		var imported: DrawingLayerNode = prepared[identifier]
		_nodes[identifier] = imported
		for tile_key: String in imported.tiles:
			_dirty_tiles[identifier + ":" + tile_key] = true
	_nodes[parent_id].children.append(mapping[original_root])
	_mark_untracked_change()
	return DrawingResult.success(mapping[original_root], revision)


static func transfer_subtree(source: DrawingDocument, target: DrawingDocument,
		node_id: String, target_parent: String, source_revision: int,
		target_revision: int, move: bool = false) -> DrawingResult:
	if source == null or target == null or source == target:
		return DrawingResult.failure("TRANSFER", "Cross-document transfer needs distinct documents")
	if source.revision != source_revision or target.revision != target_revision:
		return DrawingResult.failure("STALE_REVISION", "Transfer revisions no longer match")
	if move and not source._editable(node_id):
		return DrawingResult.failure("LOCKED", "Source layer is hidden or locked")
	var exported: DrawingResult = source.export_subtree(node_id)
	if not exported.ok:
		return exported
	if source.revision != source_revision or target.revision != target_revision:
		return DrawingResult.failure("STALE_REVISION", "Transfer changed during source export")
	if move:
		var allowed: DrawingResult = source.preflight_unrecorded_subtree_removal(node_id)
		if not allowed.ok:
			return allowed
	var inserted: DrawingResult = target.import_subtree(exported.value, target_parent, move)
	if not inserted.ok:
		return inserted
	if move:
		var removed: DrawingResult = source.remove_subtree(node_id)
		if not removed.ok:
			var rolled_back: DrawingResult = target.remove_subtree(str(inserted.value))
			if not rolled_back.ok:
				return DrawingResult.failure("TRANSFER_ROLLBACK", "Source and destination require manual recovery")
			return removed
	return inserted


## Low-level dirty RGBA8 snapshot for save consumers. A snapshot is a
## publication boundary, not permission to trust mutable Godot projection
## bytes: require exact Rust source/revision authority before reading any
## source bytes or exposing the detached payload. No lazy providers run here.
func snapshot_for_save() -> DrawingResult:
	if not _native_save_projection_matches():
		return DrawingResult.failure("STALE_SOURCE", "Native raster source differs from save projection")
	var tree: Array[Dictionary] = []
	var ids: Array[String] = _nodes.keys()
	ids.sort()
	for node_id: String in ids:
		var node: DrawingLayerNode = _nodes[node_id]
		tree.append({"id": node.id, "parent": node.parent_id, "kind": node.kind,
			"name": node.name, "visible": node.visible, "locked": node.locked,
			"children": node.children.duplicate(), "tiles": tile_keys(node_id),
			"text": node.text_value, "text_element": node.text_element.to_record() if node.text_element != null else null,
			"objects": node.objects.duplicate(true)})
	var dirty: Dictionary[String, PackedByteArray] = {}
	var removed: Array[String] = []
	for combined: String in _dirty_tiles:
		var separator: int = combined.find(":")
		var node_id: String = combined.substr(0, separator)
		var tile_id: String = combined.substr(separator + 1)
		var tile: DrawingRasterTile = _nodes[node_id].tiles.get(tile_id)
		if tile != null:
			dirty[combined] = tile.to_rgba8()
		else:
			removed.append(combined)
	return DrawingResult.success({"id": id, "revision": revision, "stride": tile_stride,
		"density": [density_numerator, density_denominator], "tree": tree,
		"dirty_rgba8": dirty, "removed_tile_ids": removed}, revision)


func mark_published(saved_revision: int,
		published_refs: Dictionary[String, String] = {}) -> DrawingResult:
	if saved_revision != revision:
		return DrawingResult.failure("STALE_REVISION", "Cannot publish an older snapshot")
	if not _native_save_projection_matches():
		return DrawingResult.failure("STALE_SOURCE", "Native raster source differs from save projection")
	# A physical savepoint must resolve every newly written tile to a durable ref.
	for combined: String in _dirty_tiles:
		var separator: int = combined.find(":")
		var node_id: String = combined.substr(0, separator)
		var tile_key: String = combined.substr(separator + 1)
		if not _nodes.has(node_id):
			return DrawingResult.failure("LAYER", "Dirty tile belongs to missing layer")
		if _nodes[node_id].tiles.has(tile_key) and (not published_refs.has(combined) or published_refs[combined].is_empty()):
			return DrawingResult.failure("UNPUBLISHED_TILE", "No durable blob ref for " + combined)
	for combined: String in _dirty_tiles:
		var separator: int = combined.find(":")
		var node_id: String = combined.substr(0, separator)
		var tile_key: String = combined.substr(separator + 1)
		var tile: DrawingRasterTile = _nodes[node_id].tiles.get(tile_key)
		if tile == null:
			_known_refs.erase(combined)
		else:
			_known_refs[combined] = {"ref": published_refs[combined],
				"sha256": DrawingRasterTile.digest_rgba8(tile.to_rgba8(), tile_stride)}
	published_revision = revision
	_saved_content_state = _content_states[_cursor]
	_saved_untracked_revision = _untracked_revision
	_dirty_tiles.clear()
	return DrawingResult.success(null, revision)


## Logical, format-neutral manifest. T-066 owns the physical file/schema, codecs
## and atomic generation publication. A blank ref denotes a tile needing staging.
func export_manifest() -> DrawingResult:
	if not _native_save_projection_matches():
		return DrawingResult.failure("STALE_SOURCE", "Native raster source differs from save projection")
	var layers: Array[Dictionary] = []
	var ids: Array[String] = _nodes.keys()
	ids.sort()
	for layer_id: String in ids:
		var node: DrawingLayerNode = _nodes[layer_id]
		var descriptors: Array[Dictionary] = []
		for tile_key: String in tile_keys(layer_id):
			var coordinates: PackedStringArray = tile_key.split(",")
			if coordinates.size() != 2:
				return DrawingResult.failure("COORD", "Malformed tile key")
			var cx: int = int(coordinates[0])
			var cy: int = int(coordinates[1])
			if tile_key != "%d,%d" % [cx, cy]:
				return DrawingResult.failure("COORD", "Noncanonical tile key")
			if not TILES.tile_coordinates_in_projection_range(cx, cy, tile_stride):
				return DrawingResult.failure("COORD_RANGE", "Raster source outside safe signed projection bounds")
			var combined: String = layer_id + ":" + tile_key
			var descriptor: Dictionary = {}
			if _known_refs.has(combined) and not _dirty_tiles.has(combined):
				descriptor = _known_refs[combined].duplicate()
			else:
				var tile: DrawingRasterTile = node.tiles.get(tile_key)
				if tile == null:
					return DrawingResult.failure("MISSING_TILE", "Tile lacks data and a verified ref")
				descriptor = {"ref": "", "sha256": DrawingRasterTile.digest_rgba8(
						tile.to_rgba8(), tile_stride)}
			descriptors.append({"coord": [cx, cy], "ref": descriptor["ref"],
				"sha256": descriptor["sha256"]})
		layers.append({"id": node.id, "parent": node.parent_id, "kind": node.kind,
			"name": node.name, "visible": node.visible, "locked": node.locked,
			"children": node.children.duplicate(), "text": node.text_value,
			"text_element": node.text_element.to_record() if node.text_element != null else null,
			"objects": node.objects.duplicate(true), "chunks": descriptors})
	return DrawingResult.success({"logical_schema": "drawing-document-v1",
		"id": id, "revision": revision, "tile_stride": tile_stride,
		"density": [density_numerator, density_denominator], "layers": layers}, revision)


## Decode only metadata. Referenced bytes remain external until first read.
## Loader signature: Callable(blob_ref: String) -> PackedByteArray | null.
static func open_manifest(manifest: Dictionary, loader: Callable) -> DrawingResult:
	if manifest.get("logical_schema") != "drawing-document-v1":
		return DrawingResult.failure("SCHEMA", "Unknown logical Drawing manifest")
	var document_id: Variant = manifest.get("id")
	var size: Variant = manifest.get("tile_stride")
	var saved_revision: Variant = manifest.get("revision")
	var density: Variant = manifest.get("density")
	var layers: Variant = manifest.get("layers")
	if not document_id is String or not valid_identifier(document_id) or not size is int or not saved_revision is int:
		return DrawingResult.failure("MANIFEST", "Invalid document identity or numeric metadata")
	if size <= 0 or size > 2048 or saved_revision < 0 or not density is Array or density.size() != 2:
		return DrawingResult.failure("MANIFEST", "Invalid tile stride, revision or density")
	if not density[0] is int or not density[1] is int or density[0] <= 0 or density[1] <= 0:
		return DrawingResult.failure("MANIFEST", "Density factors must be positive integers")
	if not layers is Array or layers.is_empty():
		return DrawingResult.failure("MANIFEST", "No layer tree")
	var document: DrawingDocument = DrawingDocument.new(document_id, size, density[0], density[1])
	document._nodes.clear()
	var chunk_descriptors: Dictionary[String, Array] = {}
	for record: Variant in layers:
		if not record is Dictionary:
			return DrawingResult.failure("MANIFEST", "Malformed layer record")
		var node_id: Variant = record.get("id")
		var parent: Variant = record.get("parent")
		var kind: Variant = record.get("kind")
		var name: Variant = record.get("name")
		var children: Variant = record.get("children")
		if not node_id is String or not valid_identifier(node_id) or document._nodes.has(node_id):
			return DrawingResult.failure("DUPLICATE_ID", "Malformed/duplicate stable layer ID")
		if not parent is String or not name is String or not kind is String:
			return DrawingResult.failure("MANIFEST", "Layer metadata types are invalid")
		if kind not in [DrawingLayerNode.GROUP, DrawingLayerNode.RASTER,
				DrawingLayerNode.TEXT, DrawingLayerNode.OBJECTS] or not children is Array:
			return DrawingResult.failure("MANIFEST", "Invalid layer kind or ordered children")
		if not record.get("visible", true) is bool or not record.get("locked", false) is bool:
			return DrawingResult.failure("MANIFEST", "Invalid visibility or locking")
		var node: DrawingLayerNode = DrawingLayerNode.new(node_id, kind, name, parent)
		node.visible = record.get("visible", true)
		node.locked = record.get("locked", false)
		for child: Variant in children:
			if not child is String:
				return DrawingResult.failure("MANIFEST", "Invalid child identity")
			node.children.append(child)
		var text: Variant = record.get("text", "")
		var objects: Variant = record.get("objects", {})
		if not text is String or not objects is Dictionary:
			return DrawingResult.failure("MANIFEST", "Invalid semantic content")
		node.text_value = text
		var element_record: Variant = record.get("text_element")
		if element_record != null:
			if kind != DrawingLayerNode.TEXT or not element_record is Dictionary:
				return DrawingResult.failure("MANIFEST", "Invalid single text-element metadata")
			var decoded_text: DrawingResult = DrawingTextElement.from_record(element_record)
			if not decoded_text.ok:
				return decoded_text
			node.text_element = decoded_text.value as DrawingTextElement
			if node.text_element.content != text:
				return DrawingResult.failure("MANIFEST", "Text element and layer content differ")
		elif not text.is_empty() and kind == DrawingLayerNode.TEXT:
			# Legacy logical manifests may carry text without styling.
			node.text_element = DrawingTextElement.new()
			node.text_element.content = text
		elif not text.is_empty() and kind != DrawingLayerNode.TEXT:
			return DrawingResult.failure("MANIFEST", "Text on non-text layer")
		# JSON-parsed dictionaries are untyped; populate the typed owned map safely.
		for object_id: Variant in objects:
			if not object_id is String or not objects[object_id] is Dictionary:
				return DrawingResult.failure("MANIFEST", "Invalid generic object record")
			node.objects[object_id] = (objects[object_id] as Dictionary).duplicate(true)
		var chunks: Variant = record.get("chunks", [])
		if not chunks is Array or (not chunks.is_empty() and kind != DrawingLayerNode.RASTER):
			return DrawingResult.failure("MANIFEST", "Invalid raster chunk placement")
		chunk_descriptors[node_id] = chunks
		document._nodes[node_id] = node
	if not document._nodes.has(ROOT_ID) or document._nodes[ROOT_ID].kind != DrawingLayerNode.GROUP:
		return DrawingResult.failure("MANIFEST", "Missing generic root group")
	if document._nodes[ROOT_ID].parent_id != "":
		return DrawingResult.failure("MANIFEST", "Root group must not have a parent")
	var visited: Dictionary[String, bool] = {}
	if not document._validate_snapshot_tree(ROOT_ID, document._nodes, visited) or visited.size() != document._nodes.size():
		return DrawingResult.failure("MANIFEST", "Disconnected or cyclic layer tree")
	for node_id: String in chunk_descriptors:
		for descriptor: Variant in chunk_descriptors[node_id]:
			if not descriptor is Dictionary:
				return DrawingResult.failure("MANIFEST", "Malformed chunk descriptor")
			var coords: Variant = descriptor.get("coord")
			var sha: Variant = descriptor.get("sha256")
			var blob_ref: Variant = descriptor.get("ref")
			if not coords is Array or coords.size() != 2 or not coords[0] is int or not coords[1] is int:
				return DrawingResult.failure("MANIFEST", "Invalid signed chunk coordinate")
			if not sha is String or not blob_ref is String or blob_ref.is_empty():
				return DrawingResult.failure("MISSING_TILE", "Manifest references an unstaged chunk")
			var registered: DrawingResult = document.register_lazy_chunk(node_id, coords[0], coords[1], blob_ref, sha, loader)
			if not registered.ok:
				return registered
	document.revision = saved_revision
	document.published_revision = saved_revision
	for node: DrawingLayerNode in document._nodes.values():
		if not node.text_value.is_empty() or not node.objects.is_empty():
			document._content_committed = true
	return DrawingResult.success(document, saved_revision)
