class_name AtlasCampaignStore
extends RefCounted

## One embedded native .scn campaign, with adjacent validated recovery generation.
## Pending files are never load candidates. Legacy JSON saves remain untouched.
const DEFAULT_PATH: String = "user://drawinatlas_campaign.scn"


static func save_campaign(campaign: AtlasCampaign, path: String = DEFAULT_PATH,
		io: AtlasStoreIO = null) -> Error:
	if campaign == null or not path.ends_with(".scn") or path.is_empty():
		return ERR_INVALID_PARAMETER
	var storage: AtlasStoreIO = io if io != null else AtlasStoreIO.new()
	var scene: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	if scene == null:
		return ERR_INVALID_DATA
	var bytes: PackedByteArray = storage.encode_scene(scene)
	if bytes.is_empty() or _validate_bytes(bytes, path, storage).error != OK:
		return ERR_FILE_CORRUPT
	var error: Error = storage.make_dir(path.get_base_dir())
	if error != OK:
		return error
	var pending: String = _pending_path(path)
	error = _stage(pending, bytes, storage)
	if error != OK:
		return error
	if _load_one(pending, storage).error != OK:
		return ERR_FILE_CORRUPT
	# Only a verified head may become the next backup. If the head is corrupt,
	# preserve any existing valid backup, even when saving a fresh candidate.
	var previous: AtlasStoreResult = _load_one(path, storage)
	if previous.error == OK:
		var backup_pending: String = _backup_pending_path(path)
		error = _stage(backup_pending, storage.read_bytes(path), storage)
		if error != OK:
			return error
		if _load_one(backup_pending, storage).error != OK:
			return ERR_FILE_CORRUPT
		error = storage.rename(backup_pending, _backup_path(path))
		if error != OK:
			return error
	return storage.rename(pending, path)


static func load_campaign(path: String = DEFAULT_PATH, io: AtlasStoreIO = null) -> AtlasCampaign:
	return load_result(path, io).campaign


static func load_result(path: String = DEFAULT_PATH, io: AtlasStoreIO = null) -> AtlasStoreResult:
	if not path.ends_with(".scn"):
		return AtlasStoreResult.failure(ERR_INVALID_PARAMETER, "Expected a .scn campaign", path)
	var storage: AtlasStoreIO = io if io != null else AtlasStoreIO.new()
	var head: AtlasStoreResult = _load_one(path, storage)
	if head.error == OK:
		return head
	var backup: AtlasStoreResult = _load_one(_backup_path(path), storage)
	if backup.error == OK:
		backup.recovered = true
		backup.message = "Recovered backup; head: " + head.message
		return backup
	return AtlasStoreResult.failure(head.error,
		"Head: %s; backup: %s" % [head.message, backup.message], path)


static func _load_one(path: String, storage: AtlasStoreIO) -> AtlasStoreResult:
	if not storage.exists(path):
		return AtlasStoreResult.failure(ERR_FILE_NOT_FOUND, "Missing " + path, path)
	return _validate_bytes(storage.read_bytes(path), path, storage)


static func _validate_bytes(bytes: PackedByteArray, path: String, storage: AtlasStoreIO) -> AtlasStoreResult:
	var scene: PackedScene = storage.decode_scene(bytes)
	if scene == null:
		return AtlasStoreResult.failure(ERR_FILE_CORRUPT, "Invalid native scene at " + path, path)
	var campaign: AtlasCampaign = AtlasNativeScene.unpack_campaign(scene)
	if campaign == null:
		return AtlasStoreResult.failure(ERR_INVALID_DATA, "Invalid native campaign at " + path, path)
	var result: AtlasStoreResult = AtlasStoreResult.new()
	result.campaign = campaign
	result.source_path = path
	return result


static func _stage(path: String, bytes: PackedByteArray, io: AtlasStoreIO) -> Error:
	var error: Error = io.write_bytes(path, bytes)
	if error != OK:
		return error
	return OK if io.read_bytes(path) == bytes else ERR_FILE_CORRUPT


static func _backup_path(path: String) -> String:
	return path.trim_suffix(".scn") + ".bak.scn"


static func _pending_path(path: String) -> String:
	return path.trim_suffix(".scn") + ".pending.scn"


static func _backup_pending_path(path: String) -> String:
	return path.trim_suffix(".scn") + ".bak.pending.scn"
