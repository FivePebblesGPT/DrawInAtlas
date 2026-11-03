class_name DrawingAssetBrowserDragList
extends ItemList
## Source-neutral Godot GUI drag surface. The host verifies the offered
## immutable source token before making any document or campaign mutation.

var drag_entry_provider: Callable


func _get_drag_data(at_position: Vector2) -> Variant:
	if not drag_entry_provider.is_valid():
		return null
	var row: int = get_item_at_position(at_position, true)
	if row < 0:
		return null
	var offered: Variant = drag_entry_provider.call(row)
	if not offered is Dictionary or (offered as Dictionary).is_empty():
		return null
	var preview: Label = Label.new()
	preview.text = "Object source: %s" % String(offered.get("name", offered.get("id", "")))
	if get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	else:
		preview.free()
	return offered
