extends "res://drawing/tests/t312_panel_icons_native.gd"
## Real Atlas Object Editor uses the same icon policy and dock transitions.

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t312-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t312-atlas-source", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Paint").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-16, -12, 32, 24), 0xffdc5b1a).ok and edit.commit().ok, "signed artwork fixture")
	var created: DrawingResult = library.create_asset(source, "Panel icon witness")
	check(created.ok, "registry source created")
	if not created.ok:
		quit(1)
		return
	var source_id: String = str(created.value)
	var path: String = library._absolute(str(library.asset_info(source_id)["path"]))
	var digest: String = FileAccess.get_sha256(path)
	var atlas_undo: bool = editor.edits.can_undo()
	var atlas_dirty: bool = editor.edits.is_dirty()
	editor._open_object_source(source_id)
	var window: AtlasObjectEditorWindow = editor.object_editor_window
	check(window != null and window.visible, "real hosted Object Editor opens")
	if window == null or not window.visible:
		quit(1)
		return
	window.size = Vector2i(1280, 840)
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	await frames(12)
	await exercise(app, window, "atlas")
	check(FileAccess.get_sha256(path) == digest and editor.edits.can_undo() == atlas_undo and editor.edits.is_dirty() == atlas_dirty, "registry source and Atlas history unchanged")
	print("T312_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T312_ATLAS_PASSED")
	root.remove_child(scene)
	scene.free()
	quit(1 if failures else 0)
