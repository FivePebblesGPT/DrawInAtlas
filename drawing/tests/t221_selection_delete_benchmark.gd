extends SceneTree
## T-221 reproducible CPU timing: detached EditSession clear/commit vs mask-only Deselect.

const AREA: Rect2i = Rect2i(-64, -64, 512, 512)
const PIXELS: Array[Vector2i] = [Vector2i(-63, -63), Vector2i(-32, -32),
	Vector2i(-1, -1), Vector2i(0, 0), Vector2i(31, 31), Vector2i(32, 32),
	Vector2i(200, 200), Vector2i(447, 447)]


func _initialize() -> void:
	call_deferred("run")


func percentile(samples: Array[int], rate: float) -> int:
	var ordered: Array[int] = samples.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(float(ordered.size()) * rate) - 1, 0, ordered.size() - 1)]


func run() -> void:
	var stage_us: Array[int] = []
	var commit_us: Array[int] = []
	var deselect_us: Array[int] = []
	for trial: int in range(7):
		var doc: DrawingDocument = DrawingDocument.new("t221-benchmark-%d" % trial, 32)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Raster").value)
		var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
		for pos: Vector2i in PIXELS:
			assert(seed._stage(pos.x, pos.y, 0x00432211).ok)
		assert(seed.commit().ok)
		var mask: DrawingSelection = DrawingSelection.new(AREA, true)
		var started: DrawingResult = doc.begin_edit(layer, doc.revision)
		assert(started.ok)
		var edit: DrawingEditSession = started.value as DrawingEditSession
		var began: int = Time.get_ticks_usec()
		var staged: DrawingResult = edit.clear_rect(AREA, mask)
		var staged_at: int = Time.get_ticks_usec()
		assert(staged.ok)
		assert(edit.commit().ok)
		var committed_at: int = Time.get_ticks_usec()
		var canvas: Control = load("res://addons/drawing/canvas.gd").new()
		canvas.set_selection_mask(mask, false)
		var deselect_start: int = Time.get_ticks_usec()
		canvas.clear_selection()
		deselect_us.append(Time.get_ticks_usec() - deselect_start)
		stage_us.append(staged_at - began)
		commit_us.append(committed_at - staged_at)
		assert(not canvas.selection_mask.enabled)
		canvas.free()
	print("T221_BENCH: 512x512, 8 stored, 32px tile, seven warm/cold combined repetitions")
	print("T221_BENCH: delete stage p50=%d us p95=%d us samples=%s" % [percentile(stage_us, 0.5), percentile(stage_us, 0.95), stage_us])
	print("T221_BENCH: delete commit p50=%d us p95=%d us samples=%s" % [percentile(commit_us, 0.5), percentile(commit_us, 0.95), commit_us])
	print("T221_BENCH: deselect p50=%d us p95=%d us samples=%s" % [percentile(deselect_us, 0.5), percentile(deselect_us, 0.95), deselect_us])
	quit(0)
