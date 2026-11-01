extends SceneTree
## T-042 fog: ordered board-space operations, history, mask and native persistence.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FOG FAILED: " + label)


func _run() -> void:
	_model_checks()
	_history_checks()
	_projection_checks()
	await _editor_checks()
	print("ATLAS_FOG_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _model_checks() -> void:
	var floor: AtlasFloor = AtlasFloor.new()
	_check(floor.fog_allows(Vector2(-1, 0)), "old floor defaults to fog disabled")
	_check(not floor.to_dict().has("fog_enabled") and not floor.to_dict().has("fog_regions"),
		"disabled default keeps pre-fog canonical native-save digest")
	floor.fog_enabled = true
	_check(not floor.fog_allows(Vector2(-1, 0)), "enabled fog defaults to hidden everywhere")
	var reveal: AtlasFogRegion = AtlasFogRegion.new(Rect2(-20, -10, 50, 30), true)
	floor.fog_regions.append(reveal)
	_check(floor.fog_allows(Vector2(-5, -2)) and not floor.fog_allows(Vector2(31, 0)),
		"signed continuous board coordinates and outside deny")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-2, -2, 8, 8), false))
	_check(not floor.fog_allows(Vector2(0, 0)) and floor.fog_allows(Vector2(-4, 0)),
		"later hide overrides earlier reveal")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 2, 2), true))
	_check(floor.fog_allows(Vector2(1, 1)) and not floor.fog_allows(Vector2(3, 1)),
		"later reveal reopens only its own area")
	_check(not floor.fog_allows(Vector2.INF), "nonfinite query never reveals")
	var decoded: AtlasFloor = AtlasFloor.from_dict(floor.to_dict())
	_check(decoded != null and decoded.fog_enabled and decoded.fog_regions.size() == 3 \
		and AtlasFloor.same_fog(floor.fog_regions, decoded.fog_regions),
		"fog dictionary roundtrip keeps ordered operations")
	decoded.fog_regions[0].bounds.position.x += 12
	_check(floor.fog_regions[0].bounds.position.x == -20,
		"dictionary roundtrip has detached fog resources")
	for broken: Variant in [ [0, 0, -1, 4], [0, 0, 0, 4], [0, NAN, 4, 4],
		[0, 0, INF, 4], [0, 0, 1e8, 1], [0, 0, 1] ]:
		_check(AtlasFogRegion.from_dict({"bounds": broken, "reveal": true}) == null,
			"reject invalid fog rectangle")
	_check(AtlasFogRegion.from_dict({"bounds": [0, 0, 1, 1], "reveal": "yes"}) == null,
		"reject nonboolean mode")
	var malformed: Dictionary = floor.to_dict()
	malformed["fog_enabled"] = "true"
	_check(AtlasFloor.from_dict(malformed) == null, "reject malformed enable flag")
	malformed = floor.to_dict()
	malformed["fog_regions"][0]["bounds"] = [0, 0, -5, 3]
	_check(AtlasFloor.from_dict(malformed) == null, "reject malformed saved region")
	malformed = floor.to_dict()
	malformed["fog_regions"] = []
	for i: int in range(AtlasFloor.MAX_FOG_REGIONS + 1):
		malformed["fog_regions"].append(reveal.to_dict())
	_check(AtlasFloor.from_dict(malformed) == null, "reject unbounded saved fog operations")
	var legacy: Dictionary = floor.to_dict()
	legacy.erase("fog_enabled")
	legacy.erase("fog_regions")
	var old: AtlasFloor = AtlasFloor.from_dict(legacy)
	_check(old != null and not old.fog_enabled and old.fog_regions.is_empty(),
		"legacy files without fog fields remain loadable")


func _history_checks() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	var document: AtlasMapDocument = AtlasMapDocument.new("fog-map", "GM")
	campaign.add_map(document)
	campaign.root_map_id = document.id
	var floor: AtlasFloor = document.floors[0]
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = document.id
	var region: AtlasFogRegion = AtlasFogRegion.new(Rect2(-8, -8, 16, 16), true)
	var guarded: AtlasFogEdit = AtlasFogEdit.new(document, floor, region)
	_check(history.execute(guarded) and floor.fog_enabled and floor.fog_allows(Vector2(0, 0)),
		"first edit enables deny-by-default fog and records reveal")
	_check(history.undo() and not floor.fog_enabled and floor.fog_regions.is_empty(),
		"undo first reveal restores previously disabled fog")
	_check(history.redo() and floor.fog_enabled and floor.fog_regions.size() == 1,
		"redo restores same canonical fog")
	var stale: AtlasFogEdit = AtlasFogEdit.new(document, floor,
		AtlasFogRegion.new(Rect2(5, 5, 3, 3), false))
	floor.fog_regions[0].bounds = Rect2(-9, -9, 17, 17)
	_check(not history.execute(stale) and floor.fog_regions.size() == 1,
		"stale history edit rejects in-place fog revision")
	floor.fog_regions[0].bounds = region.bounds
	var empty_mask: AtlasEditScope = AtlasEditScope.new(PackedVector2Array(), true)
	_check(not history.execute(AtlasFogEdit.new(document, floor, region, empty_mask)),
		"invalid active edit mask denies reveal")
	var mask: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)]), true)
	_check(not history.execute(AtlasFogEdit.new(document, floor, region, mask)),
		"selected-cell scope rejects crossing reveal")
	var local: AtlasFogRegion = AtlasFogRegion.new(Rect2(2, 2, 4, 4), false)
	_check(history.execute(AtlasFogEdit.new(document, floor, local, mask)),
		"selected-cell scope permits contained hide")
	_check(history.undo() and floor.fog_allows(Vector2(3, 3)), "undo hide restores visibility")
	_check(history.redo() and not floor.fog_allows(Vector2(3, 3)), "redo hide conceals again")
	var foreign: AtlasMapDocument = AtlasMapDocument.new(document.id, "replacement")
	campaign.maps[document.id] = foreign
	_check(not history.execute(AtlasFogEdit.new(document, floor, local)) \
		and foreign.floors[0].fog_regions.is_empty(),
		"replaced map with reused IDs is never edited")
	campaign.maps[document.id] = document
	var snapshot: Array[AtlasFogRegion] = AtlasFloor.clone_fog(floor.fog_regions)
	var path: String = "user://t042_fog_save.scn"
	_check(AtlasCampaignStore.save_campaign(campaign, path) == OK,
		"native scene saves fog operations")
	var result: AtlasStoreResult = AtlasCampaignStore.load_result(path)
	var saved_floor: AtlasFloor = result.campaign.get_map(document.id).floors[0] if result.campaign != null else null
	_check(saved_floor != null and saved_floor.fog_enabled \
		and AtlasFloor.same_fog(saved_floor.fog_regions, snapshot),
		"native independent reload restores exact fog ordering")
	if saved_floor != null:
		saved_floor.fog_regions[0].reveal = false
		_check(floor.fog_regions[0].reveal, "reloaded resources do not alias GM state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.trim_suffix(".scn") + ".bak.scn"))


func _projection_checks() -> void:
	var source: AtlasMapDocument = AtlasMapDocument.new("private-map", "secret-title")
	var floor: AtlasFloor = source.floors[0]
	floor.layers.clear()
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	var paint: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	paint.id = "paint-0"
	paint.display_name = "secret-chunk"
	paint.transform.origin = Vector2(-10, 8)
	floor.layers.append(paint)
	var high: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	high.id = "paint-1"
	high.detail_level = 1
	high.transform.origin = Vector2(-10, 8)
	floor.layers.append(high)
	var text: AtlasObjectsLayer = AtlasObjectsLayer.new("notes", "SECRET NOTES")
	floor.layers.append(text)
	floor.fog_enabled = true
	var grant0: Array[String] = ["paint-0"]
	var grant1: Array[String] = ["paint-1"]
	var no_reveal: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, floor.id, 0, grant0)
	_check(no_reveal != null and no_reveal.floors[0].layers.size() == 1 \
		and (no_reveal.floors[0].layers[0] as AtlasRasterLayer).chunks.is_empty(),
		"empty fog exposes no raster chunks or hashes")
	var no_reveal_d1: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, floor.id, 1, grant1)
	_check(no_reveal_d1 != null and (no_reveal_d1.floors[0].layers[0] as AtlasRasterLayer).chunks.is_empty(),
		"different LOD cannot bypass floor fog")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-10, 8, 4, 8), true))
	var result: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, floor.id, 0, grant0)
	var result_d1: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, floor.id, 1, grant1)
	_check(result != null and result_d1 != null, "signed-coordinate masked captures build on both LODs")
	if result == null or result_d1 == null:
		return
	var visible: AtlasRasterLayer = result.floors[0].layers[0] as AtlasRasterLayer
	var visible_d1: AtlasRasterLayer = result_d1.floors[0].layers[0] as AtlasRasterLayer
	var region: AtlasRasterChunk = visible.chunks["0,0"]
	_check(region.image.get_pixel(1, 4) == Color.GREEN,
		"authorized raster pixels retained")
	_check(region.image.get_pixel(6, 4).a == 0.0 and visible_d1.chunks["0,0"].image.get_pixel(6, 4).a == 0.0,
		"concealed pixels stripped from both LOD source images")
	_check(AtlasRasterChunk.image_hash(region.image) != paint.chunks["0,0"].asset_id,
		"sanitized image hash differs from canonical secret image")
	_check(not JSON.stringify(visible.to_dict()).contains("secret-chunk") \
		and not JSON.stringify(visible.to_dict()).contains(paint.chunks["0,0"].asset_id),
		"player layer metadata excludes source name and original pixel hash")
	region.image.fill(Color.BLUE)
	_check(paint.chunks["0,0"].image.get_pixel(1, 4) == Color.GREEN,
		"player copy never aliases GM pixel buffers")
	var mixed: Array[String] = ["paint-0", "notes"]
	_check(AtlasPlayerProjection.build_artwork_view(source, floor.id, 0, mixed) == null,
		"fogged vector/text layers fail closed until clipping policy is approved")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-10, 8, 4, 8), false))
	var hidden: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, floor.id, 0, grant0)
	_check(hidden != null and (hidden.floors[0].layers[0] as AtlasRasterLayer).chunks.is_empty(),
		"re-hide removes all formerly revealed source data")
	# Chunk coordinates and density are independent from board coordinates;
	# the filter must apply the same world-space transform as the renderer.
	var transformed: AtlasMapDocument = AtlasMapDocument.new("transformed", "Signed raster")
	var other_floor: AtlasFloor = transformed.floors[0]
	other_floor.layers.clear()
	var shifted: AtlasRasterLayer = AtlasRasterLayer.from_image(image, 4.0)
	shifted.id = "offset"
	shifted.transform.origin = Vector2(13, 5)
	var moved_chunk: AtlasRasterChunk = shifted.chunks["0,0"]
	shifted.chunks.clear()
	moved_chunk.coord = Vector2i(-1, 0)
	shifted.chunks["-1,0"] = moved_chunk
	other_floor.layers.append(shifted)
	other_floor.fog_enabled = true
	other_floor.fog_regions.append(AtlasFogRegion.new(Rect2(-51, 5, 1, 2), true))
	var shifted_grant: Array[String] = ["offset"]
	var filtered: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(
		transformed, other_floor.id, 0, shifted_grant)
	_check(filtered != null and (filtered.floors[0].layers[0] as AtlasRasterLayer).chunks.has("-1,0"),
		"signed chunk coordinates survive fog sanitization")
	if filtered != null:
		var result_chunk: AtlasRasterChunk = (filtered.floors[0].layers[0] as AtlasRasterLayer).chunks["-1,0"]
		_check(result_chunk.image.get_pixel(1, 3) == Color.GREEN \
			and result_chunk.image.get_pixel(6, 3).a == 0.0,
			"density and translated raster transform evaluate reveal in board coordinates")
		_check(moved_chunk.image.get_pixel(6, 3) == Color.GREEN,
			"fog filtering cannot erase canonical pixels on a transformed import")
	floor.fog_regions[0].bounds.size.x = -1
	_check(AtlasPlayerProjection.build_artwork_view(source, floor.id, 0, grant0) == null,
		"invalid fog policy rejects capture instead of defaulting to public")
	floor.fog_regions[0].bounds.size.x = 4
	_check(AtlasPlayerProjection.build_artwork_view(source, floor.id, 0, ["paint-1"]) == null,
		"wrong-LOD grant is rejected instead of searching another group")


func _editor_checks() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for _i: int in range(8):
		await process_frame
	editor.create_board("Fog GM", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
	var canvas: AtlasCanvas = editor.canvas
	editor._choose_tool(AtlasCanvas.Tool.FOG)
	_check(canvas.tool == AtlasCanvas.Tool.FOG and canvas.floor.fog_regions.is_empty(),
		"palette Fog tool does not create an artwork layer")
	editor._edit_fog(Rect2(-12, -6, 24, 12), true)
	_check(canvas.floor.fog_enabled and canvas.floor.fog_allows(Vector2(-1, -1)),
		"GM reveal gesture submits one history action")
	var target: AtlasFloor = canvas.floor
	editor._edit_fog(Rect2(-3, -3, 6, 6), false)
	_check(not target.fog_allows(Vector2.ZERO) and target.fog_allows(Vector2(7, 0)),
		"GM hide gesture masks only chosen rectangle")
	_check(editor.edits.undo() and target.fog_allows(Vector2.ZERO), "editor undo reveals hidden cell")
	_check(editor.edits.redo() and not target.fog_allows(Vector2.ZERO), "editor redo conceals cell")
	_check(editor.rename_floor("Revised") and canvas.floor.fog_regions.size() == 2,
		"floor rename preserves fog state")
	# Exercise the actual Canvas gesture seam, not only the editor command.
	var count: int = canvas.floor.fog_regions.size()
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = canvas.document_to_local(Vector2(14, 14))
	canvas._begin_left_press(down)
	_check(canvas.is_editing(), "fog drag starts a cancellable gesture")
	canvas._fog_end = Vector2(30, 30)
	canvas.cancel_edit()
	_check(not canvas.is_editing() and canvas.floor.fog_regions.size() == count,
		"Escape cancellation leaves saved fog and history intact")
	canvas._begin_left_press(down)
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = canvas.document_to_local(Vector2(30, 30))
	canvas._finish_left_release(up)
	_check(canvas.floor.fog_regions.size() == count + 1 and canvas.floor.fog_allows(Vector2(20, 20)),
		"reveal drag commits rectangle through the same editor history signal")
	var shifted: InputEventMouseButton = InputEventMouseButton.new()
	shifted.button_index = MOUSE_BUTTON_LEFT
	shifted.position = down.position
	shifted.shift_pressed = true
	canvas._begin_left_press(shifted)
	canvas._finish_left_release(up)
	_check(not canvas.floor.fog_allows(Vector2(20, 20)),
		"Shift-drag re-hides a region through the Canvas gesture")
	_check(editor.edits.undo() and canvas.floor.fog_allows(Vector2(20, 20)),
		"gesture history correctly undoes a hide")
	root.remove_child(scene)
	scene.free()
