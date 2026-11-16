extends SceneTree
## Cold dirty-snapshot API must reject unauthorized Rust-owned Godot projections.

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
		printerr("T167_SNAPSHOT_FAILED: " + label)

func is_stale(value: Variant) -> bool:
	return value is DrawingResult and not value.ok and value.code == "STALE_SOURCE"

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "native extension available")
	var doc: DrawingDocument = DrawingDocument.new("t167-snapshot", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "begin edit")
	if not opened.ok:
		quit(1)
		return
	var edit: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var began: DrawingResult = edit.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, INK, Rect2i(0, 0, 64, 64), true)
	check(began.ok, "begin native Hokusai stroke")
	if not began.ok:
		quit(1)
		return
	check(edit.paint_path_native(PackedVector2Array([Vector2(5, 6), Vector2(13, 6)]),
		INK, false, null).ok, "paint native pigment")
	var committed: DrawingResult = edit.commit()
	check(committed.ok and committed.delta != null and
		committed.delta.native_history_token > 0, "native history committed")
	if not committed.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var token: int = committed.delta.native_history_token
	var revision_before: int = doc.revision
	var canonical: PackedByteArray = store.call("read_tile", layer, 0, 0, false).get("bytes")
	var tile: DrawingRasterTile = doc._nodes[layer].tiles.get("0,0")
	check(tile != null and tile.to_rgba8() == canonical and tile.get_rgba(40, 40) == 0,
		"matching canonical native source")
	var snapshot: Variant = doc.snapshot_for_save()
	check(snapshot is DrawingResult, "snapshot API returns checked result")
	check(snapshot is DrawingResult and snapshot.ok and snapshot.revision == doc.revision,
		"valid snapshot returns matching revision")
	if snapshot is DrawingResult and snapshot.ok:
		var payload: Dictionary = snapshot.value
		check(payload["dirty_rgba8"][layer + ":0,0"] == canonical,
			"dirty source equals complete canonical Rust RGBA8")
		check(payload["stride"] == STRIDE and payload["revision"] == revision_before,
			"snapshot metadata retains original schema")
	else:
		check(false, "dirty source equals complete canonical Rust RGBA8")
		check(false, "snapshot metadata retains original schema")
	var dirty_before: Dictionary = doc._dirty_tiles.duplicate(true)
	var history_before: int = doc.history_length()
	var cursor_before: int = doc.history_position()
	check(tile.set_rgba(40, 40, HIDDEN), "mutate hidden RGB in projected tile")
	var stale: Variant = doc.snapshot_for_save()
	check(is_stale(stale), "unauthorized hidden-RGB snapshot rejected")
	check(doc._dirty_tiles == dirty_before and doc.revision == revision_before and
		doc.history_length() == history_before and doc.history_position() == cursor_before,
		"rejected snapshot leaves document revision/history/dirty state intact")
	check(store.call("read_tile", layer, 0, 0, false).get("bytes") == canonical and
		store.call("has_history_token", token, revision_before, true),
		"rejected snapshot leaves native source and history intact")
	check(tile.set_rgba(40, 40, 0), "restore unchanged native source in same tile object")
	var retry: Variant = doc.snapshot_for_save()
	check(retry is DrawingResult and retry.ok and
		(retry.value as Dictionary)["dirty_rgba8"][layer + ":0,0"] == canonical,
		"byte-exact retry succeeds without rebase")
	if retry is DrawingResult and retry.ok:
		var detached: Dictionary = retry.value
		var bytes: PackedByteArray = detached["dirty_rgba8"][layer + ":0,0"]
		bytes.encode_u32(0, HIDDEN)
		check(tile.to_rgba8() == canonical and
			store.call("read_tile", layer, 0, 0, false).get("bytes") == canonical,
			"detached save bytes cannot mutate native source")
	else:
		check(false, "detached save bytes cannot mutate native source")
	check(doc.undo().ok and doc.redo().ok and
		store.call("read_tile", layer, 0, 0, false).get("bytes") == canonical,
		"native Undo/Redo stays exact after rejected save")
	var after_history: Variant = doc.snapshot_for_save()
	check(after_history is DrawingResult and after_history.ok,
		"post-history snapshot still valid")
	var native_revision: int = doc.revision
	check(store.call("advance_metadata_revision", native_revision, true),
		"create native-ahead revision")
	check(int(store.call("stats").get("revision", -1)) == native_revision + 1,
		"native revision advanced independently")
	check(is_stale(doc.snapshot_for_save()), "native-ahead snapshot rejected")
	check(doc.revision == native_revision and doc._dirty_tiles == dirty_before,
		"native-ahead rejection never publishes or modifies dirty state")
	var historical: DrawingDocument = DrawingDocument.new("t167-no-native", STRIDE)
	var historical_snapshot: Variant = historical.snapshot_for_save()
	check(historical._native_raster_store == null and historical_snapshot is DrawingResult and
		historical_snapshot.ok,
		"native-absent historical save snapshot remains supported")
	check(historical_snapshot is DrawingResult and historical_snapshot.ok and
		(historical_snapshot.value as Dictionary).has("dirty_rgba8") and
		(historical_snapshot.value as Dictionary)["dirty_rgba8"].is_empty(),
		"native-absent snapshot retains ordinary empty dirty map")
	print("T167_SNAPSHOT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0 and checks >= 18:
		print("T167_SNAPSHOT_PASSED (%d checks; 0 failed)" % checks)
	quit(1 if failures else 0)
