extends RefCounted
## Regression-only adapter for historical packed-output oracles from T-095.
## Production Canvas/Document do not use this script. It translates legacy
## test calls to v1's real native handle/batch interface, preserving comparison
## against source-pinned expected pixel sequences without retaining old ABI
## entrypoints in the shipped GDExtension.

var _brush: Object = ClassDB.instantiate("DrawingNativeBrush")
var _handle: int = 0
var _mode: String = ""
var _width: float = 0.0
var _rgba: int = 0
var _clip: Rect2i = Rect2i()
var _preset: String = ""
var _pending: bool = false
var _explicit_batch: bool = false


func _reset() -> void:
	if _handle > 0:
		_brush.call("abort_stroke", _handle)
	_handle = 0
	_pending = false
	_explicit_batch = false


func _start(mode: String, width: float, clip: Rect2i) -> bool:
	if _handle != 0:
		if mode == _mode and width == _width and clip == _clip:
			return true
		_reset()
	_mode = mode
	_width = width
	_clip = clip
	var result: Dictionary = _brush.call("begin_stroke", "historical-ffi-fixture",
		mode, _preset if mode == "Hokusai" else "", width, _rgba, 1, clip)
	_handle = int(result.get("handle", 0)) if result.get("ok", false) else 0
	return _handle != 0


func _samples(points: PackedVector2Array, pressure: float) -> PackedFloat32Array:
	var output: PackedFloat32Array = PackedFloat32Array()
	for point: Vector2 in points:
		output.append_array(PackedFloat32Array([point.x, point.y, pressure, 0.01]))
	return output


func _append(points: PackedVector2Array, pressure: float) -> Dictionary:
	if _pending:
		return {"ok": false, "error": "Pending historical batch"}
	var appended: Dictionary = _brush.call("append_samples", _handle, 1,
		_samples(points, pressure))
	if not appended.get("ok", false):
		return appended
	_pending = true
	var preview: Dictionary = _brush.call("preview_changes", _handle, 1)
	if not preview.get("ok", false):
		acknowledge(false)
		return preview
	if not _explicit_batch:
		acknowledge(true)
	return preview


func acknowledge(accepted: bool) -> bool:
	if not _pending:
		return false
	var ok: bool = bool(_brush.call("acknowledge_batch", _handle, 1, accepted))
	_pending = false
	return ok


func reset_hard() -> void:
	_reset()
	_mode = "NativeHard"


func begin_hard_batch() -> bool:
	if _explicit_batch:
		return false
	_explicit_batch = true
	return true


func commit_hard_batch() -> void:
	acknowledge(true)
	_explicit_batch = false


func rollback_hard_batch() -> void:
	acknowledge(false)
	_explicit_batch = false


func hard_segments(points: PackedVector2Array, width: float, clip: Rect2i) -> Dictionary:
	if not _start("NativeHard", width, clip):
		return {"ok": false, "error": "Begin hard native stroke failed"}
	var result: Dictionary = _append(points, 1.0)
	return {"ok": true, "points": result.get("changes", PackedInt32Array())} \
		if result.get("ok", false) else result


func configure_preset(myb: String, width: float, rgba: int) -> bool:
	_reset()
	_preset = myb
	_rgba = rgba
	return _start("Hokusai", width, Rect2i())


func begin_preset_batch() -> bool:
	if _explicit_batch:
		return false
	_explicit_batch = true
	return true


func commit_preset_batch() -> void:
	acknowledge(true)
	_explicit_batch = false


func rollback_preset_batch() -> void:
	acknowledge(false)
	_explicit_batch = false


func preset_segments(points: PackedVector2Array, pressure: float) -> PackedInt32Array:
	if _handle <= 0 or _mode != "Hokusai":
		return PackedInt32Array()
	var result: Dictionary = _append(points, pressure)
	return result.get("changes", PackedInt32Array()) if result.get("ok", false) \
		else PackedInt32Array()
