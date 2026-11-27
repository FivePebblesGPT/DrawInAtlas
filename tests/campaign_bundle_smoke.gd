extends SceneTree

const TILES: Script = preload("res://addons/drawing/signed_tiles.gd")
## T-066 sparse multi-file generation save, reload and fault recovery witness.

var checks: int = 0
var failures: int = 0
var folder: String = ""
var path: String = ""


class FaultIO extends AtlasStoreIO:
	var reject_root: bool = false
	var reject_generation: bool = false
	var chunk_writes: int = 0
	var file_writes: int = 0
	var renames: int = 0

	func write_bytes(location: String, bytes: PackedByteArray) -> Error:
		file_writes += 1
		if reject_generation and location.contains("/generations/"):
			return ERR_FILE_CANT_WRITE
		if location.ends_with(".zst") or location.contains(".zst.pending-"):
			chunk_writes += 1
		return super.write_bytes(location, bytes)

	func rename(from_path: String, to_path: String) -> Error:
		renames += 1
		if reject_root and to_path.ends_with(".atlas.json"):
			return ERR_FILE_CANT_WRITE
		return super.rename(from_path, to_path)



func _initialize() -> void:
	call_deferred("_run")


func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error("T066_FAILED: " + label)


func _paint(doc: DrawingDocument, layer: String, x: int, y: int, rgba: PackedByteArray) -> bool:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision, Transform2D.IDENTITY, x, y)
	return started.ok and started.value.apply_region(Rect2i(0, 0, 1, 1), rgba).ok and started.value.commit().ok


func _run() -> void:
	folder = OS.get_cache_dir().path_join("t066-" + DrawingDocument.new_id())
	path = folder.path_join("World.scn")
	_check(DirAccess.make_dir_recursive_absolute(folder) == OK, "create independent campaign folder")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	_check(registry.attach_campaign(campaign).ok, "attach canonical registry")
	_check(registry.ensure_detail("world", "ground", 1, 2, 1, 64).ok, "declare blank D1")
	var doc: DrawingDocument = registry.document_at("world", "ground", 0, true).value
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Texture").value)
	_check(_paint(doc, layer, -514, -515, PackedByteArray([12, 34, 56, 0])), "paint signed hidden RGB")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, path)
	_check(saved.ok, "first complete generation: " + saved.code + " " + saved.message)
	if not saved.ok:
		print("BUNDLE_BASIC_FAILURE " + saved.message)
		quit(1)
		return
	_check(not doc.is_dirty(), "published document savepoint")
	_check(not FileAccess.file_exists(path), "no stale legacy campaign scene written")
	_check(FileAccess.file_exists(AtlasCampaignBundle.root_path(path)), "authoritative root pointer exists")
	var loaded: AtlasStoreResult = AtlasCampaignBundle.load(path)
	_check(loaded.error == OK and loaded.registry != null and loaded.campaign != null, "load fresh bundle " + loaded.message)
	if loaded.error == OK:
		_check(loaded.registry.document_count() == 0, "document layers loaded lazily")
		var snapshot: DrawingResult = loaded.registry.document_at("world", "ground", 0)
		_check(snapshot.ok and snapshot.value != null, "load D0 on demand: " + snapshot.message)
		if snapshot.ok and snapshot.value != null:
			var sparse: DrawingDocument = snapshot.value
			_check(sparse._native_raster_store == null and sparse._pending_tiles.size() == 1,
				"physical campaign Open retains unresolved sparse source")
			_check(sparse.read_pixel(layer, -514, -515).value == 0x0038220c, "exact hidden RGB across generation")
			if ClassDB.class_exists("DrawingNativeTiles"):
				var store: Object = sparse._native_raster_store
				var key: String = TILES.tile_key64(-514, -515, sparse.tile_stride)
				var coords: PackedStringArray = key.split(",")
				_check(store != null and bool(store.call("has_source", layer, int(coords[0]), int(coords[1]), sparse.revision)) and
					sparse._native_source_matches(layer, key, sparse._nodes[layer].tiles.get(key)),
					"first campaign pixel read immediately authorizes native source")
				var manifest: Dictionary = sparse.export_manifest().value
				sparse._trim_sparse_render_sources(DrawingDocument.SPARSE_RENDER_HIGH_WATER_BYTES + 1)
				_check(sparse._pending_tiles.size() == 1 and not bool(store.call("has_source", layer, int(coords[0]), int(coords[1]), sparse.revision)),
					"physical campaign clean source can be released")
				_check(sparse.export_manifest().ok and sparse.export_manifest().value == manifest,
					"released physical campaign source keeps its durable reference")
				_check(sparse.read_pixel(layer, -514, -515).value == 0x0038220c,
					"physical campaign re-admits exact hidden RGB through its blob provider")
				sparse._trim_sparse_render_sources(DrawingDocument.SPARSE_RENDER_HIGH_WATER_BYTES + 1)
				_check(sparse._pending_tiles.size() == 1, "save next generation while source remains pending")
			_check(not sparse.is_dirty() and sparse.history_length() == 0,
				"source admission does not change the campaign savepoint or local history")
		var blank: DrawingResult = loaded.registry.document_at("world", "ground", 1)
		_check(blank.ok and blank.value == null, "unpainted D1 has no document payload")
		_check(loaded.registry.document_count() == 1, "only D0 is resident")
		var again: DrawingResult = AtlasCampaignBundle.save(loaded.campaign, loaded.registry, loaded.library, path)
		_check(again.ok, "save second generation unchanged " + again.message)
		if again.ok:
			if snapshot.ok and snapshot.value != null and ClassDB.class_exists("DrawingNativeTiles"):
				var paged: DrawingDocument = snapshot.value
				_check(paged.read_pixel(layer, -514, -515).value == 0x0038220c and not paged.is_dirty(),
					"released source still resolves after generation publication")
			var reloaded: AtlasStoreResult = AtlasCampaignBundle.load(path)
			_check(reloaded.error == OK and reloaded.generation != loaded.generation, "new root generation loads independently")
			_check(not reloaded.recovered, "new head loads without fallback")
			var valid: DrawingResult = reloaded.registry.document_at("world", "ground", 0)
			_check(valid.ok and valid.value.read_pixel(layer, -514, -515).value == 0x0038220c, "untouched blob preserved")
			# Backup generation remains coherent after losing the new index.
			var head: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AtlasCampaignBundle.root_path(path)))
			var head_index: String = folder.path_join(head["index"]["path"])
			_check(DirAccess.remove_absolute(head_index) == OK, "simulate incomplete active generation")
			var recovered: AtlasStoreResult = AtlasCampaignBundle.load(path)
			_check(recovered.error == OK and recovered.recovered, "recover previous generation after interrupted copy")
			if recovered.error == OK:
				var previous: DrawingResult = recovered.registry.document_at("world", "ground", 0)
				_check(previous.ok and previous.value.read_pixel(layer, -514, -515).value == 0x0038220c, "recovery retains exact pixels")
	_failures_and_sparse()
	_portable_assets_and_fonts()
	_corruption_and_precision()
	print("ATLAS_BUNDLE_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _copy_tree(source: String, dest: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dest) != OK:
		return false
	var directory: DirAccess = DirAccess.open(source)
	if directory == null:
		return false
	for item: String in directory.get_files():
		if DirAccess.copy_absolute(source.path_join(item), dest.path_join(item)) != OK:
			return false
	for item: String in directory.get_directories():
		if not _copy_tree(source.path_join(item), dest.path_join(item)):
			return false
	return true


func _count_blobs(parent: String) -> int:
	var directory: DirAccess = DirAccess.open(parent)
	if directory == null:
		return 0
	var total: int = 0
	for file: String in directory.get_files():
		if file.ends_with(".zst"):
			total += 1
	for child: String in directory.get_directories():
		total += _count_blobs(parent.path_join(child))
	return total


func _failures_and_sparse() -> void:
	var base: String = folder.path_join("fault-work")
	var slot: String = base.path_join("Chaos.scn")
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	_check(registry.attach_campaign(campaign).ok, "isolated failure-test registry attached")
	var doc: DrawingDocument = registry.document_at("world", "ground", 0, true).value
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Signed sparse").value)
	_check(_paint(doc, layer, -5000, 8000, PackedByteArray([4, 5, 6, 0])), "far-world isolated edit")
	_check(_paint(doc, layer, 100000001, -230000001, PackedByteArray([33, 44, 55, 255])), "two distant sparse tiles")
	var count: int = _count_blobs(base.path_join("Drawings/chunks"))
	_check(count == 0, "no pixel files allocated before save")
	var first_io: FaultIO = FaultIO.new()
	var initial_start_usec: int = Time.get_ticks_usec()
	var first: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, slot, first_io)
	var initial_ms: float = float(Time.get_ticks_usec() - initial_start_usec) / 1000.0
	_check(first.ok, "initial sparse generation publishes")
	if not first.ok:
		return
	_check(first_io.chunk_writes == 2, "only two authored tiles staged across huge map")
	_check(_count_blobs(base.path_join("Drawings/chunks")) == 2, "content-addressed sparse file count")
	var failed_io: FaultIO = FaultIO.new()
	failed_io.reject_root = true
	_check(_paint(doc, layer, 100000001, -230000001, PackedByteArray([10, 11, 12, 0])), "change only one sparse tile")
	var fail: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, slot, failed_io)
	_check(not fail.ok and fail.code == "WRITE", "injected atomic-root rename error aborts save")
	_check(doc.is_dirty(), "failed root publication does not mark document saved")
	_check(_count_blobs(base.path_join("Drawings/chunks")) == 3, "only one new chunk staged; orphan is safe")
	var original: AtlasStoreResult = AtlasCampaignBundle.load(slot)
	_check(original.error == OK and not original.recovered, "old head is still completely valid")
	if original.error == OK:
		var loaded: DrawingResult = original.registry.document_at("world", "ground", 0)
		_check(loaded.ok and loaded.value.read_pixel(layer, 100000001, -230000001).value == 0xff372c21,
			"failed publication cannot expose changed pixel")
	var fail_write: FaultIO = FaultIO.new()
	fail_write.reject_generation = true
	var bad_scene: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, slot, fail_write)
	_check(not bad_scene.ok, "failure writing new generation cannot publish a root")
	_check(AtlasCampaignBundle.load(slot).generation == original.generation, "write failure preserves old head")
	var second_io: FaultIO = FaultIO.new()
	var incremental_start_usec: int = Time.get_ticks_usec()
	var second: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, slot, second_io)
	var incremental_ms: float = float(Time.get_ticks_usec() - incremental_start_usec) / 1000.0
	_check(second.ok, "retry successful after injected failures: " + second.message)
	if not second.ok:
		return
	_check(second_io.chunk_writes == 0, "retry reuses verified orphan blob; no redundant encoding")
	_check(not doc.is_dirty(), "successful retry saves latest revision")
	print("T066_BENCHMARK initial_ms=%.3f incremental_ms=%.3f initial_writes=%d incremental_writes=%d initial_renames=%d incremental_renames=%d chunk_count=%d" % [
		initial_ms, incremental_ms, first_io.file_writes, second_io.file_writes,
		first_io.renames, second_io.renames, _count_blobs(base.path_join("Drawings/chunks"))])
	_check(second_io.chunk_writes == 0 and second_io.file_writes < first_io.file_writes,
		"single-tile incremental retry minimizes filesystem writes")
	var two: AtlasStoreResult = AtlasCampaignBundle.load(slot)
	_check(two.error == OK and not two.recovered, "new generation head opens")
	if two.error != OK:
		return
	var third: AtlasStoreResult = AtlasCampaignBundle.load(slot)
	var newer: DrawingDocument = two.registry.document_at("world", "ground", 0).value
	var stale: DrawingDocument = third.registry.document_at("world", "ground", 0).value
	_check(_paint(newer, layer, 100000001, -230000001, PackedByteArray([99, 77, 55, 200])), "first concurrent editor changes current tile")
	_check(AtlasCampaignBundle.save(two.campaign, two.registry, two.library, slot).ok, "first concurrent editor publishes")
	_check(_paint(stale, layer, 100000001, -230000001, PackedByteArray([2, 3, 4, 5])), "other editor makes conflicting local edit")
	var conflicted: DrawingResult = AtlasCampaignBundle.save(third.campaign, third.registry, third.library, slot)
	_check(not conflicted.ok and conflicted.code == "STALE_ROOT" and stale.is_dirty(),
		"stale writer rejected without discarding its draft")
	var fresh: AtlasStoreResult = AtlasCampaignBundle.load(slot)
	_check(fresh.error == OK and fresh.registry.document_at("world", "ground", 0).value.read_pixel(
		layer, 100000001, -230000001).value == 0xc8374d63, "winning writer remains authoritative")
	var unchanged: FaultIO = FaultIO.new()
	var unchanged_result: DrawingResult = AtlasCampaignBundle.save(fresh.campaign, fresh.registry,
		fresh.library, slot, unchanged)
	_check(unchanged_result.ok and unchanged.chunk_writes == 0, "unchanged save writes zero chunk files")


func _portable_assets_and_fonts() -> void:
	var original: String = folder.path_join("portable")
	var path_a: String = original.path_join("Atlas.scn")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	_check(registry.attach_campaign(campaign).ok, "portable registry attached")
	var d0: DrawingDocument = registry.document_at("world", "ground", 0, true).value
	var label: String = String(d0.create_layer(DrawingLayerNode.TEXT, "Title").value)
	_check(d0.set_text(label, "Village 🏠").ok, "editable Unicode text committed")
	var d1id: String = String(registry.ensure_detail("world", "ground", 1, 3, 2, 64).value)
	var d1: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var raster: String = String(d1.create_layer(DrawingLayerNode.RASTER, "Mountain").value)
	_check(_paint(d1, raster, -1, 12, PackedByteArray([111, 55, 22, 0])), "D1 alpha-zero pixels at signed chunk border")
	var source: DrawingDocument = DrawingDocument.new("object-source", 16)
	var source_layer: String = String(source.create_layer(DrawingLayerNode.RASTER, "Object ink").value)
	_check(_paint(source, source_layer, 2, 5, PackedByteArray([200, 100, 50, 255])), "authored Object source independent of Atlas")
	var objects: AtlasObjectLibrary = AtlasObjectLibrary.new(path_a)
	var asset: DrawingResult = objects.create_asset(source, "Shared tower")
	_check(asset.ok, "publish portable Object Asset " + asset.message)
	if not asset.ok:
		return
	var placed: DrawingResult = objects.place(String(asset.value), "world", "ground", "D1",
		Transform2D.IDENTITY)
	_check(placed.ok, "placed linked Object on authored D1")
	var another: DrawingResult = objects.place(String(asset.value), "world", "ground", "D0",
		Transform2D(0.0, Vector2(24.0, -16.0)))
	_check(another.ok, "second linked instance references same source on D0")
	var encoded: DrawingResult = AtlasCampaignBundle.save(campaign, registry, objects, path_a)
	_check(encoded.ok, "store text, raster, Objects and fonts in one generation: " + encoded.message)
	if not encoded.ok:
		return
	_check(FileAccess.file_exists(original.path_join("Fonts/OFL-1.1.txt")), "font license copied to portable folder")
	_check(FileAccess.file_exists(original.path_join("Fonts/lato-regular-v1.ttf")), "font bytes copied to portable folder")
	var destination: String = folder.path_join("renamed-project")
	_check(_copy_tree(original, destination), "copy complete portable bundle to differently named directory")
	var moved: AtlasStoreResult = AtlasCampaignBundle.load(destination.path_join("Atlas.scn"))
	_check(moved.error == OK and not moved.recovered, "moved project loads using relative references: " + moved.message)
	if moved.error != OK:
		return
	_check(moved.library.asset_exists(asset.value), "linked Object source present after move")
	_check(moved.library.instance_info(placed.value)["source_id"] == asset.value,
		"portable Object instance still resolves stable source ID")
	_check(moved.library.instance_info(another.value)["source_id"] == asset.value,
		"second cross-detail instance retains the published source")
	_check(moved.registry.document_count() == 0, "moved project starts without decoded documents")
	var open_d1: DrawingResult = moved.registry.document_at("world", "ground", 1)
	_check(open_d1.ok and open_d1.value.id == d1id, "moved D1 retains stable document identity")
	_check(open_d1.value.read_pixel(raster, -1, 12).value == 0x0016376f, "partial tile hidden RGB survives move")
	var title: DrawingResult = moved.registry.document_at("world", "ground", 0)
	_check(title.ok and title.value.inspect_node(label).text_value == "Village 🏠", "Unicode title survives re-open")
	_check(moved.registry.document_count() == 2, "only requested documents materialized")
	var saved_again: DrawingResult = AtlasCampaignBundle.save(moved.campaign, moved.registry,
		moved.library, destination.path_join("Atlas.scn"))
	_check(saved_again.ok, "moved bundle resaves without reauthoring fonts or documents: " + saved_again.message)
	if saved_again.ok:
		_check(AtlasCampaignBundle.load(destination.path_join("Atlas.scn")).error == OK,
			"reopened second-generation project still validates bundled font and Object source")
	# An incomplete copy with no font is detected; never silently choose a system fallback.
	_check(DirAccess.remove_absolute(destination.path_join("Fonts/lato-regular-v1.ttf")) == OK,
		"simulate incomplete font copy")
	_check(AtlasCampaignBundle.load(destination.path_join("Atlas.scn")).error != OK,
		"incomplete portable bundle rejects missing font data")


func _corruption_and_precision() -> void:
	var directory: String = folder.path_join("corruption")
	var campaign_file: String = directory.path_join("Precise.scn")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	_check(registry.attach_campaign(campaign).ok, "precision registry initialized")
	var doc: DrawingDocument = registry.document_at("world", "ground", 0, true).value
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Signed projection edge").value)
	# The historical >2^53 persistence fixture is no longer a legal tile
	# source: T-158/T-159 bound persisted raster projection to +/-2^52.
	# Stay near both signed ends without crossing the tile-origin boundary.
	var edge: int = TILES.MAX_PROJECTION_PIXEL_COORD - doc.tile_stride * 2 - 1
	var x: int = edge
	var y: int = -edge
	_check(_paint(doc, layer, x, y, PackedByteArray([23, 99, 177, 0])),
		"edit at opposite signed projection edges")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, campaign_file)
	_check(saved.ok, "generation stores valid signed chunk coordinate strings: " + saved.message)
	if not saved.ok:
		return
	var loaded: AtlasStoreResult = AtlasCampaignBundle.load(campaign_file)
	_check(loaded.error == OK, "signed-edge generation reopens")
	if loaded.error == OK:
		var reopened: DrawingResult = loaded.registry.document_at("world", "ground", 0)
		_check(reopened.ok and reopened.value.read_pixel(layer, x, y).value == 0x00b16317,
			"exact positive/negative signed projection-edge pixel survives JSON")
	# Current required-native direct publication rejects unsafe pixels *before*
	# creating an invalid document revision. The prior T-202 witness expected a
	# non-native edit to succeed here and then demanded a failed Save, which is
	# no longer the behavior of this production build.
	var root_path: String = AtlasCampaignBundle.root_path(campaign_file)
	var published_root: String = FileAccess.get_file_as_string(root_path)
	var unsafe_x: int = 9007199254740993
	var unsafe_y: int = -9007199254740993
	var revision_before: int = doc.revision
	var dirty_before: bool = doc.is_dirty()
	var keys_before: Array[String] = doc.tile_keys(layer)
	var started: DrawingResult = doc.begin_edit(layer, revision_before,
		Transform2D.IDENTITY, unsafe_x, unsafe_y)
	_check(started.ok, "legacy signed anchor can still start a gesture")
	if started.ok:
		var staged: DrawingResult = started.value.apply_region(Rect2i(0, 0, 1, 1),
			PackedByteArray([99, 88, 77, 0]))
		var refusal: DrawingResult = staged if not staged.ok else started.value.commit()
		_check(not refusal.ok and refusal.code in ["COORD", "COORD_RANGE"],
			"native direct edit refuses out-of-projection pixels: %s %s" %
			[refusal.code, refusal.message])
		started.value.cancel()
	_check(doc.revision == revision_before and doc.is_dirty() == dirty_before
		and doc.tile_keys(layer) == keys_before,
		"rejected pixel edit leaves source revision, dirtiness and tiles intact")
	_check(FileAccess.get_file_as_string(root_path) == published_root,
		"rejected pixel edit never updates the campaign root")
	# Separately exercise the *cold* save boundary with a deliberately invalid
	# in-memory tile. Public edits can no longer create this state; importing
	# damaged/unauthorized internal projections must still fail closed. Mark a
	# legitimate metadata edit dirty first: clean documents are intentionally
	# reused from their immutable existing manifest without exporting pixels.
	_check(doc.rename_layer(layer, "Signed projection edge (pending)").ok
		and doc.is_dirty(), "pending valid metadata causes an export on Save")
	var dirty_revision: int = doc.revision
	var invalid_key: String = TILES.tile_key64(unsafe_x, unsafe_y, doc.tile_stride)
	doc._nodes[layer].tiles[invalid_key] = DrawingRasterTile.new(doc.tile_stride)
	var rejected: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, campaign_file)
	_check(not rejected.ok and rejected.code in ["COORD_RANGE", "STALE_SOURCE"],
		"save rejects corrupted native-unsafe source: %s %s" %
		[rejected.code, rejected.message])
	_check(doc.is_dirty() and FileAccess.get_file_as_string(root_path) == published_root,
		"rejected save cannot publish or acknowledge a corrupted raster projection")
	doc._nodes[layer].tiles.erase(invalid_key)
	_check(doc.revision == dirty_revision and doc.tile_keys(layer) == keys_before,
		"corruption fixture cleanup restores original authorized pixels")
	_check(doc.export_manifest().ok,
		"rejected cold Save does not poison subsequently authorized manifest export")
	var unchanged: AtlasStoreResult = AtlasCampaignBundle.load(campaign_file)
	_check(unchanged.error == OK and unchanged.registry != null,
		"old signed-edge generation still opens after rejected save")
	if unchanged.error == OK and unchanged.registry != null:
		var surviving: DrawingResult = unchanged.registry.document_at("world", "ground", 0)
		_check(surviving.ok and surviving.value.read_pixel(layer, x, y).value == 0x00b16317,
			"unsafe edit cannot alter published signed-edge bytes")
	var root_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AtlasCampaignBundle.root_path(campaign_file)))
	var gen_path: String = directory.path_join(root_record["index"]["path"])
	var generation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(gen_path))
	var blob_ref: String = generation["blobs"].keys()[0]
	var blob_path: String = directory.path_join(generation["blobs"][blob_ref]["path"])
	var content: PackedByteArray = FileAccess.get_file_as_bytes(blob_path)
	_check(not content.is_empty(), "test fixture has a compressed immutable payload")
	var invalid: PackedByteArray = content.duplicate()
	invalid[0] = invalid[0] ^ 0x3f
	var rewrite: FileAccess = FileAccess.open(blob_path, FileAccess.WRITE)
	if rewrite != null:
		rewrite.store_buffer(invalid)
		rewrite.close()
	_check(AtlasCampaignBundle.load(campaign_file).error == ERR_FILE_CORRUPT,
		"single-generation corrupted physical blob fails closed before exposing document")
	_check(DirAccess.remove_absolute(blob_path) == OK,
		"simulate incomplete copy with missing referenced compressed tile")
	_check(AtlasCampaignBundle.load(campaign_file).error == ERR_FILE_CORRUPT,
		"single-generation missing compressed tile fails closed without transparent fallback")
	# Reject symlink escapes, including a preexisting Drawings directory link.
	var unsafe_root: String = folder.path_join("symlink-test")
	_check(DirAccess.make_dir_recursive_absolute(unsafe_root) == OK, "prepare symlink escape fixture")
	var linked: String = unsafe_root.path_join("Drawings")
	var output: Array = []
	var command_status: int = OS.execute("ln", PackedStringArray(["-s", directory, linked]), output)
	if command_status == 0:
		var linked_registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
		linked_registry.attach_campaign(campaign)
		var refused: DrawingResult = AtlasCampaignBundle.save(campaign, linked_registry, null,
			unsafe_root.path_join("Unsafe.scn"))
		_check(not refused.ok and refused.code == "PATH", "symlink Drawings escape rejected")
	else:
		print("T066_SYMLINK_SKIPPED: platform does not provide ln -s")
	# Empty metadata records cannot silently drop an authored floor or map.
	var missing_map: Dictionary = registry.export_index()
	missing_map["maps"].clear()
	_check(not AtlasDrawingRegistry.from_index(missing_map, campaign).ok,
		"missing map metadata is never synthesized during load")
	var temporary: Dictionary = registry.export_index()
	var origin: String = registry.projection("world")[0]["details"][0]["document_id"]
	var other: AtlasMapDocument = campaign.get_map("greyhaven")
	campaign.maps.erase("greyhaven")
	_check(registry.attach_campaign(campaign).ok and registry.export_index()["maps"].size() == 1,
		"deleted map omitted from next saved registry index")
	campaign.maps[other.id] = other
	_check(registry.attach_campaign(campaign).ok and registry.projection("world")[0]["details"][0]["document_id"] == origin,
		"restoring a map does not regenerate stable DrawingDocument identities")
	_check(temporary["schema"] == AtlasDrawingRegistry.INDEX_SCHEMA, "original registry snapshot remains independent")
