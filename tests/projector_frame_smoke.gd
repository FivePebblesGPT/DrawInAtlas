extends SceneTree
## T-013: session-only frame contract, isolated from artwork and publication.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PROJECTOR FRAME FAILED: " + message)


func _run() -> void:
	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	_check(is_equal_approx(frame.aspect_ratio(), 16.0 / 9.0), "default aspect is 16:9")
	_check(frame.set_view(Vector2(12, -8), 320.0), "negative document positions are valid")
	var bounds: Rect2 = frame.bounds()
	_check(bounds.size.is_equal_approx(Vector2(320, 180)) and bounds.get_center() == Vector2(12, -8),
		"frame exactly matches aspect and document center")
	_check(is_equal_approx(frame.output_camera_zoom(), 6.0) and frame.output_camera_center() == Vector2(12, -8),
		"camera mapping follows the frame width without modifying geometry")
	_check(frame.set_output_size(Vector2i(1200, 900)) and is_equal_approx(frame.bounds().size.y, 240.0) \
		and frame.width == 320.0 and frame.center == Vector2(12, -8),
		"different output aspect changes framing height only")
	_check(not frame.set_output_size(Vector2i(0, 100)) and not frame.set_output_size(Vector2i(20000, 100)) \
		and frame.output_size == Vector2i(1200, 900), "invalid output sizes rejected atomically")
	_check(not frame.set_view(Vector2.INF, 30.0) and not frame.set_view(Vector2.ZERO, NAN) \
		and not frame.set_view(Vector2.ZERO, 0.0) and frame.center == Vector2(12, -8),
		"invalid frame updates cannot poison camera geometry")
	var original_top_left: Vector2 = frame.bounds().position
	_check(frame.resize_from_top_left(original_top_left, original_top_left + Vector2(500, 375)) \
		and frame.bounds().position.is_equal_approx(original_top_left) \
		and frame.bounds().size.is_equal_approx(Vector2(500, 375)),
		"resize preserves opposite corner and output ratio")
	_check(frame.resize_from_top_left(original_top_left, original_top_left) \
		and frame.width >= AtlasProjectorFrame.MIN_WIDTH and is_equal_approx(frame.bounds().size.x / frame.bounds().size.y, 4.0 / 3.0),
		"resize clamps to positive size instead of producing inverted frame")
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for step: int in range(7):
		await process_frame
	editor.create_board("Frame test", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
	var canvas: AtlasCanvas = editor.canvas
	var before: Dictionary = editor.campaign.to_dict().duplicate(true)
	var history_entry: AtlasEditCommand = editor.edits.get_undo_command()
	editor.projector_frame_button.button_pressed = true
	_check(canvas.projector_frame_active and editor.projector_frame_button.button_pressed,
		"chrome button enters independent GM-only framing mode")
	_check(canvas.projector_frame.center.is_equal_approx(canvas.camera_center),
		"new session frame starts at the GM camera location")
	editor.projector_aspect_picker.select(1)
	editor.projector_aspect_picker.item_selected.emit(1)
	_check(is_equal_approx(canvas.projector_frame.aspect_ratio(), 4.0 / 3.0),
		"ratio selector changes frame geometry")
	_check(editor.campaign.to_dict() == before and editor.edits.get_undo_command() == history_entry,
		"framing changes do not mutate or record canonical art")
	canvas._frame_drag = AtlasCanvas.FrameDrag.MOVE
	canvas._frame_original_center = canvas.projector_frame.center
	canvas._frame_original_width = canvas.projector_frame.width
	canvas._frame_drag_start = Vector2.ZERO
	canvas._update_projector_frame_drag(Vector2(35, -13))
	_check(canvas.projector_frame.center == canvas._frame_original_center + Vector2(35, -13),
		"moving draft changes only frame center")
	canvas.cancel_projector_frame_drag()
	_check(canvas.projector_frame.center == canvas._frame_original_center and canvas._frame_drag == AtlasCanvas.FrameDrag.NONE,
		"cancelling drag restores previous frame exactly")
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	_check(not canvas.projector_frame_active and not editor.projector_frame_button.button_pressed,
		"choosing an art tool exits framing mode")
	editor.projector_frame_button.button_pressed = true
	var alternate: AtlasMapDocument = AtlasMapDocument.new("other", "Other")
	_check(canvas.set_document(alternate, editor.campaign) and not canvas.projector_frame_active,
		"navigating to another document removes the session frame")
	_check(editor.campaign.to_dict() == before and editor.edits.get_undo_command() == history_entry,
		"moving, cancelling and aspect changes never enter document history")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_PROJECTOR_FRAME_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
