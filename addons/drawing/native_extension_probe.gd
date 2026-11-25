extends RefCounted


static func run() -> int:
	if not ClassDB.class_exists("DrawingNativeBrush") or not ClassDB.class_exists("DrawingNativeTiles"):
		printerr("NATIVE_EXTENSION_MISSING: DrawingNativeBrush/DrawingNativeTiles not registered")
		return 1
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var tiles: Object = ClassDB.instantiate("DrawingNativeTiles")
	if brush == null or tiles == null or not brush.has_method("begin_stroke"):
		printerr("NATIVE_EXTENSION_ABI_MISMATCH: native constructors/stroke ABI unavailable")
		return 1
	print("NATIVE_EXTENSION_READY")
	return 0
