extends SceneTree
## T-148: per-document native tile and tokenized history authority across
## multiple production-style sessions, plus safe non-native revision rebases.

const STRIDE: int = 64
const INK: int = 0xff2233b8
const CLIP: Rect2i = Rect2i(0, 0, 64, 64)
var checks: int = 0
var failures: int = 0


class ReentrantDocument extends DrawingDocument:
	var source_reads: int = 0
	var lock_on_read: int = -1

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		source_reads += 1
		if source_reads == lock_on_read:
			set_locked(layer_id, true)
		return super._resolve_chunk(layer_id, key)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_PERSISTENT_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func stroke(doc: DrawingDocument, layer: String, from: Vector2,
		to: Vector2, erase: bool = false) -> DrawingResult:
	var begin: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not begin.ok:
		return begin
	var session: DrawingEditSession = begin.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var native_begin: DrawingResult = session.begin_native_stroke(brush,
		"NativeHard", "", 8.0, INK, CLIP, true)
	if not native_begin.ok:
		session.cancel()
		return native_begin
	var staged: DrawingResult = session.paint_path_native(
		PackedVector2Array([from, to]), INK, erase, null)
	if not staged.ok:
		session.cancel()
		return staged
	return session.commit()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension present")
	var doc: DrawingDocument = DrawingDocument.new("persistent-native", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var original: PackedByteArray = PackedByteArray()
	original.resize(STRIDE * STRIDE * 4)
	original.encode_u32(0, 0x00112233)
	doc._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(STRIDE, original)
	var first: DrawingResult = stroke(doc, layer, Vector2(10.5, 10.5), Vector2(19.5, 10.5))
	check(first.ok, "first real native gesture")
	check(doc._native_raster_store != null and doc.revision == 2,
		"document retains native store and single revision")
	if not first.ok:
		print("T148_PERSISTENT_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var first_bytes: PackedByteArray = (doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8()
	var imported: int = int(store.call("stats").get("bytes_imported", -1))
	check(imported == original.size(), "first gesture imports one RGBA8 source tile")
	check(first.delta.native_history_token > 0, "first delta holds native history token")
	var second: DrawingResult = stroke(doc, layer, Vector2(40.5, 35.5), Vector2(47.5, 35.5))
	check(second.ok and doc.revision == 3, "second gesture commits against existing Rust source")
	check(doc._native_raster_store == store, "store object identity survives gestures")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported,
		"second gesture does not reimport previously authorized canonical pixels")
	check(int(store.call("stats").get("undo", -1)) == 2,
		"both gestures are resident in persistent Rust history")
	var both: PackedByteArray = (doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8()
	check(both != first_bytes, "second gesture changes additional source pixels")
	check(doc.undo().ok and doc.revision == 4, "first native history replay succeeds")
	check((doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == first_bytes,
		"native Undo restores exact first-gesture bytes")
	check(int(store.call("stats").get("undo", -1)) == 1 and
		int(store.call("stats").get("redo", -1)) == 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"Rust and document agree after Undo")
	check(doc.redo().ok and doc.revision == 5, "native Redo succeeds")
	check((doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == both,
		"native Redo restores exact canonical RGBA8")
	check(int(store.call("stats").get("undo", -1)) == 2 and
		int(store.call("stats").get("redo", -1)) == 0,
		"native history retains two committed gestures after Redo")
	var save_path: String = ProjectSettings.globalize_path("user://t148-persistent-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "persistent source serializes to .drawing")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok and (reopened.value as DrawingDocument).revision == doc.revision,
		"persistent result can be reopened at identical document revision")
	if reopened.ok:
		check(((reopened.value as DrawingDocument).request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == both,
			"file source equals Rust source across successive gestures")
	DirAccess.remove_absolute(save_path)
	check(doc.set_locked(layer, true).ok, "non-native lock increments revision")
	check(not stroke(doc, layer, Vector2(4.5, 4.5), Vector2(4.5, 4.5)).ok,
		"locked layer rejects native edit")
	check(doc.set_locked(layer, false).ok, "unlock increments revision")
	var after_external: DrawingResult = stroke(doc, layer, Vector2(51.5, 48.5), Vector2(54.5, 48.5))
	check(after_external.ok, "gesture rebases on non-native revisions")
	check(doc._native_raster_store == store and int(store.call("stats").get("undo", -1)) == 1,
		"external edit clears stale native history and reuses document-owned store")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported * 2,
		"rebase reauthorizes exact document source rather than using stale tile")
	# The older native events are still on the unified Godot timeline after
	# an external rebase, although Rust correctly discarded their stale tokens.
	check(doc.undo().ok, "new native gesture undoes through live Rust history")
	check(doc.undo().ok, "older native event falls back to detached snapshots")
	check((doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == first_bytes,
		"mixed-history fallback recovers the earlier source exactly")
	check(doc.redo().ok and doc.redo().ok,
		"fallback redo and live native redo remain in ordered document timeline")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) < doc.revision,
		"fallback history leaves native mirror stale until checked rebase")
	var resumed: DrawingResult = stroke(doc, layer, Vector2(25.5, 50.5), Vector2(30.5, 50.5))
	check(resumed.ok and doc._native_raster_store == store,
		"new brush gesture automatically rebases after mixed-history replay")
	# An actual GDScript raster edit, not just layer metadata, must invalidate
	# the cached Rust source and still leave the unified document history usable.
	var earlier_pixel: int = int(doc.read_pixel(layer, 0, 0).value)
	var external_raster: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"0,0": earlier_pixel}, {"0,0": 0x00887766})
	check(external_raster.ok and int(doc.read_pixel(layer, 0, 0).value) == 0x00887766,
		"non-native raster transaction changes canonical document source")
	var after_raster: DrawingResult = stroke(doc, layer,
		Vector2(35.5, 51.5), Vector2(38.5, 51.5))
	check(after_raster.ok and doc._native_raster_store == store,
		"native gesture safely rebases after actual GDScript raster edit")
	var shared: Dictionary = store.call("read_tile", layer, 0, 0, false)
	check(shared.get("ok", false) and (shared.get("bytes") as PackedByteArray).decode_u32(0) == 0x00887766,
		"native canonical source has freshly authorized external hidden RGB")
	check(int(store.call("stats").get("undo", -1)) == 1,
		"external raster edit reset stale native history")
	var before_substitution: int = doc.revision
	doc._nodes[layer].tiles["0,0"] = (doc._nodes[layer].tiles["0,0"] as DrawingRasterTile).detached_copy()
	check(not stroke(doc, layer, Vector2(32.5, 28.5), Vector2(34.5, 28.5)).ok,
		"source identity substitution without revision fails closed")
	check(doc.revision == before_substitution,
		"source identity rejection creates no revision")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == 1,
		"rejected source leaves persistent history and revision unchanged")
	# Authorizing a provider that reenters during preflight must never leave
	# Rust committed while the document rejects the source/permission change.
	var malicious: ReentrantDocument = ReentrantDocument.new("preflight-failure", STRIDE)
	var malicious_layer: String = str(malicious.create_layer(
		DrawingLayerNode.RASTER, "Ink").value)
	malicious.lock_on_read = 3
	var rejected: DrawingResult = stroke(malicious, malicious_layer,
		Vector2(11.5, 11.5), Vector2(14.5, 11.5))
	check(not rejected.ok and malicious.history_length() == 0 and
		malicious._nodes[malicious_layer].tiles.is_empty(),
		"reentrant source lock at document preflight commits no pixels/history")
	check(malicious._native_raster_store != null and
		int(malicious._native_raster_store.call("stats").get("revision", -1)) < malicious.revision,
		"preflight rejection leaves native store on prior source revision")
	check(malicious.set_locked(malicious_layer, false).ok, "reentrant lock can be repaired")
	malicious.lock_on_read = -1
	check(stroke(malicious, malicious_layer,
		Vector2(11.5, 11.5), Vector2(14.5, 11.5)).ok,
		"preflight cancellation can recover through checked rebase")
	# After a successful preflight there must be no second resolver callback
	# following Rust commit. That used to risk a half-native publication.
	var guarded: ReentrantDocument = ReentrantDocument.new("postcommit-guard", STRIDE)
	var guarded_layer: String = str(guarded.create_layer(
		DrawingLayerNode.RASTER, "Ink").value)
	guarded.lock_on_read = 4
	check(stroke(guarded, guarded_layer,
		Vector2(10.5, 10.5), Vector2(14.5, 10.5)).ok,
		"verified preflight publishes without post-Rust source callback")
	check(guarded.source_reads == 3 and not guarded._nodes[guarded_layer].locked and
		int(guarded._native_raster_store.call("stats").get("revision", -1)) == guarded.revision,
		"only authorization, precommit identity check and preflight resolve source")
	print("T148_PERSISTENT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
