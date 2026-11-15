extends SceneTree
## T-148: metadata-only tree/semantic changes must not evict canonical native
## brush tiles or lose raster Undo/Redo ordering on the shared revision timeline.

const STRIDE: int = 64
const INK: int = 0xff5599cc
var checks: int = 0
var failures: int = 0
var lazy_data: PackedByteArray = PackedByteArray()


func lazy_chunk(_reference: String) -> PackedByteArray:
	return lazy_data.duplicate()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T148_METADATA_FAILED: " + label)


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
	var resolved: DrawingResult = doc.request_chunk(layer, "0,0")
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension registered")
	var doc: DrawingDocument = DrawingDocument.new("metadata-native", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var first: DrawingResult = stroke(doc, layer, Vector2(8.5, 8.5))
	check(first.ok and first.delta.native_history_token > 0, "native first stroke")
	if not first.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var first_bytes: PackedByteArray = packed(doc, layer)
	var imported: int = int(store.call("stats").get("bytes_imported", -1))
	check(doc.rename_layer(layer, "Renamed", true).ok, "rename is recorded in Godot history")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == 1,
		"metadata changes advance shared revision without evicting Rust history")
	check(packed(doc, layer) == first_bytes, "rename does not modify canonical RGBA8")
	var second: DrawingResult = stroke(doc, layer, Vector2(32.5, 32.5))
	var both_bytes: PackedByteArray = packed(doc, layer)
	check(second.ok and both_bytes != first_bytes and
		int(store.call("stats").get("undo", -1)) == 2,
		"second stroke reuses native history after rename")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported,
		"metadata-only change requires no source reimport")
	check(doc.undo().ok and packed(doc, layer) == first_bytes,
		"undo newest native stroke restores first RGBA8")
	check(doc.undo().ok and doc.node_metadata(layer).get("name") == "Ink" and
		int(store.call("stats").get("redo", -1)) == 1,
		"undo metadata retains native redo stack")
	check(doc.undo().ok and int(store.call("stats").get("undo", -1)) == 0,
		"undo oldest raster event uses same Rust stack")
	check(doc.redo().ok and packed(doc, layer) == first_bytes,
		"redo oldest native raster event")
	check(doc.redo().ok and doc.node_metadata(layer).get("name") == "Renamed",
		"redo metadata retains later native redo")
	check(doc.redo().ok and packed(doc, layer) == both_bytes and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"redo newest raster event remains native and byte exact")
	check(doc.undo().ok and int(store.call("stats").get("redo", -1)) == 1,
		"undo native stroke opens redo branch")
	check(doc.set_locked(layer, true).ok and
		int(store.call("stats").get("redo", -1)) == 0,
		"new untracked metadata mutation clears native redo branch")
	check(not stroke(doc, layer, Vector2(45.5, 45.5)).ok,
		"locked layer rejects native brush while history is retained")
	check(doc.set_locked(layer, false).ok and
		int(store.call("stats").get("undo", -1)) == 1,
		"unlock preserves older native raster token")
	var objects: String = str(doc.create_layer(DrawingLayerNode.OBJECTS, "Objects", "root", "", -1, true).value)
	check(not objects.is_empty() and doc.add_object(objects, {"position": Vector2(3, 5)}, "obj").ok and
		doc.move_object(objects, "obj", Vector2(6, 7)).ok,
		"tree and semantic-object edits use metadata revision bridge")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("bytes_imported", -1)) == imported,
		"tree and semantic edits preserve native pixels without import")
	check(stroke(doc, layer, Vector2(45.5, 45.5)).ok and
		int(store.call("stats").get("undo", -1)) == 2,
		"brush resumes after semantic operations with retained token")
	var saved_path: String = ProjectSettings.globalize_path("user://t148-meta-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, saved_path).ok, "mixed metadata/raster source saves")
	var reopened: DrawingResult = DrawingFileIO.open(saved_path)
	check(reopened.ok and packed(reopened.value as DrawingDocument, layer) == packed(doc, layer),
		"save/reload raster pixels agree across metadata operations")
	DirAccess.remove_absolute(saved_path)
	# Semantic subtree deletion must not evict unrelated native pixels or
	# reversible history. Exercise the structural Undo/Redo replay too.
	var semantic_bytes: PackedByteArray = packed(doc, layer)
	var semantic_history: int = int(store.call("stats").get("undo", -1))
	check(doc.remove_subtree(objects, true).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == semantic_history,
		"remove semantic subtree retains native source/history")
	check(doc.undo().ok and doc.has_node(objects) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"restore semantic subtree preserves Rust revision")
	check(doc.redo().ok and not doc.has_node(objects) and
		packed(doc, layer) == semantic_bytes and
		int(store.call("stats").get("undo", -1)) == semantic_history,
		"semantic subtree redo preserves native raster bytes/history")
	check(stroke(doc, layer, Vector2(52.5, 53.5)).ok and
		doc._native_raster_store == store and
		int(store.call("stats").get("bytes_imported", -1)) == imported and
		int(store.call("stats").get("undo", -1)) == semantic_history + 1,
		"brush after semantic removal reuses existing native tile history")
	# Nested group, text and semantic objects carry no RGBA8 tiles. Replaying
	# both subtree removal and a separate structural create must leave the
	# previously imported Rust source untouched.
	var semantic_group: String = str(doc.create_layer(
		DrawingLayerNode.GROUP, "Semantic group", "root", "", -1, true).value)
	var semantic_objects: String = str(doc.create_layer(
		DrawingLayerNode.OBJECTS, "Objects", semantic_group, "", -1, true).value)
	var semantic_text: String = str(doc.create_layer(
		DrawingLayerNode.TEXT, "Text", semantic_group, "", -1, true).value)
	check(not semantic_group.is_empty() and not semantic_objects.is_empty() and
		not semantic_text.is_empty() and
		doc.add_object(semantic_objects, {"position": Vector2(1, 2)}, "token").ok,
		"nested semantic subtree registered")
	var nested_imports: int = int(store.call("stats").get("bytes_imported", -1))
	var nested_undo: int = int(store.call("stats").get("undo", -1))
	check(doc.remove_subtree(semantic_group, true).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == nested_undo,
		"nested semantic removal keeps native authority")
	check(doc.undo().ok and doc.has_node(semantic_text) and
		doc.has_node(semantic_objects) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"nested semantic undo restores structure with native revision")
	check(doc.redo().ok and not doc.has_node(semantic_group) and
		int(store.call("stats").get("bytes_imported", -1)) == nested_imports,
		"nested semantic redo does not reimport canonical tiles")
	var added: String = str(doc.create_layer(
		DrawingLayerNode.OBJECTS, "Created", "root", "", -1, true).value)
	check(not added.is_empty() and doc.undo().ok and not doc.has_node(added) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"undo semantic create preserves native authority")
	check(doc.redo().ok and doc.has_node(added) and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == nested_undo,
		"redo semantic create preserves native tokens")
	# A raster subtree with no *native* source/history can use the same
	# revision bridge as semantic metadata. Test nested IDs, a deferred signed
	# tile, exact hidden RGB and alternating structural Undo/Redo.
	var virgin_group: String = str(doc.create_layer(DrawingLayerNode.GROUP,
		"Virgin raster group", "root", "", -1, true).value)
	var virgin_a: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Unimported lazy", virgin_group, "", -1, true).value)
	var virgin_b: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Unimported empty", virgin_group, "", -1, true).value)
	lazy_data.resize(STRIDE * STRIDE * 4)
	lazy_data.encode_u32(0, 0x00123456)
	check(doc.register_lazy_chunk(virgin_a, -1, 1, "lazy-hidden",
		DrawingRasterTile.digest_rgba8(lazy_data, STRIDE),
		Callable(self, "lazy_chunk")).ok, "deferred raster source registered without import")
	var virgin_history: int = int(store.call("stats").get("undo", -1))
	var virgin_imports: int = int(store.call("stats").get("bytes_imported", -1))
	check(doc.remove_subtree(virgin_group, true).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == virgin_history,
		"nested never-imported raster removal preserves unrelated Rust history")
	check(doc.undo().ok and doc.has_node(virgin_a) and doc.has_node(virgin_b) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"restore unimported raster children retains native revision")
	check(doc.request_chunk(virgin_a, "-1,1").ok and
		(doc.request_chunk(virgin_a, "-1,1").value as DrawingRasterTile).to_rgba8() == lazy_data,
		"restored deferred signed tile preserves canonical hidden RGB")
	check(doc.redo().ok and not doc.has_node(virgin_group) and
		int(store.call("stats").get("undo", -1)) == virgin_history and
		int(store.call("stats").get("bytes_imported", -1)) == virgin_imports,
		"redo unimported raster deletion preserves existing native source")
	check(doc.undo().ok and doc.has_node(virgin_a) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"second restore of unimported raster remains synchronized")
	check(stroke(doc, layer, Vector2(56.5, 33.5)).ok and
		doc._native_raster_store == store and
		int(store.call("stats").get("undo", -1)) == virgin_history + 1 and
		int(store.call("stats").get("bytes_imported", -1)) == virgin_imports,
		"next unrelated Brush reuses history without canonical reimport")
	var virgin_save: String = ProjectSettings.globalize_path("user://t148-virgin-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, virgin_save).ok, "mixed never-imported raster/Brush saves")
	var virgin_open: DrawingResult = DrawingFileIO.open(virgin_save)
	check(virgin_open.ok and
		(virgin_open.value as DrawingDocument).request_chunk(virgin_a, "-1,1").ok and
		((virgin_open.value as DrawingDocument).request_chunk(virgin_a, "-1,1").value as DrawingRasterTile).to_rgba8() == lazy_data,
		"restored deferred source is byte-identical after Save/Open")
	DirAccess.remove_absolute(virgin_save)
	# Imported tile and native history forbid a metadata-only structural
	# revision, even if the node is nested beneath an otherwise empty group.

	var group: String = str(doc.create_layer(DrawingLayerNode.GROUP, "Mixed").value)
	var nested: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Nested", group).value)
	check(not group.is_empty() and not nested.is_empty(), "nested raster subtree created")
	check(stroke(doc, nested, Vector2(19.5, 19.5)).ok,
		"nested raster tile is authorized and enters native history")
	var before_remove_revision: int = doc.revision
	check(doc.remove_subtree(group, true).ok and
		doc.revision == before_remove_revision + 1 and
		int(store.call("stats").get("revision", -1)) < doc.revision,
		"raster-bearing subtree removal retains conservative rebase guard")
	check(stroke(doc, layer, Vector2(24.5, 52.5)).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == 1,
		"subsequent brush rebases after raster-bearing deletion")
	print("T148_METADATA_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
