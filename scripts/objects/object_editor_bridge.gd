class_name AtlasObjectEditorBridge
extends RefCounted
## Atlas-owned publisher for DrawingObjectEditorSession. This never paints;
## all raster/text/group operations stay with the Drawing document.

var library: AtlasObjectLibrary
var timeline: AtlasEditHistory
## Returns the actual current Atlas context, never one supplied by the tab.
var context_provider: Callable
var _drafts: Dictionary[int, AtlasObjectDraft] = {}
var _entry_contexts: Dictionary[int, DrawingHistoryContext] = {}


func _init(asset_library: AtlasObjectLibrary = null,
		global_history: AtlasEditHistory = null,
		current_context: Callable = Callable()) -> void:
	library = asset_library
	timeline = global_history
	context_provider = current_context


func open_source(asset_id: String) -> DrawingResult:
	return _open(asset_id, "")


func open_from_instance(instance_id: String) -> DrawingResult:
	if library == null:
		return DrawingResult.failure("LIBRARY", "Object registry is unavailable")
	var placement: Dictionary = library.instance_info(instance_id)
	if placement.is_empty() or placement.get("status") != "linked":
		return DrawingResult.failure("INSTANCE", "Instance has no editable linked source")
	return _open(String(placement["source_id"]), instance_id)


func _open(asset_id: String, instance_id: String) -> DrawingResult:
	if library == null:
		return DrawingResult.failure("LIBRARY", "Object registry is unavailable")
	var origin: DrawingHistoryContext
	if not instance_id.is_empty():
		origin = _live_context()
		var placement: Dictionary = library.instance_info(instance_id)
		if origin == null or placement.is_empty() or \
				origin.selected_instance_id != instance_id or \
				origin.map_id != placement["map_id"] or \
				origin.floor_group_id != placement["floor_id"] or \
				origin.detail_group_id != placement["detail_id"] or \
				origin.asset_id != asset_id:
			return DrawingResult.failure("CONTEXT", "Select the linked instance before editing its source")
	var opened: DrawingResult = library.begin_draft(asset_id, instance_id)
	if not opened.ok:
		return opened
	var draft: AtlasObjectDraft = opened.value
	var session: DrawingObjectEditorSession = DrawingObjectEditorSession.new(
		draft.document, draft.source_id, draft.source_revision, draft.name,
		instance_id, origin.map_id if origin != null else "", draft.origin, draft.bounds)
	var key: int = session.get_instance_id()
	_drafts[key] = draft
	if origin != null:
		_entry_contexts[key] = origin.detached_copy()
	session.save_publisher = _save.bind(key)
	session.save_as_publisher = _save_as.bind(key)
	return DrawingResult.success(session)


func _live_context() -> DrawingHistoryContext:
	if not context_provider.is_valid():
		return null
	var value: Variant = context_provider.call()
	return value if value is DrawingHistoryContext else null


## Closing a tab releases the captured origin; no draft is ever published by
## close/discard. A later Save cannot reuse an invalidated editing context.
func release(session: DrawingObjectEditorSession) -> void:
	if session == null:
		return
	var key: int = session.get_instance_id()
	_drafts.erase(key)
	_entry_contexts.erase(key)
	session.save_publisher = Callable()
	session.save_as_publisher = Callable()


func _draft_for(session: DrawingObjectEditorSession, key: int) -> AtlasObjectDraft:
	if session == null or not _drafts.has(key) or session.get_instance_id() != key:
		return null
	var draft: AtlasObjectDraft = _drafts[key]
	if draft.document != session.document or draft.source_id != session.source_id or \
			draft.source_revision != session.source_revision:
		return null
	return draft


func _origin_valid(key: int, draft: AtlasObjectDraft) -> bool:
	if draft.origin_instance_id.is_empty():
		return true
	if not _entry_contexts.has(key):
		return false
	var entry: DrawingHistoryContext = _entry_contexts[key]
	var current: DrawingHistoryContext = _live_context()
	if current == null or current.map_id != entry.map_id or \
			current.floor_group_id != entry.floor_group_id or \
			current.detail_group_id != entry.detail_group_id or \
			current.selected_instance_id != entry.selected_instance_id or \
			current.asset_id != entry.asset_id:
		return false
	var placement: Dictionary = library.instance_info(draft.origin_instance_id)
	return not placement.is_empty() and placement.get("generation") == draft.origin_generation \
		and placement.get("revision") == draft.origin_binding_revision \
		and placement.get("source_id") == draft.source_id and placement.get("status") == "linked"


func _snapshot(draft: AtlasObjectDraft, independent_variant: bool = false) -> DrawingResult:
	return DrawingResult.success({"document": draft.document, "source_id": draft.source_id,
		"source_revision": draft.source_revision, "name": draft.name,
		"origin": draft.origin, "bounds": draft.bounds,
		"detach_origin": independent_variant})


func _save(session: DrawingObjectEditorSession, key: int) -> DrawingResult:
	var draft: AtlasObjectDraft = _draft_for(session, key)
	if draft == null or not _origin_valid(key, draft):
		return DrawingResult.failure("STALE_CONTEXT", "Source or captured instance changed; reopen the editor")
	draft.name = session.name
	draft.origin = session.origin
	draft.bounds = session.bounds
	var saved: DrawingResult = library.save_draft(draft)
	return _snapshot(draft) if saved.ok else saved


func _save_as(session: DrawingObjectEditorSession, key: int) -> DrawingResult:
	var draft: AtlasObjectDraft = _draft_for(session, key)
	if draft == null or not _origin_valid(key, draft):
		return DrawingResult.failure("STALE_CONTEXT", "Source or captured instance changed; reopen the editor")
	draft.name = session.name
	draft.origin = session.origin
	draft.bounds = session.bounds
	var saved: DrawingResult
	var through_instance: bool = not draft.origin_instance_id.is_empty()
	if through_instance:
		if timeline == null:
			return DrawingResult.failure("HISTORY", "Global history is required for an instance Save As")
		var before: DrawingHistoryContext = (_entry_contexts[key] as DrawingHistoryContext).detached_copy()
		var after: DrawingHistoryContext = before.detached_copy()
		after.editor_mode = "ObjectEditor"
		saved = library.save_as(draft, timeline, before, after, session.variant_name)
	else:
		saved = library.save_as(draft, null, null, null, session.variant_name)
	if not saved.ok:
		return saved
	_entry_contexts.erase(key)
	return _snapshot(draft, true)
