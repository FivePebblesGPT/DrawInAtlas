class_name DrawingAssetBrowserDragList
extends ItemList
## Source-neutral Godot GUI drag surface. The host verifies the offered
## immutable source token before making any document or campaign mutation.

const DRAG_START_DISTANCE: float = 12.0

var drag_entry_provider: Callable
var _press_row: int = -1
var _press_position: Vector2 = Vector2.ZERO


## ItemList handles its own selection and scrolling, so its drag virtual is not
## consistently reached for a held row press. Explicitly start the *native*
## Control drag once a valid row passes the pointer threshold. No source is
## placed here; the Atlas canvas remains the only authorized drop target.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_press_row = get_item_at_position(button.position, true) if button.pressed else -1
			_press_position = button.position
	elif event is InputEventMouseMotion and _press_row >= 0:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_press_row = -1
			return
		if motion.position.distance_squared_to(_press_position) < DRAG_START_DISTANCE * DRAG_START_DISTANCE:
			return
		var row: int = _press_row
		_press_row = -1
		if get_viewport().gui_is_dragging():
			return
		var offered: Variant = drag_entry_provider.call(row) if drag_entry_provider.is_valid() else null
		if not offered is Dictionary or (offered as Dictionary).is_empty():
			return
		force_drag(offered, _make_drag_preview(offered))
		accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if not drag_entry_provider.is_valid():
		return null
	var row: int = get_item_at_position(at_position, true)
	if row < 0:
		return null
	var offered: Variant = drag_entry_provider.call(row)
	if not offered is Dictionary or (offered as Dictionary).is_empty():
		return null
	if get_viewport().gui_is_dragging():
		set_drag_preview(_make_drag_preview(offered))
	return offered


func _make_drag_preview(offered: Dictionary) -> Label:
	var preview: Label = Label.new()
	preview.text = "Object source: %s" % String(offered.get("name", offered.get("id", "")))
	return preview
