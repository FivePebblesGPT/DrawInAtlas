class_name AtlasDrawingEdit
extends AtlasEditCommand
## One already-published Drawing gesture in Atlas's *existing* command order.
## A shared asset is edited once; all live instances resolve that same document.

var floor_group_id: String = ""
var detail_group_id: String = ""
var document_id: String = ""
var asset_id: String = ""
var document: DrawingDocument
var delta: DrawingDelta
var before_context: DrawingHistoryContext
var after_context: DrawingHistoryContext
var dirty_regions: Array[DrawingDirtyRegion] = []
var _applied: bool = true
var _expected_revision: int = -1


func _init(target: DrawingDocument, change: DrawingDelta,
		before: DrawingHistoryContext, after: DrawingHistoryContext,
		regions: Array[DrawingDirtyRegion] = []) -> void:
	document = target
	delta = DrawingDelta.new(change.layer_id, change.before, change.after) if change != null else null
	before_context = before.detached_copy() if before != null else null
	after_context = after.detached_copy() if after != null else null
	if before_context != null:
		map_id = before_context.map_id
		floor_id = before_context.floor_group_id
		floor_group_id = floor_id
		detail_group_id = before_context.detail_group_id
		document_id = before_context.document_id
	asset_id = before_context.asset_id if not before_context.asset_id.is_empty() else document_id
	for region: DrawingDirtyRegion in regions:
		dirty_regions.append(DrawingDirtyRegion.new(region.layer_id, region.x,
			region.y, region.width, region.height))
	_expected_revision = document.revision if document != null else -1


## Only the Atlas timeline may refresh this after validating its document ledger.
func expect_live_revision() -> void:
	_expected_revision = document.revision if document != null else -1


func valid_applied() -> bool:
	return document != null and delta != null and not map_id.is_empty() \
		and document.id == document_id and document.external_history \
		and document.revision == _expected_revision and _applied


func apply(_campaign: AtlasCampaign) -> bool:
	if _applied or document == null or document.id != document_id \
			or document.revision != _expected_revision or not document.external_history:
		return false
	var result: DrawingResult = document.replay_delta(delta, false)
	if not result.ok:
		return false
	_expected_revision = document.revision
	_applied = true
	return true


func revert(_campaign: AtlasCampaign) -> bool:
	if not _applied or document == null or document.id != document_id \
			or document.revision != _expected_revision or not document.external_history:
		return false
	var result: DrawingResult = document.replay_delta(delta, true)
	if not result.ok:
		return false
	_expected_revision = document.revision
	_applied = false
	return true
