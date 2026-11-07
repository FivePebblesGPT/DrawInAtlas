extends SceneTree
## T-086: opaque source-over parity, signed seams, detached previews and one
## lazy source resolution per storage tile during a bounded cold composite.

class CountingDocument:
	extends DrawingDocument
	var resolve_calls: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolve_calls += 1
		return super._resolve_chunk(layer_id, key)

var checks: int = 0
var failures: int = 0
var loader_calls: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_COLD_FAILED: " + label)


func rgba_bytes(r: int, g: int, b: int, a: int) -> PackedByteArray:
	return PackedByteArray([r, g, b, a])


func seed_layer(doc: DrawingDocument, layer: String, area: Rect2i, shift: int) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	var alpha: Array[int] = [0, 1, 127, 254, 255]
	for y: int in range(area.size.y):
		for x: int in range(area.size.x):
			bytes.append_array(rgba_bytes((x * 41 + shift) % 256,
				(y * 53 + shift) % 256, (x * 7 + y * 13 + shift) % 256,
				alpha[(x + y + shift) % alpha.size()]))
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "start seeded raster edit")
	if started.ok:
		var edit: DrawingEditSession = started.value as DrawingEditSession
		check(edit.apply_region(area, bytes).ok, "stage seeded RGBA8 including hidden RGB")
		check(edit.commit().ok, "publish seeded RGBA8")


## Deliberately slow, independent per-pixel oracle using the public read API.
## The optimized renderer may not substitute source opacity for destination alpha.
func reference(doc: DrawingDocument, view: Rect2i, anchor_x: int = 0,
		anchor_y: int = 0, preview: DrawingEditSession = null) -> PackedByteArray:
	var layers: Array[String] = []
	DrawingRenderer._collect_visible(doc, DrawingDocument.ROOT_ID, layers)
	var result: PackedByteArray = PackedByteArray()
	for y: int in range(view.size.y):
		for x: int in range(view.size.x):
			var world_x: int = anchor_x + int(view.position.x) + x
			var world_y: int = anchor_y + int(view.position.y) + y
			var destination: int = 0
			for layer: String in layers:
				var sample: DrawingResult = doc.read_pixel(layer, world_x, world_y)
				if not sample.ok:
					return PackedByteArray()
				var source: int = int(sample.value)
				if preview != null and preview.layer_id == layer:
					var key: String = DrawingDocument.TILES.tile_key64(world_x, world_y, doc.tile_stride)
					var patch: Dictionary = preview.preview_tile(key)
					var index: int = posmod(world_y, doc.tile_stride) * doc.tile_stride \
						+ posmod(world_x, doc.tile_stride)
					if patch.has(index):
						source = int(patch[index])
				if ((source >> 24) & 255) != 0:
					destination = DrawingEditSession._blend(source, destination)
			result.append_array(rgba_bytes(destination & 255, (destination >> 8) & 255,
				(destination >> 16) & 255, (destination >> 24) & 255))
	return result


func lazy_bytes(_ref: String) -> PackedByteArray:
	loader_calls += 1
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4 * 4 * 4)
	bytes[0] = 202
	bytes[1] = 31
	bytes[2] = 91
	bytes[3] = 255
	return bytes


func corrupt_bytes(_ref: String) -> PackedByteArray:
	loader_calls += 1
	return PackedByteArray([1, 2, 3])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var doc: CountingDocument = CountingDocument.new("t086-cold", 4)
	var low: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Low").value)
	var high: String = String(doc.create_layer(DrawingLayerNode.RASTER, "High").value)
	seed_layer(doc, low, Rect2i(-5, -4, 10, 9), 3)
	seed_layer(doc, high, Rect2i(-4, -5, 9, 10), 7)
	var view: Rect2i = Rect2i(-6, -6, 13, 13)
	var oracle: PackedByteArray = reference(doc, view)
	doc.resolve_calls = 0
	var frame: DrawingResult = DrawingRenderer.render(doc, view)
	check(frame.ok and (frame.value as Image).get_data() == oracle,
		"byte-exact signed seams, zero/one/partial/full alpha and layer order")
	# Across x,y = -6..6, four signed storage tiles per axis per layer.
	check(doc.resolve_calls == 32,
		"each of 16 signed source chunks resolved once per layer: %d" % doc.resolve_calls)

	var staged: DrawingResult = doc.begin_edit(low, doc.revision)
	check(staged.ok, "start detached low-layer preview")
	if staged.ok:
		var preview: DrawingEditSession = staged.value as DrawingEditSession
		check(preview.apply_region(Rect2i(-1, -1, 2, 2),
			PackedByteArray([30, 215, 140, 255, 21, 51, 92, 128,
				8, 7, 6, 0, 240, 4, 9, 254])).ok, "stage opaque/alpha/erase preview")
		var draft: DrawingResult = DrawingRenderer.render(doc, view, 0, 0, 1048576, preview)
		check(draft.ok and (draft.value as Image).get_data() == reference(doc, view, 0, 0, preview),
			"detached preview resolves layer-correctly with no source mutation")
		check(doc.revision == preview.expected_revision, "preview is not published")
		check(preview.commit().ok, "publish detached preview")
		check(DrawingRenderer.render(doc, view).value.get_data() == draft.value.get_data(),
			"published image matches detached preview bytes")
		check(doc.undo().ok and DrawingRenderer.render(doc, view).value.get_data() == oracle,
			"undo recovers initial image byte-for-byte")
		check(doc.redo().ok and DrawingRenderer.render(doc, view).value.get_data() == draft.value.get_data(),
			"redo restores committed preview bytes")

	# Four densely occupied layers on signed storage seams exercise the
	# compositor's direct sparse map reads without bypassing the public oracle.
	# Transparent pixels with nonzero RGB must remain canonical source bytes,
	# even when the frame compositor correctly omits their alpha-zero color.
	var dense: CountingDocument = CountingDocument.new("t086-dense", 8)
	var dense_layers: Array[String] = []
	for layer_number: int in range(4):
		var dense_layer: String = String(dense.create_layer(DrawingLayerNode.RASTER,
			"Dense-%d" % layer_number).value)
		dense_layers.append(dense_layer)
		seed_layer(dense, dense_layer, Rect2i(-12 + layer_number,
			-9 + layer_number, 32, 27), 2 + layer_number * 11)
	var dense_view: Rect2i = Rect2i(-10, -10, 26, 24)
	var resident: DrawingRasterTile = dense._resolve_chunk(dense_layers[1], "0,0").value as DrawingRasterTile
	var original_bytes: PackedByteArray = resident.to_rgba8()
	var dense_revision: int = dense.revision
	var dense_frame: DrawingResult = DrawingRenderer.render(dense, dense_view)
	check(dense_frame.ok and (dense_frame.value as Image).get_data() == reference(dense, dense_view),
		"four dense layers preserve all source-over bytes across signed seams")
	check(dense.revision == dense_revision and resident.to_rgba8() == original_bytes,
		"direct indexed reads do not mutate source pixels or revision")
	var dense_started: DrawingResult = dense.begin_edit(dense_layers[1], dense.revision)
	check(dense_started.ok, "start lower dense-layer detached preview")
	if dense_started.ok:
		var dense_preview: DrawingEditSession = dense_started.value as DrawingEditSession
		check(dense_preview.apply_region(Rect2i(0, 0, 2, 2), PackedByteArray([
			99, 22, 88, 0, 42, 12, 190, 255,
			4, 55, 71, 127, 100, 35, 96, 254])).ok,
			"stage hidden-RGB, opaque and fractional-alpha preview pixels")
		var dense_draft: DrawingResult = DrawingRenderer.render(dense,
			dense_view, 0, 0, 1048576, dense_preview)
		check(dense_draft.ok and (dense_draft.value as Image).get_data()
			== reference(dense, dense_view, 0, 0, dense_preview),
			"four-layer preview overrides source map without leaking to other layers")
		check(dense.revision == dense_revision and resident.to_rgba8() == original_bytes,
			"detached preview preserves immutable committed source map")
		dense_preview.cancel()
		check(dense.revision == dense_revision and resident.to_rgba8() == original_bytes,
			"cancel keeps canonical dense source and revision unchanged")
		check(DrawingRenderer.render(dense, dense_view).value.get_data()
			== dense_frame.value.get_data(),
			"cancel restores multi-layer framebuffer without history or pixels")

	var far: CountingDocument = CountingDocument.new("t086-anchor", 4)
	var layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	var large: int = 5000000000
	var far_edit: DrawingEditSession = far.begin_edit(layer, far.revision,
		Transform2D.IDENTITY, large, -large).value as DrawingEditSession
	check(far_edit.apply_region(Rect2i(-1, -1, 2, 2),
		PackedByteArray([1, 2, 3, 255, 21, 31, 41, 128,
				98, 87, 76, 0, 91, 31, 11, 255])).ok and far_edit.commit().ok,
		"seed 64-bit source anchor without Vector2i truncation")
	var anchored: Rect2i = Rect2i(-2, -2, 4, 4)
	var anchored_frame: DrawingResult = DrawingRenderer.render(far, anchored, large, -large)
	check(anchored_frame.ok and (anchored_frame.value as Image).get_data()
		== reference(far, anchored, large, -large), "signed 64-bit render origin exact RGBA8")

	# A one-pixel storage stride is legal: none of its tiles repeat in a
	# scanline, so renderer caching must not scale with every view pixel.
	var tiny: CountingDocument = CountingDocument.new("t086-tiny", 1)
	var tiny_layer: String = String(tiny.create_layer(DrawingLayerNode.RASTER, "Tiny").value)
	tiny.resolve_calls = 0
	var tiny_frame: DrawingResult = DrawingRenderer.render(tiny, Rect2i(-512, 0, 1024, 1))
	check(tiny_frame.ok and tiny.resolve_calls == 1024 and
		(tiny_frame.value as Image).get_data().size() == 4096,
		"very wide 1px-stride render stays bounded and visits every source tile")

	var capped: CountingDocument = CountingDocument.new("t086-cap", 2)
	var capped_layer: String = String(capped.create_layer(DrawingLayerNode.RASTER, "Bounded").value)
	capped.resolve_calls = 0
	var capped_frame: DrawingResult = DrawingRenderer.render(capped, Rect2i(-1, 0, 1024, 2))
	check(capped_frame.ok and capped.resolve_calls == 770,
		"256-reference cap falls back to uncached reads for 257 additional chunks")

	var lazy: CountingDocument = CountingDocument.new("t086-lazy", 4)
	var lazy_layer: String = String(lazy.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	var expected: PackedByteArray = lazy_bytes("")
	loader_calls = 0
	var digest: String = DrawingRasterTile.digest_rgba8(expected, 4)
	check(lazy.register_lazy_chunk(lazy_layer, 0, 0, "reference", digest,
		Callable(self, "lazy_bytes")).ok, "register authentic lazy tile")
	lazy.resolve_calls = 0
	var decoded: DrawingResult = DrawingRenderer.render(lazy, Rect2i(0, 0, 4, 4))
	check(decoded.ok and loader_calls == 1 and lazy.resolve_calls == 1,
		"resolve valid lazy tile once and verify SHA before caching")
	check(decoded.ok and (decoded.value as Image).get_pixel(0, 0).r > 0.7,
		"render decoded opaque lazy pixel")
	var corrupt: CountingDocument = CountingDocument.new("t086-corrupt", 4)
	var corrupt_layer: String = String(corrupt.create_layer(DrawingLayerNode.RASTER, "Corrupt").value)
	check(corrupt.register_lazy_chunk(corrupt_layer, 0, 0, "bad", digest,
		Callable(self, "corrupt_bytes")).ok, "register corrupt source chunk")
	var damaged: DrawingResult = DrawingRenderer.render(corrupt, Rect2i(0, 0, 4, 4))
	check(not damaged.ok and damaged.code == "CORRUPT_TILE",
		"corrupt lazy storage fails, never renders as a transparent cache hit")

	if failures == 0:
		print("T086_COLD_PASSED %d/%d" % [checks, checks])
	else:
		printerr("T086_COLD_FAILED %d/%d" % [failures, checks])
	quit(1 if failures else 0)
