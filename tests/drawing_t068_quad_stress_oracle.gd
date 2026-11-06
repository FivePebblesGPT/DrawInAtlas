extends SceneTree
## Reproducible Godot-authored convex-scope differential stress witness.
## Never part of Drawing/Atlas runtime; AtlasFill is the independent oracle.

const SIDE: int = 24
const CASE_COUNT: int = 96
const SEED: int = 0x68048


func _initialize() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected one fixture output path")
		quit(1)
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var results: Array[Dictionary] = []
	for i: int in range(CASE_COUNT):
		var enabled: bool = i % 17 != 0
		var density: float = [0.5, 1.0, 1.5, 2.0][i % 4]
		var polygon: PackedVector2Array = PackedVector2Array()
		var center: Vector2 = Vector2(rng.randf_range(7.0, 17.0), rng.randf_range(7.0, 17.0))
		var vertex_count: int = 3 + i % 6
		var angle: float = rng.randf_range(-PI, PI)
		var radius: float = rng.randf_range(5.0, 11.0)
		for vertex_index: int in range(vertex_count):
			var direction: float = angle + TAU * float(vertex_index) / float(vertex_count)
			polygon.append(center + radius * Vector2(cos(direction), sin(direction)))
		# Every eighth case stresses exact and nearly exact axis-aligned boundaries.
		if i % 8 == 2:
			var epsilon: float = [0.0, 0.00001, -0.00001, 0.0001][(i / 8) % 4]
			var left: float = 4.0 + epsilon
			var right: float = 19.0 + epsilon
			polygon = PackedVector2Array([
				Vector2(left, 5.0), Vector2(right, 5.0),
				Vector2(right, 19.0), Vector2(left, 19.0)])
		if i % 7 == 1:
			polygon.reverse()
		if i % 19 == 0:
			polygon.clear()
		var layer: AtlasRasterLayer = AtlasRasterLayer.new()
		var x_axis: Vector2 = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
			Vector2(1.0, 0.25), Vector2(0.0, 1.0),
			Vector2(1.5, -0.2), Vector2(0.8, 0.6)][i % 6]
		var y_axis: Vector2 = [Vector2(0.0, 1.0), Vector2(0.0, 1.0),
			Vector2(0.4, 1.0), Vector2(-1.0, 0.0),
			Vector2(0.1, 0.75), Vector2(-0.6, 0.8)][i % 6]
		layer.transform = Transform2D(x_axis, y_axis,
			Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)))
		layer.pixels_per_unit = density
		var scope: AtlasEditScope = AtlasEditScope.new(polygon, enabled)
		var mask: PackedByteArray = PackedByteArray()
		mask.resize(SIDE * SIDE)
		var selected: int = 0
		for y: int in range(SIDE):
			for x: int in range(SIDE):
				var allowed: bool = AtlasFill._allows_pixel(layer, Vector2i(x, y), scope)
				mask[y * SIDE + x] = 1 if allowed else 0
				if allowed:
					selected += 1
		var t: Transform2D = layer.transform
		var vertices: Array[Array] = []
		for vertex: Vector2 in polygon:
			vertices.append([vertex.x, vertex.y])
		results.append({"id": "stress_%03d" % i,
			"transform": [t.x.x, t.x.y, t.y.x, t.y.y, t.origin.x, t.origin.y],
			"density": density, "polygon": vertices, "enabled": enabled,
			"allowed": selected, "mask_base64": Marshalls.raw_to_base64(mask)})
	var file: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot create quad stress fixture")
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "generator":
		"tests/drawing_t068_quad_stress_oracle.gd", "side": SIDE,
		"godot_version": Engine.get_version_info().get("string", ""),
		"seed": SEED, "cases": results}, "  ") + "\n")
	file.close()
	print("T068_QUAD_STRESS_ORACLE_PASSED: %d cases" % results.size())
	quit(0)
