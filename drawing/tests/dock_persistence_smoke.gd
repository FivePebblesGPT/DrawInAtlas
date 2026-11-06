extends SceneTree
## T-083: deterministic disk/model recovery independent of the OS UI.
const PERSIST: Script = preload("res://addons/drawing/dock_persistence.gd")
const LAYOUT: Script = preload("res://addons/drawing/dock_layout.gd")
const FILE: String = "user://t083-persistence-smoke.json"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T083_MODEL_FAILED: " + label)

func model(ids: Array[String]) -> DrawingDockLayout:
	var l: DrawingDockLayout = LAYOUT.new() as DrawingDockLayout
	l.create_container("right")
	for id: String in ids:
		l.register_panel(id)
		l.attach_panel(id, "right", id)
	return l

func state(l: DrawingDockLayout) -> Dictionary:
	return {"schema": 1, "layout": l.snapshot(), "dock_width": 317, "dock_scroll": 54,
		"hosts": [{"id": "float-9", "visible": false, "rect": [115.0, 80.0, 350.0, 270.0], "client": [1280.0, 800.0]}]}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original: DrawingDockLayout = model(["colors", "layers", "history", "swatches", "gradients"])
	check(original.merge_groups("layers", "colors", 1), "merge two dock tabs")
	check(original.select_panel("layers"), "select secondary tab")
	check(original.set_group_collapsed("history", true), "collapse dock group")
	check(original.create_container("float-9", DrawingDockLayout.FLOATING), "create hidden float")
	check(original.move_group("colors", "float-9", 0), "move multi-tab group into float")
	check(original.set_minimized("right", true), "minimize dock")
	check(original.activate_from_rail("right", "swatches"), "open dock flyout")
	var encoded: Dictionary = state(original)
	check(DrawingDockPersistence.save_file(FILE, encoded), "write atomic JSON settings")
	check(FileAccess.file_exists(FILE), "saved settings exist")
	var disk: Dictionary = DrawingDockPersistence.read_file(FILE)
	check(disk.has("layout") and int(disk["layout"].get("version", -1)) == 1 and disk.get("schema") == 1,
		"read versioned JSON payload")
	var restored: Dictionary = DrawingDockPersistence.recover(disk,
		model(["colors", "layers", "history", "swatches", "gradients"]))
	check(not restored.is_empty(), "valid snapshot decodes")
	check(not restored.get("recovered", true), "unchanged panel registry does not require repair")
	check(restored["layout"] == original.snapshot(), "model snapshots round-trip exactly")
	check(restored["hosts"].size() == 1 and not restored["hosts"][0]["visible"], "hidden host round-trips")
	check(restored["dock_width"] == 317 and restored["dock_scroll"] == 54, "dock width/scroll round-trip")
	var witness: DrawingDockLayout = model(["colors", "layers", "history", "swatches", "gradients"])
	check(witness.restore(restored["layout"]), "existing owner validation accepts repaired payload")
	check(witness.rail_icons("right").map(func(e: Dictionary) -> String: return e["panel"]) == ["history", "swatches", "gradients"], "rail restored without floating icons")
	check(witness.group_info("colors")["panels"] == ["colors", "layers"] and witness.group_info("colors")["active"] == "layers", "floating tab order/active restored")
	check(witness.group_info("history")["collapsed"] and witness.container_info("right")["minimized"], "collapsed and minimized restored")
	check(witness.container_info("right")["flyout_group"] == "swatches", "open flyout group restored")
	var adapted: Rect2 = DrawingDockPersistence.restore_rect(restored["hosts"][0], Vector2(640, 400))
	check(adapted.position.is_equal_approx(Vector2(57.5, 40.0)), "position scales to half-size viewport")
	check(adapted.size.is_equal_approx(Vector2(175, 135)), "size scales to half-size viewport before host min-size clamping")
	var next_model: DrawingDockLayout = model(["colors", "layers", "history", "swatches", "asset_browser"])
	var migrated: Dictionary = DrawingDockPersistence.recover(disk, next_model)
	check(not migrated.is_empty() and migrated["recovered"], "absent plugin and newly registered panel recover")
	check(not (migrated["layout"]["panels"] as Array).any(func(item: Dictionary) -> bool: return item["id"] == "gradients"), "stale plugin no longer registered")
	var migrated_groups: Array = migrated["layout"]["containers"][0]["groups"]
	check(migrated_groups[-1]["panels"] == ["asset_browser"], "future panel appended without schema hardcoding")
	check(next_model.restore(migrated["layout"]), "recovered snapshot passes model validation")
	check(next_model.owner_of("asset_browser") == "right" and next_model.owner_of("gradients") == "", "no stranded or duplicated panel")
	var renamed: Dictionary = DrawingDockPersistence.recover(disk,
		model(["colors", "layers", "history", "swatches", "tone_map"]), {"gradients": "tone_map"})
	check(not renamed.is_empty() and renamed["layout"]["containers"][0]["groups"][-1]["panels"] == ["tone_map"], "explicit rename alias preserves original position")
	var duplicate: Dictionary = disk.duplicate(true)
	duplicate["layout"]["containers"][0]["groups"][0]["panels"].append("swatches")
	check(DrawingDockPersistence.recover(duplicate, model(["colors", "layers", "history", "swatches", "gradients"])) .is_empty(), "duplicate ownership rejected transactionally")
	var malformed: Dictionary = disk.duplicate(true)
	malformed["layout"]["containers"][0]["groups"][0]["panels"] = 123
	check(DrawingDockPersistence.recover(malformed, witness).is_empty(), "malformed group rejected")
	var wrong_version: Dictionary = disk.duplicate(true)
	wrong_version["schema"] = 75
	check(DrawingDockPersistence.recover(wrong_version, witness).is_empty(), "unsupported schema not guessed")
	wrong_version = disk.duplicate(true)
	wrong_version["layout"]["version"] = 75
	check(DrawingDockPersistence.recover(wrong_version, witness).is_empty(), "unsupported model version not guessed")
	var no_host_geometry: Dictionary = disk.duplicate(true)
	no_host_geometry["hosts"] = []
	var missing_host: Dictionary = DrawingDockPersistence.recover(no_host_geometry, witness)
	check(missing_host.get("recovered", false) and missing_host["hosts"].size() == 1, "missing floating host geometry gets safe default")
	check(missing_host["hosts"][0]["visible"], "missing host geometry always recovers visibly")
	var invalid_frame: Dictionary = disk.duplicate(true)
	invalid_frame["hosts"][0]["rect"][2] = -1.0
	var repaired: Dictionary = DrawingDockPersistence.recover(invalid_frame, witness)
	check(repaired.get("recovered", false) and repaired["hosts"].size() == 1 and repaired["hosts"][0]["visible"], "invalid frame recovers visible host")
	var unsupported_host: Dictionary = disk.duplicate(true)
	unsupported_host["hosts"].append({"id": "foreign", "visible": false, "rect": [1, 1, 300, 200], "client": [1280, 800]})
	check(DrawingDockPersistence.recover(unsupported_host, witness)["hosts"].size() == 1, "metadata for unknown host discarded")
	var bad_flyout: Dictionary = disk.duplicate(true)
	bad_flyout["layout"]["containers"][0]["flyout_group"] = "ghost"
	check(DrawingDockPersistence.recover(bad_flyout, witness)["layout"]["containers"][0]["flyout_group"] == "", "stale flyout name cleared")
	var settings_path: String = ProjectSettings.globalize_path(FILE)
	var file: FileAccess = FileAccess.open(FILE, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	check(DrawingDockPersistence.read_file(FILE).is_empty(), "corrupt JSON loads as safe defaults")
	check(DrawingDockPersistence.save_file(FILE, encoded), "recover by replacing corrupt file atomically")
	check(not DrawingDockPersistence.recover(DrawingDockPersistence.read_file(FILE), witness).is_empty(),
		"recovered settings are readable and model-valid")
	check(not FileAccess.file_exists(FILE + ".tmp") and not FileAccess.file_exists(FILE + ".bak"), "no abandoned temporary files")
	check(DirAccess.rename_absolute(settings_path, settings_path + ".bak") == OK,
		"simulate power-loss gap after old settings renamed to backup")
	check(not DrawingDockPersistence.recover(DrawingDockPersistence.read_file(FILE), witness).is_empty(),
		"read intact backup when main settings file is missing")
	check(DrawingDockPersistence.save_file(FILE, encoded), "new atomic save replaces interrupted backup")
	check(not FileAccess.file_exists(FILE + ".bak"), "successful new commit cleans stale backup")
	DirAccess.remove_absolute(settings_path)
	check(DrawingDockPersistence.read_file(FILE).is_empty(), "T-063 three-stack defaults used when no file exists")
	print("T083_MODEL: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("T083_MODEL_PASSED")
	quit(0 if failures == 0 else 1)
