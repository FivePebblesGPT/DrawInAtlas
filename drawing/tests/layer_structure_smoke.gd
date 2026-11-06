extends SceneTree
## T-089: deterministic structural transactions and shared Drawing tree contracts.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T089_MODEL_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func render_pixel(doc: DrawingDocument) -> Color:
	var rendered: DrawingResult = DrawingRenderer.render(doc, Rect2i(-1, 0, 1, 1))
	check(rendered.ok, "bounded composite succeeds")
	return (rendered.value as Image).get_pixel(0, 0) if rendered.ok else Color(-1, -1, -1)


func seed_layer(doc: DrawingDocument, layer: String, rgba: int) -> void:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "begin exact layer color")
	if not opened.ok:
		return
	var edit: DrawingEditSession = opened.value as DrawingEditSession
	check(edit._stage(-1, 0, rgba).ok and edit.commit().ok, "commit signed pixel")


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t089-structure")
	var outer: String = String(doc.create_layer(DrawingLayerNode.GROUP, "Outer", "root", "outer").value)
	var bottom: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Bottom", outer, "bottom").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top", outer, "top").value)
	seed_layer(doc, bottom, 0xff0000ff) # pure red in canonical little-endian RGBA8
	seed_layer(doc, top, 0xff00ff00) # pure green
	check(render_pixel(doc).g > 0.9, "top opaque layer wins")
	var path: String = ProjectSettings.globalize_path("user://t089-structure.drawing")
	check(DrawingFileIO.save(doc, path).ok and not doc.is_dirty(), "clean baseline savepoint")
	var start_history: int = doc.history_length()
	check(start_history == 2, "two seeded raster gestures are local history")
	check(doc.create_layer(DrawingLayerNode.GROUP, "Inner", outer, "inner", 1, true).ok,
		"insert group between siblings as one history step")
	check(doc.list_children(outer) == [bottom, "inner", top] and doc.history_length() == start_history + 1,
		"group index and one-step history")
	check(doc.create_layer(DrawingLayerNode.RASTER, "Inserted", "inner", "inserted", 0, true).ok,
		"insert into selected group")
	check(doc.list_children("inner") == ["inserted"], "new layer parent and position")
	check(doc.reorder(top, "inner", 0, true).ok and doc.list_children("inner") == [top, "inserted"],
		"reparent existing layer preserving ID")
	check(not doc.reorder("inner", top, 0, true).ok, "raster cannot parent a group")
	check(not doc.reorder("inner", "inner", 0, true).ok,
		"self-cycle rejected without revision")
	check(not doc.reorder("inner", "inserted", 0, true).ok,
		"non-group target rejected")
	check(doc.reorder("inner", outer, 0, true).ok and
		doc.list_children(outer) == ["inner", bottom], "no-op? moved group before sibling")
	# Put the nested group back so the tree can be exercised through saves.
	check(doc.reorder("inner", outer, 1, true).ok, "reorder group among siblings")
	check(doc.rename_layer(top, "Renamed", true).ok and
		doc.node_metadata(top)["name"] == "Renamed", "rename recorded")
	check(doc.set_visibility("inner", false, true).ok and
		render_pixel(doc).r > 0.9, "group eye hides nested green, shows red")
	var inaccessible: DrawingResult = doc.begin_edit(top, doc.revision)
	check(not inaccessible.ok and inaccessible.code == "LOCKED", "hidden ancestor denies painting")
	check(not doc.reorder(top, outer, 0, true).ok, "hidden group denies reparent")
	check(doc.set_locked("inner", true, true).ok and
		not doc.begin_edit(top, doc.revision).ok, "group lock propagates")
	check(doc.set_visibility("inner", true, true).ok and
		not doc.begin_edit(top, doc.revision).ok, "lock survives visibility toggle")
	check(doc.set_locked("inner", false, true).ok and doc.begin_edit(top, doc.revision).ok,
		"unlock restores editing")
	check(render_pixel(doc).g > 0.9, "visible descendant composition restored")
	var unchanged: int = doc.revision
	var unchanged_history: int = doc.history_length()
	check(doc.rename_layer(top, "Renamed", true).ok and
		doc.set_visibility("inner", true, true).ok and
		doc.reorder("inner", outer, 1, true).ok and doc.revision == unchanged and
		doc.history_length() == unchanged_history, "no-ops do not dirty/history")
	# Locked destination and ancestor cycles are failure-atomic.
	check(doc.set_locked("inner", true, true).ok, "lock destination")
	var guarded_revision: int = doc.revision
	check(not doc.reorder(bottom, "inner", 1, true).ok and
		doc.revision == guarded_revision, "locked destination denies drag without mutation")
	check(doc.set_locked("inner", false, true).ok, "unlock destination")
	check(doc.set_locked(top, true, true).ok, "lock nested child")
	var blocked_delete_revision: int = doc.revision
	check(not doc.remove_subtree("inner", true).ok and doc.revision == blocked_delete_revision and
		doc.has_node(top), "local delete cannot bypass locked descendant")
	check(doc.set_locked(top, false, true).ok, "unlock nested child for structural delete")
	var removed_revision: int = doc.revision
	check(doc.remove_subtree("inner", true).ok and not doc.has_node(top) and
		not doc.has_node("inserted"), "delete nested group removes subtree atomically")
	check(doc.can_undo() and doc.undo().ok and doc.has_node(top) and
		doc.list_children("inner") == [top, "inserted"] and doc.revision > removed_revision,
		"undo deletion restores IDs/children and monotonic revision")
	check(int(doc.read_pixel(top, -1, 0).value) == 0xff00ff00 and
		render_pixel(doc).g > 0.9, "subtree undo restores byte-exact content/composite")
	check(doc.redo().ok and not doc.has_node(top), "redo deletion removes same IDs")
	check(doc.undo().ok and doc.has_node(top), "second undo works")
	check(DrawingFileIO.save(doc, path).ok and not doc.is_dirty(),
		"structural savepoint clears dirty state")
	var reopened: DrawingResult = DrawingFileIO.open(path)
	check(reopened.ok, "persist/reopen nested tree")
	if reopened.ok:
		var loaded: DrawingDocument = reopened.value as DrawingDocument
		check(loaded.id == doc.id and loaded.list_children("inner") == doc.list_children("inner") and
			loaded.node_metadata(top)["name"] == "Renamed", "stable tree IDs/name/order after reopen")
		check(loaded.node_metadata("inner")["visible"] == true and
			loaded.node_metadata("inner")["locked"] == false and
			render_pixel(loaded).g > 0.9, "state/pixel composition persists")
	# Undo the saved deletion inverse: now dirty even though revision continues increasing.
	check(doc.undo().ok and doc.is_dirty(), "undo after savepoint marks changed state dirty")
	check(doc.redo().ok and not doc.is_dirty(), "redo restores saved structural state")
	# A direct/Atlas caller must still own its chronology and retain untracked API.
	var external: DrawingDocument = DrawingDocument.new("t089-atlas")
	check(external.set_external_history(true).ok and
		external.create_layer(DrawingLayerNode.GROUP, "Host", "root", "host", -1, true).ok and
		external.create_layer(DrawingLayerNode.RASTER, "Host layer", "host", "host_layer", -1, true).ok and
		not external.can_undo(), "Atlas external history remains independently owned")
	check(external.set_visibility("host", false, true).ok and
		not external.begin_edit("host_layer", external.revision).ok,
		"external group visibility still propagates")
	# High-count layer paging and selection should use bounded row count.
	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_persistence_enabled = false
	root.add_child(workspace)
	await process_frame
	var original_layer: String = workspace.current_layer()
	var original_group: String = workspace.current_document().node_metadata(original_layer)["parent"]
	workspace._select_layer_node(original_group, false)
	check(workspace.selected_layer_node() == original_group and workspace.current_layer().is_empty()
		and workspace.canvas.layer_id.is_empty(), "group selection is not a paint target")
	var pre_rev: int = workspace.current_document().revision
	workspace._add_layer()
	var inserted: String = workspace.selected_layer_node()
	check(workspace.current_document().node_metadata(inserted)["parent"] == original_group and
		workspace.current_layer() == inserted and workspace.current_document().revision == pre_rev + 1,
		"+Layer inside group targets new raster and creates one revision")
	workspace._add_group()
	var new_group: String = workspace.selected_layer_node()
	check(workspace.current_document().node_metadata(new_group)["parent"] == original_group and
		workspace.current_layer().is_empty(), "+Group beside selected raster disables painting")
	workspace._undo()
	check(not workspace.current_document().has_node(new_group) and
		workspace.selected_layer_node() == inserted, "structural undo restores selection context")
	workspace._redo()
	check(workspace.selected_layer_node() == new_group and
		workspace.current_layer().is_empty(), "structural redo restores selected group")
	# No-op rename must not steal the preceding event's UI context.
	var old_history_length: int = workspace.current_document().history_length()
	workspace.layer_rename_field.text = workspace.current_document().node_metadata(new_group)["name"]
	workspace._commit_layer_rename()
	check(workspace.current_document().history_length() == old_history_length,
		"unchanged name leaves structural history untouched")
	var edit_result: DrawingResult = workspace.current_document().begin_edit(inserted,
		workspace.current_document().revision)
	check(edit_result.ok, "start detached stroke before row action")
	if edit_result.ok:
		workspace.canvas.session = edit_result.value
		workspace._set_row_visibility(new_group)
		check(workspace.canvas.session == null and
			not workspace.current_document().node_metadata(new_group)["visible"],
			"row visibility cancels active detached stroke before redraw")
		workspace._undo()
		check(workspace.current_document().node_metadata(new_group)["visible"],
			"undo restores eye after cancellation")
	var ws_doc: DrawingDocument = workspace.current_document()
	for index: int in range(205):
		ws_doc.create_layer(DrawingLayerNode.RASTER, "Test %03d" % index, original_group)
	workspace._refresh_layers()
	check(workspace.layers.get_root().get_child_count() <= workspace.ROW_PAGE and
		workspace.layer_page_label.text.contains("/2"), "tree renders at most 200 rows per page")
	workspace.layer_search.text = "Test 204"
	workspace._refresh_layers() # Programmatic assignment does not emit LineEdit.text_changed.
	check(workspace.layers.get_root().get_child_count() == 1 and
		workspace.layers.get_root().get_child(0).get_text(0).contains("Test 204"),
		"filtered deep tree shows only matching row")
	workspace._select_layer_node(new_group, false)
	workspace._add_layer()
	check(workspace.layer_search.text.is_empty() and workspace.selected_layer_node() != new_group,
		"new row is revealed even while filter was active")
	workspace.queue_free()
	await process_frame
	if failures == 0:
		print("T089_MODEL_PASSED: %d checks" % checks)
	else:
		printerr("T089_MODEL_FAILED: %d/%d" % [failures, checks])
	quit(1 if failures != 0 else 0)
