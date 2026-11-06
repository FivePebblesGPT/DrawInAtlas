extends SceneTree
## T-057: reproducible baseline vs bounded, exact display-cache/derived-LOD candidates.
## This benchmark intentionally does not change the production rendering backend.

const STRIDES: Array[int] = [256, 512, 1024, 2048]
const DISPLAY_TILE: int = 64
const VIEW: Vector2i = Vector2i(128, 96)
const PANS: int = 16

var checks: int = 0
var failures: int = 0
var cases: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T057_FAILED: " + label)


func _stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {}
	samples.sort()
	return {"median_ms": snappedf(samples[samples.size() / 2], 0.001),
		"p95_ms": snappedf(samples[ceili(float(samples.size()) * 0.95) - 1], 0.001),
		"worst_ms": snappedf(samples.back(), 0.001)}


func _seed(document: DrawingDocument, layer: String, world_x: int, world_y: int,
		seed_index: int) -> void:
	var opened: DrawingResult = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, world_x, world_y)
	_check(opened.ok, "open seed edit")
	if not opened.ok:
		return
	var data: PackedByteArray = PackedByteArray()
	data.resize(80 * 80 * 4)
	for index: int in range(80 * 80):
		data[index * 4] = (index * 17 + seed_index * 35) % 256
		data[index * 4 + 1] = (index * 7 + 61) % 256
		data[index * 4 + 2] = (index * 11 + 19) % 256
		data[index * 4 + 3] = [0, 128, 255][index % 3]
	var edit: DrawingEditSession = opened.value as DrawingEditSession
	var applied: DrawingResult = edit.apply_region(Rect2i(0, 0, 80, 80), data)
	_check(applied.ok and edit.commit().ok, "seed sparse RGBA8 crossing a tile seam")


## Cache is keyed by exact signed integers and source revision, not Vector2.
## Every returned hash is computed from canonical RGBA8, not a GPU readback.
func _display_frame(document: DrawingDocument, world_x: int, world_y: int,
		cached: bool, cache: Dictionary) -> Dictionary:
	var start_us: int = Time.get_ticks_usec()
	var first_x: int = world_x - posmod(world_x, DISPLAY_TILE)
	var first_y: int = world_y - posmod(world_y, DISPLAY_TILE)
	var hashes: Array[String] = []
	var hits: int = 0
	var misses: int = 0
	for y: int in range(first_y, world_y + VIEW.y, DISPLAY_TILE):
		for x: int in range(first_x, world_x + VIEW.x, DISPLAY_TILE):
			var key: String = "%d:%d:%d" % [document.revision, x, y]
			var bytes: PackedByteArray = PackedByteArray()
			if cached and cache.has(key):
				bytes = cache[key]
				hits += 1
			else:
				var frame: DrawingResult = DrawingRenderer.render(document,
					Rect2i(0, 0, DISPLAY_TILE, DISPLAY_TILE), x, y)
				if not frame.ok:
					return {"ok": false, "message": frame.message}
				bytes = (frame.value as Image).get_data()
				if cached:
					cache[key] = bytes
				misses += 1
			hashes.append(bytes.hex_encode())
	return {"ok": true, "hashes": hashes,
		"ms": float(Time.get_ticks_usec() - start_us) / 1000.0,
		"hits": hits, "misses": misses}


func _error_metric(reference: Image, candidate: Image) -> Dictionary:
	var original: PackedByteArray = reference.get_data()
	var reduced: PackedByteArray = candidate.get_data()
	var total: int = 0
	var different: int = 0
	var alpha_total: int = 0
	for index: int in range(original.size()):
		var difference: int = absi(int(original[index]) - int(reduced[index]))
		total += difference
		if difference > 0:
			different += 1
		if index % 4 == 3:
			alpha_total += difference
	return {"channel_mean_absolute_error": snappedf(float(total) / float(original.size()), 0.001),
		"alpha_mean_absolute_error": snappedf(float(alpha_total) / float(original.size() / 4), 0.001),
		"different_channels": different, "total_channels": original.size()}


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output: String = ""
	for index: int in range(args.size() - 1):
		if args[index] == "--output":
			output = args[index + 1]
	for stride: int in STRIDES:
		var document: DrawingDocument = DrawingDocument.new("t057-%d" % stride, stride)
		var back: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Base")
		var front: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Overlay")
		_check(back.ok and front.ok, "create independent raster layers")
		# 2^53 + 1 is representable in int64 but not an exact binary float.
		# Seed deliberately straddles both a positive and negative sparse tile seam.
		var positive: int = 9007199254740993
		var negative: int = -9007199254740993
		var anchor_x: int = positive - posmod(positive, stride) + stride - 40
		var anchor_y: int = negative - posmod(negative, stride) + stride - 40
		_seed(document, str(back.value), anchor_x, anchor_y, 0)
		_seed(document, str(front.value), anchor_x + 5, anchor_y + 7, 1)
		var sample: DrawingResult = document.read_pixel(str(back.value), anchor_x + 3, anchor_y + 3)
		_check(sample.ok and int(sample.value) != 0, "64-bit positive/negative source anchor intact")
		var source_version: int = document.revision
		var direct_times: Array[float] = []
		var cached_times: Array[float] = []
		var direct_hashes: Array[Array] = []
		var candidate_cache: Dictionary = {}
		var cache_hits: int = 0
		var cache_misses: int = 0
		# The same deterministic pan path is run both uncached and with a
		# bounded display-tile cache. It deliberately revisits tile boundaries.
		for index: int in range(PANS):
			var world_x: int = anchor_x - 24 + (index % 8) * 16
			var world_y: int = anchor_y - 24 + ((index / 4) % 2) * 24
			var fresh: Dictionary = _display_frame(document, world_x, world_y, false, {})
			_check(bool(fresh.get("ok", false)), "fresh pan frame")
			if not fresh.get("ok", false):
				continue
			direct_times.append(float(fresh["ms"]))
			direct_hashes.append(fresh["hashes"])
		for index: int in range(PANS):
			var world_x: int = anchor_x - 24 + (index % 8) * 16
			var world_y: int = anchor_y - 24 + ((index / 4) % 2) * 24
			var reused: Dictionary = _display_frame(document, world_x, world_y, true, candidate_cache)
			_check(bool(reused.get("ok", false)), "cached pan frame")
			if not reused.get("ok", false):
				continue
			cached_times.append(float(reused["ms"]))
			cache_hits += int(reused["hits"])
			cache_misses += int(reused["misses"])
			_check(reused["hashes"] == direct_hashes[index], "cache byte-identical to uncached viewport tiles")
		_check(document.revision == source_version, "view-only cache does not edit source")
		var exact: DrawingResult = DrawingRenderer.render(document, Rect2i(0, 0, 128, 128),
			anchor_x - 24, anchor_y - 24)
		_check(exact.ok, "derived image source render")
		var nearest_error: Dictionary = {}
		var filtered_error: Dictionary = {}
		if exact.ok:
			var base_image: Image = exact.value as Image
			var nearest: Image = base_image.duplicate()
			nearest.resize(64, 64, Image.INTERPOLATE_NEAREST)
			nearest.resize(128, 128, Image.INTERPOLATE_NEAREST)
			var filtered: Image = base_image.duplicate()
			filtered.resize(64, 64, Image.INTERPOLATE_BILINEAR)
			filtered.resize(128, 128, Image.INTERPOLATE_NEAREST)
			nearest_error = _error_metric(base_image, nearest)
			filtered_error = _error_metric(base_image, filtered)
			_check(nearest_error["different_channels"] > 0 and filtered_error["different_channels"] > 0,
				"2x derived mips are visibly lossy on patterned source")
			_check(base_image.get_data() == (exact.value as Image).get_data(),
				"derived downsample leaves canonical output untouched")
		# Revision-based invalidation is conservative and deterministic; it
		# invalidates all display tiles, not just the edited dirty regions.
		var before_revision: int = document.revision
		var changed: PackedByteArray = PackedByteArray([255, 0, 0, 255])
		var opened: DrawingResult = document.begin_edit(str(front.value), before_revision,
			Transform2D.IDENTITY, anchor_x + 18, anchor_y + 18)
		_check(opened.ok, "begin cache invalidation edit")
		if opened.ok:
			var editor: DrawingEditSession = opened.value as DrawingEditSession
			_check(editor.apply_region(Rect2i(0, 0, 1, 1), changed).ok and editor.commit().ok,
				"single-pixel published edit")
		var edited_view: Dictionary = _display_frame(document, anchor_x - 24,
			anchor_y - 24, true, candidate_cache)
		_check(document.revision > before_revision and bool(edited_view.get("ok", false))
			and int(edited_view.get("misses", 0)) > 0, "new revision cannot reuse stale source textures")
		var refreshed: Dictionary = _display_frame(document, anchor_x - 24,
			anchor_y - 24, false, {})
		_check(edited_view.get("hashes", []) == refreshed.get("hashes", []),
			"cache refresh exactly matches published pixels")
		var one: Dictionary = {"storage_stride": stride, "screen_view": [VIEW.x, VIEW.y],
			"display_tile": DISPLAY_TILE, "frames": PANS,
			"baseline_uncached_cpu": _stats(direct_times),
			"candidate_exact_cache_cpu": _stats(cached_times),
			"cache_hits": cache_hits, "cache_misses": cache_misses,
			"max_cache_entries": candidate_cache.size(),
			"estimated_cache_bytes": candidate_cache.size() * DISPLAY_TILE * DISPLAY_TILE * 4,
			"nearest_2x_fidelity": nearest_error, "bilinear_2x_fidelity": filtered_error}
		cases.append(one)
		print("T057_CASE stride=%d uncached=%s cached=%s hit=%d miss=%d" % [stride,
			JSON.stringify(one["baseline_uncached_cpu"]), JSON.stringify(one["candidate_exact_cache_cpu"]),
			cache_hits, cache_misses])
	# Documented signed 64-bit source coordinates must not be conflated with
	# camera coordinates stored in Vector2 (native float precision differs).
	var a: Vector2 = Vector2(16777216.0, -16777216.0)
	var b: Vector2 = Vector2(16777217.0, -16777217.0)
	var camera_distinct: bool = a != b
	var summary: Dictionary = {"schema": "t057-lod-headless-v1", "engine": Engine.get_version_info(),
		"cases": cases, "checks": checks, "failures": failures,
		"camera_vector2_distinguishes_2pow24_plus_one": camera_distinct,
		"limitations": "Timed source CPU tiles, not input-to-photons, actual GPU VRAM, or a production cache. "
			+ "Exact-cache candidate reuses sampled views; mip downsampling is lossy. "
			+ "64-bit DrawingDocument anchors do not imply 64-bit Atlas Vector2 camera precision."}
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		_check(file != null, "write raw benchmark JSON")
		if file != null:
			summary["checks"] = checks
			summary["failures"] = failures
			file.store_string(JSON.stringify(summary, "  ") + "\n")
			file.close()
	print("T057_LOD_HEADLESS_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
