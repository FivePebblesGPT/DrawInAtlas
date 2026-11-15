extends RefCounted
## Test-only wrapper: translate historical scripted delta/coverage fixtures to
## the single transaction contract. Does not affect production stroke handling.
const ScriptedNative = preload("res://tests/t147_scripted_source_adapter.gd")


static func paint_pigment(edit: DrawingEditSession, path: PackedVector2Array,
		rgba: int, selection: DrawingSelection, producer: Object,
		clip: Rect2i = Rect2i(), pressure: float = 1.0) -> DrawingResult:
	if edit._native_handle == 0:
		var native: Object = producer if producer.has_method("stroke_abi_version") \
			else ScriptedNative.new(producer, "Hokusai")
		var started: DrawingResult = edit.begin_native_stroke(native, "Hokusai",
			"", 24.0, rgba, clip)
		if not started.ok:
			return started
	return edit.paint_path_native(path, rgba, false, selection, pressure)


static func paint_hard(edit: DrawingEditSession, path: PackedVector2Array,
		rgba: int, width: float, erase: bool, selection: DrawingSelection,
		producer: Object, clip: Rect2i = Rect2i()) -> DrawingResult:
	if edit._native_handle == 0:
		var native: Object = producer if producer.has_method("stroke_abi_version") \
			else ScriptedNative.new(producer, "NativeHard")
		var started: DrawingResult = edit.begin_native_stroke(native, "NativeHard",
			"", width, rgba, clip)
		if not started.ok:
			return started
	return edit.paint_path_native(path, rgba, erase, selection)
