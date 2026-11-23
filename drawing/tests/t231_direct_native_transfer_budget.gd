extends SceneTree
## Direct non-Brush publishers must preflight a stride-sensitive native transfer
## envelope before touching lazy sources or copying Rust/Godot tile buffers.

const HIDDEN: int = 0x00335577
const VISIBLE: int = 0xff2468ac
var checks: int = 0
var failures: int = 0

class CountingDocument:
	extends DrawingDocument
	var resolves: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolves += 1
		return DrawingResult.failure("LOADER_CALLED", "Preflight reached a lazy source")


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T231_DIRECT_BUDGET_FAILED: " + label)


func native_document(stride: int) -> Dictionary:
	var document: CountingDocument = CountingDocument.new("t231-" + str(stride), stride)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var store: Object = document._native_store_for_edit(document.revision)
	check(store != null and int(store.call("stats").get("revision", -1)) == document.revision,
		"real native store attached to direct producer")
	return {"document": document, "layer": layer, "store": store}


func unwanted_lazy_fetch(_ref: String) -> PackedByteArray:
	printerr("T231_DIRECT_BUDGET_FAILED: lazy callback was invoked")
	return PackedByteArray()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native tile ABI loaded")
	var wide: Dictionary = native_document(2048)
	var document: CountingDocument = wide.document
	var layer: String = wide.layer
	var store: Object = wide.store
	var base: int = document.revision
	check(document.register_lazy_chunk(layer, 0, 0, "pending", "0".repeat(64),
		Callable(self, "unwanted_lazy_fetch")).ok,
		"pending lazy source registered before direct publication")
	var before: Dictionary[String, int] = {}
	var after: Dictionary[String, int] = {}
	var patches: Dictionary[String, Dictionary] = {}
	var sources: Dictionary[String, Variant] = {}
	for index: int in range(6):
		var pixel_key: String = "%d,0" % (index * 2048)
		var tile_key: String = "%d,0" % index
		before[pixel_key] = 0
		after[pixel_key] = VISIBLE
		patches[tile_key] = {0: VISIBLE}
		sources[tile_key] = null
	var outcome: DrawingResult = document._publish_edit(layer, base, before, after)
	check(not outcome.ok and outcome.code == "NATIVE_TILES",
		"six 2048px direct pixel tiles reject the 256 MiB envelope")
	check(document.resolves == 0 and document.revision == base and
		int(store.call("stats").get("revision", -1)) == base and
		document._nodes[layer].tiles.is_empty() and
		document._pending_tiles.has(layer + ":0,0"),
		"pixel refusal happens before any source read or mutation")
	outcome = document._publish_tile_edit(layer, base, patches, sources)
	check(not outcome.ok and outcome.code == "NATIVE_TILES",
		"six 2048px direct tile patches reject the same envelope")
	check(document.resolves == 0 and document.revision == base and
		int(store.call("stats").get("revision", -1)) == base,
		"tile refusal does not fetch sources or change revisions")

	var native: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(native.call("configure", 2048, 5) and
		native.call("set_layer_editable", "Ink", true),
		"independent Rust store configured")
	var descriptors: Array[Dictionary] = []
	for index: int in range(6):
		descriptors.append({"tile_x": index, "tile_y": 0,
			"before": PackedByteArray(), "after": PackedByteArray()})
	var receipt: Dictionary = native.call("adopt_external_edit", "Ink", 5, descriptors)
	check(not bool(receipt.get("ok", false)) and
		str(receipt.get("error", "")).contains("budget"),
		"Rust recorded adoption preflights budget before buffer conversion")
	receipt = native.call("adopt_untracked_edit", "Ink", 5, descriptors)
	check(not bool(receipt.get("ok", false)) and
		str(receipt.get("error", "")).contains("budget"),
		"Rust untracked adoption applies the same transfer budget")
	check(int(native.call("stats").get("revision", -1)) == 5 and
		int(native.call("stats").get("undo", -1)) == 0 and
		int(native.call("stats").get("external_bytes_received", -1)) == 0,
		"Rust rejection preserves revision and does not account copied RGBA8")

	var many: Dictionary = native_document(64)
	var crowded: CountingDocument = many.document
	var crowded_before: Dictionary[String, int] = {}
	var crowded_after: Dictionary[String, int] = {}
	var crowded_patches: Dictionary[String, Dictionary] = {}
	var crowded_sources: Dictionary[String, Variant] = {}
	for index: int in range(129):
		var coordinate: String = "%d,0" % (index * 64)
		var key: String = "%d,0" % index
		crowded_before[coordinate] = 0
		crowded_after[coordinate] = VISIBLE
		crowded_patches[key] = {0: VISIBLE}
		crowded_sources[key] = null
	check(not crowded._publish_edit(many.layer, crowded.revision,
		crowded_before, crowded_after).ok and crowded.resolves == 0,
		"more than 128 sparse pixel tiles reject before source reads")
	check(not crowded._publish_tile_edit(many.layer, crowded.revision,
		crowded_patches, crowded_sources).ok and crowded.resolves == 0,
		"more than 128 tile patches reject before source reads")

	var small: DrawingDocument = DrawingDocument.new("t231-success", 64)
	var ink: String = str(small.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var canonical: Object = small._native_store_for_edit(small.revision)
	check(canonical != null, "small document starts native-authoritative")
	var commit: DrawingResult = small._publish_edit(ink, small.revision,
		{"-1,4": 0, "65,1": 0}, {"-1,4": HIDDEN, "65,1": VISIBLE})
	check(commit.ok and commit.delta != null and commit.delta.native_history_token > 0,
		"small signed direct pixel edit commits with a native history token")
	if commit.ok:
		check(int(canonical.call("stats").get("revision", -1)) == small.revision,
			"native and Godot direct edit revisions agree")
		var signed: Dictionary = canonical.call("read_tile", ink, -1, 0, false)
		check(bool(signed.get("ok", false)) and
			(signed.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32((4 * 64 + 63) * 4) == HIDDEN,
			"Rust retains alpha-zero hidden RGB across signed boundary")
		check(small.undo().ok and int(small.read_pixel(ink, -1, 4).value) == 0,
			"native-backed direct edit undoes cleanly")
		check(small.redo().ok and int(small.read_pixel(ink, -1, 4).value) == HIDDEN,
			"native-backed direct edit redoes exact hidden RGB")
		var source: DrawingRasterTile = small._nodes[ink].tiles.get("1,0")
		var tile_edit: DrawingResult = small._publish_tile_edit(ink, small.revision,
			{"1,0": {2: HIDDEN}}, {"1,0": source}, false)
		check(tile_edit.ok and int(canonical.call("stats").get("revision", -1)) == small.revision,
			"bounded untracked tile-local edit advances the existing native owner")
		check(int(small.read_pixel(ink, 66, 0).value) == HIDDEN and
			int(canonical.call("stats").get("undo", -1)) == 0,
			"untracked direct tile edit preserves hidden RGB without inventing history")
		var path: String = ProjectSettings.globalize_path("user://t231-" +
			DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(small, path).ok, "native-authorized direct source saves")
		var opened: DrawingResult = DrawingFileIO.open(path)
		check(opened.ok and opened.value != null and
			int((opened.value as DrawingDocument).read_pixel(ink, -1, 4).value) == HIDDEN and
			int((opened.value as DrawingDocument).read_pixel(ink, 65, 1).value) == VISIBLE and
			int((opened.value as DrawingDocument).read_pixel(ink, 66, 0).value) == HIDDEN,
			"portable Open preserves exact signed and alpha-zero bytes")
		DirAccess.remove_absolute(path)

	if failures == 0:
		print("T231_DIRECT_BUDGET_PASSED checks=%d failures=0" % checks)
	else:
		print("T231_DIRECT_BUDGET_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
