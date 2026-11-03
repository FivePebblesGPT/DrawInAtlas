extends RefCounted

# T-068 isolated publication experiment. Not a DrawingDocument implementation.
# The owner calls this only from Godot's main thread; no worker owns an ImageTexture.
var width: int
var height: int
var revision: int = 1
var texture: ImageTexture
var before_publish: Callable
var _pixels: PackedByteArray

func _init(tile_width: int, tile_height: int, source: PackedByteArray) -> void:
	assert(tile_width > 0 and tile_width <= 2048)
	assert(tile_height > 0 and tile_height <= 2048)
	assert(source.size() == tile_width * tile_height * 4)
	width = tile_width
	height = tile_height
	_pixels = source.duplicate()
	texture = ImageTexture.create_from_image(_image())

func _image() -> Image:
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, _pixels)

func snapshot() -> PackedByteArray:
	return _pixels.duplicate()

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "revision": revision,
		"changed": 0, "dirty_rect": Rect2i()}

func replace_source(expected_revision: int, source: PackedByteArray) -> bool:
	if expected_revision != revision or source.size() != width * height * 4:
		return false
	if source == _pixels:
		return true
	_pixels = source.duplicate()
	revision += 1
	texture.update(_image()) # update() uploads the entire texture, not a subrectangle.
	return true

func apply(bridge: Object, expected_revision: int, points: PackedInt32Array,
		mask: PackedByteArray, rgba: int, operation: int) -> Dictionary:
	if bridge == null or not bridge.has_method("apply_checked"):
		return _failure("BRIDGE")
	if expected_revision != revision:
		return _failure("STALE")

	# Snapshot before entering native code; source never aliases writable C++ memory.
	var original: PackedByteArray = _pixels.duplicate()
	var proposed: PackedByteArray = bridge.apply_checked(original, points, mask,
		width, height, rgba, operation)
	if proposed.size() != original.size():
		return _failure("NATIVE")

	var min_x: int = width
	var min_y: int = height
	var max_x: int = -1
	var max_y: int = -1
	var changed: int = 0
	for i: int in range(width * height):
		var offset: int = i * 4
		if proposed[offset] == original[offset] and proposed[offset + 1] == original[offset + 1] \
				and proposed[offset + 2] == original[offset + 2] \
				and proposed[offset + 3] == original[offset + 3]:
			continue
		changed += 1
		var x: int = i % width
		var y: int = i / width
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)

	# The test hook models a publication race after native computation.
	# Revision and source bytes are both checked before any installation.
	if before_publish.is_valid():
		before_publish.call()
	if expected_revision != revision or original != _pixels:
		return _failure("STALE")
	if changed == 0:
		return {"ok": true, "revision": revision, "changed": 0,
			"dirty_rect": Rect2i()}

	_pixels = proposed.duplicate()
	revision += 1
	texture.update(_image())
	return {"ok": true, "revision": revision, "changed": changed,
		"dirty_rect": Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)}
