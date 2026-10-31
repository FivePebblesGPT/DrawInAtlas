class_name AtlasData
extends RefCounted
## Validation of untyped dictionary boundaries (clipboard, cloning, native integrity).


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func integer(value: Variant) -> bool:
	return number(value) and absf(float(value)) <= 2147483647.0 and float(value) == int(value)


static func text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func vector(value: Variant) -> bool:
	return (value is Array and value.size() == 2 and number(value[0]) and number(value[1])
		and Vector2(float(value[0]), float(value[1])).is_finite())


static func coordinate_key(key: Variant) -> bool:
	if not key is String:
		return false
	var parts: PackedStringArray = key.split(",")
	return (parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()
		and key == "%d,%d" % [int(parts[0]), int(parts[1])])
