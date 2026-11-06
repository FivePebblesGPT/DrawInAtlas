extends SceneTree
## T-067 software-GL framebuffer probe. ImageTexture.update uploads the entire
## image, not the brush dirty rectangle. This is NOT a discrete-GPU VRAM test.

const STRIDES: Array[int] = [256, 512, 1024, 2048]
var failures: int = 0
var cases: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _summary(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"median_ms": snappedf(samples[samples.size() / 2], 0.001),
		"p95_ms": snappedf(samples[ceili(samples.size() * 0.95) - 1], 0.001)}


func _run() -> void:
	var backend: String = "rendering-device" if RenderingServer.get_rendering_device() != null else "compatibility-or-headless"
	for stride: int in STRIDES:
		var image: Image = Image.create(stride, stride, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.14, 0.5, 0.7, 0.99))
		var texture: ImageTexture = ImageTexture.create_from_image(image)
		if texture == null:
			failures += 1
			continue
		var uploads: Array[float] = []
		var force_frames: Array[float] = []
		for iteration: int in range(11):
			image.set_pixel(iteration, 0, Color8(30, 70, 120, 244))
			var start: int = Time.get_ticks_usec()
			texture.update(image)
			uploads.append(float(Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec()
			RenderingServer.force_draw()
			force_frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
		if texture.get_width() != stride or texture.get_height() != stride:
			failures += 1
		cases.append({"stride": stride, "rgba8_upload_mib": float(stride * stride * 4) / 1048576.0,
			"update": _summary(uploads), "force_draw": _summary(force_frames),
			"video_memory_bytes_estimate": stride * stride * 4})
		print("T067_UPLOAD stride=%d update=%s draw=%s" % [stride,
			JSON.stringify(cases.back()["update"]), JSON.stringify(cases.back()["force_draw"])])
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for idx: int in range(args.size() - 1):
		if args[idx] == "--output":
			var file: FileAccess = FileAccess.open(args[idx + 1], FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"schema": "t067-software-upload-v1", "backend": backend,
					"cases": cases, "failures": failures}, "  ") + "\n")
				file.close()
	print("T067_UPLOAD_%s (%d cases)" % ["PASSED" if failures == 0 else "FAILED", cases.size()])
	quit(0 if failures == 0 else 1)
