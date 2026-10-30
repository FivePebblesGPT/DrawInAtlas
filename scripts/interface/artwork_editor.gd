class_name AtlasArtworkEditor
extends RefCounted
## Applies canvas editing intents through history. This session owns edit scope
## and clipboard state, but has no dependency on inspector/sidebar controls.

signal message(text: String)
signal layers_changed(preferred_id: String)
signal tool_requested(tool: AtlasCanvas.Tool)

var locked_to_cell: bool = false
var palette_id: int = 2
var use_system_clipboard: bool = true
var clipboard_text: String = ""
var _paste_count: int = 0
var _pending_fill: AtlasFillResult
var _pending_fill_layer_id: String = ""
var _pending_fill_is_terrain: bool = false
var _canvas: AtlasCanvas
var _edits: AtlasEditHistory


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
	if _canvas.floor != null:
		var current: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
		if tool == AtlasCanvas.Tool.PAINT and not current is AtlasTileLayer:
			var tiles: AtlasTileLayer = _canvas.floor.terrain_layer()
			if tiles != null:
				select_layer(tiles.id)
		elif tool in [AtlasCanvas.Tool.LINE, AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.POLYGON] and not current is AtlasInkLayer:
			var ink: AtlasInkLayer = _canvas.floor.ink_layer()
			if ink != null:
				select_layer(ink.id)
		elif tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER] and not (current is AtlasInkLayer or current is AtlasRasterLayer):
			var ink: AtlasInkLayer = _canvas.floor.ink_layer()
			if ink != null:
				select_layer(ink.id)
	refresh_scope()


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
	message.emit("Selected layer: %s" % _canvas.floor.layer_by_id(id).display_name)


func apply_layers(layers: Array[AtlasLayer], selected_id: String) -> bool:
	_canvas.cancel_edit()
	_canvas.clear_selection()
	for layer: AtlasLayer in layers:
		if layer is AtlasTileLayer and layer.grid == null:
			if _canvas.floor.layer_by_id(layer.id) != null:
				layer.grid = _canvas.map.get_terrain_grid(_canvas.floor.id).copy()
			elif _canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS:
				message.emit("Choose a square or hex grid before creating a terrain layer.")
				layers_changed.emit("")
				return false
			else:
				layer.grid = _canvas.map.grid.copy()
	var new_layer: bool = _canvas.floor.layer_by_id(selected_id) == null
	var command: AtlasLayerEdit = AtlasLayerEdit.new(_canvas.map.id, _canvas.floor.id, _canvas.floor.layers, layers)
	if not _edits.execute(command):
		layers_changed.emit("")
		return false
	layers_changed.emit(selected_id)
	var selected: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if new_layer and ((selected is AtlasInkLayer and selected.strokes.is_empty())
			or (selected is AtlasRasterLayer and selected.chunks.is_empty())):
		tool_requested.emit(AtlasCanvas.Tool.PEN)
	_canvas.queue_redraw()
	if not _canvas.editing_target_is_presented():
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
		var result: AtlasFillResult = AtlasRasterBrush.paint(target, stroke.points, stroke.color, stroke.width, erasing, scope())
		if not result.ok:
			message.emit(result.message)
			return
		var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
		layers[_canvas.floor.layers.find(target)] = result.layer
		apply_layers(layers, target.id)
		return
	var layer: AtlasInkLayer = target as AtlasInkLayer
	if layer == null or not layer.is_editable():
		message.emit("Select visible, unlocked ink or raster content to draw.")
		return
	var before: Array[AtlasStroke] = layer.strokes
	var after: Array[AtlasStroke]
	if erasing:
		after = scope().erase(before, stroke.points, stroke.width)
	else:
		after = AtlasStroke.clone_all(before)
		if stroke.filled:
			# A solid fill must never spill outside a cell mask. Reject the entire
			# polygon rather than splitting its interior into unrelated strokes.
			if not scope().contains_rect(AtlasSelectionGeometry.stroke_bounds(stroke)):
				message.emit("Polygon is outside the selected-cell edit mask.")
				return
			after.append(stroke.copy())
		else:
			after.append_array(scope().clip_strokes([stroke]))
	var command: AtlasStrokeEdit = AtlasStrokeEdit.new(_canvas.map.id, _canvas.floor.id, before, after, layer.id)
	if _edits.execute(command):
		_canvas.queue_redraw()
		message.emit("Erased ink. One gesture = one undo." if erasing else "Stroke added in board coordinates.")


func paint(cell: Vector2i) -> void:
	if not _canvas.editing_target_is_presented():
		message.emit("Select the editing layer's detail level before painting.")
		return
	var layer: AtlasTileLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id) as AtlasTileLayer
	if layer == null or not layer.is_editable():
		message.emit("Select a visible, unlocked terrain layer to paint.")
		return
	var basis: AtlasGrid = layer.grid if layer.grid != null else _canvas.map.get_terrain_grid(_canvas.floor.id)
	if basis.kind == AtlasGrid.Kind.GRIDLESS:
		message.emit("This terrain layer has no content grid.")
		return
	if not scope().allows_polygon(basis.cell_polygon(cell)):
		message.emit("Edit blocked by selected-cell lock.")
		return
	var key: String = "%d,%d" % [cell.x, cell.y]
	if int(layer.terrain.get(key, 0)) == palette_id:
		return
	var after: Dictionary = layer.terrain.duplicate()
	if palette_id == 0:
		after.erase(key)
	else:
		after[key] = palette_id
	var command: AtlasTileEdit = AtlasTileEdit.new(_canvas.map.id, _canvas.floor.id, layer.id, layer.terrain, after)
	if _edits.execute(command):
		_canvas.queue_redraw()


func _compute_fill(point: Vector2, inverted_global: bool = false) -> AtlasFillResult:
	if not _canvas.editing_target_is_presented():
		var hidden: AtlasFillResult = AtlasFillResult.new()
		hidden.message = "Select the editing layer's detail level before filling."
		return hidden
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if layer == null or not layer.is_editable():
		var blocked: AtlasFillResult = AtlasFillResult.new()
		blocked.message = "Fill needs visible, unlocked raster or terrain content."
		return blocked
	if layer is AtlasRasterLayer:
		return AtlasFill.raster(layer, point, _canvas.brush_color, scope(), 262144,
			_canvas.fill_tolerance, _canvas.fill_global == inverted_global)
	if layer is AtlasTileLayer:
		var basis: AtlasGrid = layer.grid if layer.grid != null else _canvas.map.get_terrain_grid(_canvas.floor.id)
		return AtlasFill.tiles(basis, layer.terrain, basis.document_to_cell(point), palette_id, scope())
	var unsupported: AtlasFillResult = AtlasFillResult.new()
	unsupported.message = "Select raster pixels or terrain cells; ink outlines are not fill boundaries."
	return unsupported


## A preview is detached: no history command, no persisted change, and no
## in-progress edit can leave modified pixels on the source layer.
func preview_fill(point: Vector2, inverted_global: bool = false) -> void:
	cancel_preview_fill()
	_pending_fill_layer_id = _canvas.active_layer_id
	_pending_fill_is_terrain = _canvas.floor.layer_by_id(_pending_fill_layer_id) is AtlasTileLayer
	_pending_fill = _compute_fill(point, inverted_global)
	if not _pending_fill.ok:
		message.emit(_pending_fill.message)
		return
	if _pending_fill_is_terrain:
		var original: AtlasTileLayer = _canvas.floor.layer_by_id(_pending_fill_layer_id) as AtlasTileLayer
		var preview: AtlasTileLayer = AtlasLayerCodec.clone(original) as AtlasTileLayer
		preview.terrain = _pending_fill.terrain
		_canvas._preview_layer = preview
	else:
		_canvas._preview_layer = _pending_fill.layer
	_canvas._raster_textures.clear()
	_canvas.queue_redraw()
	message.emit("Fill preview — release to apply, Escape to cancel.")


func cancel_preview_fill() -> void:
	_pending_fill = null
	_pending_fill_layer_id = ""
	_pending_fill_is_terrain = false
	_canvas._preview_layer = null
	_canvas._raster_textures.clear()
	_canvas.queue_redraw()


func commit_preview_fill() -> void:
	if _pending_fill == null:
		return
	var result: AtlasFillResult = _pending_fill
	var id: String = _pending_fill_layer_id
	var is_terrain: bool = _pending_fill_is_terrain
	cancel_preview_fill()
	if result.ok:
		_apply_fill_result(result, id, is_terrain)


func fill_at(point: Vector2) -> bool:
	_canvas.cancel_edit()
	var result: AtlasFillResult = _compute_fill(point)
	if not result.ok:
		message.emit(result.message)
		return false
	return _apply_fill_result(result, _canvas.active_layer_id,
		_canvas.floor.layer_by_id(_canvas.active_layer_id) is AtlasTileLayer)


func _apply_fill_result(result: AtlasFillResult, id: String, is_terrain: bool) -> bool:
	_canvas.clear_selection()
	var current: AtlasLayer = _canvas.floor.layer_by_id(id)
	if current == null or not current.is_editable() or not _canvas.editing_target_is_presented():
		message.emit("Fill target changed; nothing applied.")
		return false
	if is_terrain:
		var tiles: AtlasTileLayer = current as AtlasTileLayer
		if tiles == null:
			return false
		var command: AtlasTileEdit = AtlasTileEdit.new(_canvas.map.id, _canvas.floor.id, id,
			tiles.terrain, result.terrain)
		if _edits.execute(command):
			_canvas.queue_redraw()
			message.emit("Filled terrain cells in one undoable action.")
			return true
	elif current is AtlasRasterLayer and result.layer != null:
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
	if layer is AtlasTileLayer:
		var basis: AtlasGrid = layer.grid if layer.grid != null else _canvas.map.get_terrain_grid(_canvas.floor.id)
		var key: String = "%d,%d" % [_canvas.selected_cell.x, _canvas.selected_cell.y]
		return _canvas.has_selected_cell and basis.same_geometry(_canvas.map.grid) and layer.terrain.has(key)
	return not _canvas.selection.is_empty() and _canvas.selection.matches(layer)


func can_modify_selection() -> bool:
	if not can_copy_selection():
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if not layer.is_editable():
		return false
	if layer is AtlasTileLayer:
		var basis: AtlasGrid = layer.grid if layer.grid != null else _canvas.map.get_terrain_grid(_canvas.floor.id)
		return scope().allows_polygon(basis.cell_polygon(_canvas.selected_cell))
	return scope().contains_rect(_canvas.selection.bounds)


func _system_clipboard_enabled() -> bool:
	return use_system_clipboard and not OS.has_feature("web") and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)


func copy_selection() -> bool:
	if not can_copy_selection():
		message.emit("Select visible artwork first.")
		return false
	var layer: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	var encoded: String = ""
	if layer is AtlasInkLayer:
		encoded = AtlasClipboard.encode_ink(layer.strokes, _canvas.selection.stroke_indices, _canvas.selection.bounds.position)
	elif layer is AtlasRasterLayer:
		encoded = AtlasClipboard.encode_raster(layer, _canvas.selection.bounds.position)
	elif layer is AtlasTileLayer:
		var basis: AtlasGrid = layer.grid if layer.grid != null else _canvas.map.get_terrain_grid(_canvas.floor.id)
		var key: String = "%d,%d" % [_canvas.selected_cell.x, _canvas.selected_cell.y]
		var cells: Dictionary = {key: layer.terrain[key]}
		encoded = AtlasClipboard.encode_tiles(basis, cells, _canvas.selected_cell)
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
	if layer is AtlasTileLayer:
		var after: Dictionary = layer.terrain.duplicate()
		after.erase("%d,%d" % [_canvas.selected_cell.x, _canvas.selected_cell.y])
		var command: AtlasTileEdit = AtlasTileEdit.new(_canvas.map.id, _canvas.floor.id, layer.id, layer.terrain, after)
		if _edits.execute(command):
			_canvas.queue_redraw()
			return true
		return false
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_canvas.floor.layers)
	var index: int = _canvas.floor.layers.find(layer)
	if layer is AtlasInkLayer:
		var indices: Array[int] = _canvas.selection.stroke_indices.duplicate()
		indices.sort()
		indices.reverse()
		var ink: AtlasInkLayer = layers[index] as AtlasInkLayer
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
				return import_raster(image)
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
	var target: AtlasLayer = _canvas.floor.layer_by_id(_canvas.active_layer_id)
	if payload.kind == "INK" and target is AtlasInkLayer and target.is_editable():
		return _paste_ink(payload, target, anchor)
	if payload.kind == "RASTER" and payload.raster != null:
		return _paste_raster(payload.raster, anchor)
	if payload.kind == "TILES" and target is AtlasTileLayer and target.is_editable():
		return _paste_tiles(payload, target, anchor)
	message.emit("Select a compatible, visible and unlocked destination layer.")
	return false


func _paste_ink(payload: AtlasClipboardData, target: AtlasInkLayer, anchor: Vector2) -> bool:
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
	select_all_artwork()
	message.emit("Pasted raster asset. Drag it or use the corner handle to place it.")
	return true


func _paste_tiles(payload: AtlasClipboardData, target: AtlasTileLayer, anchor: Vector2) -> bool:
	var basis: AtlasGrid = target.grid if target.grid != null else _canvas.map.get_terrain_grid(_canvas.floor.id)
	if basis.kind != payload.grid.kind or basis.cell_size != payload.grid.cell_size or basis.rotation != payload.grid.rotation:
		message.emit("Tile paste needs matching grid shape, spacing and rotation; no implicit conversion.")
		return false
	var origin: Vector2i = basis.document_to_cell(anchor)
	var cells: Dictionary = target.terrain.duplicate()
	for key: String in payload.tiles:
		var xy: PackedStringArray = key.split(",")
		var x: int = origin.x + int(xy[0])
		var y: int = origin.y + int(xy[1])
		if abs(x) > 2147483647 or abs(y) > 2147483647:
			return false
		var cell: Vector2i = Vector2i(x, y)
		if not scope().allows_polygon(basis.cell_polygon(cell)):
			return false
		cells["%d,%d" % [cell.x, cell.y]] = payload.tiles[key]
	var command: AtlasTileEdit = AtlasTileEdit.new(_canvas.map.id, _canvas.floor.id, target.id, target.terrain, cells)
	if _edits.execute(command):
		_canvas.queue_redraw()
		return true
	message.emit("Select a compatible, visible and unlocked destination layer.")
	return false


func import_raster(image: Image) -> bool:
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
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
	select_all_artwork()
	message.emit("Imported raster asset. Drag it or use the corner handle to place it.")
	return true
