extends SceneTree
## T-088 deterministic model + workspace contracts; no OS framebuffer needed.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T088_MODEL_FAILED: " + label)


func read(doc: DrawingDocument, layer: String, pixel: Vector2i) -> int:
	var result: DrawingResult = doc.read_pixel(layer, pixel.x, pixel.y)
	check(result.ok, "read pixel %s" % pixel)
	return int(result.value) if result.ok else -1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-17, -2, 35, 4), true)
	check(selection.allows(Vector2i(-17, -2)) and selection.allows(Vector2i(17, 1))
		and not selection.allows(Vector2i(18, 1)), "signed rectangular base mask")
	check(selection.combine_rectangle(Rect2i(-1, -1, 3, 2), "Subtract"), "subtract hole")
	check(not selection.allows(Vector2i(0, 0)) and selection.allows(Vector2i(-2, 0)),
		"subtracted center invisible to mask")
	check(selection.combine_rectangle(Rect2i(24, -1, 2, 2), "Add") and
		selection.allows(Vector2i(24, 0)) and selection.bounds.has_point(Vector2i(25, 0)),
		"detached island and conservative enclosing rect")
	check(selection.combine_rectangle(Rect2i(-20, -1, 50, 2), "Intersect") and
		not selection.allows(Vector2i(-17, -2)) and selection.allows(Vector2i(24, 0)),
		"intersection updates channel but not pixels")
	var duplicate: DrawingSelection = selection.detached_copy()
	check(duplicate.same_as(selection), "mask copy retains boolean operation tree")
	check(not selection.combine_rectangle(Rect2i(0, 0, 1, 1), "Wrong") and
		duplicate.same_as(selection), "invalid combine mode is non-mutating")
	var moved_mask: DrawingSelection = selection.translated(Vector2i(-30, 5))
	check(moved_mask.allows(Vector2i(-6, 5)) and not moved_mask.allows(Vector2i(-30, 5))
		and selection.allows(Vector2i(24, 0)), "translated island and hole preserve source mask")
	duplicate.combine_rectangle(Rect2i(24, 0, 2, 1), "Subtract")
	check(not duplicate.same_as(selection), "selection copy is detached from mutation")
	var empty: DrawingSelection = DrawingSelection.new()
	check(not empty.enabled and empty.allows(Vector2i(999, -999)),
		"deselected channel permits unrestricted editing")
	var deny_all: DrawingSelection = DrawingSelection.new(Rect2i(), true)
	check(deny_all.enabled and not deny_all.allows(Vector2i.ZERO) and
		not deny_all.allows(Vector2i(-200000, 800000)),
		"active empty mask denies all pixels (Atlas compatibility contract)")
	var impossible: DrawingSelection = DrawingSelection.new(Rect2i(-2, 0, 2, 2), true)
	check(impossible.combine_rectangle(Rect2i(400, 400, 1, 1), "Intersect") and
		impossible.enabled and not impossible.allows(Vector2i(-2, 0)),
		"disjoint intersection remains deny-all, not unrestricted")
	check(empty.combine_rectangle(Rect2i(-1, -1, 2, 2), "Add") and empty.enabled,
		"Add to no selection produces initial rectangle")
	empty.clear()
	check(not empty.enabled and not empty.bounds.has_area(), "clear resets mask")

	var pixels_only: DrawingSelection = DrawingSelection.new(Rect2i(-2, -2, 4, 4), true)
	var sparse_cells: Dictionary[Vector2i, bool] = {}
	sparse_cells[Vector2i(-2, -2)] = true
	sparse_cells[Vector2i(1, 1)] = true
	pixels_only.set_mask(sparse_cells)
	check(pixels_only.allows(Vector2i(-2, -2)) and pixels_only.allows(Vector2i(1, 1))
		and not pixels_only.allows(Vector2i(0, 0)),
		"selection channel accepts explicit irregular per-pixel mask")
	check(pixels_only.detached_copy().same_as(pixels_only),
		"pixel-channel detached copy survives exact comparison")
	var optional_history: DrawingDocument = DrawingDocument.new("t088-selection-history")
	optional_history.record_selection_history = true
	var before_selection: DrawingHistoryContext = DrawingHistoryContext.new()
	before_selection.document_id = optional_history.id
	before_selection.selection_mask = DrawingSelection.new(Rect2i(0, 0, 2, 2), true)
	before_selection.selected_rect = before_selection.selection_mask.bounds
	var after_selection: DrawingHistoryContext = before_selection.detached_copy()
	after_selection.selection_mask.combine_rectangle(Rect2i(0, 0, 1, 1), "Subtract")
	var selection_revision: int = optional_history.revision
	check(optional_history.record_selection_change(before_selection, after_selection),
		"optional selection history records channel holes rather than only bounds")
	var selection_undo: DrawingResult = optional_history.undo()
	check(selection_undo.ok and (selection_undo.value as DrawingHistoryContext).selection_mask.same_as(
		before_selection.selection_mask) and optional_history.revision == selection_revision,
		"selection-only undo restores snapshot without changing revision")
	var selection_redo: DrawingResult = optional_history.redo()
	check(selection_redo.ok and (selection_redo.value as DrawingHistoryContext).selection_mask.same_as(
		after_selection.selection_mask) and not optional_history.is_dirty(),
		"selection-only redo restores hole and stays non-dirty")

	var doc: DrawingDocument = DrawingDocument.new("t088-mask", 16)
	var under: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Under").value)
	var active: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Active").value)
	var seed: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(seed._stage(-17, 0, 0xff663322).ok and seed._stage(-16, 0, 0x00224466).ok
		and seed._stage(-15, 0, 0xffaabbcc).ok and seed._stage(0, 0, 0xff778899).ok
		and seed.commit().ok, "seed signed tile seam including hidden RGB")
	var area: Rect2i = Rect2i(-17, 0, 18, 1)
	var holes: DrawingSelection = DrawingSelection.new(area, true)
	holes.combine_rectangle(Rect2i(-15, 0, 1, 1), "Subtract")
	var capture: DrawingResult = DrawingClipboard.capture(doc, active, area, holes)
	check(capture.ok, "capture active raster with signed seam and hole")
	var clip: DrawingClipboard = capture.value as DrawingClipboard
	check(clip._pixels.get(Vector2i(0, 0), 0) == 0xff663322 and
		clip._pixels.get(Vector2i(1, 0), 0) == 0x00224466 and
		not clip._pixels.has(Vector2i(2, 0)), "copy preserves hidden RGB and excludes mask hole")
	var before_revision: int = doc.revision
	var mask_paint: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(mask_paint.paint_path(PackedVector2Array([Vector2(-17.5, 0.5),
		Vector2(-14.5, 0.5)]), 0xff55ccaa, 1.0, false, holes).ok,
		"paint stroke accepts independent mask")
	check(doc.revision == before_revision and read(doc, active, Vector2i(-17, 0)) == 0xff663322,
		"masked paint remains detached")
	check(mask_paint.commit().ok, "masked brush commits atomically")
	check(read(doc, active, Vector2i(-15, 0)) == 0xffaabbcc,
		"masked brush cannot touch hole")
	check(doc.undo().ok and read(doc, active, Vector2i(-17, 0)) == 0xff663322,
		"single undo restores painted pixels across seam")
	check(doc.redo().ok, "single redo restores constrained brush")
	var clearing: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(clearing.clear_rect(area, holes).ok and clearing.commit().ok,
		"delete obeys selection mask")
	check(read(doc, active, Vector2i(-17, 0)) == 0 and
		read(doc, active, Vector2i(-15, 0)) == 0xffaabbcc,
		"delete clears included pixels but not masked hole")
	check(doc.undo().ok, "delete is one undo transaction")

	var fill_edit: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(fill_edit.fill_rect(Rect2i(-17, 0, 4, 1), 0xff123456, holes).ok,
		"filling accepts selection independently of rectangle extent")
	check(fill_edit.commit().ok and read(doc, active, Vector2i(-15, 0)) == 0xffaabbcc and
		read(doc, active, Vector2i(-17, 0)) == 0xff123456,
		"fill respects internal channel hole and changes included pixels")
	check(doc.undo().ok, "fill is one undo transaction")
	var flood_seed: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(flood_seed.fill_rect(Rect2i(-5, 4, 5, 1), 0xffbbbbbb).ok and flood_seed.commit().ok,
		"seed nonblank connected region for flood fill")
	var flood_selection: DrawingSelection = DrawingSelection.new(Rect2i(-5, 4, 5, 1), true)
	flood_selection.combine_rectangle(Rect2i(-3, 4, 1, 1), "Subtract")
	var flood_edit: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(flood_edit.flood_fill(Vector2i(-5, 4), 0xff66ccdd, flood_selection, 100).ok,
		"flood fill accepts mask as bounded channel")
	check(flood_edit.commit().ok and read(doc, active, Vector2i(-5, 4)) == 0xff66ccdd and
		read(doc, active, Vector2i(-3, 4)) == 0xffbbbbbb and
		read(doc, active, Vector2i(-2, 4)) == 0xffbbbbbb,
		"flood fill does not cross selected hole or change excluded pixels")
	var overflow_clip: DrawingClipboard = clip
	var rejected_paste: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	var failed_paste: DrawingResult = overflow_clip.paste(rejected_paste, Vector2i(1073741823, 0))
	check(not failed_paste.ok and rejected_paste.change_count() == 0,
		"out-of-range destination fails atomically, no staged changes survive")
	rejected_paste.cancel()

	var before_copy_revision: int = doc.revision
	var paste: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(clip.paste(paste, Vector2i(-9, 4)).ok and paste.commit().ok,
		"paste captured mask into signed destination")
	check(read(doc, active, Vector2i(-9, 4)) == 0xff663322 and
		read(doc, active, Vector2i(-8, 4)) == 0x00224466 and
		read(doc, active, Vector2i(-7, 4)) == 0,
		"pasted payload retains hidden RGB and masks absent cell")
	check(doc.revision == before_copy_revision + 1 and doc.undo().ok and
		read(doc, active, Vector2i(-9, 4)) == 0,
		"pasted content adds one undoable revision")
	check(doc.redo().ok and read(doc, active, Vector2i(-9, 4)) == 0xff663322,
		"paste redo exact bytes")

	var move_region: Rect2i = Rect2i(-17, 0, 3, 1)
	var move_selection: DrawingSelection = DrawingSelection.new(move_region, true)
	move_selection.combine_rectangle(Rect2i(-15, 0, 1, 1), "Subtract")
	var first_before_move: int = read(doc, active, Vector2i(-17, 0))
	var second_before_move: int = read(doc, active, Vector2i(-16, 0))
	var move_edit: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	check(DrawingClipboard.move_selection(move_edit, move_region, Vector2i(2, 0),
		move_selection).ok, "overlapping seam-crossing masked move staged")
	var preview: DrawingResult = DrawingRenderer.render(doc, Rect2i(-20, -1, 30, 4),
		0, 0, 1048576, move_edit)
	check(preview.ok and doc.read_pixel(active, -17, 0).value != 0,
		"move preview detached from canonical bytes")
	check(move_edit.commit().ok, "move makes one transaction")
	check(read(doc, active, Vector2i(-17, 0)) == 0 and
		read(doc, active, Vector2i(-15, 0)) == first_before_move and
		read(doc, active, Vector2i(-14, 0)) == second_before_move,
		"overlap move restores destination from original capture, respects hole")
	check(doc.undo().ok and read(doc, active, Vector2i(-17, 0)) == first_before_move,
		"move undo restores original source")
	check(doc.redo().ok and read(doc, active, Vector2i(-14, 0)) == second_before_move,
		"move redo restores destination")

	var saved_revision: int = doc.revision
	var locked: DrawingResult = doc.set_locked(active, true)
	check(locked.ok and not doc.begin_edit(active, doc.revision).ok,
		"locked active layer cannot be deleted, pasted or moved")
	check(doc.set_locked(active, false).ok and doc.set_visibility(active, false).ok and
		not doc.begin_edit(active, doc.revision).ok,
		"hidden active layer is not editable")
	check(doc.set_visibility(active, true).ok and doc.revision > saved_revision,
		"lock/visibility transitions retain monotonic revisions")
	var too_large: DrawingResult = DrawingClipboard.capture(doc, active,
		Rect2i(-2000, 0, 2000, 1000), null)
	check(not too_large.ok and too_large.code == "CLIPBOARD_LIMIT",
		"clipboard pixel budget enforced before allocation")
	var stale: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	var initial: int = doc.revision
	check(stale.clear_rect(Rect2i(-15, 0, 1, 1)).ok, "stage stale edit")
	check(doc.set_locked(under, true).ok and doc.revision == initial + 1,
		"concurrent structural change invalidates edit")
	check(not stale.commit().ok, "stale commit rejected without publishing")

	var context_before: DrawingHistoryContext = DrawingHistoryContext.new()
	context_before.selected_rect = selection.bounds
	context_before.selection_mask = selection.detached_copy()
	var context_after: DrawingHistoryContext = context_before.detached_copy()
	context_after.selection_mask = selection.translated(Vector2i(3, 4))
	check(not context_before.same_selection(context_after) and
		context_before.selection_mask.same_as(selection),
		"history recognizes shape changes with unchanged or shifted bounds")
	var another_copy: DrawingHistoryContext = context_after.detached_copy()
	another_copy.selection_mask.clear()
	check(context_after.selection_mask.enabled, "history context holds independent channel snapshot")

	var path: String = ProjectSettings.globalize_path("user://t088-mask.drawing")
	check(DrawingFileIO.save(doc, path).ok, "save canonical raster without ephemeral selection channel")
	var opened: DrawingResult = DrawingFileIO.open(path)
	check(opened.ok and read(opened.value as DrawingDocument, active, Vector2i(-14, 0)) ==
		second_before_move, "reopen exact bytes after signed-seam move")
	check((opened.value as DrawingDocument).id == doc.id,
		"reopened document retains identity; selection does not enter file schema")

	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_persistence_enabled = false
	root.add_child(workspace)
	await process_frame
	await process_frame
	var work_doc: DrawingDocument = workspace.current_document()
	var work_layer: String = workspace.current_layer()
	var clean_revision: int = work_doc.revision
	var initially_dirty: bool = work_doc.is_dirty()
	workspace.canvas.set_selection_mask(DrawingSelection.new(Rect2i(-1, -1, 4, 4), true))
	check(work_doc.revision == clean_revision and work_doc.is_dirty() == initially_dirty,
		"selection changes are non-dirty when history preference off")
	workspace._set_selection_mode("Subtract")
	check(workspace.canvas.selection_mode == "Subtract", "workspace exposes selectable mask mode")
	workspace._set_selection_mode("Replace")
	workspace._deselect()
	check(not workspace.canvas.selection_mask.enabled and work_doc.is_dirty() == initially_dirty,
		"Ctrl+D/menu deselect doesn't affect content or dirty state")
	var seed_ui: DrawingEditSession = work_doc.begin_edit(work_layer, work_doc.revision).value as DrawingEditSession
	check(seed_ui._stage(-1, -1, 0xff998877).ok and seed_ui.commit().ok,
		"seed workspace active layer")
	workspace.canvas.set_selection_mask(DrawingSelection.new(Rect2i(-1, -1, 1, 1), true))
	var old_rev: int = work_doc.revision
	workspace._copy_selection()
	check(workspace.drawing_clipboard != null and work_doc.revision == old_rev,
		"workspace Copy does not modify document revision")
	workspace._cut_selection()
	check(work_doc.revision == old_rev + 1 and read(work_doc, work_layer, Vector2i(-1, -1)) == 0,
		"workspace Cut clears only selected pixel in one revision")
	workspace._paste_selection()
	check(read(work_doc, work_layer, Vector2i(7, 7)) == 0xff998877 and
		workspace.canvas.selected == Rect2i(7, 7, 1, 1),
		"workspace Paste selects translated payload at deterministic offset")
	workspace._undo()
	check(read(work_doc, work_layer, Vector2i(7, 7)) == 0 and
		workspace.canvas.selected == Rect2i(-1, -1, 1, 1),
		"undo restores exact content and original selection context")
	workspace._redo()
	check(read(work_doc, work_layer, Vector2i(7, 7)) == 0xff998877 and
		workspace.canvas.selected == Rect2i(7, 7, 1, 1),
		"redo restores content and translated selection")
	workspace._delete_selection()
	check(read(work_doc, work_layer, Vector2i(7, 7)) == 0,
		"workspace Delete removes selected content")
	workspace._undo()
	check(read(work_doc, work_layer, Vector2i(7, 7)) == 0xff998877,
		"Delete undo restores exact content")

	# Floating Move is a transient selected-pixel operation, not one commit per
	# pointer release. Verify source identity across overlapping signed offsets,
	# a channel hole, nonzero RGB hidden under alpha zero and the history cursor.
	var float_seed: DrawingEditSession = work_doc.begin_edit(work_layer, work_doc.revision).value as DrawingEditSession
	check(float_seed._stage(-17, 20, 0xffaabbcc).ok and
		float_seed._stage(-16, 20, 0x00bb99aa).ok and
		float_seed._stage(-15, 20, 0xff114477).ok and
		float_seed._stage(-14, 20, 0xff882211).ok and float_seed.commit().ok,
		"seed floating-move source across signed seam with alpha-zero RGB")
	var float_mask: DrawingSelection = DrawingSelection.new(Rect2i(-17, 20, 4, 1), true)
	float_mask.combine_rectangle(Rect2i(-15, 20, 1, 1), "Subtract")
	var float_canvas: Control = workspace.canvas
	float_canvas.set_selection_mask(float_mask)
	workspace._change_tool("Move")
	var float_rev: int = work_doc.revision
	var float_history: int = work_doc.history_length()
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(-16.5, 20.5)))
	float_canvas.finish_gesture(float_canvas.pixel_to_position(Vector2(-15.5, 20.5)))
	check(float_canvas.has_floating_move() and float_canvas._move_preview != null and
		float_canvas._floating_offset == Vector2i(1, 0) and
		work_doc.revision == float_rev and work_doc.history_length() == float_history,
		"first floating mouse-up retains source revision and history unchanged")
	check(read(work_doc, work_layer, Vector2i(-17, 20)) == 0xffaabbcc and
		read(work_doc, work_layer, Vector2i(-16, 20)) == 0x00bb99aa,
		"held floating preview has not changed byte-exact source including hidden RGB")
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(-15.5, 20.5)))
	float_canvas.finish_gesture(float_canvas.pixel_to_position(Vector2(-13.5, 20.5)))
	check(float_canvas.has_floating_move() and float_canvas._floating_offset == Vector2i(3, 0) and
		float_canvas.selection_mask.allows(Vector2i(-14, 20)) and
		not float_canvas.selection_mask.allows(Vector2i(-12, 20)) and
		work_doc.revision == float_rev,
		"second drag accumulates offset; mask hole stays at shifted source location")
	workspace._drop_floating_move()
	check(not float_canvas.has_floating_move() and work_doc.revision == float_rev + 1 and
		work_doc.history_length() == float_history + 1,
		"explicit Drop publishes one undoable edit after two pointer releases")
	check(read(work_doc, work_layer, Vector2i(-17, 20)) == 0 and
		read(work_doc, work_layer, Vector2i(-16, 20)) == 0 and
		read(work_doc, work_layer, Vector2i(-15, 20)) == 0xff114477 and
		read(work_doc, work_layer, Vector2i(-14, 20)) == 0xffaabbcc and
		read(work_doc, work_layer, Vector2i(-13, 20)) == 0x00bb99aa and
		read(work_doc, work_layer, Vector2i(-11, 20)) == 0xff882211,
		"Move retains exact RGBA8, independent hole and overlapping source/target")
	workspace._undo()
	check(read(work_doc, work_layer, Vector2i(-17, 20)) == 0xffaabbcc and
		read(work_doc, work_layer, Vector2i(-13, 20)) == 0 and
		float_canvas.selection_mask.allows(Vector2i(-17, 20)),
		"one Undo restores exact source plus original channel context")
	workspace._redo()
	check(read(work_doc, work_layer, Vector2i(-13, 20)) == 0x00bb99aa and
		float_canvas.selection_mask.allows(Vector2i(-14, 20)),
		"one Redo reapplies complete move and translated mask")
	var cancel_rev: int = work_doc.revision
	var cancel_cursor: int = work_doc.history_position()
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(-13.5, 20.5)))
	float_canvas.finish_gesture(float_canvas.pixel_to_position(Vector2(-10.5, 20.5)))
	check(float_canvas.has_floating_move(), "subsequent operation can float committed piece")
	workspace._undo()
	check(not float_canvas.has_floating_move() and work_doc.revision == cancel_rev and
		work_doc.history_position() == cancel_cursor and
		read(work_doc, work_layer, Vector2i(-13, 20)) == 0x00bb99aa,
		"Ctrl+Z cancels floating preview rather than undoing an older edit")
	# Switching to Select drops the floating selection before any new marquee,
	# as verified in the PhotoCraft command behavior. No second history entry.
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(-13.5, 20.5)))
	float_canvas.finish_gesture(float_canvas.pixel_to_position(Vector2(-12.5, 20.5)))
	var implicit_rev: int = work_doc.revision
	workspace._change_tool("Select")
	check(workspace.active_tool == "Select" and not float_canvas.has_floating_move() and
		work_doc.revision == implicit_rev + 1 and
		read(work_doc, work_layer, Vector2i(-12, 20)) == 0x00bb99aa,
		"Select command implicitly drops floating pixels once before new operation")
	workspace._change_tool("Move")
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(-12.5, 20.5)))
	float_canvas.finish_gesture(float_canvas.pixel_to_position(Vector2(-11.5, 20.5)))
	var outside_rev: int = work_doc.revision
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(40.5, 40.5)))
	check(not float_canvas.has_floating_move() and work_doc.revision == outside_rev + 1 and
		read(work_doc, work_layer, Vector2i(-11, 20)) == 0x00bb99aa,
		"click outside floating mask drops pixels without starting an extra gesture")
	# External canonical revision invalidates the entire detached preview and
	# leaves the source untouched; no stale pixel delta may be published.
	float_canvas.start_gesture(float_canvas.pixel_to_position(Vector2(-11.5, 20.5)))
	float_canvas.finish_gesture(float_canvas.pixel_to_position(Vector2(-10.5, 20.5)))
	check(float_canvas.has_floating_move(), "external revision stale test starts floating")
	var ext: DrawingEditSession = work_doc.begin_edit(work_layer, work_doc.revision).value as DrawingEditSession
	check(ext._stage(45, 20, 0xff010203).ok and ext.commit().ok,
		"concurrent canonical edit advances document revision")
	float_canvas._process(0.0)
	check(not float_canvas.has_floating_move() and float_canvas._move_preview == null and
		read(work_doc, work_layer, Vector2i(-11, 20)) == 0x00bb99aa and
		read(work_doc, work_layer, Vector2i(-10, 20)) == 0,
		"stale preview auto-cancels and does not leak pixels or change selection")
	workspace.queue_free()
	print("T088_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T088_MODEL_PASSED")
	quit(1 if failures else 0)
