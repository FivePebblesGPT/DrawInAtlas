class_name AtlasTokenLayer
extends AtlasLayer
## Canonical ordered GM tabletop tokens. No automatic player visibility grant.

const MAX_TOKENS: int = 4096
@export_storage var tokens: Array[AtlasToken] = []


func _init(layer_id: String = "tokens", layer_name: String = "GM Tokens") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "TOKENS"


func token_by_id(token_id: String) -> AtlasToken:
	for token: AtlasToken in tokens:
		if token != null and token.id == token_id:
			return token
	return null


func to_dict() -> Dictionary:
	var result: Dictionary = super.to_dict()
	var items: Array[Dictionary] = []
	for token: AtlasToken in tokens:
		items.append(token.to_dict())
	result["tokens"] = items
	return result


static func valid_tokens(items: Array[AtlasToken]) -> bool:
	if items.size() > MAX_TOKENS:
		return false
	var seen: Dictionary[String, bool] = {}
	for item: AtlasToken in items:
		if item == null or not item.is_valid() or seen.has(item.id):
			return false
		seen[item.id] = true
	return true


static func clone_tokens(items: Array[AtlasToken]) -> Array[AtlasToken]:
	var result: Array[AtlasToken] = []
	for item: AtlasToken in items:
		result.append(item.copy())
	return result


static func same_tokens(first: Array[AtlasToken], second: Array[AtlasToken]) -> bool:
	if first.size() != second.size():
		return false
	for index: int in range(first.size()):
		if first[index] == null or second[index] == null \
				or first[index].to_dict() != second[index].to_dict():
			return false
	return true
