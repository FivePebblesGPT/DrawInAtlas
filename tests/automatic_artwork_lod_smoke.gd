extends SceneTree
## T-005: automatic authored content selection, inspection override and editing isolation.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var canvas: AtlasCanvas = editor.canvas
	_check(editor.automatic_artwork_lod and not editor.automatic_navigation,
		"fresh session enables authored LOD, not legacy linked-map navigation")
	_check(editor.layer_panel.auto_detail_checkbox.button_pressed and not editor.layer_panel.view_detail_spinner.editable,
		"automatic presentation is labeled and manual spinner is locked until disabled")
	var board: AtlasMapDocument = canvas.map
	var center: Vector2 = board.grid.cell_to_document(Vector2i(2, 0))
	var overview: AtlasInkLayer = canvas.floor.ink_layer()
	var d1: AtlasInkLayer = AtlasInkLayer.new("local-d1", "Streets")
	d1.detail_level = 1
	d1.strokes.append(AtlasStroke.new(PackedVector2Array([center + Vector2(-90, -80), center + Vector2(90, 80)]), Color.GREEN, 5.0))
	var d2: AtlasInkLayer = AtlasInkLayer.new("local-d2", "Interior")
	d2.detail_level = 2
	d2.strokes.append(AtlasStroke.new(PackedVector2Array([center + Vector2(-20, -20), center + Vector2(20, 20)]), Color.BLUE, 5.0))
	canvas.floor.layers.append_array([d1, d2])
	editor._rebuild_lod()
	canvas.camera_center = center
	canvas.camera_zoom = 1.0
	await process_frame
	_check(canvas.presented_detail_level == 0, "overview shows D0 at small viewport coverage")
	var document_before: AtlasMapDocument = canvas.map
	var editing_before: String = canvas.active_layer_id
	var board_point: Vector2 = center + Vector2(15, -10)
	var screen_before: Vector2 = canvas.document_to_local(board_point)
	canvas.camera_zoom = 10.0
	await process_frame
	_check(canvas.presented_detail_level == 1, "zooming in presents available authored D1")
	_check(canvas.map == document_before and canvas.active_layer_id == editing_before
		and canvas.document_to_local(board_point) != screen_before,
		"LOD changes presentation, not authored board or selected editing target")
	_check(not canvas.editing_target_is_presented() and editor.layer_panel.show_editing_detail.visible
		and editor.layer_panel.detail_status.text.contains("hidden"),
		"hidden editing target is visibly identified with an action")
	var old_count: int = overview.strokes.size()
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([center, center + Vector2(5, 0)])), false)
	_check(overview.strokes.size() == old_count, "editing hidden authored content is rejected")
	canvas.camera_zoom = 14.0
	await process_frame
	_check(canvas.presented_detail_level == 2, "more constrained authored footprint becomes available at higher zoom")
	canvas.camera_zoom = 9.0
	await process_frame
	_check(canvas.presented_detail_level == 2, "exit hysteresis keeps D2 across a moderate zoom-out")
	canvas.camera_zoom = 7.0
	await process_frame
	_check(canvas.presented_detail_level == 1, "D2 returns to D1 once coverage falls below its exit threshold")
	canvas.camera_zoom = 4.0
	await process_frame
	_check(canvas.presented_detail_level == 0, "zooming out returns to D0 on the same document")
	canvas.camera_zoom = 14.0
	await process_frame
	canvas.camera_center += Vector2(6000, 6000)
	await process_frame
	_check(canvas.presented_detail_level == 0, "empty region has no invented detail level or navigation block")
	canvas.camera_center = center
	await process_frame
	_check(canvas.presented_detail_level == 2, "panning back restores available authored detail")
	canvas._draft_stroke = AtlasStroke.new(PackedVector2Array([center, center + Vector2(2, 2)]))
	canvas.camera_zoom = 1.0
	await process_frame
	_check(canvas.presented_detail_level == 2 and canvas.active_layer_id == editing_before,
		"presentation is deferred during an in-progress stroke")
	canvas.cancel_edit()
	await process_frame
	_check(canvas.presented_detail_level == 0, "deferred presentation updates after gesture cancellation")
	canvas.camera_zoom = 14.0
	await process_frame
	canvas._manipulation = AtlasCanvas.Manipulation.MOVE
	canvas.camera_zoom = 1.0
	await process_frame
	_check(canvas.presented_detail_level == 2, "selection transform gesture defers presentation")
	canvas._manipulation = AtlasCanvas.Manipulation.NONE
	canvas.interaction_finished.emit()
	await process_frame
	_check(canvas.presented_detail_level == 0, "finished transform refreshes deferred presentation")
	canvas.camera_zoom = 14.0
	await process_frame
	canvas._draft_stroke = AtlasStroke.new(PackedVector2Array([center, center + Vector2(1, 1)]))
	canvas.camera_zoom = 1.0
	await process_frame
	_check(canvas.presented_detail_level == 2, "held raster/ink brush gesture defers presentation")
	canvas.cancel_edit()
	canvas.interaction_finished.emit()
	await process_frame
	_check(canvas.presented_detail_level == 0, "released brush refreshes presentation")
	canvas.camera_zoom = 14.0
	await process_frame
	editor.layer_panel.show_editing_detail.pressed.emit()
	await process_frame
	_check(canvas.presented_detail_level == 0 and not editor.automatic_artwork_lod
		and not editor.layer_panel.auto_detail_checkbox.button_pressed,
		"show editing detail is an intentional manual override")
	canvas.camera_zoom = 12.0
	await process_frame
	_check(canvas.presented_detail_level == 0, "manual override remains fixed while zooming")
	editor.layer_panel.view_detail_spinner.value = 1
	_check(canvas.presented_detail_level == 1 and canvas.active_layer_id == editing_before,
		"manual inspection shows independently authored content without retargeting edits")
	editor.layer_panel.auto_detail_checkbox.button_pressed = true
	await process_frame
	_check(editor.automatic_artwork_lod and canvas.presented_detail_level == 2,
		"re-enabling automatic detail re-evaluates current camera")
	# An unpainted higher detail and a completely transparent raster are not candidates.
	d1.visible = false
	d2.visible = false
	var empty_pixels: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	empty_pixels.fill(Color.TRANSPARENT)
	var empty_raster: AtlasRasterLayer = AtlasRasterLayer.from_image(empty_pixels)
	empty_raster.detail_level = 3
	canvas.floor.layers.append(empty_raster)
	editor._rebuild_lod()
	await process_frame
	_check(canvas.presented_detail_level == 0, "hidden or transparent higher groups are not selected")
	_check(editor.automatic_navigation == false, "automatic LOD never changes linked-map navigation preference")
	# Availability must be local, not the merged AABB of disconnected ink.
	var distant: AtlasInkLayer = AtlasInkLayer.new("distant", "Two disconnected towns")
	distant.detail_level = 1
	distant.strokes.append(AtlasStroke.new(PackedVector2Array([
		center + Vector2(-1000, 0), center + Vector2(-950, 0)]), Color.YELLOW, 10))
	distant.strokes.append(AtlasStroke.new(PackedVector2Array([
		center + Vector2(950, 0), center + Vector2(1000, 0)]), Color.YELLOW, 10))
	canvas.floor.layers.append(distant)
	canvas.camera_zoom = 14.0
	editor._rebuild_lod()
	await process_frame
	_check(canvas.presented_detail_level == 0, "disconnected detail pieces do not populate the empty midpoint")
	canvas.camera_center = center + Vector2(-975, 0)
	await process_frame
	_check(canvas.presented_detail_level == 1, "panning to actual distant ink makes that region available")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_AUTOMATIC_ARTWORK_LOD_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
