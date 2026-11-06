class_name DrawingObjectEditorSession
extends RefCounted
## A Drawing-only Object Editor tab. Publication is injected by the host;
## the package never imports an Atlas map, campaign, registry or history type.

signal changed

var document: DrawingDocument
var source_id: String = ""
var source_revision: int = 0
var name: String = ""
## Optional target display name for Save As; source name is unchanged until
## the target has actually been published.
var variant_name: String = ""
## Signed asset-local anchor and optional authoring rectangle. Empty bounds
## mean unrestricted sparse canvas, not a 0x0 clipping mask.
var origin: Vector2i = Vector2i.ZERO
var bounds: Rect2i = Rect2i()
var _published_origin: Vector2i = Vector2i.ZERO
var _published_bounds: Rect2i = Rect2i()
var origin_instance_id: String = ""
var origin_map_id: String = ""
var save_publisher: Callable
var save_as_publisher: Callable
var _published_name: String = ""


func _init(source: DrawingDocument = null, asset_id: String = "",
		revision: int = 0, label: String = "", instance_id: String = "",
		map_id: String = "", local_origin: Vector2i = Vector2i.ZERO,
		local_bounds: Rect2i = Rect2i()) -> void:
	document = source
	source_id = asset_id
	source_revision = revision
	name = label
	_published_name = label
	origin = local_origin
	bounds = local_bounds
	_published_origin = local_origin
	_published_bounds = local_bounds
	origin_instance_id = instance_id
	origin_map_id = map_id


func is_dirty() -> bool:
	return document != null and (document.is_dirty() or name != _published_name
		or origin != _published_origin or bounds != _published_bounds)


func set_name(label: String) -> DrawingResult:
	var clean: String = label.strip_edges()
	if clean.is_empty() or clean.length() > 128 or "\n" in clean or "\r" in clean:
		return DrawingResult.failure("NAME", "Object name must be 1–128 characters on one line")
	name = clean
	changed.emit()
	return DrawingResult.success()


func set_frame(local_origin: Vector2i, local_bounds: Rect2i) -> DrawingResult:
	if local_bounds.size.x < 0 or local_bounds.size.y < 0 or \
			absi(local_origin.x) > 1000000000 or absi(local_origin.y) > 1000000000 or \
			absi(local_bounds.position.x) > 1000000000 or \
			absi(local_bounds.position.y) > 1000000000 or \
			local_bounds.size.x > 1000000000 or local_bounds.size.y > 1000000000:
		return DrawingResult.failure("FRAME", "Object frame exceeds safe signed coordinate limits")
	origin = local_origin
	bounds = local_bounds
	changed.emit()
	return DrawingResult.success()


## A publisher returns a dictionary with the *detached* published document,
## source_id, source_revision and name. Rejected publication leaves this tab
## pointing at the same private draft, preserving its undo stack and dirty flag.
func _publish(publisher: Callable) -> DrawingResult:
	if document == null or not publisher.is_valid():
		return DrawingResult.failure("PUBLISHER", "Object source is not connected to a publisher")
	var result: Variant = publisher.call(self)
	if not result is DrawingResult:
		return DrawingResult.failure("PUBLISHER", "Invalid publication result")
	var published: DrawingResult = result
	if not published.ok:
		return published
	if not published.value is Dictionary:
		return DrawingResult.failure("PUBLISHER", "Publisher did not return a source snapshot")
	var snapshot: Dictionary = published.value
	if not snapshot.get("document") is DrawingDocument or \
			not snapshot.get("source_id") is String or \
			not snapshot.get("source_revision") is int or \
			not snapshot.get("name") is String or \
			not snapshot.get("origin") is Vector2i or \
			not snapshot.get("bounds") is Rect2i:
		return DrawingResult.failure("PUBLISHER", "Malformed publication snapshot")
	document = snapshot["document"]
	source_id = snapshot["source_id"]
	source_revision = snapshot["source_revision"]
	name = snapshot["name"]
	_published_name = name
	variant_name = ""
	origin = snapshot["origin"]
	bounds = snapshot["bounds"]
	_published_origin = origin
	_published_bounds = bounds
	if snapshot.get("detach_origin", false):
		origin_instance_id = ""
		origin_map_id = ""
	changed.emit()
	return DrawingResult.success(source_id)


func save() -> DrawingResult:
	return _publish(save_publisher)


func save_as() -> DrawingResult:
	return _publish(save_as_publisher)
