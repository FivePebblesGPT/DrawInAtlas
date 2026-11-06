class_name AtlasToken
extends Resource
## A GM-authored tabletop marker on one floor/detail level via AtlasTokenLayer.
## Tokens are not artwork strokes and are never implicit player publications.

const MIN_RADIUS: float = 3.0
const MAX_RADIUS: float = 128.0
const MAX_LABEL: int = 48
const MAX_ID: int = 80

@export_storage var id: String = ""
@export_storage var position: Vector2 = Vector2.ZERO
@export_storage var radius: float = 16.0
@export_storage var label: String = "Token"
@export_storage var tint: Color = Color("#5bb9e9")


func _init(token_id: String = "", at: Vector2 = Vector2.ZERO, caption: String = "Token") -> void:
	id = token_id
	position = at
	label = caption


func is_valid() -> bool:
	if id.is_empty() or id.length() > MAX_ID:
		return false
	# Stable IDs may enter saves/network payloads later: forbid separators and
	# control characters instead of trusting arbitrary user-provided strings.
	for index: int in range(id.length()):
		var code: int = id.unicode_at(index)
		if not (code >= 48 and code <= 57 or code >= 65 and code <= 90 \
				or code >= 97 and code <= 122 or code == 45 or code == 95):
			return false
	if label.strip_edges().is_empty() or label.length() > MAX_LABEL:
		return false
	for index: int in range(label.length()):
		if label.unicode_at(index) < 32 or label.unicode_at(index) == 127:
			return false
	return position.is_finite() and is_finite(radius) and radius >= MIN_RADIUS \
		and radius <= MAX_RADIUS and is_finite(tint.r) and is_finite(tint.g) \
		and is_finite(tint.b) and is_finite(tint.a) and tint.a > 0.0 \
		and tint.r >= 0.0 and tint.r <= 1.0 and tint.g >= 0.0 and tint.g <= 1.0 \
		and tint.b >= 0.0 and tint.b <= 1.0 and tint.a <= 1.0


func copy() -> AtlasToken:
	var result: AtlasToken = AtlasToken.new(id, position, label)
	result.radius = radius
	result.tint = tint
	return result


func to_dict() -> Dictionary:
	return {"id": id, "position": [position.x, position.y], "radius": radius,
		"label": label, "tint": [tint.r, tint.g, tint.b, tint.a]}


static func from_dict(data: Dictionary) -> AtlasToken:
	var identity: Variant = data.get("id")
	var name: Variant = data.get("label")
	var point: Variant = data.get("position")
	var size: Variant = data.get("radius")
	var rgba: Variant = data.get("tint")
	if not identity is String or not name is String or not point is Array or point.size() != 2 \
			or not size is float and not size is int or not rgba is Array or rgba.size() != 4:
		return null
	for value: Variant in point + rgba:
		if not value is float and not value is int or not is_finite(float(value)):
			return null
	var token: AtlasToken = AtlasToken.new(identity, Vector2(float(point[0]), float(point[1])), name)
	token.radius = float(size)
	token.tint = Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3]))
	return token if token.is_valid() else null
