extends SceneTree
## T-044: single-window admission, denial and lifecycle. No browser runtime claim.
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WEB FALLBACK FAILED: " + why)


func _run() -> void:
	var session: AtlasPlayerOutputSession = AtlasPlayerOutputSession.new()
	root.add_child(session)
	_check(not session.open_native(Vector2i(320, 180)), "headless native window denied")
	_check(not session.open_embedded(null), "null host denied")
	var host: Control = Control.new()
	host.size = Vector2(320, 180)
	root.add_child(host)
	var unexpected: Label = Label.new()
	host.add_child(unexpected)
	_check(not session.open_embedded(host), "host containing GM UI denied")
	host.remove_child(unexpected)
	unexpected.free()
	host.size = Vector2.ZERO
	_check(not session.open_embedded(host), "zero size denied")
	host.size = Vector2(5000, 2000)
	_check(not session.open_embedded(host), "oversized size denied")
	host.size = Vector2(320, 180)
	_check(session.open_embedded(host), "dedicated host accepted")
	_check(session.window == null and session.display != null and session.display.texture == null,
		"single-window output starts blank")
	_check(session._embedded_background.color == Color.BLACK \
		and session._embedded_background.mouse_filter == Control.MOUSE_FILTER_STOP,
		"input-blocking black background")
	_check(session.display.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"player image has no drawing interaction")
	_check(session._capture != null and session._capture.canvas == null,
		"no canonical GM canvas is parented to output")
	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	frame.set_output_size(Vector2i(1280, 720))
	frame.set_view(Vector2.ZERO, 64.0)
	_check(session.update_frame(frame), "frame accepted at matching aspect")
	var grants: Array[String] = ["public"]
	_check(not await session.publish(null, "missing", 0, grants), "missing source denied")
	_check(session.display.texture == null, "denied frame remains blank")
	var source: AtlasMapDocument = AtlasMapDocument.new("gm", "GM secret")
	_check(not await session.publish(source, source.default_floor_id, 0, grants),
		"unrecognized layer grant denied")
	_check(session.display.texture == null, "invalid grant cannot publish")
	host.size = Vector2(400, 225)
	_check(session.output_size == Vector2i(400, 225) and not session._frame_set \
		and session.display.texture == null, "resizing clears old camera/image")
	_check(not await session.publish(source, source.default_floor_id, 0, grants),
		"resize requires frame renewal")
	_check(session.update_frame(frame), "same aspect permits renewed camera")
	host.size = Vector2(400, 300)
	_check(not session.update_frame(frame), "mismatched aspect denied")
	host.hide()
	_check(not session._frame_set and not session._output_ready(), "hidden host unauthorized")
	host.show()
	_check(session.display.texture == null and not session._frame_set,
		"show does not resurrect stale pixels")
	session.close_output()
	_check(session.display == null and session._capture == null and session._embedded_host == null,
		"close destroys capture and host references")
	await process_frame
	_check(host.get_child_count() == 0 and session.open_embedded(host),
		"same dedicated host can reopen after cleanup")
	root.remove_child(session)
	_check(session._embedded_host == null and session.display == null,
		"session leaving tree clears external surface")
	await process_frame
	_check(host.get_child_count() == 0, "no player surface left in host")
	root.add_child(session)
	root.remove_child(host)
	host.free()
	root.remove_child(session)
	session.free()
	print("ATLAS_PLAYER_WEB_FALLBACK_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
