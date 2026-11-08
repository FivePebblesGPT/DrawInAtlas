extends SceneTree
## T-095: independent copy of the original 3-element source-over formula.
## Protect straight RGBA8 byte parity when optimizing the hot blend path.

const CHANNELS: Array[int] = [0, 1, 2, 3, 16, 63, 127, 128, 192, 254, 255]
const RANDOM_PAIRS: int = 32768

var checks: int = 0
var failures: int = 0


func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_BLEND_FAILED: " + label)


## This implementation deliberately preserves the pre-optimization array and
## loop; it must never call DrawingEditSession._blend as its own oracle.
func original_blend(source: int, destination: int) -> int:
	var sa: float = float((source >> 24) & 255) / 255.0
	if sa <= 0.0:
		return destination
	var da: float = float((destination >> 24) & 255) / 255.0
	var out_alpha: float = sa + da * (1.0 - sa)
	var a: int = clampi(roundi(out_alpha * 255.0), 0, 255)
	var channels: Array[int] = []
	for channel: int in range(3):
		var shift: int = channel * 8
		var sc: float = float((source >> shift) & 255)
		var dc: float = float((destination >> shift) & 255)
		channels.append(clampi(roundi((sc * sa + dc * da * (1.0 - sa)) / out_alpha), 0, 255))
	return channels[0] | (channels[1] << 8) | (channels[2] << 16) | (a << 24)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sample_count: int = 0
	var original_us: int = 0
	var optimized_us: int = 0
	# All 65,536 source/destination alpha pairs, with RGB varying from zero
	# through hidden RGB and high-contrast colors. This includes alpha=0
	# where a source must leave destination hidden RGB untouched.
	for src_a: int in range(256):
		for dst_a: int in range(256):
			var source: int = ((src_a & 255) << 24) | \
				(((src_a * 59 + dst_a * 17) & 255) << 16) | \
				(((src_a + dst_a * 3) & 255) << 8) | \
				((src_a * 13 + dst_a) & 255)
			var destination: int = (dst_a << 24) | \
				(((dst_a * 37 + src_a * 11) & 255) << 16) | \
				(((dst_a + src_a * 7) & 255) << 8) | \
				((dst_a * 71 + src_a) & 255)
			var old: int = original_blend(source, destination)
			var new_value: int = DrawingEditSession._blend(source, destination)
			if old != new_value:
				verify(false, "alpha sweep src=%08x dst=%08x old=%08x new=%08x" % [source, destination, old, new_value])
				quit(1)
				return
			sample_count += 1
	verify(true, "all 65,536 alpha pairs preserve original RGBA8 output")

	# Deterministic high-entropy RGBA combinations, including negative signed
	# int32 inputs as Godot may hand back from PackedInt32Array pigment triples.
	var seed: int = 0x1badc0de
	for i: int in range(RANDOM_PAIRS):
		seed = (seed * 1664525 + 1013904223) & 0xffffffff
		var source: int = seed
		seed = (seed * 1664525 + 1013904223) & 0xffffffff
		var destination: int = seed
		if i % 3 == 0:
			source |= 0xff000000
		if i % 7 == 0:
			source &= 0x00ffffff
		if i % 11 == 0:
			destination &= 0x00ffffff
		if (source & 0x80000000) != 0 and i % 5 == 0:
			source -= 0x100000000
		if (destination & 0x80000000) != 0 and i % 13 == 0:
			destination -= 0x100000000
		var old: int = original_blend(source, destination)
		var new_value: int = DrawingEditSession._blend(source, destination)
		if old != new_value:
			verify(false, "random pair %d src=%08x dst=%08x" % [i, source, destination])
			quit(1)
			return
		sample_count += 1
	verify(true, "deterministic RGB corpus preserves original formula")

	# Time the exact same data for each implementation. Informational only:
	# hardware/platform noise must not turn an otherwise exact test red.
	var benchmark_sources: PackedInt32Array = PackedInt32Array()
	var benchmark_destinations: PackedInt32Array = PackedInt32Array()
	for i: int in range(16384):
		var a: int = CHANNELS[i % CHANNELS.size()]
		var b: int = CHANNELS[(i * 7 + 3) % CHANNELS.size()]
		benchmark_sources.push_back((((a + 1) & 255) << 24) |
			((i * 977) & 0xffffff))
		benchmark_destinations.push_back((b << 24) | ((i * 49297) & 0xffffff))
	var first: int = Time.get_ticks_usec()
	var old_xor: int = 0
	for i: int in range(benchmark_sources.size()):
		old_xor = old_xor ^ original_blend(benchmark_sources[i], benchmark_destinations[i])
	original_us = Time.get_ticks_usec() - first
	first = Time.get_ticks_usec()
	var new_xor: int = 0
	for i: int in range(benchmark_sources.size()):
		new_xor = new_xor ^ DrawingEditSession._blend(benchmark_sources[i], benchmark_destinations[i])
	optimized_us = Time.get_ticks_usec() - first
	verify(old_xor == new_xor, "benchmark outputs unchanged")
	print("T095_BLEND_PROFILE samples=", sample_count,
		" original_us=", original_us, " optimized_us=", optimized_us)
	print("T095_BLEND_SUMMARY checks=", checks, " failures=", failures)
	if failures == 0:
		print("T095_BLEND_PASSED")
	quit(1 if failures > 0 else 0)
