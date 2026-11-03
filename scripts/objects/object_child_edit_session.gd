class_name AtlasObjectChildEditSession
extends RefCounted
## T-064: a parent-scoped edit cursor for published child layout operations.
## No Drawing pixels or campaign map history are changed by this cursor.
## Structural edits retain stable child identities and sibling order through replay.

var library: AtlasObjectLibrary
var parent_source_id: String = ""
var selected_child_id: String = ""
var expected_revision: int = -1
var _operations: Array[Dictionary] = []
var _cursor: int = 0


func _init(registry: AtlasObjectLibrary = null, parent_source: String = "") -> void:
	bind_parent(registry, parent_source)


func bind_parent(registry: AtlasObjectLibrary, parent_source: String) -> void:
	library = registry
	parent_source_id = parent_source
	selected_child_id = ""
	expected_revision = registry.children_revision(parent_source) if registry != null else -1
	_operations.clear()
	_cursor = 0


func is_stale() -> bool:
	return library == null or expected_revision < 0 or \
		library.children_revision(parent_source_id) != expected_revision


func select_child(child_id: String) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Reload the parent before selecting children")
	if child_id.is_empty():
		selected_child_id = ""
		return DrawingResult.success()
	if _record(child_id).is_empty():
		return DrawingResult.failure("CHILD", "Child is no longer attached to this parent")
	selected_child_id = child_id
	return DrawingResult.success()


func selected_record() -> Dictionary:
	return _record(selected_child_id) if not is_stale() else {}


func can_undo() -> bool:
	return not is_stale() and _cursor > 0


func can_redo() -> bool:
	return not is_stale() and _cursor < _operations.size()


func attach_source(source_id: String, placement: Transform2D = Transform2D.IDENTITY) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before attaching")
	var previous_selection: String = selected_child_id
	var position: int = library.children_for_asset(parent_source_id).size()
	var result: DrawingResult = library.attach_child(parent_source_id, expected_revision,
		source_id, placement)
	if not result.ok:
		return result
	expected_revision += 1
	var attached_id: String = String(result.value)
	var row: Dictionary = _saved_record(attached_id)
	selected_child_id = attached_id
	_record_operation({"kind": "attach", "row": row, "index": position,
		"previous_selection": previous_selection})
	return DrawingResult.success(attached_id)


func detach_selected() -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before removing")
	var child_id: String = selected_child_id
	var siblings: Array[Dictionary] = library.children_for_asset(parent_source_id)
	var position: int = -1
	for index: int in range(siblings.size()):
		if siblings[index]["id"] == child_id:
			position = index
			break
	if position < 0:
		return DrawingResult.failure("CHILD", "Select an attached child to remove")
	var row: Dictionary = _saved_record(child_id)
	var removed: DrawingResult = library.detach_child(parent_source_id, child_id, expected_revision)
	if not removed.ok:
		return removed
	expected_revision += 1
	selected_child_id = ""
	_record_operation({"kind": "detach", "row": row, "index": position})
	return DrawingResult.success()


## Rebinding a NULL child is one parent-local history action. Replaying it
## preserves the old source tombstone and never changes either source's pixels.
func repair_selected(replacement_source_id: String) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Reload the parent before repairing")
	var before: Dictionary = _saved_record(selected_child_id)
	if before.is_empty():
		return DrawingResult.failure("CHILD", "Select a missing nested child")
	var repaired: DrawingResult = library.repair_child_placeholder(parent_source_id,
		selected_child_id, expected_revision, String(before["generation"]),
		int(before["revision"]), replacement_source_id)
	if not repaired.ok:
		return repaired
	expected_revision += 1
	_record_operation({"kind": "rebind", "child": selected_child_id,
		"generation": String(before["generation"]), "before": before,
		"after": _saved_record(selected_child_id)})
	return repaired


func _record_operation(operation: Dictionary) -> void:
	# Structural edits and transforms share one parent-local history timeline.
	_operations.resize(_cursor)
	_operations.append(operation)
	_cursor += 1


func _saved_record(child_id: String) -> Dictionary:
	var row: Dictionary = _record(child_id).duplicate(true)
	row.erase("status") # UI-only dynamic availability must never enter the registry.
	return row


## Hidden children remain selectable in the inspector but disappear from
## traversal, preview rendering and canvas hit-testing. One edit = one undo.
func set_selected_visibility(visible: bool) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before editing visibility")
	var row: Dictionary = selected_record()
	if row.is_empty():
		return DrawingResult.failure("CHILD", "Select a current nested child")
	if bool(row["visible"]) == visible:
		return DrawingResult.success(false)
	var changed: DrawingResult = library.set_child_visibility(parent_source_id,
		selected_child_id, expected_revision, String(row["generation"]),
		int(row["revision"]), visible)
	if not changed.ok:
		return changed
	expected_revision += 1
	_record_operation({"kind": "visibility", "child": selected_child_id,
		"generation": String(row["generation"]), "source": String(row["source_id"]),
		"before": bool(row["visible"]), "after": visible})
	return DrawingResult.success(true)


func toggle_selected_visibility() -> DrawingResult:
	var record: Dictionary = selected_record()
	if record.is_empty():
		return DrawingResult.failure("CHILD", "Select a current nested child")
	return set_selected_visibility(not bool(record["visible"]))


func translate_selected(delta: Vector2) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before editing")
	if not delta.is_finite():
		return DrawingResult.failure("CHILD", "Translation must be finite")
	var row: Dictionary = selected_record()
	if row.is_empty():
		return DrawingResult.failure("CHILD", "Select a current nested child")
	var original: Transform2D = _transform(row)
	var moved: Transform2D = original
	moved.origin += delta
	return set_selected_transform(moved)


func rotate_selected(angle: float) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before editing")
	if not is_finite(angle):
		return DrawingResult.failure("CHILD", "Rotation must be finite")
	var row: Dictionary = selected_record()
	if row.is_empty():
		return DrawingResult.failure("CHILD", "Select a current nested child")
	var original: Transform2D = _transform(row)
	return set_selected_transform(original.rotated_local(angle))


## Uniform scale is a parent-local layout edit; the selected child source and
## placement origin stay untouched. A positive factor preserves handedness,
## including previously mirrored/nonuniform basis vectors.
func scale_selected(factor: float) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Parent changed; reload before scaling")
	if not is_finite(factor) or factor <= 0.0:
		return DrawingResult.failure("CHILD", "Scale factor must be finite and positive")
	var row: Dictionary = selected_record()
	if row.is_empty():
		return DrawingResult.failure("CHILD", "Select a current nested child")
	var original: Transform2D = _transform(row)
	return set_selected_transform(original.scaled_local(Vector2(factor, factor)))


func set_selected_transform(next_transform: Transform2D) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Nested source changed; reload before editing")
	var row: Dictionary = _record(selected_child_id)
	if row.is_empty():
		return DrawingResult.failure("CHILD", "Select a current nested child")
	var before: Transform2D = _transform(row)
	if before == next_transform:
		return DrawingResult.success(false)
	var changed: DrawingResult = library.transform_child(parent_source_id, selected_child_id,
		expected_revision, next_transform)
	if not changed.ok:
		return changed
	expected_revision += 1
	_record_operation({"kind": "transform", "child": selected_child_id,
		"generation": String(row["generation"]), "source": String(row["source_id"]),
		"before": before, "after": next_transform})
	return DrawingResult.success(true)


func undo() -> DrawingResult:
	return _replay(false)


func redo() -> DrawingResult:
	return _replay(true)


func _replay(forward: bool) -> DrawingResult:
	if is_stale():
		return DrawingResult.failure("STALE_CHILDREN", "Nested source changed; reload before history replay")
	if (forward and _cursor >= _operations.size()) or (not forward and _cursor == 0):
		return DrawingResult.failure("CHILD_HISTORY", "Nothing to replay")
	var index: int = _cursor if forward else _cursor - 1
	var operation: Dictionary = _operations[index]
	var result: DrawingResult
	if operation["kind"] == "rebind":
		var current: Dictionary = _saved_record(String(operation["child"]))
		var expected: Dictionary = operation["before"] if forward else operation["after"]
		var desired: Dictionary = operation["after"] if forward else operation["before"]
		if current.is_empty() or current["generation"] != operation["generation"] or \
				not _same_child_identity(current, expected):
			return DrawingResult.failure("STALE_CHILDREN", "Rebound child differs from history snapshot")
		result = library._set_child_binding(parent_source_id, String(operation["child"]),
			expected_revision, String(operation["generation"]), int(current["revision"]),
			String(desired["source_id"]), bool(desired["placeholder"]), desired["metadata"])
		if result.ok:
			selected_child_id = String(operation["child"])
	elif operation["kind"] == "visibility":
		var row: Dictionary = _record(String(operation["child"]))
		var from_visible: bool = bool(operation["before"]) if forward else bool(operation["after"])
		var to_visible: bool = bool(operation["after"]) if forward else bool(operation["before"])
		if row.is_empty() or String(row["generation"]) != operation["generation"] or \
				String(row["source_id"]) != operation["source"] or bool(row["visible"]) != from_visible:
			return DrawingResult.failure("STALE_CHILDREN", "History child identity or visibility changed")
		result = library.set_child_visibility(parent_source_id, String(operation["child"]),
			expected_revision, String(row["generation"]), int(row["revision"]), to_visible)
		if result.ok:
			selected_child_id = String(operation["child"])

	elif operation["kind"] == "transform":
		var row: Dictionary = _record(String(operation["child"]))
		var source: Transform2D = operation["before"] if forward else operation["after"]
		var target: Transform2D = operation["after"] if forward else operation["before"]
		if row.is_empty() or String(row["generation"]) != operation["generation"] or \
				String(row["source_id"]) != operation["source"] or _transform(row) != source:
			return DrawingResult.failure("STALE_CHILDREN", "History child identity or transform changed")
		result = library.transform_child(parent_source_id,
			String(operation["child"]), expected_revision, target)
		if result.ok:
			selected_child_id = String(operation["child"])
	else:
		var child: Dictionary = operation["row"]
		var child_id: String = String(child["id"])
		var should_restore: bool = (operation["kind"] == "attach" and forward) or \
			(operation["kind"] == "detach" and not forward)
		if should_restore:
			if not _record(child_id).is_empty():
				return DrawingResult.failure("STALE_CHILDREN", "Detached child ID is already in use")
			var restored: Dictionary = child.duplicate(true)
			restored["revision"] = int(restored["revision"]) + 1
			result = library._restore_child_snapshot(parent_source_id, expected_revision, restored,
				int(operation["index"]))
			if result.ok:
				operation["row"] = restored
				_operations[index] = operation
				selected_child_id = child_id
		else:
			var current: Dictionary = _saved_record(child_id)
			if current.is_empty() or not _same_child_identity(current, child):
				return DrawingResult.failure("STALE_CHILDREN", "Nested child changed since history recorded")
			result = library.detach_child(parent_source_id, child_id, expected_revision)
			if result.ok:
				selected_child_id = String(operation.get("previous_selection", "")) if not forward else ""
	if not result.ok:
		return result
	expected_revision += 1
	_cursor += 1 if forward else -1
	return DrawingResult.success()


static func _same_child_identity(current: Dictionary, saved: Dictionary) -> bool:
	# Revision is monotonically bumped by restore; content/identity must match.
	for field: String in ["id", "generation", "source_id", "transform", "visible",
			"placeholder", "metadata"]:
		if current.get(field) != saved.get(field):
			return false
	return true


func _record(child_id: String) -> Dictionary:
	if library == null or child_id.is_empty():
		return {}
	for row: Dictionary in library.children_for_asset(parent_source_id):
		if row["id"] == child_id:
			return row
	return {}


static func _transform(row: Dictionary) -> Transform2D:
	var values: Array = row["transform"]
	return Transform2D(Vector2(float(values[0]), float(values[1])),
		Vector2(float(values[2]), float(values[3])),
		Vector2(float(values[4]), float(values[5])))
