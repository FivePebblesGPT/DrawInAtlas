extends SceneTree
## T-068 independent dirty-display-tile upload study. Requires software/native GL.
## ImageTexture.update() uploads entire texture; no subrectangle update is claimed.

const REGIONS: Array[int] = [128, 256, 512, 1024]
const ROUNDS: int = 11
var failures: int = 0
var cases: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _stats(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"median_ms": snappedf(samples[samples.size() / 2], 0.001),
		"p95_ms": snappedf(samples[ceili(float(samples.size()) * 0.95) - 1], 0.001)}


func _run() -> void:
	var output: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--output":
			output = args[index + 1]
	var backend: String = RenderingServer.get_current_rendering_method()
	for region: int in REGIONS:
		var image: Image = Image.create(region, region, false, Image.FORMAT_RGBA8)
		image.fill(Color8(17, 45, 79, 172))
		var texture: ImageTexture = ImageTexture.create_from_image(image)
		if texture == null:
			failures += 1
			continue
		var upload_ms: Array[float] = []
		var submit_ms: Array[float] = []
		for attempt: int in range(ROUNDS):
			image.set_pixel(attempt, 0, Color8(19, 62, 115, 199))
			var start: int = Time.get_ticks_usec()
			texture.update(image)
			upload_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec()
			RenderingServer.force_draw()
			submit_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
		if texture.get_width() != region or texture.get_height() != region:
			failures += 1
		cases.append({"region": region, "rgba8_bytes": region * region * 4,
			"update": _stats(upload_ms), "force_draw": _stats(submit_ms)})
		print("T068_UPLOAD region=%d upload=%s" % [region, JSON.stringify(_stats(upload_ms))])
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			failures += 1
		else:
			file.store_string(JSON.stringify({"schema": "t068-upload-v1", "engine": Engine.get_version_info(),
				"backend": backend, "cases": cases, "failures": failures}, "  ") + "\n")
			file.close()
	print("T068_UPLOAD_%s (%d regions)" % ["PASSED" if failures == 0 else "FAILED", cases.size()])
	quit(0 if failures == 0 else 1)
