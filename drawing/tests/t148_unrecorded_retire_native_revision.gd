extends SceneTree
## Unrecorded raster subtree deletion must retire only its owned Rust layers,
## retaining other canonical tiles and native history without stale ID reuse.

const STRIDE: int = 64
const INK: int = 0xff5599cc
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T148_RETIRE_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func stroke(doc: DrawingDocument, layer: String, center: Vector2) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var opened: DrawingResult = session.begin_native_stroke(brush, "NativeHard", "",
		8.0, INK, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not opened.ok:
		session.cancel()
		return opened
	var painted: DrawingResult = session.paint_path_native(
		PackedVector2Array([center, center + Vector2(10, 0)]), INK, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func packed(doc: DrawingDocument, layer: String) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk(layer, "0,0")
	if not result.ok or result.value == null:
		return PackedByteArray()
	return (result.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension registered")
	var doc: DrawingDocument = DrawingDocument.new("retire-source", STRIDE)
	var keep: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Keep").value)
	var deleted: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Remove").value)
	var first: DrawingResult = stroke(doc, keep, Vector2(8, 8))
	var removed: DrawingResult = stroke(doc, deleted, Vector2(8, 8))
	var second: DrawingResult = stroke(doc, keep, Vector2(32, 32))
	check(first.ok and removed.ok and second.ok, "three native gestures across two layers")
	if not first.ok or not removed.ok or not second.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var before: PackedByteArray = packed(doc, keep)
	var old_deleted: PackedByteArray = packed(doc, deleted)
	var history: int = int(store.call("stats").get("undo", -1))
	var used: int = int(store.call("stats").get("bytes_used", -1))
	var imports: int = int(store.call("stats").get("bytes_imported", -1))
	check(history == 3 and old_deleted != PackedByteArray(), "all native history resident")
	var previous: int = doc.revision
	check(doc.remove_subtree(deleted).ok and not doc.has_node(deleted),
		"unrecorded native-owned raster layer removed")
	check(doc.revision == previous + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == history - 1,
		"retirement advances one revision and prunes only deleted-layer history")
	check(int(store.call("stats").get("bytes_used", -1)) < used and
		not bool(store.call("has_source", deleted, 0, 0, doc.revision)),
		"retirement frees source bytes, authorization and reversible buffers")
	check(packed(doc, keep) == before and
		bool(store.call("has_source", keep, 0, 0, doc.revision)),
		"unrelated canonical tile bytes and source authorization unchanged")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("bytes_imported", -1)) == imports,
		"untracked removal performs no source reimport")
	check(doc.history_length() == 2 and doc.history_position() == 2,
		"retirement prunes obsolete local events but keeps unrelated history order")
	check(doc.undo().ok and packed(doc, keep) != before,
		"Undo surviving top native token after deletion")
	check(doc.redo().ok and packed(doc, keep) == before and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"Redo surviving native token maintains byte-exact source")
	check(doc.undo().ok and doc.undo().ok and
		int(store.call("stats").get("undo", -1)) == 0,
		"both older surviving native tokens remain locally undoable")
	check(doc.redo().ok and doc.redo().ok and packed(doc, keep) == before and
		int(store.call("stats").get("undo", -1)) == 2,
		"both surviving tokens redo in original order")
	# A direct removal does not reserve its IDs: transfer of a distinct raster
	# with the same identifier must never recover retired canonical bytes.
	var replacement_doc: DrawingDocument = DrawingDocument.new("replacement", STRIDE)
	check(replacement_doc.create_layer(DrawingLayerNode.RASTER, "Replacement", "root",
		deleted).ok, "detached replacement uses prior identifier")
	var replacement: DrawingResult = replacement_doc.export_subtree(deleted)
	var inserted: DrawingResult = doc.import_subtree(replacement.value, "root", true)
	check(inserted.ok and str(inserted.value) == deleted and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == 2,
		"reused ID imports with no stale Rust history or forced rebase")
	check(int(doc.read_pixel(deleted, 8, 8).value) == 0,
		"old retired pigment never leaks into reused layer")
	check(stroke(doc, deleted, Vector2(40, 40)).ok and
		int(store.call("stats").get("undo", -1)) == 3,
		"first new Brush on reused ID creates fresh native history")
	check(int(doc.read_pixel(deleted, 8, 8).value) == 0 and
		int(doc.read_pixel(deleted, 40, 40).value) != 0,
		"new raster contains only replacement pigment")
	var file: String = ProjectSettings.globalize_path("user://t148-retire-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, file).ok, "mixed retained/replaced raster saves")
	var reopened: DrawingResult = DrawingFileIO.open(file)
	check(reopened.ok and packed(reopened.value as DrawingDocument, keep) == packed(doc, keep) and
		packed(reopened.value as DrawingDocument, deleted) == packed(doc, deleted),
		"real Save/Open is byte exact across retired and reused ID")
	DirAccess.remove_absolute(file)
	# Nested unrecorded removal must retire the whole group atomically while
	# leaving another native layer's history and bytes available.
	var group: String = str(doc.create_layer(DrawingLayerNode.GROUP, "Nested").value)
	var one: String = str(doc.create_layer(DrawingLayerNode.RASTER, "One", group).value)
	var two: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Two", group).value)
	check(stroke(doc, one, Vector2(8, 8)).ok and stroke(doc, two, Vector2(30, 32)).ok,
		"nested group has two owned native raster children")
	var kept_history: int = int(store.call("stats").get("undo", -1))
	var kept_bytes: PackedByteArray = packed(doc, keep)
	check(doc.remove_subtree(group).ok and not doc.has_node(one) and not doc.has_node(two),
		"unrecorded nested native subtree removed")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == kept_history - 2 and
		packed(doc, keep) == kept_bytes,
		"all nested owned IDs retired without evicting unrelated history")
	# In-place source mutations are not an authorized retirement. The next
	# native edit must rebase, not preserve a poisoned resident source.
	var stale: DrawingDocument = DrawingDocument.new("stale-owner", STRIDE)
	var safe: String = str(stale.create_layer(DrawingLayerNode.RASTER, "Safe").value)
	var victim: String = str(stale.create_layer(DrawingLayerNode.RASTER, "Victim").value)
	check(stroke(stale, safe, Vector2(8, 8)).ok and
		stroke(stale, victim, Vector2(10, 10)).ok,
		"stale-source fixture owns two layers")
	var old_store: Object = stale._native_raster_store
	var previous_native: int = int(old_store.call("stats").get("revision", -1))
	(stale._nodes[victim].tiles["0,0"] as DrawingRasterTile).set_rgba(0, 0, 0x00112233)
	check(stale.remove_subtree(victim).ok and stale.revision == previous_native + 1 and
		int(old_store.call("stats").get("revision", -1)) == previous_native,
		"tampered canonical source refuses fast retirement; bridge stays stale")
	check(stroke(stale, safe, Vector2(40, 40)).ok and
		int(old_store.call("stats").get("revision", -1)) == stale.revision and
		int(old_store.call("stats").get("undo", -1)) == 1,
		"next Brush performs checked rebase without accepting stale history")
	# Native park/restore remains reserved for reversible recorded removals.
	var parked_doc: DrawingDocument = DrawingDocument.new("parked", STRIDE)
	var park: String = str(parked_doc.create_layer(DrawingLayerNode.RASTER, "Park").value)
	check(stroke(parked_doc, park, Vector2(8, 8)).ok and
		parked_doc.remove_subtree(park, true).ok, "recorded subtree is parked")
	var parked_store: Object = parked_doc._native_raster_store
	var parked_revision: int = parked_doc.revision
	check(not bool(parked_store.call("retire_layers_revision", parked_revision,
		PackedStringArray([park]), true)) and
		bool(parked_store.call("is_layer_parked", park)) and
		int(parked_store.call("stats").get("revision", -1)) == parked_revision,
		"retirement rejects already parked history without mutation")
	check(parked_doc.undo().ok and parked_doc.has_node(park),
		"parked structural Undo still restores original source")
	# A host-owned timeline never appends the document's local structure event.
	# Even if a host passes record_history=true, direct deletion still retires
	# only the deleted native layer and keeps other native canonical tiles.
	var host: DrawingDocument = DrawingDocument.new("external-owner", STRIDE)
	check(host.set_external_history(true).ok, "host owns global edit timeline")
	var host_keep: String = str(host.create_layer(DrawingLayerNode.RASTER, "Keep").value)
	var host_deleted: String = str(host.create_layer(DrawingLayerNode.RASTER, "Delete").value)
	check(stroke(host, host_keep, Vector2(8, 8)).ok and
		stroke(host, host_deleted, Vector2(20, 20)).ok,
		"host timeline has two native raster sources")
	var host_store: Object = host._native_raster_store
	var original_host: PackedByteArray = packed(host, host_keep)
	check(host.remove_subtree(host_deleted, true).ok and
		int(host_store.call("stats").get("revision", -1)) == host.revision and
		int(host_store.call("stats").get("undo", -1)) == 1 and
		packed(host, host_keep) == original_host,
		"external history removes native-owned subtree without a local park event")
	check(host.history_length() == 0 and
		stroke(host, host_keep, Vector2(40, 40)).ok and
		int(host_store.call("stats").get("undo", -1)) == 2,
		"host remains history owner; native Brush reuses unaffected canonical source")
	print("T148_RETIRE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
