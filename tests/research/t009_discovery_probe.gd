extends SceneTree
## Research witness for T-009, not a regression requirement for the old link model.
## Run with: godot --headless --path . --script res://tests/research/t009_discovery_probe.gd

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T009 DISCOVERY FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame

	var initial_map: AtlasMapDocument = editor.canvas.map
	var initial_floor: AtlasFloor = editor.canvas.floor
	var edit_target: String = editor.canvas.active_layer_id
	var history_count: int = editor.history.size()
	var canonical: Dictionary = editor.campaign.to_dict()
	_check(initial_map.display_name == "Northern Marches", "example opens on the shared world board")

	# Scenario 1: find a named destination with no knowledge of map/link IDs.
	editor.sidebar.select_view(&"Search")
	var search_input: LineEdit = editor.sidebar.get_view_content(&"Search").get_node("SearchInput")
	search_input.text = "greyHAVEN"
	editor.overview_panel.mode_picker.select(AtlasOverview.Filter.MAP)
	editor.browser.refresh_search(search_input.text)
	var entries: Array[AtlasOverviewEntry] = editor.overview_panel.entries
	_check(entries.size() == 1, "name search locates Greyhaven in current-map links")
	if entries.size() == 1:
		var entry: AtlasOverviewEntry = entries[0]
		_check(entry.caption.contains("Greyhaven") and entry.can_focus, "result includes readable name and spatial focus")
		_check(entry.breadcrumb.contains("Northern Marches") and entry.breadcrumb.contains("Greyhaven"), "result provides world context")
		editor.overview_panel.result_list.select(0)
		editor.overview_panel.get_node("FocusButton").pressed.emit()
		await process_frame
		_check(editor.canvas.map == initial_map and editor.canvas.camera_center.is_equal_approx(entry.source_focus),
			"Focus source anchor locates marker without opening another map")
		_check(editor.canvas.floor == initial_floor and editor.canvas.active_layer_id == edit_target,
			"focusing a result leaves editing target and floor unchanged")

	# Scenario 2: campaign-level lookup finds documents but cannot locate an
	# arbitrary point inside continuous artwork without an authored place entity.
	editor.overview_panel.mode_picker.select(AtlasOverview.Filter.CAMPAIGN)
	editor.browser.refresh_search("Greyhaven")
	entries = editor.overview_panel.entries
	_check(entries.size() == 1 and entries[0].caption.contains("Greyhaven"),
		"global result identifies a map by display name")
	_check(entries.size() == 1 and not entries[0].can_focus,
		"global map result lacks a board-space location; documented model gap")

	# Scenario 3: a user cannot find arbitrary named ink/tile regions because
	# the search indexes document metadata and links, not authored board places.
	editor.browser.refresh_search("Southwatch Ruins")
	_check(editor.overview_panel.entries.is_empty(),
		"unindexed place has an empty result, not an invented location")
	_check(editor.campaign.to_dict() == canonical and editor.history.size() == history_count,
		"search and location focus do not modify saved content or map history")

	root.remove_child(scene)
	scene.free()
	print("ATLAS_T009_DISCOVERY_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
