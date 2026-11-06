extends SceneTree
## Cross-language payload parity for benchmark native libzstd and Godot 4.8.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = ""
	for index: int in range(args.size() - 1):
		if args[index] == "--folder":
			folder = args[index + 1]
	if folder.is_empty():
		push_error("T067_CODECFIXTURE_FAILED: --folder is required")
		quit(1)
		return
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("codec-fixture.json")))
	if not metadata is Dictionary:
		push_error("T067_CODECFIXTURE_FAILED: invalid fixture manifest")
		quit(1)
		return
	var stride: int = metadata["stride"]
	var packed: PackedByteArray = FileAccess.get_file_as_bytes(folder.path_join("codec-fixture.zst"))
	var bytes: PackedByteArray = packed.decompress(stride * stride * 4, FileAccess.COMPRESSION_ZSTD)
	var okay: bool = bytes.size() == int(metadata["decoded_bytes"]) \
		and DrawingRasterTile.digest_rgba8(bytes, stride) == metadata["sha256"] \
		and FileAccess.get_sha256(folder.path_join("codec-fixture.zst")) == metadata["compressed_sha256"]
	if okay:
		var back: PackedByteArray = bytes.compress(FileAccess.COMPRESSION_ZSTD)
		var destination: FileAccess = FileAccess.open(folder.path_join("godot-codec-fixture.zst"), FileAccess.WRITE)
		okay = destination != null and back.size() > 0
		if destination != null:
			destination.store_buffer(back)
			destination.close()
	print("T067_CODEC_%s" % ["PASSED" if okay else "FAILED"])
	if not okay:
		push_error("T067_CODECFIXTURE_FAILED: C codec/Godot native frame mismatch")
	quit(0 if okay else 1)
