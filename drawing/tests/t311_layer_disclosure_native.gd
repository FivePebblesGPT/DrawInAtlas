extends "t304_selection_menu_native.gd"
## Actual Tree input and view-only hierarchy state, separate from artwork history.

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T311_NATIVE_FAILED: " + description)

func find_row(tree: Tree, id: String) -> TreeItem:
	if tree.get_root() == null:
		return null
	var item: TreeItem = tree.get_root().get_first_child()
	while item != null:
		if item.get_metadata(0) == id:
			return item
		item = item.get_next_in_tree()
	return null

func screenshot(name: String, window: Window = root) -> void:
	var folder: String = OS.get_environment("T311_SCREENSHOTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		window.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func click_fold(app: Control, id: String, window: Window = root) -> void:
	var tree: Tree = app.layers
	var item: TreeItem = find_row(tree, id)
	if item == null:
		check(false, "fold row available: " + id)
		return
	tree.scroll_to_item(item)
	await frames(4)
	var rect: Rect2 = tree.get_item_area_rect(item)
	var depth: int = 0
	var parent: TreeItem = item.get_parent()
	while parent != tree.get_root():
		depth += 1
		parent = parent.get_parent()
	var pos: Vector2 = tree.global_position + Vector2(8 + depth * tree.get_theme_constant("item_margin"), rect.get_center().y)
	await click(window, pos)
	await frames(5)

func click_row(app: Control, id: String, action: int = -1, window: Window = root) -> void:
	var tree: Tree = app.layers
	var item: TreeItem = find_row(tree, id)
	if item == null:
		check(false, "row available: " + id)
		return
	tree.scroll_to_item(item)
	await frames(4)
	var rect: Rect2 = tree.get_item_area_rect(item, 0, action)
	var pos: Vector2 = tree.global_position + rect.get_center()
	if action == -1:
		pos.x = tree.global_position.x + rect.size.x * 0.45
	await click(window, pos)
	await frames(5)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "native display and tile extension required")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.record_selection_history = true
	root.add_child(app)
	await frames(8)
	app.dock_layout.move_group("layers", "right", 0)
	app._render_dock()
	await frames(8)
	var doc: DrawingDocument = app.current_document()
	var child: String = app.current_layer()
	var group: String = doc.node_metadata(child)["parent"]
	var row: TreeItem = find_row(app.layers, child)
	check(row != null and row.get_parent() == find_row(app.layers, group), "actual group parent, not flat labels")
	var parent: TreeItem = find_row(app.layers, group)
	check(parent != null and parent.get_first_child() != null, "group has a real disclosure target")
	if failures:
		quit(1)
		return
	var edit: DrawingEditSession = doc.begin_edit(child, doc.revision).value
	check(edit.fill_rect(Rect2i(-4, -3, 8, 6), 0xffd07040).ok and edit.commit().ok, "seed exact signed RGBA8")
	doc.rename_layer(group, "Terrain")
	doc.rename_layer(child, "Base paint")
	app._select_layer_node(group, false)
	app._add_group()
	var inner: String = app.selected_layer_node()
	doc.rename_layer(inner, "Details")
	app._add_layer()
	var leaf: String = app.current_layer()
	doc.rename_layer(leaf, "Road markers")
	app._after_edit()
	await frames(7)
	check(find_row(app.layers, leaf).get_parent() == find_row(app.layers, inner) and find_row(app.layers, inner).get_parent() == find_row(app.layers, group), "nested actual group hierarchy")
	check(find_row(app.layers, inner).get_text(0) == "Details", "group label is name without whitespace or marker")
	check(find_row(app.layers, child).get_button_count(0) == 2, "separate eye and lock actions remain")
	var path: String = OS.get_cache_dir().path_join("t311-" + DrawingDocument.new_id() + ".drawing")
	app._save_file(path)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var rev: int = doc.revision
	var hist: int = doc.history_length()
	var cursor: int = doc.history_position()
	var dirty: bool = doc.is_dirty()
	check(not dirty and doc.record_selection_history, "clean baseline with optional selection history enabled")
	await screenshot("layers-expanded")
	var old_eye: Vector2 = app.layers.global_position + app.layers.get_item_area_rect(find_row(app.layers, leaf), 0, 0).get_center()
	await click_fold(app, inner)
	check(find_row(app.layers, inner).collapsed, "pointer collapses nested actual group arrow")
	check(find_row(app.layers, leaf) == null, "collapsed descendant not instantiated")
	check(app.selected_layer_node() == inner and app.current_layer().is_empty(), "collapse relocates hidden selected child to nonpaintable group")
	check(doc.revision == rev and doc.history_length() == hist and doc.history_position() == cursor and doc.is_dirty() == dirty, "collapse does not change document or history")
	await click(root, old_eye)
	check(doc.revision == rev and doc.node_metadata(leaf)["visible"], "click at old descendant eye no longer intercepts input")
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(2.5, 2.5)))
	app.canvas.finish_gesture(app.canvas.pixel_to_position(Vector2(2.5, 2.5)))
	check(doc.revision == rev and not app.canvas.has_pending_stroke(), "collapsed selection cannot paint into an invisible old layer")
	await screenshot("layers-nested-collapsed")
	await click_fold(app, group)
	check(find_row(app.layers, group).collapsed and find_row(app.layers, child) == null and find_row(app.layers, inner) == null, "outer collapse removes nested input targets")
	await screenshot("layers-collapsed")
	await click_fold(app, group)
	check(not find_row(app.layers, group).collapsed and find_row(app.layers, child) != null, "pointer reopens outer group")
	check(find_row(app.layers, inner).collapsed and find_row(app.layers, leaf) == null, "nested collapse survives ancestor reopen")
	app.layers.grab_focus()
	await key(root, KEY_LEFT)
	check(find_row(app.layers, group).collapsed, "keyboard collapses focused group")
	await key(root, KEY_RIGHT)
	check(find_row(app.layers, inner) != null and find_row(app.layers, inner).collapsed, "keyboard expands focused group without resetting children")
	check(doc.history_length() == hist and doc.history_position() == cursor, "keyboard disclosure is not selection history")
	# Filter traverses collapsed groups but only shows matches and their ancestors.
	app.layer_search.text = "Road markers"
	app.layer_search.text_changed.emit(app.layer_search.text)
	await frames(5)
	check(find_row(app.layers, leaf) != null and find_row(app.layers, child) == null and not find_row(app.layers, inner).collapsed, "filter exposes hidden match with ancestor context only")
	check(app.layer_page_label.text.ends_with("· 1"), "ancestor context not counted as search matches")
	await screenshot("layers-filtered")
	app.layers.grab_focus()
	await key(root, KEY_LEFT)
	check(find_row(app.layers, leaf) != null, "filter keyboard cannot hide a matching descendant")
	app.layer_search.text = ""
	app.layer_search.text_changed.emit("")
	await frames(5)
	check(find_row(app.layers, inner).collapsed and find_row(app.layers, leaf) == null, "clearing filter restores unmodified disclosure")
	app.layer_search.text = "Road markers"
	app.layer_search.text_changed.emit(app.layer_search.text)
	await frames(5)
	await click_row(app, leaf)
	app.layer_search.text = ""
	app.layer_search.text_changed.emit("")
	await frames(5)
	check(find_row(app.layers, leaf) != null and not find_row(app.layers, inner).collapsed, "selecting a search match reveals its ancestor on clear")
	check(app.current_layer() == leaf and app.canvas.layer_id == leaf, "ordinary row click selects paintable layer")
	var pending: DrawingEditSession = doc.begin_edit(leaf, doc.revision).value
	# Isolate the detached session from the unrelated Brush drain scheduler.
	app.canvas.set_process(false)
	app.canvas.session = pending
	await click_fold(app, inner)
	check(not find_row(app.layers, inner).collapsed and app.current_layer() == leaf and app.canvas.session == pending, "collapse cannot retarget detached pending Brush")
	app.canvas.cancel_gesture()
	app.canvas.set_process(true)
	await click_fold(app, inner)
	check(find_row(app.layers, inner).collapsed, "collapse resumes after explicit cancel")
	var before_eye: int = doc.history_length()
	await click_row(app, inner, 0)
	check(not doc.node_metadata(inner)["visible"] and app.current_layer().is_empty() and find_row(app.layers, inner).collapsed, "group eye distinct from folding or painting")
	await click_row(app, inner, 0)
	check(doc.node_metadata(inner)["visible"] and doc.history_length() == before_eye + 2, "eye updates artwork history exactly once per click")
	await click_row(app, inner, 1)
	check(doc.node_metadata(inner)["locked"] and not doc.begin_edit(leaf, doc.revision).ok, "group lock independent of fold state")
	app._undo()
	check(not doc.node_metadata(inner)["locked"] and find_row(app.layers, inner).collapsed, "Undo of lock retains view collapse")
	app._redo()
	check(doc.node_metadata(inner)["locked"] and find_row(app.layers, inner).collapsed, "Redo of lock retains view collapse")
	app._undo()
	check(FileAccess.get_file_as_bytes(path) == before and int(doc.read_pixel(child, -4, -3).value) == 0xffd07040, "view and structural actions preserve saved source bytes and pixels")
	# Retain per-tab disclosure across dock rebuild, switch and explicit save/open.
	app._render_dock()
	await frames(5)
	check(find_row(app.layers, inner).collapsed, "dock re-render retains per-tab collapse")
	app.new_drawing()
	await frames(5)
	check(app.current_document() != doc and app._collapsed_layer_groups().is_empty(), "new tab starts expanded independently")
	app._activate(0)
	await frames(5)
	check(app.current_document() == doc and find_row(app.layers, inner).collapsed, "switch back restores original collapse")
	app._open_file(path)
	await frames(5)
	check(app.current_document() != doc and find_row(app.layers, inner) != null and not find_row(app.layers, inner).collapsed, "fresh file open starts expanded without modifying artwork format")
	app._activate(0)
	await frames(5)
	# New child under selected collapsed group is deliberately revealed.
	app._select_layer_node(inner, false)
	app._add_layer()
	var fresh: String = app.current_layer()
	check(find_row(app.layers, fresh) != null and not find_row(app.layers, inner).collapsed, "new child expands ancestor and reveals itself")
	app._outdent_selected_layer()
	check(find_row(app.layers, fresh).get_parent() == find_row(app.layers, group), "outdent changes actual Tree parent")
	app._undo()
	check(find_row(app.layers, fresh).get_parent() == find_row(app.layers, inner), "Undo restores actual Tree parent")
	app._redo()
	check(find_row(app.layers, fresh).get_parent() == find_row(app.layers, group), "Redo restores reordered parent")
	# Narrow and scaled views retain functional pointer targets.
	root.size = Vector2i(800, 600)
	await frames(10)
	await screenshot("layers-narrow")
	await click_fold(app, inner)
	check(find_row(app.layers, inner).collapsed, "narrow pointer fold reachable")
	root.content_scale_factor = 1.5
	await frames(10)
	await screenshot("layers-hidpi")
	await click_fold(app, inner)
	check(not find_row(app.layers, inner).collapsed, "HiDPI pointer fold reachable")
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	await frames(8)
	# Page boundary: ancestor context may be present on a later page, with
	# no mutation and no hidden descendant counted when the group is folded.
	app._select_layer_node(group, false)
	for i: int in range(205):
		doc.create_layer(DrawingLayerNode.RASTER, "Paged %03d" % i, inner)
	app._refresh_layers()
	check(app.layer_page_label.text.begins_with("1/2") and app._layer_items.size() == app.ROW_PAGE, "first page remains bounded by matching rows")
	app._change_layer_page(1)
	await frames(5)
	check(app.layer_page_label.text.begins_with("2/2") and find_row(app.layers, inner) != null and find_row(app.layers, group) != null, "later page includes real ancestor context")
	await screenshot("layers-page")
	await click_fold(app, inner)
	check(app.layer_page == 0 and find_row(app.layers, inner).collapsed and not app.layer_page_label.text.contains("/2"), "folding page context shrinks page count and focuses group")
	await click_fold(app, inner)
	check(not find_row(app.layers, inner).collapsed and app.layer_page_label.text.begins_with("1/2"), "reopen after page shrink restores pagination")
	DirAccess.remove_absolute(path)
	app.queue_free()
	await frames(4)
	if failures == 0:
		print("T311_NATIVE_PASSED: %d checks" % checks)
	else:
		printerr("T311_NATIVE_FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
