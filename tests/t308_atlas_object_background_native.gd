extends "res://drawing/tests/t304_selection_menu_native.gd"

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T308_ATLAS_FAILED: " + description)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t308-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t308-atlas-source", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-18, -12, 36, 24), 0xffdc5b1a).ok and edit.commit().ok, "paint source fixture")
	var created: DrawingResult = library.create_asset(source, "Atlas Object")
	check(created.ok, "publish registry-owned asset")
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
	check(window != null and window.visible, "actual hosted Object Editor opens")
	if window == null or not window.visible:
		quit(1)
		return
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	await frames(12)
	var canvas: Control = app.canvas
	canvas.camera = Vector2.ZERO
	canvas.zoom = 3.0
	canvas.show_grid = false
	canvas.show_pixel_grid = false
	canvas.queue_redraw()
	await frames(8)
	check(canvas.object_backdrop, "hosted Object checker restored")
	var frame: Image = window.get_texture().get_image()
	var p: Vector2i = Vector2i(canvas.global_position + Vector2(20, 20))
	check(frame.get_pixelv(p) != frame.get_pixelv(p + Vector2i(16, 0)), "actual transparent framebuffer alternates checker pixels")
	var directory: String = OS.get_environment("T308_SCREENSHOTS")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		frame.save_png(directory.path_join("object-atlas.png"))
	var local_root: String = folder.path_join("Local/Objects")
	DirAccess.make_dir_recursive_absolute(local_root)
	var local_path: String = local_root.path_join("portable.drawing")
	check(DrawingObjectEditorFile.save(source, local_path, "Portable Object", Vector2i.ZERO, Rect2i(), 1).ok, "standalone source fixture")
	check(app.show_asset_browser(local_root), "explicit local catalog selectable")
	await frames(8)
	var token: Dictionary = app.asset_browser._drag_entry_for_row(0)
	var doc: DrawingDocument = app.current_document()
	var rev: int = doc.revision
	check(not token.is_empty() and not app._check_object_drop(token, Vector2i.ZERO).has_area(), "standalone drop cannot bypass registry-owned Object Editor")
	check(doc.revision == rev and FileAccess.get_sha256(source_path) == digest and editor.edits.can_undo() == old_undo and editor.edits.is_dirty() == old_dirty, "background and rejection preserve source and Atlas history")
	var index: DrawingAssetBrowserIndex = DrawingAssetBrowserIndex.new()
	check(index.scan(local_root).ok, "local catalog authorization")
	var linked: DrawingDocument = DrawingDocument.new("standalone-link")
	check(linked.commit_linked_object(token, index, Vector2i.ZERO, DrawingDocument.ROOT_ID, 0, linked.revision).ok, "standalone model link fixture")
	check(not library.create_asset(linked, "Invalid registry import").ok, "registry rejects implicit standalone graph import")
	print("T308_ATLAS: %d passed; %d failed" % [checks - failures, failures])
	if failures == 0:
		print("T308_ATLAS_PASSED")
	quit(1 if failures else 0)
