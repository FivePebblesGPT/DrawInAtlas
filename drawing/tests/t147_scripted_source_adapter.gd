extends RefCounted
## A deterministic mock of the versioned ABI for source-stage unit oracles.
## Production uses the real DrawingNativeBrush; these scripted producers were
## already fixed-data fixtures, not substitutes for native integration checks.

var _producer: Object
var _mode: String
var _active: bool = false
var _pending: bool = false
var _handle: int = 0
var _revision: int = -1
var _width: float = 0.0
var _clip: Rect2i = Rect2i()
var _data: PackedInt32Array = PackedInt32Array()
var _batches: int = 0
var _sample_floats: int = 0
var _exported_ints: int = 0
var _calls: int = 0


func _init(producer: Object, mode: String) -> void:
	_producer = producer
	_mode = mode


func stroke_abi_version() -> int:
	return 1


func begin_stroke(_layer: String, mode: String, _preset: String,
		width: float, _rgba: int, source_revision: int, clip: Rect2i) -> Dictionary:
	if _active or mode != _mode:
		return {"ok": false, "error": "Invalid scripted test stroke"}
	_active = true
	_revision = source_revision
	_width = width
	_clip = clip
	_handle += 1
	_calls += 1
	return {"ok": true, "handle": _handle, "abi_version": 1}


func append_samples(handle: int, source_revision: int, packed: PackedFloat32Array) -> Dictionary:
	if not _active or _pending or handle != _handle or source_revision != _revision:
		return {"ok": false, "error": "Invalid scripted test handle/revision/batch"}
	if packed.is_empty() or packed.size() % 4 != 0:
		return {"ok": false, "error": "Invalid packed test samples"}
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(0, packed.size(), 4):
		points.append(Vector2(packed[index], packed[index + 1]))
	if _mode == "Hokusai":
		if _producer.has_method("begin_preset_batch") and not _producer.begin_preset_batch():
			return {"ok": false, "error": "Scripted native pigment begin failed"}
		_data = _producer.preset_segments(points, packed[2])
	else:
		if _producer.has_method("begin_hard_batch") and not _producer.begin_hard_batch():
			return {"ok": false, "error": "Scripted native hard begin failed"}
		var result: Dictionary = _producer.hard_segments(points, _width, _clip)
		if not result.get("ok", false):
			if _producer.has_method("rollback_hard_batch"):
				_producer.rollback_hard_batch()
			return result
		_data = result.get("points", PackedInt32Array())
	_pending = true
	_calls += 1
	_sample_floats += packed.size()
	_exported_ints += _data.size()
	return {"ok": true}


func preview_changes(handle: int, source_revision: int) -> Dictionary:
	if not _pending or handle != _handle or source_revision != _revision:
		return {"ok": false, "error": "No pending scripted test preview"}
	_calls += 1
	return {"ok": true, "format": "xy_rgba" if _mode == "Hokusai" else "xy",
		"changes": _data}


func acknowledge_batch(handle: int, source_revision: int, accepted: bool) -> bool:
	if not _pending or handle != _handle or source_revision != _revision:
		return false
	_pending = false
	_data = PackedInt32Array()
	_calls += 1
	if _mode == "Hokusai":
		if accepted and _producer.has_method("commit_preset_batch"):
			_producer.commit_preset_batch()
		elif not accepted and _producer.has_method("rollback_preset_batch"):
			_producer.rollback_preset_batch()
	else:
		if accepted and _producer.has_method("commit_hard_batch"):
			_producer.commit_hard_batch()
		elif not accepted and _producer.has_method("rollback_hard_batch"):
			_producer.rollback_hard_batch()
	if accepted:
		_batches += 1
	return true


func stroke_stats(handle: int, source_revision: int) -> Dictionary:
	if handle != _handle or source_revision != _revision:
		return {"ok": false}
	_calls += 1
	return {"ok": true, "ffi_calls": _calls, "batches": _batches,
		"input_floats": _sample_floats, "exported_ints": _exported_ints}


func commit_stroke(handle: int, source_revision: int) -> bool:
	if handle != _handle or source_revision != _revision or _pending:
		return false
	_active = false
	return true


func abort_stroke(handle: int) -> bool:
	if handle != _handle or not _active:
		return false
	if _pending:
		acknowledge_batch(handle, _revision, false)
	_active = false
	return true
