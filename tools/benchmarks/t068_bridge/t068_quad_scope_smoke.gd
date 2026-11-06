extends SceneTree

# Opt-in T-068: complete Godot-authored Atlas four-corner masks through an
# isolated native GDExtension, then through the scalar sparse brush ABI.
# The pinned oracle comes from real AtlasFill._allows_pixel; neither operation
# is enabled in Drawing or Atlas at runtime.
var checks: int = 0
var failures: int = 0

func _check(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("T068_QUAD_BRIDGE_FAIL: ", label)

static func _pack_pairs(values: Array) -> PackedByteArray:
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(values.size() * 16)
	for i: int in range(values.size()):
		packed.encode_double(i * 16, float(values[i][0]))
		packed.encode_double(i * 16 + 8, float(values[i][1]))
	return packed

static func _transform(values: Array) -> PackedByteArray:
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(48)
	for i: int in range(6):
		packed.encode_double(i * 8, float(values[i]))
	return packed

static func _digest(bytes: PackedByteArray) -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "load opt-in extension")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("build_quad_selection") and
		bridge.has_method("apply_scalar_brush_sparse"), "register both checked methods")
	if bridge == null:
		quit(1)
		return
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://quad_oracle.json"))
	_check(fixture is Dictionary and fixture.get("schema", 0) == 1 and
		fixture.get("side", 0) == 64, "load pinned Godot 64px oracle")
	if not fixture is Dictionary:
		bridge.free()
		quit(1)
		return
	var source: PackedByteArray = PackedByteArray()
	source.resize(64 * 64 * 4)
	source.encode_u32((22 * 64 + 22) * 4, 0x00223344)
	var original: PackedByteArray = source.duplicate()
	var path: PackedByteArray = _pack_pairs([[8.5, 8.5], [55.5, 55.5]])
	var paint: PackedByteArray = PackedByteArray([0xcc, 0xaa, 0x44, 0x80])
	var records: Array[Dictionary] = []
	for spec: Dictionary in fixture["cases"]:
		var label: String = String(spec["id"])
		var coefficients: PackedByteArray = _transform(spec["transform"])
		var polygon: PackedByteArray = _pack_pairs(spec["polygon"])
		var mask: PackedByteArray = bridge.build_quad_selection(
			coefficients, float(spec["density"]), polygon, 64, int(spec["enabled"]))
		var expected: PackedByteArray = Marshalls.base64_to_raw(spec["mask_base64"])
		_check(mask.size() == 4096 and mask == expected, label + ": full canonical mask parity")
		if mask.size() != 4096 or mask != expected:
			continue
		_check(mask.count(1) == spec["allowed"] and mask.count(0) + mask.count(1) == 4096,
			label + ": strictly binary mask and count")
		var wire: PackedByteArray = bridge.apply_scalar_brush_sparse(
			source, mask, path, 64, 4.0, paint, 0, 4096)
		var valid: bool = wire.size() >= 4 and (wire.size() - 4) % 12 == 0
		var changed: int = wire.decode_u32(0) if valid else -1
		valid = valid and wire.size() == 4 + changed * 12
		var previous: int = -1
		var reconstructed: PackedByteArray = source.duplicate()
		if valid:
			for i: int in range(changed):
				var offset: int = 4 + i * 12
				var pixel: int = wire.decode_u32(offset)
				var before: int = wire.decode_u32(offset + 4)
				var after: int = wire.decode_u32(offset + 8)
				if pixel <= previous or pixel >= 4096 or mask[pixel] != 1 or \
					before != reconstructed.decode_u32(pixel * 4) or before == after:
					valid = false
					break
				previous = pixel
				reconstructed.encode_u32(pixel * 4, after)
		_check(valid and changed <= spec["allowed"] and source == original,
			label + ": sparse brush respects native four-corner scope without mutation")
		records.append({"id": label, "allowed": mask.count(1), "mask_sha256": _digest(mask),
			"changed": changed, "sparse_bytes": wire.size(),
			"pixels_sha256": _digest(reconstructed)})
	var identity: PackedByteArray = _transform([1, 0, 0, 1, 0, 0])
	var square: PackedByteArray = _pack_pairs([[12, 12], [52, 12], [52, 52], [12, 52]])
	_check(bridge.build_quad_selection(PackedByteArray([1]), 1.0, square, 64, 1).is_empty(),
		"malformed transform fails closed")
	_check(bridge.build_quad_selection(identity, 0.0, square, 64, 1).is_empty(),
		"invalid density fails closed")
	_check(bridge.build_quad_selection(identity, 1.0, square, 2049, 1).is_empty(),
		"out-of-bounds dimensions fail closed")
	_check(bridge.build_quad_selection(identity, 1.0, square.slice(0, 15), 64, 1).is_empty(),
		"partial polygon vertex fails closed")
	_check(bridge.build_quad_selection(identity, 1.0, square, 64, 2).is_empty(),
		"invalid enabled flag fails closed")
	var invalid: PackedByteArray = _transform([1, 0, 0, 0, 0, 0])
	_check(bridge.build_quad_selection(invalid, 1.0, square, 64, 1).is_empty(),
		"singular transform fails closed")
	_check(source == original, "all native errors and brush calls preserve source")
	bridge.free()
	if failures == 0 and records.size() == 15:
		print("T068_QUAD_BRIDGE_EVIDENCE: " + JSON.stringify(records))
		print("T068_QUAD_BRIDGE_PASSED: %d checks" % checks)
	else:
		printerr("T068_QUAD_BRIDGE_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 and records.size() == 15 else 1)
