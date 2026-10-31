class_name AtlasPlayerProjection
extends RefCounted
## T-039: detached, deny-by-default artwork boundary for projector design review.
## Not wired to player windows or saved data: publish grants still need owner approval.
## A caller must supply an explicit set of entire-layer grants from a trusted
## authority. Editor `visible`, cache audience strings and layer names are NOT grants.

const BOARD_ID: String = "player-board"
const FLOOR_ID: String = "player-floor"
const MAX_GRANTED_LAYERS: int = 256


## Preferred boundary for renderers: the returned campaign has one sanitized map,
## no private document graph, links, placements or campaign metadata.
## Null is denial; callers MUST render a neutral blank frame, never GM content.
static func build_capture_input(document: AtlasMapDocument, floor_id: String,
		detail_level: int, granted_layer_ids: Array[String]) -> AtlasCampaign:
	var view: AtlasMapDocument = build_artwork_view(document, floor_id, detail_level, granted_layer_ids)
	if view == null:
		return null
	var result: AtlasCampaign = AtlasCampaign.new()
	result.display_name = "Player output"
	result.root_map_id = view.id
	result.maps.clear()
	result.links.clear()
	result.placements.clear()
	result.add_map(view)
	return result


## Construct an independent rendering document containing ONLY granted artwork
## from one floor and one authored LOD. Null means an invalid/stale grant; an
## empty grant list produces a deliberately blank board. Never fall back to the
## original map after a null result.
##
## This proof boundary grants whole layers, including every Objects-layer text
## and prop. It cannot safely express per-object or per-pixel/fog permissions;
## those require a later approved policy and representation (T-041/T-042).
static func build_artwork_view(document: AtlasMapDocument, floor_id: String,
		detail_level: int, granted_layer_ids: Array[String]) -> AtlasMapDocument:
	if document == null or document.grid == null or not document.grid.is_valid() \
			or detail_level < 0 or detail_level > AtlasLayer.MAX_DETAIL_LEVEL \
			or granted_layer_ids.size() > MAX_GRANTED_LAYERS:
		return null
	var source_floor: AtlasFloor = document.floor_by_id(floor_id)
	if source_floor == null:
		return null

	# Reject duplicate, missing or stale IDs rather than silently widening scope.
	var source_ids: Dictionary[String, bool] = {}
	for source: AtlasLayer in source_floor.layers:
		if source == null or source.id.is_empty() or source_ids.has(source.id):
			return null
		source_ids[source.id] = true
	var grants: Dictionary[String, bool] = {}
	for id: String in granted_layer_ids:
		if id.is_empty() or grants.has(id) or not source_ids.has(id):
			return null
		grants[id] = true

	var output: AtlasMapDocument = AtlasMapDocument.new(BOARD_ID, "Player board")
	output.kind = "REGION"
	output.tags.clear()
	output.floors.clear()
	output.default_floor_id = FLOOR_ID
	output.grid = AtlasGrid.new(document.grid.kind, document.grid.cell_size)
	output.grid.origin = document.grid.origin
	output.grid.rotation = document.grid.rotation
	# Measure and grid display are separate calibration/authorization decisions.
	output.grid.distance_per_cell = 1.0
	output.grid.distance_unit = "unit"
	output.grid.visible = false
	var player_floor: AtlasFloor = AtlasFloor.new()
	player_floor.id = FLOOR_ID
	player_floor.display_name = "Player floor"
	player_floor.layers.clear()

	# The source stack owns the compositing order, not user-supplied grant order.
	for source: AtlasLayer in source_floor.layers:
		if not grants.has(source.id):
			continue
		if not source.visible or source.opacity <= 0.0 or source.detail_level != detail_level:
			return null
		if not (source is AtlasRasterLayer or source is AtlasObjectsLayer):
			return null
		if source is AtlasRasterLayer:
			# Never expose a lazy source asset reference to the player renderer.
			for chunk: AtlasRasterChunk in (source as AtlasRasterLayer).chunks.values():
				if chunk == null or chunk.image == null:
					return null
		var copy: AtlasLayer = AtlasLayerCodec.clone(source)
		if copy == null:
			return null
		copy.id = "art-%d" % player_floor.layers.size()
		copy.display_name = "Artwork"
		copy.locked = true
		player_floor.layers.append(copy)

	output.floors.append(player_floor)
	return output
