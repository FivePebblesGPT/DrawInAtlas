extends "res://drawing/tests/t309_window_panels_native.gd"
## Real hosted Object Editor menu and private artwork/Atlas state isolation.

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T309_ATLAS_FAILED: " + description)

func menu_label(app: Control, label: String) -> String:
	return label if app.top_bar._menus[7].visible else "Window › " + label

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t309-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t309-atlas-source", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-16, -12, 32, 24), 0xffdc5b1a).ok and edit.commit().ok, "published pixel fixture")
	var created: DrawingResult = library.create_asset(source, "Panel witness")
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
	check(window != null and window.visible, "real hosted editor opens")
	if window == null or not window.visible:
		quit(1)
		return
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	await frames(12)
	var layout: DrawingDockLayout = app.dock_layout
	var doc: DrawingDocument = app.current_document()
	var rev: int = doc.revision
	var history: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	check(layout.merge_groups("layers", "colors", 1) and layout.merge_groups("text_options", "colors", 2), "hosted group includes hidden Text Options peer")
	app._render_dock()
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "float hosted group")
	if host_id.is_empty():
		quit(1)
		return
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	await frames(8)
	await click(window, (host.get_node("FloatingColumn/FloatingTitleBar/HideHost") as Button).get_global_rect().get_center())
	check(not host.visible and not checked(window_popup(app), "Colors") and not checked(window_popup(app), "Layers"), "native close updates menu")
	var popup: PopupMenu = await open_window_menu(app, window)
	await invoke_key(popup, menu_label(app, "Layers"))
	check(host.visible and host.tab_buttons.keys() == ["layers"], "only Layers restored in hosted group")
	check(not checked(window_popup(app), "Colors") and not checked(window_popup(app), "Text Options"), "unrelated peers remain hidden")
	popup = await open_window_menu(app, window)
	await invoke_key(popup, menu_label(app, "Text Options"))
	check(host.tab_buttons.keys() == ["layers", "text_options"] and host.is_ancestor_of(app.text_panel), "Text Options individually restored to original host")
	check(not app.text_edit.editable and not checked(window_popup(app), "Colors"), "no implicit draft or restoration of Colors")
	check(layout.owner_of("text_options") == host_id and layout.owner_of("colors") == host_id, "all original ownership preserved")
	popup = await open_window_menu(app, window)
	await screenshot("window-atlas")
	popup.hide()
	check(doc.revision == rev and doc.history_length() == history and doc.is_dirty() == dirty, "private native artwork unchanged")
	check(FileAccess.get_sha256(path) == digest and editor.edits.can_undo() == atlas_undo and editor.edits.is_dirty() == atlas_dirty, "registry source and Atlas history unchanged")
	print("T309_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T309_ATLAS_PASSED")
	quit(1 if failures else 0)
