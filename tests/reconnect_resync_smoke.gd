extends SceneTree
## T-047: trusted-handle reconnection, filtered full-state handoff, replay safety.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("RECONNECT FAILED: " + description)


func _raster(id: String, color: Color, detail_level: int = 0) -> AtlasRasterLayer:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	layer.id = id
	layer.detail_level = detail_level
	return layer


func _fixture() -> Dictionary:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.display_name = "SUPER SECRET campaign"
	var document: AtlasMapDocument = AtlasMapDocument.new("board", "SUPER SECRET board")
	var floor: AtlasFloor = document.floors[0]
	floor.layers.append(_raster("public", Color.RED))
	floor.layers.append(_raster("secret", Color.GREEN))
	floor.layers.append(_raster("d1", Color.BLUE, 1))
	var labels: AtlasObjectsLayer = AtlasObjectsLayer.new("notes", "SUPER SECRET labels")
	var note: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2.ONE]), Color.WHITE, 12)
	note.text = "SUPER SECRET PASSWORD"
	labels.strokes.append(note)
	floor.layers.append(labels)
	var tokens: AtlasTokenLayer = AtlasTokenLayer.new("gm-tokens", "GM tokens")
	tokens.tokens = [AtlasToken.new("a", Vector2.ZERO, "SUPER SECRET Rogue"),
		AtlasToken.new("b", Vector2(2, 3), "Guard")]
	floor.layers.append(tokens)
	campaign.add_map(document)
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "board"
	var host: AtlasHostSession = AtlasHostSession.new(campaign, history, "epoch_1",
		"board", "ground", "gm-tokens")
	return {"host": host, "history": history, "tokens": tokens,
		"floor": floor, "document": document, "campaign": campaign}


func _pixel(artwork: Dictionary) -> Color:
	if not artwork.has("floors"):
		return Color.MAGENTA
	var chunk: Dictionary = artwork["floors"][0]["layers"][0]["chunks"][0]
	var bytes: PackedByteArray = Marshalls.base64_to_raw(chunk["png_base64"])
	var image: Image = Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return Color.MAGENTA
	return image.get_pixel(0, 0)


func _run() -> void:
	_gm_reconnect_and_replay()
	_viewer_permission_changes()
	_divergence_and_epochs()
	_lifetime_peer_budget()
	print("ATLAS_RECONNECT_RESYNC_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _gm_reconnect_and_replay() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture.host
	var alice: AtlasSessionClient = host.join("alice")
	var bob: AtlasSessionClient = host.join("bob")
	_check(alice != null and bob != null and alice.revision == 0,
		"two GM mirrors join a canonical epoch")
	var initial: Dictionary = alice.move_token("a", Vector2(4, 5))
	_check(initial.ok and initial.revision == "1" and fixture.history.can_undo(),
		"first host edit commits to history")
	_check(host.disconnect_peer(alice) and not host.disconnect_peer(alice),
		"trusted controller retires a handle exactly once")
	_check(not alice.resync() and alice.move_token("a", Vector2(9, 9)).code == "NOT_CONNECTED"
		and alice.retry_last().code == "NOT_CONNECTED",
		"offline handle cannot mutate, resync or retry")
	_check(host.snapshot_for(alice).is_empty() and host.join("alice") == null,
		"disconnect does not release identity to an unrelated join")
	_check(bob.move_token("b", Vector2(-3, 8)).ok and host.revision == 2,
		"connected GM can edit while another peer is offline")
	alice._receive_update({"session_id": "epoch_1", "revision": "2", "tokens": []})
	_check(alice.revision == 1, "late delta cannot revive a retired mirror")
	var invalid: AtlasSessionClient = AtlasSessionClient.new(host, "alice")
	_check(host.reconnect(invalid) == null and host.reconnect(bob) == null,
		"forged and still-active handles cannot reclaim an identity")
	var resumed: AtlasSessionClient = host.reconnect(alice)
	_check(resumed != null and resumed != alice and resumed.peer_id == "alice",
		"trusted previous handle creates a fresh connection")
	if resumed == null:
		return
	_check(resumed.revision == 2 and resumed.token_records() == bob.token_records(),
		"missed deltas are replaced by the latest complete authoritative snapshot")
	_check(alice.move_token("b", Vector2.ONE).code == "NOT_CONNECTED"
		and host.reconnect(alice) == null and host.snapshot_for(alice).is_empty(),
		"old handle is permanently retired after resume")
	var replay: Dictionary = resumed.retry_last()
	_check(replay == initial and host.revision == 2,
		"explicit replay of an acknowledged request returns cached prior outcome")
	_check(fixture.tokens.tokens[0].position == Vector2(4, 5)
		and fixture.tokens.tokens[1].position == Vector2(-3, 8),
		"replaying a previous success does not duplicate or overwrite host edits")
	var next: Dictionary = resumed.move_token("a", Vector2(6, 7))
	_check(next.ok and resumed.revision == 3 and bob.revision == 3,
		"new edits use a distinct request ID and current revision")
	var altered: Dictionary = {"request_id": "req_1", "session_id": "epoch_1",
		"peer_id": "alice", "operation": "token_move", "base_revision": "0",
		"token_id": "a", "position": [123.0, 123.0]}
	_check(host.receive(resumed, altered).code == "REQUEST_REUSE",
		"request IDs cannot be reused with altered payload after reconnect")
	_check(host.revision == 3 and fixture.tokens.tokens[0].position == Vector2(6, 7),
		"replay attack has no history or token side effects")


func _viewer_permission_changes() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture.host
	var gm: AtlasSessionClient = host.join("gm")
	var player: AtlasSessionClient = host.join_as("audience", "player", ["public"])
	var spectator: AtlasSessionClient = host.join_as("watcher", "spectator", ["d1"], 1)
	_check(player != null and spectator != null and _pixel(player.artwork_record()) == Color.RED
		and _pixel(spectator.artwork_record()) == Color.BLUE,
		"different viewer roles receive independent, granted detail-level pixels")
	if player == null or spectator == null:
		return
	var stale: Dictionary = host.snapshot_for(player)
	_check(host.disconnect_peer(player) and player.artwork_record().is_empty(),
		"disconnect erases the player-facing PNG bytes immediately")
	_check(host.set_viewer_grants("audience", [], 0) and gm.move_token("a", Vector2(4, 4)).ok,
		"host can revoke publication and advance edits while viewer is absent")
	_check(player.artwork_record().is_empty() and not player.resync(),
		"offline viewer cannot recover a previously granted capture")
	var resumed: AtlasSessionClient = host.reconnect(player)
	_check(resumed != null and resumed.revision == host.revision
		and resumed.artwork_record().is_empty() and resumed.token_records().is_empty(),
		"rejoining after revocation receives only current blank policy")
	if resumed == null:
		return
	_check(resumed.move_token("a", Vector2(5, 5)).code == "ROLE_FORBIDDEN",
		"reconnect cannot change player role to GM")
	player._receive_snapshot(stale)
	_check(player.artwork_record().is_empty(),
		"late stale full snapshot cannot restore bytes on retired handle")
	_check(host.set_viewer_grants("audience", ["d1"], 1)
		and _pixel(resumed.artwork_record()) == Color.BLUE,
		"trusted reauthorization may change allowed detail level")
	_check(host.disconnect_peer(resumed) and resumed.artwork_record().is_empty(),
		"subsequent disconnect clears even newly granted player pixels")
	_check(host.set_viewer_grants("audience", ["public"], 0),
		"trusted permission update applies to disconnected viewer")
	var next: AtlasSessionClient = host.reconnect(resumed)
	_check(next != null and _pixel(next.artwork_record()) == Color.RED
		and next.revision == host.revision,
		"reconnect uses current grant, not permissions from earlier session handle")
	if next == null:
		return
	var wire: String = JSON.stringify(host.snapshot_for(next))
	_check(not wire.contains("SUPER SECRET") and not wire.contains("gm-tokens")
		and not wire.contains("secret\"") and not wire.contains("d1\""),
		"serialized resync payload contains no private source metadata or hidden layers")
	_check(JSON.parse_string(wire) is Dictionary and _pixel(next.artwork_record()) == Color.RED,
		"filtered payload remains independently serializable")
	_check(host.disconnect_peer(spectator) and spectator.artwork_record().is_empty(),
		"spectator revocation uses the same safe disconnect boundary")
	_check(host.set_viewer_grants("watcher", [], 0)
		and host.reconnect(spectator).artwork_record().is_empty(),
		"spectator resync never restores removed authorization")


func _divergence_and_epochs() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture.host
	var viewer: AtlasSessionClient = host.join_as("viewer", "player", ["public"])
	_check(host.disconnect_peer(viewer), "viewer disconnects before local source divergence")
	var raster: AtlasRasterLayer = fixture.floor.layer_by_id("public") as AtlasRasterLayer
	raster.chunks["0,0"].image.fill(Color.BLUE)
	_check(host.reconnect(viewer) == null and viewer.artwork_record().is_empty(),
		"out-of-band raster modification invalidates host and blocks reconnect")
	var history_case: Dictionary = _fixture()
	var other: AtlasHostSession = history_case.host
	var gm: AtlasSessionClient = other.join("gm")
	_check(gm.move_token("a", Vector2(12, 12)).ok
		and other.disconnect_peer(gm), "GM can disconnect after a valid edit")
	_check(history_case.history.undo() and other.reconnect(gm) == null,
		"out-of-band undo invalidates reconnect even when history reverts data")
	var closing: Dictionary = _fixture()
	var final_host: AtlasHostSession = closing.host
	var client: AtlasSessionClient = final_host.join_as("viewer", "player", ["public"])
	_check(final_host.disconnect_peer(client), "viewer can be offline before host close")
	final_host.close()
	_check(final_host.reconnect(client) == null and final_host.join("new_peer") == null,
		"closed session cannot be reopened using an old trusted handle")
	var second: Dictionary = _fixture()
	var other_host: AtlasHostSession = second.host
	_check(other_host.reconnect(client) == null,
		"another host cannot adopt a handle from a previous session epoch")


func _lifetime_peer_budget() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = fixture.host
	var first: AtlasSessionClient
	for index: int in AtlasHostSession.MAX_PEERS:
		var client: AtlasSessionClient = host.join("peer_%d" % index)
		if index == 0:
			first = client
		_check(client != null and host.disconnect_peer(client),
			"registered peer slot %d survives disconnect" % index)
	_check(host.join("overflow") == null and host.join("peer_0") == null,
		"offline peers still count toward the lifetime identity budget")
	_check(host.reconnect(first) != null,
		"reconnect reuses an existing identity slot without expanding the peer budget")
