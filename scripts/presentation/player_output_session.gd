class_name AtlasPlayerOutputSession
extends Node
## T-040 native player-window proof. Only AtlasPlayerProjection's detached
## campaign reaches AtlasMapCapture. Not connected to editor controls until
## T-039 privacy permissions and T-043 acceptance are approved.

const MAX_RENDER_PIXELS: int = 3840 * 2160

var window: Window
var display: TextureRect
var calibration: AtlasProjectorCalibration = AtlasProjectorCalibration.new()
var following: bool = true
var camera_center: Vector2 = Vector2.ZERO
var camera_width: float = 400.0
var output_size: Vector2i = Vector2i(1280, 720)
var _capture: AtlasMapCapture
var _generation: int = 0
var _frame_set: bool = false


func open_native(size: Vector2i, fullscreen: bool = false) -> bool:
	if DisplayServer.get_name() == "headless" or not is_inside_tree() \
			or size.x < 1 or size.y < 1 or size.x > 16384 or size.y > 16384 \
			or size.x * size.y > MAX_RENDER_PIXELS:
		return false
	close_native()
	output_size = size
	_capture = AtlasMapCapture.new()
	add_child(_capture)
	window = Window.new()
	window.title = "Player output (privacy prototype)"
	window.size = size
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	window.close_requested.connect(close_native)
	display = TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.modulate = Color.WHITE
	window.add_child(display)
	add_child(window)
	window.size_changed.connect(_on_output_resized)
	window.show()
	return true


## The display is blank until an explicit, authorized publish request.
## This also cancels any outstanding readback before the next policy revision.
func invalidate() -> void:
	_generation += 1
	if _capture != null:
		_capture.cancel(true)
	if display != null:
		display.texture = null


func close_native() -> void:
	invalidate()
	if window != null:
		window.queue_free()
		window = null
		display = null
	if _capture != null:
		_capture.queue_free()
		_capture = null
	_frame_set = false


## Follow tracks the frame when explicitly updated. Freeze pins the last
## authorized camera/image; invalidate() must be called on any grant change.
func set_follow(enabled: bool) -> void:
	following = enabled


func update_frame(frame: AtlasProjectorFrame) -> bool:
	if window == null or frame == null or not is_finite(frame.width) \
			or frame.width < AtlasProjectorFrame.MIN_WIDTH \
			or frame.width > AtlasProjectorFrame.MAX_WIDTH \
			or frame.output_size.x < 1 or frame.output_size.y < 1 \
			or not is_finite(frame.center.x) or not is_finite(frame.center.y) \
			or not is_equal_approx(frame.aspect_ratio(), float(output_size.x) / float(output_size.y)):
		invalidate()
		_frame_set = false
		return false
	if not following and _frame_set:
		return true
	if not _frame_set or frame.center != camera_center or frame.width != camera_width:
		invalidate()
	camera_center = frame.center
	camera_width = frame.width
	_frame_set = true
	return true


## Grant IDs must come from a trusted GM publication policy (not layer.visible).
## Capture failure, invalid grants and renderer errors always leave a blank view.
func publish(source: AtlasMapDocument, floor_id: String, detail_level: int,
		granted_layer_ids: Array[String]) -> bool:
	invalidate()
	var generation: int = _generation
	if window == null or _capture == null or not _frame_set:
		return false
	# GPU readback is asynchronous. Recheck the full source/grant context:
	# fog-only checks would allow an older public frame to be published after
	# in-place pixel edits, layer revocation, or detail-level changes.
	var source_signature: String = _publication_signature(source, floor_id,
		detail_level, granted_layer_ids)
	if source_signature.is_empty():
		return false
	var sanitized: AtlasCampaign = AtlasPlayerProjection.build_capture_input(
		source, floor_id, detail_level, granted_layer_ids)
	if sanitized == null:
		return false
	var board: AtlasMapDocument = sanitized.get_map(sanitized.root_map_id)
	var dimensions: Vector2 = Vector2(camera_width, camera_width * float(output_size.y) / float(output_size.x))
	var bounds: Rect2 = Rect2(camera_center - dimensions * 0.5, dimensions)
	var image: Image = await _capture.capture(sanitized, board, board.default_floor_id,
		bounds, output_size, false, detail_level)
	if generation != _generation or image == null or display == null \
			or _publication_signature(source, floor_id, detail_level,
			granted_layer_ids) != source_signature:
		invalidate()
		return false
	display.texture = ImageTexture.create_from_image(image)
	return true


## Native resizes change render pixels, not the measured display or board
## width. A fresh matching frame and authorized capture are required.
func _on_output_resized() -> void:
	if window == null or window.size == output_size:
		return
	output_size = window.size
	_frame_set = false
	invalidate()


func _exit_tree() -> void:
	invalidate()


## Fingerprint the publication inputs both before and after asynchronous GPU
## readback. This does NOT confer grants: a trusted caller still owns publishing
## policy and must call invalidate() when that policy changes, including while
## frozen. Layer dictionaries include current raster asset hashes, so in-place
## pixel edits and authoring/LOD/visibility revisions invalidate stale frames.
func _publication_signature(document: AtlasMapDocument, floor_id: String,
		detail_level: int, granted_layer_ids: Array[String]) -> String:
	var floor: AtlasFloor = document.floor_by_id(floor_id) if document != null else null
	if floor == null or not floor.valid_fog() or document.grid == null:
		return ""
	var layers: Array[Dictionary] = []
	for layer: AtlasLayer in floor.layers:
		if layer == null:
			return ""
		var state: Dictionary = layer.to_dict()
		if layer is AtlasRasterLayer:
			var residency: Array[bool] = []
			var keys: Array[String] = (layer as AtlasRasterLayer).chunks.keys()
			keys.sort()
			for key: String in keys:
				var chunk: AtlasRasterChunk = (layer as AtlasRasterLayer).chunks[key]
				if chunk == null:
					return ""
				residency.append(chunk.image != null)
			state["resident"] = residency
		layers.append(state)
	var fog: Array[Dictionary] = []
	for region: AtlasFogRegion in floor.fog_regions:
		fog.append(region.to_dict())
	return JSON.stringify({"document_instance": document.get_instance_id(),
		"document_id": document.id, "floor_instance": floor.get_instance_id(),
		"floor_id": floor_id, "detail_level": detail_level,
		"grants": granted_layer_ids, "grid": document.grid.to_dict(),
		"layers": layers, "fog_enabled": floor.fog_enabled,
		"fog": fog}, "", true, true).sha256_text()
