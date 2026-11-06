extends SceneTree
## T-015 native regression: links are marker-only; no registered parent/child
## board compositing survives the retired spatial placement feature.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MARKER REFERENCES UI FAILED: " + message)


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "world"
	var world: AtlasMapDocument = AtlasMapDocument.new("world", "World")
	var city: AtlasMapDocument = AtlasMapDocument.new("city", "City")
	campaign.add_map(world)
	campaign.add_map(city)
	var entrance: AtlasMapLink = AtlasMapLink.new()
	entrance.id = "world-city"
	entrance.source_map_id = world.id
	entrance.target_map_id = city.id
	entrance.anchor = Vector2(-32.5, 25.25)
	entrance.target_focus = Vector2(100, -90)
	entrance.target_zoom = 2.5
	campaign.links.append(entrance)

	var old: AtlasPlacement = AtlasPlacement.new()
	old.id = "old-footprint"
	old.parent_map_id = world.id
	old.child_map_id = city.id
	old.origin = Vector2(100, 100)
	campaign.placements.append(old)
	var retired_link: AtlasMapLink = AtlasMapLink.from_dict(entrance.to_dict())
	retired_link.id = "old-link"
	retired_link.placement_id = old.id
	campaign.links.append(retired_link)
	var before: Dictionary = campaign.to_dict()
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.campaign = campaign
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	root.add_child(scene)
	for i: int in range(6):
		await process_frame
	_check(editor.canvas.map == world, "editor opens independent root document")
	_check(editor.map_references != null, "reference context component remains connected")
	_check(editor.map_references.get_child_count() == 0, "no hidden child-board capture viewport exists")
	_check(editor.inspector.preview_picker.item_count == 2,
		"UI offers only Off and Markers, never aligned overlay choices")
	_check(editor.inspector.preview_picker.get_item_text(0) == "Off" and
		editor.inspector.preview_picker.get_item_text(1) == "Markers",
		"remaining preview modes explain marker semantics")
	_check(not editor.inspector.reference_checkbox.visible and
		not editor.inspector.opacity_slider.visible,
		"obsolete parent reference opacity and toggle controls are hidden")
	_check(not editor.inspector.freeze_checkbox.visible and
		not editor.inspector.reference_source_picker.visible,
		"obsolete parent source and freeze controls are hidden")
	_check(editor.canvas.campaign.find_links_at(world.id, entrance.anchor).size() == 1,
		"marker is still the only hit target, despite archived placement")
	editor.map_references.select_source(retired_link.id)
	editor.map_references.set_frozen(true)
	editor.map_references.refresh()
	_check(editor.map_references.omitted_count == 0 and
		editor.map_references.get_child_count() == 0,
		"retired reference cannot trigger hidden capture or preview overflow")
	_check(campaign.to_dict() == before and not editor.edits.is_dirty(),
		"reference selection and freeze state do not edit campaign")
	_check(not editor.navigator.enter_link(retired_link),
		"legacy entrance cannot navigate by its old footprint")
	_check(editor.canvas.map == world and editor.navigator.history.is_empty(),
		"refused legacy navigation preserves the view and Back stack")
	_check(editor.navigator.enter_link(entrance), "ordinary marker entrance still navigates")
	_check(editor.canvas.map == city and
		editor.canvas.camera_center == entrance.target_focus and
		is_equal_approx(editor.canvas.camera_zoom, entrance.target_zoom),
		"marker navigation preserves exact arrival focus and zoom")
	_check(editor.navigator.history.size() == 1, "successful independent navigation adds Back state")
	editor.navigator.back()
	_check(editor.canvas.map == world, "Back returns to independent source document")
	_check(campaign.to_dict() == before, "navigation never mutates or converts the archive")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_REFERENCES_UI_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
