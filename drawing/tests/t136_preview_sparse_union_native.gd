extends SceneTree
## Actual software X11 draw: committed+detached indexed union, with RGBA8 parity.
var checks: int = 0
var failures: int = 0
var samples: Array[int] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T136_NATIVE_FAILED: " + label)

func frames(n: int = 3) -> void:
	for _i: int in range(n):
		await process_frame

func pixel(canvas: Control, source: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var at: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(source))
	if image == null or image.is_empty() or at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(at)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display required")
		quit(1)
		return
	root.size = Vector2i(820, 610)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(28, 28)
	canvas.size = Vector2(512, 384)
	canvas.zoom = 0.25
	canvas.tool = "Pan"
	root.add_child(canvas)
	# The fixture drives a detached editor draft directly, not an OS press.
	# Disable pointer draining and initialize only the phase counters required
	# by live preview draws. Actual input scheduling has separate witnesses.
	canvas.set_process(false)
	canvas._metrics.merge({"preview_frames": 0, "compose_cpu_us": 0,
		"texture_cpu_us": 0, "preview_index_cpu_us": 0,
		"bytes_uploaded": 0, "first_preview_submit_us": 0,
		"frame_phase_total": 0, "frame_phases_us": []}, true)
	var doc: DrawingDocument = DrawingDocument.new("t136-preview-union", 256)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var committed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(committed.paint_path(PackedVector2Array([Vector2(-64.5, -64.5)]), 0xff2020ef, 15.0).ok and
		committed.commit().ok, "signed red committed dab")
	canvas.document = doc
	canvas.layer_id = layer
	await frames(4)
	check(pixel(canvas, Vector2(-64.5, -64.5)).r > 0.7,
		"committed signed dab appears in framebuffer")
	var original_revision: int = doc.revision
	var draft: DrawingEditSession = doc.begin_edit(layer, original_revision).value as DrawingEditSession
	check(draft.paint_path(PackedVector2Array([Vector2(64.5, 64.5)]), 0xffee5520, 16.0).ok,
		"stage blue preview in previously empty display tile")
	canvas.session = draft
	canvas.queue_redraw()
	await frames(4)
	check(doc.revision == original_revision and int(doc.read_pixel(layer, 64, 64).value) == 0,
		"detached blue preview did not publish canonical pixels")
	check(pixel(canvas, Vector2(64.5, 64.5)).b > 0.65,
		"draft blue pixel visible in actual framebuffer")
	canvas.zoom = 0.01
	canvas.queue_redraw()
	await frames(4)
	var first: Dictionary = canvas.last_frame_metrics.duplicate()
	check(int(first.get("tiles_visible", 0)) > 50000,
		"preview workload spans over 50,000 screen-source display cells")
	check(int(first.get("preview_index_built", 0)) == 1 and int(first.get("preview_index_keys", 0)) > 0,
		"real draft provides complete bounded preview display index")
	check(int(first.get("sparse_draw", 0)) == 1,
		"complete preview union authorizes indexed traversal")
	check(int(first.get("tiles_examined", 999999)) < 16,
		"committed and preview-only tiles both visited without scanning empty viewport")
	check(int(first.get("empty_skipped", 0)) >= int(first.get("tiles_visible", 0)) - 16,
		"visible empty tiles skipped without textures")
	for i: int in range(7):
		canvas.queue_redraw()
		await frames(2)
		samples.append(int(canvas.last_frame_metrics.get("draw_cpu_us", -1)))
	check(samples.size() == 7 and samples.min() >= 0,
		"seven warm detached-preview draw CPU samples recorded")
	canvas.zoom = 1.0
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(-64.5, -64.5)).r > 0.7 and
		pixel(canvas, Vector2(64.5, 64.5)).b > 0.65,
		"committed red and draft blue pixels remain visible after zoom cycle")
	check(draft.paint_path(PackedVector2Array([Vector2(-32.5, 64.5)]), 0xffee5520, 16.0).ok,
		"append additional signed draft dab without committing")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(-32.5, 64.5)).b > 0.65,
		"new draft generation updates framebuffer without stale sparse result")
	canvas.zoom = 0.01
	canvas.queue_redraw()
	await frames(3)
	check(int(canvas.last_frame_metrics.get("sparse_draw", 0)) == 1 and
		int(canvas.last_frame_metrics.get("tiles_examined", 999999)) < 16,
		"updated preview index stays bounded at 1% zoom")
	# Full-scan fallback is intentionally tested at normal zoom: at 1% it
	# is an expensive safety path, not a performance benchmark.
	canvas.zoom = 0.25
	canvas._occupancy_unknown = true
	canvas.queue_redraw()
	await frames(3)
	check(int(canvas.last_frame_metrics.get("sparse_draw", 1)) == 0,
		"unknown committed occupancy forces exact legacy preview traversal")
	canvas._rebuild_occupancy()
	canvas.queue_redraw()
	await frames(3)
	check(int(canvas.last_frame_metrics.get("sparse_draw", 0)) == 1,
		"restored complete source occupancy permits indexed preview again")
	canvas.zoom = 1.0
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(-32.5, 64.5)).b > 0.65,
		"conservative fallback cannot drop detached pixels")
	draft.cancel()
	canvas.session = null
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(64.5, 64.5)).b < 0.5 and
		pixel(canvas, Vector2(-64.5, -64.5)).r > 0.7 and doc.revision == original_revision,
		"cancellation removes blue preview, never committed red")
	var new_edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(new_edit.paint_path(PackedVector2Array([Vector2(64.5, 64.5)]), 0xffee5520, 16.0).ok and
		new_edit.commit().ok, "new valid transaction commits preview source area")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(64.5, 64.5)).b > 0.65,
		"committed blue pixel visible after detached preview lifecycle")
	check(doc.undo().ok, "Undo source transaction")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(64.5, 64.5)).b < 0.5 and
		pixel(canvas, Vector2(-64.5, -64.5)).r > 0.7,
		"Undo exact pixels and retained committed red")
	check(doc.redo().ok, "Redo source transaction")
	canvas.queue_redraw()
	await frames(3)
	check(pixel(canvas, Vector2(64.5, 64.5)).b > 0.65,
		"Redo blue source pixel appears in framebuffer")
	check(canvas._display_tiles.size() <= canvas.MAX_DISPLAY_TILES,
		"retained GPU display tiles stay under the 144-entry cap")
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	print("T136_NATIVE_TIMING " + JSON.stringify({
		"engine": Engine.get_version_info().get("string"),
		"zoom": 0.01, "cells": first.get("tiles_visible"),
		"examined": first.get("tiles_examined"), "warm_draw_us": sorted,
		"p50_us": sorted[3], "p95_us": sorted[6]}))
	print("T136_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
