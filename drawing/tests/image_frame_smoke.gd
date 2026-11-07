extends SceneTree
## T-087: metadata/data separation, legacy compatibility and UI state.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T087_MODEL_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t087-sparse")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Art").value)
	var edit_result: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(edit_result.ok, "begin signed sparse paint")
	var edit: DrawingEditSession = edit_result.value as DrawingEditSession
	var hidden_rgb: PackedByteArray = PackedByteArray([51, 87, 203, 0])
	check(edit.apply_region(Rect2i(-900, -800, 1, 1), hidden_rgb).ok,
		"hidden RGB can exist outside image guide")
	check(edit.apply_region(Rect2i(840, 700, 1, 1), PackedByteArray([22, 120, 220, 255])).ok,
		"opaque paint can exist outside frame")
	check(edit.commit().ok, "commit one sparse revision")

	var frames: Array[Rect2i] = [Rect2i(-900, -800, 1800, 1600),
		Rect2i(-21, 13, 8, 16), Rect2i(999000, 999010, 96, 128),
		DrawingImageFrame.DEFAULT_BOUNDS]
	for bounds: Rect2i in frames:
		var data: Dictionary = DrawingImageFrame.encode(bounds)
		var decoded: DrawingResult = DrawingImageFrame.decode(data)
		check(decoded.ok and decoded.value == bounds,
			"signed image frame roundtrip %s" % bounds)
	for invalid: Variant in [{"origin": [1, 2], "size": [40, 50]},
		{"origin": ["-0", "0"], "size": [40, 50]},
		{"origin": ["0", "0"], "size": [0, 50]},
		{"origin": ["0", "0"], "size": [40.5, 50]},
		{"origin": ["1000000000", "0"], "size": [200, 50]},
		{"origin": ["0", "0"], "size": [1000001, 50]},
		{"origin": ["0", "0"], "size": [40, INF]}, {}]:
		check(not DrawingImageFrame.decode(invalid).ok,
			"malformed frame rejected: %s" % invalid)

	var path: String = ProjectSettings.globalize_path("user://t087-frame.drawing")
	var explicit_bounds: Rect2i = Rect2i(-21, 13, 80, 96)
	check(DrawingFileIO.save(doc, path,
		{"image_frame": DrawingImageFrame.encode(explicit_bounds)}).ok,
		"save bounded guide without cropping signed sparse pixels")
	var opened: DrawingResult = DrawingFileIO.open_with_frame(path)
	check(opened.ok, "open_with_frame checks canonical pixels and guide")
	if opened.ok:
		var loaded: Dictionary = opened.value
		check(loaded["image_frame"] == explicit_bounds, "guide stored independently of content")
		var restored: DrawingDocument = loaded["document"] as DrawingDocument
		check(int(restored.read_pixel(layer, -900, -800).value) == 0x00cb5733,
			"straight RGBA8 including invisible RGB survives outside guide")
		check(int(restored.read_pixel(layer, 840, 700).value) == 0xffdc7816,
			"unclipped opaque off-frame art survives ordinary reopen")
		check(restored.id == doc.id and restored.revision == doc.revision,
			"frame metadata cannot replace document identity/revision")
	var legacy: DrawingResult = DrawingFileIO.encode(doc)
	check(legacy.ok and not (legacy.value as Dictionary).has("image_frame"),
		"legacy byte format has no view guide")
	var legacy_frame: Rect2i = DrawingImageFrame.infer_legacy(doc)
	check(legacy_frame.has_point(Vector2i(-900, -800)) and
		legacy_frame.has_point(Vector2i(840, 700)),
		"legacy guide conservatively encloses signed sparse content")
	var legacy_path: String = ProjectSettings.globalize_path("user://t087-legacy.drawing")
	var file: FileAccess = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy.value))
	file.close()
	var read_legacy: DrawingResult = DrawingFileIO.open_with_frame(legacy_path)
	check(read_legacy.ok and (read_legacy.value as Dictionary)["image_frame"] == legacy_frame,
		"old ordinary file opens with inferred guide without migration")
	var malformed: Dictionary = (legacy.value as Dictionary).duplicate(true)
	malformed["image_frame"] = {"origin": ["0", "0"], "size": [-4, 4]}
	check(not DrawingFileIO.decode(malformed).ok,
		"bad optional guide is not silently ignored on ordinary load")
	check(not DrawingFileIO.save(doc, path, {"image_frame": malformed["image_frame"]}).ok,
		"invalid guide cannot overwrite a valid existing file")
	check(DrawingFileIO.open_with_frame(path).ok,
		"failed metadata validation kept previous file intact")
	var object_path: String = ProjectSettings.globalize_path("user://t087-object.drawing")
	check(DrawingFileIO.save(doc, object_path, {"object_source": {"name": "test"}}).ok,
		"Object Asset portable metadata continues to save independently")
	check(DrawingFileIO.open(object_path).ok, "legacy document-only open API preserved")

	# Independent session oracle: clipping restricts a *gesture*, not persisted
	# source storage, selection semantics or render/save/export boundaries.
	var frame_clip: Rect2i = Rect2i(-3, 5, 6, 4)
	var clip_doc: DrawingDocument = DrawingDocument.new("t087-clip")
	var clip_layer: String = String(clip_doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var clip_edit: DrawingEditSession = clip_doc.begin_edit(clip_layer, clip_doc.revision).value as DrawingEditSession
	check(clip_edit.paint_path(PackedVector2Array([Vector2(-10.5, 6.5),
		Vector2(10.5, 6.5)]), 0xff12ab34, 5.0, false, null, 100000, frame_clip).ok,
		"clipped wide stroke crosses both signed frame edges")
	check(clip_edit.change_count() > 0 and clip_doc.read_pixel(clip_layer, -3, 6).value == 0,
		"clip operates on detached candidate pixels before publication")
	check(clip_edit.commit().ok and clip_doc.read_pixel(clip_layer, -3, 6).value != 0
		and clip_doc.read_pixel(clip_layer, 2, 6).value != 0
		and clip_doc.read_pixel(clip_layer, -4, 6).value == 0
		and clip_doc.read_pixel(clip_layer, 3, 6).value == 0,
		"whole brush footprint, not just center, is cropped at signed extent")
	check(clip_doc.undo().ok and clip_doc.read_pixel(clip_layer, -3, 6).value == 0
		and clip_doc.redo().ok and clip_doc.read_pixel(clip_layer, 2, 6).value != 0,
		"clipped stroke remains exactly one Undo/Redo step")
	var restricted: DrawingSelection = DrawingSelection.new()
	restricted.set_rectangle(Rect2i(-2, 6, 2, 2))
	var restricted_edit: DrawingEditSession = clip_doc.begin_edit(clip_layer, clip_doc.revision).value as DrawingEditSession
	check(restricted_edit.paint_path(PackedVector2Array([Vector2(-10.5, 7.5),
		Vector2(10.5, 7.5)]), 0xff5500aa, 1.0, false, restricted,
		100000, frame_clip).ok and restricted_edit.commit().ok,
		"selection mask and frame both constrain stroke without mutating either")
	check(clip_doc.read_pixel(clip_layer, -2, 7).value != 0
		and clip_doc.read_pixel(clip_layer, 2, 7).value == 0xff12ab34
		and restricted.allows(Vector2i(-2, 7)) and not restricted.allows(Vector2i(2, 7)),
		"intersection with a signed selection excludes pixels inside frame but outside mask")
	var atlas_edit: DrawingEditSession = clip_doc.begin_edit(clip_layer, clip_doc.revision).value as DrawingEditSession
	check(atlas_edit.paint_path(PackedVector2Array([Vector2(12.5, 9.5)]),
		0xffaa11cc, 1.0).ok and atlas_edit.commit().ok and
		clip_doc.read_pixel(clip_layer, 12, 9).value != 0,
		"unclipped shared edit-session API still permits sparse Atlas pixels")
	var clip_path: String = ProjectSettings.globalize_path("user://t087-clip.drawing")
	check(DrawingFileIO.save(clip_doc, clip_path,
		{"image_frame": DrawingImageFrame.encode(frame_clip)}).ok,
		"saving a framed document does not delete pre-existing outside pixels")
	var clip_loaded: DrawingResult = DrawingFileIO.open_with_frame(clip_path)
	check(clip_loaded.ok and
		int((clip_loaded.value["document"] as DrawingDocument).read_pixel(clip_layer, 12, 9).value) != 0,
		"outside pixels survive framed save/reopen even though new strokes are clipped")
	DirAccess.remove_absolute(clip_path)

	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_persistence_enabled = false
	root.add_child(workspace)
	await process_frame
	await process_frame
	check(workspace.canvas.clip_strokes_to_image_frame,
		"standalone workspace opts in to stroke clipping; Atlas default is unbounded")
	check(workspace.canvas.image_bounds == DrawingImageFrame.DEFAULT_BOUNDS,
		"new standalone tab has an explicit visible guide")
	check(not workspace.canvas.snap_to_grid and not workspace.canvas.show_grid,
		"grid visibility and edit snap are independent and off by default")
	workspace._toggle_grid()
	check(workspace.canvas.show_grid and not workspace.canvas.snap_to_grid,
		"show grid does not enable snapping")
	workspace._set_snap_enabled(true)
	check(workspace.canvas.show_grid and workspace.canvas.snap_to_grid,
		"snap toggle does not hide grid")
	workspace.grid_fields[0].value = 12
	workspace.grid_fields[1].value = -3
	workspace.grid_fields[2].value = 5
	workspace._apply_grid_settings()
	check(workspace.canvas.grid_spacing == 12 and workspace.canvas.grid_origin == Vector2i(-3, 5),
		"configurable signed origin and spacing reach canvas")
	var sample: Vector2 = workspace.canvas.pixel_to_position(Vector2(8.4, 8.1))
	check(workspace.canvas.position_to_pixel(sample) == Vector2i(9, 5),
		"edit coordinates snap to configured independent grid")
	workspace._set_snap_enabled(false)
	check(workspace.canvas.position_to_pixel(sample) == Vector2i(8, 8) and
		workspace.canvas.show_grid, "snapping off leaves visible grid and raw edit coordinates")
	workspace.image_frame_fields[0].value = -42
	workspace.image_frame_fields[1].value = 27
	workspace.image_frame_fields[2].value = 75
	workspace.image_frame_fields[3].value = 95
	workspace._apply_image_frame()
	check(workspace.canvas.image_bounds == Rect2i(-42, 27, 75, 95) and
		bool(workspace.tabs[workspace.active_tab]["frame_dirty"]),
		"resizing image frame marks metadata dirty without cropping or document revision")
	var target_revision: int = workspace.current_document().revision
	check(target_revision == workspace.current_document().revision,
		"guide edits don't increment document generation")
	var ui_path: String = ProjectSettings.globalize_path("user://t087-workspace.drawing")
	workspace._save_file(ui_path)
	check(not bool(workspace.tabs[workspace.active_tab].get("frame_dirty", true)),
		"successful workspace Save clears view-metadata dirty indicator")
	workspace.image_frame_fields[2].value = 76
	workspace._apply_image_frame()
	check(bool(workspace.tabs[workspace.active_tab].get("frame_dirty", false)),
		"changing a saved frame marks only view metadata dirty")
	workspace.image_frame_fields[2].value = 75
	workspace._apply_image_frame()
	check(not bool(workspace.tabs[workspace.active_tab].get("frame_dirty", true)),
		"restoring saved frame clears spurious unsaved-change prompt")
	workspace._open_file(ui_path)
	check(workspace.canvas.image_bounds == Rect2i(-42, 27, 75, 95) and
		not bool(workspace.tabs[workspace.active_tab].get("frame_dirty", true)),
		"ordinary workspace Open restores explicit image frame")
	check(not workspace.canvas.show_grid and not workspace.canvas.snap_to_grid,
		"view-only grid and snap preferences are not embedded in .drawing bytes")
	workspace._activate(0)
	check(workspace.status.text.contains("image 75×95 @ -42,27") and
		workspace.status.text.contains("grid 12px @ -3,5"),
		"status names image dimensions, origin, cursor, grid origin and spacing")
	DirAccess.remove_absolute(ui_path)
	workspace.new_drawing()
	check(workspace.canvas.image_bounds == DrawingImageFrame.DEFAULT_BOUNDS and
		not workspace.canvas.snap_to_grid and not workspace.canvas.show_grid,
		"new tab doesn't inherit another tab's grid and frame settings")
	workspace._activate(0)
	check(workspace.canvas.image_bounds == Rect2i(-42, 27, 75, 95) and
		workspace.canvas.grid_spacing == 12 and workspace.canvas.show_grid,
		"switching tabs preserves per-tab guide/grid preferences")
	# Unlike Show grid, snap settings alter the meaning of a pending source
	# position. A selection drag must not combine two coordinate mappings.
	workspace.canvas.tool = "Select"
	workspace.canvas.clear_selection()
	workspace._set_snap_enabled(true)
	var select_start: Vector2 = workspace.canvas.pixel_to_position(Vector2(-3, 40))
	var select_end: Vector2 = workspace.canvas.pixel_to_position(Vector2(21, 64))
	workspace.canvas.start_gesture(select_start)
	workspace.canvas.update_gesture(select_end)
	check(workspace.canvas.dragging and workspace.canvas.selecting and
		workspace.canvas._marquee.has_area(),
		"grid-snapped marquee is pending before editing snap settings")
	workspace._toggle_grid()
	workspace.canvas.grid_spacing = 12
	workspace.canvas.grid_origin = Vector2i(-3, 5)
	check(workspace.canvas.dragging and workspace.canvas.selecting,
		"visual grid toggle and identical source-grid mapping retain marquee")
	workspace.grid_fields[0].value = 14
	workspace._apply_grid_settings()
	check(not workspace.canvas.dragging and not workspace.canvas.selecting and
		not workspace.canvas.selection_mask.enabled,
		"effective grid-spacing change cancels the unpublished marquee")
	workspace.canvas.finish_gesture(select_end)
	check(not workspace.canvas.selection_mask.enabled,
		"mouse-up after cancelled marquee cannot create a selection")
	workspace.canvas.grid_spacing = 12
	workspace.canvas.grid_origin = Vector2i(-3, 5)
	workspace._set_snap_enabled(false)
	# A host may turn standalone-style frame clipping on or off while input
	# is queued. Neither direction may publish a stroke authorized by the
	# old policy. Identical policy writes must not interrupt the gesture.
	workspace.canvas.tool = "Brush"
	workspace.canvas.brush_width = 1.0
	workspace.canvas.clip_strokes_to_image_frame = false
	var clip_canvas: Control = workspace.canvas
	var clip_document: DrawingDocument = workspace.current_document()
	var clip_revision: int = clip_document.revision
	var outside_point: Vector2 = clip_canvas.pixel_to_position(Vector2(-60.5, 40.5))
	clip_canvas.start_gesture(outside_point)
	check(clip_canvas.session != null and clip_canvas.dragging,
		"unbounded Brush is captured outside the image guide before policy change")
	clip_canvas.clip_strokes_to_image_frame = true
	check(clip_canvas.session == null and not clip_canvas.dragging and
		clip_document.revision == clip_revision and not clip_canvas._owns_accumulated_input,
		"enabling clipping cancels an unbounded queued Brush and restores input mode")
	clip_canvas.finish_gesture(outside_point)
	check(clip_document.revision == clip_revision,
		"stale release after clipping enabled never publishes the old Brush")
	var inside_point: Vector2 = clip_canvas.pixel_to_position(Vector2(-20.5, 40.5))
	clip_canvas.start_gesture(inside_point)
	check(clip_canvas.session != null and clip_canvas.dragging,
		"frame-clipped Brush begins inside the guide")
	clip_canvas.clip_strokes_to_image_frame = false
	check(clip_canvas.session == null and not clip_canvas.dragging and
		clip_document.revision == clip_revision and not clip_canvas._owns_accumulated_input,
		"disabling clipping discards old-policy pixels without history")
	clip_canvas.finish_gesture(inside_point)
	check(clip_document.revision == clip_revision,
		"stale release after disabling clipping has no document side effects")
	clip_canvas.start_gesture(outside_point)
	clip_canvas.clip_strokes_to_image_frame = false
	check(clip_canvas.session != null and clip_canvas.dragging,
		"equivalent clipping assignment preserves an active unbounded Brush")
	clip_canvas.finish_gesture(outside_point)
	check(clip_canvas.session == null and clip_document.revision == clip_revision + 1,
		"unchanged clipping policy publishes exactly one normal history edit")
	check(clip_document.undo().ok and clip_document.revision == clip_revision + 2,
		"ordinary post-policy-change Brush remains undoable")
	workspace.queue_free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(legacy_path)
	DirAccess.remove_absolute(object_path)
	print("T087_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T087_MODEL_PASSED")
	quit(1 if failures else 0)
