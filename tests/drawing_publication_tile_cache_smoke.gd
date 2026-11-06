extends SceneTree
## T-068: commit-time source resolutions are per tile, not per pixel.
## Failed publication must not leak partial tiles, revision or history.

class CountingDocument extends DrawingDocument:
	var resolve_calls: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolve_calls += 1
		return super._resolve_chunk(layer_id, key)


var checks: int = 0
var failures: int = 0
var _lazy_data: PackedByteArray = PackedByteArray()
var _lazy_works: bool = false
var _lazy_calls: int = 0
var _reentrant_document: CountingDocument = null


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T068_PUBLICATION_FAILED: " + label)


func _load_lazy(_ref: String) -> Variant:
	_lazy_calls += 1
	if _reentrant_document != null:
		_reentrant_document.create_layer(DrawingLayerNode.RASTER, "Concurrent edit")
		_reentrant_document = null
	return _lazy_data if _lazy_works else null


func _run() -> void:
	var document: CountingDocument = CountingDocument.new("publication", 16)
	var result: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	_check(result.ok, "create generic raster layer")
	var layer: String = String(result.value)
	var edit: DrawingEditSession = document.begin_edit(layer, document.revision).value
	_check(edit.fill_rect(Rect2i(1, 1, 12, 12), 0x00112233).ok,
		"stage many hidden-RGB pixels without source mutation")
	var before_revision: int = document.revision
	document.resolve_calls = 0
	result = edit.commit()
	_check(result.ok and document.revision == before_revision + 1 and
		result.delta.after.size() == 144, "atomic single-tile publication")
	_check(document.resolve_calls == 1, "exactly one source resolve for 144 pixels")
	_check(result.regions.size() == 1 and result.regions[0].width == 12 and
		result.regions[0].height == 12, "dirty bounds unchanged")
	_check(int(document.read_pixel(layer, 1, 1).value) == 0x00112233,
		"transparent source retains hidden RGB")
	_check(document.undo().ok and int(document.read_pixel(layer, 1, 1).value) == 0,
		"undo restores exact prior value")
	_check(document.redo().ok and int(document.read_pixel(layer, 1, 1).value) == 0x00112233,
		"redo restores published hidden RGB")

	var far: CountingDocument = CountingDocument.new("far-publication", 16)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	var anchor: int = 9007199254740993
	var far_edit: DrawingEditSession = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(far_edit.fill_rect(Rect2i(-2, -2, 4, 4), 0x80818283).ok,
		"stage at signed 64-bit position spanning canonical tiles")
	far.resolve_calls = 0
	result = far_edit.commit()
	_check(result.ok and result.regions.size() == 4,
		"far-coordinate commit creates four exact dirty tiles")
	_check(far.resolve_calls == 4, "resolve each of four source tiles once")
	_check(int(far.read_pixel(far_layer, anchor - 2, -anchor - 2).value) == 0x80818283,
		"signed coordinate remains exact without float rounding")
	_check(far.undo().ok and far.redo().ok and
		int(far.read_pixel(far_layer, anchor + 1, -anchor + 1).value) == 0x80818283,
		"four-tile undo/redo is intact")

	# Explicit low-level publication is also used by history adapters. Ensure
	# a stale pixel cannot install a valid earlier detached tile.
	var first_key: String = "2,2"
	var second_key: String = "3,3"
	var prior_revision: int = document.revision
	var history_size: int = document.history_length()
	document.resolve_calls = 0
	result = document._publish_edit(layer, prior_revision,
		{first_key: 0x00112233, second_key: 0},
		{first_key: 0xaa776655, second_key: 0xbb112233})
	_check(not result.ok and result.code == "STALE_PIXEL", "stale original rejects publication")
	_check(document.resolve_calls == 1 and document.revision == prior_revision,
		"failed validation resolves without publishing a tile")
	_check(int(document.read_pixel(layer, 2, 2).value) == 0x00112233 and
		int(document.read_pixel(layer, 3, 3).value) == 0x00112233,
		"failed commit preserves source and exact hidden RGB")
	_check(document.history_length() == history_size,
		"failed publication does not append history")
	result = document._publish_edit(layer, prior_revision - 1,
		{first_key: 0x00112233}, {first_key: 0x10101010})
	_check(not result.ok and result.code == "STALE_REVISION",
		"stale document revision is rejected before tile access")
	result = document._publish_edit(layer, prior_revision,
		{"+2,2": 0x00112233}, {"+2,2": 0x10101010})
	_check(not result.ok and result.code == "COORD", "noncanonical coordinate rejected")
	result = document._publish_edit(layer, prior_revision,
		{}, {})
	_check(not result.ok and result.code == "NO_CHANGE", "empty publication has no side effects")

	# The first tile validates, but a later lazy referenced tile fails to load.
	# No detached tile can be installed before all source checks pass.
	var lazy: CountingDocument = CountingDocument.new("lazy-publication", 16)
	var lazy_layer: String = String(lazy.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	_lazy_data.resize(16 * 16 * 4)
	_lazy_data[0] = 0x12
	_lazy_data[1] = 0x34
	_lazy_data[2] = 0x56
	_lazy_data[3] = 0x78
	var digest: String = DrawingRasterTile.digest_rgba8(_lazy_data, 16)
	_check(lazy.register_lazy_chunk(lazy_layer, 1, 0, "blob", digest,
		Callable(self, "_load_lazy")).ok, "register lazy source with checksum")
	var start_revision: int = lazy.revision
	var pending_before: Dictionary[String, int] = {"0,0": 0, "16,0": 0x78563412}
	var pending_after: Dictionary[String, int] = {"0,0": 0xff332211, "16,0": 0xff8899aa}
	lazy.resolve_calls = 0
	result = lazy._publish_edit(lazy_layer, start_revision, pending_before, pending_after)
	_check(not result.ok and result.code == "MISSING_TILE", "lazy failure rejects whole commit")
	_check(lazy.resolve_calls == 2 and lazy.revision == start_revision and
		lazy.tile_keys(lazy_layer).size() == 1, "failed commit keeps lazy ref and no new tile")
	_check(int(lazy.read_pixel(lazy_layer, 0, 0).value) == 0,
		"failed commit does not install first detached tile")
	_lazy_works = true
	lazy.resolve_calls = 0
	result = lazy._publish_edit(lazy_layer, start_revision, pending_before, pending_after)
	_check(result.ok and lazy.resolve_calls == 2 and _lazy_calls == 2,
		"corrected provider retries and source tiles resolve once each")
	_check(int(lazy.read_pixel(lazy_layer, 0, 0).value) == 0xff332211 and
		int(lazy.read_pixel(lazy_layer, 16, 0).value) == 0xff8899aa,
		"lazy retry commits both tiles exactly")
	_check(lazy.undo().ok and int(lazy.read_pixel(lazy_layer, 16, 0).value) == 0x78563412,
		"lazy retry undo preserves original pixels")

	# A lazy provider is external code and can reenter the document. Detect a
	# source revision change before publishing any of our detached tiles.
	var reentrant: CountingDocument = CountingDocument.new("provider-reentrancy", 16)
	var reentrant_layer: String = String(reentrant.create_layer(DrawingLayerNode.RASTER, "R").value)
	_check(reentrant.register_lazy_chunk(reentrant_layer, 1, 0, "blob", digest,
		Callable(self, "_load_lazy")).ok, "register reentrant lazy provider")
	var reentrant_revision: int = reentrant.revision
	_reentrant_document = reentrant
	result = reentrant._publish_edit(reentrant_layer, reentrant_revision,
		{"0,0": 0, "16,0": 0x78563412},
		{"0,0": 0xff010203, "16,0": 0xff040506})
	_check(not result.ok and result.code == "STALE_REVISION" and
		reentrant.revision > reentrant_revision, "reentrant provider revision invalidates commit")
	_check(int(reentrant.read_pixel(reentrant_layer, 0, 0).value) == 0 and
		int(reentrant.read_pixel(reentrant_layer, 16, 0).value) == 0x78563412,
		"reentrant failure does not install partially detached pixels")

	print("T068_PUBLICATION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
