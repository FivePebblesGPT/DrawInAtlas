class_name AtlasHostSession
extends RefCounted
## T-045: trusted, in-process GM collaboration proof. Only this host owns the
## mutable campaign and edit history. No socket, player authorization or
## arbitrary client-provided EditCommand/Resource deserialization is allowed.
## Viewer publications are explicit, host-filtered DTOs (T-046). No transport
## authentication or production publishing integration is implied.

const MAX_PEERS: int = 16
const MAX_REQUESTS_PER_PEER: int = 256
const MAX_PUBLIC_PNG_BYTES: int = 8388608
const MAX_PUBLIC_RASTER_PIXELS: int = 16777216

var session_id: String = ""
var revision: int = 0
var _campaign: AtlasCampaign
var _history: AtlasEditHistory
var _map_id: String = ""
var _floor_id: String = ""
var _layer_id: String = ""
var _map: AtlasMapDocument
var _floor: AtlasFloor
var _layer: AtlasTokenLayer
var _scope: AtlasEditScope
var _baseline: Dictionary = {}
var _document_baseline: Dictionary = {}
var _roles: Dictionary = {} # host-owned peer ID -> gm/player/spectator
var _publication: Dictionary = {} # viewer peer ID -> {grants, detail_level}
var _connections: Dictionary = {} # peer ID -> AtlasSessionClient
var _requests: Dictionary = {} # peer ID -> request ID -> original payload and response
var _invalidated: bool = false
var _own_history_change: bool = false


func _init(campaign: AtlasCampaign, history: AtlasEditHistory, identity: String,
		map_id: String, floor_id: String, layer_id: String, scope: AtlasEditScope = null) -> void:
	_campaign = campaign
	_history = history
	session_id = identity
	_map_id = map_id
	_floor_id = floor_id
	_layer_id = layer_id
	_scope = AtlasEditScope.new(scope.polygon, scope.enabled) if scope != null else AtlasEditScope.new()
	if campaign != null:
		_map = campaign.get_map(map_id)
		_floor = _map.floor_by_id(floor_id) if _map != null else null
		_layer = _floor.layer_by_id(layer_id) as AtlasTokenLayer if _floor != null else null
	if _layer != null:
		_baseline = _layer.to_dict().duplicate(true)
	if _map != null:
		_document_baseline = _map.to_dict().duplicate(true)
	if _history != null:
		_history.changed.connect(_on_history_changed)


func is_ready() -> bool:
	return _identity_valid(session_id) and _identity_valid(_map_id) \
		and _identity_valid(_floor_id) and _identity_valid(_layer_id) \
		and _history != null and _history.active_map_id == _map_id \
		and _map != null and _floor != null and _layer != null \
		and AtlasTokenLayer.valid_tokens(_layer.tokens) and not _invalidated


## Joining is a trusted local controller operation, NOT identity authentication.
## Callers never receive a host Campaign, Layer, or mutable Token Resource.
func join(peer_id: String) -> AtlasSessionClient:
	# Backward-compatible trusted GM entry point. NEVER expose this method to
	# unauthenticated transport clients: caller identity/roles are not verified.
	return join_as(peer_id, "gm")


## Called ONLY by the trusted local session controller, not from a client
## command. The host owns role/grants; client-supplied fields cannot upgrade it.
func join_as(peer_id: String, role: String, grants: Array[String] = [],
		detail_level: int = 0) -> AtlasSessionClient:
	if not is_ready() or not _identity_valid(peer_id) or _requests.has(peer_id) \
			or _connections.size() >= MAX_PEERS or not _source_unchanged():
		return null
	if role != "gm" and role != "player" and role != "spectator":
		return null
	if role == "gm" and (not grants.is_empty() or detail_level != 0):
		return null
	if role != "gm" and not _publication_valid(grants, detail_level):
		return null
	var client: AtlasSessionClient = AtlasSessionClient.new(self, peer_id)
	_roles[peer_id] = role
	if role != "gm":
		_publication[peer_id] = {"grants": grants.duplicate(), "detail_level": detail_level}
	_connections[peer_id] = client
	_requests[peer_id] = {}
	client._receive_snapshot(_snapshot_for(client))
	return client


func snapshot_for(client: AtlasSessionClient) -> Dictionary:
	if not _connected(client) or not _source_unchanged():
		return {}
	return _snapshot_for(client)


## Permission changes are host-owned policy events, not client edits. Revision
## increments so stale client commands cannot cross a publication change.
## Empty grants revoke all viewer image bytes, including frozen local mirrors.
func set_viewer_grants(peer_id: String, grants: Array[String], detail_level: int = 0) -> bool:
	if _roles.get(peer_id, "") != "player" and _roles.get(peer_id, "") != "spectator":
		return false
	if not _source_unchanged() or not _publication_valid(grants, detail_level):
		return false
	var previous: Dictionary = _publication[peer_id]
	if previous["grants"] == grants and previous["detail_level"] == detail_level:
		return true
	_publication[peer_id] = {"grants": grants.duplicate(), "detail_level": detail_level}
	revision += 1
	_broadcast()
	return true


## The client sends primitive wire-like dictionaries. The host constructs the
## command from *current* canonical tokens; a caller cannot provide a "before"
## snapshot, a Resource, a command instance or a changed target layer.
func receive(client: AtlasSessionClient, request: Dictionary) -> Dictionary:
	if not _connected(client):
		return _reply(false, "NOT_CONNECTED", "")
	if _roles.get(client.peer_id, "") != "gm":
		return _reply(false, "ROLE_FORBIDDEN", "")
	if not _source_unchanged():
		return _reply(false, "LOCAL_DIVERGENCE", "")
	var request_id: Variant = request.get("request_id")
	if not request_id is String or not _identity_valid(request_id):
		return _reply(false, "BAD_REQUEST", "")
	var seen: Dictionary = _requests[client.peer_id]
	if seen.has(request_id):
		var prior: Dictionary = seen[request_id]
		if prior["request"] != request:
			return _reply(false, "REQUEST_REUSE", request_id)
		return (prior["response"] as Dictionary).duplicate(true)
	if seen.size() >= MAX_REQUESTS_PER_PEER:
		return _reply(false, "REQUEST_LIMIT", request_id)
	var response: Dictionary = _accept(client, request)
	seen[request_id] = {"request": request.duplicate(true), "response": response.duplicate(true)}
	_requests[client.peer_id] = seen
	return response.duplicate(true)


func close() -> void:
	## GM mirrors retain detached token snapshots; player/spectator imagery is
	## cleared. No peer may submit or resync, and IDs cannot be recycled.
	_invalidate()
	_connections.clear()
	if _history != null and _history.changed.is_connected(_on_history_changed):
		_history.changed.disconnect(_on_history_changed)


func invalidate_for_local_edit() -> void:
	## An ordinary editor undo or mutation outside this host cannot be silently
	## folded into a live revision stream. Start a new session after such edits.
	_invalidate()


func _accept(client: AtlasSessionClient, request: Dictionary) -> Dictionary:
	var request_id: String = request["request_id"]
	if request.size() != 7 or not request.has("session_id") \
			or not request.has("peer_id") or not request.has("operation") \
			or not request.has("base_revision") or not request.has("token_id") \
			or not request.has("position"):
		return _reply(false, "BAD_REQUEST", request_id)
	if request["session_id"] != session_id or request["peer_id"] != client.peer_id:
		return _reply(false, "IDENTITY_MISMATCH", request_id)
	if request["operation"] != "token_move":
		return _reply(false, "UNKNOWN_OPERATION", request_id)
	var base: Variant = request["base_revision"]
	# JSON.parse_string converts numbers to floats. Encode revisions as decimal
	# strings to preserve exact equality, including values past 2^53.
	if not base is String or base != str(revision):
		return _reply(false, "STALE_REVISION", request_id)
	var token_id: Variant = request["token_id"]
	var point: Variant = request["position"]
	if not token_id is String or not _identity_valid(token_id) \
			or not point is Array or point.size() != 2:
		return _reply(false, "BAD_REQUEST", request_id)
	for coordinate: Variant in point:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
			return _reply(false, "BAD_REQUEST", request_id)
	var previous: AtlasToken = _layer.token_by_id(token_id)
	if previous == null:
		return _reply(false, "NOT_FOUND", request_id)
	var destination: Vector2 = Vector2(float(point[0]), float(point[1]))
	if not destination.is_finite():
		return _reply(false, "BAD_REQUEST", request_id)
	if previous.position == destination:
		return _reply(false, "UNCHANGED", request_id)
	var before: Array[AtlasToken] = AtlasTokenLayer.clone_tokens(_layer.tokens)
	var after: Array[AtlasToken] = AtlasTokenLayer.clone_tokens(before)
	for token: AtlasToken in after:
		if token.id == token_id:
			token.position = destination
			break
	var command: AtlasTokenEdit = AtlasTokenEdit.new(_map_id, _floor_id, _layer_id,
		before, after, _scope)
	_own_history_change = true
	var committed: bool = _history.execute(command)
	_own_history_change = false
	if not committed:
		return _reply(false, "EDIT_REJECTED", request_id)
	revision += 1
	_baseline = _layer.to_dict().duplicate(true)
	_document_baseline = _map.to_dict().duplicate(true)
	_broadcast()
	return _reply(true, "ACCEPTED", request_id)


func _on_history_changed() -> void:
	# Even an undo followed by redo to identical pixels changes local history;
	# reject it instead of silently reinterpreting the authoritative log.
	if not _own_history_change:
		_invalidate()


func _source_unchanged() -> bool:
	if _invalidated or not is_ready() or _campaign.get_map(_map_id) != _map \
			or _map.floor_by_id(_floor_id) != _floor \
			or _floor.layer_by_id(_layer_id) != _layer \
			or _layer.to_dict() != _baseline or _map.to_dict() != _document_baseline:
		_invalidate()
		return false
	return true


func _connected(client: AtlasSessionClient) -> bool:
	return client != null and _connections.get(client.peer_id) == client


func _broadcast() -> void:
	for recipient: AtlasSessionClient in _connections.values():
		recipient._receive_update(_snapshot_for(recipient))


func _snapshot_for(client: AtlasSessionClient) -> Dictionary:
	var response: Dictionary = {"session_id": session_id, "revision": str(revision)}
	if _roles.get(client.peer_id) == "gm":
		var serialized: Array[Dictionary] = []
		for token: AtlasToken in _layer.tokens:
			serialized.append(token.to_dict())
		response["tokens"] = serialized
	else:
		# Never send canonical tokens, maps, labels, fog commands or previews to
		# viewers. Even a spectator receives only the sanitized publication DTO.
		var policy: Dictionary = _publication[client.peer_id]
		response["artwork"] = _public_artwork(policy["grants"], policy["detail_level"])
	return response


func _publication_valid(grants: Array[String], detail_level: int) -> bool:
	if detail_level < 0 or detail_level > AtlasLayer.MAX_DETAIL_LEVEL:
		return false
	if grants.is_empty():
		return true
	# T-039 has not approved viewer text/objects or tokens; do not treat
	# even a trusted entire-Objects grant as permission to send private labels.
	for layer_id: String in grants:
		if not _floor.layer_by_id(layer_id) is AtlasRasterLayer:
			return false
	return not _public_artwork(grants, detail_level).is_empty()


## Transport-safe primitive document: the T-039 boundary sanitizes first,
## then each permitted raster chunk carries its own PNG bytes. A hash alone
## would be unsafe (and insufficient to render) without permissioned assets.
## Any failed filter/encoding/size budget returns an empty denial, not GM data.
func _public_artwork(grants: Array[String], detail_level: int) -> Dictionary:
	if grants.is_empty():
		return {}
	# Preflight decoded image work even when fog is disabled; PNG compression
	# can make very large flat-color images deceptively small on the wire.
	var decoded_pixels: int = 0
	for layer_id: String in grants:
		var raster: AtlasRasterLayer = _floor.layer_by_id(layer_id) as AtlasRasterLayer
		if raster == null:
			return {}
		for piece: AtlasRasterChunk in raster.chunks.values():
			if piece == null or not piece.is_valid(true):
				return {}
			decoded_pixels += piece.width * piece.height
			if decoded_pixels > MAX_PUBLIC_RASTER_PIXELS:
				return {}
	var sanitized: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(
		_map, _floor_id, detail_level, grants)
	if sanitized == null:
		return {}
	var payload: Dictionary = sanitized.to_dict()
	var floor_record: Dictionary = payload["floors"][0]
	var layer_records: Array = floor_record["layers"]
	var size_budget: int = 0
	for index: int in sanitized.floors[0].layers.size():
		var layer: AtlasLayer = sanitized.floors[0].layers[index]
		if layer is AtlasRasterLayer:
			var raster: AtlasRasterLayer = layer as AtlasRasterLayer
			var chunks: Array = layer_records[index]["chunks"]
			var keys: Array[String] = raster.chunks.keys()
			keys.sort()
			for chunk_index: int in keys.size():
				var piece: AtlasRasterChunk = raster.chunks[keys[chunk_index]]
				if piece == null or not piece.is_valid(true):
					return {}
				var encoded: PackedByteArray = piece.image.save_png_to_buffer()
				size_budget += encoded.size()
				if encoded.is_empty() or size_budget > MAX_PUBLIC_PNG_BYTES:
					return {}
				chunks[chunk_index]["png_base64"] = Marshalls.raw_to_base64(encoded)
	return payload


func _invalidate() -> void:
	_invalidated = true
	for recipient: AtlasSessionClient in _connections.values():
		if _roles.get(recipient.peer_id) != "gm":
			recipient._clear_public_artwork()


func _reply(allowed: bool, code: String, request_id: String) -> Dictionary:
	return {"ok": allowed, "code": code, "request_id": request_id,
		"session_id": session_id, "revision": str(revision)}


static func _identity_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for index: int in value.length():
		var char_code: int = value.unicode_at(index)
		if not (char_code >= 48 and char_code <= 57 \
				or char_code >= 65 and char_code <= 90 \
				or char_code >= 97 and char_code <= 122 \
				or char_code == 45 or char_code == 95):
			return false
	return true
