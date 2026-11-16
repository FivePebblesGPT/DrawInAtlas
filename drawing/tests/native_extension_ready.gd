extends SceneTree
## Fail startup before drawing if the required Hokusai GDExtension did not register.

func _initialize() -> void:
	if not ClassDB.class_exists("DrawingNativeBrush") or not ClassDB.class_exists("DrawingNativeTiles"):
		printerr("NATIVE_EXTENSION_MISSING: DrawingNativeBrush/DrawingNativeTiles not registered")
		quit(1)
		return
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var tiles: Object = ClassDB.instantiate("DrawingNativeTiles")
	if brush == null or tiles == null or not brush.has_method("begin_stroke"):
		printerr("NATIVE_EXTENSION_ABI_MISMATCH: native constructors/stroke ABI unavailable")
		quit(1)
		return
	print("NATIVE_EXTENSION_READY")
	quit(0)
