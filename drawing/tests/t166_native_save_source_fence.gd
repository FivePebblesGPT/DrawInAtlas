extends SceneTree
## Save/manifest publication must not let mutable Godot projections supersede
## current Rust-owned raster bytes or accept a divergent native revision.

const STRIDE: int = 64
const INK: int = 0xff234567
const HIDDEN: int = 0x00112233
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T166_SAVE_FENCE_FAILED: " + label)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "required native extension loaded")
	var doc: DrawingDocument = DrawingDocument.new("t166-native-save", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "begin native Hokusai stroke")
	if not opened.ok:
		quit(1)
		return
	var edit: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var configured: DrawingResult = edit.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, INK, Rect2i(0, 0, 64, 64), true)
	check(configured.ok, "Hokusai preset starts tile transaction")
	if not configured.ok:
		quit(1)
		return
	check(edit.paint_path_native(PackedVector2Array([Vector2(5, 6), Vector2(13, 6)]),
		INK, false, null).ok, "native pigment path staged")
	var committed: DrawingResult = edit.commit()
	check(committed.ok and committed.delta != null and
		committed.delta.native_history_token > 0, "real native history committed")
	if not committed.ok:
		quit(1)
		return
	var token: int = committed.delta.native_history_token
	var store: Object = doc._native_raster_store
	var revision_before: int = doc.revision
	var bytes_before: PackedByteArray = store.call("read_tile", layer, 0, 0, false).get("bytes")
	var tile: DrawingRasterTile = doc._nodes[layer].tiles.get("0,0")
	check(tile != null and tile.to_rgba8() == bytes_before and
		tile.get_rgba(40, 40) == 0, "Godot and Rust begin with same full-tile RGBA8")
	check(doc.export_manifest().ok and DrawingFileIO.encode(doc).ok and
		DrawingBundleManifest.encode(doc).ok, "all serialization formats accept honest projection")
	var dirty_before: Dictionary = doc._dirty_tiles.duplicate(true)
	var history_before: int = doc.history_length()
	var cursor_before: int = doc.history_position()
	var original_pixel: int = tile.get_rgba(40, 40)
	check(tile.set_rgba(40, 40, HIDDEN), "simulate unsupported in-place alpha-zero RGB mutation")
	check(tile.to_rgba8() != bytes_before and tile.get_rgba(40, 40) == HIDDEN,
		"Godot projection differs from canonical Rust hidden-RGB tile")
	var manifest_bad: DrawingResult = doc.export_manifest()
	var standalone_bad: DrawingResult = DrawingFileIO.encode(doc)
	var sparse_bad: DrawingResult = DrawingBundleManifest.encode(doc)
	check(not manifest_bad.ok and manifest_bad.code == "STALE_SOURCE",
		"logical manifest rejects unauthorized in-place tile bytes")
	check(not standalone_bad.ok and standalone_bad.code == "STALE_SOURCE",
		"portable .drawing export rejects modified Godot tile")
	check(not sparse_bad.ok and sparse_bad.code == "STALE_SOURCE",
		"sparse Atlas manifest export rejects modified Godot tile")
	var refs: Dictionary[String, String] = {}
	for combined: String in dirty_before:
		refs[combined] = "verified-ref"
	var marked_bad: DrawingResult = doc.mark_published(doc.revision, refs)
	check(not marked_bad.ok and marked_bad.code == "STALE_SOURCE",
		"publication cannot certify a mutated canonical native tile")
	check(doc._dirty_tiles == dirty_before and doc.revision == revision_before and
		doc.history_length() == history_before and doc.history_position() == cursor_before,
		"rejected serialization leaves dirty state, revision and history untouched")
	check(store.call("read_tile", layer, 0, 0, false).get("bytes") == bytes_before and
		store.call("has_history_token", token, revision_before, true),
		"rejected save neither rewrites Rust tiles nor consumes native history")
	check(tile.set_rgba(40, 40, original_pixel) and tile.to_rgba8() == bytes_before,
		"restore same tile object to exact canonical source bytes")
	check(doc.export_manifest().ok and DrawingFileIO.encode(doc).ok and
		DrawingBundleManifest.encode(doc).ok,
		"retry serialization succeeds without rebase after byte-exact restoration")
	check(doc.mark_published(doc.revision, refs).ok and not doc.is_dirty(),
		"valid publication saves canonical source and clears dirty state")
	check(doc.undo().ok and doc.redo().ok and
		store.call("read_tile", layer, 0, 0, false).get("bytes") == bytes_before,
		"Undo/Redo remains exact after rejected and successful saves")

	var aligned_revision: int = doc.revision
	check(store.call("advance_metadata_revision", aligned_revision, true),
		"simulate external native-only revision advancement")
	check(int(store.call("stats").get("revision", -1)) == aligned_revision + 1 and
		doc.revision == aligned_revision, "native attachment is now ahead")
	check(not doc.export_manifest().ok and not DrawingFileIO.encode(doc).ok and
		not DrawingBundleManifest.encode(doc).ok,
		"all save encoders fail closed on native-ahead revision")
	check(not doc.mark_published(doc.revision, {}).ok,
		"publish checkpoint rejects divergent native revision")
	check(doc.revision == aligned_revision and doc.published_revision != doc.revision,
		"rejected native-ahead publication does not advance saved revision")

	print("T166_SAVE_FENCE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0 and checks >= 20:
		print("T166_SAVE_FENCE_PASSED (%d checks; 0 failed)" % checks)
	quit(1 if failures else 0)
