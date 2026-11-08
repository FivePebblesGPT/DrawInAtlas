extends SceneTree
## T-095: fixed MyPaint 0.3.0 native export witness. Hash the complete
## batch-by-batch signed RGBA8 delta stream, including empty batches.
## Expected digests come from the pre-cache exporter in remote-compatible
## Hokusai commit 7cd08ea, not from the optimized implementation.

const PRESETS: Array[String] = ["hard", "soft", "ink", "airbrush"]
const EXPECTED: Dictionary[String, String] = {
	"hard": "3ced84511c66119e75e9fc1187b042a5269b0a2aa69037fe39a5503ffeb5e48b",
	"soft": "f496a29d8190fdca3cb489ffc66f0d2d4364d40b4a61239e81d0e123e2e351fd",
	"ink": "26ff4075e8499be5f196fc17564f9223220fcf0981c1704567727b653dc9dcb0",
	"airbrush": "cf4c1e0d372b9b27a2a9cf93acacd6b7366f72d1f124d704b874ca96b47f3577"
}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_EXPORT_CACHE_FAILED: " + message)

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "native GDExtension available")
	if not ClassDB.class_exists("DrawingNativeBrush"):
		quit(1)
		return
	for preset: String in PRESETS:
		var native: Object = ClassDB.instantiate("DrawingNativeBrush")
		var resource: String = "res://addons/drawing/brushes/%s.myb" % {
			"hard": "hard_round", "soft": "soft", "ink": "ink", "airbrush": "airbrush"
		}[preset]
		var settings: String = FileAccess.get_file_as_string(resource)
		check(not settings.is_empty() and native.call("configure_preset",
			settings, 32.0, 0xff53a071), "configure %s MyPaint preset" % preset)
		var digest: HashingContext = HashingContext.new()
		check(digest.start(HashingContext.HASH_SHA256) == OK, "init digest")
		var pixels: int = 0
		for batch: int in range(12):
			var points: PackedVector2Array = PackedVector2Array()
			for sample: int in range(8):
				var t: float = float(batch * 8 + sample) / 95.0
				points.append(Vector2(-70.5 + 141.0 * t,
					-38.5 + 33.0 * sin(t * TAU * 4.0)))
			var output: PackedInt32Array = native.call("preset_segments", points,
				0.7 if batch % 3 == 0 else 1.0)
			check(output.size() % 3 == 0, "valid signed RGBA8 triples")
			pixels += output.size() / 3
			var header: PackedByteArray = PackedByteArray()
			header.resize(4)
			header.encode_u32(0, output.size())
			digest.update(header)
			digest.update(output.to_byte_array())
		var checksum: String = digest.finish().hex_encode()
		print("T095_EXPORT_CACHE preset=%s pixels=%d sha256=%s" % [preset, pixels, checksum])
		check(checksum == EXPECTED[preset], "pre-cache pixel stream identical for " + preset)
		# An invalid trailing point may not mutate the earlier valid points:
		# the following valid batch must match a never-invalid reference brush.
		var reference: Object = ClassDB.instantiate("DrawingNativeBrush")
		var candidate: Object = ClassDB.instantiate("DrawingNativeBrush")
		check(reference.call("configure_preset", settings, 32.0, 0xff53a071) and
			candidate.call("configure_preset", settings, 32.0, 0xff53a071),
			"initialize side-effect reference for " + preset)
		var first: PackedVector2Array = PackedVector2Array([
			Vector2(-9.5, -7.5), Vector2(1.5, 3.5)])
		var continuation: PackedVector2Array = PackedVector2Array([
			Vector2(12.5, 5.5), Vector2(21.5, -4.5)])
		check(reference.call("preset_segments", first, 1.0) ==
			candidate.call("preset_segments", first, 1.0),
			"reference matches before invalid input")
		var malformed: PackedInt32Array = candidate.call("preset_segments",
			PackedVector2Array([Vector2(4.5, 7.5), Vector2(NAN, -2.0)]), 1.0)
		check(malformed.is_empty(), "non-finite later point rejects entire input")
		var bad_pressure: PackedInt32Array = candidate.call("preset_segments",
			PackedVector2Array([Vector2(7.5, 8.5)]), NAN)
		check(bad_pressure.is_empty(), "non-finite pressure rejects input")
		check(reference.call("preset_segments", continuation, 0.8) ==
			candidate.call("preset_segments", continuation, 0.8),
			"rejected input leaves native brush state and next export identical")
	print("T095_EXPORT_CACHE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
