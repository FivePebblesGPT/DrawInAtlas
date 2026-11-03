extends SceneTree
## T-064: the Atlas File menu exposes an explicitly saved, independent project
## copy. No dirty drafts are serialized and neither source nor open view changes.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_COPY_UI_FAILED: " + name)


func _source() -> DrawingDocument:
	var source: DrawingDocument = DrawingDocument.new("Reusable", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixel").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	edit.fill_rect(Rect2i(-3, 5, 1, 1), 0xff22eeff)
	edit.commit()
	return source


func _run() -> void:
	var parent: String = OS.get_cache_dir().path_join("t064-copy-ui-" + DrawingDocument.new_id())
	var original_dir: String = parent.path_join("original")
	var source_path: String = original_dir.path_join("World.scn")
	_check(DirAccess.make_dir_recursive_absolute(original_dir) == OK, "create source project directory")
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	var chrome: Control = scene.get_node("Interface/UI")
	editor.save_path = source_path
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(scene)
	if OS.get_environment("T064_COPY_UI_NARROW") == "1":
		root.size = Vector2i(420, 600)
	for index: int in range(5):
		await process_frame
	_check(editor._campaign_copy_dialog != null and editor._campaign_copy_parent_picker != null,
		"copy dialog and filesystem directory chooser are mounted in Atlas workspace")
	_check(editor._campaign_copy_dialog.get_ok_button().text == "Copy",
		"confirmation explicitly identifies the copy action")
	_check(editor._campaign_copy_parent_picker.file_mode == FileDialog.FILE_MODE_OPEN_DIR and \
		editor._campaign_copy_parent_picker.access == FileDialog.ACCESS_FILESYSTEM,
		"directory chooser selects existing destination parent rather than a precreated project")
	var menu: PopupMenu = chrome.get_node("Chrome/Layout/MenuBar/File")
	var action: int = menu.get_item_id(menu.item_count - 3)
	_check(action == 4 and menu.get_item_text(menu.item_count - 3).contains("Copy saved campaign"),
		"File menu exposes project-copy command apart from regular Save/Load")
	editor._request_campaign_copy()
	_check(not editor._campaign_copy_dialog.visible and editor.status_label.text.contains("Save the campaign"),
		"unsaved new campaign cannot be copied as if saved")
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var a: DrawingResult = library.create_asset(_source(), "Parent")
	var b: DrawingResult = library.create_asset(_source(), "Nested")
	_check(a.ok and b.ok, "publish test assets in original campaign registry")
	if not a.ok or not b.ok:
		quit(1)
		return
	var linked: DrawingResult = library.attach_child(str(a.value), 0, str(b.value),
		Transform2D(0.0, Vector2(-8, 2)))
	_check(linked.ok, "persist nested child source under original parent")
	editor._on_save()
	_check(editor.status_label.text.contains("Saved generation") and editor._campaign_copy_is_saved(),
		"save publishes authoritative source campaign generation")
	var root_file: String = AtlasCampaignBundle.root_path(source_path)
	var source_hash: String = FileAccess.get_sha256(root_file)
	chrome._on_file_menu(4)
	_check(editor._campaign_copy_dialog.visible and editor._campaign_copy_parent.text == parent,
		"File menu routes to copy dialog with source's sibling directory")
	_check(editor._campaign_copy_folder.text == "original-copy" and \
		editor._campaign_copy_filename.text == "World.scn",
		"dialog seeds a fresh project name without mutating the source")
	if not OS.get_environment("T064_COPY_UI_SCREENSHOT").is_empty():
		await process_frame
		await process_frame
		var screenshot: String = OS.get_environment("T064_COPY_UI_SCREENSHOT")
		var captured: Error = scene.get_viewport().get_texture().get_image().save_png(screenshot)
		_check(captured == OK, "native dialog screenshot captured")
	editor._on_campaign_copy_parent_selected(parent)
	_check(editor._campaign_copy_parent.text == parent, "filesystem directory picker writes selected parent")
	for invalid: String in ["", "..", "../escape", "nested/folder", "other\\folder"]:
		editor._campaign_copy_folder.text = invalid
		_check(not editor._campaign_copy_destination().ok, "reject unsafe folder component: " + invalid)
	editor._campaign_copy_folder.text = "renamed"
	for invalid: String in ["", "x.txt", "../escape.scn", "foo/bar.scn", "dir\\file.scn"]:
		editor._campaign_copy_filename.text = invalid
		_check(not editor._campaign_copy_destination().ok, "reject unsafe campaign filename: " + invalid)
	editor._campaign_copy_filename.text = "NewWorld.scn"
	editor._campaign_copy_parent.text = "relative/path"
	_check(not editor._campaign_copy_destination().ok, "parent must be absolute and canonical")
	editor._campaign_copy_parent.text = parent
	var cloned_path: String = parent.path_join("renamed/NewWorld.scn")
	_check(str(editor._campaign_copy_destination().value) == cloned_path,
		"choose renamed folder and new campaign root filename")
	var pending_dest: String = parent.path_join("not-copied")
	editor._campaign_copy_folder.text = "not-copied"
	editor.edits.mark_external_change()
	editor._confirm_campaign_copy()
	_check(not DirAccess.dir_exists_absolute(pending_dest) and \
		editor.status_label.text.contains("Save all edits"),
		"dirty Atlas history prevents copying even after dialog is already open")
	editor._on_save()
	_check(editor._campaign_copy_is_saved(), "new checkpoint resolves dirty history")
	var first_doc: DrawingDocument = editor.drawing_composition.registry.document_at(
		"world", "ground", 0, true).value
	var layer: String = str(first_doc.create_layer(DrawingLayerNode.RASTER, "Pending").value)
	var edit: DrawingEditSession = first_doc.begin_edit(layer, first_doc.revision).value
	edit.fill_rect(Rect2i(4, 4, 1, 1), 0xffaa22ff)
	edit.commit()
	_check(first_doc.is_dirty(), "Drawing document holds unsaved canonical changes")
	editor._request_campaign_copy()
	_check(editor.status_label.text.contains("Save the campaign") and \
		not DirAccess.dir_exists_absolute(pending_dest),
		"dirty Drawing source is never silently copied")
	editor._on_save()
	var before_copy_hash: String = FileAccess.get_sha256(root_file)
	editor._campaign_copy_folder.text = "renamed"
	editor._campaign_copy_filename.text = "NewWorld.scn"
	editor._confirm_campaign_copy()
	_check(editor.status_label.text.contains("Copied saved campaign") and \
		DirAccess.dir_exists_absolute(cloned_path.get_base_dir()),
		"confirmation publishes new directory and reports success")
	_check(editor.save_path == source_path and editor.campaign != null and \
		FileAccess.get_sha256(root_file) == before_copy_hash,
		"source path, active campaign, and original root remain unchanged")
	var cloned: AtlasStoreResult = AtlasCampaignStore.load_portable_result(cloned_path)
	_check(cloned.error == OK and cloned.library != null,
		"renamed copy loads as an independent T-066 portable campaign")
	if cloned.library != null:
		var children: Array[Dictionary] = cloned.library.children_for_asset(str(a.value))
		_check(children.size() == 1 and children[0]["source_id"] == str(b.value) and \
			cloned.library.asset_exists(str(b.value)),
			"copy retains published nested child identity and source artwork")
	var copy_doc: DrawingResult = cloned.registry.document_at("world", "ground", 0)
	_check(copy_doc.ok and copy_doc.value.has_node(layer) and \
		int(copy_doc.value.read_pixel(layer, 4, 4).value) == 0xffaa22ff,
		"copy includes latest fully published Drawing pixels")
	editor._confirm_campaign_copy()
	_check(editor.status_label.text.contains("COPY_EXISTS") and \
		FileAccess.get_sha256(root_file) == before_copy_hash,
		"repeating copy refuses destination collision without overwriting either project")
	# A separate Object Editor has its own dirty draft, independent of Atlas history.
	editor._open_object_source(str(a.value))
	_check(editor.object_editor_window != null and \
		editor.object_editor_window.workspace.tabs.size() == 1,
		"independent Object Editor tab opens published parent source")
	var draft: DrawingObjectEditorSession = editor.object_editor_window.workspace.tabs[0].get("object")
	_check(draft != null and draft.set_name("Unsaved parent edit").ok and draft.is_dirty(),
		"Object Editor draft changes remain private and dirty")
	editor._request_campaign_copy()
	_check(editor.status_label.text.contains("Save the campaign") and \
		FileAccess.get_sha256(root_file) == before_copy_hash,
		"Object Editor dirty draft independently blocks saved project copy")
	editor.object_editor_window.queue_free()
	editor.object_editor_window = null
	await process_frame
	# Dialog cancellation must not perform a filesystem write.
	editor._request_campaign_copy()
	editor._campaign_copy_folder.text = "cancelled"
	editor._campaign_copy_dialog.hide()
	_check(not DirAccess.dir_exists_absolute(parent.path_join("cancelled")),
		"cancelling dialog has no destination side effects")
	# Keyboard mapping must open the copy command, not save over the current root.
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.pressed = true
	shortcut.keycode = KEY_S
	shortcut.ctrl_pressed = true
	shortcut.shift_pressed = true
	editor._unhandled_key_input(shortcut)
	_check(editor._campaign_copy_dialog.visible and \
		FileAccess.get_sha256(root_file) == before_copy_hash,
		"Ctrl+Shift+S routes to copy dialogue without invoking Save")
	print("T064_COPY_UI_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
