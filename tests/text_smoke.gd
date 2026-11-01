extends SceneTree
## T-027: text metadata, selection/transform, in-editor revision and persistence.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEXT FAILED: " + reason)

func _run() -> void:
	var origin: Vector2 = Vector2(40, 60)
	var label: AtlasStroke = AtlasTextLayout.make(origin, "Greyhaven\nEast Gate", "Serif", 20.0,
		Color(0.8, 0.9, 0.95, 0.65), true, true)
	_check(label != null and label.is_text() and label.is_valid(), "typed editable text")
	_check(label.points.size() == 1 and label.font_family == "Serif" and label.text_bold and label.text_italic, "explicit font/style metadata")
	_check(AtlasTextLayout.bounds(label).size.x > 50 and AtlasTextLayout.bounds(label).size.y > 30, "multiline font bounds")
	_check(not AtlasTextLayout.readable(label, 0.4) and AtlasTextLayout.readable(label, 0.5), "9 screen px culling threshold")
	_check(label.copy().to_dict() == label.to_dict() and AtlasStroke.from_dict(label.to_dict()).to_dict() == label.to_dict(), "clone and dictionary roundtrip")
	var broken: Dictionary = label.to_dict().duplicate(true)
	broken["text_bold"] = "yes"
	_check(AtlasStroke.from_dict(broken) == null, "invalid style rejected")
	broken = label.to_dict().duplicate(true)
	broken["text"] = ""
	_check(AtlasStroke.from_dict(broken) == null, "empty text not persisted as normal stroke")
	broken = label.to_dict().duplicate(true)
	broken["font_family"] = "Unknown"
	_check(AtlasStroke.from_dict(broken) == null, "invalid font family rejected")
	_check(AtlasStroke.from_dict({"points": [[0, 0]], "width": 2, "color": [1, 1, 1, 1]}) != null, "legacy stroke unaffected")
	var copy: AtlasClipboardData = AtlasClipboard.decode(AtlasClipboard.encode_ink([label], [0], origin))
	_check(copy != null and copy.strokes.size() == 1 and copy.strokes[0].text == label.text and copy.strokes[0].points[0] == Vector2.ZERO,
		"clipboard retains text and relative anchor")
	var ink: AtlasInkLayer = AtlasInkLayer.new()
	ink.strokes.append(label.copy())
	var box: Rect2 = AtlasTextLayout.bounds(label)
	_check(AtlasSelectionGeometry.stroke_bounds(label) == box, "selection bounds use glyph extent")
	_check(AtlasSelectionGeometry.select_point(ink, box.get_center(), 1.0).stroke_indices == [0], "select text by visible bounds")
	_check(AtlasSelectionGeometry.select_rect(ink, box.grow(2)).stroke_indices == [0], "marquee selects text")
	var selection: AtlasSelection = AtlasSelectionGeometry.select_indices(ink, [0])
	var transformed: AtlasInkLayer = AtlasSelectionGeometry.transformed(ink, selection,
		Transform2D(0, Vector2(20, 15))) as AtlasInkLayer
	_check(transformed != null and transformed.strokes[0].text == label.text and transformed.strokes[0].points[0] == origin + Vector2(20, 15),
		"move is lossless")
	var scaled: AtlasInkLayer = AtlasSelectionGeometry.transformed(ink, selection,
		AtlasSelectionGeometry.about(box.position, Vector2.ZERO, 1.5)) as AtlasInkLayer
	_check(scaled != null and is_equal_approx(scaled.strokes[0].width, 30.0), "text size scales with selection")
	var rotated: AtlasInkLayer = AtlasSelectionGeometry.transformed(ink, selection,
		AtlasSelectionGeometry.about(box.position, Vector2.ZERO, 1.0, PI / 4.0)) as AtlasInkLayer
	_check(rotated != null and is_equal_approx(rotated.strokes[0].text_rotation, PI / 4.0) and
		rotated.strokes[0].text == label.text and AtlasTextLayout.bounds(rotated.strokes[0]).size.y > box.size.y,
		"rotation preserves text glyph layout, edits and bounds")
	_check(AtlasStroke.from_dict(rotated.strokes[0].to_dict()).text_rotation == rotated.strokes[0].text_rotation,
		"save retains text rotation")
	_check(AtlasStrokeEraser.erase([label], PackedVector2Array([box.get_center()]), 4).is_empty(), "eraser removes whole text")
	_check(AtlasStrokeEraser.erase([label], PackedVector2Array([box.position - Vector2(20, 0),
		box.end + Vector2(20, 0)]), 4).is_empty(), "crossing eraser segment removes whole text")
	_check(AtlasStrokeEraser.erase([label], PackedVector2Array([box.end + Vector2(100, 100)]), 4).size() == 1,
		"eraser miss keeps editable object")
	var allowed: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		box.position - Vector2(10, 10), Vector2(box.end.x + 10, box.position.y - 10),
		box.end + Vector2(10, 10), Vector2(box.position.x - 10, box.end.y + 10)]), true)
	_check(allowed.clip_strokes([label]).size() == 1, "whole text inside mask is preserved")
	var tight: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		origin - Vector2.ONE, origin + Vector2(5, -1), origin + Vector2(5, 5), origin + Vector2(-1, 5)]), true)
	_check(tight.clip_strokes([label]).is_empty(), "partial mask never splits letters")
	_check(tight.erase([label], PackedVector2Array([origin + Vector2(2, 2)]), 4).size() == 1,
		"eraser cannot bypass mask via anchor")

	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = "user://text-smoke-%d/campaign.scn" % Time.get_ticks_usec()
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Text board", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	var canvas: AtlasCanvas = editor.canvas
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.TEXT) != null and canvas.tool == AtlasCanvas.Tool.TEXT, "palette and tool")
	canvas.camera_zoom = 1.0
	canvas.camera_center = origin
	canvas._begin_text_edit(origin)
	_check(editor.text_editor.visible and editor.text_editor.text_input.has_focus(), "open modal on click")
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.pressed = true
	shortcut.keycode = KEY_B
	editor._unhandled_key_input(shortcut)
	_check(canvas.tool == AtlasCanvas.Tool.TEXT, "text editing isolates drawing shortcuts")
	editor.text_editor.text_input.text = "A persistent label"
	editor.text_editor.size_input.value = 19
	editor.text_editor.confirm_text()
	var active: AtlasObjectsLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	_check(active.strokes.size() == 1 and active.strokes[0].text == "A persistent label", "placement creates one object")
	_check(not editor.text_editor.visible, "editor closed after commit")
	_check(editor.edits.undo() and active.strokes.is_empty(), "placement undo")
	_check(editor.edits.redo() and active.strokes.size() == 1, "placement redo")
	canvas._begin_text_edit(origin + Vector2(4, 4))
	_check(editor.text_editor.visible and editor.text_editor.text_input.text == "A persistent label", "click existing text reopens content")
	editor.text_editor.text_input.text = "Revised label"
	editor.text_editor.confirm_text()
	_check(active.strokes.size() == 1 and active.strokes[0].text == "Revised label", "revision changes existing object")
	_check(editor.edits.undo() and active.strokes[0].text == "A persistent label", "revision undo")
	_check(editor.edits.redo() and active.strokes[0].text == "Revised label", "revision redo")
	# The modal never discards typed text when a target or history guard fails.
	canvas._begin_text_edit(origin + Vector2(250, 100))
	editor.text_editor.text_input.text = "  "
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and editor.text_editor.error_label.visible
		and active.strokes.size() == 1, "invalid content preserves the draft and history")
	editor.text_editor.close_editor()
	canvas._begin_text_edit(origin + Vector2(4, 4))
	var external_original: AtlasStroke = active.strokes[0].copy()
	var external_update: AtlasStroke = external_original.copy()
	external_update.text = "A newer revision"
	_check(editor.artwork.edit_text(0, external_original, external_update), "interleaved text change commits")
	editor.text_editor.text_input.text = "Uncommitted draft"
	editor.text_editor.confirm_text()
	_check(active.strokes[0].text == "A newer revision" and editor.text_editor.visible
		and editor.text_editor.error_label.visible and editor.text_editor.text_input.text == "Uncommitted draft",
		"stale revision cannot overwrite later history or lose the draft")
	editor.text_editor.close_editor()
	_check(editor.edits.undo() and active.strokes[0].text == "Revised label",
		"rejected revision created no extra undo command")
	canvas._begin_text_edit(origin + Vector2(250, 100))
	editor.text_editor.text_input.text = "Wrong target"
	var initial_layer_id: String = canvas.active_layer_id
	editor.layer_panel._add_objects()
	var alternate: AtlasObjectsLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	_check(alternate != null and canvas.active_layer_id != initial_layer_id, "layer changed during modal")
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and editor.text_editor.error_label.visible
		and alternate.strokes.is_empty() and active.strokes.size() == 1,
		"pending placement cannot move to a different Objects layer")
	editor.text_editor.close_editor()
	editor.select_layer(initial_layer_id)
	active = canvas.floor.layer_by_id(initial_layer_id) as AtlasObjectsLayer
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	canvas._begin_text_edit(origin + Vector2(250, 100))
	editor.text_editor.text_input.text = "Retry when unlocked"
	active.locked = true
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and editor.text_editor.error_label.visible
		and active.strokes.size() == 1, "locked target rejects placement without closing")
	active.locked = false
	editor.text_editor.confirm_text()
	_check(not editor.text_editor.visible and active.strokes.size() == 2
		and active.strokes[-1].text == "Retry when unlocked", "retry applies preserved text once unlocked")
	_check(editor.edits.undo() and active.strokes.size() == 1, "recovery placement undo")
	var unchanged_cursor: int = editor.edits._cursor
	canvas._begin_text_edit(origin + Vector2(4, 4))
	editor.text_editor.confirm_text()
	_check(not editor.text_editor.visible and editor.edits._cursor == unchanged_cursor,
		"unchanged text closes without making a redundant history command")
	var wrong_floor_text: AtlasStroke = AtlasTextLayout.make(origin + Vector2(260, 100),
		"Wrong floor", "Sans", 18, Color.WHITE)
	_check(not editor.artwork.edit_text_in_context(-1, null, wrong_floor_text,
		canvas.map.id, "another-floor", active.id) and active.strokes.size() == 1,
		"modal submission rejects a different floor even with the same layer id")
	canvas._begin_text_edit(origin + Vector2(4, 4))
	editor.text_editor.close_editor()
	_check(active.strokes[0].text == "Revised label", "cancel never alters artwork")
	editor._on_save()
	var restored: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	_check(restored != null and restored.get_map(canvas.map.id) != null, "native campaign save and reload")
	var native_map: AtlasMapDocument = restored.get_map(canvas.map.id) if restored != null else null
	var native_ink: AtlasObjectsLayer = native_map.floor_by_id(canvas.floor.id).layer_by_id(active.id) as AtlasObjectsLayer if native_map != null else null
	_check(native_ink != null and native_ink.strokes.size() == 1 and native_ink.strokes[0].text == "Revised label", "native save preserves editable content")
	if native_ink != null and not native_ink.strokes.is_empty():
		editor.text_editor.open_editor(native_ink.strokes[0].points[0], native_ink.strokes[0], 0)
		_check(editor.text_editor.text_input.text == "Revised label" and
			editor.text_editor.apply_button.text == "Update text", "saved text reopens as editable text")
		editor.text_editor.close_editor()
	var saved: AtlasMapDocument = AtlasMapDocument.from_dict(canvas.map.to_dict()) if canvas.map.has_method("to_dict") else null
	_check(saved != null and saved.floor_by_id(canvas.floor.id) != null and
		saved.floor_by_id(canvas.floor.id).layer_by_id(active.id) is AtlasObjectsLayer, "map dictionary retains layer")
	var saved_text: AtlasObjectsLayer = saved.floor_by_id(canvas.floor.id).layer_by_id(active.id) as AtlasObjectsLayer if saved != null else null
	_check(saved_text != null and saved_text.strokes[0].text == "Revised label", "dictionary roundtrip retains text")
	# D1 authors another independent label at the same board coordinates.
	editor.layer_panel.view_detail_spinner.value = 1
	editor.layer_panel._add_objects()
	var detail_id: String = canvas.active_layer_id
	var detail: AtlasObjectsLayer = canvas.floor.layer_by_id(detail_id) as AtlasObjectsLayer
	_check(detail != null and detail.detail_level == 1 and canvas.editing_target_is_presented(),
		"D1 has its own editable text destination")
	canvas._begin_text_edit(origin)
	editor.text_editor.text_input.text = "Street name"
	editor.text_editor.confirm_text()
	_check(detail.strokes.size() == 1 and detail.strokes[0].text == "Street name", "D1 text created")
	editor.layer_panel.view_detail_spinner.value = 0
	_check(not canvas.editing_target_is_presented() and detail.strokes[0].text == "Street name", "presentation change retains hidden text")
	editor.select_layer(detail_id)
	_check(canvas.presented_detail_level == 1 and detail.strokes[0].is_text(), "returning to D1 restores text editability")
	_check(AtlasCampaignStore.save_campaign(editor.campaign, editor.save_path) == OK, "D1 save")
	var both: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	var persisted: AtlasObjectsLayer = both.get_map(canvas.map.id).floor_by_id(canvas.floor.id).layer_by_id(detail_id) as AtlasObjectsLayer if both != null else null
	_check(persisted != null and persisted.strokes.size() == 1 and persisted.strokes[0].text == "Street name", "D1 native save preserves text")
	# A map change can reuse an object index: the modal must still bind to its source map.
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	canvas._begin_text_edit(origin + Vector2(280, 160))
	editor.text_editor.text_input.text = "Never place on another board"
	var previous_map_id: String = canvas.map.id
	_check(editor.create_board("Another text board", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
		and canvas.map.id != previous_map_id, "switch boards with text editor open")
	editor.text_editor.confirm_text()
	var other_layer: AtlasObjectsLayer = canvas.floor.objects_layer()
	_check(editor.text_editor.visible and editor.text_editor.error_label.visible
		and (other_layer == null or other_layer.strokes.is_empty()),
		"pending text cannot be placed in another map")
	editor.text_editor.close_editor()
	# Text is modal: an edit mask is captured at opening, not silently
	# re-evaluated against a later selected cell or rotated grid on Apply.
	_check(editor.create_board("Text edit-scope board", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 200)),
		"create grid board for modal scope checks")
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	var scope_cell: Vector2i = Vector2i(0, 0)
	var scope_anchor: Vector2 = canvas.map.grid.cell_to_document(scope_cell) - Vector2(30, 12)
	editor._on_select(scope_cell)
	editor._on_scope_toggled(true)
	var scope_layer: AtlasObjectsLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	var scope_before: Dictionary = scope_layer.to_dict()
	var scope_cursor: int = editor.edits._cursor
	canvas._begin_text_edit(scope_anchor)
	editor.text_editor.text_input.text = "Cell note"
	editor.text_editor.size_input.value = 12
	_check(editor._text_scope_at_open != null and editor._text_scope_at_open.enabled,
		"opening text modal snapshots enabled cell scope")
	editor._on_select(scope_cell + Vector2i(2, 0))
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and editor.text_editor.error_label.visible
		and "edit mask" in editor.text_editor.error_label.text
		and editor.text_editor.text_input.text == "Cell note",
		"changed selected cell rejects modal placement without discarding draft")
	_check(scope_layer.to_dict() == scope_before and editor.edits._cursor == scope_cursor,
		"stale text placement does not change objects or undo history")
	editor._on_select(scope_cell)
	editor.text_editor.confirm_text()
	_check(not editor.text_editor.visible and scope_layer.strokes.size() == 1
		and scope_layer.strokes[0].text == "Cell note" and editor.edits._cursor == scope_cursor + 1,
		"restored original cell mask accepts exactly one placement")
	canvas._begin_text_edit(scope_anchor + Vector2(2, 2))
	editor.text_editor.text_input.text = "Changed style"
	var previous_grid_rotation: float = canvas.map.grid.rotation
	canvas.map.grid.rotation += PI / 6.0
	editor.artwork.refresh_scope()
	var revision_before: Dictionary = scope_layer.to_dict()
	var revision_cursor: int = editor.edits._cursor
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and scope_layer.to_dict() == revision_before
		and editor.edits._cursor == revision_cursor,
		"rotated selected-cell grid rejects stale text revision")
	canvas.map.grid.rotation = previous_grid_rotation
	editor.artwork.refresh_scope()
	editor.text_editor.confirm_text()
	_check(not editor.text_editor.visible and scope_layer.strokes[0].text == "Changed style",
		"restored original grid permits text revision")
	# Disabled masking makes the selected cell immaterial to authorization.
	editor._on_scope_toggled(false)
	var unrestricted_cursor: int = editor.edits._cursor
	canvas._begin_text_edit(scope_anchor + Vector2(2, 2))
	editor.text_editor.text_input.text = "Unmasked revision"
	editor._on_select(scope_cell + Vector2i(3, 0))
	editor.text_editor.confirm_text()
	_check(not editor.text_editor.visible and scope_layer.strokes[0].text == "Unmasked revision"
		and editor.edits._cursor == unrestricted_cursor + 1,
		"selected-cell changes do not reject text while masking is disabled")
	# Replacing an Objects layer with the same ID cannot inherit a modal's grant.
	canvas._begin_text_edit(scope_anchor + Vector2(2, 2))
	editor.text_editor.text_input.text = "Old layer edit"
	var layer_index: int = canvas.floor.layers.find(scope_layer)
	var replacement_layer: AtlasObjectsLayer = AtlasObjectsLayer.new(scope_layer.id, scope_layer.display_name)
	replacement_layer.strokes = AtlasStroke.clone_all(scope_layer.strokes)
	canvas.floor.layers[layer_index] = replacement_layer
	var identity_cursor: int = editor.edits._cursor
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and replacement_layer.strokes[0].text == "Unmasked revision"
		and editor.edits._cursor == identity_cursor,
		"same-id replacement layer cannot receive an old text edit")
	editor.text_editor.close_editor()
	_check(editor._text_scope_at_open == null and editor._text_layer_at_open == null
		and editor._text_map_at_open == null and editor._text_floor_at_open == null,
		"closing rejected modal releases original authorization references")
	canvas.floor.layers[layer_index] = scope_layer
	root.remove_child(scene)
	scene.free()
	print("ATLAS_TEXT_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
