class_name AtlasDrawingComposition
extends RefCounted
## Atlas-only adapter between map-world identity, the canonical Drawing engine,
## Object Assets and the chronological campaign history. No Drawing package
## source imports this class or any Atlas type.

signal changed
signal composition_error(message: String)

const TILE_VIEW: int = 128
const MAX_VIEW_PIXELS: int = 1048576
const MAX_CACHE: int = 96

var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
var library: AtlasObjectLibrary
var history: AtlasEditHistory
var campaign: AtlasCampaign
var context_provider: Callable
var active_layer_by_detail: Dictionary[String, String] = {}
var selected_instance_id: String = ""
var _gesture: DrawingEditSession
var _gesture_mask: DrawingSelection
var _gesture_context: DrawingHistoryContext
var _gesture_anchor: Dictionary = {}
var _cached_frames: Dictionary[String, Image] = {}
var _cache_order: Array[String] = []


func _init(timeline: AtlasEditHistory = null, assets: AtlasObjectLibrary = null,
		provider: Callable = Callable()) -> void:
	history = timeline
	context_provider = provider
	set_library(assets)


func set_library(assets: AtlasObjectLibrary) -> void:
	if library != null:
		if library.asset_published.is_connected(_on_asset_change):
			library.asset_published.disconnect(_on_asset_change)
		if library.instances_changed.is_connected(_on_instance_change):
			library.instances_changed.disconnect(_on_instance_change)
	library = assets
	if library != null:
		library.asset_published.connect(_on_asset_change)
		library.instances_changed.connect(_on_instance_change)
	invalidate()


func _on_asset_change(_asset_id: String, _revision: int) -> void:
	invalidate()


func _on_instance_change(_instance_ids: Array) -> void:
	invalidate()


func attach_campaign(source: AtlasCampaign) -> DrawingResult:
	cancel_stroke()
	var bound: DrawingResult = registry.attach_campaign(source)
	if bound.ok:
		campaign = source
		selected_instance_id = ""
		invalidate()
	return bound


func invalidate() -> void:
	_cached_frames.clear()
	_cache_order.clear()
	changed.emit()


func _detail_key(map_id: String, floor_id: String, level: int) -> String:
	return JSON.stringify([map_id, floor_id, level])


## This only constructs a generic layer when an actual paint gesture begins.
## A blank higher detail remains a blank DrawingDocument until painted.
func editable_layer(map_id: String, floor_id: String, level: int) -> DrawingResult:
	var ensured: DrawingResult = registry.ensure_detail(map_id, floor_id, level)
	if not ensured.ok:
		return ensured
	var found: DrawingResult = registry.document_at(map_id, floor_id, level, true)
	if not found.ok:
		return found
	var document: DrawingDocument = found.value
	var key: String = _detail_key(map_id, floor_id, level)
	var layer_id: String = active_layer_by_detail.get(key, "")
	if document.has_node(layer_id) and document.node_metadata(layer_id)["kind"] == DrawingLayerNode.RASTER:
		return DrawingResult.success({"document": document, "layer_id": layer_id})
	for candidate: String in document.list_children():
		var metadata: Dictionary = document.node_metadata(candidate)
		if metadata["kind"] == DrawingLayerNode.RASTER and metadata["visible"] and not metadata["locked"]:
			active_layer_by_detail[key] = candidate
			return DrawingResult.success({"document": document, "layer_id": candidate})
	var created: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Atlas painting")
	if not created.ok:
		return created
	active_layer_by_detail[key] = String(created.value)
	return DrawingResult.success({"document": document, "layer_id": String(created.value)})


func _world_ticks(point: Vector2) -> DrawingResult:
	if not point.is_finite() or absf(point.x) > 3.0e12 or absf(point.y) > 3.0e12:
		return DrawingResult.failure("COORD_RANGE", "Outside supported map-world range")
	return DrawingResult.success({"x": floori(point.x * AtlasWorldSpace.TICKS_PER_UNIT),
		"y": floori(point.y * AtlasWorldSpace.TICKS_PER_UNIT)})


func _context(map_id: String, floor_id: String, level: int,
		layer_id: String, document: DrawingDocument) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = null
	if context_provider.is_valid():
		result = context_provider.call() as DrawingHistoryContext
	if result == null:
		result = DrawingHistoryContext.new()
	result = result.detached_copy()
	result.map_id = map_id
	result.floor_group_id = floor_id
	result.detail_group_id = str(level)
	result.document_id = document.id
	result.selected_layer_ids = [layer_id]
	return result


## Atlas supplies a convex, frozen board-cell mask. The generic Drawing
## session receives only a pixel selection, never an Atlas grid or link type.
## A huge mask fails closed rather than allocating an unbounded bitmap.
func _selection_mask(polygon: PackedVector2Array, enabled: bool,
		num: int, den: int, origin: Vector2i = Vector2i.ZERO) -> DrawingResult:
	if not enabled:
		return DrawingResult.success(null)
	if polygon.size() < 3:
		return DrawingResult.success(DrawingSelection.new(Rect2i(), true))
	var min_point: Vector2 = polygon[0]
	var max_point: Vector2 = polygon[0]
	for vertex: Vector2 in polygon:
		if not vertex.is_finite() or absf(vertex.x) > 1000000000.0 or absf(vertex.y) > 1000000000.0:
			return DrawingResult.failure("MASK_RANGE", "Grid mask outside supported coordinate range")
		min_point = min_point.min(vertex)
		max_point = max_point.max(vertex)
	var density: float = float(num) / float(den)
	var first: Vector2i = Vector2i(floori(min_point.x * density) - 1,
		floori(min_point.y * density) - 1)
	var size: Vector2i = Vector2i(ceili(max_point.x * density) - first.x + 1,
		ceili(max_point.y * density) - first.y + 1)
	if size.x <= 0 or size.y <= 0 or size.x > 262144 or size.y > 262144 / size.x:
		return DrawingResult.failure("MASK_LIMIT", "Board mask exceeds bounded pixel budget")
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(first - origin, size), true)
	var mask: Dictionary[Vector2i, bool] = {}
	for y: int in range(first.y, first.y + size.y):
		for x: int in range(first.x, first.x + size.x):
			var center: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / density
			if Geometry2D.is_point_in_polygon(center, polygon):
				mask[Vector2i(x, y) - origin] = true
	if mask.is_empty():
		return DrawingResult.success(DrawingSelection.new(Rect2i(), true))
	selection.set_mask(mask)
	return DrawingResult.success(selection)


func start_stroke(map_id: String, floor_id: String, level: int,
		world_point: Vector2, rgba: int, width_world: float, erase: bool = false,
		mask_polygon: PackedVector2Array = PackedVector2Array(), mask_enabled: bool = false) -> DrawingResult:
	if _gesture != null or history == null or campaign == null or history.active_map_id != map_id:
		return DrawingResult.failure("GESTURE", "No active Atlas history or another stroke is in progress")
	var point: DrawingResult = _world_ticks(world_point)
	if not point.ok:
		return point
	var target: DrawingResult = editable_layer(map_id, floor_id, level)
	if not target.ok:
		return target
	var doc: DrawingDocument = target.value["document"]
	var id: String = target.value["layer_id"]
	var origin: DrawingResult = AtlasWorldSpace.point_to_pixels(point.value["x"],
		point.value["y"], doc.density_numerator, doc.density_denominator)
	if not origin.ok:
		return origin
	var boundary: DrawingResult = _selection_mask(mask_polygon, mask_enabled,
		doc.density_numerator, doc.density_denominator, Vector2i(origin.value["x"], origin.value["y"]))
	if not boundary.ok:
		return boundary
	var started: DrawingResult = registry.begin_world_gesture(map_id, floor_id, level, id,
		point.value["x"], point.value["y"])
	if not started.ok:
		return started
	_gesture = started.value["session"]
	_gesture_mask = boundary.value
	_gesture_context = _context(map_id, floor_id, level, id, doc)
	_gesture_anchor = {"x": point.value["x"], "y": point.value["y"],
		"num": doc.density_numerator, "den": doc.density_denominator,
		"rgba": rgba, "width": maxf(0.5, width_world * float(doc.density_numerator) / float(doc.density_denominator)),
		"erase": erase}
	var drawn: DrawingResult = append_stroke(world_point)
	if not drawn.ok:
		cancel_stroke()
	return drawn


func append_stroke(world_point: Vector2) -> DrawingResult:
	if _gesture == null:
		return DrawingResult.failure("GESTURE", "No active stroke")
	var converted: DrawingResult = _world_ticks(world_point)
	if not converted.ok:
		return converted
	var density_num: int = _gesture_anchor["num"]
	var density_den: int = _gesture_anchor["den"]
	var position: DrawingResult = AtlasWorldSpace.point_to_pixels(converted.value["x"],
		converted.value["y"], density_num, density_den)
	var origin: DrawingResult = AtlasWorldSpace.point_to_pixels(_gesture_anchor["x"],
		_gesture_anchor["y"], density_num, density_den)
	if not position.ok:
		return position
	if not origin.ok:
		return origin
	var local: Vector2 = Vector2(float(int(position.value["x"]) - int(origin.value["x"])) + 0.5,
		float(int(position.value["y"]) - int(origin.value["y"])) + 0.5)
	return _gesture.paint_path(PackedVector2Array([local]), _gesture_anchor["rgba"],
		_gesture_anchor["width"], _gesture_anchor["erase"], _gesture_mask)


func finish_stroke() -> DrawingResult:
	if _gesture == null:
		return DrawingResult.failure("GESTURE", "No active stroke")
	var session: DrawingEditSession = _gesture
	var before: DrawingHistoryContext = _gesture_context
	_gesture = null
	_gesture_context = null
	_gesture_mask = null
	_gesture_anchor.clear()
	if session.change_count() == 0:
		session.cancel()
		return DrawingResult.success(false)
	var committed: DrawingResult = history.commit_drawing(session, before, before.detached_copy())
	if not committed.ok:
		session.cancel()
		composition_error.emit(committed.message)
	else:
		invalidate()
	return committed


func cancel_stroke() -> void:
	if _gesture != null:
		_gesture.cancel()
	_gesture = null
	_gesture_context = null
	_gesture_mask = null
	_gesture_anchor.clear()


func stroke_active() -> bool:
	return _gesture != null


## A reusable Object is always a separate Atlas placement, never a map layer.
func place_asset(asset_id: String, map_id: String, floor_id: String, level: int,
		transform: Transform2D) -> DrawingResult:
	if library == null or campaign == null or campaign.get_map(map_id) == null or \
		campaign.get_map(map_id).floor_by_id(floor_id) == null:
		return DrawingResult.failure("INSTANCE", "Unknown Atlas placement target")
	var result: DrawingResult = library.place(asset_id, map_id, floor_id,
		"D%d" % level, transform)
	if result.ok:
		invalidate()
	return result


func select_instance(map_id: String, floor_id: String, level: int,
		world_point: Vector2) -> DrawingResult:
	selected_instance_id = ""
	if library == null:
		return DrawingResult.success("")
	if not world_point.is_finite():
		return DrawingResult.failure("COORD_RANGE", "Invalid hit-test point")
	var candidates: Array[String] = registry.visible_placements(library, map_id, floor_id, level)
	candidates.reverse() # newest placement is visually on top
	for instance_id: String in candidates:
		var hit: DrawingResult = library.hit_test(instance_id, world_point)
		if not hit.ok:
			return hit
		if hit.value is bool and hit.value:
			selected_instance_id = instance_id
			break
	return DrawingResult.success(selected_instance_id)


func _cache_key(map_id: String, floor_id: String, level: int,
		view: Rect2i, anchor_x: int, anchor_y: int) -> String:
	var found: DrawingResult = registry.document_at(map_id, floor_id, level)
	var doc: DrawingDocument = found.value if found.ok else null
	var instances: Array[Dictionary] = []
	if library != null:
		for id: String in registry.visible_placements(library, map_id, floor_id, level):
			var instance: Dictionary = library.instance_info(id)
			var asset: Dictionary = library.asset_info(instance["source_id"])
			instances.append({"id": id, "revision": instance["revision"],
				"transform": instance["transform"], "asset_revision": asset.get("revision", 0)})
	return JSON.stringify([map_id, floor_id, level, view.position.x, view.position.y,
		view.size.x, view.size.y, anchor_x, anchor_y,
		doc.id if doc != null else "", doc.revision if doc != null else -1, instances])


func _asset_bounds(asset_id: String) -> Rect2i:
	var result: DrawingResult = library.authored_bounds(asset_id)
	return result.value if result.ok else Rect2i()


## Conservative world-space extents for preview framing. Inspect sparse tile
## addresses only (no full-image scan); object frames are transformed from
## asset-local coordinates. This must not change document/asset revisions.
func authored_bounds_world(map_id: String, floor_id: String, level: int) -> Rect2:
	var extents: Rect2 = Rect2()
	var has_bounds: bool = false
	var found: DrawingResult = registry.document_at(map_id, floor_id, level)
	var document: DrawingDocument = found.value if found.ok else null
	if document != null:
		var density: float = float(document.density_numerator) / float(document.density_denominator)
		var queued: Array[Dictionary] = [{"id": DrawingDocument.ROOT_ID, "visible": true}]
		while not queued.is_empty():
			var entry: Dictionary = queued.pop_back()
			for child_id: String in document.list_children(entry["id"]):
				var meta: Dictionary = document.node_metadata(child_id)
				if not entry["visible"] or not meta["visible"]:
					continue
				if meta["kind"] == DrawingLayerNode.GROUP:
					queued.append({"id": child_id, "visible": true})
				elif meta["kind"] == DrawingLayerNode.RASTER:
					for key: String in document.tile_keys(child_id):
						var coordinates: PackedStringArray = key.split(",")
						if coordinates.size() != 2:
							continue
						# Signed tile coordinates are 64-bit; don't narrow them to
						# Vector2i just to calculate a preview viewport.
						var stride_world: float = float(document.tile_stride) / density
						var tile_bounds: Rect2 = Rect2(Vector2(float(coordinates[0].to_int()) * stride_world,
							float(coordinates[1].to_int()) * stride_world), Vector2.ONE * stride_world)
						extents = extents.merge(tile_bounds) if has_bounds else tile_bounds
						has_bounds = true
	if library != null:
		for instance_id: String in registry.visible_placements(library, map_id, floor_id, level):
			var instance: Dictionary = library.instance_info(instance_id)
			var frame: Rect2i = _asset_bounds(String(instance.get("source_id", "")))
			if not frame.has_area():
				continue
			var parts: Array = instance["transform"]
			var transform: Transform2D = Transform2D(
				Vector2(float(parts[0]), float(parts[1])),
				Vector2(float(parts[2]), float(parts[3])),
				Vector2(float(parts[4]), float(parts[5])))
			var corners: Array[Vector2] = [Vector2(frame.position),
				Vector2(frame.end.x, frame.position.y), Vector2(frame.end),
				Vector2(frame.position.x, frame.end.y)]
			var world_bounds: Rect2 = Rect2(transform * corners[0], Vector2.ZERO)
			for corner: Vector2 in corners.slice(1):
				world_bounds = world_bounds.expand(transform * corner)
			extents = extents.merge(world_bounds) if has_bounds else world_bounds
			has_bounds = true
	return extents if has_bounds else Rect2()


## Read-only bounded compositing: no interactive AtlasCanvas and no mutation of
## DrawingDocuments/asset source bytes. Image output is always detached.
func render_region(map_id: String, floor_id: String, level: int, view: Rect2i,
		anchor_x: int = 0, anchor_y: int = 0) -> DrawingResult:
	if view.size.x <= 0 or view.size.y <= 0 or view.size.x > MAX_VIEW_PIXELS \
			or view.size.y > MAX_VIEW_PIXELS / view.size.x:
		return DrawingResult.failure("RENDER_LIMIT", "Read-only frame exceeds pixel limit")
	var key: String = _cache_key(map_id, floor_id, level, view, anchor_x, anchor_y)
	if _cached_frames.has(key):
		return DrawingResult.success((_cached_frames[key] as Image).duplicate())
	var base: DrawingResult = registry.render_detail_at(map_id, floor_id, level, view, anchor_x, anchor_y)
	if not base.ok:
		return base
	var result: Image = base.value
	if library != null:
		var doc_rec: Dictionary = {}
		for f: Dictionary in registry.projection(map_id):
			if f["id"] == floor_id:
				for d: Dictionary in f["details"]:
					if d["level"] == level:
						doc_rec = d
		if not doc_rec.is_empty():
			var density: Array = doc_rec["density"]
			var pixels_per_world: float = float(density[0]) / float(density[1])
			for id: String in registry.visible_placements(library, map_id, floor_id, level):
				var instance: Dictionary = library.instance_info(id)
				var bounds: Rect2i = _asset_bounds(instance["source_id"])
				if not bounds.has_area() or bounds.size.x > 2048 or bounds.size.y > 2048 \
						or bounds.size.x * bounds.size.y > MAX_VIEW_PIXELS:
					continue # Explicit bounded source frame; no implicit infinite image
				var sampled: DrawingResult = library.render_instance(id, bounds)
				if not sampled.ok:
					return sampled
				if sampled.value.get("status") != "linked":
					continue
				var texture: Image = sampled.value["image"]
				var transform: Transform2D = sampled.value["transform"]
				var inverse: Transform2D = transform.affine_inverse()
				for y: int in range(view.size.y):
					for x: int in range(view.size.x):
						var world: Vector2 = Vector2(float(anchor_x + int(view.position.x) + x) + 0.5,
							float(anchor_y + int(view.position.y) + y) + 0.5) / pixels_per_world
						var local: Vector2 = inverse * world
						var sx: int = floori(local.x) - bounds.position.x
						var sy: int = floori(local.y) - bounds.position.y
						if sx < 0 or sy < 0 or sx >= texture.get_width() or sy >= texture.get_height():
							continue
						var overlay: Color = texture.get_pixel(sx, sy)
						if overlay.a > 0.0:
							result.set_pixel(x, y, result.get_pixel(x, y).blend(overlay))
	_cached_frames[key] = result.duplicate()
	_cache_order.append(key)
	while _cache_order.size() > MAX_CACHE:
		_cached_frames.erase(_cache_order.pop_front())
	return DrawingResult.success(result)


## Explicit world window and output size, usable by overview/search/projector
## clients without constructing the editor's interactive canvas.
func preview(map_id: String, floor_id: String, level: int,
		world_window: Rect2, size: Vector2i) -> DrawingResult:
	if not world_window.has_area() or size.x <= 0 or size.y <= 0 \
			or size.x > 2048 or size.y > 2048 or size.x * size.y > MAX_VIEW_PIXELS:
		return DrawingResult.failure("PREVIEW_LIMIT", "Invalid preview bounds")
	var details: Array[Dictionary] = registry.projection(map_id)
	var density: float = 0.0
	for floor: Dictionary in details:
		if floor["id"] != floor_id:
			continue
		for d: Dictionary in floor["details"]:
			if d["level"] == level:
				density = float(d["density"][0]) / float(d["density"][1])
	if density <= 0.0:
		return DrawingResult.failure("DETAIL", "Missing preview detail")
	var first: Vector2i = Vector2i(floori(world_window.position.x * density),
		floori(world_window.position.y * density))
	var extent: Vector2i = Vector2i(ceili(world_window.size.x * density) + 1,
		ceili(world_window.size.y * density) + 1)
	if extent.x <= 0 or extent.y <= 0 or extent.x > MAX_VIEW_PIXELS \
			or extent.y > MAX_VIEW_PIXELS / extent.x:
		return DrawingResult.failure("PREVIEW_LIMIT", "Source frame too large")
	var frame: DrawingResult = render_region(map_id, floor_id, level, Rect2i(first, extent))
	if not frame.ok:
		return frame
	var image: Image = (frame.value as Image).duplicate()
	image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return DrawingResult.success(image)
