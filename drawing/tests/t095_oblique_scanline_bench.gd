extends SceneTree
## Optional synthetic CPU-only T-095 measurement, not a pointer/render latency gate.
## Compare with canonical pre-optimization DrawingEditSession using identical data.
const INK: int = 0x9a61c4d7
const FRAME: Rect2i = Rect2i(0, 0, 512, 512)

func measure(i: int) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new("oblique-bench-%d" % i, 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var edit: DrawingEditSession = document.begin_edit(layer, document.revision, Transform2D.IDENTITY, 0, 0).value
	var path: PackedVector2Array = PackedVector2Array([
		Vector2(58.125 + (i % 3), 62.375),
		Vector2(453.75 + (i % 3), 459.25)])
	var begin: int = Time.get_ticks_usec()
	var result: DrawingResult = edit.paint_path(path, INK, 60.0, false, null, 1048576, FRAME)
	var elapsed: float = float(Time.get_ticks_usec() - begin) / 1000.0
	if not result.ok:
		printerr("T095_OBLIQUE_BENCH_FAILED stage=" + result.code)
		return {}
	var count: int = edit.change_count()
	var commit: DrawingResult = edit.commit()
	if not commit.ok:
		printerr("T095_OBLIQUE_BENCH_FAILED commit=" + commit.code)
		return {}
	return {"ms": elapsed, "count": count, "history": commit.delta.after.size()}

func run() -> void:
	var results: Array[float] = []
	var changed: Array[int] = []
	for i: int in range(9):
		var result: Dictionary = measure(i)
		if result.is_empty():
			quit(2)
			return
		results.append(float(result["ms"]))
		changed.append(int(result["count"]))
	results.sort()
	print("T095_OBLIQUE_BENCH median=%.3f min=%.3f max=%.3f count=%s" % [
		results[4], results[0], results[8], str(changed)])
	quit(0)

func _initialize() -> void:
	call_deferred("run")
