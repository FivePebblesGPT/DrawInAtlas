extends SceneTree
## Opt-in CPU microbenchmark for T-095; synthetic waypoint staging only.
## Not a pointer-event, renderer, physical-device, or acceptance measurement.
const INK: int = 0x9052acd3

func trial(kind: String, rep: int) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("ref-bench-%s-%d" % [kind, rep], 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision, Transform2D.IDENTITY, 0, 0).value
	var start_us: int = Time.get_ticks_usec()
	# Repeated waypoints in axis-aligned, dab-pattern and oblique trajectories.
	# All positions share one edit session, so subsequent calls may sweep.
	for i: int in range(130):
		var x: float = 80.0 + float(i % 65) * 5.0
		var y: float = 60.0 + float((i * 7) % 48) * 4.0
		if kind == "axis":
			y = 64.5 + float(i / 13) * 24.0
		elif kind == "dab":
			x = 100.25 + float((i * 3) % 47) * 4.0
			y = 100.25 + float((i * 11) % 37) * 3.0
		var part: PackedVector2Array = PackedVector2Array([Vector2(x,y)])
		var result: DrawingResult = edit.paint_path(part, INK, 60.0)
		if not result.ok:
			printerr("FAIL %s %s" % [kind, result.code])
			return {}
	var us: int = Time.get_ticks_usec() - start_us
	var count: int = edit.change_count()
	var commit: DrawingResult = edit.commit()
	if not commit.ok:
		printerr("commit failed %s" % commit.code)
	return {"ms": float(us)/1000.0, "count":count, "after":commit.delta.after.size()}

func run() -> void:
	for kind: String in ["axis", "dab", "oblique"]:
		var samples: Array[float] = []
		var changed: Array[int] = []
		for i: int in range(7):
			var out: Dictionary = trial(kind, i)
			if out.is_empty():
				quit(2)
				return
			samples.append(out["ms"])
			changed.append(out["count"])
		samples.sort()
		print("T095_REF_BENCH %s median=%.3f min=%.3f max=%.3f counts=%s" % [kind, samples[3], samples[0], samples[6], str(changed)])
	quit(0)

func _initialize() -> void:
	call_deferred("run")
