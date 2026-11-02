class_name AtlasDrawingTransfer
extends AtlasEditCommand
## One global history step transfers a detached Drawing layer/group tree.
## Documents are required to use Atlas-owned history. Different density needs
## a separate, explicitly approved resampling transaction (T-061).

var source: DrawingDocument
var target: DrawingDocument
var source_node_id: String = ""
var target_parent_id: String = ""
var source_parent_id: String = ""
var source_index: int = -1
var target_node_id: String = ""
var copied: bool = false
var before_context: DrawingHistoryContext
var after_context: DrawingHistoryContext
var _snapshot: Dictionary = {}
var _inserted_snapshot: Dictionary = {}
var _source_revision: int = -1
var _target_revision: int = -1
var _applied: bool = false
var _prepared: bool = false


func _init(from: DrawingDocument, into: DrawingDocument, node_id: String,
		parent_id: String, is_copy: bool, before: DrawingHistoryContext,
		after: DrawingHistoryContext) -> void:
	source = from
	target = into
	source_node_id = node_id
	target_parent_id = parent_id
	copied = is_copy
	before_context = before.detached_copy() if before != null else null
	after_context = after.detached_copy() if after != null else null
	if before_context != null:
		map_id = before_context.map_id
		floor_id = before_context.floor_group_id
	if source == null or target == null or source == target or not source.external_history \
			or not target.external_history or before_context == null or after_context == null \
			or before_context.document_id != source.id or after_context.document_id != target.id \
			or source.tile_stride != target.tile_stride \
			or source.density_numerator * target.density_denominator != target.density_numerator * source.density_denominator:
		return
	var node: DrawingLayerNode = source.inspect_node(source_node_id)
	if node == null or not target.has_node(target_parent_id) \
			or (not copied and not source.can_remove_subtree(source_node_id)):
		return
	source_parent_id = node.parent_id
	source_index = source.list_children(source_parent_id).find(source_node_id)
	var exported: DrawingResult = source.export_subtree(source_node_id)
	if not exported.ok:
		return
	_snapshot = exported.value
	_source_revision = source.revision
	_target_revision = target.revision
	_prepared = true


## Called by the global timeline after validating both current revisions.
func expect_live_revisions() -> void:
	_source_revision = source.revision if source != null else -1
	_target_revision = target.revision if target != null else -1


func apply(_campaign: AtlasCampaign) -> bool:
	if not _prepared or _applied or source.revision != _source_revision \
			or target.revision != _target_revision:
		return false
	var inserted: DrawingResult = target.import_subtree(
		_inserted_snapshot if not _inserted_snapshot.is_empty() else _snapshot,
		target_parent_id, not _inserted_snapshot.is_empty() or not copied)
	if not inserted.ok:
		return false
	var new_id: String = String(inserted.value)
	if not copied:
		var removed: DrawingResult = source.remove_subtree(source_node_id)
		if not removed.ok:
			target.remove_subtree(new_id)
			_target_revision = target.revision
			return false
	if _inserted_snapshot.is_empty():
		var exported: DrawingResult = target.export_subtree(new_id)
		if not exported.ok:
			# An unexpected bad chunk must not leave a half-moved tree.
			if not copied:
				source.import_subtree(_snapshot, source_parent_id, true)
				source.reorder(source_node_id, source_parent_id, source_index)
			target.remove_subtree(new_id)
			_source_revision = source.revision
			_target_revision = target.revision
			return false
		_inserted_snapshot = exported.value
	target_node_id = new_id
	_applied = true
	_source_revision = source.revision
	_target_revision = target.revision
	return true


func revert(_campaign: AtlasCampaign) -> bool:
	if not _applied or source.revision != _source_revision \
			or target.revision != _target_revision or not target.has_node(target_node_id):
		return false
	if not copied:
		var restored: DrawingResult = source.import_subtree(_snapshot, source_parent_id, true)
		if not restored.ok:
			return false
		# Restore original sibling position, not just the layer identity.
		var reordered: DrawingResult = source.reorder(source_node_id, source_parent_id, source_index)
		if not reordered.ok:
			source.remove_subtree(source_node_id)
			return false
	var removed: DrawingResult = target.remove_subtree(target_node_id)
	if not removed.ok:
		if not copied:
			source.remove_subtree(source_node_id)
		return false
	_applied = false
	_source_revision = source.revision
	_target_revision = target.revision
	return true
