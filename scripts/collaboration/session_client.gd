class_name AtlasSessionClient
extends RefCounted
## Role-bound in-process mirror. No mutable campaign or host Token is
## retained; all mirrored state is detached primitive dictionaries.

var peer_id: String = ""
var session_id: String = ""
var revision: int = -1
var _host: AtlasHostSession
var _tokens: Array[Dictionary] = []
var _artwork: Dictionary = {}
var _next_request: int = 0
var _needs_sync: bool = false
var _last_request: Dictionary = {}


func _init(host: AtlasHostSession, peer: String) -> void:
	_host = host
	peer_id = peer


func token_records() -> Array[Dictionary]:
	return _tokens.duplicate(true)


func artwork_record() -> Dictionary:
	return _artwork.duplicate(true)


func _clear_public_artwork() -> void:
	_artwork.clear()


func move_token(token_id: String, position: Vector2) -> Dictionary:
	if _needs_sync or revision < 0:
		return {"ok": false, "code": "SYNC_REQUIRED"}
	_next_request += 1
	_last_request = {"request_id": "req_%d" % _next_request,
		"session_id": session_id, "peer_id": peer_id, "operation": "token_move",
		"base_revision": str(revision), "token_id": token_id,
		"position": [position.x, position.y]}
	return _host.receive(self, _last_request.duplicate(true))


func retry_last() -> Dictionary:
	if _last_request.is_empty():
		return {"ok": false, "code": "NO_REQUEST"}
	return _host.receive(self, _last_request.duplicate(true))


func resync() -> bool:
	var snapshot: Dictionary = _host.snapshot_for(self)
	if snapshot.is_empty():
		return false
	_receive_snapshot(snapshot)
	return true


func _receive_snapshot(snapshot: Dictionary) -> void:
	session_id = snapshot["session_id"]
	revision = (snapshot["revision"] as String).to_int()
	_tokens.clear()
	for record: Dictionary in snapshot.get("tokens", []):
		_tokens.append(record.duplicate(true))
	_artwork = (snapshot.get("artwork", {}) as Dictionary).duplicate(true)
	_needs_sync = false


func _receive_update(snapshot: Dictionary) -> void:
	if _needs_sync or snapshot["session_id"] != session_id or snapshot["revision"] != str(revision + 1):
		_needs_sync = true
		_clear_public_artwork()
		return
	_receive_snapshot(snapshot)
