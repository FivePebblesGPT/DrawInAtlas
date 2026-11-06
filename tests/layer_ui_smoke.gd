extends SceneTree

var failures: int = 0


class RecoveryIO extends AtlasStoreIO:
	func decode_scene(bytes: PackedByteArray) -> PackedScene:
		var printed_errors: bool = Engine.print_error_messages
		if bytes == "invalid checkpoint".to_utf8_buffer():
			Engine.print_error_messages = false
		var scene: PackedScene = super.decode_scene(bytes)
		Engine.print_error_messages = printed_errors
		return scene


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("LAYER UI FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = "user://layer-ui-%d.scn" % Time.get_ticks_usec()
	editor.store_io = RecoveryIO.new()
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	# The fixed workspace and reusable panels must come from scene files.
	_check(editor.canvas == editor.get_node("Shell/CanvasAndInspector/Canvas"),
		"the editor uses the scene-owned canvas")
	_check(editor.board_dialog.grid_controls ==
		editor.board_dialog.get_node("Scroll/Margin/Form/GridControls"),
		"board creation uses the embedded grid form scene")
	_check(editor.grid_controls.distance_spinner ==
		editor.grid_controls.get_node("DistanceRow/DistanceSpinner"),
		"popup grid form binds its scene controls")
	_check(editor.layer_panel.layer_list == editor.layer_panel.get_node("LayerList"),
		"layer panel binds its scene controls")
	_check(editor.overview_panel.preview == editor.overview_panel.get_node("Preview"),
		"overview embeds its preview panel")
	_check(editor.map_preview.texture_rect == editor.map_preview.get_node("TextureRect"),
		"map preview binds its scene texture display")

	_check_wrapped_labels(scene)

	var floor: AtlasFloor = editor.canvas.floor
	var basis: PackedVector2Array = editor.canvas.map.grid.cell_polygon(Vector2i.ZERO)
	var overlay: AtlasGrid = editor.canvas.map.grid.copy()
	overlay.cell_size = 90.0
	overlay.rotation = deg_to_rad(37)
	editor.apply_grid(overlay)
	editor.layer_panel._add_objects()
	var id: String = editor.canvas.active_layer_id
	_check(id != "objects" and floor.layer_by_id(id) is AtlasObjectsLayer, "new Objects layer becomes the explicit edit target")
	_check(editor.canvas.map.grid.cell_polygon(Vector2i.ZERO) != basis,
		"editing the overlay changes only grid polygons")
	var stroke: AtlasStroke = AtlasEditablePath.make(PackedVector2Array([Vector2(-3.125, 0.25), Vector2(30.5, 10.75)]), Color.WHITE, 2.0, false)
	editor.artwork.edit_path(-1, null, stroke)
	_check((floor.layer_by_id(id) as AtlasObjectsLayer).strokes.size() == 1 and floor.strokes.is_empty(),
		"wall object goes only into the selected Objects layer")
	# Presentation is a view choice; assigning a layer to a different authored
	# detail group is history-backed metadata, not a new document or transform.
	editor.layer_panel.layer_detail_spinner.value = 1
	_check(floor.layer_by_id(id).detail_level == 1 and not editor.canvas.editing_target_is_presented(),
		"layer detail assignment is persistent and does not silently change presentation")
	editor.layer_panel.view_detail_spinner.value = 1
	_check(editor.canvas.presented_detail_level == 1 and editor.canvas.active_layer_id == id
		and editor.canvas.editing_target_is_presented(),
		"manual detail presentation does not retarget editing")
	editor.layer_panel.layer_detail_spinner.value = 0
	editor.layer_panel.view_detail_spinner.value = 0
	_check(floor.layer_by_id(id).detail_level == 0 and editor.canvas.editing_target_is_presented(),
		"editor can return to overview editing without another map")
	editor.layer_panel.lock_checkbox.button_pressed = true
	var command: AtlasEditCommand = editor.edits.get_undo_command()
	editor.artwork.edit_path(-1, null, stroke)
	_check((floor.layer_by_id(id) as AtlasObjectsLayer).strokes.size() == 1
		and editor.edits.get_undo_command() == command, "locked edit is rejected without adding history")
	editor._on_undo()
	_check(not floor.layer_by_id(id).locked, "undo unlocks the correct layer")
	editor.layer_panel.visibility_checkbox.button_pressed = false
	command = editor.edits.get_undo_command()
	editor.artwork.edit_path(-1, null, stroke)
	_check((floor.layer_by_id(id) as AtlasObjectsLayer).strokes.size() == 1
		and editor.edits.get_undo_command() == command, "hidden layer cannot be erased")
	editor._on_undo()
	editor.layer_panel.opacity_spinner.value = 0.5
	_check(floor.layer_by_id(id).opacity == 0.5, "opacity control edits selected layer metadata")
	editor.layer_panel._move(-1)
	_check(floor.layers[1].id == id, "lower moves the selected layer in canonical order")
	editor._on_undo()
	_check(floor.layers[-1].id == id, "undo restores canonical layer order")
	editor._on_redo()
	var pixels: Image = Image.create(9, 7, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.2, 0.4, 0.6, 0.5))
	editor.import_raster(pixels)
	var raster_id: String = editor.canvas.active_layer_id
	var raster: AtlasRasterLayer = floor.layer_by_id(raster_id) as AtlasRasterLayer
	_check(raster != null and raster.chunks.size() == 1, "import creates a typed chunked raster layer")
	editor.select_layer("objects")
	command = editor.edits.get_undo_command()
	_check(editor.canvas.floor.layer_by_id(editor.canvas.active_layer_id) is AtlasObjectsLayer,
		"selecting Objects switches to object tools")
	_check(editor.edits.get_undo_command() == command, "layer selection is not an edit command")
	editor._on_save()
	var checkpoint: Dictionary = editor.campaign.to_dict()
	_check(not editor.edits.is_dirty(), "validated save clears dirty state")
	editor.select_layer(id)
	editor.layer_panel._rename("Renamed Objects")
	editor._on_save()
	var basename: String = editor.save_path.trim_suffix(".scn")
	var head: String = basename + ".atlas.json"
	var backup: String = basename + ".atlas.bak.json"
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(backup)),
		"second portable generation retains an independently recoverable pointer")
	_corrupt(head)
	editor._on_load()
	_check(editor.campaign.to_dict() == checkpoint and editor.edits.is_dirty(),
		"Load recovers the complete previous generation and marks it for repair")
	_check(editor.status_label.text.contains("Recovered previous complete generation"),
		"recovery is reported in the UI")
	var recovered_raster: AtlasRasterLayer = editor.canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer
	_check(recovered_raster != null and recovered_raster.chunks["0,0"].image.get_data() == pixels.get_data(),
		"UI recovery hydrates exact raster pixels")
	# Repair while the verified backup still exists, then test damage to both pointers.
	editor._on_save()
	_check(not editor.edits.is_dirty() and editor.status_label.text.contains("Saved generation"),
		"saving a recovered generation publishes a healthy new root")
	_corrupt(head)
	_corrupt(backup)
	var retained: AtlasCampaign = editor.campaign
	editor._on_load()
	_check(editor.campaign == retained and editor.status_label.text.contains("Head:"),
		"failed load never replaces the active campaign or history")
	editor._on_save()
	_check(editor.status_label.text.contains("Campaign save failed") and FileAccess.get_file_as_string(ProjectSettings.globalize_path(head)) == "invalid checkpoint",
		"saving cannot overwrite an unrecoverable damaged root")
	root.remove_child(scene)
	scene.free()
	if failures == 0:
		print("ATLAS_LAYER_UI_PASSED")
	quit(0 if failures == 0 else 1)


## Godot warns if an autowrapping Label has no positive width constraint.
## Traverse the instantiated scene, including embedded inspector/browser scenes,
## so changes to reusable forms cannot regress their width constraints.
func _check_wrapped_labels(node: Node) -> void:
	if node is Label:
		var label: Label = node as Label
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			_check(label.custom_minimum_size.x > 0.0,
				"wrapping label has explicit minimum width: " + str(label.get_path()))
	for child: Node in node.get_children():
		_check_wrapped_labels(child)


func _corrupt(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("invalid checkpoint")
	file.close()
