extends SceneTree
## Workspace controls must expose the required native presets and 96px width.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T182_PRESETS_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	root.add_child(workspace)
	await process_frame
	await process_frame
	var picker: OptionButton = workspace.get("brush_preset_control") as OptionButton
	check(picker != null, "brush preset selector is present in the workspace")
	if picker != null:
		check(picker.item_count == 4, "all four bundled native presets are selectable")
		check(picker.get_item_text(0) == "Hard Round" and workspace.canvas.brush_preset == "hard",
			"default hard-round native preset is named explicitly")
		workspace.width_spin.value = 96
		check(workspace.canvas.brush_width == 96.0, "96px benchmark width is reachable")
		var document: DrawingDocument = workspace.current_document()
		var revision: int = document.revision
		for index: int in range(picker.item_count):
			picker.select(index)
			picker.item_selected.emit(index)
			var preset: String = str(picker.get_item_metadata(index))
			check(workspace.canvas.brush_preset == preset, "picker selects native preset " + preset)
			check(FileAccess.file_exists(workspace.canvas.BUNDLED_PRESETS[preset]),
				"selected preset settings are packaged: " + preset)
		check(document.revision == revision, "choosing presets does not edit document history")
		workspace._change_tool("Eraser")
		check(picker.get_parent() == workspace.top_bar.options_region,
			"same native preset selector is available for Eraser")
		workspace._change_tool("Pan")
		check(picker.get_parent() != workspace.top_bar.options_region,
			"preset control does not crowd unrelated tool options")
		workspace._change_tool("Brush")
		picker.select(0)
		picker.item_selected.emit(0)
		check(picker.get_parent() == workspace.top_bar.options_region and
			workspace.canvas.brush_preset == "hard" and workspace.canvas.brush_width == 96.0,
			"Brush restores a reachable Hard Round / 96px configuration")
	workspace.queue_free()
	await process_frame
	await process_frame
	print("T182_PRESETS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T182_PRESETS_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
