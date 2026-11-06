extends SceneTree
## T-058 release-pack witness: the save codec can read original font bytes from
## imported resources even when Godot omits the raw .ttf files from the .pck.

var failures: int = 0


func _check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error("DRAWING_PACK_FONT_FAILED: " + description)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_path: String = "res://addons/drawing/fonts/Lato-Regular.ttf"
	var license: String = "res://addons/drawing/fonts/OFL-1.1.txt"
	var resource: FontFile = load(original_path) as FontFile
	_check(resource != null and resource.get_data().size() > 100000,
		"Release bundle retains exact imported OpenType font bytes")
	_check(not FileAccess.file_exists(original_path),
		"Probe is actually running inside exported resource pack")
	_check(FileAccess.get_file_as_string(license).contains("SIL OPEN FONT LICENSE"),
		"Release bundle includes font redistribution license")
	var drawing: DrawingDocument = DrawingDocument.new("release-fonts", 32)
	var label: DrawingTextElement = DrawingTextElement.new()
	label.content = "Portable café"
	label.position = Vector2i(-17, 29)
	var added: DrawingResult = drawing.commit_text("", label, drawing.revision)
	_check(added.ok, "Text commit works in packaged Drawing engine")
	var encoded: DrawingResult = DrawingFileIO.encode(drawing)
	_check(encoded.ok, "Portable codec encodes from imported FontFile resource")
	if encoded.ok:
		var asset: Dictionary = encoded.value["font_assets"]["lato-regular-v1"]
		_check(Marshalls.base64_to_raw(asset["bytes64"]) == resource.get_data(),
			"Embedded file carries unchanged exact original font bytes")
		_check(asset["license"] == FileAccess.get_file_as_string(license),
			"Saved file carries complete OFL redistribution license")
		var reopened: DrawingResult = DrawingFileIO.decode(encoded.value)
		_check(reopened.ok, "Portable file round-trips inside release bundle")
		if reopened.ok:
			_check((reopened.value as DrawingDocument).list_children().size() == 1,
				"Reopened release document retains its single editable text layer")
	print("DRAWING_PACK_FONT_PASSED (%d failures)" % failures)
	quit(0 if failures == 0 else 1)
