extends SceneTree
## T-101: NativeHard's verified packed deltas take the tile-local path without
## the generic _stage() dispatcher. Mixed edits still use canonical staging;
## failures roll back both the GDScript preview and native transaction.

const ANCHOR_X: int = 2147483651
const ANCHOR_Y: int = -2147483671
const WINDOW: Rect2i = Rect2i(-26, -26, 52, 52)
const COLOR: int = 0x805c21dd
const INK: int = 0xffa14e07

class CountingSession:
	extends DrawingEditSession
	var generic_calls: int = 0

	func _stage(x: int, y: int, rgba: int, selection: DrawingSelection = null,
			once: bool = false, blend: bool = false, verified_source: int = -1,
			internal_brush: bool = false) -> DrawingResult:
		generic_calls += 1
		return super._stage(x, y, rgba, selection, once, blend, verified_source,
			internal_brush)

class PackedCoverage:
	extends RefCounted
	var points: PackedInt32Array = PackedInt32Array()
	var begins: int = 0
	var commits: int = 0
	var rollbacks: int = 0
	func begin_hard_batch() -> bool:
		begins += 1
		return true
	func hard_segments(_path: PackedVector2Array, _width: float,
			_clip: Rect2i) -> Dictionary:
		return {"ok": true, "points": points}
	func commit_hard_batch() -> void:
		commits += 1
	func rollback_hard_batch() -> void:
		rollbacks += 1

class ReadFaultDocument:
	extends DrawingDocument
	var reject_key: String = ""
	func _resolve_chunk(layer: String, key: String) -> DrawingResult:
		if key == reject_key:
			return DrawingResult.failure("INJECTED_TILE", "Late source tile unavailable")
		return super._resolve_chunk(layer, key)

var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T101_NATIVE_DISPATCH_FAILED: " + message)

func make_document(name: String, faulty: bool = false) -> Dictionary:
	var doc: DrawingDocument = ReadFaultDocument.new(name, 16) if faulty else DrawingDocument.new(name, 16)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Pixels", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
	check(seed._stage(0, 0, 0x00abcdef).ok, "hidden RGB seed accepted")
	check(seed._stage(-7, -7, 0x80446688).ok, "partial alpha seed accepted")
	check(seed.commit().ok, "initial seed published")
	return {"document": doc, "layer": layer}

func snapshot(state: Dictionary, edit: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(state["document"], WINDOW,
		ANCHOR_X, ANCHOR_Y, 1048576, edit)
	check(result.ok, "signed canonical RGBA8 render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()

func make_points() -> PackedInt32Array:
	var pixels: PackedInt32Array = PackedInt32Array()
	for y: int in range(-17, 18):
		for x: int in range(-17, 18):
			pixels.append(x)
			pixels.append(y)
	return pixels

func make_edit(state: Dictionary) -> CountingSession:
	var doc: DrawingDocument = state["document"]
	return CountingSession.new(doc, state["layer"], doc.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y)

func paint(edit: CountingSession, native: PackedCoverage,
		selection: DrawingSelection = null, erase: bool = false) -> DrawingResult:
	return edit.paint_path_native_hard(PackedVector2Array([Vector2(-8.5, -8.5)]), INK, 24.0, erase, selection,
		native, WINDOW)

func compare_commit(a: Dictionary, b: Dictionary, stage_a: CountingSession,
		stage_b: CountingSession) -> void:
	check(snapshot(a, stage_a) == snapshot(b, stage_b),
		"preview matches independent generic staging")
	var revision_a: int = (a["document"] as DrawingDocument).revision
	var revision_b: int = (b["document"] as DrawingDocument).revision
	var first: DrawingResult = stage_a.commit()
	var second: DrawingResult = stage_b.commit()
	check(first.ok and second.ok, "one atomic commit accepted")
	check((a["document"] as DrawingDocument).revision == revision_a + 1 and
		(b["document"] as DrawingDocument).revision == revision_b + 1,
		"one revision per stroke")
	check(first.delta.before == second.delta.before and
		first.delta.after == second.delta.after,
		"canonical RGBA8 history unchanged")
	check(snapshot(a) == snapshot(b), "committed signed RGBA8 parity")
	check((a["document"] as DrawingDocument).undo().ok and
		(b["document"] as DrawingDocument).undo().ok and
		snapshot(a) == snapshot(b), "one-step Undo parity")
	check((a["document"] as DrawingDocument).redo().ok and
		(b["document"] as DrawingDocument).redo().ok and
		snapshot(a) == snapshot(b), "Redo parity")

func test_regular(masked: bool, erase: bool) -> void:
	var optimized: Dictionary = make_document("native-only")
	var reference: Dictionary = make_document("generic-only")
	var edit: CountingSession = make_edit(optimized)
	var oracle: CountingSession = make_edit(reference)
	# Both sources share signed anchors and a selection hole; the reference
	# uses the historical _stage(..., internal_brush=true) contract explicitly.
	var mask: DrawingSelection = null
	if masked:
		mask = DrawingSelection.new(WINDOW, true)
		check(mask.combine_rectangle(Rect2i(-5, -5, 10, 10), "Subtract"),
			"selection hole configured")
	var native: PackedCoverage = PackedCoverage.new()
	native.points = make_points()
	var start_us: int = Time.get_ticks_usec()
	check(paint(edit, native, mask, erase).ok, "native pixels staged")
	var stage_us: int = Time.get_ticks_usec() - start_us
	check(edit.generic_calls == 0, "native-only stream bypasses generic per-pixel dispatch")
	check(native.begins == 1 and native.commits == 1 and native.rollbacks == 0,
		"native batch is acknowledged once")
	for index: int in range(0, native.points.size(), 2):
		check(oracle._stage(native.points[index], native.points[index + 1],
			0 if erase else INK, mask, true, not erase, -1, true).ok,
			"reference pixel staged")
	check(edit.change_count() == oracle.change_count(), "changed-pixel count parity")
	print("T101_NATIVE_DISPATCH_CPU masked=%s erase=%s pixels=%d stage_ms=%.3f" % [
		str(masked), str(erase), native.points.size() / 2, float(stage_us) / 1000.0])
	compare_commit(optimized, reference, edit, oracle)

func test_mixed_and_retry() -> void:
	var optimized: Dictionary = make_document("native-mixed", true)
	var reference: Dictionary = make_document("generic-mixed")
	var edit: CountingSession = make_edit(optimized)
	var oracle: CountingSession = make_edit(reference)
	var native: PackedCoverage = PackedCoverage.new()
	native.points = PackedInt32Array([-18, -18, 0, 0, 18, 18])
	# First public edit switches off tile-only staging; NativeHard must keep
	# the original mixed/global-history path, including rollback.
	check(edit._stage(2, 2, COLOR).ok and oracle._stage(2, 2, COLOR).ok,
		"mixed canonical operation staged")
	var before: PackedByteArray = snapshot(optimized, edit)
	var fault: ReadFaultDocument = optimized["document"]
	fault.reject_key = DrawingDocument.TILES.tile_key64(ANCHOR_X + 18,
		ANCHOR_Y + 18, fault.tile_stride)
	var failed: DrawingResult = paint(edit, native)
	check(not failed.ok and failed.code == "INJECTED_TILE", "late source read rejects batch")
	check(native.begins == 1 and native.rollbacks == 1 and native.commits == 0,
		"native pending coverage rolled back")
	# The injected lazy read fault also affects renderer reads, so release it
	# before comparing the unchanged detached bytes and retrying the batch.
	fault.reject_key = ""
	check(snapshot(optimized, edit) == before,
		"failure restores mixed preview without partial state")
	check(paint(edit, native).ok, "identical mixed native batch retries")
	for index: int in range(0, native.points.size(), 2):
		check(oracle._stage(native.points[index], native.points[index + 1],
			INK, null, true, true, -1, true).ok,
			"mixed reference source pixel accepted")
	check(edit.generic_calls >= 4, "mixed NativeHard still uses generic staging")
	check(native.begins == 2 and native.commits == 1 and native.rollbacks == 1,
		"native retry transaction committed once")
	compare_commit(optimized, reference, edit, oracle)

func run() -> void:
	for masked: bool in [false, true]:
		for erase: bool in [false, true]:
			test_regular(masked, erase)
	test_mixed_and_retry()
	print("T101_NATIVE_DISPATCH_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T101_NATIVE_DISPATCH_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
