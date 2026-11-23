class_name DrawingWorkspacePreferences
extends RefCounted
## App settings only: never stored in `.drawing` or used in content revision checks.

const VERSION: int = 3
const MAX_BYTES: int = 2048
const BRUSH_SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")


static func decode(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("record_selection_history") is bool:
		return {}
	var schema: Variant = value.get("schema")
	# JSON.parse_string produces floats for integer schema versions. Accept
	# only integral finite versions, not fractional/corrupt replacements.
	if not (schema is int or schema is float) or not is_finite(float(schema)) \
			or float(schema) != floorf(float(schema)):
		return {}
	if int(schema) == 1:
		return {"record_selection_history": value["record_selection_history"]}
	if not int(schema) in [2, VERSION] or not value.get("brush") is Dictionary:
		return {}
	var brush: Dictionary = value["brush"]
	if not BRUSH_SETTINGS.PRESETS.has(brush.get("preset")) \
			or not (brush.get("width") is float or brush.get("width") is int) \
			or not (brush.get("opacity") is float or brush.get("opacity") is int) \
			or not brush.get("hardness") is Dictionary:
		return {}
	var width: float = float(brush["width"])
	var opacity: float = float(brush["opacity"])
	if not is_finite(width) or not (1.0 <= width and width <= 96.0) \
			or not is_finite(opacity) or not (0.0 <= opacity and opacity <= 1.0):
		return {}
	var hardness: Dictionary = brush["hardness"]
	for key: Variant in hardness:
		if not BRUSH_SETTINGS.PRESETS.has(key) \
				or not (hardness[key] is float or hardness[key] is int) \
				or not is_finite(float(hardness[key])) \
				or not (0.0 <= float(hardness[key]) and float(hardness[key]) <= 1.0):
			return {}
	var density: Variant = brush.get("density", {}) if int(schema) == 2 else brush.get("density")
	if not density is Dictionary:
		return {}
	for key: Variant in density:
		if not BRUSH_SETTINGS.PRESETS.has(key) \
				or not (density[key] is float or density[key] is int) \
				or not is_finite(float(density[key])) \
				or not (BRUSH_SETTINGS.DENSITY_MIN <= float(density[key]) \
					and float(density[key]) <= BRUSH_SETTINGS.DENSITY_MAX):
			return {}
	return {"record_selection_history": value["record_selection_history"],
		"brush": {"preset": brush["preset"], "width": width,
		"opacity": opacity, "hardness": hardness.duplicate(true),
		"density": (density as Dictionary).duplicate(true)}}


static func read_file(path: String) -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var stream: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if stream == null or stream.get_length() > MAX_BYTES:
			continue
		var parsed: Variant = JSON.parse_string(stream.get_as_text())
		stream.close()
		var checked: Dictionary = decode(parsed)
		if not checked.is_empty():
			return checked
	return {}


static func save_file(path: String, enabled: bool, brush: Dictionary = {}) -> bool:
	if brush.is_empty():
		brush = {"preset": "hard", "width": 3.0, "opacity": 1.0,
			"hardness": {}, "density": {}}
	var document: Dictionary = {"schema": VERSION, "record_selection_history": enabled,
		"brush": brush}
	if decode(document).is_empty():
		return false
	var destination: String = ProjectSettings.globalize_path(path)
	var temporary: String = destination + ".tmp"
	var backup: String = destination + ".bak"
	var stream: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		return false
	stream.store_string(JSON.stringify(document))
	stream.flush()
	stream.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(destination, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(backup, destination)
		DirAccess.remove_absolute(temporary)
		return false
	DirAccess.remove_absolute(backup)
	return true
