extends SceneTree
## T-064: real saved source pixels composited through nested affine instances.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_RENDER_FAILED: " + name)


func _source(name: String, color: int) -> DrawingDocument:
	var source: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	var staged: DrawingResult = edit.fill_rect(Rect2i(0, 0, 1, 1), color)
	if not staged.ok or not edit.commit().ok:
		push_error("T064_RENDER_FAILED: source preparation")
	return source


func _pixel(image: Image, region: Rect2i, at: Vector2i) -> Color:
	return image.get_pixelv(at - region.position)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-render-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var a: DrawingResult = library.create_asset(_source("parent", 0xff0000ff), "Parent")
	var b: DrawingResult = library.create_asset(_source("child", 0xff00ff00), "Child")
	var c: DrawingResult = library.create_asset(_source("grandchild", 0xffff0000), "Grandchild")
	_check(a.ok and b.ok and c.ok, "publish three separate immutable pixel sources")
	if not a.ok or not b.ok or not c.ok:
		quit(1)
		return
	var aid: String = str(a.value)
	var bid: String = str(b.value)
	var cid: String = str(c.value)
	var placement: DrawingResult = library.place(aid, "world", "ground", "D0",
		Transform2D(0.0, Vector2(20, 10)))
	_check(placement.ok, "place parent at nonzero world translation")
	if not placement.ok:
		quit(1)
		return
	var instance_id: String = str(placement.value)
	var first: DrawingResult = library.render_instance(instance_id, Rect2i(-4, -5, 16, 13))
	_check(first.ok and first.value["status"] == "linked", "flat root still renders")
	var ab: DrawingResult = library.attach_child(aid, 0, bid,
		Transform2D(0.0, Vector2(5, -3)))
	var bc: DrawingResult = library.attach_child(bid, 0, cid,
		Transform2D(0.0, Vector2(-2, 4)))
	_check(ab.ok and bc.ok, "root, child and grandchild have composable local transforms")
	var area: Rect2i = Rect2i(-4, -5, 16, 13)
	var rendered: DrawingResult = library.render_instance(instance_id, area)
	_check(rendered.ok, "bounded read-only nested render succeeds")
	if not rendered.ok:
		quit(1)
		return
	var image: Image = rendered.value["image"]
	_check(_pixel(image, area, Vector2i(0, 0)).r > 0.9,
		"root source pixel retains its own origin")
	_check(_pixel(image, area, Vector2i(5, -3)).g > 0.9,
		"child source is translated into root source coordinates")
	_check(_pixel(image, area, Vector2i(3, 1)).b > 0.9,
		"grandchild composes both transforms")
	_check(_pixel(image, area, Vector2i(-2, 4)).a == 0.0,
		"transparent space is not turned into an Object hit")
	var child_hit: DrawingResult = library.hit_test_path(instance_id, Vector2(25.5, 7.5))
	_check(child_hit.ok and child_hit.value is Dictionary and \
			child_hit.value["path"] == PackedStringArray([str(ab.value)]),
		"child selection resolves stable one-link path")
	var grand_hit: DrawingResult = library.hit_test_path(instance_id, Vector2(23.5, 11.5))
	_check(grand_hit.ok and grand_hit.value is Dictionary and \
			grand_hit.value["path"] == PackedStringArray([str(ab.value), str(bc.value)]),
		"deepest hit resolves grandchild path through parent and child")
	_check(library.hit_test(instance_id, Vector2(23.5, 11.5)).value == true,
		"existing Atlas placement hit-test includes nested pixels")
	_check(library.hit_test(instance_id, Vector2(25.5, 20.5)).value == false,
		"no invisible nested shape is selectable")
	var bounds: DrawingResult = library.composed_bounds(aid)
	_check(bounds.ok and bounds.value.has_point(Vector2i(3, 1)) and \
			bounds.value.has_point(Vector2i(5, -3)),
		"frame contains transformed child and grandchild beyond parent guide")
	_check(not library.render_source_tree(aid, Rect2i(0, 0, 1100000, 1)).ok,
		"render viewport limit rejects oversized source request")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new()
	history.reset(campaign)
	var adapter: AtlasDrawingComposition = AtlasDrawingComposition.new(history, library)
	_check(adapter.attach_campaign(campaign).ok, "Atlas composition mounts the nested asset library")
	var world_region: Rect2i = Rect2i(18, 5, 16, 14)
	var atlas_first: DrawingResult = adapter.render_region("world", "ground", 0, world_region)
	_check(atlas_first.ok and _pixel(atlas_first.value, world_region, Vector2i(25, 7)).g > 0.9 \
		and _pixel(atlas_first.value, world_region, Vector2i(23, 11)).b > 0.9,
		"Atlas read-only map composition draws nested children at world positions")
	_check(adapter.authored_bounds_world("world", "ground", 0).has_point(Vector2(23.5, 11.5)),
		"Atlas preview bounds include nested child transforms")
	var top: DrawingResult = library.attach_child(aid, 1, cid,
		Transform2D(0.0, Vector2(5, -3)))
	_check(top.ok, "second sibling can reuse the same source identity")
	var overdraw: DrawingResult = library.render_source_tree(aid, area)
	_check(overdraw.ok and _pixel(overdraw.value, area, Vector2i(5, -3)).b > 0.9,
		"later sibling paints over earlier child source")
	var atlas_reordered: DrawingResult = adapter.render_region("world", "ground", 0, world_region)
	_check(atlas_reordered.ok and _pixel(atlas_reordered.value, world_region, Vector2i(25, 7)).b > 0.9,
		"child-graph publication invalidates Atlas's cached source composition")
	var top_hit: DrawingResult = library.hit_test_path(instance_id, Vector2(25.5, 7.5))
	_check(top_hit.ok and top_hit.value is Dictionary and \
			top_hit.value["path"] == PackedStringArray([str(top.value)]),
		"topmost sibling wins selection without losing its child ID")
	var turned: DrawingResult = library.attach_child(aid, 2, cid,
		Transform2D(PI / 2.0, Vector2(9, 3)))
	_check(turned.ok, "quarter-turn child publishes a finite invertible affine transform")
	var rotated_image: DrawingResult = library.render_source_tree(aid, area)
	_check(rotated_image.ok and _pixel(rotated_image.value, area, Vector2i(8, 3)).b > 0.9,
		"rotated child raster pixel samples the composed local footprint")
	var rotated_hit: DrawingResult = library.hit_test_path(instance_id, Vector2(28.5, 13.5))
	_check(rotated_hit.ok and rotated_hit.value is Dictionary and \
		rotated_hit.value["path"] == PackedStringArray([str(turned.value)]),
		"rotated child remains individually selectable at world location")
	var draft: AtlasObjectDraft = library.begin_draft(cid).value
	var layer: String = draft.document.list_children()[0]
	var editing: DrawingEditSession = draft.document.begin_edit(layer, draft.document.revision).value
	_check(editing.fill_rect(Rect2i(1, 0, 1, 1), 0xffffffff).ok and editing.commit().ok,
		"child document can be edited privately")
	var unpublished: DrawingResult = library.render_source_tree(aid, area)
	_check(unpublished.ok and _pixel(unpublished.value, area, Vector2i(4, 1)).a == 0.0,
		"unpublished grandchild draft does not leak into parent")
	_check(library.save_draft(draft).ok, "explicit child Save publishes a new immutable version")
	var updated: DrawingResult = library.render_source_tree(aid, area)
	_check(updated.ok and _pixel(updated.value, area, Vector2i(4, 1)).a > 0.9,
		"parent resolves newly published grandchild content after Save")
	var atlas_saved: DrawingResult = adapter.render_region("world", "ground", 0, world_region)
	_check(atlas_saved.ok and _pixel(atlas_saved.value, world_region, Vector2i(24, 11)).a > 0.9,
		"child source Save invalidates Atlas preview through asset publication")
	var reload: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	_check(reload.load().ok, "nested graph remains portable after save and reload")
	var reloaded: DrawingResult = reload.render_source_tree(aid, area)
	_check(reloaded.ok and _pixel(reloaded.value, area, Vector2i(4, 1)).a > 0.9,
		"reloaded graph renders the updated grandchild without baked pixels")
	var removed: DrawingResult = library.delete_asset(cid, "null")
	_check(removed.ok, "source deletion applies existing NULL policy to nested children")
	var null_hit: DrawingResult = library.hit_test_path(instance_id, Vector2(15.5, 10.5))
	_check(null_hit.ok and null_hit.value is Dictionary and null_hit.value["status"] == "NULL" \
			and null_hit.value["path"] == PackedStringArray([str(ab.value), str(bc.value)]),
		"missing grandchild remains selectable as a stable NULL path")
	var null_image: DrawingResult = library.render_source_tree(aid, area)
	_check(null_image.ok and _pixel(null_image.value, area, Vector2i(3, 1)).a > 0.0,
		"NULL child marker remains visible in parent composition")
	_check(not library.render_source_tree(aid, Rect2i(0, 0, 1100000, 2)).ok,
		"pathological source viewport fails closed rather than allocating huge pixels")
	print("T064_CHILD_RENDER_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
