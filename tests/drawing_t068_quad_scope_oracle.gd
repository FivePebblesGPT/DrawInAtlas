extends SceneTree
## Detached T-068 scope oracle: real AtlasFill._allows_pixel uses all four
## transformed corners. It is not a native/Godot integration test.

const SIDE: int = 64

func _cases() -> Array[Dictionary]:
	return [
		{"id": "rect_identity", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [[14.25, 12.5], [47.75, 12.5], [47.75, 46.25], [14.25, 46.25]], "enabled": true},
		{"id": "rotated", "transform": [0.0, 1.0, -1.0, 0.0, 64.0, 0.0], "density": 1.0,
			"polygon": [[12.25, 17.25], [49.75, 17.25], [49.75, 46.75], [12.25, 46.75]], "enabled": true},
		{"id": "shear", "transform": [1.0, 0.25, 0.5, 1.0, -7.0, 6.0], "density": 1.0,
			"polygon": [[10.2, 12.2], [54.4, 21.2], [63.4, 52.4], [19.2, 43.4]], "enabled": true},
		{"id": "mirror", "transform": [-1.0, 0.0, 0.0, 1.0, 64.0, 2.0], "density": 1.0,
			"polygon": [[13.25, 12.25], [51.75, 12.25], [51.75, 47.75], [13.25, 47.75]], "enabled": true},
		{"id": "nonuniform_density", "transform": [1.5, 0.0, 0.0, 0.75, -8.0, 4.0], "density": 2.0,
			"polygon": [[3.21, 9.21], [35.71, 9.21], [35.71, 22.71], [3.21, 22.71]], "enabled": true},
		{"id": "diamond", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [[32.3, 8.2], [56.2, 32.3], [32.3, 56.2], [8.2, 32.3]], "enabled": true},
		# Exact-edge and vertex ties intentionally exercise Godot's inclusive
		# Geometry2D.is_point_in_polygon contract (including reversed winding).
		{"id": "edge_rect", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [[12.0, 12.0], [52.0, 12.0], [52.0, 52.0], [12.0, 52.0]], "enabled": true},
		{"id": "edge_rect_cw", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [[12.0, 52.0], [52.0, 52.0], [52.0, 12.0], [12.0, 12.0]], "enabled": true},
		{"id": "edge_rotated", "transform": [0.0, 1.0, -1.0, 0.0, 64.0, 0.0], "density": 1.0,
			"polygon": [[12.0, 12.0], [52.0, 12.0], [52.0, 52.0], [12.0, 52.0]], "enabled": true},
		{"id": "edge_sheared", "transform": [1.0, 0.25, 0.5, 1.0, -7.0, 6.0], "density": 1.0,
			"polygon": [[11.0, 21.0], [51.0, 31.0], [71.0, 71.0], [31.0, 61.0]], "enabled": true},
		{"id": "edge_density", "transform": [2.0, 0.0, 0.0, 0.5, -8.0, 4.0], "density": 2.0,
			"polygon": [[4.0, 7.0], [44.0, 7.0], [44.0, 17.0], [4.0, 17.0]], "enabled": true},
		{"id": "edge_diamond", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [[32.0, 8.0], [56.0, 32.0], [32.0, 56.0], [8.0, 32.0]], "enabled": true},
		{"id": "edge_thin", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [[0.0, 0.0], [1.0, 0.0], [1.0, 64.0], [0.0, 64.0]], "enabled": true},
		{"id": "disabled", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [], "enabled": false},
		{"id": "empty_enabled", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "density": 1.0,
			"polygon": [], "enabled": true},
	]

func _initialize() -> void:
	call_deferred("_generate")

func _generate() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected exactly one output path")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	for spec: Dictionary in _cases():
		var t: Array = spec["transform"]
		var layer: AtlasRasterLayer = AtlasRasterLayer.new()
		layer.transform = Transform2D(Vector2(t[0], t[1]), Vector2(t[2], t[3]), Vector2(t[4], t[5]))
		layer.pixels_per_unit = spec["density"]
		var vertices: PackedVector2Array = PackedVector2Array()
		for pair: Array in spec["polygon"]:
			vertices.append(Vector2(pair[0], pair[1]))
		var scope: AtlasEditScope = AtlasEditScope.new(vertices, spec["enabled"])
		var mask: PackedByteArray = PackedByteArray()
		mask.resize(SIDE * SIDE)
		var count: int = 0
		for y: int in range(SIDE):
			for x: int in range(SIDE):
				var allowed: bool = AtlasFill._allows_pixel(layer, Vector2i(x, y), scope)
				mask[y * SIDE + x] = 1 if allowed else 0
				if allowed:
					count += 1
		rows.append({"id": spec["id"], "transform": spec["transform"], "density": spec["density"],
			"polygon": spec["polygon"], "enabled": spec["enabled"],
			"allowed": count, "mask_base64": Marshalls.raw_to_base64(mask)})
	var file: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write T-068 scope fixture")
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "generator": "tests/drawing_t068_quad_scope_oracle.gd",
		"godot_version": Engine.get_version_info().get("string", ""), "side": SIDE, "cases": rows}, "  ") + "\n")
	file.close()
	print("T068_QUAD_SCOPE_ORACLE_PASSED: %d cases" % rows.size())
	quit(0)
