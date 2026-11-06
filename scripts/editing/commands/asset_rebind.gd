class_name AtlasAssetRebind
extends AtlasEditCommand
## Published Object Editor Save As: create B + bind instance A as one command.
## Callbacks belong to the future T-060/T-062 asset registry, never Drawing.
## First publication MUST atomically persist B and bind A (or fail unchanged).

var before_context: DrawingHistoryContext
var after_context: DrawingHistoryContext
var instance_id: String = ""
var instance_generation: String = ""
var original_asset_id: String = ""
var variant_asset_id: String = ""
var lookup_instance: Callable
var asset_exists: Callable
var publish_and_rebind: Callable
var set_binding: Callable
var _applied: bool = false
var _published: bool = false


func _init(instance: String, generation: String, original: String, variant: String,
		before: DrawingHistoryContext, after: DrawingHistoryContext,
		lookup: Callable, asset_present: Callable, publish: Callable,
		rebind: Callable) -> void:
	instance_id = instance
	instance_generation = generation
	original_asset_id = original
	variant_asset_id = variant
	before_context = before.detached_copy() if before != null else null
	after_context = after.detached_copy() if after != null else null
	if before_context != null:
		map_id = before_context.map_id
		floor_id = before_context.floor_group_id
	lookup_instance = lookup
	asset_exists = asset_present
	publish_and_rebind = publish
	set_binding = rebind


func _binding_is(expected_asset: String) -> bool:
	if not lookup_instance.is_valid():
		return false
	var state: Variant = lookup_instance.call(instance_id)
	return state is Dictionary and state.get("generation", "") == instance_generation \
		and state.get("source_id", "") == expected_asset


func apply(_campaign: AtlasCampaign) -> bool:
	if _applied or instance_id.is_empty() or instance_generation.is_empty() \
			or original_asset_id.is_empty() or variant_asset_id.is_empty() \
			or original_asset_id == variant_asset_id or not _binding_is(original_asset_id) \
			or not asset_exists.is_valid():
		return false
	if not _published:
		if not publish_and_rebind.is_valid() \
				or not bool(publish_and_rebind.call(instance_id, instance_generation,
					original_asset_id, variant_asset_id)) \
				or not _binding_is(variant_asset_id) or not bool(asset_exists.call(variant_asset_id)):
			return false
		_published = true
	else:
		# Redo reuses exactly B. A deliberately deleted B must not be recreated.
		if not bool(asset_exists.call(variant_asset_id)) or not set_binding.is_valid() \
				or not bool(set_binding.call(instance_id, instance_generation,
					original_asset_id, variant_asset_id)):
			return false
	_applied = true
	return true


func revert(_campaign: AtlasCampaign) -> bool:
	if not _applied or not _binding_is(variant_asset_id) or not set_binding.is_valid() \
			or not bool(set_binding.call(instance_id, instance_generation,
				variant_asset_id, original_asset_id)):
		return false
	# Intentionally leave saved Variant B in its asset library.
	_applied = false
	return true


func published_variant() -> bool:
	return _published
