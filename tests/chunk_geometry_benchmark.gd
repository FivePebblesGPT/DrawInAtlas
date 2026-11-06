extends SceneTree
## T-067 native Godot 4.8 benchmark: actual Drawing transactions, small viewport
## rendering, repeated history and the T-066 atomic bundle writer. Desktop/headless.

const STRIDES: Array[int] = [256, 512, 1024, 2048]
const ROUNDS: int = 13
var checks: int = 0
var failures: int = 0
var records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(yes: bool, label: String) -> void:
	checks += 1
	if not yes:
		failures += 1
		push_error("T067_FAILED: " + label)


func _ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _summary(values: Array[float]) -> Dictionary:
	values.sort()
	if values.is_empty():
		return {"median_ms": 0.0, "p95_ms": 0.0}
	var middle: int = values.size() / 2
	var index: int = ceili(values.size() * 0.95) - 1
	return {"median_ms": snappedf(values[middle], 0.001),
		"p95_ms": snappedf(values[index], 0.001)}


func _run() -> void:
	var output: String = ""
	var only_stride: int = 0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--output":
			output = args[index + 1]
		elif args[index] == "--stride":
			only_stride = int(args[index + 1])
	for stride: int in STRIDES:
		if only_stride > 0 and stride != only_stride:
			continue
		var result: Dictionary = _benchmark(stride)
		records.append(result)
		print("T067_NATIVE stride=%d edit=%s viewport=%s save=%s" % [
			stride, JSON.stringify(result["edit"]), JSON.stringify(result["viewport"]),
			JSON.stringify(result["save"])])
	if not output.is_empty():
		var dir_error: Error = DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		_check(dir_error == OK, "output directory exists")
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		_check(file != null, "output JSON created")
		if file != null:
			file.store_string(JSON.stringify({"schema": "t067-native-godot-v1", "engine": Engine.get_version_info(),
				"rounds": ROUNDS, "checks": checks, "failures": failures, "cases": records}, "  ") + "\n")
			file.close()
	print("T067_NATIVE_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _sum_ints(items: Array[int]) -> int:
	var total: int = 0
	for size: int in items:
		total += size
	return total


func _benchmark(stride: int) -> Dictionary:
	var edits: Array[float] = []
	var frames: Array[float] = []
	var histories: Array[float] = []
	var serializations: Array[float] = []
	var compressed_sizes: Array[int] = []
	var undo_encoded_bytes: Array[int] = []
	var doc: DrawingDocument = DrawingDocument.new("t067-%d" % stride, stride)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var far_x: int = ((9007199254740993 / stride) + 1) * stride - 4
	var far_y: int = -((9007199254740993 / stride) + 1) * stride - 4
	var changes: int = 0
	for iteration: int in range(ROUNDS):
		var begun: DrawingResult = doc.begin_edit(layer, doc.revision, Transform2D.IDENTITY,
			far_x + iteration * stride, far_y - iteration * stride)
		_check(begun.ok, "start signed gesture %d %d" % [stride, iteration])
		if not begun.ok:
			continue
		var edit: DrawingEditSession = begun.value as DrawingEditSession
		var start: int = Time.get_ticks_usec()
		var touched: DrawingResult = edit.paint_path(PackedVector2Array([
			Vector2(0.5, 0.5), Vector2(7.5, 4.5)]), 0xffedbabe, 4.0)
		var committed: DrawingResult = edit.commit() if touched.ok else touched
		edits.append(_ms(start))
		_check(touched.ok and committed.ok, "swept 4px path succeeds %d %d, stage=%s:%s commit=%s:%s" % [stride, iteration, touched.code, touched.message, committed.code, committed.message])
		if not committed.ok:
			continue
		if committed.delta != null:
			changes += committed.delta.after.size()
			# Godot Variant wire size of both canonical dictionaries: a repeatable
			# memory-pressure proxy, NOT a heap profiler or per-tile snapshot.
			undo_encoded_bytes.append(var_to_bytes([committed.delta.before,
				committed.delta.after]).size())
		_check(committed.regions.size() >= 2 and committed.regions.size() <= 4,
			"bounded dirty tile regions")
		start = Time.get_ticks_usec()
		var frame: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 24, 24),
			far_x + iteration * stride, far_y - iteration * stride)
		frames.append(_ms(start))
		_check(frame.ok and frame.value is Image and frame.value.get_width() == 24,
			"camera-relative viewport render")
		start = Time.get_ticks_usec()
		var undone: DrawingResult = doc.undo()
		var redone: DrawingResult = doc.redo()
		histories.append(_ms(start))
		_check(undone.ok and redone.ok, "one-step gesture undo/redo")
	# Encode the sparsely populated tile using the real Godot ZSTD implementation;
	# the 2048 case measures the full 16MiB source buffer, not a guessed copy.
	var chunks: Array[String] = doc.tile_keys(layer)
	_check(not chunks.is_empty(), "sparse document has chunk keys")
	if not chunks.is_empty():
		var requested: DrawingResult = doc.request_chunk(layer, chunks[0])
		_check(requested.ok and requested.value != null, "fetch sparse source tile")
		if requested.ok and requested.value != null:
			var source: PackedByteArray = (requested.value as DrawingRasterTile).to_rgba8()
			_check(source.size() == stride * stride * 4, "buffer stride is exact")
			for iteration: int in range(3):
				var start: int = Time.get_ticks_usec()
				var compressed: PackedByteArray = source.compress(FileAccess.COMPRESSION_ZSTD)
				serializations.append(_ms(start))
				compressed_sizes.append(compressed.size())
				_check(compressed.decompress(source.size(), FileAccess.COMPRESSION_ZSTD) == source,
					"Godot ZSTD roundtrip includes transparent RGB")
	var hidden_edit: DrawingResult = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, far_x + 24, far_y + 24)
	_check(hidden_edit.ok, "start explicit alpha-zero RGBA edit")
	if hidden_edit.ok:
		var session: DrawingEditSession = hidden_edit.value
		_check(session.apply_region(Rect2i(0, 0, 1, 1),
			PackedByteArray([187, 170, 153, 0])).ok and session.commit().ok,
			"store hidden RGB unchanged by compositing")
	var sample: DrawingResult = doc.read_pixel(layer, far_x + 24, far_y + 24)
	_check(sample.ok and sample.value == 0x0099aabb, "non-zero hidden RGB survives signed source")
	var save_times: Array[float] = []
	var load_times: Array[float] = []
	var folder: String = OS.get_cache_dir().path_join("t067-native-" + DrawingDocument.new_id())
	var location: String = folder.path_join("World.scn")
	_check(DirAccess.make_dir_recursive_absolute(folder) == OK, "new generation folder")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	_check(registry.attach_campaign(campaign).ok, "attach test campaign")
	_check(registry.ensure_detail("world", "ground", 1, 2, 1, stride).ok,
		"versioned per-document stride")
	var target: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	_check(target.tile_stride == stride, "created independent stride")
	var target_layer: String = str(target.create_layer(DrawingLayerNode.RASTER, "Patch").value)
	for iteration: int in range(3):
		var began: DrawingResult = target.begin_edit(target_layer, target.revision,
			Transform2D.IDENTITY, -stride - iteration, stride + iteration)
		_check(began.ok, "bundle begin edit")
		if began.ok:
			var edit: DrawingEditSession = began.value
			_check(edit.apply_region(Rect2i(0, 0, 1, 1), PackedByteArray([3, 4, 5, 0])).ok
				and edit.commit().ok, "bundle touched pixel preserved")
		var start: int = Time.get_ticks_usec()
		var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, location)
		save_times.append(_ms(start))
		_check(saved.ok, "bundled sparse generation %d" % iteration)
		if not saved.ok:
			break
		start = Time.get_ticks_usec()
		var reloaded: AtlasStoreResult = AtlasCampaignBundle.load(location)
		load_times.append(_ms(start))
		_check(reloaded.error == OK, "read sparse generation metadata")
		if reloaded.error == OK:
			var reopened: DrawingResult = reloaded.registry.document_at("world", "ground", 1)
			_check(reopened.ok and reopened.value.tile_stride == stride, "immutable stride survives reopen")
			if reopened.ok:
				var pixel: DrawingResult = reopened.value.read_pixel(target_layer, -stride - iteration, stride + iteration)
				_check(pixel.ok and pixel.value == 0x00050403, "bytes preserved across generation")
	# Avoid deleting saved evidence until all reopen assertions have completed.
	return {"stride": stride, "rounds": ROUNDS, "edit": _summary(edits),
		"viewport": _summary(frames), "undo_redo": _summary(histories),
		"zstd_encode": _summary(serializations), "zstd_bytes": compressed_sizes,
		"save": _summary(save_times), "load_metadata": _summary(load_times),
		"max_decoded_tile_mib": float(stride * stride * 4) / 1048576.0,
		"cache_32mib_max_tiles": mini(64, (32 * 1048576) / (stride * stride * 4)),
		"document_tiles": chunks.size(), "committed_pixel_changes": changes,
		"undo_encoded_delta_bytes_sum": _sum_ints(undo_encoded_bytes),
		"undo_encoded_delta_bytes_max": undo_encoded_bytes.max() if not undo_encoded_bytes.is_empty() else 0}
