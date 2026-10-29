class_name AtlasMapReferences
extends Node
## Bounded, derived editor-only images. All captures use the ordinary artwork
## renderer in a private world; no reference can recursively capture another.

const MAX_CHILD_PREVIEWS: int = 8
const THUMB_SIZE: Vector2i = Vector2i(192, 128)
var source_link_id: String = ""
var source_floor_id: String = ""
var frozen: bool = false
var cache: AtlasPreviewCache = AtlasPreviewCache.new(16)
var omitted_count: int = 0
var _canvas: AtlasCanvas
var _capture: AtlasMapCapture
var _children: Dictionary[String, Dictionary] = {}
var _parent: Dictionary = {}
var _generation: int = 0
var _queued: bool = false


func bind(canvas: AtlasCanvas) -> void:
	_canvas = canvas
	_capture = AtlasMapCapture.new()
	add_child(_capture)
	canvas.view_region_changed.connect(refresh)


func reset() -> void:
	_generation += 1
	source_link_id = ""
	source_floor_id = ""
	frozen = false
	_children.clear()
	_parent.clear()
	cache.invalidate()
	if _capture != null:
		_capture.cancel(true)


func select_source(link_id: String, floor_id: String = "") -> void:
	source_link_id = link_id
	source_floor_id = floor_id
	frozen = false
	_parent.clear()
	refresh()


func set_frozen(value: bool) -> void:
	frozen = value
	refresh()


func refresh() -> void:
	_generation += 1
	if _capture != null:
		_capture.cancel()
	if not _queued and is_inside_tree():
		_queued = true
		call_deferred("_refresh")


func _refresh() -> void:
	_queued = false
	if _canvas == null or _canvas.map == null or _canvas.floor == null:
		return
	var generation: int = _generation
	var jobs: Array[Dictionary] = []
	_children.clear()
	var parent_link: AtlasMapLink = _parent_link()
	if parent_link == null:
		_parent.clear()
	else:
		var floor_id: String = source_floor_id if not source_floor_id.is_empty() else parent_link.source_floor_id
		var placement: AtlasPlacement = _placement(parent_link)
		var spatial: bool = placement != null and not placement.symbolic
		if _parent.get("link_id", "") != parent_link.id or _parent.get("floor_id", "") != floor_id \
				or _parent.get("source_map_id", "") != parent_link.source_map_id or _parent.get("spatial", spatial) != spatial:
			_parent.clear()
		if _canvas.show_reference and (not frozen or _parent.is_empty()):
			_parent.clear()
			var job: Dictionary = _parent_job(parent_link)
			if not job.is_empty():
				jobs.append(job)
		elif not frozen:
			_parent.clear()
	omitted_count = 0
	var child_count: int = 0
	if _canvas.preview in [AtlasCanvas.Preview.THUMBNAILS, AtlasCanvas.Preview.OVERLAY]:
		for link: AtlasMapLink in _canvas.campaign.outgoing_links(_canvas.map.id, _canvas.floor.id):
			var document: AtlasMapDocument = _canvas.campaign.get_map(link.target_map_id)
			if document == null or document.floor_by_id(link.target_floor_id) == null or not _visible(link):
				continue
			if child_count >= MAX_CHILD_PREVIEWS:
				omitted_count += 1
				continue
			var placement: AtlasPlacement = _placement(link)
			if not link.placement_id.is_empty() and placement == null:
				continue
			var spatial: bool = placement != null and not placement.symbolic and _canvas.preview == AtlasCanvas.Preview.OVERLAY
			var bounds: Rect2 = placement.child_bounds() if spatial else AtlasPreviewPanel.artwork_bounds(document, document.floor_by_id(link.target_floor_id)).grow(2.0)
			if not bounds.has_area():
				bounds = Rect2(Vector2(-1, -1), Vector2(2, 2))
			jobs.append({"link_id": link.id, "document": document, "floor_id": link.target_floor_id,
				"bounds": bounds, "size": _capture_size(bounds) if spatial else THUMB_SIZE,
				"parent": false, "spatial": spatial})
			child_count += 1
	_canvas.queue_redraw()
	for job: Dictionary in jobs:
		if generation != _generation or not is_inside_tree():
			return
		var document: AtlasMapDocument = job.document
		var bounds: Rect2 = job.bounds
		var pixel_size: Vector2i = job.size
		var audience: String = "editor-reference:" + var_to_str(bounds)
		var image: Image = cache.get_image(document, job.floor_id, pixel_size, audience)
		if image == null:
			image = await _capture.capture(_canvas.campaign, document, job.floor_id, bounds, pixel_size)
			if generation != _generation or not is_inside_tree():
				return
			if image == null:
				continue
			cache.put_image(document, job.floor_id, pixel_size, image, audience)
		var rendered: Dictionary = {"texture": ImageTexture.create_from_image(image),
			"rect": _fit_rect(bounds, pixel_size), "spatial": job.spatial, "link_id": job.link_id,
			"floor_id": job.floor_id, "source_map_id": document.id}
		if job.parent:
			rendered["vertices"] = job.vertices
			rendered["source_points"] = job.source_points
			_parent = rendered
		else:
			_children[job.link_id] = rendered
		_canvas.queue_redraw()


func _parent_link() -> AtlasMapLink:
	var incoming: Array[AtlasMapLink] = _canvas.campaign.incoming_links(_canvas.map.id, _canvas.floor.id)
	var link: AtlasMapLink = _canvas.campaign.link_by_id(source_link_id)
	if link == null and source_link_id.is_empty() and incoming.size() == 1:
		link = incoming[0]
	if link == null or not incoming.has(link):
		return null
	var parent: AtlasMapDocument = _canvas.campaign.get_map(link.source_map_id)
	if parent == null or parent.floor_by_id(link.source_floor_id) == null:
		return null
	if not source_floor_id.is_empty() and parent.floor_by_id(source_floor_id) == null:
		return null
	if not link.placement_id.is_empty() and _placement(link) == null:
		return null
	return link


func _parent_job(link: AtlasMapLink) -> Dictionary:
	var document: AtlasMapDocument = _canvas.campaign.get_map(link.source_map_id)
	var floor_id: String = source_floor_id if not source_floor_id.is_empty() else link.source_floor_id
	if document.floor_by_id(floor_id) == null:
		return {}
	var placement: AtlasPlacement = _placement(link)
	var spatial: bool = placement != null and not placement.symbolic
	var bounds: Rect2
	if spatial:
		bounds = placement.child_to_parent() * placement.child_bounds()
	else:
		bounds = AtlasPreviewPanel.artwork_bounds(document, document.floor_by_id(floor_id)).grow(2.0)
	if not bounds.has_area():
		return {}
	return {"link_id": link.id, "document": document, "floor_id": floor_id,
		"bounds": bounds, "size": _capture_size(bounds) if spatial else THUMB_SIZE,
		"parent": true, "spatial": spatial,
		"vertices": _rect_points(placement.child_bounds()) if spatial else PackedVector2Array(),
		"source_points": placement.child_to_parent() * _rect_points(placement.child_bounds()) if spatial else PackedVector2Array()}


func _visible(link: AtlasMapLink) -> bool:
	var bounds: Rect2 = Rect2(_canvas.local_to_document(Vector2.ZERO), _canvas.size / _canvas.camera_zoom).grow(220.0 / _canvas.camera_zoom)
	var placement: AtlasPlacement = _placement(link)
	if not link.placement_id.is_empty() and placement == null:
		return false
	if placement == null:
		return bounds.has_point(link.anchor)
	return bounds.intersects(placement.child_to_parent() * placement.child_bounds())


func _placement(link: AtlasMapLink) -> AtlasPlacement:
	var value: AtlasPlacement = _canvas.campaign.placement_by_id(link.placement_id)
	return value if value != null and value.parent_map_id == link.source_map_id and value.child_map_id == link.target_map_id else null


func draw_parent(item: CanvasItem) -> void:
	if _parent.is_empty() or not _canvas.show_reference or not _parent.spatial:
		return
	var link: AtlasMapLink = _parent_link()
	var placement: AtlasPlacement = _canvas.campaign.placement_by_id(link.placement_id) if link != null else null
	if placement == null or placement.symbolic:
		return
	item.draw_polygon(_parent.vertices, PackedColorArray([Color(1, 1, 1, _canvas.reference_opacity)]),
		_uvs(_parent.source_points, _parent.rect), _parent.texture)


func draw_children(item: Node2D) -> void:
	var stacks: Dictionary[String, int] = {}
	for link: AtlasMapLink in _canvas.campaign.outgoing_links(_canvas.map.id, _canvas.floor.id):
		if _canvas.preview not in [AtlasCanvas.Preview.THUMBNAILS, AtlasCanvas.Preview.OVERLAY] or not _children.has(link.id):
			continue
		var image: Dictionary = _children[link.id]
		var placement: AtlasPlacement = _canvas.campaign.placement_by_id(link.placement_id)
		if image.spatial and placement != null and not placement.symbolic:
			item.draw_polygon(placement.corners(), PackedColorArray([Color(1, 1, 1, 0.7)]),
				_uvs(_rect_points(placement.child_bounds()), image.rect), image.texture)
		else:
			var point: Vector2 = placement.origin if placement != null else link.anchor
			var key: String = var_to_str(point)
			var offset: int = stacks.get(key, 0)
			stacks[key] = offset + 1
			var size: Vector2 = Vector2(96, 64) / _canvas.camera_zoom
			item.draw_texture_rect(image.texture, Rect2(point + Vector2(24, 18 + offset * 68) / _canvas.camera_zoom, size), false)
	if not _parent.is_empty() and not _parent.spatial and _canvas.show_reference:
		# Symbolic/marker references are explicitly unregistered screen thumbnails.
		var position: Vector2 = _canvas.local_to_document(Vector2(12, 28))
		item.draw_texture_rect(_parent.texture, Rect2(position, Vector2(144, 96) / _canvas.camera_zoom), false,
			Color(1, 1, 1, _canvas.reference_opacity))
		item.draw_string(ThemeDB.fallback_font, _canvas.local_to_document(Vector2(12, 22)),
			"Parent preview · unregistered", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(12 / _canvas.camera_zoom)))
	if omitted_count > 0 and _canvas.preview in [AtlasCanvas.Preview.THUMBNAILS, AtlasCanvas.Preview.OVERLAY]:
		item.draw_string(ThemeDB.fallback_font, _canvas.local_to_document(Vector2(12, _canvas.size.y - 12)),
			"%d more previews — use Search" % omitted_count, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(12 / _canvas.camera_zoom)))


static func _capture_size(bounds: Rect2) -> Vector2i:
	var factor: float = 512.0 / maxf(bounds.size.x, bounds.size.y)
	return Vector2i(maxi(16, roundi(bounds.size.x * factor)), maxi(16, roundi(bounds.size.y * factor)))


static func _fit_rect(bounds: Rect2, size: Vector2i) -> Rect2:
	var zoom: float = minf(size.x / bounds.size.x, size.y / bounds.size.y)
	return Rect2(bounds.get_center() - Vector2(size) / zoom * 0.5, Vector2(size) / zoom)


static func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _uvs(points: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append((point - rect.position) / rect.size)
	return result
