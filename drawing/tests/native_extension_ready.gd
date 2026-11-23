extends SceneTree
## Fail startup before drawing if the required Hokusai GDExtension did not register.

func _initialize() -> void:
	quit(preload("res://addons/drawing/native_extension_probe.gd").run())
