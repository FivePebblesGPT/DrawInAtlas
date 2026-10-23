class_name AtlasCampaignStore
extends RefCounted

const DEFAULT_PATH: String = "user://drawinatlas_campaign.json"


static func save_campaign(campaign: AtlasCampaign, path: String = DEFAULT_PATH) -> Error:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(campaign.to_dict(), "  "))
    file.close()
    return OK


static func load_campaign(path: String = DEFAULT_PATH) -> AtlasCampaign:
    if not FileAccess.file_exists(path):
        return null
    var raw := FileAccess.get_file_as_string(path)
    var value: Variant = JSON.parse_string(raw)
    if not value is Dictionary:
        return null
    return AtlasCampaign.from_dict(value)
