extends SceneTree
## T-154: native-owned text/raster history transitions must keep Rust tokens,
## preserve canonical RGBA8, and reject caller-corrupted detached snapshots.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T154_PARKED_FAILED: " + label)


func stroke(doc: DrawingDocument, layer: String, position: Vector2) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb")
	var began: DrawingResult = session.begin_native_stroke(brush, preset, 8.0,
		0xff5599cc, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not began.ok:
		session.cancel()
		return began
	var drew: DrawingResult = session.paint_path_native(
		PackedVector2Array([position, position + Vector2(10, 0)]),
		0xff5599cc, false, null)
	if not drew.ok:
		session.cancel()
		return drew
	return session.commit()


func tile_bytes(doc: DrawingDocument, layer: String) -> PackedByteArray:
	var source: DrawingResult = doc.request_chunk(layer, "0,0")
	if not source.ok or source.value == null:
		return PackedByteArray()
	return (source.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real Rust store registered")
	var doc: DrawingDocument = DrawingDocument.new("t154-parked", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	check(stroke(doc, ink, Vector2(14, 14)).ok, "native ink history token")
	var store: Object = doc._native_raster_store
	var initial_ink: PackedByteArray = tile_bytes(doc, ink)
	var ink_token: int = int(store.call("stats").get("undo", -1))
	var element: DrawingTextElement = DrawingTextElement.new()
	element.content = "Rust + Text"
	element.position = Vector2i(-18, -17)
	element.font_size = 20
	var created: DrawingResult = doc.commit_text("", element, doc.revision,
		"root", "text-park")
	check(created.ok, "semantic source committed")
	if not created.ok:
		quit(1)
		return
	var label: String = String(created.value)
	check(doc.rasterize_text(label, doc.revision).ok, "semantic glyphs rasterized")
	var glyphs: PackedByteArray = tile_bytes(doc, label)
	check(not glyphs.is_empty(), "text raster has RGBA8 source")
	check(stroke(doc, label, Vector2(25, 24)).ok,
		"Hokusai painted glyphs, authorizing text layer in Rust")
	var painted: PackedByteArray = tile_bytes(doc, label)
	check(painted != glyphs, "text Brush changed canonical RGBA8")
	var imported: int = int(store.call("stats").get("bytes_imported", -1))
	check(doc.undo().ok and tile_bytes(doc, label) == glyphs,
		"native text Brush Undo restores exact glyph source")
	var before_park: int = doc.revision
	check(doc.undo().ok and doc.inspect_node(label).kind == DrawingLayerNode.TEXT,
		"Undo text conversion returns to semantic layer")
	check(doc.revision == before_park + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"shared revision survives owned-layer kind transition")
	check(store.call("is_layer_parked", label) and
		int(store.call("stats").get("parked_layers", -1)) == 1,
		"Rust parks owned text-derived raster tiles")
	check(int(store.call("stats").get("undo", -1)) == ink_token and
		int(store.call("stats").get("redo", -1)) == 1,
		"unrelated Ink Undo and text Brush Redo tokens retained")
	check(not doc.create_layer(DrawingLayerNode.RASTER, "Collision", "root", label).ok,
		"parked layer identity cannot be reused")
	check(doc._native_raster_store == store and tile_bytes(doc, ink) == initial_ink,
		"park leaves unrelated canonical ink untouched")

	# The caller owns the detached event snapshot. Mutate its known native tile
	# and prove Redo rejects before moving the native or document revision.
	var event_index: int = doc._cursor
	var snapshot: DrawingLayerNode = doc._events[event_index]["after"]
	check(snapshot != null and snapshot.kind == DrawingLayerNode.RASTER and
		snapshot.tiles.has("0,0"), "text history stores detached tile snapshot")
	var tile: DrawingRasterTile = snapshot.tiles.get("0,0")
	if tile != null:
		var original_pixel: int = tile.get_rgba(63, 63)
		tile.set_rgba(63, 63, original_pixel ^ 0x00ffffff)
		var stalled_revision: int = doc.revision
		var stalled_cursor: int = doc._cursor
		var rejected: DrawingResult = doc.redo()
		check(not rejected.ok and rejected.code == "STALE_PIXEL",
			"mutated raster snapshot is refused before Rust restore")
		check(doc.revision == stalled_revision and doc._cursor == stalled_cursor and
			int(store.call("stats").get("revision", -1)) == stalled_revision and
			store.call("is_layer_parked", label),
			"rejected Redo leaves both timelines and park state unchanged")
		tile.set_rgba(63, 63, original_pixel)
	check(doc.redo().ok and not store.call("is_layer_parked", label),
		"uncorrupted snapshot can retry and unpark")
	check(tile_bytes(doc, label) == glyphs and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"unpark restored exact glyph bytes and shared revision")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported,
		"structural replay avoided source reimport")
	check(doc.redo().ok and tile_bytes(doc, label) == painted,
		"original native Brush Redo token survives park/unpark")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == ink_token + 1,
		"native history and Godot timeline remain synchronized")
	check(doc.undo().ok and doc.undo().ok and store.call("is_layer_parked", label),
		"repeated Undo safely parks again")
	check(doc.redo().ok and doc.redo().ok and tile_bytes(doc, label) == painted,
		"repeated Redo returns byte-exact painted glyphs")
	var save_path: String = ProjectSettings.globalize_path("user://t154-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "native parked-history document saves")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok and tile_bytes(reopened.value as DrawingDocument, label) == painted and
		tile_bytes(reopened.value as DrawingDocument, ink) == initial_ink,
		"Save/Open preserves both native painted layers")
	DirAccess.remove_absolute(save_path)
	check(doc.undo().ok and tile_bytes(doc, label) == glyphs,
		"stage text-raster history transition after exact native Brush Undo")
	var host_revision: int = doc.revision
	var host_cursor: int = doc._cursor
	check(store.call("advance_metadata_revision", host_revision, false),
		"inject native-ahead revision without changing Godot source")
	var rejected_ahead: DrawingResult = doc.undo()
	check(not rejected_ahead.ok and rejected_ahead.code == "STALE_REVISION",
		"text-raster Undo fails closed when Rust is ahead of host")
	check(doc.revision == host_revision and doc._cursor == host_cursor and
		doc.inspect_node(label).kind == DrawingLayerNode.RASTER and
		int(store.call("stats").get("revision", -1)) == host_revision + 1,
		"native-ahead rejection preserves both independent revisions and history cursor")
	print("T154_PARKED_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
