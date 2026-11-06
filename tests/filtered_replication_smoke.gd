extends SceneTree
## T-046: primitive wire payloads and authoritative GM/player/spectator roles.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FILTERED REPLICATION FAILED: " + description)


func _raster(id: String, label: String, color: Color, lod: int = 0) -> AtlasRasterLayer:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	layer.id = id
	layer.display_name = label
	layer.detail_level = lod
	return layer


func _fixture() -> Dictionary:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.display_name = "SUPER SECRET campaign"
	var map: AtlasMapDocument = AtlasMapDocument.new("board", "SUPER SECRET map")
	map.tags.append("SUPER SECRET tag")
	var floor: AtlasFloor = map.floors[0]
	floor.layers.clear()
	floor.layers.append(_raster("public", "Public artwork", Color.RED))
	floor.layers.append(_raster("secret", "SUPER SECRET traps", Color.GREEN))
	floor.layers.append(_raster("d1", "SUPER SECRET D1", Color.BLUE, 1))
	var objects: AtlasObjectsLayer = AtlasObjectsLayer.new("notes", "SUPER SECRET notes")
	var note: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2.ONE]), Color.WHITE, 15.0)
	note.text = "SUPER SECRET PASSWORD"
	objects.strokes.append(note)
	floor.layers.append(objects)
	var tokens: AtlasTokenLayer = AtlasTokenLayer.new("gm-tokens", "SUPER SECRET token layer")
	tokens.tokens = [AtlasToken.new("hidden-token", Vector2(2, 3), "SUPER SECRET Rogue")]
	floor.layers.append(tokens)
	campaign.add_map(map)
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "board"
	var host: AtlasHostSession = AtlasHostSession.new(campaign, history, "session", "board",
		"ground", "gm-tokens")
	return {"host": host, "map": map, "floor": floor,
		"history": history, "campaign": campaign, "tokens": tokens}


func _pixel(payload: Dictionary, x: int = 0, y: int = 0) -> Color:
	var layers: Array = payload["floors"][0]["layers"]
	var chunk: Dictionary = layers[0]["chunks"][0]
	var image: Image = Image.new()
	var raw: PackedByteArray = Marshalls.base64_to_raw(chunk["png_base64"])
	if image.load_png_from_buffer(raw) != OK:
		return Color.MAGENTA
	return image.get_pixel(x, y)


func _run() -> void:
	_join_and_authority()
	_fog_and_revocation()
	_divergence_and_shutdown()
	print("ATLAS_FILTERED_REPLICATION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _join_and_authority() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture.host
	var gm: AtlasSessionClient = host.join("gm")
	var player: AtlasSessionClient = host.join_as("player", "player", ["public"])
	var spectator: AtlasSessionClient = host.join_as("audience", "spectator")
	_check(gm != null and player != null and spectator != null,
		"trusted controller establishes three distinct host-owned roles")
	if gm == null or player == null or spectator == null:
		return
	_check(gm.token_records().size() == 1 and gm.artwork_record().is_empty(),
		"GM receives token editing scope, not public raster payload")
	_check(player.token_records().is_empty() and spectator.token_records().is_empty(),
		"player and spectator never receive host token records")
	_check(spectator.artwork_record().is_empty(), "viewer without grants receives blank payload")
	var published: Dictionary = player.artwork_record()
	_check(published.has("floors") and published["floors"].size() == 1,
		"granted player receives a sanitized one-floor raster DTO")
	_check(published["floors"][0]["layers"].size() == 1
		and published["floors"][0]["layers"][0]["id"] == "art-0",
		"only explicitly granted layer passes with a sanitized identifier")
	_check(_pixel(published) == Color.RED, "viewer PNG contains authorized red pixels")
	var wire: String = JSON.stringify(host.snapshot_for(player))
	_check(not wire.contains("SUPER SECRET") and not wire.contains("hidden-token")
		and not wire.contains("public\"") and not wire.contains("gm-tokens")
		and not wire.contains("secret\"") and not wire.contains("notes\""),
		"serialized snapshot omits source metadata, token IDs, and private labels")
	var decoded: Variant = JSON.parse_string(wire)
	_check(decoded is Dictionary and _pixel(decoded["artwork"]) == Color.RED,
		"JSON transport roundtrip retains authorized PNG bytes")
	published["floors"][0]["layers"][0]["chunks"][0]["png_base64"] = "tampered"
	_check(_pixel(player.artwork_record()) == Color.RED,
		"caller mutation of DTO cannot corrupt the mirror")
	_check(not host.snapshot_for(player).has("tokens") and not host.snapshot_for(gm).has("artwork"),
		"host snapshot shape is role-bound, not client-side hidden")
	var state: Dictionary = fixture.campaign.to_dict().duplicate(true)
	_check(player.move_token("hidden-token", Vector2(18, 19)).code == "ROLE_FORBIDDEN",
		"player edits are refused by host before revision validation")
	_check(spectator.move_token("hidden-token", Vector2(18, 19)).code == "ROLE_FORBIDDEN",
		"spectator edits are refused by host")
	var forged: Dictionary = {"request_id": "forged", "session_id": "session", "peer_id": "gm",
		"operation": "token_move", "base_revision": "0", "token_id": "hidden-token",
		"position": [100.0, 200.0]}
	_check(host.receive(player, forged).code == "ROLE_FORBIDDEN",
		"forged GM peer ID cannot elevate a viewer handle")
	_check(host.revision == 0 and fixture.campaign.to_dict() == state
		and not fixture.history.can_undo(), "all denied operations have zero canonical side effects")
	var moved: Dictionary = gm.move_token("hidden-token", Vector2(4, 5))
	_check(moved.ok and host.revision == 1 and gm.token_records()[0]["position"] == [4.0, 5.0],
		"GM host command still advances authoritative history")
	_check(player.revision == 1 and spectator.revision == 1
		and player.token_records().is_empty() and spectator.token_records().is_empty(),
		"viewer revisions advance without leaking edited GM tokens")
	_check(_pixel(player.artwork_record()) == Color.RED,
		"viewer authorized artwork survives unrelated host token moves")
	_check(host.join_as("bad-role", "owner") == null
		and host.join_as("bad-gm", "gm", ["public"]) == null,
		"unknown roles and GM publication policy arguments are rejected")
	_check(host.join_as("bad-layer", "player", ["missing"]) == null
		and host.join_as("bad-duplicate", "player", ["public", "public"]) == null,
		"unknown and duplicate grants reject before peer joins")
	_check(host.join_as("bad-token", "player", ["gm-tokens"]) == null
		and host.join_as("bad-text", "player", ["notes"]) == null,
		"tokens and text/semantic layers cannot be published by unapproved policy")
	_check(host.join_as("bad-lod", "spectator", ["d1"], 0) == null
		and host.join_as("bad-level", "player", ["public"], -1) == null,
		"detail levels and invalid LOD are rejected before publication")
	_check(host.join_as("other-lod", "spectator", ["d1"], 1) != null,
		"explicit D1 raster grant can be assigned independently")


func _fog_and_revocation() -> void:
	var fixture: Dictionary = _fixture()
	var floor: AtlasFloor = fixture.floor
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 4, 8), true))
	# The host observes this as the initial canonical floor state.
	var host: AtlasHostSession = AtlasHostSession.new(fixture.campaign, fixture.history,
		"fog_session", "board", "ground", "gm-tokens")
	var player: AtlasSessionClient = host.join_as("player", "player", ["public"])
	_check(player != null, "fogged public raster can be granted with safe pixel clipping")
	if player == null:
		return
	_check(_pixel(player.artwork_record(), 1, 1) == Color.RED
		and _pixel(player.artwork_record(), 6, 1).a == 0.0,
		"unrevealed pixels are removed before PNG byte serialization")
	var secret: String = JSON.stringify(player.artwork_record())
	_check(not secret.contains("SUPER SECRET") and not secret.contains("hidden-token"),
		"fogged wire payload contains no private semantic metadata")
	var watcher: AtlasSessionClient = host.join_as("spectator", "spectator")
	_check(watcher != null and watcher.artwork_record().is_empty(),
		"another peer does not inherit prior viewer grants")
	var old_revision: int = player.revision
	_check(host.set_viewer_grants("player", [], 0), "trusted host can revoke player publication")
	_check(player.artwork_record().is_empty() and player.revision == old_revision + 1,
		"revocation clears existing viewer snapshot and advances revision")
	_check(watcher.artwork_record().is_empty() and watcher.revision == player.revision,
		"revocation update does not publish to ungranted spectator")
	_check(not host.set_viewer_grants("player", ["notes"])
		and not host.set_viewer_grants("player", ["public", "public"]),
		"invalid policy updates reject without widening permissions")
	_check(not host.set_viewer_grants("gm", ["public"]) and host.revision == old_revision + 1,
		"only viewer grants may be changed; rejections preserve revision")
	_check(host.set_viewer_grants("player", ["public"], 0)
		and _pixel(player.artwork_record(), 1, 1) == Color.RED,
		"host may explicitly reauthorize a raster view")
	_check(host.set_viewer_grants("player", ["public"], 0)
		and host.revision == old_revision + 2,
		"identical policy is idempotent")
	var snapshot: Dictionary = host.snapshot_for(player)
	snapshot["artwork"]["floors"][0]["layers"].clear()
	_check(_pixel(player.artwork_record(), 1, 1) == Color.RED,
		"host snapshot and client local memory never alias")
	player._receive_update({"session_id": "wrong", "revision": str(player.revision + 1),
		"artwork": {"secret": "forged"}})
	_check(player.artwork_record().is_empty() and player.move_token("hidden-token", Vector2.ZERO).code == "SYNC_REQUIRED",
		"bad/out-of-order updates wipe viewer pixels and require resync")
	_check(player.resync() and _pixel(player.artwork_record(), 1, 1) == Color.RED,
		"trusted snapshot resync restores only currently granted pixels")


func _divergence_and_shutdown() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture.host
	var player: AtlasSessionClient = host.join_as("viewer", "player", ["public"])
	var gm: AtlasSessionClient = host.join("gm")
	_check(player != null and gm != null, "divergence fixture binds a GM and viewer")
	if player == null or gm == null:
		return
	var source: AtlasRasterLayer = fixture.floor.layer_by_id("public") as AtlasRasterLayer
	source.chunks["0,0"].image.fill(Color.BLUE)
	_check(not player.resync() and player.artwork_record().is_empty(),
		"in-place source pixel change invalidates host and clears viewer buffer")
	_check(gm.move_token("hidden-token", Vector2(4, 4)).code == "LOCAL_DIVERGENCE",
		"host rejects commands after out-of-band source change")
	var fresh: Dictionary = _fixture()
	var another: AtlasHostSession = fresh.host
	var watched: AtlasSessionClient = another.join_as("viewer", "player", ["public"])
	var editor: AtlasSessionClient = another.join("gm")
	_check(editor.move_token("hidden-token", Vector2(3, 4)).ok,
		"host can still perform a valid GM move before history divergence")
	_check(fresh.history.undo() and watched.artwork_record().is_empty(),
		"out-of-band undo immediately blanks viewer payload")
	var shutdown: Dictionary = _fixture()
	var closing: AtlasHostSession = shutdown.host
	var audience: AtlasSessionClient = closing.join_as("viewer", "spectator", ["public"])
	closing.close()
	_check(audience.artwork_record().is_empty() and not audience.resync()
		and audience.move_token("hidden-token", Vector2.ZERO).code == "NOT_CONNECTED",
		"session shutdown revokes viewer pixels and all future access")
