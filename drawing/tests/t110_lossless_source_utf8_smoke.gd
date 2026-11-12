extends SceneTree
## A portable source is indexed only when its exact bytes are valid UTF-8.
## JSON's replacement-character fallback must never authorize malformed bytes.

const INDEX: Script = preload("res://addons/drawing/asset_browser_index.gd")
const TRANSFER: Script = preload("res://addons/drawing/asset_browser_transfer.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T110_UTF8_FAILED: " + label)


func write_source(path: String, id: String, name: String) -> bool:
	return DrawingObjectEditorFile.save(DrawingDocument.new(id, 16), path, name,
		Vector2i(-17, 9), Rect2i(-33, -7, 9, 11), 1).ok


func replace_one_utf8_byte(path: String, token: String) -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var string_view: String = bytes.get_string_from_utf8()
	var offset: int = string_view.find(token)
	if offset < 0 or token.length() == 0:
		return false
	# All bytes preceding this ASCII marker are ASCII in this fixture.
	bytes[offset] = 255
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	# Prove JSON otherwise decodes into a plausible source using replacement.
	var decoded: String = bytes.get_string_from_utf8()
	return decoded.to_utf8_buffer() != bytes and JSON.parse_string(decoded) is Dictionary


func remove_tree(path: String) -> bool:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return false
	for filename: String in dir.get_files():
		if DirAccess.remove_absolute(path.path_join(filename)) != OK:
			return false
	for child: String in dir.get_directories():
		if not remove_tree(path.path_join(child)):
			return false
	return DirAccess.remove_absolute(path) == OK


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t110-utf8-" + DrawingDocument.new_id())
	var objects: String = base.path_join("Objects")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK, "create isolated Objects folder")
	var malformed: String = objects.path_join("a-invalid.drawing")
	check(write_source(malformed, "shared-source", "RejectHere"), "create valid canonical source")
	var index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(index.scan(objects).ok and index.entries.size() == 1,
		"valid source is initially indexed")
	var old_entry: Dictionary = index.entries[0].duplicate(true)
	check(replace_one_utf8_byte(malformed, "RejectHere"),
		"corrupt one UTF-8 byte without breaking decoded JSON envelope")
	var scan: DrawingResult = index.scan(objects)
	check(scan.ok, "invalid source reports warning rather than failing entire root")
	check(index.entries.is_empty() and not index.warnings.is_empty() and \
		"UTF-8" in index.warnings[0], "malformed UTF-8 cannot enter the authorized index")
	check(not index.safe_to_open(old_entry), "stale valid entry rejected after byte substitution")

	var good: String = objects.path_join("b-valid.drawing")
	check(write_source(good, "shared-source", "Snowman ☃ and Ā"),
		"valid multibyte UTF-8 name saves without normalization")
	check(index.scan(objects).ok and index.entries.size() == 1,
		"malformed duplicate cannot suppress good source identity")
	var good_entry: Dictionary = index.entries[0] if index.entries.size() == 1 else {}
	check(good_entry.get("id") == "shared-source" and \
		good_entry.get("name") == "Snowman ☃ and Ā", "valid Unicode metadata preserved")
	check(good_entry.get("sha256") == FileAccess.get_sha256(good),
		"indexed digest covers exact valid on-disk source bytes")
	check(index.safe_to_open(good_entry) if not good_entry.is_empty() else false,
		"valid Unicode source remains openable")

	check(DirAccess.remove_absolute(malformed) == OK and index.scan(objects).ok and \
		index.entries.size() == 1 and index.warnings.is_empty(),
		"removing malformed source restores clean snapshot")

	var incoming_dir: String = base.path_join("Incoming")
	check(DirAccess.make_dir_recursive_absolute(incoming_dir) == OK,
		"create untrusted incoming directory")
	var incoming: String = incoming_dir.path_join("invalid.drawing")
	check(write_source(incoming, "incoming-malformed", "RejectHere") and \
		replace_one_utf8_byte(incoming, "RejectHere"), "create malformed incoming source")
	var imported: DrawingResult = TRANSFER.import_file(index, incoming)
	check(not imported.ok and imported.code == "SOURCE_UTF8",
		"Import rejects malformed source before publication")
	check(not FileAccess.file_exists(objects.path_join("incoming-malformed.drawing")),
		"failed import leaves no published or partially written source")
	check(index.entries.size() == 1 and index.safe_to_open(index.entries[0]),
		"failed import preserves the prior source authorization")
	var exported: String = incoming_dir.path_join("unicode-export.drawing")
	var copy_result: DrawingResult = TRANSFER.export_file(index, index.entries[0], exported)
	check(copy_result.ok and FileAccess.get_sha256(exported) == FileAccess.get_sha256(good),
		"valid multibyte source still exports byte-for-byte")
	check(remove_tree(base), "isolated fixtures cleaned")
	if failures > 0:
		printerr("T110_UTF8_FAILED: %d/%d checks" % [failures, checks])
		quit(1)
		return
	print("T110_UTF8_PASSED (%d checks, 0 failures)" % checks)
	quit(0)
