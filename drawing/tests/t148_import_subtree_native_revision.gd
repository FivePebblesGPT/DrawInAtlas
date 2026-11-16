extends SceneTree
## T-148: importing detached subtrees must use the checked native revision
## bridge, rather than evicting unrelated Rust raster source and history.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0
var lazy_bytes: PackedByteArray = PackedByteArray()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_IMPORT_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func lazy_chunk(_reference: String) -> PackedByteArray:
	return lazy_bytes.duplicate()


func stroke(doc: DrawingDocument, layer: String, center: Vector2) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var bounds: Rect2i = Rect2i(-STRIDE, STRIDE, STRIDE, STRIDE) if center.x < 0.0 \
		else Rect2i(0, 0, STRIDE, STRIDE)
	var opened: DrawingResult = session.begin_native_stroke(brush, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, 0xff5599cc, bounds, true)
	if not opened.ok:
		session.cancel()
		return opened
	var painted: DrawingResult = session.paint_path_native(
		PackedVector2Array([center, center + Vector2(10, 0)]), 0xff5599cc, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func packed(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk(layer, key)
	if not result.ok or result.value == null:
		return PackedByteArray()
	return (result.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native store registered")
	var source: DrawingDocument = DrawingDocument.new("copy-source", STRIDE)
	var group: String = str(source.create_layer(DrawingLayerNode.GROUP, "Transfer").value)
	var raster: String = str(source.create_layer(DrawingLayerNode.RASTER, "Texture", group).value)
	var objects: String = str(source.create_layer(DrawingLayerNode.OBJECTS, "Entities", group).value)
	check(source.add_object(objects, {"position": Vector2(9, 11)}, "object-a").ok,
		"source has a semantic object")
	lazy_bytes.resize(STRIDE * STRIDE * 4)
	lazy_bytes.encode_u32(4 * (STRIDE + 3), 0x00112233)
	lazy_bytes.encode_u32(4 * (3 * STRIDE + 1), 0xaabbccdd)
	check(source.register_lazy_chunk(raster, -1, 1, "detached",
		DrawingRasterTile.digest_rgba8(lazy_bytes, STRIDE),
		Callable(self, "lazy_chunk")).ok, "signed lazy tile registered")
	var exported: DrawingResult = source.export_subtree(group)
	check(exported.ok and packed(source, raster, "-1,1") == lazy_bytes,
		"export resolves source and preserves transparent hidden RGB")

	var dest: DrawingDocument = DrawingDocument.new("copy-target", STRIDE)
	var ink: String = str(dest.create_layer(DrawingLayerNode.RASTER, "Resident").value)
	check(stroke(dest, ink, Vector2(8, 8)).ok, "prior native Brush owns canonical tile")
	var store: Object = dest._native_raster_store
	var original: PackedByteArray = packed(dest, ink, "0,0")
	var imported_bytes: int = int(store.call("stats").get("bytes_imported", -1))
	var history: int = int(store.call("stats").get("undo", -1))
	var previous: int = dest.revision
	var copied: DrawingResult = dest.import_subtree(exported.value, "root")
	var copied_group: String = str(copied.value)
	var copied_raster: String = dest.list_children(copied_group)[0] if copied.ok else ""
	check(copied.ok and copied_group != group and copied_raster != raster and
		dest.revision == previous + 1, "detached copy remaps IDs in one revision")
	check(dest._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == dest.revision and
		int(store.call("stats").get("undo", -1)) == history,
		"unreferenced raster import retains Rust source and native history")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported_bytes and
		packed(dest, ink, "0,0") == original,
		"import does not reimport or mutate existing brush RGBA8")
	check(packed(dest, copied_raster, "-1,1") == lazy_bytes and
		packed(source, raster, "-1,1") == lazy_bytes,
		"copied signed source is detached and byte-identical")
	check(dest.inspect_node(copied_group).children.size() == 2 and
		dest.inspect_node(dest.list_children(copied_group)[1]).objects.size() == 1,
		"nested semantic objects copied with remapped identity")
	check(stroke(dest, ink, Vector2(32, 34)).ok and
		dest._native_raster_store == store and
		int(store.call("stats").get("bytes_imported", -1)) == imported_bytes and
		int(store.call("stats").get("undo", -1)) == history + 1,
		"subsequent brush keeps canonical Rust store across import")
	check(dest.undo().ok and packed(dest, ink, "0,0") == original,
		"Undo newest native stroke after subtree import")
	check(dest.undo().ok and
		int(store.call("stats").get("undo", -1)) == history - 1,
		"Undo older native stroke crosses untracked imported subtree")
	check(dest.redo().ok and dest.redo().ok and
		int(store.call("stats").get("revision", -1)) == dest.revision,
		"Redo both native strokes restores one synchronized timeline")
	check(stroke(dest, copied_raster, Vector2(-53, 78)).ok and
		dest._native_raster_store == store,
		"first native edit of imported raster authorizes only its new source")
	check(int(store.call("stats").get("bytes_imported", -1)) > imported_bytes,
		"new imported raster lazily enters Rust when first painted")
	check(packed(dest, copied_raster, "-1,1") != lazy_bytes and
		int(dest.read_pixel(copied_raster, -61, 65).value) == 0x00112233,
		"editing copied raster preserves untouched signed hidden-RGB pixel")
	var save_path: String = ProjectSettings.globalize_path("user://t148-import-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(dest, save_path).ok, "native/copy mixed document saves")
	var loaded: DrawingResult = DrawingFileIO.open(save_path)
	check(loaded.ok and
		packed(loaded.value as DrawingDocument, copied_raster, "-1,1") ==
		packed(dest, copied_raster, "-1,1") and
		packed(loaded.value as DrawingDocument, ink, "0,0") == packed(dest, ink, "0,0"),
		"real Save/Open retains both imported source and resident native source")
	DirAccess.remove_absolute(save_path)

	# A semantic-only detached import is also metadata-only to the Rust store.
	var semantic: DrawingDocument = DrawingDocument.new("semantic-source", STRIDE)
	var semantic_layer: String = str(semantic.create_layer(DrawingLayerNode.OBJECTS, "Notes").value)
	var semantic_export: DrawingResult = semantic.export_subtree(semantic_layer)
	var before_semantic: int = dest.revision
	var undo_before: int = int(store.call("stats").get("undo", -1))
	check(dest.import_subtree(semantic_export.value, "root", true).ok and
		dest.revision == before_semantic + 1 and
		int(store.call("stats").get("revision", -1)) == dest.revision and
		int(store.call("stats").get("undo", -1)) == undo_before,
		"semantic-only import advances metadata revision without native rebase")

	# Invalid structure and parked native IDs must fail *before* publication.
	var malformed: Dictionary = exported.value.duplicate(true)
	var bad_group: DrawingLayerNode = malformed["nodes"][group]
	bad_group.children.append("ghost")
	var before_bad: int = dest.revision
	var before_layers: int = dest.layer_count()
	check(not dest.import_subtree(malformed, "root").ok and
		dest.revision == before_bad and dest.layer_count() == before_layers and
		int(store.call("stats").get("revision", -1)) == before_bad,
		"malformed detached subtree leaves Rust and Godot untouched")
	var owned: String = str(dest.create_layer(DrawingLayerNode.RASTER, "Parkable").value)
	check(stroke(dest, owned, Vector2(12, 14)).ok and
		dest.remove_subtree(owned, true).ok and
		bool(store.call("is_layer_parked", owned)),
		"recorded native subtree removal reserves parked identity")
	var parked_revision: int = dest.revision
	var forged: DrawingLayerNode = DrawingLayerNode.new(owned, DrawingLayerNode.RASTER, "Collision", "root")
	var collision: Dictionary = {"root": owned, "nodes": {owned: forged}}
	check(not dest.import_subtree(collision, "root", true).ok and
		dest.revision == parked_revision and not dest.has_node(owned) and
		bool(store.call("is_layer_parked", owned)),
		"import cannot reuse parked native raster ID")
	check(dest.undo().ok and dest.has_node(owned) and
		int(store.call("stats").get("revision", -1)) == dest.revision,
		"rejected import does not block native structural Undo")
	# Cross-document copy uses the same safe path, without aliasing or
	# invalidating an existing native store in the receiving document.
	var before_transfer: int = int(store.call("stats").get("undo", -1))
	var transferred: DrawingResult = DrawingDocument.transfer_subtree(source, dest,
		group, "root", source.revision, dest.revision)
	check(transferred.ok and source.has_node(group) and
		int(store.call("stats").get("revision", -1)) == dest.revision and
		int(store.call("stats").get("undo", -1)) == before_transfer,
		"cross-document copy retains native history and leaves source alive")
	# Direct unrecorded removals now retire the removed layer's canonical
	# tiles/history, so the same identifier may be safely imported with an
	# independent source. This is deliberately unlike recorded park/restore.
	var stale: DrawingDocument = DrawingDocument.new("reused-id", STRIDE)
	var original_id: String = str(stale.create_layer(DrawingLayerNode.RASTER,
		"Old", "root", "identity-unchanged").value)
	check(stroke(stale, original_id, Vector2(8, 8)).ok,
		"negative control creates native history for the original ID")
	var old_store: Object = stale._native_raster_store
	var old_undo: int = int(old_store.call("stats").get("undo", -1))
	check(stale.remove_subtree(original_id).ok and
		int(old_store.call("stats").get("revision", -1)) == stale.revision and
		int(old_store.call("stats").get("undo", -1)) == 0,
		"unrecorded owned-layer removal retires canonical history")
	var replacement: DrawingDocument = DrawingDocument.new("replacement-source", STRIDE)
	var new_id: String = str(replacement.create_layer(DrawingLayerNode.RASTER,
		"Replacement", "root", original_id).value)
	var detached: DrawingResult = replacement.export_subtree(new_id)
	var replaced: DrawingResult = stale.import_subtree(detached.value, "root", true)
	check(replaced.ok and stale.has_node(original_id) and
		int(old_store.call("stats").get("revision", -1)) == stale.revision and
		int(old_store.call("stats").get("undo", -1)) == 0 and old_undo == 1,
		"reused retired ID reenters through fresh unreferenced bridge")
	check(stroke(stale, original_id, Vector2(40, 40)).ok and
		int(old_store.call("stats").get("revision", -1)) == stale.revision and
		int(old_store.call("stats").get("undo", -1)) == 1,
		"next gesture records only replacement raster history without rebase")
	check(int(stale.read_pixel(original_id, 8, 8).value) == 0 and
		int(stale.read_pixel(original_id, 40, 40).value) != 0,
		"old native bytes cannot bleed into reused source identity")
	# Native metadata imports are intentionally bounded to 128 layer IDs.
	# Over-limit transfers must reject atomically when Rust is attached;
	# silently publishing Godot-only nodes would discard native history.
	var oversized: DrawingDocument = DrawingDocument.new("many-rasters", STRIDE)
	var oversized_group: String = str(oversized.create_layer(
		DrawingLayerNode.GROUP, "Bulk").value)
	for index: int in range(129):
		oversized.create_layer(DrawingLayerNode.RASTER, "Source %d" % index,
			oversized_group)
	var too_many: DrawingResult = oversized.export_subtree(oversized_group)
	var bulk: DrawingDocument = DrawingDocument.new("bounded-dest", STRIDE)
	var bulk_ink: String = str(bulk.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(stroke(bulk, bulk_ink, Vector2(8, 8)).ok and too_many.ok,
		"bounded-fallback fixture has native history and 129 raster layers")
	var bulk_store: Object = bulk._native_raster_store
	var bulk_base: int = bulk.revision
	var bulk_history: int = int(bulk_store.call("stats").get("undo", -1))
	var bulk_source: PackedByteArray = packed(bulk, bulk_ink, "0,0")
	var bulk_import: DrawingResult = bulk.import_subtree(too_many.value, "root")
	check(not bulk_import.ok and bulk_import.code == "NATIVE_STRUCTURE" and
		bulk.revision == bulk_base and bulk.list_children("root") == [bulk_ink] and
		int(bulk_store.call("stats").get("revision", -1)) == bulk_base,
		"over-limit native bridge rejects the entire Godot import")
	check(stroke(bulk, bulk_ink, Vector2(40, 40)).ok and
		int(bulk_store.call("stats").get("revision", -1)) == bulk.revision and
		int(bulk_store.call("stats").get("undo", -1)) == bulk_history + 1 and
		packed(bulk, bulk_ink, "0,0") != bulk_source,
		"post-rejection gesture preserves earlier native history without rebase")

	print("T148_IMPORT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
