class_name DrawingChunkStore
extends RefCounted
## Generic immutable content-addressed RGBA8 blob store; one shared package.
## Compression is physical, while each document owns its versioned tile stride.

const MAX_STRIDE: int = 2048
const CACHE_LIMIT_BYTES: int = 32 * 1024 * 1024
const CACHE_LIMIT_ENTRIES: int = 64

var root: String = ""
var _cache: Dictionary[String, PackedByteArray] = {}
var _order: Array[String] = []
var _bytes_cached: int = 0


func _init(root_directory: String = "") -> void:
	root = root_directory


static func valid_digest(digest: String) -> bool:
	return digest.length() == 64 and digest == digest.to_lower() and digest.is_valid_hex_number(false)


func relative_path(digest: String) -> String:
	if not valid_digest(digest):
		return ""
	return "Drawings/chunks/%s/%s.zst" % [digest.substr(0, 2), digest]


func absolute_path(digest: String) -> String:
	return root.path_join("chunks").path_join(digest.substr(0, 2)).path_join(digest + ".zst") if valid_digest(digest) else ""


func _unsafe_path(digest: String) -> bool:
	if not valid_digest(digest) or not root.is_absolute_path():
		return true
	var components: Array[String] = [root.get_base_dir(), root, root.path_join("chunks"), root.path_join("chunks").path_join(digest.substr(0, 2))]
	for folder: String in components:
		var parent: DirAccess = DirAccess.open(folder.get_base_dir())
		if parent != null and parent.is_link(folder.get_file()):
			return true
	var directory: DirAccess = DirAccess.open(root.path_join("chunks").path_join(digest.substr(0, 2)))
	return directory != null and directory.is_link(digest + ".zst")


func stage(bytes: PackedByteArray, stride: int, storage: RefCounted = null) -> DrawingResult:
	if stride < 1 or stride > MAX_STRIDE or bytes.size() != stride * stride * 4:
		return DrawingResult.failure("STRIDE", "Invalid canonical RGBA8 tile")
	var digest: String = DrawingRasterTile.digest_rgba8(bytes, stride)
	if digest.is_empty() or _unsafe_path(digest):
		return DrawingResult.failure("PATH", "Unsafe Drawing chunk path")
	var path: String = absolute_path(digest)
	if FileAccess.file_exists(path):
		var verified: Variant = read(digest, stride)
		return DrawingResult.success(digest) if verified is PackedByteArray else DrawingResult.failure("CORRUPT_TILE", "Existing immutable chunk is corrupt")
	var compressed: PackedByteArray = bytes.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty():
		return DrawingResult.failure("COMPRESS", "Unable to compress canonical tile")
	var error: Error = storage.call("make_dir", path.get_base_dir()) if storage != null else DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return DrawingResult.failure("WRITE", "Cannot create chunk directory")
	var pending: String = path + ".pending-" + DrawingDocument.new_id()
	error = storage.call("write_bytes", pending, compressed) if storage != null else _write(pending, compressed)
	if error != OK:
		return DrawingResult.failure("WRITE", "Cannot stage chunk payload")
	if (storage.call("read_bytes", pending) if storage != null else FileAccess.get_file_as_bytes(pending)) != compressed or _unsafe_path(digest):
		return DrawingResult.failure("VERIFY", "Staged chunk changed")
	# Never overwrite an immutable blob, even when racing another generation.
	if FileAccess.file_exists(path):
		return DrawingResult.success(digest) if read(digest, stride) is PackedByteArray else DrawingResult.failure("COLLISION", "Concurrent chunk is invalid")
	error = storage.call("rename", pending, path) if storage != null else DirAccess.rename_absolute(pending, path)
	if error != OK:
		return DrawingResult.failure("WRITE", "Cannot publish chunk payload")
	return DrawingResult.success(digest) if read(digest, stride) is PackedByteArray else DrawingResult.failure("VERIFY", "Published chunk failed verification")


func read(digest: String, stride: int) -> Variant:
	if stride < 1 or stride > MAX_STRIDE or _unsafe_path(digest):
		return null
	if _cache.has(digest):
		_touch(digest)
		return _cache[digest].duplicate()
	var path: String = absolute_path(digest)
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > stride * stride * 4 + 65536:
		return null
	var packed: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var bytes: PackedByteArray = packed.decompress(stride * stride * 4, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != stride * stride * 4 or DrawingRasterTile.digest_rgba8(bytes, stride) != digest:
		return null
	_cache[digest] = bytes
	_order.append(digest)
	_bytes_cached += bytes.size()
	while _bytes_cached > CACHE_LIMIT_BYTES or _order.size() > CACHE_LIMIT_ENTRIES:
		var oldest: String = _order.pop_front()
		_bytes_cached -= _cache[oldest].size()
		_cache.erase(oldest)
	return bytes.duplicate()


func invalidate() -> void:
	_cache.clear()
	_order.clear()
	_bytes_cached = 0


func _touch(digest: String) -> void:
	_order.erase(digest)
	_order.append(digest)


static func _write(path: String, bytes: PackedByteArray) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var okay: bool = file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error if okay else ERR_FILE_CANT_WRITE
