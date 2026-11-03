class_name AtlasObjectChildEditSession
extends RefCounted
## T-064: a parent-scoped edit cursor for published child transforms.
## No Drawing pixels or campaign map history are changed by this cursor.

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
	# Stale redo must never survive a divergent transform branch.
	_operations.resize(_cursor)
	_operations.append({"child": selected_child_id,
		"generation": String(row["generation"]), "source": String(row["source_id"]),
		"before": before, "after": next_transform})
	_cursor += 1
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
	var row: Dictionary = _record(String(operation["child"]))
	var source: Transform2D = operation["before"] if forward else operation["after"]
	var target: Transform2D = operation["after"] if forward else operation["before"]
	if row.is_empty() or String(row["generation"]) != operation["generation"] or \
		String(row["source_id"]) != operation["source"] or _transform(row) != source:
		return DrawingResult.failure("STALE_CHILDREN", "History child identity or transform changed")
	var result: DrawingResult = library.transform_child(parent_source_id,
		String(operation["child"]), expected_revision, target)
	if not result.ok:
		return result
	expected_revision += 1
	_cursor += 1 if forward else -1
	selected_child_id = String(operation["child"])
	return DrawingResult.success()


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
