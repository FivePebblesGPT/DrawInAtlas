extends SceneTree
## Seeded, deterministic differential corpus for T-068 native four-corner
## selection. The reference is AtlasFill._allows_pixel(), not an analytic
## reimplementation. Generated only on demand; not an application dependency.

const SIDE: int = 32
const CASE_COUNT: int = 48


func _initialize() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected one output path for the differential oracle")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	for index: int in range(CASE_COUNT):
		var variant: int = index % 6
		var offset: float = float((index * 7) % 5) - 2.0
		var edge: float = [0.0, -0.00001, 0.00001, -0.125, 0.125, 0.5][index % 6]
		var lower: float = 9.0 + float(index % 4) + edge
		var upper: float = 24.0 - float(index % 3) + edge
		var polygon: PackedVector2Array = PackedVector2Array([
			Vector2(lower, lower - 1.0), Vector2(upper, lower - 1.0),
			Vector2(upper, upper), Vector2(lower, upper)])
		if index % 4 == 1:
			polygon.reverse()
		if index % 12 == 11:
			polygon.clear()
		var enabled: bool = index % 12 != 10
		var axes: Array[Transform2D] = [
			Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2.ZERO),
			Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(32, 0)),
			Transform2D(Vector2(1, 0.25), Vector2(0.5, 1), Vector2(-8, 3)),
			Transform2D(Vector2(0, 1), Vector2(-1, 0), Vector2(32, 0)),
			Transform2D(Vector2(1.5, 0), Vector2(0, 0.75), Vector2(-6, 4)),
			Transform2D(Vector2(0.8, 0.6), Vector2(-0.6, 0.8), Vector2(6, -4)),
		]
		var layer: AtlasRasterLayer = AtlasRasterLayer.new()
		layer.transform = axes[variant]
		layer.transform.origin += Vector2(offset, -offset)
		layer.pixels_per_unit = 2.0 if variant == 4 else 1.0
		var scope: AtlasEditScope = AtlasEditScope.new(polygon, enabled)
		var mask: PackedByteArray = PackedByteArray()
		mask.resize(SIDE * SIDE)
		var allowed: int = 0
		for y: int in range(SIDE):
			for x: int in range(SIDE):
				var eligible: bool = AtlasFill._allows_pixel(layer, Vector2i(x, y), scope)
				mask[y * SIDE + x] = 1 if eligible else 0
				if eligible:
					allowed += 1
		var t: Transform2D = layer.transform
		var vertices: Array[Array] = []
		for vertex: Vector2 in polygon:
			vertices.append([vertex.x, vertex.y])
		rows.append({"id": "seed_%02d" % index,
			"transform": [t.x.x, t.x.y, t.y.x, t.y.y, t.origin.x, t.origin.y],
			"density": layer.pixels_per_unit, "polygon": vertices,
			"enabled": enabled, "allowed": allowed,
			"mask_base64": Marshalls.raw_to_base64(mask)})
	var file: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write native quad differential fixture")
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "generator":
		"tests/drawing_t068_quad_differential_oracle.gd", "side": SIDE,
		"godot_version": Engine.get_version_info().get("string", ""), "cases": rows}, "  ") + "\n")
	file.close()
	print("T068_QUAD_DIFFERENTIAL_ORACLE_PASSED: %d cases" % rows.size())
	quit(0)
