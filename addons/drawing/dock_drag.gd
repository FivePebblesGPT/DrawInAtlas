class_name DrawingDockDrag
extends RefCounted
## Transactional, UI-independent drop planner for dock panel/group gestures.
## Previews validate on a clone. The live layout changes only on commit.

const PANEL: String = "panel"
const GROUP: String = "group"
const TAB_SLOT: String = "tab_slot"
const GROUP_SLOT: String = "group_slot"
const MERGE_GROUP: String = "merge_group"

var _layout: DrawingDockLayout
var _source_kind: String = ""
var _source_id: String = ""
var _baseline: Dictionary = {}
var _target: Dictionary = {}
var _serial: int = 0


func _init(layout: DrawingDockLayout) -> void:
	_layout = layout


func begin_panel(panel_id: String) -> bool:
	if _layout.owner_of(panel_id).is_empty():
		return false
	return _begin(PANEL, panel_id)


func begin_group(group_id: String) -> bool:
	if _layout.group_info(group_id).is_empty():
		return false
	return _begin(GROUP, group_id)


func _begin(kind: String, id: String) -> bool:
	cancel()
	_source_kind = kind
	_source_id = id
	_baseline = _layout.snapshot()
	return true


func is_dragging() -> bool:
	return not _source_id.is_empty()


func source_kind() -> String:
	return _source_kind


func target() -> Dictionary:
	return _target.duplicate(true)


func preview(target_candidate: Dictionary) -> bool:
	_target.clear()
	if not is_dragging() or _layout.snapshot() != _baseline:
		return false
	var trial: DrawingDockLayout = _clone_layout()
	if trial == null:
		return false
	if not _apply(trial, target_candidate, _proposed_group_id()):
		return false
	_target = target_candidate.duplicate(true)
	return true


func commit() -> bool:
	if _target.is_empty() or not is_dragging() or _layout.snapshot() != _baseline:
		cancel()
		return false
	var success: bool = _apply(_layout, _target, _proposed_group_id())
	if success and _target.get("kind") == GROUP_SLOT and _source_kind == PANEL:
		_serial += 1
	cancel()
	return success


func cancel() -> void:
	_source_kind = ""
	_source_id = ""
	_baseline = {}
	_target = {}


func _clone_layout() -> DrawingDockLayout:
	var trial: DrawingDockLayout = DrawingDockLayout.new()
	for panel: Dictionary in _baseline.get("panels", []):
		if not trial.register_panel(String(panel["id"])):
			return null
	if not trial.restore(_baseline):
		return null
	return trial


func _proposed_group_id() -> String:
	var index: int = _serial + 1
	var candidate: String = "split-%d" % index
	while not _layout.group_info(candidate).is_empty():
		index += 1
		candidate = "split-%d" % index
	return candidate


func _apply(layout: DrawingDockLayout, destination: Dictionary, split_id: String) -> bool:
	if not destination.get("kind") is String:
		return false
	var kind: String = destination["kind"]
	if kind == TAB_SLOT or kind == MERGE_GROUP:
		if not destination.get("group") is String or not destination.get("index") is int:
			return false
		var group_id: String = destination["group"]
		var index: int = destination["index"]
		if _source_kind == PANEL:
			return layout.move_panel(_source_id, group_id, index)
		if _source_kind == GROUP and kind == MERGE_GROUP:
			return layout.merge_groups(_source_id, group_id, index)
	elif kind == GROUP_SLOT:
		if not destination.get("container") is String or not destination.get("index") is int:
			return false
		var container_id: String = destination["container"]
		var group_index: int = destination["index"]
		if _source_kind == PANEL:
			return layout.split_panel(_source_id, split_id, container_id, group_index)
		if _source_kind == GROUP:
			return layout.move_group(_source_id, container_id, group_index)
	return false
