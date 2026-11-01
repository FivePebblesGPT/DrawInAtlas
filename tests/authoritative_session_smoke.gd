extends SceneTree
## T-045: a trusted in-process host and two detached client mirrors.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("SESSION FAILED: " + description)


func _fixture() -> Dictionary:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	var map: AtlasMapDocument = AtlasMapDocument.new("board", "Board")
	var layer: AtlasTokenLayer = AtlasTokenLayer.new("gm-tokens", "GM tokens")
	layer.tokens = [AtlasToken.new("a", Vector2(-3, 2), "Rogue"),
		AtlasToken.new("b", Vector2(8, 8), "Guard")]
	map.floors[0].layers.append(layer)
	campaign.add_map(map)
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "board"
	return {"campaign": campaign, "map": map, "layer": layer, "history": history}


func _run() -> void:
	_basic_flow()
	_rejection_flow()
	_history_and_divergence()
	print("ATLAS_AUTHORITATIVE_SESSION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _basic_flow() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = AtlasHostSession.new(fixture.campaign, fixture.history,
		"session_1", "board", "ground", "gm-tokens")
	_check(host.is_ready() and host.revision == 0, "host binds existing token layer and history")
	var alice: AtlasSessionClient = host.join("alice")
	var bob: AtlasSessionClient = host.join("bob")
	_check(alice != null and bob != null and host.join("alice") == null,
		"trusted peers join once; duplicate peer identity rejected")
	_check(alice.token_records() == bob.token_records() and alice.revision == 0,
		"two clients begin with identical detached snapshots")
	var copy: Array[Dictionary] = alice.token_records()
	copy[0]["label"] = "corrupt"
	_check(fixture.layer.tokens[0].label == "Rogue" and bob.token_records()[0]["label"] == "Rogue",
		"mutating a client snapshot cannot mutate host or second client")
	var accepted: Dictionary = alice.move_token("a", Vector2(-12.5, 6.25))
	_check(accepted.ok and accepted.code == "ACCEPTED" and accepted.revision == "1",
		"accepted command has authoritative revision")
	_check(fixture.layer.tokens[0].position == Vector2(-12.5, 6.25)
		and alice.token_records()[0]["position"] == [-12.5, 6.25]
		and bob.token_records()[0]["position"] == [-12.5, 6.25]
		and alice.revision == 1 and bob.revision == 1,
		"both mirrors see the committed token move without Resource aliasing")
	_check(fixture.history.can_undo() and fixture.history.is_dirty(),
		"authoritative command enters ordinary campaign history")
	var retry: Dictionary = alice.retry_last()
	_check(retry == accepted and host.revision == 1 and not fixture.history.can_redo(),
		"retransmission returns cached response without double-application")
	var bob_move: Dictionary = bob.move_token("b", Vector2(17, -12))
	_check(bob_move.ok and host.revision == 2 and alice.revision == 2,
		"second peer's command is ordered after first")
	_check(alice.token_records()[1]["position"] == [17.0, -12.0]
		and fixture.layer.tokens[1].position == Vector2(17, -12),
		"all peers agree on second committed object")
	_check(host.join("bad id") == null and host.join("bob") == null,
		"invalid and reused peer IDs rejected")
	_check(alice.resync() and alice.revision == 2, "explicit client resync is available")
	alice._receive_update({"session_id": "session_1", "revision": "10", "tokens": []})
	_check(alice.move_token("a", Vector2.ZERO).code == "SYNC_REQUIRED",
		"out-of-order host event forces resynchronization")
	_check(alice.resync() and alice.revision == 2 and alice.token_records().size() == 2,
		"resynchronization restores exact authoritative snapshot")
	var packet: Dictionary = {"request_id": "json_move", "session_id": "session_1",
		"peer_id": "alice", "operation": "token_move", "base_revision": "2",
		"token_id": "a", "position": [12.5, -4.0]}
	var decoded: Variant = JSON.parse_string(JSON.stringify(packet))
	_check(decoded is Dictionary and host.receive(alice, decoded).ok
		and bob.token_records()[0]["position"] == [12.5, -4.0],
		"serialized JSON request preserves exact revision and changes both mirrors")
	var original: Dictionary = JSON.parse_string(JSON.stringify(host.snapshot_for(bob)))
	_check(original["revision"] == "3", "JSON snapshot keeps exact decimal revision")
	original["tokens"][0]["position"] = [1234.0, 5678.0]
	_check(fixture.layer.tokens[0].position == Vector2(12.5, -4.0),
		"host snapshot is detached from canonical state")
	host.close()
	_check(alice.move_token("a", Vector2(5, 6)).code == "NOT_CONNECTED"
		and not bob.resync() and host.join("new") == null,
		"closing session revokes requests, resync and new peers")


func _rejection_flow() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = AtlasHostSession.new(fixture.campaign, fixture.history,
		"session_2", "board", "ground", "gm-tokens")
	var alice: AtlasSessionClient = host.join("alice")
	var bob: AtlasSessionClient = host.join("bob")
	var before: Dictionary = fixture.campaign.to_dict().duplicate(true)
	var bad: Dictionary = alice.move_token("missing", Vector2(1, 2))
	_check(not bad.ok and bad.code == "NOT_FOUND", "nonexistent token rejected")
	bad = alice.move_token("a", Vector2(-3, 2))
	_check(not bad.ok and bad.code == "UNCHANGED", "no-op is not a new revision")
	bad = alice.move_token("a", Vector2.INF)
	_check(not bad.ok and bad.code == "BAD_REQUEST", "nonfinite position rejected")
	_check(host.revision == 0 and fixture.campaign.to_dict() == before
		and not fixture.history.can_undo(), "rejected requests have no side effects")
	var forged: Dictionary = {"request_id": "forged", "session_id": "session_2",
		"peer_id": "bob", "operation": "token_move", "base_revision": "0",
		"token_id": "a", "position": [2.0, 3.0]}
	_check(host.receive(alice, forged).code == "IDENTITY_MISMATCH",
		"request peer does not override trusted connection identity")
	forged["peer_id"] = "alice"
	forged["operation"] = "delete_all"
	_check(host.receive(alice, forged).code == "REQUEST_REUSE",
		"request ID cannot be reused with changed content")
	forged["request_id"] = "unknown"
	_check(host.receive(alice, forged).code == "UNKNOWN_OPERATION", "arbitrary operations rejected")
	forged["operation"] = "token_move"
	forged["position"] = [3.0, 7.0]
	forged["base_revision"] = 0
	forged["request_id"] = "bad_revision"
	_check(host.receive(alice, forged).code == "STALE_REVISION", "revision must be exact decimal string")
	forged["base_revision"] = "0"
	forged["position"] = [3.0, "bad"]
	forged["request_id"] = "bad_vector"
	_check(host.receive(alice, forged).code == "BAD_REQUEST", "non-numeric vector rejected")
	forged["position"] = [3.0, 7.0]
	forged["unexpected"] = "inject"
	forged["request_id"] = "extra"
	_check(host.receive(alice, forged).code == "BAD_REQUEST", "unknown fields rejected")
	forged.erase("unexpected")
	forged["request_id"] = "ok"
	_check(host.receive(alice, forged).ok, "good structured primitive request accepted")
	_check(host.receive(bob, forged).code == "IDENTITY_MISMATCH",
		"same packet cannot impersonate a different connected peer")
	forged["request_id"] = "stale"
	_check(host.receive(alice, forged).code == "STALE_REVISION", "stale base revision rejected")
	_check(fixture.layer.tokens[0].position == Vector2(3, 7) and host.revision == 1,
		"rejection does not overwrite accepted edit")
	var locked: Dictionary = _fixture()
	locked.layer.locked = true
	var locked_host: AtlasHostSession = AtlasHostSession.new(locked.campaign, locked.history,
		"locked", "board", "ground", "gm-tokens")
	var locked_client: AtlasSessionClient = locked_host.join("gm")
	_check(locked_client.move_token("a", Vector2(6, 6)).code == "EDIT_REJECTED"
		and not locked.history.can_undo(), "canonical editability is enforced by existing command")
	var masked: Dictionary = _fixture()
	var scope: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)]), true)
	var scoped_host: AtlasHostSession = AtlasHostSession.new(masked.campaign, masked.history,
		"masked", "board", "ground", "gm-tokens", scope)
	var scoped_client: AtlasSessionClient = scoped_host.join("gm")
	_check(scoped_client.move_token("a", Vector2(1000, 1000)).code == "EDIT_REJECTED"
		and masked.layer.tokens[0].position == Vector2(-3, 2),
		"host passes trusted selection mask to existing token command")


func _history_and_divergence() -> void:
	var fixture: Dictionary = _fixture()
	var host: AtlasHostSession = AtlasHostSession.new(fixture.campaign, fixture.history,
		"session_3", "board", "ground", "gm-tokens")
	var alice: AtlasSessionClient = host.join("alice")
	_check(alice.move_token("a", Vector2(12, 4)).ok, "move accepted before local history edit")
	_check(fixture.history.undo(), "ordinary local undo is possible on host")
	_check(alice.move_token("b", Vector2(20, 20)).code == "LOCAL_DIVERGENCE",
		"local undo cannot silently mix revisions into live session")
	_check(not alice.resync() and host.revision == 1,
		"diverged session requires restart instead of relabeling old state")
	var replaced: Dictionary = _fixture()
	var replaced_host: AtlasHostSession = AtlasHostSession.new(replaced.campaign, replaced.history,
		"session_4", "board", "ground", "gm-tokens")
	var client: AtlasSessionClient = replaced_host.join("gm")
	replaced.map.floors[0].layers[-1] = AtlasTokenLayer.new("gm-tokens", "replacement")
	_check(client.move_token("a", Vector2(12, 4)).code == "LOCAL_DIVERGENCE",
		"replacing layer with same stable ID invalidates session")
	var saved: Dictionary = _fixture()
	var saved_host: AtlasHostSession = AtlasHostSession.new(saved.campaign, saved.history,
		"session_5", "board", "ground", "gm-tokens")
	var saved_client: AtlasSessionClient = saved_host.join("gm")
	saved.history.mark_saved()
	_check(saved_client.move_token("a", Vector2(10, 10)).code == "LOCAL_DIVERGENCE",
		"external history checkpoint invalidates session even with identical pixels")
	var invalid: Dictionary = _fixture()
	invalid.history.active_map_id = "another"
	_check(not AtlasHostSession.new(invalid.campaign, invalid.history, "new", "board",
		"ground", "gm-tokens").is_ready(), "misbound history cannot start host")
