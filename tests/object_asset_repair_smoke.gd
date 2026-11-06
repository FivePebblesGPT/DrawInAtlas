extends SceneTree
## T-065 Atlas-owned deletion confirmation, NULL recovery and safe explicit rebind.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T065_ASSET_REPAIR_FAILED: " + description)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in directory.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t065-null-" + DrawingDocument.new_id())
	var path: String = folder.path_join("Campaign.scn")
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var source: DrawingDocument = DrawingDocument.new("asset-smoke", 16)
	var group: DrawingResult = source.create_layer(DrawingLayerNode.GROUP, "Group")
	_check(group.ok, "create source group")
	var painted: DrawingResult = source.create_layer(DrawingLayerNode.RASTER, "Pixels", String(group.value))
	_check(painted.ok, "create source layer")
	var a: DrawingResult = library.create_asset(source, "Pine")
	var b: DrawingResult = library.create_asset(source, "Pine")
	_check(a.ok and b.ok and a.value != b.value, "distinct published IDs can share a display name")
	if not a.ok or not b.ok:
		print("T065_ASSET_REPAIR_FAILED missing setup")
		quit(1)
		return
	var old_id: String = String(a.value)
	var target_id: String = String(b.value)
	var matrix: Transform2D = Transform2D(0.5, Vector2(140.0, -11.0))
	var placed: DrawingResult = library.place(old_id, "world", "floor", "D1", matrix)
	var another: DrawingResult = library.place(old_id, "city", "upper", "D2", Transform2D.IDENTITY)
	_check(placed.ok and another.ok, "two placements use the published source")
	if not placed.ok or not another.ok:
		quit(1)
		return
	var instance_id: String = String(placed.value)
	var another_id: String = String(another.value)
	var before: Dictionary = library.instance_info(instance_id)
	var baseline: Dictionary = library.export_index()
	var usage: Dictionary = library.source_usage(old_id)
	_check(usage == {"linked": 2, "null": 0, "total": 2}, "counts report two linked uses")
	_check(library.source_usage(target_id)["total"] == 0 and library.asset_exists(target_id),
		"unused retained source is not implicitly deleted")
	var preview: DrawingResult = library.preview_delete_asset(old_id)
	_check(preview.ok and preview.value["bindings"].size() == 2,
		"confirmation includes both ordered placements")
	_check(not library.preview_delete_asset("absent-source").ok, "unknown deletion target cannot be previewed")
	_check(library.delete_asset(old_id, "cancel", preview.value).ok and library.export_index() == baseline,
		"cancel never changes source or instances")
	_check(not library.delete_asset(old_id, "nonsense", preview.value).ok and library.export_index() == baseline,
		"unsupported deletion policy fails closed")
	var changed: DrawingResult = library.transform_instance(instance_id, int(before["revision"]),
		Transform2D(0.75, Vector2(-32, 18)))
	_check(changed.ok, "concurrent instance transform can occur while confirmation is open")
	var changed_snapshot: Dictionary = library.export_index()
	var stale: DrawingResult = library.delete_asset(old_id, "null", preview.value)
	_check(not stale.ok and stale.code == "STALE_SOURCE", "old confirmation fails after placement edit")
	_check(library.export_index() == changed_snapshot, "stale confirmation does not partially change registry")
	var renewed: DrawingResult = library.preview_delete_asset(old_id)
	_check(renewed.ok and renewed.value["bindings"] != preview.value["bindings"],
		"new confirmation reflects changed instance revision")
	var kept: DrawingResult = library.delete_asset(old_id, "null", renewed.value)
	_check(kept.ok and library.asset_info(old_id).is_empty(), "NULL policy retires source registry entry")
	_check(not library.asset_exists(old_id) and library.asset_exists(target_id),
		"independent source remains available")
	_check(library.source_usage(old_id) == {"linked": 0, "null": 2, "total": 2},
		"retired source keeps two NULL uses")
	var null_info: Dictionary = library.instance_info(instance_id)
	_check(null_info["id"] == instance_id and null_info["generation"] == before["generation"]
		and null_info["transform"] == changed_snapshot["instances"].filter(
			func(row: Dictionary) -> bool: return row["id"] == instance_id)[0]["transform"],
		"NULL keeps placement ID, generation and transformed geometry")
	_check(null_info["source_id"] == old_id and null_info["status"] == "NULL",
		"placeholder retains original source ID")
	_check(library.instance_info(another_id)["status"] == "NULL",
		"deletion handles both map placements")
	_check(library.render_instance(instance_id, Rect2i(0, 0, 1, 1)).value["status"] == "NULL",
		"NULL renderer remains visible as a missing-object proxy")
	var wrong_revision: DrawingResult = library.repair_placeholder(instance_id,
		String(null_info["generation"]), int(null_info["revision"]) + 1, target_id)
	_check(not wrong_revision.ok and wrong_revision.code == "STALE_INSTANCE", "stale revision cannot repair")
	var wrong_generation: DrawingResult = library.repair_placeholder(instance_id,
		"substituted-generation", int(null_info["revision"]), target_id)
	_check(not wrong_generation.ok and wrong_generation.code == "STALE_INSTANCE",
		"reused ID under a different generation cannot repair")
	var namesake: DrawingResult = library.repair_placeholder(instance_id,
		String(null_info["generation"]), int(null_info["revision"]), old_id)
	_check(not namesake.ok and namesake.code == "MISSING_SOURCE",
		"repair does not guess same-named retired source")
	_check(library.instance_info(instance_id) == null_info, "failed repair preserves NULL metadata and transform")
	var recovered: DrawingResult = library.repair_placeholder(instance_id,
		String(null_info["generation"]), int(null_info["revision"]), target_id)
	_check(recovered.ok and recovered.value == instance_id, "explicit published target repairs NULL")
	var repaired: Dictionary = library.instance_info(instance_id)
	_check(repaired["status"] == "linked" and repaired["source_id"] == target_id,
		"repaired link resolves selected target source")
	_check(repaired["id"] == null_info["id"] and repaired["generation"] == null_info["generation"]
		and repaired["transform"] == null_info["transform"] and repaired["map_id"] == null_info["map_id"]
		and repaired["floor_id"] == null_info["floor_id"] and repaired["detail_id"] == null_info["detail_id"],
		"repair preserves stable placement identity and exact map-space transform")
	_check(repaired["metadata"].get("null_origin_source_id", "") == old_id,
		"repair records origin of missing source for inspection")
	_check(repaired["revision"] == null_info["revision"] + 1,
		"repair advances binding revision exactly once")
	_check(library.source_usage(target_id)["linked"] == 1 and library.source_usage(old_id)["null"] == 1,
		"per-source usage counts update when a NULL is repaired")
	var retry: DrawingResult = library.repair_placeholder(instance_id,
		String(null_info["generation"]), int(null_info["revision"]), target_id)
	_check(not retry.ok and retry.code == "STALE_INSTANCE", "stale repeated repair cannot replay")
	var live_attempt: DrawingResult = library.repair_placeholder(instance_id,
		String(repaired["generation"]), int(repaired["revision"]), target_id)
	_check(not live_attempt.ok and live_attempt.code == "NOT_NULL", "cannot rebind a live instance as NULL repair")
	var reopened: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(reopened.load().ok, "source and NULL repair survive new library handle")
	_check(reopened.instance_info(instance_id)["metadata"].get("null_origin_source_id", "") == old_id
		and reopened.instance_info(another_id)["status"] == "NULL",
		"portable registry preserves repaired and unrepaired placements")
	var other_before: Dictionary = reopened.instance_info(another_id)
	var forced_fail: DrawingResult = reopened.repair_placeholder(another_id,
		String(other_before["generation"]), int(other_before["revision"]), target_id)
	_check(forced_fail.ok, "second explicit repair succeeds")
	# Repair must not produce a registry that later fails the 128-field
	# metadata schema, even when all keys were legal before placeholder creation.
	var fresh_source: DrawingResult = reopened.create_asset(source, "Full-metadata source")
	_check(fresh_source.ok, "create source for metadata-cap recovery")
	if fresh_source.ok:
		var extra: DrawingResult = reopened.place(String(fresh_source.value), "world", "floor", "D0")
		_check(extra.ok, "create placement for maximum-size metadata")
		if extra.ok:
			var extra_id: String = String(extra.value)
			var extra_info: Dictionary = reopened.instance_info(extra_id)
			var full: Dictionary = {}
			for k: int in range(128):
				full["tag-%d" % k] = "value"
			_check(reopened.set_instance_metadata(extra_id, int(extra_info["revision"]), full).ok,
				"128 scalar metadata entries are valid before NULL repair")
			var cap_preview: DrawingResult = reopened.preview_delete_asset(String(fresh_source.value))
			_check(cap_preview.ok and reopened.delete_asset(String(fresh_source.value), "null", cap_preview.value).ok,
				"full-metadata placement becomes a NULL without information loss")
			var capped: Dictionary = reopened.instance_info(extra_id)
			var refused: DrawingResult = reopened.repair_placeholder(extra_id,
				String(capped["generation"]), int(capped["revision"]), target_id)
			_check(not refused.ok and refused.code == "METADATA_LIMIT",
				"repair rejects adding origin metadata beyond serialized schema cap")
			_check(reopened.instance_info(extra_id) == capped, "failed capped repair leaves exact NULL snapshot")
	var second_token: DrawingResult = reopened.preview_delete_asset(target_id)
	_check(second_token.ok and second_token.value["bindings"].size() == 2,
		"source delete preview counts newly repaired links")
	reopened.publication_guard = func() -> bool: return false
	var rejected: DrawingResult = reopened.delete_asset(target_id, "remove", second_token.value)
	_check(not rejected.ok and reopened.asset_exists(target_id), "publication failure preserves source")
	_check(reopened.instance_info(instance_id)["status"] == "linked" and reopened.instance_ids().size() == 3,
		"failed Remove all does not erase unrelated instance bindings")
	reopened.publication_guard = Callable()
	var removed: DrawingResult = reopened.delete_asset(target_id, "remove", second_token.value)
	_check(removed.ok and reopened.instance_ids().size() == 1 and reopened.asset_info(target_id).is_empty(),
		"confirmed Remove all deletes only this source's references")
	var file_path: String = folder.path_join(String(library.asset_info(target_id)["path"]))
	_check(FileAccess.file_exists(file_path), "retired source bytes remain on disk for recovery/history")
	var final_handle: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(final_handle.load().ok and final_handle.instance_ids().size() == 1 and
		final_handle.instance_info(final_handle.instance_ids()[0])["status"] == "NULL",
		"metadata-limit refusal and removal leave a reloadable NULL-only registry")
	_erase_tree(folder)
	print("T065_ASSET_REPAIR_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
