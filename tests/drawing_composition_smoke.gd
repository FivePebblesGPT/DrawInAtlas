extends SceneTree
## T-055: canonical painter and read-only rendering composed into Atlas.
## Exercise live UI event arbitration and independently persisted Object sources.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T055_FAILED: " + label)

func _pixel(doc: DrawingDocument, layer: String, x: int, y: int) -> int:
	var result: DrawingResult = doc.read_pixel(layer, x, y)
	return int(result.value) if result.ok else -1

func _button(position: Vector2, pressed: bool, double_click: bool = false) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = position
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.double_click = double_click
	return e

func _motion(position: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new()
	history.reset(campaign)
	history.active_map_id = "world"
	var adapter: AtlasDrawingComposition = AtlasDrawingComposition.new(history)
	_check(adapter.attach_campaign(campaign).ok, "campaign attached")
	_check(adapter.registry.document_count() == 0, "one canonical registry remains lazy")
	_check(adapter.registry.projection("world")[0]["details"][0]["blank"], "blank floor initially")
	_check(not adapter.finish_stroke().ok, "commit without a gesture is rejected")
	_check(not adapter.append_stroke(Vector2.ZERO).ok, "sample without a gesture is rejected")
	_check(adapter.start_stroke("world", "ground", 0, Vector2(-3.1, 2.0),
		0xff0000ff, 1.5).ok, "Atlas starts canonical raster session")
	_check(adapter.stroke_active(), "a gesture is frozen")
	_check(not adapter.start_stroke("world", "ground", 1, Vector2.ZERO,
		0xff0000ff, 1.0).ok, "another detail cannot hijack live stroke")
	_check(adapter.append_stroke(Vector2(-2.1, 2.0)).ok, "swept path continues through signed coordinates")
	_check(adapter.finish_stroke().ok, "one Atlas history commit")
	_check(not adapter.stroke_active() and history.can_undo(), "gesture closed and globally undoable")
	var doc: DrawingDocument = adapter.registry.document_at("world", "ground", 0).value
	var layer: String = String(doc.list_children()[0])
	_check(_pixel(doc, layer, -4, 2) != 0, "negative map-world pixels authored")
	_check(_pixel(doc, layer, -3, 2) != 0, "one swept path covers intermediate pixels")
	_check(doc.external_history, "one Atlas-owned history, no second local undo")
	var frame: DrawingResult = adapter.render_region("world", "ground", 0, Rect2i(-5, 0, 6, 6))
	_check(frame.ok and (frame.value as Image).get_pixel(1, 2).a > 0.0, "read-only bounded composite contains paint")
	var before_revision: int = doc.revision
	(frame.value as Image).fill(Color.BLACK)
	_check(_pixel(doc, layer, -4, 2) != 0 and doc.revision == before_revision,
		"mutating returned preview cannot modify DrawingDocument")
	_check(adapter.render_region("world", "ground", 0, Rect2i(-5, 0, 6, 6)).value.get_pixel(1, 2).a > 0.0,
		"cached read-only image is detached")
	_check(not adapter.render_region("world", "ground", 0, Rect2i(0, 0, 2000, 2000)).ok,
		"unbounded preview rejected")
	_check(adapter.registry.ensure_detail("world", "ground", 1).ok, "new blank D1 created logically")
	var blank: DrawingResult = adapter.render_region("world", "ground", 1, Rect2i(-5, 0, 6, 6))
	_check(blank.ok and blank.value.get_data().count(0) == 6 * 6 * 4,
		"D1 cannot borrow any D0 artwork")
	_check(adapter.registry.projection("world")[0]["details"][1]["blank"], "blank detail stays unallocated")
	_check(adapter.start_stroke("world", "ground", 1, Vector2(-3.1, 2.0),
		0xffff8800, 1.0).ok and adapter.finish_stroke().ok, "independent D1 painting")
	var doc1: DrawingDocument = adapter.registry.document_at("world", "ground", 1).value
	var layer1: String = doc1.list_children()[0]
	_check(doc1.id != doc.id and _pixel(doc1, layer1, -7, 4) != 0,
		"higher detail has double density but same world origin")
	_check(history.undo(), "global undo reverses last detail")
	_check(_pixel(doc1, layer1, -7, 4) == 0 and _pixel(doc, layer, -4, 2) != 0,
		"undo changes D1 only")
	_check(history.undo() and _pixel(doc, layer, -4, 2) == 0, "second undo returns to D0")
	_check(history.redo() and history.redo(), "both details redo in chronological order")
	_check(_pixel(doc, layer, -4, 2) != 0 and _pixel(doc1, layer1, -7, 4) != 0,
		"replay restores both layers")
	_check(adapter.preview("world", "ground", 0, Rect2(-6, 0, 9, 6), Vector2i(90, 60)).ok,
		"read-only preview with explicit world bounds")
	_check(doc.revision == before_revision + 2, "previews do not increment history/document revision")
	_check(not adapter.preview("world", "ground", 0, Rect2(), Vector2i(90, 60)).ok,
		"invalid preview window fails closed")
	# Atlas's convex board cell edit mask becomes a frozen DrawingSelection.
	var polygon: PackedVector2Array = PackedVector2Array([
		Vector2(-11, -11), Vector2(-6, -11), Vector2(-6, -6), Vector2(-11, -6)])
	_check(adapter.start_stroke("world", "ground", 0, Vector2(-9, -9),
		0xff0000ff, 1.0, false, polygon, true).ok, "bounded map edit mask accepted")
	_check(adapter.append_stroke(Vector2(-3, -9)).ok and adapter.finish_stroke().ok,
		"masked gesture clips an otherwise crossing brush stroke")
	_check(_pixel(doc, layer, -9, -9) != 0 and _pixel(doc, layer, -3, -9) == 0,
		"paint outside the frozen board mask is excluded")
	_check(adapter.start_stroke("world", "ground", 0, Vector2(40, 40),
		0xff0000ff, 2.0, false, PackedVector2Array(), true).ok,
		"enabled but empty board mask is a deny-all selection")
	_check(adapter.finish_stroke().ok and _pixel(doc, layer, 40, 40) == 0,
		"deny-all mask commits no content")
	_check(not adapter._selection_mask(PackedVector2Array([
		Vector2.ZERO, Vector2(4000, 0), Vector2(0, 4000)]), true, 1, 1).ok,
		"unbounded grid mask fails closed")

	# Real Object Asset files and links (no map-background object masquerade).
	var directory: String = OS.get_cache_dir().path_join("t055-assets-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(directory.path_join("Campaign.scn"))
	var source: DrawingDocument = DrawingDocument.new("object-source", 16)
	var object_layer: String = String(source.create_layer(DrawingLayerNode.RASTER, "Spruce tree").value)
	var edit: DrawingEditSession = source.begin_edit(object_layer, source.revision).value
	_check(edit.fill_rect(Rect2i(3, 2, 1, 1), 0xff008800).ok and edit.commit().ok,
		"object source uses Drawing brush/storage semantics")
	var source_id_result: DrawingResult = library.create_asset(source, "Tree")
	var published_instance_id: String = ""
	_check(source_id_result.ok, "source published in independent Objects directory")
	if source_id_result.ok:
		var asset_id: String = String(source_id_result.value)
		adapter.set_library(library)
		var p1: DrawingResult = adapter.place_asset(asset_id, "world", "ground", 0,
			Transform2D(0.0, Vector2(12, 5)))
		var p2: DrawingResult = adapter.place_asset(asset_id, "world", "ground", 0,
			Transform2D(0.0, Vector2(25, 5)))
		if p1.ok:
			published_instance_id = String(p1.value)
		_check(p1.ok and p2.ok, "one source links two independent placements")
		_check(adapter.registry.visible_placements(library, "world", "ground", 0).size() == 2,
			"both linked instances visible on D0")
		_check(adapter.registry.visible_placements(library, "world", "ground", 1).is_empty(),
			"object instance does not leak to D1")
		var composed: DrawingResult = adapter.render_region("world", "ground", 0,
			Rect2i(10, 2, 25, 12))
		_check(composed.ok and (composed.value as Image).get_pixel(5, 5).a > 0.0 and
			(composed.value as Image).get_pixel(18, 5).a > 0.0,
			"linked Object sources rendered at two independent transforms")
		_check(adapter.select_instance("world", "ground", 0, Vector2(15.5, 7.5)).value == p1.value,
			"hit-testing selects first visible placed instance")
		_check(adapter.select_instance("world", "ground", 0, Vector2(28.5, 7.5)).value == p2.value,
			"same asset has distinct selected placement ID")
		_check(String(adapter.select_instance("world", "ground", 1,
			Vector2(15.5, 7.5)).value).is_empty(), "hidden detail cannot select D0 instance")
		var before: int = library.asset_info(asset_id)["revision"]
		var draft: AtlasObjectDraft = library.begin_draft(asset_id).value
		var new_edit: DrawingEditSession = draft.document.begin_edit(draft.document.list_children()[0], draft.document.revision).value
		_check(new_edit.fill_rect(Rect2i(4, 2, 1, 1), 0xff6600ff).ok and new_edit.commit().ok,
			"private source draft changes second local pixel")
		var unsaved: DrawingResult = adapter.render_region("world", "ground", 0, Rect2i(12, 5, 10, 6))
		_check(unsaved.ok and (unsaved.value as Image).get_pixel(4, 2).a == 0.0,
			"unsaved private asset draft does not leak to Atlas")
		_check(library.save_draft(draft).ok and library.asset_info(asset_id)["revision"] == before + 1,
			"Save publishes shared object revision to all placements")
		var published: DrawingResult = adapter.render_region("world", "ground", 0, Rect2i(12, 5, 25, 6))
		_check(published.ok and (published.value as Image).get_pixel(4, 2).a > 0.0 and
			(published.value as Image).get_pixel(17, 2).a > 0.0,
			"asset publish invalidates linked render cache")
		_check(library.authored_bounds(asset_id).ok and library.authored_bounds(asset_id).value.has_area(),
			"assets without explicit frame derive bounded authored tile extent")
		_check(adapter.preview("world", "ground", 0, Rect2(10, 4, 29, 10),
			Vector2i(145, 50)).ok, "asset-aware overview preview is detached")
		var rotated_transform: Transform2D = Transform2D(PI / 4.0, Vector2(1200, -450))
		var rotated: DrawingResult = adapter.place_asset(asset_id, "world", "ground", 0, rotated_transform)
		_check(rotated.ok, "transformed object placement supports rotation and a distant origin")
		var rendered_bounds: Rect2 = adapter.authored_bounds_world("world", "ground", 0)
		_check(rendered_bounds.has_point(rotated_transform * Vector2(3.5, 2.5)),
			"preview bounds include rotated asset-local content in world space")

	# A real Atlas editor uses this same adapter for pointer input and previews.
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(scene)
	for i: int in range(4):
		await process_frame
	_check(editor.drawing_composition != null and editor.canvas.drawing_composition == editor.drawing_composition,
		"Atlas main canvas is wired to the canonical Drawing adapter")
	_check(editor.browser.map_preview.drawing_composition == editor.drawing_composition,
		"map preview resolves same read-only registry")
	_check(editor.layer_panel._drawing_registry == editor.drawing_composition.registry,
		"layer hierarchy projects canonical map/floor/detail groups")
	var canvas: AtlasCanvas = editor.canvas
	canvas.render_grid = false
	canvas.camera_zoom = 2.0
	canvas.camera_center = Vector2(50, 60)
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	canvas.brush_width = 2.0
	var center: Vector2 = canvas.size * 0.5
	var count_before: int = editor.edits._commands.size() if editor.edits.has_method("command_count") else 0
	canvas._gui_input(_button(center, true))
	canvas._gui_input(_button(center + Vector2(12, 0), false))
	var native_doc: DrawingDocument = editor.drawing_composition.registry.document_at(
		canvas.map.id, canvas.floor.id, canvas.presented_detail_level).value
	_check(native_doc != null and not native_doc.list_children().is_empty(),
		"real pointer input creates a canonical Drawing layer")
	if native_doc != null and not native_doc.list_children().is_empty():
		var new_layer: String = native_doc.list_children()[0]
		_check(_pixel(native_doc, new_layer, 50, 60) != 0, "mouse gesture published to engine once")
		_check(editor.edits.can_undo(), "native mouse gesture appended global history")
		editor._on_undo()
		_check(_pixel(native_doc, new_layer, 50, 60) == 0, "native Undo reverts canonical pixels")
		editor._on_redo()
		_check(_pixel(native_doc, new_layer, 50, 60) != 0, "native Redo repaints canonical pixels")
		_check(editor.layer_panel.hierarchy.get_root().get_child_count() > 0,
			"live layer hierarchy refreshes after paint")
		var saved: bool = native_doc.is_dirty()
		_check(saved, "canonical painting reports unsaved content until T-066")
		var caption_before: int = native_doc.revision
		editor.browser.map_preview.request_preview(editor.campaign, canvas.map.id, canvas.floor.id)
		_check(native_doc.revision == caption_before, "preview never edits canonical source")
	# A real placed source opens the shared Drawing Object Editor through the
	# Atlas canvas. A normal single selection click must never open a tab.
	if source_id_result.ok:
		editor.drawing_composition.set_library(library)
		canvas.camera_center = Vector2(15.5, 7.5)
		canvas.choose_tool(AtlasCanvas.Tool.SELECT)
		var asset_click: Vector2 = canvas.size * 0.5
		canvas._gui_input(_button(asset_click, true))
		canvas._gui_input(_button(asset_click, false))
		_check(editor.drawing_composition.selected_instance_id == published_instance_id,
			"single-click selects a placed Object instance by its own ID")
		_check(editor.object_editor_window == null,
			"single-click does not unexpectedly open source editor")
		canvas._gui_input(_button(asset_click, true, true))
		_check(editor.object_editor_window != null and editor.object_editor_window.visible,
			"double-click launches independent Drawing-powered Object Editor")
		if editor.object_editor_window != null:
			_check(editor.object_editor_window.bridge != null and
				String(editor.object_editor_window.bridge.library.instance_info(published_instance_id).get("source_id", "")) == String(source_id_result.value),
				"Object Editor captures the selected source and originating instance")
			canvas._gui_input(_button(asset_click, false))
	# A GUI control may never receive a mouse-up after the pointer enters a
	# dock. An outside motion must complete only the in-bounds ink, and the
	# eventual outside mouse-up must not add a second history entry.
	editor.open_map("world", "ground")
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	var boundary_start: Vector2 = Vector2(24, 24)
	var outside: Vector2 = Vector2(canvas.size.x + 45, 24)
	var outside_world: Vector2 = canvas.local_to_document(outside)
	var revision_before_exit: int = native_doc.revision
	var commands_before_exit: int = editor.edits._commands.size()
	canvas._gui_input(_button(boundary_start, true))
	canvas._gui_input(_motion(outside))
	_check(not canvas.is_editing() and native_doc.revision == revision_before_exit + 1,
		"pointer leaving canvas commits the final valid stroke without hanging")
	_check(_pixel(native_doc, native_doc.list_children()[0], floori(outside_world.x),
		floori(outside_world.y)) == 0, "outside motion cannot paint into editor chrome")
	_check(editor.edits._commands.size() == commands_before_exit + 1,
		"outside gesture records exactly one global history command")
	canvas._gui_input(_button(outside, false))
	_check(editor.edits._commands.size() == commands_before_exit + 1,
		"outside mouse-up cannot duplicate the completed stroke")
	# Simulate a mouse exit without even an out-of-bounds motion callback.
	canvas._gui_input(_button(boundary_start + Vector2(0, 18), true))
	canvas.mouse_exited.emit()
	_check(not canvas.is_editing() and editor.edits._commands.size() == commands_before_exit + 2,
		"mouse-exit commits a pressed stroke when other controls consume release")
	canvas._gui_input(_button(outside, false))
	_check(editor.edits._commands.size() == commands_before_exit + 2,
		"late outside release after mouse-exit remains a no-op")

	# Entrance navigation never overrides painting; stable ID + time + location.
	var world_link: AtlasMapLink = editor.campaign.outgoing_links("world", "ground")[0]
	canvas.camera_center = world_link.anchor
	var click: Vector2 = canvas.size * 0.5
	var hits: Dictionary = {"count": 0}
	canvas.link_candidates_requested.connect(func(_links: Array[AtlasMapLink]) -> void: hits["count"] += 1)
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	canvas._gui_input(_button(click, true, true))
	canvas._gui_input(_button(click, false))
	_check(hits["count"] == 0, "painting over entrance does not navigate")
	canvas.choose_tool(AtlasCanvas.Tool.SELECT)
	canvas._gui_input(_button(click, true, false))
	canvas._gui_input(_button(click, false))
	_check(hits["count"] == 0, "single selection click does not enter map")
	canvas._gui_input(_button(click, true, true))
	_check(hits["count"] == 1, "stable-ID double-click enters through navigation tool")
	canvas._gui_input(_button(click, false))
	canvas._previous_entrance_at = Time.get_ticks_msec() - 1000
	canvas._gui_input(_button(click, true, true))
	_check(hits["count"] == 1, "expired double click is rejected")
	canvas._gui_input(_button(click, false))
	canvas._previous_entrance_id = "missing-link"
	canvas._gui_input(_button(click, true, true))
	_check(hits["count"] == 1, "stale stable entrance ID rejects navigation")
	canvas._gui_input(_button(click, false))
	# PAN mode is also a navigation tool. A single click does not start a link move.
	editor.open_map("world", "ground")
	canvas.camera_center = world_link.anchor
	click = canvas.size * 0.5
	canvas.choose_tool(AtlasCanvas.Tool.PAN)
	canvas._gui_input(_button(click, true))
	_check(canvas._moving_link_id.is_empty() and canvas._panning,
		"Pan never moves an entrance on single click")
	canvas._gui_input(_button(click, false))
	_check(not canvas._panning, "Pan gesture is released")
	canvas._gui_input(_button(click, true, true))
	_check(hits["count"] == 2, "Pan double click on same stable entrance navigates")
	canvas._gui_input(_button(click, false))
	_check(editor.drawing_composition.registry.document_count() >= 1,
		"Atlas app owns live generic Drawing document")
	# A canonical preview must fit its own authored world region, not a
	# legacy map layer around the origin. Keep this adapter detached from the
	# live editor timeline so the check cannot affect user history.
	var far_history: AtlasEditHistory = AtlasEditHistory.new()
	far_history.reset(editor.campaign)
	far_history.active_map_id = "world"
	var far_composition: AtlasDrawingComposition = AtlasDrawingComposition.new(far_history)
	_check(far_composition.attach_campaign(editor.campaign).ok,
		"independent read-only preview registry attaches without Atlas UI")
	var far_position: Vector2 = Vector2(10240.0, -4096.0)
	_check(far_composition.start_stroke("world", "ground", 0, far_position,
		0xff0088ff, 48.0).ok and far_composition.finish_stroke().ok,
		"far-world authored artwork is committed through the same package")
	var far_extent: Rect2 = far_composition.authored_bounds_world("world", "ground", 0)
	_check(far_extent.has_area() and far_extent.has_point(far_position),
		"read-only bounds include distant signed canonical tile positions")
	var far_doc: DrawingDocument = far_composition.registry.document_at("world", "ground", 0).value
	var far_revision: int = far_doc.revision
	editor.browser.map_preview.drawing_composition = far_composition
	editor.browser.map_preview.request_preview(editor.campaign, "world", "ground")
	var preview_texture: Texture2D = editor.browser.map_preview.texture_rect.texture
	_check(preview_texture != null and preview_texture.get_image().get_used_rect().has_area(),
		"map preview shows distant canonical paint rather than cropping at legacy origin")
	_check(far_doc.revision == far_revision,
		"fitting and rendering preview never mutate the authored document")

	scene.queue_free()
	print("T055_COMPOSITION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
