extends "res://drawing/tests/t311_layer_disclosure_native.gd"
## Native hosted Object Editor disclosure must remain private view state.

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T311_ATLAS_FAILED: " + description)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t311-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t311-atlas-source", 16)
	var outer: String = str(source.create_layer(DrawingLayerNode.GROUP, "Landmark").value)
	var inner: String = str(source.create_layer(DrawingLayerNode.GROUP, "Details", outer).value)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Paint", inner).value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-16, -12, 32, 24), 0xffdc5b1a).ok and edit.commit().ok, "signed published pixel fixture")
	var created: DrawingResult = library.create_asset(source, "Layer witness")
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
	check(window != null and window.visible, "actual hosted Object Editor opens")
	if window == null or not window.visible:
		quit(1)
		return
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.dock_layout.move_group("layers", "right", 0)
	app._render_dock()
	await frames(10)
	var doc: DrawingDocument = app.current_document()
	# Registry publication may remap IDs. Inspect the opened private draft.
	layer = app.current_layer()
	inner = String(doc.node_metadata(layer).get("parent", ""))
	outer = String(doc.node_metadata(inner).get("parent", ""))
	check(doc.node_metadata(layer).get("name") == "Paint" and doc.node_metadata(inner).get("name") == "Details" and doc.node_metadata(outer).get("name") == "Landmark", "published hierarchy restored in draft")
	if failures:
		quit(1)
		return
	var rev: int = doc.revision
	var history: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	var row: TreeItem = find_row(app.layers, layer)
	check(row != null and row.get_parent() == find_row(app.layers, inner), "hosted actual nested TreeItems")
	if failures:
		quit(1)
		return
	await click_fold(app, inner, window)
	check(find_row(app.layers, inner).collapsed and find_row(app.layers, layer) == null and app.current_layer().is_empty(), "hosted native collapse removes child and paint target")
	await screenshot("layers-atlas", window)
	await click_fold(app, outer, window)
	check(find_row(app.layers, outer).collapsed and find_row(app.layers, inner) == null, "hosted outer disclosure")
	await click_fold(app, outer, window)
	check(find_row(app.layers, inner).collapsed and find_row(app.layers, layer) == null, "nested state survives parent expand")
	await click_fold(app, inner, window)
	await click_row(app, layer, -1, window)
	check(app.current_layer() == layer and int(doc.read_pixel(layer, -16, -12).value) == 0xffdc5b1a, "hosted reopened row selectable and exact pixels retained")
	check(doc.revision == rev and doc.history_length() == history and doc.is_dirty() == dirty, "disclosure preserves private artwork and history")
	check(FileAccess.get_sha256(path) == digest and editor.edits.can_undo() == atlas_undo and editor.edits.is_dirty() == atlas_dirty, "registry source and Atlas history unchanged")
	print("T311_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T311_ATLAS_PASSED")
	root.remove_child(scene)
	scene.free()
	quit(1 if failures else 0)
