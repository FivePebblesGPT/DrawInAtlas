extends SceneTree
## T-109: real 512/513-file scan, thumbnail pressure and stale-transfer oracle.

const INDEX: Script = preload("res://addons/drawing/asset_browser_index.gd")
const TRANSFER: Script = preload("res://addons/drawing/asset_browser_transfer.gd")
const THUMBNAILS: Script = preload("res://addons/drawing/asset_browser_thumbnails.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T109_SCALE_FAILED: " + label)


func write_source(path: String, id: String, name: String = "") -> bool:
	var document: DrawingDocument = DrawingDocument.new(id, 16)
	return DrawingObjectEditorFile.save(document, path, name if not name.is_empty() else id,
		Vector2i(-17, 9), Rect2i(-33, -7, 9, 11), 1).ok


func erase_fixture(path: String) -> bool:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	for name: String in directory.get_files():
		if DirAccess.remove_absolute(path.path_join(name)) != OK:
			return false
	for name: String in directory.get_directories():
		if directory.is_link(name):
			if DirAccess.remove_absolute(path.path_join(name)) != OK:
				return false
		elif not erase_fixture(path.path_join(name)):
			return false
	return DirAccess.remove_absolute(path) == OK


func quantile(values: Array[int], numerator: int, denominator: int) -> int:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1,
		maxi(0, ceili(float(sorted.size() * numerator) / float(denominator)) - 1))]


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t109-scale-" + DrawingDocument.new_id())
	var objects: String = base.path_join("Campaign/Objects")
	var incoming: String = base.path_join("Incoming")
	var export_dir: String = base.path_join("Export")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK and
		DirAccess.make_dir_recursive_absolute(incoming) == OK and
		DirAccess.make_dir_recursive_absolute(export_dir) == OK,
		"create real isolated portable directory tree")
	var index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(index.scan(objects).ok and index.entries.is_empty(), "empty root accepts first scan")
	var original_input: String = incoming.path_join("input.drawing")
	check(write_source(original_input, "asset-import"), "prepare real incoming portable source")
	var imported: DrawingResult = TRANSFER.import_file(index, original_input)
	check(imported.ok and FileAccess.file_exists(objects.path_join("asset-import.drawing")),
		"explicit Import succeeds on unchanged snapshot")
	check(index.scan(objects).ok and index.entries.size() == 1, "refresh after Import")
	var populated: bool = true
	for i: int in range(511):
		if not write_source(objects.path_join("asset-%04d.drawing" % i), "asset-%04d" % i):
			populated = false
			break
	check(populated, "create 511 more actual canonical portable sources")
	var times_us: Array[int] = []
	var memory_samples: Array[int] = []
	var complete: bool = true
	for trial: int in range(5):
		var before: int = Time.get_ticks_usec()
		var result: DrawingResult = index.scan(objects)
		times_us.append(Time.get_ticks_usec() - before)
		memory_samples.append(OS.get_static_memory_usage())
		if not result.ok or index.entries.size() != 512 or not index.warnings.is_empty():
			complete = false
	check(complete, "five complete 512-source scans with no dropped identities")
	check(index.filtered("asset-0500").size() == 1 and
		index.filtered("asset-import").size() == 1,
		"late alphabetic source and imported source both present")
	var remembered: Dictionary = index.filtered("asset-0500")[0].duplicate(true)
	check(index.safe_to_open(remembered), "late indexed source authorized")
	var thumbnails: DrawingAssetBrowserThumbnails = THUMBNAILS.new() as DrawingAssetBrowserThumbnails
	var preview_ok: bool = true
	for row: int in range(26):
		var rendered: DrawingResult = thumbnails.preview(index, index.entries[row])
		if not rendered.ok or not rendered.value is Image:
			preview_ok = false
	check(preview_ok and thumbnails.count() == DrawingAssetBrowserThumbnails.CAPACITY,
		"26 real previews obey 24-entry bounded thumbnail LRU")
	var previous: Array[Dictionary] = index.entries.duplicate(true)
	var extra: String = objects.path_join("zz-extra.drawing")
	check(write_source(extra, "asset-513"), "create 513th unique real source")
	var exceeded: DrawingResult = index.scan(objects)
	check(not exceeded.ok and exceeded.code == "ASSET_LIMIT" and index.entries == previous,
		"513th source rejects entire snapshot atomically")
	check(DirAccess.remove_absolute(extra) == OK, "remove only test-owned overflow fixture")
	var duplicate: String = objects.path_join("zz-duplicate.drawing")
	check(write_source(duplicate, "asset-0500", "Duplicate late ID"), "create late duplicate ID")
	check(index.scan(objects).ok and index.filtered("asset-0500").is_empty() and
		index.entries.size() == 511 and not index.warnings.is_empty(),
		"late duplicate suppresses ambiguous ID, without selecting either")
	check(DirAccess.remove_absolute(duplicate) == OK and index.scan(objects).ok and
		index.entries.size() == 512, "restore unambiguous snapshot")
	var selected: Dictionary = index.filtered("asset-0500")[0].duplicate(true)
	var selected_path: String = selected["path"]
	var parked: String = incoming.path_join("parked-original.drawing")
	check(DirAccess.rename_absolute(selected_path, parked) == OK, "move selected source out of root")
	var root_dir: DirAccess = DirAccess.open(objects)
	check(root_dir.create_link(original_input, selected_path) == OK,
		"replace selected path with external symlink")
	check(not index.safe_to_open(selected) and
		not thumbnails.preview(index, selected).ok and
		not TRANSFER.export_file(index, selected, export_dir.path_join("link.drawing")).ok and
		not FileAccess.file_exists(export_dir.path_join("link.drawing")),
		"Open, preview and Export reject replaced selected path")
	check(DirAccess.remove_absolute(selected_path) == OK and
		DirAccess.rename_absolute(parked, selected_path) == OK and
		index.safe_to_open(selected), "restore real path without modifying bytes")
	# Keep one free source slot: a full 512/512 index rejects Import for capacity
	# regardless of freshness, and would not exercise the stale-index preflight.
	var held_back: String = objects.path_join("asset-0510.drawing")
	var held_back_safe: String = incoming.path_join("held-back.drawing")
	check(DirAccess.rename_absolute(held_back, held_back_safe) == OK and
		index.scan(objects).ok and index.entries.size() == 511,
		"leave capacity for a real stale-snapshot Import control")
	var new_input: String = incoming.path_join("new-source.drawing")
	check(write_source(new_input, "asset-fresh"), "prepare second external source")
	var new_unindexed: String = objects.path_join("new-unindexed.drawing")
	check(write_source(new_unindexed, "asset-other"),
		"simulate external source creation after displayed snapshot")
	var stale_import: DrawingResult = TRANSFER.import_file(index, new_input)
	check(not stale_import.ok and stale_import.code == "STALE_INDEX" and
		not FileAccess.file_exists(objects.path_join("asset-fresh.drawing")) and
		FileAccess.file_exists(new_input),
		"Import fails on stale root rather than using its spare capacity")
	check(DirAccess.remove_absolute(new_unindexed) == OK and
		DirAccess.rename_absolute(held_back_safe, held_back) == OK and
		index.scan(objects).ok and index.entries.size() == 512,
		"restore complete trusted index after stale-source rejection")
	var pinned_copy: String = export_dir.path_join("pinned-copy.drawing")
	var wrong_hash: String = "f".repeat(64)
	if wrong_hash == FileAccess.get_sha256(selected_path):
		wrong_hash = "0".repeat(64)
	var mismatch: DrawingResult = TRANSFER._copy_to_new_file(selected_path, pinned_copy, wrong_hash)
	check(not mismatch.ok and not FileAccess.file_exists(pinned_copy),
		"copy-stage rejects source bytes newer than the selected digest")
	var authorized: DrawingResult = TRANSFER.export_file(index, index.filtered("asset-0500")[0],
		pinned_copy)
	check(authorized.ok and FileAccess.get_sha256(pinned_copy) == selected["sha256"],
		"unchanged authorized source exports exactly selected SHA-256")
	check(FileAccess.file_exists(original_input), "separate original Import input survives all operations")
	var moved: String = base.path_join("RenamedCampaign")
	check(DirAccess.rename_absolute(base.path_join("Campaign"), moved) == OK,
		"rename whole campaign while retaining source filenames")
	check(not index.safe_to_open(selected) and
		not index.scan(objects).ok and index.entries.size() == 512,
		"old absolute listing cannot authorize relocated root")
	var moved_objects: String = moved.path_join("Objects")
	check(index.scan(moved_objects).ok and index.entries.size() == 512 and
		index.safe_to_open(index.filtered("asset-0500")[0]),
		"relocated folder rescans with same source identities and bytes")
	var stats: Dictionary = {"count": 512, "trials": times_us.size(),
		"scan_us": times_us, "scan_p50_us": quantile(times_us, 50, 100),
		"scan_p95_us": quantile(times_us, 95, 100),
		"memory_bytes": memory_samples,
		"memory_p50_bytes": quantile(memory_samples, 50, 100),
		"memory_p95_bytes": quantile(memory_samples, 95, 100),
		"memory_kind": "Godot OS.get_static_memory_usage (engine-tracked, not RSS/VRAM)"}
	print("T109_SCALE_STATS: ", JSON.stringify(stats))
	var keep_fixture: bool = OS.get_environment("T109_KEEP_FIXTURE") == "1"
	if keep_fixture:
		print("T109_FIXTURE_OBJECTS: ", moved_objects)
	check(keep_fixture or erase_fixture(base),
		"clean isolated fixtures unless explicitly retained for the paired benchmark")
	print("T109_SCALE_PASSED (%d checks, %d failures)" % [checks, failures])
	quit(0 if failures == 0 else 1)

