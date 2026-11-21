class_name DrawingBrushSettings
extends RefCounted
## Presentation-independent MyPaint settings mapping. Rust still owns rendering.
## One immutable preset string is prepared at pointer-down, never during a dab.

const PRESETS: Array[String] = ["hard", "soft", "ink", "airbrush"]
const NAMES: Array[String] = ["Hard Round", "Soft", "Ink", "Airbrush"]
const DESCRIPTIONS: Array[String] = [
	"Opaque, hard-edged round tip; stylus pressure controls size and opacity",
	"Feathered translucent tip; no grain or spray particles",
	"Firm ink pen; pressure and motion shape its edge",
	"Smooth, diffuse low-opacity tip; no grain or spray particles",
]
const FILES: Dictionary = {
	"hard": "res://addons/drawing/brushes/hard_round.myb",
	"soft": "res://addons/drawing/brushes/soft.myb",
	"ink": "res://addons/drawing/brushes/ink.myb",
	"airbrush": "res://addons/drawing/brushes/airbrush.myb",
}
const PREVIEW_ROOT: String = "res://addons/drawing/brushes/previews/"
## Hokusai evaluates dabs_per_actual_radius in its stroke spacing equation.
## Keep this bounded: very high densities can multiply native dab work.
const DENSITY_MIN: float = 1.0
const DENSITY_MAX: float = 8.0


static func preset_data(preset: String) -> Dictionary:
	var path: String = str(FILES.get(preset, ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("settings") is Dictionary:
		return {}
	return parsed


static func default_hardness(preset: String) -> float:
	var data: Dictionary = preset_data(preset)
	if data.is_empty():
		return 1.0
	return float((data["settings"]["hardness"] as Dictionary)["base_value"])


static func default_density(preset: String) -> float:
	var data: Dictionary = preset_data(preset)
	if data.is_empty():
		return -1.0
	var setting: Variant = (data["settings"] as Dictionary).get("dabs_per_actual_radius")
	if not setting is Dictionary or not setting.get("base_value") is float:
		return -1.0
	return float(setting["base_value"])


## Opacity is a percentage of the preset's native base opaque value; pressure
## input maps and opaque_multiply curves remain intact. Hardness changes its
## MyPaint base value while retaining native speed/pressure shaping.
static func configured_preset(preset: String, opacity: float, hardness: float,
		density: float = -1.0) -> String:
	if density == -1.0:
		density = default_density(preset)
	if not is_finite(opacity) or not is_finite(hardness) or not (0.0 <= opacity and opacity <= 1.0) \
			or not (0.0 <= hardness and hardness <= 1.0) or not is_finite(density) \
			or not (DENSITY_MIN <= density and density <= DENSITY_MAX):
		return ""
	var path: String = str(FILES.get(preset, ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var raw: String = FileAccess.get_file_as_string(path)
	# Keep the exact bundled native bytes (including pressure curves and numeric
	# precision) for the common 100% / default-hardness configuration.
	if is_equal_approx(opacity, 1.0) and is_equal_approx(hardness, default_hardness(preset)) \
			and is_equal_approx(density, default_density(preset)):
		return raw
	var data: Dictionary = preset_data(preset)
	if data.is_empty():
		return ""
	data["version"] = int(data["version"]) # Godot JSON parses integers as floats.
	var settings: Dictionary = data["settings"]
	var opaque_setting: Dictionary = settings["opaque"]
	opaque_setting["base_value"] = float(opaque_setting["base_value"]) * opacity
	var hardness_setting: Dictionary = settings["hardness"]
	hardness_setting["base_value"] = hardness
	var density_setting: Dictionary = settings["dabs_per_actual_radius"]
	density_setting["base_value"] = density
	return JSON.stringify(data)
