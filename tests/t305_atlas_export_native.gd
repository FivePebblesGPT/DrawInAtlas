extends "res://drawing/tests/t305_export_native.gd"
## Real Atlas host: finite private Object frame exports without source publication.

func delete_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for folder: String in dir.get_directories():
		delete_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "native display and tiles required")
		quit(1)
		return
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t305-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t305-object", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	fill(source, layer, Rect2i(-2, -1, 4, 2), 0x8000aaff)
	var created: DrawingResult = library.create_asset(source, "Export object")
	check(created.ok, "Atlas publishes fixture")
	if not created.ok:
		quit(1)
		return
	var source_id: String = str(created.value)
	var source_path: String = library._absolute(str(library.asset_info(source_id)["path"]))
	var digest: String = FileAccess.get_sha256(source_path)
	var old_undo: bool = editor.edits.can_undo()
	var old_dirty: bool = editor.edits.is_dirty()
	editor._open_object_source(source_id)
	var window: AtlasObjectEditorWindow = editor.object_editor_window
	check(window != null and window.visible, "actual Atlas Object Editor opens")
	if window == null or not window.visible:
		quit(1)
		return
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	await frames(12)
	var session: DrawingObjectEditorSession = app.current_object()
	check(session.set_frame(Vector2i(3, -4), Rect2i()).ok, "unrestricted Object has no finite frame")
	app._ask_export()
	check(not app.export_dialog.visible and app.status.text.contains("non-empty frame"), "unrestricted Object needs finite frame")
	var bounds: Rect2i = Rect2i(-4, -3, 8, 6)
	check(session.set_frame(Vector2i(3, -4), bounds).ok, "private signed Object frame defined")
	var draft: DrawingDocument = app.current_document()
	fill(draft, app.current_layer(), Rect2i(-1, 0, 1, 1), 0xff1144cc)
	var revision: int = draft.revision
	var history: int = draft.history_length()
	var dirty: bool = session.is_dirty()
	var source_revision: int = session.source_revision
	await open_export(app, window)
	var dialog: DrawingExportDialog = app.export_dialog
	if not dialog.visible:
		quit(1)
		return
	check(not app.status.text.begins_with("Error:"), "valid Export clears preceding bounds error")
	check(dialog.source.get_size() == bounds.size and dialog.source.get_data().decode_u32((2 * 8 + 2) * 4) == 0x8000aaff, "Object output is local frame, independent of instance anchor")
	dialog.refresh_preview()
	var bytes: PackedByteArray = dialog.encoded
	await frames()
	await screenshot("export-atlas")
	await choose_path(app, folder, "object.png")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_ok_button())
	var output: String = folder.path_join("object.png")
	check(FileAccess.file_exists(output) and FileAccess.get_file_as_bytes(output) == bytes, "hosted chooser publishes standalone raster bytes")
	check(app.current_object() == session and draft.revision == revision and draft.history_length() == history and session.source_revision == source_revision and session.is_dirty() == dirty, "private draft history, dirty flag, source identity and source revision preserved")
	check(FileAccess.get_sha256(source_path) == digest and editor.edits.can_undo() == old_undo and editor.edits.is_dirty() == old_dirty, "Atlas source bytes and campaign history unchanged")
	print("T305_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T305_ATLAS_PASSED")
	root.remove_child(scene)
	scene.free()
	delete_tree(folder)
	quit(1 if failures else 0)
