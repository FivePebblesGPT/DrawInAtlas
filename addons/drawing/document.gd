class_name DrawingDocument
extends RefCounted
## Generic sparse Drawing source, with stable nested groups and transactional edits.
## Atlas chooses which document is active; this type knows no Atlas concepts.

const TILES: Script = preload("res://addons/drawing/signed_tiles.gd")
const ROOT_ID: String = "root"

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
var _undo: Array[DrawingDelta] = []
var _redo: Array[DrawingDelta] = []


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
	return revision != published_revision


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
		requested_id: String = "") -> DrawingResult:
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
	_nodes[new_identifier] = DrawingLayerNode.new(new_identifier, kind, name, parent_id)
	_nodes[parent_id].children.append(new_identifier)
	revision += 1
	return DrawingResult.success(new_identifier, revision)


func rename_layer(node_id: String, name: String) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID:
		return DrawingResult.failure("LAYER", "Cannot rename missing/root layer")
	if not _editable(node_id):
		return DrawingResult.failure("LOCKED", "Layer or ancestor is hidden or locked")
	if _nodes[node_id].name != name:
		_nodes[node_id].name = name
		revision += 1
	return DrawingResult.success(null, revision)


func set_visibility(node_id: String, visible: bool) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID:
		return DrawingResult.failure("LAYER", "Cannot change missing/root layer")
	if _nodes[node_id].visible != visible:
		_nodes[node_id].visible = visible
		revision += 1
	return DrawingResult.success(null, revision)


func set_locked(node_id: String, locked: bool) -> DrawingResult:
	if not _nodes.has(node_id) or node_id == ROOT_ID:
		return DrawingResult.failure("LAYER", "Cannot change missing/root layer")
	if _nodes[node_id].locked != locked:
		_nodes[node_id].locked = locked
		revision += 1
	return DrawingResult.success(null, revision)


func _editable(node_id: String) -> bool:
	var current: String = node_id
	while _nodes.has(current):
		var node: DrawingLayerNode = _nodes[current]
		if node.locked or not node.visible:
			return false
		current = node.parent_id
	return true


func reorder(node_id: String, new_parent: String, new_index: int) -> DrawingResult:
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
	original.erase(node_id)
	var destination: Array[String] = _nodes[new_parent].children
	destination.insert(clampi(new_index, 0, destination.size()), node_id)
	_nodes[node_id].parent_id = new_parent
	revision += 1
	return DrawingResult.success(null, revision)


func remove_subtree(node_id: String) -> DrawingResult:
	if node_id == ROOT_ID or not _nodes.has(node_id) or not _editable(node_id):
		return DrawingResult.failure("LAYER", "Missing, root or inaccessible layer")
	_erase_subtree(node_id)
	revision += 1
	return DrawingResult.success(null, revision)


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
		density_numerator = numerator
		density_denominator = denominator
		revision += 1
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
	if abs(anchor_x) > 1152921504606846976 or abs(anchor_y) > 1152921504606846976:
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
		var pending: Dictionary = _pending_tiles[lookup]
		var provider: Callable = pending["fetch"] as Callable
		if not provider.is_valid():
			return DrawingResult.failure("MISSING_TILE", "No provider for referenced chunk " + lookup)
		var content: Variant = provider.call(pending["ref"])
		if not content is PackedByteArray:
			return DrawingResult.failure("MISSING_TILE", "Referenced chunk is missing " + lookup)
		var bytes: PackedByteArray = content
		if bytes.size() != tile_stride * tile_stride * 4 or DrawingRasterTile.digest_rgba8(bytes, tile_stride) != pending["sha256"]:
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
	var key: String = "%d,%d" % [cx, cy]
	if _nodes[layer_id].tiles.has(key) or _pending_tiles.has(layer_id + ":" + key):
		return DrawingResult.failure("DUPLICATE_TILE", "Chunk already registered")
	_pending_tiles[layer_id + ":" + key] = {"ref": blob_ref, "sha256": canonical_sha256, "fetch": loader}
	_known_refs[layer_id + ":" + key] = {"ref": blob_ref, "sha256": canonical_sha256}
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


## Read and compare originals before publication, then detach only touched tiles.
func _publish_edit(layer_id: String, expected: int,
		before: Dictionary[String, int], after: Dictionary[String, int],
		record_history: bool = true) -> DrawingResult:
	if revision != expected:
		return DrawingResult.failure("STALE_REVISION", "Concurrent edit invalidated the gesture")
	if not _nodes.has(layer_id) or not _editable(layer_id):
		return DrawingResult.failure("LOCKED", "Edited layer became unavailable")
	if after.is_empty():
		return DrawingResult.failure("NO_CHANGE", "Gesture made no content changes")

	var detached: Dictionary[String, DrawingRasterTile] = {}
	var bounds: Dictionary[String, Array] = {}
	for coordinate: String in after:
		var components: PackedStringArray = coordinate.split(",")
		if components.size() != 2:
			return DrawingResult.failure("COORD", "Invalid pixel coordinate")
		var x: int = int(components[0])
		var y: int = int(components[1])
		if coordinate != TILES.pixel_key64(x, y):
			return DrawingResult.failure("COORD", "Noncanonical signed pixel coordinate")
		var original: DrawingResult = read_pixel(layer_id, x, y)
		if not original.ok:
			return original
		if int(original.value) != before.get(coordinate, -1):
			return DrawingResult.failure("STALE_PIXEL", "Source pixel changed during gesture")
		var tile_key: String = TILES.tile_key64(x, y, tile_stride)
		if not detached.has(tile_key):
			var existing: DrawingRasterTile = _nodes[layer_id].tiles.get(tile_key)
			detached[tile_key] = existing.detached_copy() if existing != null else DrawingRasterTile.new(tile_stride)
		var point: Vector2i = TILES.local_offset64(x, y, tile_stride)
		detached[tile_key].set_rgba(point.x, point.y, after[coordinate])
		if not bounds.has(tile_key):
			bounds[tile_key] = [x, y, x, y]
		else:
			var rect: Array = bounds[tile_key]
			rect[0] = mini(int(rect[0]), x)
			rect[1] = mini(int(rect[1]), y)
			rect[2] = maxi(int(rect[2]), x)
			rect[3] = maxi(int(rect[3]), y)

	# No owned pixels change until every source, digest and revision check succeeds.
	var result: DrawingResult = DrawingResult.success(null)
	for key: String in detached:
		if detached[key].is_empty():
			_nodes[layer_id].tiles.erase(key)
		else:
			_nodes[layer_id].tiles[key] = detached[key]
		_dirty_tiles[layer_id + ":" + key] = true
		_known_refs.erase(layer_id + ":" + key)
		var rect: Array = bounds[key]
		result.regions.append(DrawingDirtyRegion.new(layer_id, int(rect[0]), int(rect[1]),
			int(rect[2]) - int(rect[0]) + 1, int(rect[3]) - int(rect[1]) + 1))
	revision += 1
	_content_committed = true
	result.revision = revision
	result.delta = DrawingDelta.new(layer_id, before, after)
	if record_history:
		_undo.append(result.delta)
		_redo.clear()
	return result


func undo() -> DrawingResult:
	if _undo.is_empty():
		return DrawingResult.failure("EMPTY_HISTORY", "Nothing to undo")
	var delta: DrawingDelta = _undo.back()
	var replayed: DrawingResult = _publish_edit(delta.layer_id, revision, delta.after, delta.before, false)
	if replayed.ok:
		_undo.pop_back()
		_redo.append(delta)
	return replayed


func redo() -> DrawingResult:
	if _redo.is_empty():
		return DrawingResult.failure("EMPTY_HISTORY", "Nothing to redo")
	var delta: DrawingDelta = _redo.back()
	var replayed: DrawingResult = _publish_edit(delta.layer_id, revision, delta.before, delta.after, false)
	if replayed.ok:
		_redo.pop_back()
		_undo.append(delta)
	return replayed


func add_object(layer_id: String, data: Dictionary, requested_id: String = "") -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.OBJECTS or not _editable(layer_id):
		return DrawingResult.failure("LAYER", "Unavailable semantic-object layer")
	var object_id: String = requested_id if not requested_id.is_empty() else new_id()
	if _nodes[layer_id].objects.has(object_id):
		return DrawingResult.failure("DUPLICATE_ID", "Object ID already exists")
	_nodes[layer_id].objects[object_id] = data.duplicate(true)
	revision += 1
	_content_committed = true
	return DrawingResult.success(object_id, revision)


func move_object(layer_id: String, object_id: String, position: Vector2) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.OBJECTS or not _editable(layer_id):
		return DrawingResult.failure("LAYER", "Unavailable semantic-object layer")
	if not _nodes[layer_id].objects.has(object_id) or not position.is_finite():
		return DrawingResult.failure("OBJECT", "Missing object or invalid position")
	var updated: Dictionary = _nodes[layer_id].objects[object_id].duplicate(true)
	updated["position"] = position
	_nodes[layer_id].objects[object_id] = updated
	revision += 1
	return DrawingResult.success(null, revision)


func set_text(layer_id: String, content: String) -> DrawingResult:
	if not _nodes.has(layer_id) or _nodes[layer_id].kind != DrawingLayerNode.TEXT or not _editable(layer_id):
		return DrawingResult.failure("LAYER", "Unavailable text layer")
	if _nodes[layer_id].text_value != content:
		_nodes[layer_id].text_value = content
		revision += 1
		_content_committed = true
	return DrawingResult.success(null, revision)


## Caller gets a detached hierarchical snapshot. Import cannot alias tile dictionaries.
func export_subtree(node_id: String) -> DrawingResult:
	if node_id == ROOT_ID or not _nodes.has(node_id):
		return DrawingResult.failure("LAYER", "Cannot export missing/root layer")
	# A detached transfer cannot drop unresolved tile references. Resolve or fail.
	var ids: Array[String] = []
	_gather_ids(node_id, ids)
	for child_id: String in ids:
		if _nodes[child_id].kind != DrawingLayerNode.RASTER:
			continue
		for tile_id: String in tile_keys(child_id):
			var loaded: DrawingResult = _resolve_chunk(child_id, tile_id)
			if not loaded.ok:
				return loaded
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
	# Validate before publishing any nodes. No source/target tile object is shared.
	for old_id: Variant in nodes:
		var imported: DrawingLayerNode = (nodes[old_id] as DrawingLayerNode).detached_copy()
		imported.id = mapping[String(old_id)]
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
		_nodes[imported.id] = imported
		for tile_key: String in imported.tiles:
			_dirty_tiles[imported.id + ":" + tile_key] = true
	_nodes[parent_id].children.append(mapping[original_root])
	revision += 1
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
	var inserted: DrawingResult = target.import_subtree(exported.value, target_parent, move)
	if not inserted.ok:
		return inserted
	if move:
		# The previous validation and single-threaded commit prevent an aliasing window.
		source.remove_subtree(node_id)
	return inserted


func snapshot_for_save() -> Dictionary:
	var tree: Array[Dictionary] = []
	var ids: Array[String] = _nodes.keys()
	ids.sort()
	for node_id: String in ids:
		var node: DrawingLayerNode = _nodes[node_id]
		tree.append({"id": node.id, "parent": node.parent_id, "kind": node.kind,
			"name": node.name, "visible": node.visible, "locked": node.locked,
			"children": node.children.duplicate(), "tiles": tile_keys(node_id),
			"text": node.text_value, "objects": node.objects.duplicate(true)})
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
	return {"id": id, "revision": revision, "stride": tile_stride,
		"density": [density_numerator, density_denominator], "tree": tree,
		"dirty_rgba8": dirty, "removed_tile_ids": removed}


func mark_published(saved_revision: int,
		published_refs: Dictionary[String, String] = {}) -> DrawingResult:
	if saved_revision != revision:
		return DrawingResult.failure("STALE_REVISION", "Cannot publish an older snapshot")
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
	_dirty_tiles.clear()
	return DrawingResult.success(null, revision)


## Logical, format-neutral manifest. T-066 owns the physical file/schema, codecs
## and atomic generation publication. A blank ref denotes a tile needing staging.
func export_manifest() -> DrawingResult:
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
