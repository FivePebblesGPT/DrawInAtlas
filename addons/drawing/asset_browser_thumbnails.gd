class_name DrawingAssetBrowserThumbnails
extends RefCounted
## T-065: on-demand, bounded preview images for already indexed Object sources.
## Never writes to the source or scans a directory independently of the index.

const CAPACITY: int = 24
const SIZE: int = 48
const MAX_RENDER_EDGE: int = 192

var _images: Dictionary[String, Image] = {}
var _order: Array[String] = []
var renders: int = 0
var _linked_keys: Dictionary = {}
var _catalog_keys: Dictionary = {}


func count() -> int:
	return _images.size()


func clear() -> void:
	_images.clear()
	_order.clear()
	_linked_keys.clear()
	_catalog_keys.clear()


## Only a changed source's bytes should discard a previously rendered preview.
## Retain a cached image when the index is refreshed without changes.
func reconcile(entries: Array[Dictionary], complete_index: bool = true) -> void:
	var keys: Dictionary = {}
	var revisions_by_id: Dictionary = {}
	for entry: Dictionary in entries:
		var key: String = _key(entry)
		keys[key] = true
		revisions_by_id[String(entry.get("id", "")) + ":"] = key
	var changed: bool = complete_index and keys != _catalog_keys
	if complete_index:
		_catalog_keys = keys
	for key: String in _order.duplicate():
		# Standalone scans are complete and can drop missing files. Atlas pages
		# are *not* complete indexes: preserve off-page LRU entries, but evict
		# a prior revision if the current page exposes changed bytes for its ID.
		var invalid: bool = complete_index and (not keys.has(key) or (changed and _linked_keys.has(key)))
		if not complete_index:
			for prefix: String in revisions_by_id:
				if key.begins_with(prefix) and key != revisions_by_id[prefix]:
					invalid = true
					break
		if invalid:
			_images.erase(key)
			_linked_keys.erase(key)
			_order.erase(key)


func contains(entry: Dictionary) -> bool:
	return _images.has(_key(entry))


func preview(index: DrawingAssetBrowserIndex, entry: Dictionary) -> DrawingResult:
	if index == null or not index.safe_to_open(entry):
		return DrawingResult.failure("STALE_SOURCE", "Refresh the Asset Browser before previewing a changed source")
	var key: String = _key(entry)
	if _images.has(key):
		_order.erase(key)
		_order.append(key)
		return DrawingResult.success(_images[key])
	var opened: DrawingResult = DrawingObjectEditorFile.open(String(entry["path"]))
	if not opened.ok:
		return opened
	var data: Dictionary = opened.value
	if String(data["source_id"]) != String(entry.get("embedded_id", entry["id"])) or \
			int(data["source_revision"]) != int(entry.get("embedded_revision", entry["revision"])) or \
			FileAccess.get_sha256(String(entry["path"])) != entry["sha256"]:
		return DrawingResult.failure("STALE_SOURCE", "Object source changed while making its preview")
	var document: DrawingDocument = data["document"]
	var linked: bool = not document.linked_records().is_empty()
	if linked:
		if not DrawingLinkedObjects.flat_entry(index, entry):
			return DrawingResult.failure("LINK_ROOT", "Standalone links require a flat Object catalog")
		var resolved: DrawingResult = DrawingLinkedObjects.resolve(document, index)
		if not resolved.ok:
			return resolved
		document.set_linked_sources(resolved.value)
	var bounds: Rect2i = data["bounds"]
	var origin: Vector2i = data["origin"]
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		bounds = Rect2i(origin - Vector2i(64, 64), Vector2i(128, 128))
	# The renderer's pixel budget is bounded. Very large authoring frames show
	# their center crop rather than allocating unbounded source textures.
	var width: int = mini(bounds.size.x, MAX_RENDER_EDGE)
	var height: int = mini(bounds.size.y, MAX_RENDER_EDGE)
	var sample: Rect2i = Rect2i(bounds.position + (bounds.size - Vector2i(width, height)) / 2,
		Vector2i(width, height))
	var rendered: DrawingResult = DrawingRenderer.render(data["document"], sample,
		0, 0, MAX_RENDER_EDGE * MAX_RENDER_EDGE)
	if not rendered.ok:
		return rendered
	var image: Image = rendered.value
	# Scale only the small bounded sample, preserving transparent pixels.
	var target_width: int = maxi(1, roundi(float(width) * float(SIZE) / float(maxi(width, height))))
	var target_height: int = maxi(1, roundi(float(height) * float(SIZE) / float(maxi(width, height))))
	image.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
	var preview_image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	preview_image.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()),
		Vector2i((SIZE - target_width) / 2, (SIZE - target_height) / 2))
	_images[key] = preview_image
	if linked:
		_linked_keys[key] = true
	_order.append(key)
	if _order.size() > CAPACITY:
		var oldest: String = _order.pop_front()
		_images.erase(oldest)
		_linked_keys.erase(oldest)
	renders += 1
	return DrawingResult.success(preview_image)


func _key(entry: Dictionary) -> String:
	return "%s:%s" % [String(entry.get("id", "")), String(entry.get("sha256", ""))]
