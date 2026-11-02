class_name AtlasObjectEditorWindow
extends Window
## Atlas-hosted dedicated Object Editor window with Drawing document tabs.
## T-055 will wire its open_instance() action into the Atlas selection toolbar.
## No duplicate drawing engine or locally defined painting tools are used.

const WORKSPACE_SCRIPT: Script = preload("res://addons/drawing/workspace.gd")

var bridge: AtlasObjectEditorBridge
var workspace: Control


func _ready() -> void:
	title = "DrawInAtlas · Object Editor"
	size = Vector2i(1240, 810)
	min_size = Vector2i(760, 500)
	visible = false
	workspace = WORKSPACE_SCRIPT.new() as Control
	workspace.start_blank_document = false
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.object_tab_closed.connect(_release_session)
	add_child(workspace)
	close_requested.connect(_request_window_close)


func configure(asset_library: AtlasObjectLibrary, global_history: AtlasEditHistory,
		current_context: Callable) -> void:
	bridge = AtlasObjectEditorBridge.new(asset_library, global_history, current_context)


func open_instance(instance_id: String) -> DrawingResult:
	if bridge == null or workspace == null:
		return DrawingResult.failure("HOST", "Object Editor is not configured")
	var opened: DrawingResult = bridge.open_from_instance(instance_id)
	return _mount(opened)


func open_source(asset_id: String) -> DrawingResult:
	if bridge == null or workspace == null:
		return DrawingResult.failure("HOST", "Object Editor is not configured")
	return _mount(bridge.open_source(asset_id))


func _mount(opened: DrawingResult) -> DrawingResult:
	if not opened.ok:
		return opened
	var attached: DrawingResult = workspace.attach_object_session(opened.value)
	if not attached.ok:
		bridge.release(opened.value)
		return attached
	popup_centered()
	return DrawingResult.success(opened.value)


func _release_session(session: DrawingObjectEditorSession) -> void:
	if bridge != null:
		bridge.release(session)
	if workspace.tabs.is_empty():
		hide()


func _request_window_close() -> void:
	if workspace.tabs.is_empty():
		hide()
	else:
		workspace._request_close_current()
