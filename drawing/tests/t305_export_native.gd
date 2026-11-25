extends "t304_selection_menu_native.gd"
## Real native menu, options, FileDialog confirmation and read-only export workflow.

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T305_NATIVE_FAILED: " + label)

func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("T305_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var image: Image = DisplayServer.screen_get_image(0)
	if image != null and image.save_png(folder.path_join(name + ".png")) != OK:
		printerr("OPTIONAL_VISUAL_CAPTURE_FAILED: " + name)

func click_control(window: Window, control: Control) -> void:
	await click(window, control.get_global_rect().get_center())

func open_export(app: Control, window: Window) -> void:
	var file: PopupMenu = app.top_bar._menus[0].get_popup()
	await click_control(window, app.top_bar._menus[0])
	check(file.visible, "pointer opens File menu")
	if file.visible:
		file.set_focused_item(5)
		await popup_key("Return")
	await frames()
	check(app.export_dialog.visible, "File Export opens independent options dialog")

func set_format(dialog: DrawingExportDialog, index: int) -> void:
	await click_control(dialog, dialog.format_option)
	var menu: PopupMenu = dialog.format_option.get_popup()
	check(menu.visible, "pointer opens native format chooser")
	if menu.visible:
		menu.set_focused_item(index)
		await popup_key("Return")
	await frames()
	check(dialog.format_option.selected == index, "native format chooser applies selected codec")

func choose_path(app: Control, folder: String, name: String) -> void:
	var dialog: DrawingExportDialog = app.export_dialog
	await click_control(dialog, dialog.get_ok_button())
	await frames()
	check(app.export_file_dialog.visible and not dialog.visible, "Choose file opens separate save-mode raster chooser")
	app.export_file_dialog.current_dir = folder
	app.export_file_dialog.current_file = name
	await frames()

func overwrite_dialog(file: FileDialog) -> ConfirmationDialog:
	for node: Node in file.find_children("*", "ConfirmationDialog", true, false):
		if node is ConfirmationDialog and node.visible:
			return node as ConfirmationDialog
	# Engine-owned subwindows are internal children and aren't in find_children.
	for node: Node in file.get_children(true):
		if node is ConfirmationDialog and node.visible:
			return node as ConfirmationDialog
	return null

func fill(doc: DrawingDocument, layer: String, area: Rect2i, rgba: int) -> void:
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(edit.fill_rect(area, rgba).ok and edit.commit().ok, "fixture edit committed")

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "native display and tiles required")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.position = Vector2i(40, 40)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(10)
	var file: PopupMenu = app.top_bar._menus[0].get_popup()
	check(file.item_count == 6 and file.get_item_text(5) == "Export…", "File offers separate raster Export")
	var folder: String = OS.get_cache_dir().path_join("t305-native-" + DrawingDocument.new_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var bounds: Rect2i = Rect2i(-32, -24, 64, 48)
	app.canvas.image_bounds = bounds
	app.tabs[app.active_tab]["frame"] = bounds
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	fill(doc, layer, Rect2i(-20, -12, 28, 24), 0xff3366ee)
	var native: String = folder.path_join("source.drawing")
	app._save_file(native)
	check(FileAccess.file_exists(native) and not doc.is_dirty(), "native Save fixture established")
	var digest: String = FileAccess.get_sha256(native)
	var top: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Overlay").value)
	fill(doc, top, Rect2i(-8, -8, 24, 16), 0x8000dd66)
	fill(doc, top, Rect2i(-30, -22, 2, 2), 0xff2211ff)
	check(doc.undo().ok, "leave a redo entry to protect")
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var position: int = doc.history_position()
	var published: int = doc.published_revision
	var dirty: bool = doc.is_dirty()
	await open_export(app, root)
	var dialog: DrawingExportDialog = app.export_dialog
	if not dialog.visible:
		quit(1)
		return
	check(dialog.source.get_size() == bounds.size and dialog.dimensions.text.contains("(-32, -24)"), "finite signed image frame displayed and rendered")
	check(not dialog.quality_row.visible and not dialog.matte_row.visible and not dialog.lossless_option.visible, "PNG shows no fictitious options")
	dialog.refresh_preview()
	var png_bytes: PackedByteArray = dialog.encoded
	check(not png_bytes.is_empty() and dialog.feedback.text.contains(str(png_bytes.size())), "encoded preview shows actual size")
	await frames()
	await screenshot("export-png")
	await choose_path(app, folder, "result.png")
	if not app.export_file_dialog.visible:
		quit(1)
		return
	await screenshot("export-file")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_ok_button())
	await frames(10)
	var png: String = folder.path_join("result.png")
	check(FileAccess.file_exists(png) and FileAccess.get_file_as_bytes(png) == png_bytes, "real chooser writes exact previewed bytes")
	check(not app.export_file_dialog.visible and app._export_target.is_empty(), "success consumes snapshot and closes chooser")
	check(doc.revision == revision and doc.history_length() == history and doc.history_position() == position and doc.published_revision == published and doc.is_dirty() == dirty and app.tabs[app.active_tab]["path"] == native and FileAccess.get_sha256(native) == digest, "Export preserves identity, native bytes, dirty state and redo cursor")
	# Options change invalidates the cached bytes; applicable settings only.
	await open_export(app, root)
	await set_format(dialog, 1)
	check(dialog.lossless_option.visible and dialog.lossless_option.button_pressed and not dialog.quality_row.visible and not dialog.matte_row.visible, "lossless WebP has no quality or matte option")
	await click_control(dialog, dialog.lossless_option)
	check(not dialog.lossless_option.button_pressed and dialog.quality_row.visible, "pointer toggles WebP lossy quality")
	dialog.quality_option.value = 65
	dialog.refresh_preview()
	var webp_bytes: PackedByteArray = dialog.encoded
	check(not webp_bytes.is_empty(), "lossy WebP preview encodes")
	await frames()
	await screenshot("export-webp")
	dialog.quality_option.value = 80
	check(dialog.encoded.is_empty(), "changed quality invalidates encoded preview")
	await choose_path(app, folder, "result.webp")
	var webp_path: String = folder.path_join("result.webp")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_ok_button())
	check(FileAccess.file_exists(webp_path) and DrawingRasterImport.load_file_image(webp_path).ok and FileAccess.get_file_as_bytes(webp_path) != webp_bytes, "WebP exports re-encoded changed quality to correct file")
	await open_export(app, root)
	await set_format(dialog, 2)
	check(dialog.quality_row.visible and dialog.matte_row.visible and not dialog.lossless_option.visible and not dialog.matte_option.edit_alpha, "JPEG exposes only quality and opaque matte")
	dialog.matte_option.color = Color(0.25, 0.55, 0.75)
	dialog.matte_option.color_changed.emit(dialog.matte_option.color)
	dialog.refresh_preview()
	var jpeg_bytes: PackedByteArray = dialog.encoded
	check(not jpeg_bytes.is_empty(), "JPEG options encode preview")
	await frames()
	await screenshot("export-jpeg")
	await choose_path(app, folder, "result.jpeg")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_ok_button())
	var jpeg_path: String = folder.path_join("result.jpeg")
	check(FileAccess.file_exists(jpeg_path) and FileAccess.get_file_as_bytes(jpeg_path) == jpeg_bytes and DrawingRasterImport.load_file_image(jpeg_path).ok, "real JPEG chooser exports exact preview with .jpeg suffix")
	await open_export(app, root)
	await choose_path(app, folder, "cancel.jpg")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_cancel_button())
	check(not FileAccess.file_exists(folder.path_join("cancel.jpg")) and app._export_target.is_empty() and app._export_bytes.is_empty(), "chooser Cancel discards cached output without file")
	# Existing destination must require actual confirmation. Cancel keeps bytes;
	# approve replaces only the raster export, not the native document.
	await open_export(app, root)
	await set_format(dialog, 0)
	await choose_path(app, folder, "result.png")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_ok_button())
	await frames(8)
	var confirmation: ConfirmationDialog = overwrite_dialog(app.export_file_dialog)
	check(confirmation != null, "existing file requires overwrite confirmation")
	if confirmation != null:
		await screenshot("export-overwrite")
		await click_control(confirmation, confirmation.get_cancel_button())
		check(FileAccess.get_file_as_bytes(png) == png_bytes and app.export_file_dialog.visible, "overwrite Cancel retains original and chooser")
		await click_control(app.export_file_dialog, app.export_file_dialog.get_ok_button())
		await frames(8)
		confirmation = overwrite_dialog(app.export_file_dialog)
		check(confirmation != null, "overwrite can be requested again")
		if confirmation != null:
			await click_control(confirmation, confirmation.get_ok_button())
			check(FileAccess.get_file_as_bytes(png) == png_bytes and not app.export_file_dialog.visible, "overwrite confirmation commits only raster bytes")
	app._cancel_export()
	# Stale snapshot after a native edit/frame/tab switch cannot publish.
	await open_export(app, root)
	await choose_path(app, folder, "stale.png")
	fill(doc, top, Rect2i(0, 0, 1, 1), 0xffaaaaaa)
	app.export_file_dialog.file_selected.emit(folder.path_join("stale.png"))
	check(not FileAccess.file_exists(folder.path_join("stale.png")) and app._export_target.is_empty(), "revision changed after chooser opened; reject stale bytes")
	await open_export(app, root)
	await choose_path(app, folder, "other.png")
	app.new_drawing()
	app.export_file_dialog.file_selected.emit(folder.path_join("other.png"))
	check(not FileAccess.file_exists(folder.path_join("other.png")), "tab changed after chooser opened; reject stale target")
	app._activate(0)
	app.canvas.image_bounds = Rect2i(0, 0, 4096, 4096)
	app._ask_export()
	check(not dialog.visible and app.status.text.contains("4,194,304"), "oversize frame rejected before showing dialog")
	app.canvas.image_bounds = bounds
	var pending: DrawingEditSession = doc.begin_edit(top, doc.revision).value
	var pending_revision: int = doc.revision
	app._ask_export()
	check(not dialog.visible and doc.revision == pending_revision and not pending._closed, "pending edit rejected without cancellation or commit")
	pending.cancel()
	# A held canvas gesture and a floating Move must not be auto-published.
	app._change_tool("Brush")
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(-5.5, -5.5)))
	check(app.canvas.has_pending_stroke(), "held Brush fixture is pending")
	app._ask_export()
	check(not dialog.visible and app.canvas.has_pending_stroke() and doc.revision == pending_revision, "Export leaves held Brush unpublished")
	app.canvas.cancel_gesture()
	app.canvas.set_selection_mask(DrawingSelection.new(Rect2i(-10, -10, 4, 4), true))
	app._change_tool("Move")
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(-8.5, -8.5)))
	app.canvas.finish_gesture(app.canvas.pixel_to_position(Vector2(-6.5, -8.5)))
	check(app.canvas.has_floating_move(), "floating Move fixture created")
	app._ask_export()
	check(not dialog.visible and app.canvas.has_floating_move() and doc.revision == pending_revision, "Export leaves floating Move uncommitted")
	app.canvas.cancel_gesture()
	# Real narrow, high-scale dialog remains usable with the actual options.
	root.size = Vector2i(800, 600)
	root.content_scale_factor = 1.5
	await frames(12)
	await open_export(app, root)
	await set_format(dialog, 2)
	await frames()
	await screenshot("export-narrow-hidpi")
	await choose_path(app, folder, "narrow.jpg")
	await screenshot("export-narrow-file")
	await click_control(app.export_file_dialog, app.export_file_dialog.get_cancel_button())
	check(not app.export_file_dialog.visible and not FileAccess.file_exists(folder.path_join("narrow.jpg")), "narrow chooser Cancel remains reachable")
	await open_export(app, root)
	await click_control(dialog, dialog.get_cancel_button())
	check(not dialog.visible and app._export_target.is_empty() and dialog.source == null, "options Cancel releases snapshot in narrow window")
	check(FileAccess.get_sha256(native) == digest, "all exports and rejected paths leave native source bytes unchanged")
	for filename: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)
	print("T305_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T305_NATIVE_PASSED")
	root.remove_child(app)
	app.free()
	quit(1 if failures else 0)
