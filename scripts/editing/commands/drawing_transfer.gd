class_name AtlasDrawingTransfer
extends AtlasEditCommand
## One global history step transfers a detached Drawing layer/group tree.
## The timeline alone abandons unrelated Redo; replay must retain it.
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
# Only Copy needs a second snapshot: its layer/object identities are remapped.
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
	var node: Dictionary = source.node_metadata(source_node_id)
	if node.is_empty() or not target.has_node(target_parent_id) \
			or (not copied and not source.can_remove_subtree(source_node_id)):
		return
	source_parent_id = String(node["parent"])
	source_index = source.list_children(source_parent_id).find(source_node_id)
	if source_index < 0:
		return
	# A lazy source provider can mutate either document synchronously. Do not
	# accept its new destination revision as if it were the original context.
	_source_revision = source.revision
	_target_revision = target.revision
	var target_epoch: int = target.display_source_epoch
	var exported: DrawingResult = source.export_subtree(source_node_id)
	if not exported.ok or source.revision != _source_revision or target.revision != _target_revision or \
			target.display_source_epoch != target_epoch:
		return
	_snapshot = exported.value
	_prepared = true


## Called by the global timeline after validating both current revisions.
func expect_live_revisions() -> void:
	_source_revision = source.revision if source != null else -1
	_target_revision = target.revision if target != null else -1


func apply(_campaign: AtlasCampaign) -> bool:
	if not _prepared or _applied or source.revision != _source_revision \
			or target.revision != _target_revision or not source.external_history or not target.external_history \
			or _snapshot.get("root") != source_node_id:
		return false
	# All lazy fetches are finished. Check the outgoing tree and retirement
	# before importing anything. Copy Redo uses the retained independent copy.
	var first_import: bool = target_node_id.is_empty()
	if (not copied or first_import) and not source.preflight_host_transfer_source(_snapshot, not copied).ok:
		return false
	var capture_copy: bool = copied and first_import
	var inserted: DrawingResult = target.import_subtree(
		_inserted_snapshot if copied and not first_import else _snapshot,
		target_parent_id, not capture_copy, true, -1, capture_copy)
	if not inserted.ok:
		return false
	var new_id: String = String(inserted.value["id"]) if capture_copy else String(inserted.value)
	if not copied:
		var removed: DrawingResult = source.remove_subtree(source_node_id, false, true)
		if not removed.ok:
			# No provider or ordinary failure point remains after preflight.
			# Keep defensive recovery for unexpected internal divergence.
			target.remove_subtree(new_id, false, true)
			_target_revision = target.revision
			return false
	if capture_copy:
		_inserted_snapshot = inserted.value["snapshot"]
	target_node_id = new_id
	_applied = true
	_source_revision = source.revision
	_target_revision = target.revision
	return true


func revert(_campaign: AtlasCampaign) -> bool:
	if not _applied or source.revision != _source_revision \
			or target.revision != _target_revision or not target.has_node(target_node_id) \
			or not source.external_history or not target.external_history \
			or (copied and _inserted_snapshot.get("root") != target_node_id) or _snapshot.get("root") != source_node_id \
			or (not copied and target_node_id != source_node_id):
		return false
	# Validate the exact imported source before touching the original tree.
	# Copy Undo is allowed to remove its own protected root, not an arbitrary
	# locked/hidden layer. Move Undo restores sibling order with the import.
	if not copied:
		# Move uses one immutable logical source snapshot for both visits.
		if not target.preflight_host_transfer_source(_snapshot, true, false, target_parent_id).ok:
			return false
		var restored: DrawingResult = source.import_subtree(_snapshot, source_parent_id, true, true, source_index)
		if not restored.ok:
			return false
	var removed: DrawingResult = target.remove_host_copied_subtree(_inserted_snapshot) if copied else \
		target.remove_subtree(target_node_id, false, true)
	if not removed.ok:
		if not copied:
			source.remove_subtree(source_node_id, false, true)
		return false
	_applied = false
	_source_revision = source.revision
	_target_revision = target.revision
	return true
