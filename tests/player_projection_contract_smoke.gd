extends SceneTree
## T-039 proposed, non-production layer-grant boundary. A passing result is
## NOT approval of private/public, fog or preview policy for a player view.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_deny_by_default()
	_test_explicit_layer_scope()
	_test_fail_closed()
	_test_detached_pixels_and_objects()
	print("ATLAS_PLAYER_PROJECTION_CONTRACT_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PROJECTION CONTRACT FAILED: " + reason)


func _fixture() -> AtlasMapDocument:
	var document: AtlasMapDocument = AtlasMapDocument.new("secret-map-id", "GM: hidden dungeon")
	document.tags.append("hidden-entrance")
	document.grid.distance_unit = "SECRET UNIT"
	var ground: AtlasFloor = document.floors[0]
	ground.id = "private-floor-id"
	ground.display_name = "Basement: secret"
	ground.layers.clear()
	var approved: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(Color.RED))
	approved.id = "public-art-id"
	approved.display_name = "Approved drawing"
	ground.layers.append(approved)
	var secret: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(Color.GREEN))
	secret.id = "secret-art-id"
	secret.display_name = "GM traps"
	ground.layers.append(secret)
	var texts: AtlasObjectsLayer = AtlasObjectsLayer.new("private-text-id", "Private notes")
	var note: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2(4, 5)]), Color.WHITE, 18.0)
	note.text = "SECRET PASSWORD"
	texts.strokes.append(note)
	ground.layers.append(texts)
	var local: AtlasRasterLayer = AtlasRasterLayer.from_image(_image(Color.BLUE))
	local.id = "local-art-id"
	local.display_name = "Secret D1 plans"
	local.detail_level = 1
	ground.layers.append(local)
	document.default_floor_id = ground.id
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "hidden-upper"
	upper.display_name = "Hidden roof"
	document.floors.append(upper)
	return document


func _image(color: Color) -> Image:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _test_deny_by_default() -> void:
	var source: AtlasMapDocument = _fixture()
	var grants: Array[String] = []
	var output: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, grants)
	_check(output != null, "empty explicit grants yield an output, not source fallback")
	if output == null:
		return
	_check(output.floors.size() == 1 and output.floors[0].layers.is_empty(),
		"blank output includes no implicit raster, object, or other-floor data")
	_check(output.id != source.id and output.display_name != source.display_name \
		and output.tags.is_empty() and output.default_floor_id != source.default_floor_id,
		"map identity, tags, and floor identity are scrubbed")
	_check(output.grid.distance_unit == "unit" and not output.grid.visible \
		and output.grid.kind == source.grid.kind and output.grid.origin == source.grid.origin,
		"unapproved grid labels/visibility are scrubbed without shifting board geometry")
	_check(not JSON.stringify(output.to_dict()).contains("SECRET") \
		and not JSON.stringify(output.to_dict()).contains("secret") \
		and not JSON.stringify(output.to_dict()).contains("hidden"),
		"serialized empty view contains no secret metadata")
	# Audience strings in the existing editor cache partition images only;
	# they have never been a publication policy or permission check.
	var cache: AtlasPreviewCache = AtlasPreviewCache.new()
	var gm_image: Image = _image(Color.GREEN)
	cache.put_image(source, "private-floor-id", Vector2i(8, 8), gm_image, "player")
	_check(cache.get_image(source, "private-floor-id", Vector2i(8, 8), "player").get_pixel(0, 0) == Color.GREEN,
		"existing preview cache 'player' label does not filter GM pixels")


func _test_explicit_layer_scope() -> void:
	var source: AtlasMapDocument = _fixture()
	var grants: Array[String] = ["public-art-id"]
	var output: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, grants)
	_check(output != null, "explicitly granted public layer creates a view")
	var input: AtlasCampaign = AtlasPlayerProjection.build_capture_input(source, "private-floor-id", 0, grants)
	_check(input != null and input.maps.size() == 1 and input.links.is_empty() \
		and input.placements.is_empty() and input.root_map_id == AtlasPlayerProjection.BOARD_ID \
		and input.display_name == "Player output", "capture input contains only the sanitized map and no GM campaign graph")
	if output == null:
		return
	var floor: AtlasFloor = output.floors[0]
	_check(floor.layers.size() == 1 and floor.layers[0] is AtlasRasterLayer,
		"only the granted raster is present; private raster/text/LOD excluded")
	_check(output.floor_by_id("private-floor-id") == null and floor.layer_by_id("secret-art-id") == null,
		"private source IDs cannot resolve in output")
	_check(floor.layers[0].id == "art-0" and floor.layers[0].display_name == "Artwork" \
		and floor.layers[0].locked and not floor.layers[0] == source.floors[0].layers[0],
		"granted layer is immutable-by-editor, renamed and detached")
	var payload: String = JSON.stringify(output.to_dict())
	_check(not payload.contains("secret") and not payload.contains("SECRET") \
		and not payload.contains("public-art-id") and not payload.contains("hidden"),
		"dictionary payload includes no non-granted names or source layer identifiers")
	var inverted: Array[String] = ["secret-art-id", "public-art-id"]
	var two: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, inverted)
	_check(two != null and two.floors[0].layers.size() == 2 \
		and (two.floors[0].layers[0] as AtlasRasterLayer).chunks["0,0"].image.get_pixel(0, 0) == Color.RED,
		"layer stacking follows source order, never grant order")
	var d1: Array[String] = ["local-art-id"]
	var local: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 1, d1)
	_check(local != null and local.floors[0].layers.size() == 1 \
		and local.floors[0].layers[0].detail_level == 1,
		"only specifically granted D1 artwork enters the D1 view")


func _test_fail_closed() -> void:
	var source: AtlasMapDocument = _fixture()
	var valid: Array[String] = ["public-art-id"]
	var missing: Array[String] = ["missing"]
	var duplicate: Array[String] = ["public-art-id", "public-art-id"]
	var secret: Array[String] = ["secret-art-id"]
	_check(AtlasPlayerProjection.build_artwork_view(null, "private-floor-id", 0, valid) == null,
		"null source rejects")
	_check(AtlasPlayerProjection.build_artwork_view(source, "wrong-floor", 0, valid) == null,
		"wrong floor rejects")
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", -1, valid) == null \
		and AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 33, valid) == null,
		"invalid detail level rejects")
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, missing) == null \
		and AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, duplicate) == null,
		"stale and duplicate grants reject")
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 1, valid) == null \
		and AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, ["local-art-id"]) == null,
		"grants scoped to exactly one authored LOD")
	var hidden: AtlasRasterLayer = source.floors[0].layer_by_id("secret-art-id") as AtlasRasterLayer
	hidden.visible = false
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, secret) == null,
		"source visibility cannot force an explicitly denied layer to render")
	hidden.visible = true
	hidden.chunks["0,0"].image = null
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, secret) == null,
		"unresident asset is never passed as a lazy source reference")
	var collision: AtlasObjectsLayer = AtlasObjectsLayer.new("public-art-id", "Unintended alias")
	source.floors[0].layers.append(collision)
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, valid) == null,
		"ambiguous duplicate source layer IDs reject the complete view")
	source.floors[0].layers.pop_back()
	var invalid: AtlasRasterLayer = source.floors[0].layer_by_id("public-art-id") as AtlasRasterLayer
	invalid.pixels_per_unit = -1.0
	_check(AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, valid) == null,
		"invalid granted metadata rejects rather than skipping the layer")


func _test_detached_pixels_and_objects() -> void:
	var source: AtlasMapDocument = _fixture()
	var grants: Array[String] = ["public-art-id"]
	var output: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, grants)
	_check(output != null, "detachment setup succeeds")
	if output == null:
		return
	var original: AtlasRasterLayer = source.floors[0].layer_by_id("public-art-id") as AtlasRasterLayer
	var copy: AtlasRasterLayer = output.floors[0].layers[0] as AtlasRasterLayer
	original.chunks["0,0"].image.fill(Color.CYAN)
	_check(copy.chunks["0,0"].image.get_pixel(1, 1) == Color.RED,
		"editing source pixel bytes cannot mutate an issued view")
	copy.chunks["0,0"].image.fill(Color.BLUE)
	_check(original.chunks["0,0"].image.get_pixel(1, 1) == Color.CYAN,
		"writing to an issued view cannot mutate canonical raster pixels")
	var text_grant: Array[String] = ["private-text-id"]
	var text_view: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, text_grant)
	_check(text_view != null and text_view.floors[0].layers.size() == 1,
		"entire Objects layers require explicit grants")
	if text_view == null:
		return
	var source_text: AtlasObjectsLayer = source.floors[0].layer_by_id("private-text-id") as AtlasObjectsLayer
	var output_text: AtlasObjectsLayer = text_view.floors[0].layers[0] as AtlasObjectsLayer
	_check(output_text.strokes.size() == 1 and output_text.strokes[0].text == "SECRET PASSWORD",
		"granting a mixed/private Objects layer WILL expose its text; policy must forbid this")
	source_text.strokes[0].text = "edited later"
	_check(output_text.strokes[0].text == "SECRET PASSWORD",
		"issued Objects snapshots do not share mutable strokes")
	var revoked: Array[String] = []
	var after_revoke: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source, "private-floor-id", 0, revoked)
	_check(after_revoke != null and after_revoke.floors[0].layers.is_empty(),
		"a new denied view is blank after revocation (caller must discard old output)")
