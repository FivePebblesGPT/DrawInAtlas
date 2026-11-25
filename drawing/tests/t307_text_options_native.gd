extends "t304_selection_menu_native.gd"
## Real text authoring panel and detached canvas preview, with exact composition parity.

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T307_NATIVE_FAILED: " + description)

func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("T307_SCREENSHOTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		DisplayServer.screen_get_image(0).save_png(folder.path_join(name + ".png"))

func type_letter(window: Window, code: Key, unicode: int) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.unicode = unicode
		event.pressed = pressed
		window.push_input(event, true)
		await frames(2)

func set_content(app: Control, content: String) -> void:
	app.text_edit.text = content
	app.text_edit.text_changed.emit()

func render_bytes(app: Control, view: Rect2i, preview: bool) -> PackedByteArray:
	var doc: DrawingDocument = app.current_document()
	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc, app.canvas.text_preview if preview else {})
	var rendered: DrawingResult = DrawingRenderer.render(doc, view, 0, 0, 1048576, null, plan)
	check(rendered.ok, "canonical text render succeeds")
	return (rendered.value as Image).get_data() if rendered.ok else PackedByteArray()

func frame_bytes(app: Control, view: Rect2i) -> PackedByteArray:
	var canvas: Control = app.canvas
	var from: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(view.position)))
	var to: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(view.end)))
	var frame: Image = canvas.get_viewport().get_texture().get_image()
	return frame.get_region(Rect2i(from, to - from)).get_data()

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "mandatory native display and tiles")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.position = Vector2i(40, 40)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(12)
	check(app.dock_views.has("text_options"), "Text Options is registered as a real dock panel")
	var text_menu: MenuButton = null
	for menu: MenuButton in app.top_bar._menus:
		if menu.text == "Text":
			text_menu = menu
	check(text_menu != null, "Text menu exists")
	if failures > 0:
		quit(1)
		return
	var popup: PopupMenu = text_menu.get_popup()
	await click(root, text_menu.get_global_rect().get_center())
	check(popup.visible, "real Text menu pointer opens")
	popup.set_focused_item(0)
	await popup_key("Return")
	await frames(10)
	check(app.text_panel.is_visible_in_tree() and not app.text_edit.editable, "menu restores same panel without creating a draft")
	var doc: DrawingDocument = app.current_document()
	var canvas: Control = app.canvas
	canvas.camera = Vector2.ZERO
	canvas.zoom = 2.0
	canvas.show_pixel_grid = false
	canvas.show_grid = false
	canvas.queue_redraw()
	var base: String = app.current_layer()
	var group: String = str(doc.create_layer(DrawingLayerNode.GROUP, "Labels").value)
	var under: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ground", group).value)
	var edit: DrawingEditSession = doc.begin_edit(under, doc.revision).value
	check(edit.fill_rect(Rect2i(-90, -65, 180, 105), 0xfff0e8d8).ok and edit.commit().ok, "ground fixture")
	var over: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Above labels").value)
	edit = doc.begin_edit(over, doc.revision).value
	check(edit.fill_rect(Rect2i(-10, -50, 12, 38), 0x80604020).ok and edit.commit().ok, "overlapping higher layer fixture")
	app._select_layer_node(under, false)
	app._after_edit()
	await frames(8)
	var view: Rect2i = Rect2i(-95, -70, 190, 130)
	var baseline: PackedByteArray = render_bytes(app, view, false)
	var original_frame: PackedByteArray = frame_bytes(app, view)
	var revision: int = doc.revision
	var history: int = doc.history_position()
	var count: int = doc.layer_count()
	await click(root, app.tool_buttons["Text"].get_global_rect().get_center())
	var anchor: Vector2i = Vector2i(-70, -55)
	await click(root, canvas.global_position + canvas.pixel_to_position(Vector2(anchor) + Vector2(0.5, 0.5)))
	await frames(10)
	check(app.text_edit.editable and app.text_edit.has_focus() and app.text_apply.disabled, "canvas click opens focused empty draft")
	await type_letter(root, KEY_H, 72)
	await type_letter(root, KEY_I, 105)
	check(app.text_edit.text == "Hi" and not app.text_apply.disabled, "real typing enables Apply and updates draft")
	check(doc.revision == revision and doc.history_position() == history and doc.layer_count() == count, "typing does not publish")
	check(render_bytes(app, view, false) == baseline, "committed renderer excludes draft")
	check(frame_bytes(app, view) != original_frame, "actual framebuffer displays typed glyphs")
	set_content(app, "Harbor\nEast")
	app.text_size.value = 24
	app.text_color.color = Color8(50, 90, 160, 230)
	app.text_color.color_changed.emit(app.text_color.color)
	var style: PopupMenu = popup.get_item_submenu_node(4) as PopupMenu
	await click(root, text_menu.get_global_rect().get_center())
	check(popup.visible, "text commands available during draft")
	popup.set_focused_item(4)
	await popup_key("Right")
	check(style.visible, "style submenu opens with keyboard")
	await screenshot("text-menu")
	style.set_focused_item(1)
	await popup_key("Return")
	await frames(8)
	check(app.text_font.selected == 1 and style.is_item_checked(1), "menu style and panel synchronized")
	app.text_alignment.select(0)
	app.text_alignment.item_selected.emit(0)
	app.text_angle.value = 0.0
	await frames(10)
	var preview: PackedByteArray = render_bytes(app, view, true)
	var displayed: PackedByteArray = frame_bytes(app, view)
	check(preview != baseline and displayed != original_frame, "styled multiline preview uses canonical compositor")
	await screenshot("text-preview")
	app.text_edit.grab_focus()
	await key(root, KEY_ENTER, true)
	await frames(10)
	check(doc.layer_count() == count + 1 and doc.revision == revision + 1 and doc.history_position() == history + 1, "Ctrl+Enter commits exactly one text history event")
	var id: String = app.current_layer()
	var node: DrawingLayerNode = doc.inspect_node(id)
	check(node != null and node.kind == DrawingLayerNode.TEXT and node.parent_id == group and node.text_element.content == "Harbor\nEast" and node.text_element.position == anchor and node.text_element.font_id == "lato-bold-v1", "semantic text committed to same signed group")
	check(canvas.text_preview.is_empty() and render_bytes(app, view, false) == preview, "preview and committed composite byte-identical including higher raster")
	check(frame_bytes(app, view) == displayed, "actual framebuffer matches preview after commit")
	await screenshot("text-committed")
	app._undo()
	await frames(5)
	check(not doc.has_node(id) and render_bytes(app, view, false) == baseline, "Undo removes first text")
	app._redo()
	await frames(5)
	check(doc.has_node(id) and render_bytes(app, view, false) == preview, "Redo restores original semantic text and pixels")
	app._select_layer_node(id, false)
	app._edit_selected_text()
	await frames(8)
	var before: int = doc.revision
	var old_record: Dictionary = doc.inspect_node(id).text_element.to_record()
	set_content(app, "")
	await frames(6)
	check(app.text_apply.disabled and render_bytes(app, view, true) == baseline and render_bytes(app, view, false) == preview, "empty existing draft hides glyphs only in preview")
	set_content(app, "West 🚀")
	await frames(6)
	check(app.text_notice.tooltip_text.contains("U+1F680") and not app.text_apply.disabled, "unsupported glyph warns but preserves semantic content")
	check(doc.revision == before and doc.inspect_node(id).text_element.to_record() == old_record, "existing draft never mutates committed text")
	app.text_edit.grab_focus()
	await key(root, KEY_ESCAPE)
	await frames(8)
	check(canvas.text_preview.is_empty() and not app.text_edit.editable and render_bytes(app, view, false) == preview and frame_bytes(app, view) == displayed, "Escape restores initial text and framebuffer")
	app._edit_selected_text()
	set_content(app, "Harbor West")
	app.text_font.select(2)
	app.text_font.item_selected.emit(2)
	app.text_alignment.select(1)
	app.text_alignment.item_selected.emit(1)
	app.text_angle.value = 12.5
	await frames(8)
	var changed: PackedByteArray = render_bytes(app, view, true)
	app._save()
	check(doc.revision == before and app.status.text.contains("Apply or cancel"), "Save cannot discard pending draft")
	await click(root, app.text_apply.get_global_rect().get_center())
	await frames(8)
	check(doc.layer_count() == count + 1 and doc.revision == before + 1 and doc.inspect_node(id).text_element.content == "Harbor West", "pointer Apply edits same layer once")
	check(render_bytes(app, view, false) == changed, "edited existing text matches preview")
	app._undo()
	check(doc.inspect_node(id).text_element.to_record() == old_record, "Undo restores all original text properties")
	app._redo()
	check(doc.inspect_node(id).text_element.font_id == "lato-italic-v1" and doc.inspect_node(id).text_element.alignment == "center", "Redo restores style and alignment")
	var path: String = OS.get_cache_dir().path_join("t307-" + DrawingDocument.new_id() + ".drawing")
	var expected: Dictionary = doc.inspect_node(id).text_element.to_record()
	app._save_file(path)
	app._open_file(path)
	var reopened: Dictionary = app.current_document().inspect_node(id).text_element.to_record()
	check(reopened == expected, "Save/Open preserves editable text and exact settings: %s vs %s" % [reopened, expected])
	DirAccess.remove_absolute(path)
	app._select_layer_node(id, false)
	app._edit_selected_text()
	set_content(app, "Pending tab draft")
	app.new_drawing()
	check(canvas.text_preview.is_empty() and not app.text_edit.editable, "tab change clears detached preview")
	var blank_count: int = app.current_document().layer_count()
	var blank_revision: int = app.current_document().revision
	app._confirm_text()
	check(app.current_document().layer_count() == blank_count and app.current_document().revision == blank_revision, "late Apply cannot create a layer in another document")
	# Small and high-DPI: scroll to the real edit controls and apply/cancel.
	root.size = Vector2i(800, 600)
	root.content_scale_factor = 1.5
	await frames(12)
	app._change_tool("Text")
	app._edit_text_at(Vector2i(-10, -15))
	set_content(app, "Map")
	app.text_size.value = 14
	await frames(12)
	app.inspector.ensure_control_visible(app.text_edit)
	await frames(8)
	await screenshot("text-narrow-hidpi")
	check(app.text_panel.is_visible_in_tree() and app.text_edit.editable, "narrow HiDPI draft panel remains available")
	app.inspector.ensure_control_visible(app.text_cancel)
	await frames(8)
	await click(root, app.text_cancel.get_global_rect().get_center())
	await frames(5)
	check(canvas.text_preview.is_empty() and not app.text_edit.editable, "narrow HiDPI Cancel reachable by actual pointer")
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	await frames(10)
	var host_id: String = app.float_group(app.dock_layout.group_of("text_options"))
	await frames(8)
	check(not host_id.is_empty() and app.floating_hosts[host_id].is_ancestor_of(app.text_panel), "same text panel floats with dock ownership")
	app.hide_floating_host(host_id)
	app._show_text_options()
	await frames(8)
	check(app.floating_hosts[host_id].visible and app.text_panel.is_visible_in_tree(), "Text menu restores hidden floating panel")
	await screenshot("text-floating")
	print("T307_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T307_NATIVE_PASSED")
	quit(1 if failures else 0)
