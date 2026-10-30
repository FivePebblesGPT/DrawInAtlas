extends SceneTree
## T-018: native density and discoverability witness at normal/compact widths.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("HIERARCHY VISUAL FAILED: " + message)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "native renderer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(10)
	editor.sidebar.select_view(&"Layers")
	var panel: AtlasLayerPanel = editor.layer_panel
	await _frames(7)
	_check(panel.hierarchy.visible and panel.hierarchy.size.y >= 160.0,
		"real tree has adequate scannable height")
	_check(editor.canvas.size.x >= 394.0, "960-pixel canvas keeps T-007 clearance")
	_check(panel.hierarchy.global_position.x + panel.hierarchy.size.x <= editor.canvas.global_position.x,
		"hierarchy is confined to sidebar")
	_check(not panel.name_input.visible, "metadata controls don't crowd default hierarchy")
	_check(panel.hierarchy.get_root().get_child_count() >= 2, "detail and navigation groups drawn")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(root.get_texture().get_image().save_png("user://validation/layer-hierarchy-960.png") == OK,
		"native normal-width screenshot")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(9)
	_check(editor.canvas.size.x >= 234.0, "compact width preserves canvas area")
	_check(panel.hierarchy.size.x > 80.0, "tree retains usable horizontal width")
	_check(root.get_texture().get_image().save_png("user://validation/layer-hierarchy-800.png") == OK,
		"native compact-width screenshot")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_LAYER_HIERARCHY_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
