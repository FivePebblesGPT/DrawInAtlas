extends SceneTree
## T-113: a staged Bucket fill belongs to the original registered map/floor
## Resources, not merely IDs and byte-equal snapshots.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T113_BUCKET_FAILED: " + label)


func _pixels(floor: AtlasFloor, layer_id: String) -> PackedByteArray:
	var layer: AtlasRasterLayer = floor.layer_by_id(layer_id) as AtlasRasterLayer
	return layer.chunks["0,0"].image.get_data() if layer != null else PackedByteArray()


func _staged(editor: AtlasEditor) -> bool:
	editor.artwork.preview_fill(Vector2(0.5, 0.5))
	return editor.artwork._pending_fill != null and editor.artwork._pending_fill.ok \
		and editor.canvas._preview_layer != null


func _rejected(editor: AtlasEditor, floor: AtlasFloor,
		before: Dictionary, history: AtlasEditCommand, label: String) -> void:
	editor.artwork.commit_preview_fill()
	_check(floor.to_dict() == before, label + ": raster source unchanged")
	_check(editor.edits.get_undo_command() == history, label + ": no undo transaction")
	_check(editor.artwork._pending_fill == null and editor.canvas._preview_layer == null,
		label + ": preview discarded")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-113 Bucket", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 8)),
		"create isolated campaign")
	var canvas: AtlasCanvas = editor.canvas
	var image: Image = Image.create_empty(3, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 0, 0.6))
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	raster.id = "t113-raster"
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	layers.append(raster)
	_check(editor.apply_layers(layers, raster.id), "install raster target")
	editor.select_layer(raster.id)
	editor._choose_tool(AtlasCanvas.Tool.FILL)
	canvas.brush_color = Color(0.1, 0.8, 0.95, 1)
	var original_map: AtlasMapDocument = canvas.map
	var original_floor: AtlasFloor = canvas.floor
	var id: String = raster.id
	var floor_index: int = original_map.floors.find(original_floor)
	_check(floor_index >= 0 and editor.campaign.get_map(original_map.id) == original_map,
		"initial map and floor are registered Resources")
	var history: AtlasEditCommand = editor.edits.get_undo_command()

	# An equivalent floor with identical IDs and source bytes must not inherit
	# the original press authorization after a host replaces the Resource.
	_check(_staged(editor), "floor replacement starts detached preview")
	var copy_floor: AtlasFloor = AtlasFloor.from_dict(original_floor.to_dict())
	_check(copy_floor != null and copy_floor != original_floor
		and copy_floor.to_dict() == original_floor.to_dict(),
		"same-ID floor clone has identical serialized source")
	original_map.floors[floor_index] = copy_floor
	canvas.floor = copy_floor
	_rejected(editor, copy_floor, copy_floor.to_dict(), history, "floor replacement")
	original_map.floors[floor_index] = original_floor
	canvas.floor = original_floor

	# A map replacement with the same ID, floor ID and bytes also invalidates
	# a held fill; navigation may reuse these identifiers in a reconstructed map.
	_check(_staged(editor), "map replacement starts detached preview")
	var copy_map: AtlasMapDocument = AtlasMapDocument.from_dict(original_map.to_dict())
	_check(copy_map != null and copy_map != original_map
		and copy_map.to_dict() == original_map.to_dict(),
		"same-ID map clone has identical serialized source")
	editor.campaign.add_map(copy_map)
	canvas.map = copy_map
	canvas.floor = copy_map.floor_by_id(original_floor.id)
	_rejected(editor, canvas.floor, canvas.floor.to_dict(), history, "map replacement")
	editor.campaign.add_map(original_map)
	canvas.map = original_map
	canvas.floor = original_floor

	# Registry ownership matters even if the Canvas retained the *original*
	# Resource pointer. A stale preview must never overwrite the new registry.
	_check(_staged(editor), "detached registry map starts preview")
	var registered_copy: AtlasMapDocument = AtlasMapDocument.from_dict(original_map.to_dict())
	editor.campaign.add_map(registered_copy)
	var registered_floor: AtlasFloor = registered_copy.floor_by_id(original_floor.id)
	_rejected(editor, registered_floor, registered_floor.to_dict(), history, "replaced registry map")
	editor.campaign.add_map(original_map)

	_check(_staged(editor), "detached registered floor starts preview")
	var registered_floor_copy: AtlasFloor = AtlasFloor.from_dict(original_floor.to_dict())
	original_map.floors[floor_index] = registered_floor_copy
	_rejected(editor, registered_floor_copy, registered_floor_copy.to_dict(), history, "replaced registered floor")
	original_map.floors[floor_index] = original_floor

	# The campaign owner may change without changing either map or floor
	# object. This is a separate authorization boundary from their stable IDs.
	_check(_staged(editor), "replaced campaign owner starts preview")
	var other_campaign: AtlasCampaign = AtlasCampaign.new()
	other_campaign.add_map(original_map)
	canvas.campaign = other_campaign
	_rejected(editor, original_floor, original_floor.to_dict(), history,
		"replaced campaign owner")
	canvas.campaign = editor.campaign

	# Rejection must not poison a fresh, properly registered gesture.
	# This is self-contained even in a deliberately failing old-source control.
	canvas.brush_color = Color(0.72, 0.11, 0.41, 1)
	var fresh_before: PackedByteArray = _pixels(original_floor, id)
	var fresh_history: AtlasEditCommand = editor.edits.get_undo_command()
	_check(_staged(editor), "fresh registered preview is valid")
	editor.artwork.commit_preview_fill()
	var changed: PackedByteArray = _pixels(original_floor, id)
	_check(changed != fresh_before and editor.edits.get_undo_command() != fresh_history,
		"fresh fill publishes one atomic history entry")
	editor._on_undo()
	_check(_pixels(original_floor, id) == fresh_before, "undo restores original bytes")
	editor._on_redo()
	_check(_pixels(original_floor, id) == changed, "redo restores filled bytes")

	root.remove_child(scene)
	scene.free()
	print("T113_BUCKET_%s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
