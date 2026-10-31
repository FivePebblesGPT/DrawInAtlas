class_name AtlasEditHistory
extends RefCounted
## Campaign-local command log and dirty-state tracking. _states stores unique
## history-state identifiers, not cursor indexes: after undo + a new command,
## the new branch must not inherit the checkpoint identity of discarded redo.
## _external_revision accounts for changes not yet represented by commands.

signal changed

var active_map_id: String = ""
var _campaign: AtlasCampaign
var _commands: Array[AtlasEditCommand] = []
## One unique state token per command boundary (length = commands + 1).
## Tokens are identities, not array positions, and may skip after branching.
var _states: Array[int] = [0]
## Number of currently applied commands; 0.._commands.size().
var _cursor: int = 0
var _next_state: int = 0
## Saved checkpoint identity compared to _states[_cursor] for dirty status.
var _saved_state: int = 0
## Dirty revisions for direct mutations outside history commands; the saved
## counterpart captures only the last persisted external revision.
var _external_revision: int = 0
var _saved_external_revision: int = 0


func _init(campaign: AtlasCampaign = null) -> void:
	_campaign = campaign


func reset(campaign: AtlasCampaign, saved: bool = true) -> void:
	_campaign = campaign
	active_map_id = ""
	_commands.clear()
	_states = [0]
	_cursor = 0
	_next_state = 0
	_saved_state = 0 if saved else -1
	_external_revision = 0
	_saved_external_revision = 0
	changed.emit()


## Applying a command is transactional: invalid commands do not mutate history.
## Only after successful apply do we discard the redo branch and issue a state ID.
func execute(command: AtlasEditCommand) -> bool:
	if _campaign == null or command == null or command.map_id != active_map_id:
		return false
	if not command.apply(_campaign):
		return false
	_discard_redo()
	_commands.append(command)
	_cursor += 1
	_next_state += 1
	_states.append(_next_state)
	changed.emit()
	return true


func undo() -> bool:
	if not can_undo() or not _commands[_cursor - 1].revert(_campaign):
		return false
	_cursor -= 1
	changed.emit()
	return true


func redo() -> bool:
	if not can_redo() or not _commands[_cursor].apply(_campaign):
		return false
	_cursor += 1
	changed.emit()
	return true


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _commands.size()


func get_undo_command() -> AtlasEditCommand:
	return _commands[_cursor - 1] if can_undo() else null


func get_redo_command() -> AtlasEditCommand:
	return _commands[_cursor] if can_redo() else null


func is_dirty() -> bool:
	return _states[_cursor] != _saved_state or _external_revision != _saved_external_revision


func mark_saved() -> void:
	_saved_state = _states[_cursor]
	_saved_external_revision = _external_revision
	changed.emit()


func mark_external_change() -> void:
	# External metadata edits are dirty even when not represented by commands.
	_discard_redo()
	_external_revision += 1
	changed.emit()


func _discard_redo() -> void:
	_commands.resize(_cursor)
	_states.resize(_cursor + 1)
