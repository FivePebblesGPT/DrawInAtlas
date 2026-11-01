class_name AtlasArtworkEditor
extends RefCounted
## Applies canvas editing intents through history. This session owns edit scope
## and clipboard state, but has no dependency on inspector/sidebar controls.

signal message(text: String)
signal layers_changed(preferred_id: String)
signal tool_requested(tool: AtlasCanvas.Tool)

var locked_to_cell: bool = false
var use_system_clipboard: bool = true
var clipboard_text: String = ""
var _paste_count: int = 0
## Detached fill candidate while the pointer is pressed: no persisted pixels
## or history entry until release, and switching layers cancels the candidate.
var _pending_fill: AtlasFillResult
var _pending_fill_layer_id: String = ""
## The preview is a candidate against one exact source snapshot and board/floor.
## A history change between press and release must not overwrite newer pixels.
var _pending_fill_map_id: String = ""
var _pending_fill_floor_id: String = ""
var _pending_fill_source: Dictionary = {}
var _canvas: AtlasCanvas
var _edits: AtlasEditHistory
var _routing_tool: bool = false


func _init(canvas: AtlasCanvas, edits: AtlasEditHistory) -> void:
	_canvas = canvas
	_edits = edits


func scope() -> AtlasEditScope:
	var boundary: PackedVector2Array = PackedVector2Array()
	if locked_to_cell and _canvas.map != null and _canvas.has_selected_cell:
		boundary = _canvas.map.grid.cell_polygon(_canvas.selected_cell)
	return AtlasEditScope.new(boundary, locked_to_cell)


func refresh_scope() -> void:
	_canvas.edit_scope = scope()


func choose_tool(tool: AtlasCanvas.Tool) -> void:
	_canvas.choose_tool(tool)
	if _canvas.map == null or _canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS:
		locked_to_cell = false
	if tool not in [AtlasCanvas.Tool.ART_SELECT, AtlasCanvas.Tool.MOVE]:
		_canvas.clear_selection()
	_route_tool(tool, tool not in [AtlasCanvas.Tool.ART_SELECT, AtlasCanvas.Tool.MOVE])
	refresh_scope()


static func tool_layer_kind(tool: AtlasCanvas.Tool) -> String:
	if tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER, AtlasCanvas.Tool.FILL,
			AtlasCanvas.Tool.LINE, AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.POLYGON]:
		return "RASTER"
	if tool in [AtlasCanvas.Tool.WALL_PATH, AtlasCanvas.Tool.TEXT, AtlasCanvas.Tool.ART_SELECT, AtlasCanvas.Tool.MOVE]:
		return "OBJECTS"
	if tool == AtlasCanvas.Tool.TOKEN:
		return "TOKENS"
	return ""


func _route_tool(tool: AtlasCanvas.Tool, create: bool = true) -> void:
	if _canvas.floor == null or tool_layer_kind(tool).is_empty():
		return
	var kind: String = tool_layer_kind(tool)
	var level: int = _canvas.presented_detail_level
	var target: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if not _eligible_target(target, kind, level):
		target = null
		for candidate: AtlasLayer in _canvas.floor.layers:
			if _eligible_target(candidate, kind, level):
				target = candidate
	if target == null and not create:
		_canvas.clear_selection()
		message.emit("There are no editable Objects on this detail level.")
		return
	_routing_tool = true
	if target == null:
		var id: String = kind.to_lower() + "-" + Crypto.new().generate_random_bytes(16).hex_encode()
		match kind:
			"RASTER": target = AtlasRasterLayer.paint_layer(id)
			"TOKENS": target = AtlasTokenLayer.new(id)
			"OBJECTS": target = AtlasObjectsLayer.new(id)
		target.detail_level = level
		var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
		layers.append(target)
		apply_layers(layers, target.id)
	elif target is AtlasRasterLayer and target.pixels_per_unit < AtlasRasterLayer.PAINT_PIXELS_PER_UNIT:
		var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
		var upgraded: AtlasRasterLayer = target.at_paint_density()
		if upgraded != null:
			layers[_canvas.floor.layers.find(target)] = upgraded
			apply_layers(layers, target.id)
	if _canvas.active_layer_id != target.id:
		select_layer(target.id)
	_routing_tool = false


static func _eligible_target(layer: AtlasLayer, kind: String, level: int) -> bool:
	if layer == null or not layer.is_editable() or layer.detail_level != level:
		return false
	match kind:
		"RASTER": return layer is AtlasRasterLayer
		"OBJECTS": return layer is AtlasObjectsLayer
		"TOKENS": return layer is AtlasTokenLayer
	return false


func select_layer(id: String) -> void:
	if _canvas.floor.layer_by_id(id) == null:
		return
	_canvas.cancel_edit()
	_canvas.clear_selection()
	_canvas.active_layer_id = id
	# Selecting a layer is an explicit authoring decision. Zoom/presentation
	# updates never perform this operation or change the editing target.
	_canvas.set_presented_detail_level(_canvas.floor.layer_by_id(id).detail_level)
	layers_changed.emit(id)
	if not _routing_tool:
		var layer: AtlasLayer = _canvas.floor.layer_by_id(id)
		var required: String = tool_layer_kind(_canvas.tool)
		if not _eligible_target(layer, required, layer.detail_level) and not required.is_empty():
			tool_requested.emit(AtlasCanvas.Tool.TOKEN if layer is AtlasTokenLayer else
				AtlasCanvas.Tool.ART_SELECT if layer is AtlasObjectsLayer else AtlasCanvas.Tool.PEN)
	message.emit("Selected layer: %s" % _canvas.floor.layer_by_id(id).display_name)


func apply_layers(layers: Array[AtlasLayer], selected_id: String) -> bool:
	_canvas.cancel_edit()
	_canvas.clear_selection()
	var new_layer: bool = _canvas.floor.layer_by_id(selected_id) == null
	var command: AtlasLayerEdit = AtlasLayerEdit.new(_canvas.map.id, _canvas.floor.id, _canvas.floor.layers, layers)
	if not _edits.execute(command):
		layers_changed.emit("")
		return false
	layers_changed.emit(selected_id)
	var selected: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if new_layer and not _routing_tool:
		tool_requested.emit(AtlasCanvas.Tool.TOKEN if selected is AtlasTokenLayer else
			AtlasCanvas.Tool.ART_SELECT if selected is AtlasObjectsLayer else AtlasCanvas.Tool.PEN)
	_canvas.queue_redraw()
	if _routing_tool and selected is AtlasTokenLayer:
		message.emit("GM Token layer ready. Tokens are private until explicitly authorized by a future player-output policy.")
	elif not _canvas.editing_target_is_presented():
		message.emit("Layer changed. Editing target is in D%d, but D%d is displayed; select its detail level before drawing." % [
			_canvas.floor.layer_by_id(_canvas.active_layer_id).detail_level, _canvas.presented_detail_level])
	else:
		message.emit("Layer changed. Hidden or locked layers are not editable.")
	return true


func stroke(stroke: AtlasStroke, erasing: bool) -> void:
	if not _canvas.editing_target_is_presented():
		message.emit("Editing layer is outside the displayed detail level. Select its level to edit.")
		return
	if not stroke.is_valid():
		return
	_canvas.clear_selection()
	var target: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if target is AtlasRasterLayer:
		var result: AtlasFillResult = AtlasRasterBrush.paint_stroke(target, stroke, erasing, scope())
		if not result.ok:
			message.emit(result.message)
			return
		var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
		layers[_canvas.floor.layers.find(target)] = result.layer
		apply_layers(layers, target.id)
		return
	message.emit("Drawing tools paint raster. Use object tools to create or edit Objects.")


## A path is a separately editable stroke object; all changes use a guarded
## history snapshot. Never clip vertices into ordinary non-editable strokes.
func edit_path(index: int, expected: AtlasStroke, replacement: AtlasStroke) -> void:
	if not _canvas.editing_target_is_presented():
		return
	var layer: AtlasObjectsLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id) as AtlasObjectsLayer
	if layer == null or not layer.is_editable() or replacement == null or not replacement.editable_path or not replacement.is_valid():
		return
	if index < -1 or index >= layer.strokes.size():
		return
	if index >= 0 and (expected == null or not expected.editable_path or not expected.is_valid()
				or layer.strokes[index].to_dict() != expected.to_dict()):
		return
	var active_scope: AtlasEditScope = scope()
	if not active_scope.contains_rect(AtlasSelectionGeometry.stroke_bounds(replacement)):
		message.emit("Path is outside the edit mask.")
		return
	if index >= 0 and not active_scope.contains_rect(AtlasSelectionGeometry.stroke_bounds(expected)):
		message.emit("Cannot edit a path crossing the edit mask.")
		return
	var before: Array[AtlasStroke] = layer.strokes
	var after: Array[AtlasStroke] = AtlasStroke.clone_all(before)
	if index == -1:
		after.append(replacement.copy())
	else:
		after[index] = replacement.copy()
	if _edits.execute(AtlasStrokeEdit.new(_canvas.map.id, _canvas.floor.id, before, after, layer.id)):
		_canvas.queue_redraw()
		message.emit("Editable wall path updated.")


## A modal submission must still address its original map/floor/layer.
## New text has no expected object snapshot, so it needs this separate guard.
func edit_text_in_context(index: int, expected: AtlasStroke, replacement: AtlasStroke,
		map_id: String, floor_id: String, layer_id: String) -> bool:
	if _canvas.map == null or _canvas.floor == null or map_id.is_empty() \
			or floor_id.is_empty() or layer_id.is_empty() \
			or _canvas.map.id != map_id or _canvas.floor.id != floor_id \
			or _canvas.active_layer_id != layer_id:
		message.emit("Text not applied: its original editing target changed.")
		return false
	return edit_text(index, expected, replacement)


## One guarded snapshot per placement/revision; text is never flattened.
func edit_text(index: int, expected: AtlasStroke, replacement: AtlasStroke) -> bool:
	if not _canvas.editing_target_is_presented():
		return false
	var layer: AtlasObjectsLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id) as AtlasObjectsLayer
	if layer == null or not layer.is_editable() or replacement == null or not replacement.is_text() or not replacement.is_valid():
		return false
	if index < -1 or index >= layer.strokes.size():
		return false
	if index >= 0 and (expected == null or not expected.is_text() or layer.strokes[index].to_dict() != expected.to_dict()):
		return false
	var active_scope: AtlasEditScope = scope()
	if not active_scope.contains_rect(AtlasSelectionGeometry.stroke_bounds(replacement)):
		message.emit("Text must fit inside the edit mask.")
		return false
	if expected != null and not active_scope.contains_rect(AtlasSelectionGeometry.stroke_bounds(expected)):
		message.emit("Cannot edit text crossing the edit mask.")
		return false
	if index >= 0 and layer.strokes[index].to_dict() == replacement.to_dict():
		return true
	var after: Array[AtlasStroke] = AtlasStroke.clone_all(layer.strokes)
	if index == -1:
		after.append(replacement.copy())
	else:
		after[index] = replacement.copy()
	if not _edits.execute(AtlasStrokeEdit.new(_canvas.map.id, _canvas.floor.id, layer.strokes, after, layer.id)):
		return false
	_canvas.queue_redraw()
	message.emit("Editable text updated.")
	return true


func _compute_fill(point: Vector2, inverted_global: bool = false) -> AtlasFillResult:
	if not _canvas.editing_target_is_presented():
		var hidden: AtlasFillResult = AtlasFillResult.new()
		hidden.message = "Select the editing layer's detail level before filling."
		return hidden
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if layer == null or not layer.is_editable():
		var blocked: AtlasFillResult = AtlasFillResult.new()
		blocked.message = "Fill needs a visible, unlocked raster layer."
		return blocked
	if layer is AtlasRasterLayer:
		return AtlasFill.raster(layer, point, _canvas.brush_color, scope(), 262144,
			_canvas.fill_tolerance, _canvas.fill_global == inverted_global)
	var unsupported: AtlasFillResult = AtlasFillResult.new()
	unsupported.message = "Select raster pixels; ink outlines are not fill boundaries."
	return unsupported


## A preview is detached: no history command, no persisted change, and no
## in-progress edit can leave modified pixels on the source layer.
func preview_fill(point: Vector2, inverted_global: bool = false) -> void:
	cancel_preview_fill()
	_pending_fill_layer_id = _canvas.active_layer_id
	_pending_fill = _compute_fill(point, inverted_global)
	if not _pending_fill.ok:
		message.emit(_pending_fill.message)
		return
	_pending_fill_map_id = _canvas.map.id
	_pending_fill_floor_id = _canvas.floor.id
	_pending_fill_source = _canvas.floor.layer_by_id(_pending_fill_layer_id).to_dict()
	_canvas._preview_layer = _pending_fill.layer
	_canvas._raster_textures.clear()
	_canvas.queue_redraw()
	message.emit("Fill preview — release to apply, Escape to cancel.")


func cancel_preview_fill() -> void:
	_pending_fill = null
	_pending_fill_layer_id = ""
	_pending_fill_map_id = ""
	_pending_fill_floor_id = ""
	_pending_fill_source.clear()
	_canvas._preview_layer = null
	_canvas._raster_textures.clear()
	_canvas.queue_redraw()


func commit_preview_fill() -> void:
	if _pending_fill == null:
		return
	var result: AtlasFillResult = _pending_fill
	var id: String = _pending_fill_layer_id
	var source: Dictionary = _pending_fill_source.duplicate(true)
	var same_context: bool = (_canvas.map != null and _canvas.floor != null
		and _canvas.map.id == _pending_fill_map_id
		and _canvas.floor.id == _pending_fill_floor_id
		and _canvas.active_layer_id == id)
	cancel_preview_fill()
	if not result.ok:
		return
	var current: AtlasLayer = _canvas.floor.layer_by_id(id) if same_context else null
	if current == null or current.to_dict() != source:
		message.emit("Fill target changed since preview; nothing applied.")
		return
	_apply_fill_result(result, id)


func fill_at(point: Vector2) -> bool:
	_canvas.cancel_edit()
	var result: AtlasFillResult = _compute_fill(point)
	if not result.ok:
		message.emit(result.message)
		return false
	return _apply_fill_result(result, _canvas.active_layer_id)


func _apply_fill_result(result: AtlasFillResult, id: String) -> bool:
	_canvas.clear_selection()
	var current: AtlasLayer = _canvas.floor.layer_by_id(id)
	if current == null or not current.is_editable() or not _canvas.editing_target_is_presented():
		message.emit("Fill target changed; nothing applied.")
		return false
	if current is AtlasRasterLayer and result.layer != null:
		var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
		layers[_canvas.floor.layers.find(current)] = result.layer
		if apply_layers(layers, id):
			message.emit("Filled raster pixels in one undoable action.")
			return true
	return false


func transform_selection(selection: AtlasSelection, delta: Transform2D) -> bool:
	if not _canvas.editing_target_is_presented():
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	var transformed: AtlasLayer = AtlasSelectionGeometry.transformed(layer, selection, delta, scope())
	if transformed == null:
		message.emit("Transform rejected: stale/locked selection or footprint outside the selected cell.")
		return false
	if transformed.to_dict() == layer.to_dict():
		return false
	var indices: Array[int] = selection.stroke_indices.duplicate()
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
	layers[_canvas.floor.layers.find(layer)] = transformed
	if not apply_layers(layers, layer.id):
		return false
	_canvas.selection = AtlasSelectionGeometry.select_indices(_canvas.floor.layer_by_id(layer.id), indices)
	_canvas.selection_changed.emit()
	_canvas.queue_redraw()
	message.emit("Transformed artwork without changing its grid or source pixels.")
	return true


func select_all_artwork() -> void:
	tool_requested.emit(AtlasCanvas.Tool.ART_SELECT)
	_canvas.select_all_artwork()


func can_copy_selection() -> bool:
	if _canvas.floor == null or not _canvas.editing_target_is_presented():
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if layer == null or not layer.visible:
		return false
	return not _canvas.selection.is_empty() and _canvas.selection.matches(layer)


func can_modify_selection() -> bool:
	if not can_copy_selection():
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if not layer.is_editable():
		return false
	return scope().contains_rect(_canvas.selection.bounds)


func _system_clipboard_enabled() -> bool:
	return use_system_clipboard and not OS.has_feature("web") and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)


func copy_selection() -> bool:
	if not can_copy_selection():
		message.emit("Select visible artwork first.")
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	var encoded: String = ""
	if layer is AtlasObjectsLayer:
		encoded = AtlasClipboard.encode_ink(layer.strokes, _canvas.selection.stroke_indices, _canvas.selection.bounds.position)
	elif layer is AtlasRasterLayer:
		encoded = AtlasClipboard.encode_raster(layer, _canvas.selection.bounds.position)
	if encoded.is_empty():
		message.emit("Selection is invalid or too large for the artwork clipboard.")
		return false
	clipboard_text = encoded
	_paste_count = 0
	if _system_clipboard_enabled():
		DisplayServer.clipboard_set(encoded)
	message.emit("Copied typed artwork in board units; no physical unit conversion.")
	return true


func delete_selection() -> bool:
	if not can_modify_selection():
		message.emit("Delete rejected: locked/hidden selection or footprint outside edit scope.")
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
	var index: int = _canvas.floor.layers.find(layer)
	if layer is AtlasObjectsLayer:
		var indices: Array[int] = _canvas.selection.stroke_indices.duplicate()
		indices.sort()
		indices.reverse()
		var ink: AtlasObjectsLayer = layers[index] as AtlasObjectsLayer
		for stroke_index: int in indices:
			ink.strokes.remove_at(stroke_index)
	else:
		layers.remove_at(index)
	return apply_layers(layers, layer.id)


func cut_selection() -> bool:
	return can_modify_selection() and copy_selection() and delete_selection()


func paste_selection() -> bool:
	var text: String = DisplayServer.clipboard_get() if _system_clipboard_enabled() else clipboard_text
	var payload: AtlasClipboardData = AtlasClipboard.decode(text)
	if payload == null:
		if _system_clipboard_enabled() and DisplayServer.clipboard_has_image():
			var image: Image = DisplayServer.clipboard_get_image()
			if image != null:
				return import_prop(image)
		message.emit("Clipboard has no supported artwork.")
		return false
	var anchor: Vector2 = _canvas.camera_center + Vector2.ONE * float(20 * _paste_count)
	if paste_payload(payload, anchor):
		_paste_count += 1
		return true
	return false


func paste_payload(payload: AtlasClipboardData, anchor: Vector2) -> bool:
	if payload == null or not anchor.is_finite() or not _canvas.editing_target_is_presented():
		return false
	if payload.kind == "INK":
		for object: AtlasStroke in payload.strokes:
			if not (object.editable_path or object.is_text() or object.is_prop()):
				message.emit("Ordinary vector drawing is retired; clipboard objects must be walls, text or props.")
				return false
		_route_tool(AtlasCanvas.Tool.ART_SELECT)
		choose_tool(AtlasCanvas.Tool.ART_SELECT)
	var target: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if payload.kind == "INK" and target is AtlasObjectsLayer and target.is_editable():
		return _paste_ink(payload, target, anchor)
	if payload.kind == "RASTER" and payload.raster != null:
		return _paste_raster(payload.raster, anchor)
	message.emit("Select a compatible, visible and unlocked destination layer.")
	return false


func _paste_ink(payload: AtlasClipboardData, target: AtlasObjectsLayer, anchor: Vector2) -> bool:
	var pasted: Array[AtlasStroke] = AtlasStroke.clone_all(payload.strokes)
	for stroke: AtlasStroke in pasted:
		for point: int in range(stroke.points.size()):
			stroke.points[point] += anchor
	pasted = scope().clip_strokes(pasted)
	if pasted.is_empty():
		return false
	var after: Array[AtlasStroke] = AtlasStroke.clone_all(target.strokes)
	var first: int = after.size()
	after.append_array(pasted)
	var command: AtlasStrokeEdit = AtlasStrokeEdit.new(_canvas.map.id, _canvas.floor.id, target.strokes, after, target.id)
	if not _edits.execute(command):
		return false
	tool_requested.emit(AtlasCanvas.Tool.ART_SELECT)
	var indices: Array[int] = []
	for index: int in range(first, after.size()):
		indices.append(index)
	_canvas.selection = AtlasSelectionGeometry.select_indices(_canvas.floor.layer_by_id(target.id), indices)
	_canvas.selection_changed.emit()
	_canvas.queue_redraw()
	return true


func _paste_raster(source: AtlasRasterLayer, anchor: Vector2) -> bool:
	var raster: AtlasRasterLayer = AtlasLayerCodec.clone(source) as AtlasRasterLayer
	raster.id = "raster-" + Crypto.new().generate_random_bytes(16).hex_encode()
	# Clipboard source may come from a different group; paste into the
	# explicitly presented authoring group, at unchanged board coordinates.
	raster.detail_level = _canvas.presented_detail_level
	raster.transform = Transform2D(0.0, anchor) * raster.transform
	if not scope().contains_rect(AtlasSelectionGeometry.select_all(raster).bounds):
		return false
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
	layers.append(raster)
	if not apply_layers(layers, raster.id):
		return false
	message.emit("Pasted raster artwork. Drawing tools target this raster layer.")
	return true


func import_raster(image: Image) -> bool:
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image_chunks(image, AtlasRasterLayer.PAINT_PIXELS_PER_UNIT)
	if layer == null:
		message.emit("Could not create a raster layer from that image.")
		return false
	layer.id = "raster-" + Crypto.new().generate_random_bytes(16).hex_encode()
	layer.display_name = "Imported image"
	layer.detail_level = _canvas.presented_detail_level
	layer.transform.origin = _canvas.camera_center - AtlasSelectionGeometry.raster_local_bounds(layer).size * 0.5
	if not scope().contains_rect(AtlasSelectionGeometry.select_all(layer).bounds):
		message.emit("Imported image does not fit the selected-cell scope.")
		return false
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
	layers.append(layer)
	if not apply_layers(layers, layer.id):
		return false
	message.emit("Imported raster artwork. Drawing tools target this raster layer.")
	return true


func import_prop(image: Image) -> bool:
	if image == null or image.is_empty() or image.get_width() > 4096 or image.get_height() > 4096:
		return false
	var bytes: PackedByteArray = AtlasWebPStore.encode_lossless(image)
	if bytes.is_empty():
		message.emit("Could not encode the prop as lossless WebP.")
		return false
	_route_tool(AtlasCanvas.Tool.ART_SELECT)
	choose_tool(AtlasCanvas.Tool.ART_SELECT)
	var layer: AtlasObjectsLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id) as AtlasObjectsLayer
	if layer == null or not layer.is_editable():
		return false
	var object: AtlasStroke = AtlasStroke.new(PackedVector2Array([_canvas.camera_center]), Color.WHITE,
		float(image.get_width()) / AtlasRasterLayer.PAINT_PIXELS_PER_UNIT)
	object.prop_webp = bytes
	object.prop_size = image.get_size()
	object.points[0] -= object.prop_dimensions() * 0.5
	if not object.is_valid() or not scope().contains_rect(AtlasSelectionGeometry.stroke_bounds(object)):
		message.emit("The image prop does not fit the current edit mask.")
		return false
	var after: Array[AtlasStroke] = AtlasStroke.clone_all(layer.strokes)
	after.append(object)
	if not _edits.execute(AtlasStrokeEdit.new(_canvas.map.id, _canvas.floor.id, layer.strokes, after, layer.id)):
		return false
	_canvas.selection = AtlasSelectionGeometry.select_indices(_canvas.floor.layer_by_id(layer.id), [after.size() - 1])
	_canvas.selection_changed.emit()
	_canvas.queue_redraw()
	message.emit("Placed image prop on Objects. Drag to move; the corner handle scales it.")
	return true
