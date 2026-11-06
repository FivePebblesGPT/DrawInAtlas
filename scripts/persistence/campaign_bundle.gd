class_name AtlasCampaignBundle
extends RefCounted
## T-066: one authoritative atomic JSON root per campaign. Immutable generations
## contain the existing validated metadata scene and sparse Drawing manifests.
## No cross-file rename is treated as an atomic transaction.

const ROOT_SCHEMA: String = "atlas-campaign-root-v1"
const GENERATION_SCHEMA: String = "atlas-campaign-generation-v1"
const MAX_INDEX_BYTES: int = 16777216
const MAX_SCENE_BYTES: int = 134217728
const MAX_DOCUMENTS: int = 100000
const MAX_ASSETS: int = 10000


static func root_path(path: String) -> String:
	return path.trim_suffix(".scn") + ".atlas.json"


static func backup_path(path: String) -> String:
	return path.trim_suffix(".scn") + ".atlas.bak.json"


static func _base(path: String) -> String:
	return path.get_base_dir()


static func _hash(data: PackedByteArray) -> String:
	return DrawingBundleManifest._hash(data)


static func _hex(value: Variant) -> bool:
	return value is String and DrawingChunkStore.valid_digest(value)


static func _safe(root: String, relative: String) -> bool:
	if not root.is_absolute_path() or relative.is_empty() or relative.begins_with("/") or relative.contains("\\"):
		return false
	var components: PackedStringArray = relative.split("/")
	var current: String = root
	var parent: DirAccess = DirAccess.open(root.get_base_dir())
	if parent != null and parent.is_link(root.get_file()):
		return false
	for part: String in components:
		if part.is_empty() or part == "." or part == ".." or part.contains(":"):
			return false
		parent = DirAccess.open(current)
		if parent != null and parent.is_link(part):
			return false
		current = current.path_join(part)
	return true


static func _parse_json(data: PackedByteArray) -> Variant:
	# Invalid/crash-interrupted JSON is a normal recovery input, not a script error.
	var parser: JSON = JSON.new()
	return parser.data if parser.parse(data.get_string_from_utf8()) == OK else null


static func _read_json(path: String, limit: int = MAX_INDEX_BYTES) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > limit:
		return null
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return _parse_json(data)


static func _stage(relative: String, bytes: PackedByteArray, directory: String, io: AtlasStoreIO) -> DrawingResult:
	if not _safe(directory, relative):
		return DrawingResult.failure("PATH", "Unsafe project-relative path: " + relative)
	var destination: String = directory.path_join(relative)
	if FileAccess.file_exists(destination):
		return DrawingResult.success() if FileAccess.get_file_as_bytes(destination) == bytes else DrawingResult.failure("COLLISION", "Immutable file has changed: " + relative)
	var error: Error = io.make_dir(destination.get_base_dir())
	if error != OK:
		return DrawingResult.failure("WRITE", "Cannot create directory for " + relative)
	var pending: String = destination + ".pending-" + DrawingDocument.new_id()
	error = io.write_bytes(pending, bytes)
	if error != OK:
		return DrawingResult.failure("WRITE", "Could not write " + relative)
	if io.read_bytes(pending) != bytes:
		return DrawingResult.failure("VERIFY", "Staged bytes changed for " + relative)
	if FileAccess.file_exists(destination):
		return DrawingResult.success() if FileAccess.get_file_as_bytes(destination) == bytes else DrawingResult.failure("COLLISION", "Concurrent immutable-file conflict")
	error = io.rename(pending, destination)
	if error != OK:
		return DrawingResult.failure("WRITE", "Could not publish " + relative)
	return DrawingResult.success() if FileAccess.get_file_as_bytes(destination) == bytes else DrawingResult.failure("VERIFY", "Published file changed")


static func _read_ref(directory: String, record: Variant, prefix: String, limit: int) -> DrawingResult:
	if not record is Dictionary or not record.get("path") is String or not _hex(record.get("sha256")):
		return DrawingResult.failure("MANIFEST", "Malformed generation file reference")
	var path: String = record["path"]
	if not path.begins_with(prefix) or not _safe(directory, path):
		return DrawingResult.failure("PATH", "Unsafe generation file reference")
	var full: String = directory.path_join(path)
	var file: FileAccess = FileAccess.open(full, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > limit:
		return DrawingResult.failure("MISSING", "Missing or oversized file: " + path)
	var content: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if _hash(content) != record["sha256"]:
		return DrawingResult.failure("CORRUPT", "Changed file: " + path)
	return DrawingResult.success(content)


static func _ref(relative: String, bytes: PackedByteArray) -> Dictionary:
	return {"path": relative, "sha256": _hash(bytes)}


static func _verify_objects(index: Dictionary, directory: String) -> DrawingResult:
	if index.get("schema") != AtlasObjectLibrary.SCHEMA or not index.get("assets") is Array \
			or not index.get("instances") is Array or index["assets"].size() > MAX_ASSETS:
		return DrawingResult.failure("OBJECTS", "Malformed Object Asset index")
	for record: Variant in index["assets"]:
		if not record is Dictionary or not DrawingDocument.valid_identifier(str(record.get("id", ""))) \
				or not AtlasObjectLibrary._integer(record.get("revision")) or not _hex(record.get("sha256")):
			return DrawingResult.failure("OBJECTS", "Malformed asset record")
		var relative: String = "Objects/%s/v%06d.drawing" % [record["id"], record["revision"]]
		if record.get("path") != relative:
			return DrawingResult.failure("OBJECTS", "Object Asset path is not canonical")
		var checked: DrawingResult = _read_ref(directory, record, "Objects/", DrawingFileIO.MAX_FILE_BYTES)
		if not checked.ok:
			return checked
	return DrawingResult.success()


static func _fonts_for_documents(documents: Dictionary, object_index: Dictionary,
		directory: String, io: AtlasStoreIO) -> DrawingResult:
	var required: Dictionary = {}
	for manifest: Dictionary in documents.values():
		for record: Dictionary in manifest.get("layers", []):
			var element: Variant = record.get("text_element")
			if element is Dictionary:
				required[str(element.get("font_id", ""))] = true
	# Independent Object source files already bundle fonts; also materialize
	# their licensed bytes under Fonts/ for the complete portable project.
	for asset: Dictionary in object_index.get("assets", []):
		var absolute: String = directory.path_join(asset["path"])
		var content: Variant = _read_json(absolute, DrawingFileIO.MAX_FILE_BYTES)
		if not content is Dictionary or not content.get("font_assets", {}) is Dictionary:
			return DrawingResult.failure("FONT", "Invalid Object source font data")
		for font_id: String in content["font_assets"]:
			required[font_id] = true
	var references: Dictionary = {}
	if required.is_empty():
		return DrawingResult.success(references)
	var license: PackedByteArray = FileAccess.get_file_as_bytes("res://addons/drawing/fonts/OFL-1.1.txt")
	if license.is_empty():
		return DrawingResult.failure("FONT_LICENSE", "Missing redistributable font license")
	var license_path: String = "Fonts/OFL-1.1.txt"
	var saved_license: DrawingResult = _stage(license_path, license, directory, io)
	if not saved_license.ok:
		return saved_license
	references["license"] = _ref(license_path, license)
	for id: String in required:
		if not DrawingDocument.valid_identifier(id):
			return DrawingResult.failure("FONT", "Invalid font name")
		var status: DrawingResult = DrawingTextRaster.font_status(id)
		if not status.ok:
			return status
		var data: PackedByteArray = (status.value as FontFile).get_data()
		if data.is_empty():
			return DrawingResult.failure("FONT", "Bundled font has no bytes")
		var path: String = "Fonts/%s.ttf" % id
		var written: DrawingResult = _stage(path, data, directory, io)
		if not written.ok:
			return written
		references[id] = _ref(path, data)
	return DrawingResult.success(references)


static func save(campaign: AtlasCampaign, registry: AtlasDrawingRegistry,
		library: AtlasObjectLibrary, path: String, injection: AtlasStoreIO = null) -> DrawingResult:
	if campaign == null or registry == null or not path.ends_with(".scn") or not path.is_absolute_path():
		return DrawingResult.failure("PATH", "An absolute .scn campaign path is required")
	var directory: String = _base(path)
	var head_path: String = root_path(path)
	var observed: String = _hash(FileAccess.get_file_as_bytes(head_path)) if FileAccess.file_exists(head_path) else ""
	if observed != registry._loaded_root_digest:
		return DrawingResult.failure("STALE_ROOT", "Campaign root was changed by another editor; reopen it")
	var io: AtlasStoreIO = injection if injection != null else AtlasStoreIO.new()
	if not _safe(directory, "Drawings/generations") or not _safe(directory, "Objects") or not _safe(directory, "Fonts"):
		return DrawingResult.failure("PATH", "Unsafe project directory")
	var aligned: DrawingResult = registry.attach_campaign(campaign)
	if not aligned.ok:
		return aligned
	var native: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	if native == null:
		return DrawingResult.failure("CAMPAIGN", "Campaign metadata cannot be encoded")
	var scene: PackedByteArray = io.encode_scene(native)
	if scene.is_empty() or scene.size() > MAX_SCENE_BYTES \
			or AtlasCampaignStore._validate_bytes(scene, path, io).error != OK:
		return DrawingResult.failure("CAMPAIGN", "Campaign scene cannot be verified")
	var generation: String = DrawingDocument.new_id()
	var prefix: String = "Drawings/generations/%s/" % generation
	var chunk_store: DrawingChunkStore = DrawingChunkStore.new(directory.path_join("Drawings"))
	var live_refs: Dictionary = {}
	var docs: Dictionary = {}
	var seen: Dictionary = {}
	for saved_map: Dictionary in registry.export_index()["maps"]:
		for floor: Dictionary in saved_map["floors"]:
			for detail: Dictionary in floor["details"]:
				seen[detail["document_id"]] = true
	# Retain references to never-opened documents; do not allocate their pixels.
	for id: String in registry._persistent_refs:
		if seen.has(id):
			docs[id] = registry._persistent_refs[id].duplicate(true)
	var checked_manifests: Dictionary = {}
	for document: DrawingDocument in registry._documents.values():
		if not seen.has(document.id):
			continue
		if not document.is_dirty() and docs.has(document.id):
			continue
		var exported: DrawingResult = DrawingBundleManifest.encode(document)
		if not exported.ok:
			return exported
		var manifest: Dictionary = exported.value["manifest"]
		var published: Dictionary[String, String] = {}
		for record: Dictionary in manifest["layers"]:
			for chunk: Dictionary in record["chunks"]:
				var ref: String = chunk["ref"]
				if ref.is_empty():
					var coords: Array = chunk["coord"]
					var fetched: DrawingResult = document.request_chunk_at(record["id"], int(coords[0]), int(coords[1]))
					if not fetched.ok or fetched.value == null:
						return DrawingResult.failure("MISSING_TILE", "Edited tile has no pixels")
					var committed: DrawingResult = chunk_store.stage((fetched.value as DrawingRasterTile).to_rgba8(), document.tile_stride, io)
					if not committed.ok:
						return committed
					ref = committed.value
					chunk["ref"] = ref
					published[record["id"] + ":" + coords[0] + "," + coords[1]] = ref
				elif not chunk_store.read(ref, document.tile_stride) is PackedByteArray:
					return DrawingResult.failure("CORRUPT_TILE", "Unchanged tile blob is missing or damaged")
				if ref != chunk["sha256"]:
					return DrawingResult.failure("DIGEST", "Canonical chunk digest mismatch")
		# Re-encode after assigning all immutable physical refs.
		var bytes: PackedByteArray = JSON.stringify(manifest, "", true, true).to_utf8_buffer()
		if bytes.size() > DrawingBundleManifest.MAX_MANIFEST_BYTES:
			return DrawingResult.failure("MANIFEST_LIMIT", "Document manifest too large")
		var digest: String = _hash(bytes)
		var manifest_path: String = "Drawings/manifests/%s/%s.json" % [document.id, digest]
		var written: DrawingResult = _stage(manifest_path, bytes, directory, io)
		if not written.ok:
			return written
		docs[document.id] = _ref(manifest_path, bytes)
		checked_manifests[document.id] = manifest
		live_refs[document.id] = {"document": document, "revision": document.revision, "refs": published}
	if docs.size() > MAX_DOCUMENTS:
		return DrawingResult.failure("DOC_LIMIT", "Too many Drawing documents")
	var objects: Dictionary = library.export_index() if library != null else {"schema": AtlasObjectLibrary.SCHEMA, "assets": [], "instances": []}
	var valid_objects: DrawingResult = _verify_objects(objects, directory)
	if not valid_objects.ok:
		return valid_objects
	# Carry font resources even when all text documents stayed unloaded/clean.
	for saved_id: String in docs:
		if checked_manifests.has(saved_id):
			continue
		var saved_doc: DrawingResult = _read_ref(directory, docs[saved_id], "Drawings/manifests/", DrawingBundleManifest.MAX_MANIFEST_BYTES)
		if not saved_doc.ok:
			return saved_doc
		var existing: Variant = _parse_json(saved_doc.value)
		if not existing is Dictionary:
			return DrawingResult.failure("MANIFEST", "Invalid saved document metadata")
		checked_manifests[saved_id] = existing
	var fonts: DrawingResult = _fonts_for_documents(checked_manifests, objects, directory, io)
	if not fonts.ok:
		return fonts
	# Record physical compressed-blob checksums so startup can validate the
	# complete generation without decoding or allocating every raster tile.
	var blobs: Dictionary = {}
	for saved_id: String in checked_manifests:
		var metadata: Dictionary = checked_manifests[saved_id]
		var populated: bool = false
		for node: Dictionary in metadata.get("layers", []):
			if not node.get("chunks", []).is_empty() or node.get("text_element") != null or not node.get("objects", {}).is_empty():
				populated = true
				break
		docs[saved_id]["blank"] = not populated
	for metadata: Dictionary in checked_manifests.values():
		var stride: int = int(metadata.get("tile_stride", 0))
		if stride <= 0 or stride > DrawingChunkStore.MAX_STRIDE:
			return DrawingResult.failure("STRIDE", "Invalid saved document tile size")
		for record: Dictionary in metadata.get("layers", []):
			for chunk: Dictionary in record.get("chunks", []):
				var ref: String = chunk.get("ref", "")
				if not _hex(ref) or ref != chunk.get("sha256"):
					return DrawingResult.failure("DIGEST", "Saved chunk digest mismatch")
				if blobs.has(ref):
					if blobs[ref]["stride"] != stride:
						return DrawingResult.failure("STRIDE", "Digest reused with different geometry")
					continue
				var relative: String = chunk_store.relative_path(ref)
				if not _safe(directory, relative) or not FileAccess.file_exists(directory.path_join(relative)):
					return DrawingResult.failure("MISSING_TILE", "Referenced compressed chunk is missing")
				var compressed_sha: String = FileAccess.get_sha256(directory.path_join(relative))
				if not _hex(compressed_sha):
					return DrawingResult.failure("CORRUPT_TILE", "Cannot checksum referenced chunk")
				blobs[ref] = {"path": relative, "sha256": compressed_sha, "stride": stride}
	var index: Dictionary = {"schema": GENERATION_SCHEMA, "generation": generation,
		"campaign": {}, "registry": {}, "objects": {}, "documents": docs,
		"blobs": blobs, "fonts": fonts.value}
	for named: String in ["campaign", "registry", "objects"]:
		var content: PackedByteArray = PackedByteArray()
		var suffix: String = ""
		match named:
			"campaign":
				content = scene
				suffix = "campaign.scn"
			"registry":
				content = JSON.stringify(registry.export_index(), "", true, true).to_utf8_buffer()
				suffix = "registry.json"
			"objects":
				content = JSON.stringify(objects, "", true, true).to_utf8_buffer()
				suffix = "objects.json"
		var relative: String = prefix + suffix
		var staged: DrawingResult = _stage(relative, content, directory, io)
		if not staged.ok:
			return staged
		index[named] = _ref(relative, content)
	var generation_bytes: PackedByteArray = JSON.stringify(index, "", true, true).to_utf8_buffer()
	if generation_bytes.size() > MAX_INDEX_BYTES:
		return DrawingResult.failure("INDEX_LIMIT", "Generation index is too large")
	var generation_path: String = prefix + "generation.json"
	var staged_index: DrawingResult = _stage(generation_path, generation_bytes, directory, io)
	if not staged_index.ok:
		return staged_index
	# Verify *all* references before a new authoritative root can reference them.
	var examined: DrawingResult = _verify_generation(directory, _ref(generation_path, generation_bytes), io)
	if not examined.ok:
		return examined
	var new_root: PackedByteArray = JSON.stringify({"schema": ROOT_SCHEMA,
		"generation": generation, "index": _ref(generation_path, generation_bytes)}, "", true, true).to_utf8_buffer()
	var saved_head: AtlasStoreResult = AtlasCampaignBundle.load(path, io)
	# Never publish atop a corrupt root unless its backup is independently recoverable.
	if FileAccess.file_exists(head_path) and saved_head.error != OK:
		return DrawingResult.failure("ROOT", "Existing root is corrupt and cannot be safely replaced")
	if not _safe(directory, head_path.get_file()) or not _safe(directory, backup_path(path).get_file()):
		return DrawingResult.failure("PATH", "Unsafe campaign root")
	var pending: String = head_path + ".pending-" + DrawingDocument.new_id()
	var error: Error = io.write_bytes(pending, new_root)
	if error != OK or io.read_bytes(pending) != new_root:
		return DrawingResult.failure("WRITE", "Could not stage authoritative root")
	if FileAccess.file_exists(head_path):
		var old: PackedByteArray = io.read_bytes(head_path)
		# If load recovered the backup, don't overwrite that last known-good backup.
		if not saved_head.recovered:
			var backup_pending: String = backup_path(path) + ".pending-" + DrawingDocument.new_id()
			error = io.write_bytes(backup_pending, old)
			if error != OK or io.read_bytes(backup_pending) != old:
				return DrawingResult.failure("WRITE", "Could not stage recovery root")
			error = io.rename(backup_pending, backup_path(path))
			if error != OK:
				return DrawingResult.failure("WRITE", "Could not publish recovery root")
	var current_root: String = _hash(io.read_bytes(head_path)) if FileAccess.file_exists(head_path) else ""
	if current_root != observed:
		return DrawingResult.failure("STALE_ROOT", "Campaign root changed during generation staging")
	error = io.rename(pending, head_path)
	if error != OK:
		return DrawingResult.failure("WRITE", "Could not atomically publish root")
	# The pointer commit is the only publication point; only now mark savepoints.
	registry._persistent_refs = docs.duplicate(true)
	registry._loaded_root_digest = _hash(new_root)
	for record: Dictionary in live_refs.values():
		var published_doc: DrawingDocument = record["document"]
		var completed: DrawingResult = published_doc.mark_published(record["revision"], record["refs"])
		if not completed.ok:
			return DrawingResult.failure("SAVEPOINT", "Committed bytes, but local edit revision changed")
	return DrawingResult.success({"generation": generation, "document_count": docs.size(),
		"new_manifests": live_refs.size()})


static func _verify_generation(directory: String, pointer: Dictionary, io: AtlasStoreIO) -> DrawingResult:
	var found: DrawingResult = _read_ref(directory, pointer, "Drawings/generations/", MAX_INDEX_BYTES)
	if not found.ok:
		return found
	var parsed: Variant = _parse_json(found.value)
	if not parsed is Dictionary or parsed.get("schema") != GENERATION_SCHEMA or \
			not DrawingDocument.valid_identifier(str(parsed.get("generation", ""))) or \
			not parsed.get("documents") is Dictionary or parsed["documents"].size() > MAX_DOCUMENTS:
		return DrawingResult.failure("INDEX", "Invalid generation index")
	var index: Dictionary = parsed
	var generation_dir: String = "Drawings/generations/%s/" % index["generation"]
	if pointer["path"] != generation_dir + "generation.json":
		return DrawingResult.failure("INDEX", "Generation pointer mismatch")
	var scene: DrawingResult = _read_ref(directory, index.get("campaign"), generation_dir, MAX_SCENE_BYTES)
	if not scene.ok:
		return scene
	var campaign_result: AtlasStoreResult = AtlasCampaignStore._validate_bytes(scene.value, "bundle.scn", io)
	if campaign_result.error != OK:
		return DrawingResult.failure("CAMPAIGN", "Invalid campaign scene in generation")
	var meta: DrawingResult = _read_ref(directory, index.get("registry"), generation_dir, MAX_INDEX_BYTES)
	if not meta.ok:
		return meta
	var registry_index: Variant = _parse_json(meta.value)
	if not registry_index is Dictionary:
		return DrawingResult.failure("REGISTRY", "Invalid Drawing mapping index")
	var restored: DrawingResult = AtlasDrawingRegistry.from_index(registry_index, campaign_result.campaign)
	if not restored.ok:
		return restored
	var object_bytes: DrawingResult = _read_ref(directory, index.get("objects"), generation_dir, MAX_INDEX_BYTES)
	if not object_bytes.ok:
		return object_bytes
	var objects: Variant = _parse_json(object_bytes.value)
	if not objects is Dictionary:
		return DrawingResult.failure("OBJECTS", "Invalid Object Asset registry")
	var object_files: DrawingResult = _verify_objects(objects, directory)
	if not object_files.ok:
		return object_files
	var documents: Dictionary = index["documents"]
	var physical: Variant = index.get("blobs")
	if not physical is Dictionary or physical.size() > DrawingBundleManifest.MAX_CHUNKS:
		return DrawingResult.failure("BLOBS", "Invalid compressed chunk index")
	var chunk_store: DrawingChunkStore = DrawingChunkStore.new(directory.path_join("Drawings"))
	# Physical hash verification avoids decoding chunk pixels on project open.
	for ref: String in physical:
		var blob: Variant = physical[ref]
		if not _hex(ref) or not blob is Dictionary or blob.get("path") != chunk_store.relative_path(ref) \
				or not _hex(blob.get("sha256")) or not AtlasDrawingRegistry._integral(blob.get("stride"), 1, 2048):
			return DrawingResult.failure("BLOBS", "Invalid physical chunk descriptor")
		var path: String = directory.path_join(blob["path"])
		if not _safe(directory, blob["path"]) or not FileAccess.file_exists(path) \
				or FileAccess.get_sha256(path) != blob["sha256"]:
			return DrawingResult.failure("CORRUPT_TILE", "Missing/corrupt compressed chunk: " + ref)
	var ids: Dictionary = {}
	for saved_map: Dictionary in registry_index["maps"]:
		for floor: Dictionary in saved_map["floors"]:
			for detail: Dictionary in floor["details"]:
				ids[detail["document_id"]] = detail
	for doc_id: String in documents:
		if not ids.has(doc_id):
			return DrawingResult.failure("DOCUMENT", "Orphan document manifest")
		var entry: Variant = documents[doc_id]
		if not entry is Dictionary or not _hex(entry.get("sha256")) or \
				entry.get("path") != "Drawings/manifests/%s/%s.json" % [doc_id, entry.get("sha256", "")]:
			return DrawingResult.failure("DOCUMENT", "Noncanonical document path")
		var encoded: DrawingResult = _read_ref(directory, entry, "Drawings/manifests/", DrawingBundleManifest.MAX_MANIFEST_BYTES)
		if not encoded.ok:
			return encoded
		var loader: Callable = func(ref: String) -> Variant:
			return chunk_store.read(ref, ids[doc_id]["stride"])
		var opened: DrawingResult = DrawingBundleManifest.decode(encoded.value, loader)
		if not opened.ok:
			return opened
		var document: DrawingDocument = opened.value
		if document.id != doc_id or document.tile_stride != ids[doc_id]["stride"] \
				or document.density_numerator != ids[doc_id]["num"] or document.density_denominator != ids[doc_id]["den"]:
			return DrawingResult.failure("DOCUMENT", "Document metadata conflicts with map/detail identity")
		for record: Dictionary in document.export_manifest().value["layers"]:
			for chunk: Dictionary in record["chunks"]:
				var ref: String = chunk["ref"]
				if not _hex(ref) or ref != chunk["sha256"] or not physical.has(ref) \
						or int(physical[ref]["stride"]) != document.tile_stride:
					return DrawingResult.failure("CORRUPT_TILE", "Generation references an unverified chunk")
	# The license and font payload digests are part of the same root generation.
	var fonts: Variant = index.get("fonts", {})
	if not fonts is Dictionary:
		return DrawingResult.failure("FONTS", "Invalid font references")
	for name: String in fonts:
		if name != "license" and not DrawingDocument.valid_identifier(name):
			return DrawingResult.failure("FONTS", "Invalid portable font name")
		var suffix: String = "Fonts/OFL-1.1.txt" if name == "license" else "Fonts/%s.ttf" % name
		if not fonts[name] is Dictionary or fonts[name].get("path") != suffix:
			return DrawingResult.failure("FONTS", "Invalid portable font record")
		var file_check: DrawingResult = _read_ref(directory, fonts[name], "Fonts/", 16777216)
		if not file_check.ok:
			return file_check
		var expected: PackedByteArray = PackedByteArray()
		if name == "license":
			expected = FileAccess.get_file_as_bytes("res://addons/drawing/fonts/OFL-1.1.txt")
		else:
			var font: DrawingResult = DrawingTextRaster.font_status(name)
			if not font.ok:
				return font
			expected = (font.value as FontFile).get_data()
		if file_check.value != expected:
			return DrawingResult.failure("FONT_VERSION", "Portable font/license changed from bundled source")
	return DrawingResult.success({"campaign": campaign_result.campaign,
		"registry_index": registry_index, "objects": objects,
		"documents": documents, "chunk_store": chunk_store,
		"generation": index["generation"]})


static func load(path: String, injection: AtlasStoreIO = null) -> AtlasStoreResult:
	if not path.ends_with(".scn") or not path.is_absolute_path():
		return AtlasStoreResult.failure(ERR_INVALID_PARAMETER, "Expected absolute .scn path", path)
	var io: AtlasStoreIO = injection if injection != null else AtlasStoreIO.new()
	var head: AtlasStoreResult = _load_one(path, root_path(path), io)
	if head.error == OK:
		return head
	var backup: AtlasStoreResult = _load_one(path, backup_path(path), io)
	if backup.error == OK:
		backup.recovered = true
		backup.message = "Recovered previous complete generation; head: " + head.message
		return backup
	return AtlasStoreResult.failure(head.error, "Head: %s; backup: %s" % [head.message, backup.message], path)


static func _load_one(path: String, pointer_file: String, io: AtlasStoreIO) -> AtlasStoreResult:
	if not FileAccess.file_exists(pointer_file):
		return AtlasStoreResult.failure(ERR_FILE_NOT_FOUND, "Missing " + pointer_file, path)
	var parsed: Variant = _read_json(pointer_file)
	if not parsed is Dictionary or parsed.get("schema") != ROOT_SCHEMA or \
			not DrawingDocument.valid_identifier(str(parsed.get("generation", ""))):
		return AtlasStoreResult.failure(ERR_FILE_CORRUPT, "Invalid root pointer", path)
	var verified: DrawingResult = _verify_generation(_base(path), parsed.get("index", {}), io)
	if not verified.ok or verified.value["generation"] != parsed["generation"]:
		return AtlasStoreResult.failure(ERR_FILE_CORRUPT,
			verified.message if not verified.ok else "Generation identity changed", path)
	var data: Dictionary = verified.value
	var registry_loaded: DrawingResult = AtlasDrawingRegistry.from_index(data["registry_index"], data["campaign"])
	if not registry_loaded.ok:
		return AtlasStoreResult.failure(ERR_FILE_CORRUPT, registry_loaded.message, path)
	var registry: AtlasDrawingRegistry = registry_loaded.value
	registry._persistent_refs = data["documents"].duplicate(true)
	registry._loaded_root_digest = _hash(FileAccess.get_file_as_bytes(root_path(path))) if FileAccess.file_exists(root_path(path)) else ""
	var chunk_store: DrawingChunkStore = data["chunk_store"]
	var base: String = _base(path)
	var load_document: Callable = func(id: String) -> DrawingResult:
		var reference: Dictionary = registry._persistent_refs.get(id, {})
		if reference.is_empty():
			return DrawingResult.failure("DOCUMENT", "Unknown saved Drawing source")
		var content: DrawingResult = _read_ref(base, reference, "Drawings/manifests/", DrawingBundleManifest.MAX_MANIFEST_BYTES)
		if not content.ok:
			return content
		var normalized: Dictionary = registry._stored_detail(id)
		var provider: Callable = func(digest: String) -> Variant:
			return chunk_store.read(digest, normalized["stride"])
		return DrawingBundleManifest.decode(content.value, provider)
	registry._lazy_document_loader = load_document
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var objects_loaded: DrawingResult = library.load_snapshot(data["objects"])
	if not objects_loaded.ok:
		return AtlasStoreResult.failure(ERR_FILE_CORRUPT, objects_loaded.message, path)
	var result: AtlasStoreResult = AtlasStoreResult.new()
	result.campaign = data["campaign"]
	result.registry = registry
	result.library = library
	result.generation = data["generation"]
	result.source_path = pointer_file
	return result
