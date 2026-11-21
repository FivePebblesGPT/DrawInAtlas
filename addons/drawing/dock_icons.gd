class_name DrawingDockIcons
extends RefCounted
## Shared identity for expanded dock, minimized rail, flyout and floating tabs.


static func for_panel(panel_id: String) -> Texture2D:
	var named_path: String = "res://addons/drawing/icons/dock_%s.svg" % panel_id
	if ResourceLoader.exists(named_path):
		return load(named_path) as Texture2D
	return load("res://addons/drawing/icons/dock_panel.svg") as Texture2D
