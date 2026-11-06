class_name DrawingResult
extends RefCounted
## Explicit failure/success transport: callers must not treat absent/corrupt tiles as blank.

var ok: bool = false
var code: String = ""
var message: String = ""
var value: Variant = null
var revision: int = -1
var regions: Array[DrawingDirtyRegion] = []
var delta: DrawingDelta = null


static func success(payload: Variant = null, at_revision: int = -1) -> DrawingResult:
	var result: DrawingResult = DrawingResult.new()
	result.ok = true
	result.value = payload
	result.revision = at_revision
	return result


static func failure(error_code: String, description: String) -> DrawingResult:
	var result: DrawingResult = DrawingResult.new()
	result.code = error_code
	result.message = description
	return result
