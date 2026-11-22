class_name AtlasEditHistory
extends RefCounted
## Campaign-local command log and dirty-state tracking. _states stores unique
## history-state identifiers, not cursor indexes: after undo + a new command,
## the new branch must not inherit the checkpoint identity of discarded redo.
## _external_revision accounts for changes not yet represented by commands.

signal changed
signal restoration_warning(message: String)

## Application-level setting, not serialized artwork state.
var record_selection_history: bool = false
## Host handlers are configurable only between history operations. A context
## callback or synchronous observer must not replace its own partner midway
## through capture/restoration, including reflective Object.set() writes.
var _context_provider: Callable
var context_provider: Callable:
	get:
		return _context_provider
	set(value):
		if _timeline_reserved() or _replaying:
			return
		_context_provider = value
## Optional synchronous host UI restoration; false triggers a visible warning.
var _context_restorer: Callable
var context_restorer: Callable:
	get:
		return _context_restorer
	set(value):
		if _timeline_reserved() or _replaying:
			return
		_context_restorer = value
var last_playback_warning: String = ""
var last_playback_context: DrawingHistoryContext
var _replaying: bool = false
## A Drawing commit can resolve caller-owned lazy sources synchronously. Their
## callbacks must not insert, undo, reset or mark saved another host command
## before this transaction has been appended to the Atlas timeline.
var _committing_drawing: bool = false
## Reserve other synchronous host commands across context callbacks, apply and signals.
var _executing_command: bool = false
## Synchronous history notifications are observable, not a second command window.
var _notifying_changed: bool = false
var _contexts_before: Array[DrawingHistoryContext] = []
var _contexts_after: Array[DrawingHistoryContext] = []
## Expected live revisions for every Drawing document touched by this timeline.
## A command from an older cursor point must not assume its original revision
## still holds after later undo/redo replay has incremented that revision.
var _drawing_revisions: Dictionary[int, int] = {}

## The host may navigate while idle, including between a gesture and commit,
## but synchronous command callbacks must not rebind the active edit target.
var _active_map_id: String = ""
var active_map_id: String:
	get:
		return _active_map_id
	set(value):
		if _timeline_reserved() or _replaying:
			return
		_active_map_id = value
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


func _timeline_reserved() -> bool:
	return _committing_drawing or _executing_command or _notifying_changed


func _emit_changed() -> void:
	var previous: bool = _notifying_changed
	_notifying_changed = true
	changed.emit()
	_notifying_changed = previous


func reset(campaign: AtlasCampaign, saved: bool = true) -> void:
	if _timeline_reserved() or _replaying:
		return
	_campaign = campaign
	active_map_id = ""
	_commands.clear()
	_contexts_before.clear()
	_contexts_after.clear()
	_drawing_revisions.clear()
	last_playback_warning = ""
	last_playback_context = null
	_replaying = false
	_states = [0]
	_cursor = 0
	_next_state = 0
	_saved_state = 0 if saved else -1
	_external_revision = 0
	_saved_external_revision = 0
	_emit_changed()


## Applying a command is transactional: invalid commands do not mutate history.
## Only after successful apply do we discard the redo branch and issue a state ID.
func execute(command: AtlasEditCommand) -> bool:
	if _replaying or _timeline_reserved() or _campaign == null or command == null or command.map_id != active_map_id \
			or not _revisions_valid(command):
		return false
	_executing_command = true
	var before: DrawingHistoryContext = _capture_context(command.map_id, command.floor_id)
	if not command.apply(_campaign):
		_executing_command = false
		return false
	var after: DrawingHistoryContext = _capture_context(command.map_id, command.floor_id)
	_append_applied(command, before, after, true)
	_remember_revisions(command)
	if command is AtlasAssetRebind:
		# Save As creates a durable B that survives undoing only its binding.
		_external_revision += 1
		_emit_changed()
	_executing_command = false
	return true


## Use this entry point for one pinned DrawingEditSession. Never call execute()
## after the gesture: its canonical pixels have *already* been committed.
func commit_drawing(session: DrawingEditSession, before: DrawingHistoryContext,
		after: DrawingHistoryContext) -> DrawingResult:
	if _replaying or _timeline_reserved() or _campaign == null or session == null or session.document == null \
			or before == null or after == null or before.map_id.is_empty() \
			or before.document_id != session.document.id or after.document_id != before.document_id \
			or not session.document.external_history or _campaign.get_map(before.map_id) == null \
			or not _revision_valid(session.document):
		return DrawingResult.failure("HISTORY_CONTEXT", "Invalid drawing origin or external history owner")
	_committing_drawing = true
	var result: DrawingResult = session.commit()
	if not result.ok:
		_committing_drawing = false
		return result
	var command: AtlasDrawingEdit = AtlasDrawingEdit.new(session.document, result.delta,
		before, after, result.regions)
	# The complete host append and revision-ledger update form one reserved
	# boundary, including callbacks from the changed signal.
	_append_applied(command, before, after, true)
	_remember_revisions(command)
	_committing_drawing = false
	return result


## Atomic across the two documents from Atlas's chronological point of view.
func execute_drawing_transfer(command: AtlasDrawingTransfer) -> bool:
	if _replaying or _timeline_reserved() or _campaign == null or command == null or command.map_id.is_empty() \
			or _campaign.get_map(command.map_id) == null or not _revisions_valid(command):
		return false
	_executing_command = true
	if not command.apply(_campaign):
		_executing_command = false
		return false
	_append_applied(command, command.before_context, command.after_context, true)
	_remember_revisions(command)
	_executing_command = false
	return true


func execute_asset_rebind(command: AtlasAssetRebind) -> bool:
	if _replaying or _timeline_reserved() or _campaign == null or command == null or command.map_id.is_empty() \
			or _campaign.get_map(command.map_id) == null:
		return false
	_executing_command = true
	if not command.apply(_campaign):
		_executing_command = false
		return false
	_append_applied(command, command.before_context, command.after_context, true)
	# Saved B is independently durable. Undo binding never clears this dirty bit.
	_external_revision += 1
	_emit_changed()
	_executing_command = false
	return true


func record_selection_change(before: DrawingHistoryContext,
		after: DrawingHistoryContext) -> bool:
	if _replaying or _timeline_reserved() or _campaign == null or not record_selection_history or before == null \
			or after == null or before.same_selection(after) \
			or _campaign.get_map(before.map_id) == null:
		return false
	var command: AtlasSelectionEdit = AtlasSelectionEdit.new(before, after)
	_append_applied(command, before, after, false)
	return true



## The timeline is the revision authority for edits performed through its entry
## points. Check before any mutation: unexpected external changes are rejected.
func _drawing_documents(command: AtlasEditCommand) -> Array[DrawingDocument]:
	var documents: Array[DrawingDocument] = []
	if command is AtlasDrawingEdit:
		var edit: AtlasDrawingEdit = command as AtlasDrawingEdit
		if edit.document != null:
			documents.append(edit.document)
	elif command is AtlasDrawingTransfer:
		var transfer: AtlasDrawingTransfer = command as AtlasDrawingTransfer
		if transfer.source != null:
			documents.append(transfer.source)
		if transfer.target != null and transfer.target != transfer.source:
			documents.append(transfer.target)
	return documents


func _revision_valid(document: DrawingDocument) -> bool:
	var instance: int = document.get_instance_id()
	return not _drawing_revisions.has(instance) or _drawing_revisions[instance] == document.revision


func _revisions_valid(command: AtlasEditCommand) -> bool:
	for document: DrawingDocument in _drawing_documents(command):
		if not _revision_valid(document):
			return false
	return true


func _remember_revisions(command: AtlasEditCommand) -> void:
	for document: DrawingDocument in _drawing_documents(command):
		_drawing_revisions[document.get_instance_id()] = document.revision


## Rebase an old command only after checking the coordinator's live revision.
## The command still compares every touched pixel against its captured delta.
func _prepare_replay(command: AtlasEditCommand) -> bool:
	if not _revisions_valid(command):
		return false
	if command is AtlasDrawingEdit:
		(command as AtlasDrawingEdit).expect_live_revision()
	elif command is AtlasDrawingTransfer:
		(command as AtlasDrawingTransfer).expect_live_revisions()
	return true

func _capture_context(map: String, floor: String) -> DrawingHistoryContext:
	var context: DrawingHistoryContext = null
	if context_provider.is_valid():
		context = context_provider.call() as DrawingHistoryContext
	if context == null:
		context = DrawingHistoryContext.new()
	context = context.detached_copy()
	context.map_id = map
	if context.floor_group_id.is_empty():
		context.floor_group_id = floor
	return context


func _append_applied(command: AtlasEditCommand, before: DrawingHistoryContext,
		after: DrawingHistoryContext, content_change: bool) -> void:
	_discard_redo()
	_commands.append(command)
	_contexts_before.append(before.detached_copy())
	_contexts_after.append(after.detached_copy())
	_cursor += 1
	if content_change:
		_next_state += 1
		_states.append(_next_state)
	else:
		_states.append(_states[_cursor - 1])
	_emit_changed()


func undo() -> bool:
	if _replaying or _timeline_reserved() or not can_undo():
		return false
	_replaying = true
	var command: AtlasEditCommand = _commands[_cursor - 1]
	if not _prepare_replay(command) or not command.revert(_campaign):
		_replaying = false
		return false
	_remember_revisions(command)
	_cursor -= 1
	_restore(_contexts_before[_cursor], command)
	_replaying = false
	_emit_changed()
	return true


func redo() -> bool:
	if _replaying or _timeline_reserved() or not can_redo():
		return false
	_replaying = true
	var command: AtlasEditCommand = _commands[_cursor]
	if not _prepare_replay(command) or not command.apply(_campaign):
		_replaying = false
		return false
	_remember_revisions(command)
	_restore(_contexts_after[_cursor], command)
	_cursor += 1
	_replaying = false
	_emit_changed()
	return true


func _restore(context: DrawingHistoryContext, command: AtlasEditCommand) -> void:
	last_playback_warning = ""
	last_playback_context = context.detached_copy()
	var regions: Array[DrawingDirtyRegion] = []
	if command is AtlasDrawingEdit:
		regions = (command as AtlasDrawingEdit).dirty_regions
	if context_restorer.is_valid() and not bool(context_restorer.call(last_playback_context, regions)):
		last_playback_warning = "History changed the artwork, but its original view/selection is unavailable."
		restoration_warning.emit(last_playback_warning)


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
	if _timeline_reserved() or _replaying:
		return
	_saved_state = _states[_cursor]
	_saved_external_revision = _external_revision
	_emit_changed()


func mark_external_change() -> void:
	if _timeline_reserved() or _replaying:
		return
	# External metadata edits are dirty even when not represented by commands.
	_discard_redo()
	_external_revision += 1
	_emit_changed()


func _discard_redo() -> void:
	_commands.resize(_cursor)
	_contexts_before.resize(_cursor)
	_contexts_after.resize(_cursor)
	_states.resize(_cursor + 1)
