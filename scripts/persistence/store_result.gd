class_name AtlasStoreResult
extends RefCounted

var campaign: AtlasCampaign = null
var error: Error = OK
var message: String = ""
var recovered: bool = false
var source_path: String = ""


static func failure(code: Error, detail: String, path: String) -> AtlasStoreResult:
    var result: AtlasStoreResult = AtlasStoreResult.new()
    result.error = code
    result.message = detail
    result.source_path = path
    return result
