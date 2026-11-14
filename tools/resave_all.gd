extends SceneTree
## Resave every scene/resource under res:// so the running engine version
## normalizes serialization (bumps, serde changes, uid/format drift).
## Run once per engine update, then commit the normalized files:
##
##   godot --headless --path . --import --quit
##   godot --headless --path . --script res://tools/resave_all.gd
##
## Optional user args after `--`: `--dry-run` (load/validate only, never write)
## and res:// roots limiting the scan, e.g. `-- --dry-run drawing/`.
## Contract line: `RESAVE_ALL_PASSED: checked=..; resaved=..; failed=..; engine=<ver>`.

const RESAVE_EXTENSIONS: PackedStringArray = ["tscn", "scn", "tres", "res"]
const STATUS_PASS: String = "RESAVE_ALL_PASSED"
const STATUS_FAIL: String = "RESAVE_ALL_FAILED"

var _dry_run: bool = false
var _checked: int = 0
var _resaved: int = 0
var _failed: int = 0


func _initialize() -> void:
	var roots: PackedStringArray = []
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--dry-run":
			_dry_run = true
		else:
			roots.append(arg)
	if roots.is_empty():
		roots = PackedStringArray(["res://"])
	for root_path: String in roots:
		_process_root(_canonical_root(root_path))
	var engine: String = _engine_version()
	var status: String = STATUS_PASS if _failed == 0 else STATUS_FAIL
	print("%s: checked=%d; resaved=%d; failed=%d; engine=%s%s" % [
		status, _checked, _resaved, _failed, engine,
		"; dry_run=true" if _dry_run else ""])
	quit(1 if _failed > 0 else 0)


func _canonical_root(raw: String) -> String:
	var path: String = raw.strip_edges()
	if not path.begins_with("res://"):
		path = "res://" + path
	while path.length() > 6 and path.ends_with("/"):
		path = path.substr(0, path.length() - 1)
	return path


func _engine_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%d.%d.%d.%s.%s" % [info["major"], info["minor"], info["patch"],
		info["status"], info["build"]]


func _process_root(root_path: String) -> void:
	if FileAccess.file_exists(root_path):
		_resave_file(root_path)
		return
	var directory: DirAccess = DirAccess.open(root_path)
	if directory == null:
		_failed += 1
		push_error("RESAVE_ALL open failed: %s (%s)" % [root_path, DirAccess.get_open_error()])
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var full: String = directory.get_current_dir().path_join(entry)
		if directory.current_is_dir():
			if entry == ".godot":
				continue
			_process_root(full)
		elif RESAVE_EXTENSIONS.has(full.get_extension().to_lower()):
			_resave_file(full)
	directory.list_dir_end()


func _resave_file(path: String) -> void:
	_checked += 1
	if not ResourceLoader.exists(path):
		_failed += 1
		push_error("RESAVE_ALL missing resource: %s" % path)
		return
	var resource: Resource = ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if resource == null:
		_failed += 1
		push_error("RESAVE_ALL load failed: %s" % path)
		return
	if _dry_run:
		return
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var error: Error = ResourceSaver.save(resource, path)
	if error != OK:
		_failed += 1
		push_error("RESAVE_ALL save failed: %s (%s)" % [path, error_string(error)])
		return
	var after: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if before != after:
		_resaved += 1
		print("RESAVE_ALL_SAVED %s bytes=%d -> %d" % [
			path, before.size(), after.size()])
