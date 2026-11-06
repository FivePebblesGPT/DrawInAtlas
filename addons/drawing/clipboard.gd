class_name DrawingClipboard
extends RefCounted
## Independent pixel payload. A copied selection has no references to source tiles.

var width: int = 0
var height: int = 0
var _pixels: Dictionary[Vector2i, int] = {}


static func capture(document: DrawingDocument, layer_id: String,
		area: Rect2i, selection: DrawingSelection = null,
		origin_x: int = 0, origin_y: int = 0, max_pixels: int = 1048576) -> DrawingResult:
	if document == null or area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("CLIPBOARD_LIMIT", "Clipboard region is invalid or too large")
	var result: DrawingClipboard = DrawingClipboard.new()
	result.width = area.size.x
	result.height = area.size.y
	for y: int in range(area.size.y):
		for x: int in range(area.size.x):
			var local: Vector2i = area.position + Vector2i(x, y)
			if selection != null and not selection.allows(local):
				continue
			var read: DrawingResult = document.read_pixel(layer_id, origin_x + local.x, origin_y + local.y)
			if not read.ok:
				return read
			var rgba: int = int(read.value)
			if rgba != 0:
				result._pixels[Vector2i(x, y)] = rgba
	return DrawingResult.success(result, document.revision)


func paste(edit: DrawingEditSession, top_left: Vector2i,
		selection: DrawingSelection = null, transparent: bool = true) -> DrawingResult:
	if edit == null:
		return DrawingResult.failure("CLIPBOARD", "No destination edit session")
	var before: Dictionary[String, int] = edit._before.duplicate()
	var after: Dictionary[String, int] = edit._after.duplicate()
	for y: int in range(height):
		for x: int in range(width):
			var point: Vector2i = Vector2i(x, y)
			var rgba: int = _pixels.get(point, 0)
			if rgba == 0 and transparent:
				continue
			var staged: DrawingResult = edit._stage(top_left.x + x, top_left.y + y, rgba, selection)
			if not staged.ok:
				edit._before = before
				edit._after = after
				return staged
	return DrawingResult.success(edit.change_count())


## Move a bounded selection atomically: capture source, clear it, then paste at
## displacement. The edit session owns one undo delta, even for overlapping moves.
static func move_selection(edit: DrawingEditSession, source_area: Rect2i,
		displacement: Vector2i, selection: DrawingSelection = null) -> DrawingResult:
	if edit == null:
		return DrawingResult.failure("CLIPBOARD", "Missing document edit session")
	var captured: DrawingResult = capture(edit.document, edit.layer_id, source_area,
		selection, edit.anchor_x, edit.anchor_y)
	if not captured.ok:
		return captured
	var clipboard: DrawingClipboard = captured.value as DrawingClipboard
	var before: Dictionary[String, int] = edit._before.duplicate()
	var after: Dictionary[String, int] = edit._after.duplicate()
	var cleared: DrawingResult = edit.clear_rect(source_area, selection)
	if cleared.ok:
		var pasted: DrawingResult = clipboard.paste(edit, source_area.position + displacement)
		if pasted.ok:
			return pasted
		cleared = pasted
	edit._before = before
	edit._after = after
	return cleared
