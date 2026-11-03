class_name AtlasObjectChildGraph
extends RefCounted
## T-064: validate the portable registry's source-owned nested references.
## No recursive rendering occurs here; the legacy flat map instances stay intact.

const MAX_CHILDREN_PER_SOURCE: int = 64
const MAX_GRAPH_EDGES: int = 20000
const MAX_NESTING_DEPTH: int = 16


static func _identifier(value: Variant) -> bool:
	return value is String and value != "root" and DrawingDocument.valid_identifier(value)


static func _revision(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= 2147483647.0 \
		and floorf(float(value)) == float(value)


static func _child_valid(row: Dictionary) -> bool:
	if not _identifier(row.get("id")) or not _identifier(row.get("generation")) \
			or not _identifier(row.get("source_id")) or not row.get("visible") is bool \
			or not row.get("placeholder") is bool or not _revision(row.get("revision")) \
			or not row.get("transform") is Array or not row.get("metadata", {}) is Dictionary:
		return false
	var metadata: Dictionary = row.get("metadata", {})
	if metadata.size() > 128:
		return false
	for key: Variant in metadata:
		if not key is String or not (metadata[key] is bool or metadata[key] is String \
				or metadata[key] is int or metadata[key] is float) \
				or (metadata[key] is float and not is_finite(float(metadata[key]))):
			return false
	var transform: Array = row["transform"]
	if transform.size() != 6:
		return false
	for component: Variant in transform:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
	var basis: Transform2D = Transform2D(
		Vector2(float(transform[0]), float(transform[1])),
		Vector2(float(transform[2]), float(transform[3])),
		Vector2(float(transform[4]), float(transform[5])))
	return is_finite(basis.determinant()) and absf(basis.determinant()) > 0.00000001


## Missing published sources are kept as broken links for explicit NULL repair.
## Acyclicity is checked across every *available registry record*, not files.
static func validate(assets: Dictionary) -> DrawingResult:
	var indegree: Dictionary = {}
	var depths: Dictionary = {}
	var edges: Dictionary = {}
	var child_ids: Dictionary = {}
	var edge_count: int = 0
	for source_id: Variant in assets:
		if not _identifier(source_id) or not assets[source_id] is Dictionary:
			return DrawingResult.failure("CHILD_GRAPH", "Invalid parent source identity")
		indegree[source_id] = 0
		depths[source_id] = 0
		edges[source_id] = []
	for source_id: Variant in assets:
		var parent: Dictionary = assets[source_id]
		if not _revision(parent.get("children_revision", 0)):
			return DrawingResult.failure("CHILD_GRAPH", "Invalid nested-reference revision")
		var children: Variant = parent.get("children", [])
		if not children is Array or children.size() > MAX_CHILDREN_PER_SOURCE:
			return DrawingResult.failure("CHILD_GRAPH_LIMIT", "Too many nested children on a source")
		edge_count += children.size()
		if edge_count > MAX_GRAPH_EDGES:
			return DrawingResult.failure("CHILD_GRAPH_LIMIT", "Nested source graph is too large")
		for child: Variant in children:
			if not child is Dictionary or not _child_valid(child):
				return DrawingResult.failure("CHILD_GRAPH", "Malformed nested child reference")
			var child_id: String = str(child["id"])
			if child_ids.has(child_id):
				return DrawingResult.failure("CHILD_GRAPH", "Duplicate nested child identity")
			child_ids[child_id] = true
			var dependency: String = str(child["source_id"])
			if assets.has(dependency):
				(edges[source_id] as Array).append(dependency)
				indegree[dependency] = int(indegree[dependency]) + 1
	var ready: Array[String] = []
	for source_id: Variant in indegree:
		if int(indegree[source_id]) == 0:
			ready.append(str(source_id))
	ready.sort()
	var cursor: int = 0
	var processed: int = 0
	var maximum_depth: int = 0
	while cursor < ready.size():
		var source_id: String = ready[cursor]
		cursor += 1
		processed += 1
		for dependency: Variant in edges[source_id]:
			var dependency_id: String = str(dependency)
			depths[dependency_id] = maxi(int(depths[dependency_id]), int(depths[source_id]) + 1)
			maximum_depth = maxi(maximum_depth, int(depths[dependency_id]))
			if maximum_depth > MAX_NESTING_DEPTH:
				return DrawingResult.failure("CHILD_DEPTH", "Nested references exceed the safe depth budget")
			indegree[dependency_id] = int(indegree[dependency_id]) - 1
			if int(indegree[dependency_id]) == 0:
				ready.append(dependency_id)
	if processed != assets.size():
		return DrawingResult.failure("CHILD_CYCLE", "Nested Object source references must be acyclic")
	return DrawingResult.success({"edges": edge_count, "depth": maximum_depth})


## Transitive parents need refresh after a child source publishes a revision.
static func dependent_sources(assets: Dictionary, changed_source: String) -> Array[String]:
	var reverse: Dictionary = {}
	for parent_id: Variant in assets:
		for child: Variant in (assets[parent_id] as Dictionary).get("children", []):
			if not child is Dictionary:
				continue
			var source_id: String = str(child.get("source_id", ""))
			if not reverse.has(source_id):
				reverse[source_id] = []
			(reverse[source_id] as Array).append(str(parent_id))
	var seen: Dictionary = {changed_source: true}
	var queue: Array[String] = [changed_source]
	var result: Array[String] = []
	var index: int = 0
	while index < queue.size():
		var source_id: String = queue[index]
		index += 1
		for parent: Variant in reverse.get(source_id, []):
			var parent_id: String = str(parent)
			if not seen.has(parent_id):
				seen[parent_id] = true
				queue.append(parent_id)
				result.append(parent_id)
	result.sort()
	return result
