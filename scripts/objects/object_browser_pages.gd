class_name AtlasObjectBrowserPages
extends RefCounted
## Metadata-only navigation for large, published Atlas source libraries.
## Never opens source documents or authorizes placing one. That belongs to
## AtlasObjectLibrary and the guarded editor drop/open path.

const PAGE_SIZE: int = 64


static func select_page(sources: Array[Dictionary], query: String,
		requested_page: int, page_size: int = PAGE_SIZE) -> Dictionary:
	var needle: String = query.strip_edges().to_lower()
	var matches: Array[Dictionary] = []
	for source: Dictionary in sources:
		if needle.is_empty() or needle in String(source.get("name", "")).to_lower() or \
				needle in String(source.get("id", "")).to_lower():
			matches.append(source)
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: String = String(a.get("name", ""))
		var right: String = String(b.get("name", ""))
		var comparison: int = left.nocasecmp_to(right)
		return comparison < 0 if comparison != 0 else String(a.get("id", "")) < String(b.get("id", "")))
	var width: int = maxi(1, page_size)
	var total: int = matches.size()
	var page_count: int = maxi(1, ceili(float(total) / float(width)))
	var page: int = clampi(requested_page, 0, page_count - 1)
	var page_sources: Array[Dictionary] = []
	for index: int in range(page * width, mini(total, (page + 1) * width)):
		page_sources.append(matches[index].duplicate(true))
	return {"records": page_sources, "page": page, "pages": page_count,
		"total": total}
