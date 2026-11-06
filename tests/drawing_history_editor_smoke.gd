extends SceneTree
## T-054: exercise real AtlasEditor map/floor, mode, camera and missing-target replay.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HISTORY EDITOR FAILED: " + description)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var canvas: AtlasCanvas = editor.canvas
	var destination: AtlasMapDocument = editor.campaign.get_map("greyhaven")
	_check(destination != null, "destination stable map exists")
	if destination == null:
		scene.queue_free()
		quit(1)
		return
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = destination.id
	context.floor_group_id = destination.default_floor_id
	context.detail_group_id = "0"
	context.editor_mode = str(int(AtlasCanvas.Tool.ART_SELECT))
	context.has_focus = true
	context.focus_bounds = Rect2(2000.0, 1000.0, 10.0, 10.0)
	canvas.camera_center = Vector2(25.0, 25.0)
	canvas.camera_zoom = 2.5
	var initial_undo: bool = editor.edits.can_undo()
	var empty_regions: Array[DrawingDirtyRegion] = []
	_check(editor._restore_history_context(context, empty_regions),
		"return to originating map and floor via the live editor")
	_check(canvas.map.id == destination.id and canvas.floor.id == destination.default_floor_id,
		"restoration selects the stable destination IDs")
	_check(is_equal_approx(canvas.camera_zoom, 2.5),
		"cross-map restoration keeps current zoom, not saved destination zoom")
	_check(canvas.camera_center == context.focus_bounds.get_center(),
		"invisible affected geometry pans into view")
	_check(canvas.tool == AtlasCanvas.Tool.ART_SELECT,
		"source editing mode is restored")
	_check(editor.edits.active_map_id == destination.id,
		"restored map becomes the global edit origin")
	_check(editor.edits.can_undo() == initial_undo,
		"context restoration never adds navigation-only undo history")
	var prior_center: Vector2 = canvas.camera_center
	context.focus_bounds = Rect2(prior_center - Vector2(10, 10), Vector2(20, 20))
	_check(editor._restore_history_context(context, empty_regions),
		"second context replay succeeds on same map")
	_check(canvas.camera_center == prior_center and is_equal_approx(canvas.camera_zoom, 2.5),
		"partly visible geometry leaves camera translation and zoom alone")
	context.selected_layer_ids = ["reused-name-not-stable-id"]
	_check(not editor._restore_history_context(context, empty_regions),
		"missing stable layer ID is rejected rather than rebound by name")
	context.selected_layer_ids.clear()
	context.map_id = "deleted-map-not-present"
	_check(not editor._restore_history_context(context, empty_regions),
		"missing map triggers deterministic fallback")
	_check(canvas.map.id == editor.campaign.root_map_id,
		"missing map falls back to campaign root")
	var before: DrawingHistoryContext = editor._capture_history_context()
	before.selected_layer_ids = ["deleted-original-layer"]
	var after: DrawingHistoryContext = editor._capture_history_context()
	if after.selected_layer_ids.is_empty():
		after.selected_layer_ids = ["some-other-missing-layer"]
	editor.edits.record_selection_history = true
	_check(editor.edits.record_selection_change(before, after),
		"opt-in selection event is present in the real editor")
	editor._on_undo()
	_check(editor.status_label.text.contains("unavailable"),
		"visible missing-target warning is not replaced by generic undo success")
	_check(editor.edits.can_redo(), "warning does not disrupt history cursor")
	root.remove_child(scene)
	scene.free()
	print("DRAWING_HISTORY_EDITOR_%s (%d checks; %d failed)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
