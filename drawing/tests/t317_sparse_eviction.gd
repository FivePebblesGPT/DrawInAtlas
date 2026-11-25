extends SceneTree
## Real native high-water pressure plus clean/dirty/history source lifecycle.
const STRIDE: int = 2048
const HIDDEN: int = 0x00112233
const INK: int = 0xff987654
var checks: int = 0
var failures: int = 0
var fetches: int = 0
var corrupt: bool = false
var payload: PackedByteArray

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T317_FAILED: " + label)

func fetch(_ref: String) -> PackedByteArray:
	fetches += 1
	return PackedByteArray([1]) if corrupt else payload

func fixture(stride: int, count: int) -> DrawingDocument:
	payload = PackedByteArray()
	payload.resize(stride * stride * 4)
	payload.encode_u32(0, HIDDEN)
	payload.encode_u32(4, INK)
	var digest: String = DrawingRasterTile.digest_rgba8(payload, stride)
	var original: DrawingDocument = DrawingDocument.new("paging", stride)
	original.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink")
	for i: int in range(count):
		original.register_lazy_chunk("ink", i - 1, -2, digest, digest, fetch)
	var encoded: DrawingResult = DrawingBundleManifest.encode(original)
	return DrawingBundleManifest.decode(encoded.value["bytes"], fetch).value

func draw(doc: DrawingDocument, x: int) -> DrawingResult:
	return DrawingRenderer.render(doc, Rect2i(0, 0, 2, 1), x * doc.tile_stride, -2 * doc.tile_stride)

func run() -> void:
	var doc: DrawingDocument = fixture(STRIDE, 18)
	var saved: int = doc.revision
	var manifest: Dictionary = doc.export_manifest().value
	var peak: int = 0
	for i: int in range(18):
		var rendered: DrawingResult = draw(doc, i - 1)
		check(rendered.ok and (rendered.value as Image).get_data().decode_u32(4) == INK, "render signed source %d" % i)
		peak = maxi(peak, int(doc._native_raster_store.call("stats").get("bytes_used", 0)))
	print("T317_NATIVE_PEAK_BYTES=%d" % peak)
	check(peak <= 192 * 1024 * 1024, "quiescent browsing remains under high-water budget")
	check(doc._pending_tiles.has("ink:-1,-2") and not doc._nodes["ink"].tiles.has("-1,-2"), "old clean tile becomes pending")
	check(not bool(doc._native_raster_store.call("has_source", "ink", -1, -2, saved)), "old clean native source deauthorized")
	check(doc.export_manifest().ok and doc.export_manifest().value == manifest and doc.revision == saved and not doc.is_dirty() and doc.history_length() == 0, "eviction preserves exact logical manifest and history")
	var before: int = fetches
	corrupt = true
	check(not draw(doc, -1).ok and doc._pending_tiles.has("ink:-1,-2"), "corrupt reload stays pending")
	corrupt = false
	check(draw(doc, -1).ok and fetches == before + 2, "verified reload fetches again")
	var loaded: DrawingResult = doc.request_chunk("ink", "-1,-2")
	check(loaded.ok and (loaded.value as DrawingRasterTile).get_rgba(0, 0) == HIDDEN, "reload preserves hidden RGB")
	doc = null
	# Small fixtures force the pressure seam without repeating the large
	# allocation. An uncommitted script session pins identities even before
	# Rust starts; a retained native token must survive unrelated eviction.
	var local: DrawingDocument = fixture(64, 4)
	for i: int in range(4):
		check(local.request_chunk("ink", "%d,-2" % (i - 1)).ok, "admit small fixture")
	var owner: Object = local._native_raster_store
	var epoch: int = local.display_source_epoch
	var force: int = DrawingDocument.SPARSE_RENDER_HIGH_WATER_BYTES + 1
	var session: DrawingEditSession = local.begin_edit("ink", local.revision).value
	local._trim_sparse_render_sources(force)
	check(local._pending_tiles.is_empty(), "script edit reservation pins all sources")
	session.cancel()
	var edit: DrawingEditSession = local.begin_edit("ink", local.revision).value
	check(edit.fill_rect(Rect2i(-64, -128, 1, 1), INK).ok and edit.commit().ok, "commit native edit before trimming")
	var edited_revision: int = local.revision
	var edited_bytes: PackedByteArray = local._nodes["ink"].tiles["-1,-2"].to_rgba8()
	var mutated: DrawingRasterTile = local._nodes["ink"].tiles["0,-2"]
	mutated.set_rgba(0, 0, 0x00445566)
	local._trim_sparse_render_sources(force)
	check(local._pending_tiles.size() == 2 and local._nodes["ink"].tiles.has("-1,-2") and local._nodes["ink"].tiles.has("0,-2"), "trim only pristine unchanged sources")
	check(not local.export_manifest().ok, "corrupt projection still fails Save fence")
	mutated.set_rgba(0, 0, HIDDEN)
	check(local.export_manifest().ok and local.revision == edited_revision and local.display_source_epoch == epoch and local.history_length() == 1 and local.is_dirty(), "trim retains exact document state")
	check(not bool(owner.call("release_pristine_source", "ink", -1, -2, edited_revision, edited_bytes)), "Rust rejects edited source even with exact bytes")
	check(local.undo().ok and int(local.read_pixel("ink", -64, -128).value) == HIDDEN, "unrelated trim preserves native Undo")
	check(local.redo().ok and int(local.read_pixel("ink", -64, -128).value) == INK and local._native_raster_store == owner, "unrelated trim preserves native Redo")
	check(local.export_subtree("ink").ok and local._pending_tiles.is_empty(), "subtree export resolves every source without eviction")
	# Pending descriptors restored by structural Undo may be loaded later.
	# Pin that layer until structural history is gone, including promoted
	# resident snapshots after Redo and repeated Undo.
	var structure: DrawingDocument = fixture(64, 2)
	check(structure.remove_subtree("ink", true).ok and structure.undo().ok, "restore pending subtree")
	check(structure.request_chunk("ink", "-1,-2").ok, "admit late structural source")
	structure._trim_sparse_render_sources(force)
	check(structure._nodes["ink"].tiles.has("-1,-2") and structure._pending_tiles.size() == 1, "structural history pins late loaded layer")
	check(structure.redo().ok and structure.undo().ok and int(structure.read_pixel("ink", -64, -128).value) == HIDDEN, "structural Redo/Undo retains late bytes")
	# While a provider is on the stack, no unrelated render may discard a
	# source held by the outer read/transfer preflight.
	var guarded: DrawingDocument = fixture(64, 2)
	check(guarded.request_chunk("ink", "-1,-2").ok, "admit reentrant fixture")
	guarded._resolving_chunks["ink:0,-2"] = true
	guarded._trim_sparse_render_sources(force)
	check(guarded._nodes["ink"].tiles.has("-1,-2"), "provider reservation pins sources")
	guarded._resolving_chunks.clear()
	guarded._trim_sparse_render_sources(force)
	check(guarded._pending_tiles.size() == 2 and guarded._native_source_identities.is_empty(), "quiescent source may be released")
	print("T317_SPARSE_EVICTION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T317_SPARSE_EVICTION_PASSED")
	quit(0 if failures == 0 else 1)
