extends SceneTree
## T-009: Search/Open/Focus revalidate detached results before navigating.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SEARCH STALE FAILED: " + message)


func _result(editor: AtlasEditor, query: String = "Greyhaven") -> AtlasOverviewEntry:
	editor.browser.refresh_search(query)
	var entries: Array[AtlasOverviewEntry] = editor.overview_panel.entries
	return entries[0] if entries.size() == 1 else null


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "world"
	campaign.add_map(AtlasMapDocument.new("world", "Northern Marches"))
	campaign.add_map(AtlasMapDocument.new("town", "Greyhaven"))
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = "world-gate"
	link.source_map_id = "world"
	link.target_map_id = "town"
	link.anchor = Vector2(-123.5, 55.25)
	campaign.links.append(link)

	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	editor.campaign = campaign
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var canvas: AtlasCanvas = editor.canvas
	editor.overview_panel.mode_picker.select(AtlasOverview.Filter.MAP)
	var current: AtlasOverviewEntry = _result(editor)
	_check(current != null and current.can_focus and current.caption.contains("Greyhaven"),
		"readable-name lookup returns a locatable result without IDs")
	_check(AtlasOverview.entry_is_current(campaign, current), "fresh link result is authorized for navigation")
	var canonical_before: Dictionary = campaign.to_dict()
	var history_count: int = editor.history.size()

	# Changing an anchor after listing must not focus its obsolete location.
	link.anchor = Vector2(-310.25, -40.5)
	canvas.camera_center = Vector2(1, 2)
	editor.browser._focus_overview_source(current)
	_check(canvas.camera_center == Vector2(1, 2) and canvas.map.id == "world",
		"moved link refuses stale Focus without changing camera or map")
	_check(editor.overview_panel.summary.text.contains("Results changed")
		and editor.overview_panel.result_list.get_selected_items().is_empty(),
		"stale action explains rejection and requires deliberate result reselection")
	_check(editor.overview_panel.get_node("FocusButton").disabled
		and editor.overview_panel.get_node("OpenButton").disabled,
		"stale result disables both navigation actions")
	var fresh: AtlasOverviewEntry = editor.overview_panel.entries[0]
	_check(fresh != current and AtlasOverview.entry_is_current(campaign, fresh),
		"refresh supplies a newly validated result")
	editor.overview_panel.result_list.select(0)
	editor.overview_panel.result_list.item_selected.emit(0)
	(editor.overview_panel.get_node("FocusButton") as Button).pressed.emit()
	_check(canvas.camera_center == link.anchor and canvas.map.id == "world",
		"reselecting an updated row and pressing Focus locates the new anchor")

	# A destination change must never use a previously listed Open action.
	current = _result(editor)
	link.target_floor_id = "missing-floor"
	(editor.overview_panel.get_node("OpenButton") as Button).pressed.emit()
	_check(canvas.map.id == "world" and editor.history.size() == history_count,
		"retargeted link refuses stale Open without history mutation")
	var broken: AtlasOverviewEntry = editor.overview_panel.entries[0]
	_check(not broken.broken_reason.is_empty() and broken.can_focus,
		"current broken target is reported but retains valid source Focus")
	canvas.camera_center = Vector2(0, 0)
	editor.browser._focus_overview_source(broken)
	_check(canvas.camera_center == link.anchor,
		"current broken destination still permits deliberate source Focus")
	link.target_floor_id = "ground"

	# Retired links and edited hit geometry cannot reuse an old result.
	current = _result(editor)
	link.hit_radius += 10.0
	_check(not AtlasOverview.entry_is_current(campaign, current),
		"changing a marker's hit region invalidates its listed result")
	editor.browser._open_overview_entry(current)
	_check(canvas.map.id == "world", "changed marker geometry cannot trigger old Open")
	current = _result(editor)
	campaign.links.erase(link)
	editor.browser._focus_overview_source(current)
	_check(canvas.camera_center == link.anchor and editor.overview_panel.entries.is_empty(),
		"deleted link cannot focus and disappears after refresh")
	campaign.links.append(link)

	# Archived footprints are reported but are never live source locations.
	var footprint: AtlasPlacement = AtlasPlacement.new()
	footprint.id = "old-footprint"
	footprint.parent_map_id = "world"
	footprint.child_map_id = "town"
	footprint.origin = Vector2(-800, 300)
	campaign.placements.append(footprint)
	link.placement_id = footprint.id
	current = _result(editor)
	_check(current != null and not current.can_focus and
		not AtlasOverview.entry_is_current(campaign, current),
		"archived footprint is not an actionable search result")
	footprint.rotation = PI / 4.0
	canvas.camera_center = Vector2.ZERO
	editor.browser._focus_overview_source(current)
	_check(canvas.camera_center == Vector2.ZERO, "rotated footprint invalidates old Focus")
	fresh = editor.overview_panel.entries[0]
	editor.browser._focus_overview_source(fresh)
	_check(canvas.camera_center == Vector2.ZERO and fresh != null and not fresh.can_focus,
		"refresh never converts archived geometry into a focusable source")

	# Replacing a same-ID document must not revive a detached result.
	current = _result(editor)
	campaign.add_map(AtlasMapDocument.new("town", "Greyhaven"))
	_check(not AtlasOverview.entry_is_current(campaign, current),
		"same-ID destination replacement invalidates stale result")
	editor.browser._open_overview_entry(current)
	_check(canvas.map.id == "world", "stale destination replacement cannot open")

	# Replacing a whole campaign with the same serialized IDs is also stale.
	current = _result(editor)
	var replacement: AtlasCampaign = AtlasCampaign.from_dict(campaign.to_dict())
	_check(replacement != null, "replacement fixture preserves valid schema")
	editor.browser.refresh(replacement)
	_check(not AtlasOverview.entry_is_current(replacement, current),
		"campaign replacement rejects old result despite identical IDs and values")
	editor.browser._open_overview_entry(current)
	_check(canvas.map.id == "world", "replaced campaign cannot use old Open event")
	# Continue with an ordinary marker: recursive results must still validate
	# the full navigation path, without relying on a retired placement.
	link.placement_id = ""
	editor.browser.refresh(campaign)
	campaign.add_map(AtlasMapDocument.new("mine", "Deep Mine"))
	var nested: AtlasMapLink = AtlasMapLink.new()
	nested.id = "town-mine"
	nested.source_map_id = "town"
	nested.target_map_id = "mine"
	nested.anchor = Vector2(4, -2)
	campaign.links.append(nested)
	editor.overview_panel.recursive_checkbox.button_pressed = true
	current = _result(editor, "Deep Mine")
	_check(current != null and current.depth == 2 and AtlasOverview.entry_is_current(campaign, current),
		"recursive name lookup includes an unchanged two-link path")
	link.anchor += Vector2(40, 10)
	canvas.camera_center = Vector2(77, -77)
	editor.browser._focus_overview_source(current)
	_check(canvas.camera_center == Vector2(77, -77) and canvas.map.id == "world",
		"moving an ancestor link rejects the stale descendant Focus")
	current = _result(editor)
	campaign.get_map("town").display_name = "Greyhaven Renamed"
	_check(not AtlasOverview.entry_is_current(campaign, current),
		"destination label changes invalidate displayed names before Open")
	editor.browser._open_overview_entry(current)
	_check(canvas.map.id == "world", "old display label cannot navigate without reselection")
	_check(editor.history.size() == history_count, "all rejected actions leave navigation history unchanged")
	_check(campaign.to_dict() != canonical_before and not editor.edits.is_dirty(),
		"Search itself creates no edit commands or saved-state mutations")

	root.remove_child(scene)
	scene.free()
	print("ATLAS_SEARCH_STALE_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
