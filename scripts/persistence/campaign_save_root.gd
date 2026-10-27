class_name AtlasCampaignSaveRoot
extends Node

## Data-only scene root. The map registry is reconstructed from owned children.
const NATIVE_VERSION: int = 1

@export_storage var native_version: int = NATIVE_VERSION
@export_storage var semantic_digest: String = ""
@export_storage var campaign: AtlasCampaign
