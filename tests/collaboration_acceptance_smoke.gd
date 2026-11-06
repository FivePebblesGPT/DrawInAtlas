extends SceneTree
## T-048: end-to-end acceptance witness for the trusted in-process protocol.
## Assertions inspect JSON wire payloads and decoded PNG bytes, not UI hiding.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("COLLABORATION ACCEPTANCE FAILED: " + description)


func _raster(id: String, label: String, color: Color, detail: int = 0) -> AtlasRasterLayer:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	layer.id = id
	layer.display_name = label
	layer.detail_level = detail
	return layer


func _fixture() -> Dictionary:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.display_name = "PRIVATE_CAMPAIGN_KEY"
	var document: AtlasMapDocument = AtlasMapDocument.new("private-map", "PRIVATE_MAP_KEY")
	document.tags.append("PRIVATE_TAG_KEY")
	var floor: AtlasFloor = document.floors[0]
	floor.layers.clear()
	floor.layers.append(_raster("open-d0", "Allowed red", Color.RED))
	floor.layers.append(_raster("sealed-d0", "PRIVATE_RASTER_KEY", Color.GREEN))
	floor.layers.append(_raster("open-d1", "Allowed blue", Color.BLUE, 1))
	floor.layers.append(_raster("sealed-d1", "PRIVATE_D1_KEY", Color.GREEN, 1))
	var notes: AtlasObjectsLayer = AtlasObjectsLayer.new("private-notes", "PRIVATE_NOTES_KEY")
	var text: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2.ONE]), Color.WHITE, 14.0)
	text.text = "PRIVATE_PASSWORD_KEY"
	notes.strokes.append(text)
	floor.layers.append(notes)
	var token_layer: AtlasTokenLayer = AtlasTokenLayer.new("private-tokens", "PRIVATE_TOKEN_LAYER_KEY")
	token_layer.tokens = [AtlasToken.new("guard", Vector2.ZERO, "PRIVATE_TOKEN_LABEL_KEY"),
		AtlasToken.new("scout", Vector2(1, 1), "Scout")]
	floor.layers.append(token_layer)
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 4, 8), true))
	campaign.add_map(document)
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "private-map"
	var host: AtlasHostSession = AtlasHostSession.new(campaign, history, "acceptance_epoch",
		"private-map", floor.id, "private-tokens")
	return {"host": host, "history": history, "campaign": campaign,
		"tokens": token_layer, "floor": floor}


func _wire(host: AtlasHostSession, viewer: AtlasSessionClient) -> Dictionary:
	var serialized: String = JSON.stringify(host.snapshot_for(viewer))
	var decoded: Variant = JSON.parse_string(serialized)
	if not decoded is Dictionary:
		return {}
	return {"text": serialized, "decoded": decoded}


func _safe_wire(view: Dictionary, permitted: Color) -> bool:
	if view.is_empty():
		return false
	var text: String = view["text"]
	for fragment: String in ["PRIVATE_", "private-map", "private-tokens", "private-notes",
		"sealed-d0", "sealed-d1", "open-d0", "open-d1", "guard", "scout"]:
		if text.contains(fragment):
			return false
	var payload: Dictionary = view["decoded"]
	if payload.has("tokens") or not payload.has("artwork"):
		return false
	var art: Dictionary = payload["artwork"]
	if not art.has("floors") or art["floors"].size() != 1:
		return false
	var layers: Array = art["floors"][0]["layers"]
	if layers.size() != 1 or layers[0]["id"] != "art-0":
		return false
	var chunks: Array = layers[0]["chunks"]
	if chunks.size() != 1 or not chunks[0].has("png_base64"):
		return false
	var bytes: PackedByteArray = Marshalls.base64_to_raw(chunks[0]["png_base64"])
	var image: Image = Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_width() != 8 or image.get_height() != 8:
		return false
	for y: int in 8:
		for x: int in 8:
			var pixel: Color = image.get_pixel(x, y)
			if x < 4 and not pixel.is_equal_approx(permitted):
				return false
			if x >= 4 and pixel.a != 0.0:
				return false
	return true


func _run() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture["host"]
	var alice: AtlasSessionClient = host.join("alice")
	var bob: AtlasSessionClient = host.join("bob")
	var player: AtlasSessionClient = host.join_as("player", "player", ["open-d0"])
	var spectator: AtlasSessionClient = host.join_as("spectator", "spectator", ["open-d1"], 1)
	_check(alice != null and bob != null and player != null and spectator != null,
		"two GM editors and two filtered viewers join the same trusted epoch")
	if alice == null or bob == null or player == null or spectator == null:
		quit(1)
		return
	_check(_safe_wire(_wire(host, player), Color.RED),
		"actual player JSON and PNG omit private names, tokens, sealed raster and unrevealed pixels")
	_check(_safe_wire(_wire(host, spectator), Color.BLUE),
		"spectator receives independently sanitized D1 PNG, not private D0/D1 content")
	_check(not _wire(host, player)["text"].contains("PRIVATE_PASSWORD_KEY")
		and not _wire(host, spectator)["text"].contains("PRIVATE_TOKEN_LABEL_KEY"),
		"private label text is absent before serialization, not hidden by the UI")
	_check(player.token_records().is_empty() and spectator.token_records().is_empty(),
		"read-only viewers hold no detached canonical token records")

	var baseline: Dictionary = fixture["campaign"].to_dict().duplicate(true)
	var forbidden: Dictionary = {"request_id": "attack", "session_id": "acceptance_epoch",
		"peer_id": "alice", "operation": "token_move", "base_revision": "0",
		"token_id": "guard", "position": [33.0, 44.0]}
	_check(host.receive(player, forbidden).code == "ROLE_FORBIDDEN"
		and host.receive(spectator, forbidden).code == "ROLE_FORBIDDEN",
		"viewer and spectator cannot impersonate a GM through a command payload")
	var counterfeit: AtlasSessionClient = AtlasSessionClient.new(host, "alice")
	_check(host.receive(counterfeit, forbidden).code == "NOT_CONNECTED"
		and host.snapshot_for(counterfeit).is_empty(),
		"forged in-process handle cannot send or retrieve host snapshots")
	var injected: Dictionary = forbidden.duplicate(true)
	injected["request_id"] = "injection"
	injected["extra_private_state"] = "PRIVATE_PASSWORD_KEY"
	_check(host.receive(alice, injected).code == "BAD_REQUEST",
		"GM command with unexpected private data field is rejected, not logged as an edit")
	_check(fixture["campaign"].to_dict() == baseline and host.revision == 0
		and not fixture["history"].can_undo(),
		"unauthorized and malformed requests leave campaign, revision and undo history untouched")

	var first: Dictionary = alice.move_token("guard", Vector2(5, 6))
	_check(first.ok and host.revision == 1 and bob.token_records() == alice.token_records(),
		"host-authorized edit updates two independent GM mirrors")
	_check(_safe_wire(_wire(host, player), Color.RED)
		and _safe_wire(_wire(host, spectator), Color.BLUE),
		"GM token edit broadcasts new revisions without leaking private token data")
	_check(host.disconnect_peer(bob) and host.disconnect_peer(player),
		"GM and viewer may disconnect independently")
	_check(player.artwork_record().is_empty() and host.snapshot_for(player).is_empty(),
		"disconnected viewer immediately loses bytes and cannot request a snapshot")
	var second: Dictionary = alice.move_token("scout", Vector2(-4, 10))
	_check(second.ok and host.revision == 2, "connected GM can edit while peers are offline")
	_check(host.set_viewer_grants("player", [], 0) and host.revision == 3,
		"trusted host revokes offline player's publication during missed updates")
	_check(not host.set_viewer_grants("player", ["private-notes"])
		and not host.set_viewer_grants("spectator", ["private-tokens"]),
		"semantic-label and token grants cannot bypass privacy during reconnect")
	var bob_again: AtlasSessionClient = host.reconnect(bob)
	var player_again: AtlasSessionClient = host.reconnect(player)
	_check(bob_again != null and player_again != null,
		"previous trusted handles permit new connections with fresh state")
	if bob_again != null and player_again != null:
		_check(bob_again.token_records() == alice.token_records()
			and bob_again.revision == host.revision,
			"reconnected GM converges after missing multiple host revisions")
		_check(player_again.artwork_record().is_empty()
			and player_again.revision == host.revision,
			"reconnected player gets current blank policy, not cached pre-revocation imagery")
		_check(_wire(host, player_again)["decoded"].get("artwork", {"leak": true}).is_empty(),
			"serialized reconnect snapshot carries an empty artwork dictionary")
		_check(player_again.move_token("guard", Vector2(99, 99)).code == "ROLE_FORBIDDEN",
			"reconnected viewer cannot gain GM privileges")
		_check(host.reconnect(bob) == null and host.snapshot_for(bob).is_empty(),
			"retired GM handle cannot reenter or read through a new connection")
		var retried: Dictionary = bob_again.move_token("scout", Vector2(7, -2))
		_check(retried.ok and alice.token_records() == bob_again.token_records(),
			"post-reconnect GM edit is authoritative and mirrored consistently")
		var revision_after: int = host.revision
		_check(bob_again.retry_last() == retried and host.revision == revision_after,
			"replayed acknowledgement does not reexecute the accepted command")
		_check(host.set_viewer_grants("player", ["open-d0"])
			and _safe_wire(_wire(host, player_again), Color.RED),
			"fresh host grant restores only current authorized D0 bytes")
	_check(_safe_wire(_wire(host, spectator), Color.BLUE)
		and spectator.revision == host.revision,
		"uninterrupted spectator remains synchronized with D1-only privacy policy")
	var spectator_wire: String = _wire(host, spectator)["text"]
	_check(not spectator_wire.contains("PRIVATE_") and not spectator_wire.contains("guard"),
		"final transmitted viewer payload remains free of GM metadata")

	# After a local edit bypasses the host, no old viewer snapshot may be issued.
	var raster: AtlasRasterLayer = fixture["floor"].layer_by_id("open-d0") as AtlasRasterLayer
	raster.chunks["0,0"].image.fill(Color.GREEN)
	_check(host.snapshot_for(spectator).is_empty(),
		"out-of-band pixel mutation causes host denial instead of publishing stale permissions")
	_check(spectator.artwork_record().is_empty()
		and (player_again == null or player_again.artwork_record().is_empty()),
		"local divergence clears all currently connected viewer mirrors")
	host.close()
	print("ATLAS_COLLABORATION_ACCEPTANCE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
