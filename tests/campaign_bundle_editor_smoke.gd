extends SceneTree
## T-066: real AtlasEditor Save/Load invokes the portable generation boundary.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T066_EDITOR_FAILED: " + label)


func _open(path: String, load_existing: bool) -> Node:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.save_path = path
	editor.load_saved_on_startup = load_existing
	editor.use_system_clipboard = false
	root.add_child(scene)
	for i: int in range(5):
		await process_frame
	return scene


func _run() -> void:
	var path: String = OS.get_cache_dir().path_join("t066-editor-" + DrawingDocument.new_id()).path_join("Campaign.scn")
	var first: Node = await _open(path, false)
	var editor: AtlasEditor = first.get_node("Interface/UI/WorkspaceSplit/Workspace")
	_check(editor.drawing_composition != null, "editor mounts canonical composition")
	var adapter: AtlasDrawingComposition = editor.drawing_composition
	var painted: DrawingResult = adapter.start_stroke("world", "ground", 0, Vector2(-3, -4),
		0xff112233, 1.5)
	_check(painted.ok and adapter.finish_stroke().ok, "live Atlas edit committed before Save")
	var first_doc: DrawingDocument = adapter.registry.document_at("world", "ground", 0).value
	var layer: String = first_doc.list_children()[0]
	_check(first_doc.is_dirty(), "live authored Drawing is dirty before save")
	editor._on_save()
	_check(editor.status_label.text.contains("Saved generation"), "Save publishes portable root")
	_check(not first_doc.is_dirty(), "savepoint updated only after generation publication")
	_check(FileAccess.file_exists(AtlasCampaignBundle.root_path(path)), "editor writes portable campaign pointer")
	_check(not FileAccess.file_exists(path), "editor does not create legacy one-file native save")
	var original_color: int = int(first_doc.read_pixel(layer, -3, -4).value)
	_check(original_color != 0, "original painted pixel is present")
	var second: DrawingResult = adapter.start_stroke("world", "ground", 0, Vector2(-3, -4),
		0xffffaa55, 1.5)
	_check(second.ok and adapter.finish_stroke().ok and first_doc.is_dirty(), "next gesture dirties editor")
	editor._on_load()
	_check(editor.status_label.text.contains("confirm discarding") and editor._discard_drawing_dialog.visible,
		"Load warns before replacing uncommitted Drawing pixels")
	_check(editor.drawing_composition.registry.document_at("world", "ground", 0).value == first_doc and first_doc.is_dirty(),
		"Load confirmation preserves current dirty document until accepted")
	# Cancel and reopen the warning: do not accumulate one-shot callbacks.
	editor._discard_drawing_dialog.hide()
	editor._on_load()
	_check(editor._pending_discard_action.is_valid() and editor._discard_drawing_dialog.visible,
		"reopening a cancelled warning keeps one pending action")
	editor._discard_drawing_dialog.hide()
	editor._confirm_drawing_discard()
	_check(not editor._pending_discard_action.is_valid(), "accepting a warning consumes the pending callback")
	_check(editor.status_label.text.contains("Portable campaign generation loaded"), "Confirmed Load selects last committed generation")
	var reloaded: DrawingResult = editor.drawing_composition.registry.document_at("world", "ground", 0)
	_check(reloaded.ok and reloaded.value != first_doc, "loading drops uncommitted previous document")
	if reloaded.ok:
		_check(int(reloaded.value.read_pixel(layer, -3, -4).value) == original_color,
			"load restores exact published pixel, not newer unsaved edit")
	first.queue_free()
	for i: int in range(4):
		await process_frame
	var scene: Node = await _open(path, true)
	var restarted: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	_check(restarted.drawing_composition != null and restarted.campaign != null,
		"fresh editor startup restores portable campaign")
	var reopened: DrawingResult = restarted.drawing_composition.registry.document_at("world", "ground", 0)
	_check(reopened.ok and int(reopened.value.read_pixel(layer, -3, -4).value) == original_color,
		"startup lazily reopens exact Drawing layer")
	_check(restarted.drawing_composition.registry.document_count() == 1,
		"startup only resolves the viewed Drawing document")
	var live_doc: DrawingDocument = reopened.value
	var before_reset: AtlasCampaign = restarted.campaign
	var pending: DrawingResult = restarted.drawing_composition.start_stroke("world", "ground", 0,
		Vector2(9, 11), 0xff556677, 1.0)
	_check(pending.ok and restarted.drawing_composition.finish_stroke().ok and live_doc.is_dirty(),
		"fresh startup can edit a lazily opened Drawing before replacing sample")
	restarted._on_sample()
	_check(restarted.campaign == before_reset and live_doc.is_dirty() and restarted._discard_drawing_dialog.visible,
		"sample reset also waits for confirmation instead of dropping dirty Drawing content")
	restarted._discard_drawing_dialog.hide()
	restarted._on_sample(true)
	restarted._on_save()
	_check(restarted.status_label.text.contains("Saved generation"),
		"new sample intentionally overwrites the loaded root without losing its concurrency lease")
	var reset: AtlasStoreResult = AtlasCampaignBundle.load(path)
	_check(reset.error == OK and reset.registry.projection("world")[0]["details"][0]["blank"],
		"sample reset round-trips as an empty authored Drawing detail")
	scene.queue_free()
	for i: int in range(4):
		await process_frame
	print("ATLAS_BUNDLE_EDITOR_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
