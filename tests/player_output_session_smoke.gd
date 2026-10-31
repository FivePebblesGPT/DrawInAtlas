extends SceneTree
## T-040: camera/freeze and physical calibration contract without native display.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("PLAYER OUTPUT FAILED: " + description)


func _run() -> void:
	var calibration: AtlasProjectorCalibration = AtlasProjectorCalibration.new()
	_check(is_nan(calibration.actual_cell_mm(400.0, 10.0)), "no guessed screen dimensions or DPI")
	_check(not calibration.set_measurements(0.0, 25.0) \
		and not calibration.set_measurements(NAN, 25.0) \
		and not calibration.set_measurements(1000.0, INF) \
		and not calibration.set_measurements(100.0, 120.0), "invalid measurements denied")
	_check(calibration.set_measurements(800.0, 25.0), "measured physical width accepted")
	_check(is_equal_approx(calibration.suggested_frame_width(10.0), 320.0), "calibration suggests independent board-frame width")
	_check(is_equal_approx(calibration.actual_cell_mm(320.0, 10.0), 25.0), "current frame physical cell size")
	_check(is_equal_approx(calibration.pixels_per_mm(1920), 2.4), "resolution-to-physical scaling is independent")
	_check(is_equal_approx(calibration.actual_cell_mm(400.0, 10.0), 20.0), "frame pan/zoom does not change measurement")
	_check(calibration.set_measurements(760.0, 20.0) \
		and is_equal_approx(calibration.suggested_frame_width(10.0), 380.0), "recalibration changes suggestion only")
	_check(is_nan(calibration.suggested_frame_width(0.0)) \
		and is_nan(calibration.actual_cell_mm(-1.0, 5.0)) \
		and is_nan(calibration.pixels_per_mm(0)), "invalid geometry never yields a plausible number")

	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	var before: Rect2 = frame.bounds()
	_check(calibration.set_measurements(800.0, 25.0) and frame.bounds() == before,
		"calibration cannot mutate project framing or artwork")
	var session: AtlasPlayerOutputSession = AtlasPlayerOutputSession.new()
	root.add_child(session)
	_check(not session.open_native(Vector2i.ZERO) and not session.open_native(Vector2i(10000, 10000)),
		"invalid dimensions and expensive framebuffers are rejected")
	_check(not session.update_frame(frame), "no frame published without an output window")
	_check(not await session.publish(null, "missing", 0, []), "no document cannot publish")
	_check(session.display == null, "no fallback to editor content in a headless session")
	root.remove_child(session)
	session.free()
	print("ATLAS_PLAYER_OUTPUT_SESSION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
